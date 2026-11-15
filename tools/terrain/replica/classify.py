"""Surface class map from the ortho: colour + local texture + shadow adjacency + line features.

One uint8 class id per ortho pixel (row 0 north, col 0 west). Rules are fixed numbers in
PARAMS (lengths in metres, converted with cfg.ortho_m_per_px); hand fixes go in the
override PNG (edits/classes_override.png), which always wins.
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

from .site import SiteConfig
from .sun import Sun, sun_from_site

UNKNOWN = 0
ROCK = 1
SAND = 2
GRASS = 3
SCRUB = 4
CHANNEL = 5
TRACK = 6
STRUCTURE = 7

CLASS_IDS = {
    "unknown": UNKNOWN, "rock": ROCK, "sand": SAND, "grass": GRASS,
    "scrub": SCRUB, "channel": CHANNEL, "track": TRACK, "structure": STRUCTURE,
}

# Debug-overlay colours (RGB) per class id.
CLASS_COLOURS = {
    UNKNOWN: (0, 0, 0), ROCK: (230, 40, 40), SAND: (250, 220, 120), GRASS: (140, 200, 60),
    SCRUB: (20, 110, 40), CHANNEL: (40, 120, 255), TRACK: (255, 255, 255),
    STRUCTURE: (255, 0, 255),
}

PARAMS = {
    # Colour: warmth = (R - B) / L. Bare sand ~0.33, dry grass ~0.13-0.20, scrub/rock < 0.
    "sand_warmth_min": 0.25,
    # Brightness (mean RGB 0-255, 5 px mean) below which non-sand ground is scrub, not grass.
    "scrub_lum_max": 82.0,
    # Shadow: smoothed luminance below shadow_lum_max, or below shadow_rel_max x local mean.
    "shadow_smooth_m": 0.5,
    "shadow_lum_max": 58.0,
    "shadow_rel_max": 0.62,
    "shadow_min_area_m2": 1.5,
    "local_mean_m": 40.0,
    # Rock seeds, either:
    #  (a) grey-green (warmth < rock_warmth_max), bright and coarse: mean5 + 2 * std9 >= score;
    #      measured scrub ~67 + 2*8 = 83, granite ~85 + 2*12 = 109;
    #  (b) lit, not sand, textured, brighter than the neighbourhood (rock_lit_rel_min x
    #      local mean), with a cast shadow on the anti-sun side within rock_shadow_reach_m.
    "rock_warmth_max": 0.05,
    "rock_lum_min": 78.0,
    "rock_score_min": 105.0,
    "rock_lit_rel_min": 1.05,
    "rock_lit_texture_min": 6.0,
    "rock_shadow_reach_m": 3.0,
    # Seeds grow (up to rock_grow_m) into connected not-sand pixels that are either
    # not-dark and textured, or clearly brighter than the neighbourhood (smooth lit slabs).
    "rock_grow_m": 3.0,
    "rock_grow_rel_min": 0.9,
    "rock_grow_texture_min": 6.0,
    "rock_grow_bright_rel_min": 1.15,
    # Non-sand holes enclosed by rock up to this size are rock (slab tops, cracks).
    "rock_hole_max_m2": 30.0,
    "rock_min_area_m2": 4.0,
    # Lines (channels dark, tracks light) only on smooth, warm open ground.
    "line_context_m": 20.0,
    "line_context_warmth_min": 0.12,
    # ... where at most this fraction of the context window is rock or scrub, and at most
    # line_context_textured_max of it has std9 above line_texture_px (measured: rocky
    # slopes ~0.95, speckled stony grass ~0.85, grass with channels ~0.6, sand ~0).
    "line_context_rough_max": 0.3,
    "line_texture_px": 5.0,
    "line_context_textured_max": 0.75,
    # Oriented line detector: along-line mean vs. parallel flanks (luminance difference).
    "channel_depth_min": 10.0,
    "track_height_min": 8.0,
    "line_max_width_m": 4.0,
    "channel_min_length_m": 12.0,
    "line_segment_m": 8.0,
    "track_min_length_m": 30.0,
    # Shadowed ground takes the class found beyond the shadow's far end (up to this far).
    "shadow_fill_reach_m": 30.0,
}


def _px(metres: float, m_per_px: float) -> int:
    return max(1, int(round(metres / m_per_px)))


def _disk(r: int) -> np.ndarray:
    yy, xx = np.mgrid[-r : r + 1, -r : r + 1]
    return xx * xx + yy * yy <= r * r


def _shift(a: np.ndarray, dr: int, dc: int, fill) -> np.ndarray:
    """out[r, c] = a[r + dr, c + dc] (fill outside)."""
    out = np.full_like(a, fill)
    h, w = a.shape
    rs, re = max(0, -dr), min(h, h - dr)
    cs, ce = max(0, -dc), min(w, w - dc)
    if rs < re and cs < ce:
        out[rs:re, cs:ce] = a[rs + dr : re + dr, cs + dc : ce + dc]
    return out


def _remove_small(mask: np.ndarray, min_px: int) -> np.ndarray:
    lab, n = ndi.label(mask)
    if n == 0:
        return mask
    sizes = np.bincount(lab.ravel())
    keep = sizes >= min_px
    keep[0] = False
    return keep[lab]


def _long_components(mask: np.ndarray, min_len_px: float) -> np.ndarray:
    """Keep components whose bounding-box diagonal is at least min_len_px."""
    lab, n = ndi.label(mask, structure=np.ones((3, 3)))
    if n == 0:
        return mask
    keep = np.zeros(n + 1, bool)
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        if sl is None:
            continue
        h = sl[0].stop - sl[0].start
        w = sl[1].stop - sl[1].start
        keep[i] = math.hypot(h, w) >= min_len_px
    return keep[lab]


def _line_responses(
    lum: np.ndarray, half_len: int, offset: int, n_orient: int = 12
) -> tuple[np.ndarray, np.ndarray]:
    """Oriented line detector. For each of n_orient directions, the mean luminance along a
    centred segment (2*half_len+1 px) is compared with the two parallel segments `offset` px
    to either side. Returns (dark, light): max over directions of
    min(flanks) - line (dark lines) and line - max(flanks) (light lines). Speckle averages out."""
    pad = half_len + offset + 1
    lum = np.pad(lum, pad, mode="edge")
    dark = np.full(lum.shape, -np.inf, np.float32)
    light = np.full(lum.shape, -np.inf, np.float32)
    for k in range(n_orient):
        th = math.pi * k / n_orient
        sr, sc = math.sin(th), math.cos(th)
        line = np.zeros(lum.shape, np.float32)
        for t in range(-half_len, half_len + 1):
            line += _shift(lum, int(round(t * sr)), int(round(t * sc)), 0)
        line /= 2 * half_len + 1
        # Perpendicular to (sr, sc) is (sc, -sr) in (row, col).
        pr, pc = int(round(offset * sc)), int(round(-offset * sr))
        side_a = _shift(line, pr, pc, np.nan)
        side_b = _shift(line, -pr, -pc, np.nan)
        lo = np.fmin(side_a, side_b)
        hi = np.fmax(side_a, side_b)
        np.fmax(dark, lo - line, out=dark)
        np.fmax(light, line - hi, out=light)
    crop = (slice(pad, -pad), slice(pad, -pad))
    return (
        np.nan_to_num(dark[crop], nan=0.0, neginf=0.0),
        np.nan_to_num(light[crop], nan=0.0, neginf=0.0),
    )


def _thin_lines(mask: np.ndarray, max_w: int, min_len: float) -> np.ndarray:
    """Parts of mask no wider than max_w px, in components at least min_len px long."""
    wide = ndi.binary_opening(mask, structure=_disk(max(1, max_w // 2 + 1)))
    thin = mask & ~ndi.binary_dilation(wide, iterations=1)
    return _long_components(thin, min_len)


def _shadow_steps(sun: Sun, reach_px: int) -> list[tuple[int, int]]:
    """(dr, dc) pixel offsets from 1..reach_px along the shadow direction (row down = south)."""
    dx, dz = sun.shadow_dir_xz()
    steps = []
    for t in range(1, reach_px + 1):
        s = (int(round(t * dz)), int(round(t * dx)))
        if s != (0, 0) and (not steps or steps[-1] != s):
            steps.append(s)
    return steps


def _shadow_from_lum(lum_s: np.ndarray, local_mean: np.ndarray, mpp: float) -> np.ndarray:
    """Shadows: dark in absolute terms or relative to the neighbourhood, not speckle."""
    P = PARAMS
    shadow = (lum_s < P["shadow_lum_max"]) | (lum_s < P["shadow_rel_max"] * local_mean)
    return _remove_small(shadow, int(P["shadow_min_area_m2"] / (mpp * mpp)))


def shadow_mask(ortho: np.ndarray, cfg: SiteConfig) -> np.ndarray:
    """Bool mask of cast/self shadow pixels, exactly as classify() detects them."""
    P = PARAMS
    mpp = cfg.ortho_m_per_px
    lum = np.asarray(ortho, dtype=np.float32)[..., :3].mean(axis=2)
    local_mean = ndi.uniform_filter(lum, _px(P["local_mean_m"], mpp) | 1)
    lum_s = ndi.gaussian_filter(lum, P["shadow_smooth_m"] / mpp)
    return _shadow_from_lum(lum_s, local_mean, mpp)


def classify(ortho: np.ndarray, cfg: SiteConfig, sun: Sun | None = None) -> np.ndarray:
    """Class id per ortho pixel (uint8, same H x W as ortho)."""
    P = PARAMS
    mpp = cfg.ortho_m_per_px
    sun = sun or sun_from_site(cfg)
    img = np.asarray(ortho, dtype=np.float32)[..., :3]
    r, b = img[..., 0], img[..., 2]
    lum = img.mean(axis=2)
    warmth = (r - b) / np.maximum(lum, 1.0)

    # Brightness (5 px mean) and coarse texture (std-dev in a 9 px window).
    mean5 = ndi.uniform_filter(lum, 5)
    mean9 = ndi.uniform_filter(lum, 9)
    std9 = np.sqrt(np.maximum(ndi.uniform_filter(lum * lum, 9) - mean9 * mean9, 0.0))
    warmth_s = ndi.uniform_filter(warmth, 3)
    local_mean = ndi.uniform_filter(lum, _px(P["local_mean_m"], mpp) | 1)
    lum_s = ndi.gaussian_filter(lum, P["shadow_smooth_m"] / mpp)
    shadow = _shadow_from_lum(lum_s, local_mean, mpp)

    # Base classes: warm = sand; otherwise dark = scrub, lighter = grass.
    classes = np.where(mean5 < P["scrub_lum_max"], SCRUB, GRASS).astype(np.uint8)
    sand = warmth_s >= P["sand_warmth_min"]
    classes[sand] = SAND

    # Rock seeds (see PARAMS), then bounded growth into similar connected pixels.
    behind = np.zeros_like(shadow)
    for dr, dc in _shadow_steps(sun, _px(P["rock_shadow_reach_m"], mpp)):
        behind |= _shift(shadow, dr, dc, False)
    lit = ~shadow & (mean5 >= P["rock_lum_min"])
    score = mean5 + 2.0 * std9
    seed_grey = lit & (warmth_s < P["rock_warmth_max"]) & (score >= P["rock_score_min"])
    seed_cast = (
        lit & ~sand & behind
        & (mean5 >= P["rock_lit_rel_min"] * local_mean)
        & (std9 >= P["rock_lit_texture_min"])
    )
    grow_ok = (
        lit & ~sand
        & (mean5 >= P["rock_grow_rel_min"] * local_mean)
        & (
            (std9 >= P["rock_grow_texture_min"])
            | (mean5 >= P["rock_grow_bright_rel_min"] * local_mean)
        )
    )
    seeds = ndi.binary_opening(seed_grey | seed_cast, structure=_disk(1))
    rock = ndi.binary_dilation(
        seeds, iterations=_px(P["rock_grow_m"], mpp), mask=grow_ok | seeds
    ) | seeds
    rock = ndi.binary_closing(rock, structure=_disk(2))
    rock = ndi.binary_opening(rock, structure=_disk(1)) & ~shadow
    rock = _remove_small(rock, int(P["rock_min_area_m2"] / (mpp * mpp)))
    holes = ndi.binary_fill_holes(rock) & ~rock
    small_holes = holes & ~_remove_small(holes, int(P["rock_hole_max_m2"] / (mpp * mpp)) + 1)
    rock |= small_holes & ~sand
    classes[rock] = ROCK

    # Thin dark lines (channels) and long light lines (tracks) on warm open ground.
    win = _px(P["line_context_m"], mpp) | 1
    open_ground = (
        (ndi.uniform_filter(warmth, win) >= P["line_context_warmth_min"])
        & (
            ndi.uniform_filter(((classes == ROCK) | (classes == SCRUB)).astype(np.float32), win)
            <= P["line_context_rough_max"]
        )
        & (
            ndi.uniform_filter((std9 > P["line_texture_px"]).astype(np.float32), win)
            <= P["line_context_textured_max"]
        )
        & ~rock
    )
    max_w = _px(P["line_max_width_m"], mpp)
    dark, light = _line_responses(
        lum_s, _px(P["line_segment_m"] / 2.0, mpp), max_w // 2 + 1
    )
    channel = _thin_lines(
        open_ground & (dark >= P["channel_depth_min"]), max_w, P["channel_min_length_m"] / mpp
    )
    track = _thin_lines(
        open_ground & (light >= P["track_height_min"]), max_w, P["track_min_length_m"] / mpp
    )
    classes[channel] = CHANNEL
    classes[track & ~channel] = TRACK

    # Ground under cast shadows: the class just beyond the shadow's far end.
    fill = shadow & ~channel
    if fill.any():
        todo = fill.copy()
        for dr, dc in _shadow_steps(sun, _px(P["shadow_fill_reach_m"], mpp)):
            src_shadow = _shift(fill, dr, dc, True)
            src = _shift(classes, dr, dc, UNKNOWN)
            take = todo & ~src_shadow & (src != UNKNOWN)
            classes[take] = src[take]
            todo &= ~take
            if not todo.any():
                break
        if todo.any():
            # Fallback: nearest non-shadow pixel.
            _, (ir, ic) = ndi.distance_transform_edt(fill, return_indices=True)
            classes[todo] = classes[ir[todo], ic[todo]]
    return classes


def apply_overrides(classes: np.ndarray, png_path: Path) -> np.ndarray:
    """Copy of classes where every non-zero override pixel (palette index = class id) wins."""
    out = np.array(classes, dtype=np.uint8, copy=True)
    png_path = Path(png_path)
    if not png_path.exists():
        return out
    with Image.open(png_path) as im:
        if im.mode not in ("P", "L"):
            raise ValueError(f"override {png_path} must be palette or 8-bit grey, got {im.mode}")
        ov = np.asarray(im)
    if ov.shape != out.shape:
        raise ValueError(f"override size {ov.shape} != class map size {out.shape}")
    mask = ov != 0
    out[mask] = ov[mask]
    return out


def debug_overlay(ortho: np.ndarray, classes: np.ndarray, alpha: float = 0.45) -> np.ndarray:
    """Ortho blended with class colours (local-only: contains imagery)."""
    lut = np.zeros((256, 3), np.float32)
    for cid, col in CLASS_COLOURS.items():
        lut[cid] = col
    base = np.asarray(ortho, np.float32)[..., :3]
    out = (1.0 - alpha) * base + alpha * lut[classes]
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def write_classes(cfg: SiteConfig) -> tuple[Path, Path]:
    """Classify build/ortho.png, apply edits/classes_override.png, write build/classes_full.png
    (class ids, committed) and build/classes_debug.png (imagery overlay, local-only)."""
    with Image.open(cfg.build_dir / "ortho.png") as im:
        ortho = np.asarray(im.convert("RGB"))
    classes = apply_overrides(classify(ortho, cfg), cfg.edits_dir / "classes_override.png")
    full = cfg.build_dir / "classes_full.png"
    debug = cfg.build_dir / "classes_debug.png"
    Image.fromarray(classes, mode="L").save(full, optimize=True)
    Image.fromarray(debug_overlay(ortho, classes)).save(debug)
    return full, debug


def class_fractions(classes: np.ndarray) -> dict[str, float]:
    counts = np.bincount(classes.ravel(), minlength=256)
    total = float(classes.size)
    return {name: counts[cid] / total for name, cid in CLASS_IDS.items()}
