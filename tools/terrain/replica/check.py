"""`check`: does the Godot replica line up with the surface map it was built from?

Godot's `--capture-topdown` (scripts/replica/replica_capture.gd) renders the core straight down,
orthographic, at the class map's 0.5 m/px into build/topdown.png: the ground flat per class and
every rock / fill-piece mesh in one unlit colour, CAPTURE_ROCK_RGB (grass, scrub, trees, scree,
stones and gers hidden). So the rendered rock mask is exact, not a threshold guess, and it is
compared with the ROCK class of build/classes_full.png (0.5 m, Ruling 4):

- IoU of the two masks, both against every ROCK pixel and against the ROCK components of
  rock-list size (footprint >= rocks.PARAMS min_footprint_m; Ruling 29: specks are rule fill);
- the share of the mass outlines (rocks_placed.json) the rendered rock covers;
- per traced rock (a ROCK component at least MIN_ROCK_M across): the shift, within SEARCH_M,
  that best overlays it on the rendered mask (ties -> the smallest shift), i.e. how far its
  centroid moved. Reported as median length and as mean signed dx (east +) / dz (south +), so a
  frame or axis bug shows as a consistent direction.

Pass: rock-list-size IoU >= IOU_MIN and median offset <= OFFSET_MAX_M (plan Task 11).
Results go to stdout and build/check.json. With the (local-only) build/ortho.png present it also writes
build/check_side_debug.png (ortho | topdown) and build/check_overlay_debug.png; *_debug.png are
gitignored because they contain imagery (licence rule).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy import signal

from .classify import ROCK
from .rocks import PARAMS as ROCK_PARAMS
from .rocks import _footprint, _rock_from_dict, footprint_mask

# Unlit colour of every rock / fill mesh in the capture (Godot ReplicaCapture.ROCK_COLOR).
CAPTURE_ROCK_RGB = (255, 0, 255)
COLOUR_TOL = 24
IOU_MIN = 0.7
OFFSET_MAX_M = 2.0
MIN_ROCK_M = 3.0
SEARCH_M = 8.0


def topdown_rock_mask(rgb: np.ndarray, tol: int = COLOUR_TOL) -> np.ndarray:
    """Pixels of a capture drawn in CAPTURE_ROCK_RGB (within `tol` per channel)."""
    diff = np.abs(rgb[..., :3].astype(np.int16) - np.array(CAPTURE_ROCK_RGB, np.int16))
    return np.all(diff <= tol, axis=-1)


def footprint_m(mask: np.ndarray, m_per_px: float) -> float:
    """sqrt(length x width) of a pixel set along its principal axes: the size rock detection
    compares with min_footprint_m (rocks._footprint)."""
    rows, cols = np.nonzero(mask)
    _, _, length, width, _ = _footprint(rows, cols, m_per_px, 0.0, 0.0)
    return float(np.sqrt(length * width))


def _iou(a: np.ndarray, b: np.ndarray) -> float:
    union = int((a | b).sum())
    return float((a & b).sum()) / union if union else 1.0


def outline_coverage(rocks: list[dict], got: np.ndarray, m_per_px: float) -> float:
    """Share of the area inside the mass outlines (rocks_placed.json entries) that `got` covers
    (Ruling 28); the mask is centred on the origin, row 0 north."""
    inside = np.zeros(got.shape, bool)
    for d in rocks:
        if d.get("kind") == "mass" and d.get("outline"):
            r0, c0, m = footprint_mask(_rock_from_dict(d), got.shape, m_per_px)
            if m.size:
                inside[r0 : r0 + m.shape[0], c0 : c0 + m.shape[1]] |= m
    return float((inside & got).sum()) / max(1, int(inside.sum()))


def compare(ref: np.ndarray, got: np.ndarray, m_per_px: float, min_size_m: float = MIN_ROCK_M,
            search_m: float = SEARCH_M) -> dict:
    """IoU of two rock masks (row 0 north, column 0 west) and the offset of each traced rock of
    `ref` (a component >= min_size_m across, 8-connected) onto `got`.

    Two IoUs (Ruling 29): `iou` against every ref pixel, and `iou_rocklist` against the ref
    components of rock-list size (footprint_m >= the detection minimum min_footprint_m);
    smaller specks are rule-fill territory by design."""
    ref = np.asarray(ref, bool)
    got = np.asarray(got, bool)
    if ref.shape != got.shape:
        raise ValueError(f"mask shapes differ: {ref.shape} vs {got.shape}")
    iou = _iou(ref, got)
    labels, _ = ndi.label(ref, structure=np.ones((3, 3), bool))
    min_fp = float(ROCK_PARAMS["min_footprint_m"])
    keep = np.zeros(labels.max() + 1, bool)
    for k, sl in enumerate(ndi.find_objects(labels), 1):
        comp = labels[sl] == k
        # Principal-axis extents are at most the box diagonal: skip the obvious specks fast.
        if max(comp.shape) * m_per_px * 1.5 >= min_fp and footprint_m(comp, m_per_px) >= min_fp:
            keep[k] = True
    rocklist = keep[labels]
    r = int(round(search_m / m_per_px))
    padded = np.pad(got, r).astype(np.float32)
    shifts = np.mgrid[-r:r + 1, -r:r + 1]
    norm = np.hypot(shifts[0], shifts[1])
    dx, dz = [], []
    rocks = 0
    at_edge = 0
    for k, sl in enumerate(ndi.find_objects(labels), 1):
        h = sl[0].stop - sl[0].start
        w = sl[1].stop - sl[1].start
        if max(h, w) * m_per_px < min_size_m:
            continue
        rocks += 1
        comp = (labels[sl] == k).astype(np.float32)
        window = padded[sl[0].start:sl[0].stop + 2 * r, sl[1].start:sl[1].stop + 2 * r]
        score = np.rint(signal.correlate(window, comp, mode="valid"))
        best = score.max()
        if best < 1:
            continue  # nothing rendered near it
        cand = np.where(score == best, norm, np.inf)
        a, b = np.unravel_index(int(np.argmin(cand)), cand.shape)
        if max(abs(a - r), abs(b - r)) == r:
            at_edge += 1
        dz.append((a - r) * m_per_px)
        dx.append((b - r) * m_per_px)
    dx_a = np.array(dx)
    dz_a = np.array(dz)
    off = np.hypot(dx_a, dz_a)
    matched = len(dx)
    return {
        "iou": round(iou, 4),
        "iou_rocklist": round(_iou(rocklist, got), 4),
        "rocklist_px": int(rocklist.sum()),
        "ref_px": int(ref.sum()),
        "got_px": int(got.sum()),
        "rocks": rocks,
        "matched": matched,
        "at_search_edge": at_edge,
        # None (JSON null) when nothing matched: json.dumps would write NaN, which is not JSON.
        "median_offset_m": float(np.median(off)) if matched else None,
        "p90_offset_m": float(np.percentile(off, 90)) if matched else None,
        "mean_dx_m": round(float(dx_a.mean()), 3) if matched else None,
        "mean_dz_m": round(float(dz_a.mean()), 3) if matched else None,
        "min_rock_m": min_size_m,
        "search_m": search_m,
    }


def _debug_images(build: Path, topdown: np.ndarray, ref: np.ndarray, got: np.ndarray) -> list[Path]:
    """ortho | topdown side by side, and the ortho with ROCK class (red) / rendered rock (cyan)
    edges, both at half size. Local only: they contain imagery."""
    ortho_path = build / "ortho.png"
    if not ortho_path.exists():
        return []
    with Image.open(ortho_path) as im:
        ortho = np.asarray(im.convert("RGB"))
    if ortho.shape[:2] != topdown.shape[:2]:
        return []
    half = (ortho.shape[1] // 2, ortho.shape[0] // 2)
    side = Image.new("RGB", (half[0] * 2, half[1]))
    side.paste(Image.fromarray(ortho).resize(half, Image.BILINEAR), (0, 0))
    side.paste(Image.fromarray(topdown[..., :3]).resize(half, Image.NEAREST), (half[0], 0))
    out = [build / "check_side_debug.png", build / "check_overlay_debug.png"]
    side.save(out[0])
    over = ortho.copy()
    over[ref & ~ndi.binary_erosion(ref)] = (255, 40, 40)
    over[got & ~ndi.binary_erosion(got)] = (0, 255, 255)
    Image.fromarray(over).save(out[1])
    return out


def check_site(site_dir: Path) -> int:
    build = Path(site_dir) / "build"
    paths = {"classes": build / "classes_full.png", "topdown": build / "topdown.png"}
    for name, p in paths.items():
        if not p.exists():
            hint = ("run Godot with `-- --capture-topdown --quit` on the site scene"
                    if name == "topdown" else f"run `python -I -m replica build {site_dir}`")
            print(f"replica check: missing {p}; {hint}", file=sys.stderr)
            return 1
    with Image.open(paths["classes"]) as im:
        classes = np.asarray(im)
    with Image.open(paths["topdown"]) as im:
        topdown = np.asarray(im.convert("RGB"))
    if classes.shape != topdown.shape[:2]:
        print(f"replica check: topdown {topdown.shape[:2]} != classes_full {classes.shape}",
              file=sys.stderr)
        return 1
    # classes_full covers the core square (manifest core.size_m); without a manifest assume the
    # pipeline's 0.5 m class map.
    mpp = 0.5
    manifest = build / "manifest.json"
    if manifest.exists():
        size_m = float(json.loads(manifest.read_text(encoding="utf-8"))["core"]["size_m"])
        mpp = size_m / classes.shape[1]
    ref = classes == ROCK
    got = topdown_rock_mask(topdown)
    res = compare(ref, got, mpp)
    res["m_per_px"] = mpp
    placed = build / "rocks_placed.json"
    if placed.exists():
        rocks = json.loads(placed.read_text(encoding="utf-8"))["rocks"]
        res["mass_outline_coverage"] = round(outline_coverage(rocks, got, mpp), 4)
    # Ruling 29: the threshold applies to the rock-list-size IoU.
    res["pass"] = bool(res["iou_rocklist"] >= IOU_MIN and res["median_offset_m"] is not None
                       and res["median_offset_m"] <= OFFSET_MAX_M)
    (build / "check.json").write_text(json.dumps(res, indent=1), encoding="utf-8")
    print(
        f"rock mask IoU vs rock-list-size ROCK {res['iou_rocklist']:.3f} (min {IOU_MIN}; "
        f"{res['rocklist_px']} px), vs all ROCK {res['iou']:.3f} ({res['ref_px']} px); "
        f"rendered {res['got_px']} px"
    )
    if "mass_outline_coverage" in res:
        print(f"mass outlines covered by rendered rock: {res['mass_outline_coverage']:.3f}")
    def m(key: str, sign: str = "") -> str:
        return "n/a" if res[key] is None else f"{res[key]:{sign}.2f}"

    print(
        f"traced rocks >= {MIN_ROCK_M:g} m: {res['rocks']}, matched {res['matched']}; offset "
        f"median {m('median_offset_m')} m (max {OFFSET_MAX_M}), p90 "
        f"{m('p90_offset_m')} m, mean dx {m('mean_dx_m', '+')} / dz "
        f"{m('mean_dz_m', '+')} m, {res['at_search_edge']} at the {SEARCH_M:g} m search edge"
    )
    for p in _debug_images(build, topdown, ref, got):
        print(f"wrote {p} (local only: contains imagery)")
    print("PASS" if res["pass"] else "FAIL")
    return 0 if res["pass"] else 1
