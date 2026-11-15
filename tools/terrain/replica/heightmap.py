"""Core and ring heightmaps, and the DEM agreement check.

Grids: row 0 = north (-z), col 0 = west (-x). The core heightmap has n = core_m / core_step_m + 1
samples per side; sample (i, j) is at x = -core_m/2 + j*step, z = -core_m/2 + i*step (2001 x 2001
at 1 m for x, z in [-1000, 1000]). Heights are absolute metres (Copernicus GLO-30, EGM2008).

Copernicus GLO-30 is a *surface* model: over rocks it measures rock tops. The ground surface is
built so that ground + rock tops reproduces the DEM at the 30 m block scale (no double counting):

  1. Bicubic (cubic B-spline, interpolating) upsample of a 30 m DEM grid to the core grid.
  2. Small-scale ground detail from the class map: a rise at ROCK edges (rock_edge_rise_m,
     fading over rock_edge_band_m), SAND smoothed by a sand_blur_m box blur, CHANNELs cut by
     channel_depth_per_width x their width, clamped to [channel_depth_min_m, channel_depth_max_m].
  3. Re-levelling against the DEM: per 30 m block, r = mean(max(ground, rock tops)) - mean(DEM);
     ground -= cubic-spline interpolation of r through the block centres; repeated until every
     |r| < level_tol_m. Rock tops ride on the ground (top = ground at centre + height), so a
     rock-covered block's ground sinks by the rock's share of the block mean. The correction is
     a smooth field (no seams at block edges).
  4. Ground under each site structure (gers) is flattened to its mean (feathered outside).
  5. Large masses (kind "mass", long axis >= large_mass_min_length_m, i.e. >= 2 DEM cells):
     the DEM resolves them, so their rock-top surface *is* the upsampled DEM inside the outline
     (mass_top_surface); the ground beneath is a harmonic (Laplace) fill from the ground on the
     outline's rim, clamped to <= that rock top. These samples are left out of step 3.

Footprints on the grid: a boulder covers the samples inside its length x width ellipse (rock-top
coverage); its base is the min ground over the samples of every 1 m cell its oriented
length x width rectangle touches (so a bilinear ground never pokes above the base). A mass
covers the samples inside its outline polygon (base: dilated by one sample).
"""
from __future__ import annotations

import math
import warnings

import numpy as np
from scipy import ndimage as ndi
from scipy.ndimage import map_coordinates
from scipy.sparse import coo_matrix
from scipy.sparse.linalg import spsolve

from .classify import CHANNEL, ROCK, SAND, STRUCTURE, TRACK
from .geo import LocalFrame
from .rocks import Rock
from .site import SiteConfig

DEM_STEP_M = 30.0

PARAMS = {
    # Agreement blocks (m): the DEM's resolution.
    "block_m": 30.0,
    # Re-levelling iterations stop once every block residual is below this (m).
    "level_tol_m": 0.02,
    "level_max_iter": 40,
    # A block with less than this fraction of its samples outside large masses is not
    # levelled (its residual is ~0 anyway: the rock top there is the DEM).
    "level_min_free_frac": 0.1,
    # Channel cut depth = this x channel width (m), clamped; channels are <= 4 m wide
    # (classify line_max_width_m), so the cut is 0.3-1.2 m in practice.
    "channel_depth_per_width": 0.3,
    "channel_depth_min_m": 0.3,
    "channel_depth_max_m": 1.5,
    # Window (m) over which a channel pixel looks for the channel's centre line (>= max width).
    "channel_width_window_m": 4.5,
    "sand_blur_m": 5.0,
    # Soil/scree bank at rock feet: rise at the rock edge, fading to 0 over the band (m).
    "rock_edge_rise_m": 0.5,
    "rock_edge_band_m": 3.0,
    # Masses at least this long (m, long axis; >= 2 DEM cells) take their rock top from the
    # DEM. A single flat `height` top over a long mass on a slope stands metres above the DEM
    # at its downhill end, and re-levelling would dig a pit under it (measured: -24 m).
    "large_mass_min_length_m": 60.0,
    # Ger pads: flat over radius diameter/2 + margin, blended back over the feather width.
    "structure_margin_m": 1.0,
    "structure_feather_m": 3.0,
}


# --- grid helpers ------------------------------------------------------------------------


def core_n(cfg: SiteConfig) -> int:
    return int(round(cfg.core_m / cfg.core_step_m)) + 1


def _half(cfg: SiteConfig) -> float:
    return cfg.core_m / 2.0


def _axis(cfg: SiteConfig) -> np.ndarray:
    return -_half(cfg) + np.arange(core_n(cfg), dtype=np.float64) * cfg.core_step_m


def _interp_matrix(n_src: int, u: np.ndarray) -> np.ndarray:
    """(len(u), n_src) matrix of 1-D interpolating cubic-spline weights at fractional indices u
    (edge mode 'nearest'). The 2-D spline is the tensor product: W_r @ a @ W_c.T."""
    eye = np.eye(n_src)
    return np.stack(
        [map_coordinates(eye[k], [u], order=3, mode="nearest") for k in range(n_src)], axis=1
    )


def core_dem30(cfg: SiteConfig, frame: LocalFrame, dems=None) -> np.ndarray:
    """The 30 m DEM grid used for the core: centred on the origin, two cells beyond the core."""
    from .rasters import dem_grid

    half = (math.ceil(_half(cfg) / DEM_STEP_M) + 2) * DEM_STEP_M
    return dem_grid(cfg, frame, half, DEM_STEP_M, dems)


def upsample_dem(dem30: np.ndarray, cfg: SiteConfig) -> np.ndarray:
    """Bicubic (cubic B-spline, through the samples) upsample of a centred 30 m DEM grid
    (row 0 north) to the core grid; float64."""
    n30 = dem30.shape[0]
    if dem30.shape != (n30, n30):
        raise ValueError(f"dem30 must be square, got {dem30.shape}")
    half30 = (n30 - 1) * DEM_STEP_M / 2.0
    if half30 < _half(cfg) + DEM_STEP_M:
        raise ValueError(f"dem30 half-extent {half30} m does not cover the core + one cell")
    w = _interp_matrix(n30, (_axis(cfg) + half30) / DEM_STEP_M)
    return w @ dem30.astype(np.float64) @ w.T


# Tie-break order for the categorical downsample: thin / linear and man-made classes first
# (a 2-px channel straddling two blocks must survive in both), then whichever class holds the
# block's first (north-west) pixel -- position-based, so no class is favoured on average.
TIE_PRIORITY = (STRUCTURE, CHANNEL, TRACK)


def block_mode(a: np.ndarray, f: int, priority: tuple[int, ...] = TIE_PRIORITY) -> np.ndarray:
    """Mode of each f x f block of categorical ids. Ties: the first class of `priority` among
    the tied, else the class of the block's north-west pixel if tied, else the lowest id."""
    h, w = a.shape
    if h % f or w % f:
        raise ValueError(f"shape {a.shape} not divisible by {f}")
    blocks = a.reshape(h // f, f, w // f, f)
    nw = blocks[:, 0, :, 0]
    ids = np.unique(a)
    scale = 2 * (len(priority) + 2)  # counts dominate; bonuses only break ties
    scores = []
    for k in ids:
        bonus = len(priority) + 1 - priority.index(k) if k in priority else 0
        scores.append((blocks == k).sum(axis=(1, 3)) * scale + bonus + (nw == k))
    return ids[np.argmax(np.stack(scores), axis=0)].astype(a.dtype)


def _class_factor(classes: np.ndarray, cfg: SiteConfig) -> tuple[int, float]:
    mpp = cfg.core_m / classes.shape[0]
    f = int(round(cfg.core_step_m / mpp))
    square = classes.shape[0] == classes.shape[1]
    if not square or f < 2 or f % 2 or abs(f * mpp - cfg.core_step_m) > 1e-9:
        raise ValueError(
            f"class map {classes.shape} must be square at core_step_m / (even integer)"
        )
    return f, mpp


def classes_at_samples(classes: np.ndarray, cfg: SiteConfig) -> np.ndarray:
    """Class id per core sample: mode of the f x f class pixels around it (edges padded)."""
    f, _ = _class_factor(classes, cfg)
    p = np.pad(classes, f // 2, mode="edge")
    return block_mode(p, f)


def _pixels_to_samples_mean(a: np.ndarray, f: int) -> np.ndarray:
    p = np.pad(a, f // 2, mode="edge")
    h = p.shape[0] // f
    return p.reshape(h, f, h, f).mean(axis=(1, 3))


def _bilinear(g: np.ndarray, x, z, cfg: SiteConfig) -> np.ndarray:
    s = cfg.core_step_m
    rows = (np.asarray(z, np.float64) + _half(cfg)) / s
    cols = (np.asarray(x, np.float64) + _half(cfg)) / s
    return map_coordinates(g.astype(np.float64, copy=False), [np.ravel(rows), np.ravel(cols)],
                           order=1, mode="nearest")


# --- footprints --------------------------------------------------------------------------


def is_large_mass(rock: Rock) -> bool:
    return (
        rock.kind == "mass"
        and bool(rock.outline)
        and rock.length >= PARAMS["large_mass_min_length_m"]
    )


def _bbox(cfg, x0, x1, z0, z1):
    s, h, n = cfg.core_step_m, _half(cfg), core_n(cfg)
    c0 = max(0, math.ceil((x0 + h) / s - 1e-9))
    c1 = min(n - 1, math.floor((x1 + h) / s + 1e-9))
    r0 = max(0, math.ceil((z0 + h) / s - 1e-9))
    r1 = min(n - 1, math.floor((z1 + h) / s + 1e-9))
    return r0, r1, c0, c1


def _nearest(rock: Rock, cfg: SiteConfig):
    s, h, n = cfg.core_step_m, _half(cfg), core_n(cfg)
    r = min(n - 1, max(0, int(round((rock.z + h) / s))))
    c = min(n - 1, max(0, int(round((rock.x + h) / s))))
    return np.array([r]), np.array([c])


def _axes(rock: Rock):
    yaw = math.radians(rock.yaw_deg)
    return (math.sin(yaw), -math.cos(yaw)), (math.cos(yaw), math.sin(yaw))  # long, short


def _box_samples(rock: Rock, cfg: SiteConfig, half_l: float, half_w: float, ellipse: bool):
    (ax, az), (bx, bz) = _axes(rock)
    ext = abs(ax) * half_l + abs(bx) * half_w, abs(az) * half_l + abs(bz) * half_w
    r0, r1, c0, c1 = _bbox(cfg, rock.x - ext[0], rock.x + ext[0], rock.z - ext[1], rock.z + ext[1])
    if r1 < r0 or c1 < c0:
        return _nearest(rock, cfg)
    s, h = cfg.core_step_m, _half(cfg)
    rr, cc = np.mgrid[r0 : r1 + 1, c0 : c1 + 1]
    dx = -h + cc * s - rock.x
    dz = -h + rr * s - rock.z
    u = dx * ax + dz * az
    v = dx * bx + dz * bz
    if ellipse:
        inside = (u / max(half_l, 1e-6)) ** 2 + (v / max(half_w, 1e-6)) ** 2 <= 1.0
    else:
        inside = (np.abs(u) <= half_l) & (np.abs(v) <= half_w)
    if not inside.any():
        return _nearest(rock, cfg)
    return rr[inside], cc[inside]


def _polygon_mask(outline, cfg: SiteConfig):
    """(r0, c0, bool mask) of the samples inside a closed polygon (even-odd rule)."""
    pts = np.asarray(outline, np.float64)
    r0, r1, c0, c1 = _bbox(cfg, pts[:, 0].min(), pts[:, 0].max(), pts[:, 1].min(), pts[:, 1].max())
    if r1 < r0 or c1 < c0:
        return r0, c0, np.zeros((0, 0), bool)
    s, h = cfg.core_step_m, _half(cfg)
    xs = -h + np.arange(c0, c1 + 1) * s
    zs = -h + np.arange(r0, r1 + 1) * s
    X, Z = np.meshgrid(xs, zs)
    inside = np.zeros(X.shape, bool)
    x0, z0 = pts[:, 0], pts[:, 1]
    x1, z1 = np.roll(x0, -1), np.roll(z0, -1)
    for a, b, c, d in zip(x0, z0, x1, z1):
        if b == d:
            continue
        crosses = (b > Z) != (d > Z)
        xc = a + (Z - b) * (c - a) / (d - b)
        inside ^= crosses & (X < xc)
    return r0, c0, inside


def _poly_samples(rock: Rock, cfg: SiteConfig, dilate: bool = False):
    r0, c0, m = _polygon_mask(rock.outline, cfg)
    if dilate and m.size:
        m = np.pad(m, 1)
        m = ndi.binary_dilation(m)
        r0, c0 = r0 - 1, c0 - 1
    rr, cc = np.nonzero(m)
    rr, cc = rr + r0, cc + c0
    n = core_n(cfg)
    ok = (rr >= 0) & (rr < n) & (cc >= 0) & (cc < n)
    if not ok.any():
        return _nearest(rock, cfg)
    return rr[ok], cc[ok]


def top_samples(rock: Rock, cfg: SiteConfig):
    """Samples covered by the rock's top: outline polygon (mass) or length x width ellipse."""
    if rock.kind == "mass" and rock.outline:
        return _poly_samples(rock, cfg)
    return _box_samples(rock, cfg, rock.length / 2.0, rock.width / 2.0, ellipse=True)


def base_samples(rock: Rock, cfg: SiteConfig):
    """Samples of every grid cell the footprint touches (base = min ground over them)."""
    if rock.kind == "mass" and rock.outline:
        return _poly_samples(rock, cfg, dilate=True)
    m = cfg.core_step_m * math.sqrt(2.0)
    return _box_samples(rock, cfg, rock.length / 2.0 + m, rock.width / 2.0 + m, ellipse=False)


def rock_base_y(rock: Rock, hm: np.ndarray, cfg: SiteConfig) -> float:
    """Min ground under the footprint (the rock is never floating, even on a slope)."""
    rr, cc = base_samples(rock, cfg)
    return float(hm[rr, cc].min())


def rock_top_y(rock: Rock, hm: np.ndarray, cfg: SiteConfig) -> float:
    """Ground (bilinear) at the rock centre + its height. Large masses' real top surface is
    mass_top_surface; this stays the single-number fallback for them."""
    return float(_bilinear(hm, rock.x, rock.z, cfg)[0]) + float(rock.height)


class _Tops:
    """Rock-top raster for the rocks that use their `height` (all but large masses)."""

    def __init__(self, rocks: list[Rock], cfg: SiteConfig) -> None:
        self.cfg = cfg
        self.n = core_n(cfg)
        small = [r for r in rocks if not is_large_mass(r)]
        idx, owner = [], []
        for k, r in enumerate(small):
            rr, cc = top_samples(r, cfg)
            idx.append(rr * self.n + cc)
            owner.append(np.full(rr.size, k, np.int64))
        self.idx = np.concatenate(idx) if idx else np.zeros(0, np.int64)
        self.owner = np.concatenate(owner) if owner else np.zeros(0, np.int64)
        self.x = np.array([r.x for r in small])
        self.z = np.array([r.z for r in small])
        self.h = np.array([r.height for r in small], np.float64)

    def raster(self, g: np.ndarray) -> np.ndarray:
        out = np.full(self.n * self.n, -np.inf)
        if self.idx.size:
            top = _bilinear(g, self.x, self.z, self.cfg) + self.h
            vals = top[self.owner]
            order = np.argsort(vals, kind="stable")  # highest written last: per-sample max
            out[self.idx[order]] = vals[order]
        return out.reshape(self.n, self.n)


def mass_top_surface(dem30: np.ndarray, rocks: list[Rock], cfg: SiteConfig,
                     up: np.ndarray | None = None) -> np.ndarray:
    """Rock-top surface (float32) of the large masses = upsampled DEM inside their outlines,
    NaN elsewhere (Ruling 15)."""
    if up is None:
        up = upsample_dem(dem30, cfg)
    out = np.full(up.shape, np.nan, np.float32)
    for r in rocks:
        if is_large_mass(r):
            rr, cc = _poly_samples(r, cfg)
            out[rr, cc] = up[rr, cc]
    return out


def surface(hm: np.ndarray, rocks: list[Rock], tops: np.ndarray, cfg: SiteConfig,
            _t: _Tops | None = None) -> np.ndarray:
    """max(ground, rock tops): what a surface model sees."""
    t = _t or _Tops(rocks, cfg)
    s = np.maximum(hm.astype(np.float64), t.raster(hm))
    return np.fmax(s, tops.astype(np.float64))


# --- blocks ------------------------------------------------------------------------------


def _blocks(cfg: SiteConfig) -> tuple[int, int, int]:
    """(samples per block, blocks per side, offset of the first block): centred blocks."""
    b = int(round(PARAMS["block_m"] / cfg.core_step_m))
    n = core_n(cfg)
    nb = n // b
    return b, nb, (n - nb * b) // 2


def _block_sums(a: np.ndarray, cfg: SiteConfig) -> np.ndarray:
    b, nb, o = _blocks(cfg)
    sub = a[o : o + nb * b, o : o + nb * b]
    return sub.reshape(nb, b, nb, b).sum(axis=(1, 3))


def block_residuals(hm, rocks, dem30, cfg, tops=None) -> np.ndarray:
    """Per 30 m block: mean(max(ground, rock tops)) - mean(DEM upsampled)."""
    up = upsample_dem(dem30, cfg)
    if tops is None:
        tops = mass_top_surface(dem30, rocks, cfg, up)
    s = surface(hm, rocks, tops, cfg)
    b = _blocks(cfg)[0]
    return _block_sums(s - up, cfg) / (b * b)


def dem_agreement(hm: np.ndarray, rocks: list[Rock], dem30: np.ndarray,
                  cfg: SiteConfig) -> tuple[float, float]:
    """(rms, max |.|) over the 30 m blocks of mean(max(ground, rock top in footprint)) - DEM."""
    r = block_residuals(hm, rocks, dem30, cfg)
    return float(np.sqrt(np.mean(r * r))), float(np.abs(r).max())


# Plan thresholds for every agreement figure (m).
AGREEMENT_RMS_MAX_M = 2.0
AGREEMENT_MAX_ABS_M = 6.0


def drift_check(hm: np.ndarray, rocks: list[Rock], dem30: np.ndarray, dem_native: np.ndarray,
                cfg: SiteConfig) -> dict:
    """Checks independent of the re-levelling (which makes dem_agreement ~0 by construction).

    dem_native: the native Copernicus posts sampled bilinearly on the core grid (no 30 m
    resampling, no bicubic). Returns, over the 30 m blocks:
      native_rms_m / native_max_m: mean(max(ground, rock tops)) - mean(native DEM);
      rock_free_rms_m / rock_free_max_m: mean(ground) - mean(native DEM) on blocks no rock
      footprint touches (there the ground alone must match the DEM: no drift).
    """
    b = _blocks(cfg)[0]
    up = upsample_dem(dem30, cfg)
    tops = mass_top_surface(dem30, rocks, cfg, up)
    t = _Tops(rocks, cfg)
    nat = dem_native.astype(np.float64)
    r = _block_sums(surface(hm, rocks, tops, cfg, t) - nat, cfg) / (b * b)
    covered = np.isfinite(t.raster(hm)) | np.isfinite(tops)
    free = _block_sums(covered.astype(np.float64), cfg) == 0
    g = (_block_sums(hm.astype(np.float64) - nat, cfg) / (b * b))[free]
    out = {
        "native_rms_m": float(np.sqrt(np.mean(r * r))),
        "native_max_m": float(np.abs(r).max()),
        "rock_free_blocks": int(free.sum()),
        "rock_free_rms_m": float(np.sqrt(np.mean(g * g))) if g.size else 0.0,
        "rock_free_max_m": float(np.abs(g).max()) if g.size else 0.0,
    }
    return out


def agreement_failures(stats: dict) -> list[str]:
    """Names of the figures in stats (keys *_rms_m / *_max_m) that exceed the plan thresholds."""
    bad = []
    for k, v in sorted(stats.items()):
        if k.endswith("_rms_m") and v > AGREEMENT_RMS_MAX_M:
            bad.append(f"{k} = {v:.3f} > {AGREEMENT_RMS_MAX_M}")
        if k.endswith("_max_m") and v > AGREEMENT_MAX_ABS_M:
            bad.append(f"{k} = {v:.3f} > {AGREEMENT_MAX_ABS_M}")
    return bad


# --- core heightmap ----------------------------------------------------------------------


def _ground_detail(g: np.ndarray, classes: np.ndarray, cfg: SiteConfig) -> np.ndarray:
    P = PARAMS
    s = cfg.core_step_m
    f, mpp = _class_factor(classes, cfg)
    cls = classes_at_samples(classes, cfg)
    # Rise at rock feet.
    rock = cls == ROCK
    if rock.any():
        d = ndi.distance_transform_edt(~rock) * s
        g = g + P["rock_edge_rise_m"] * np.clip(1.0 - d / P["rock_edge_band_m"], 0.0, 1.0)
    # Smooth sand (soft class weight so there is no step at the class border).
    k = max(1, int(round(P["sand_blur_m"] / s)))
    w = ndi.uniform_filter((cls == SAND).astype(np.float64), size=k, mode="nearest")
    if w.any():
        g = w * ndi.uniform_filter(g, size=k, mode="nearest") + (1.0 - w) * g
    # Channels: width from the class map (0.5 m), U-shaped cut.
    ch = classes == CHANNEL
    if ch.any():
        dt = ndi.distance_transform_edt(ch) * mpp  # edge pixel: mpp
        win = int(round(P["channel_width_window_m"] / mpp)) | 1
        half_w = ndi.maximum_filter(dt, size=win)
        width = 2.0 * half_w
        depth = np.clip(P["channel_depth_per_width"] * width, P["channel_depth_min_m"],
                        P["channel_depth_max_m"])
        cut = np.where(ch, depth * np.sqrt(np.clip(dt / np.maximum(half_w, mpp), 0, 1)), 0.0)
        g = g - _pixels_to_samples_mean(cut, f)
    return g


def _level(g, up, t: _Tops, free: np.ndarray, cfg: SiteConfig) -> tuple[np.ndarray, float]:
    """Re-level ground against the DEM per block (smooth spline correction); residuals are
    measured on the `free` samples only (large masses excluded). Returns (ground, final max
    |block residual|); warns if level_max_iter is hit before level_tol_m."""
    P = PARAMS
    b, nb, o = _blocks(cfg)
    n = core_n(cfg)
    w = _interp_matrix(nb, (np.arange(n) - o - (b - 1) / 2.0) / b)
    cnt = _block_sums(free.astype(np.float64), cfg)
    ok = cnt >= P["level_min_free_frac"] * b * b
    def residual(g):
        s = np.maximum(g, t.raster(g))
        return np.where(ok, _block_sums(np.where(free, s - up, 0.0), cfg) / np.maximum(cnt, 1), 0.0)

    res = residual(g)
    for _ in range(P["level_max_iter"]):
        if np.abs(res).max() < P["level_tol_m"]:
            return g, float(np.abs(res).max())
        g = g - w @ res @ w.T
        res = residual(g)
    worst = float(np.abs(res).max())
    if worst >= P["level_tol_m"]:
        warnings.warn(
            f"re-levelling hit {P['level_max_iter']} iterations without converging: "
            f"max block residual {worst:.3f} m (tol {P['level_tol_m']} m)",
            stacklevel=2,
        )
    return g, worst


def _flatten_structures(g: np.ndarray, cfg: SiteConfig) -> np.ndarray:
    P = PARAMS
    if not cfg.structures:
        return g
    ax = _axis(cfg)
    for st in cfg.structures:
        r0 = float(st["diameter_m"]) / 2.0 + P["structure_margin_m"]
        fe = P["structure_feather_m"]
        x, z = float(st["x"]), float(st["z"])
        rows = np.nonzero(np.abs(ax - z) <= r0 + fe)[0]
        cols = np.nonzero(np.abs(ax - x) <= r0 + fe)[0]
        if rows.size == 0 or cols.size == 0:
            continue
        sl = (slice(rows[0], rows[-1] + 1), slice(cols[0], cols[-1] + 1))
        d = np.hypot(ax[sl[1]][None, :] - x, ax[sl[0]][:, None] - z)
        sub = g[sl]
        level = float(sub[d <= r0].mean()) if (d <= r0).any() else float(sub.mean())
        wgt = np.clip((r0 + fe - d) / fe, 0.0, 1.0)
        g[sl] = wgt * level + (1.0 - wgt) * sub
    return g


def _harmonic_fill(g: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """g with the masked samples replaced by the harmonic (Laplace) interpolation of the
    unmasked samples around them (4-neighbour stencil, zero-flux at the grid edge)."""
    g = g.copy()
    lab, nlab = ndi.label(mask)
    n0, n1 = g.shape
    for k, sl in enumerate(ndi.find_objects(lab), start=1):
        r0, r1 = max(0, sl[0].start - 1), min(n0, sl[0].stop + 1)
        c0, c1 = max(0, sl[1].start - 1), min(n1, sl[1].stop + 1)
        m = lab[r0:r1, c0:c1] == k
        sub = g[r0:r1, c0:c1]
        num = -np.ones(m.shape, np.int64)
        rr, cc = np.nonzero(m)
        num[rr, cc] = np.arange(rr.size)
        rows, cols, vals = [], [], []
        rhs = np.zeros(rr.size)
        deg = np.zeros(rr.size)
        for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            r2, c2 = rr + dr, cc + dc
            inside = (r2 >= 0) & (r2 < m.shape[0]) & (c2 >= 0) & (c2 < m.shape[1])
            deg += inside
            r2i, c2i = r2[inside], c2[inside]
            idx = np.nonzero(inside)[0]
            nb = num[r2i, c2i]
            unk = nb >= 0
            rows.append(idx[unk])
            cols.append(nb[unk])
            vals.append(-np.ones(unk.sum()))
            rhs[idx[~unk]] += sub[r2i[~unk], c2i[~unk]]
        rows.append(np.arange(rr.size))
        cols.append(np.arange(rr.size))
        vals.append(deg)
        a = coo_matrix(
            (np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))),
            shape=(rr.size, rr.size),
        ).tocsr()
        sub[rr, cc] = spsolve(a, rhs)
    return g


def core_heightmap(dem30: np.ndarray, classes: np.ndarray, rocks: list[Rock],
                   cfg: SiteConfig) -> np.ndarray:
    """Ground heightmap (float32, n x n, absolute metres); see the module doc for the steps."""
    up = upsample_dem(dem30, cfg)
    g = _ground_detail(up.copy(), classes, cfg)
    large = np.zeros(up.shape, bool)
    for r in rocks:
        if is_large_mass(r):
            rr, cc = _poly_samples(r, cfg)
            large[rr, cc] = True
    g, _ = _level(g, up, _Tops(rocks, cfg), ~large, cfg)
    g = _flatten_structures(g, cfg)
    if large.any():
        g = _harmonic_fill(g, large)
        g[large] = np.minimum(g[large], up[large])
    return g.astype(np.float32)


# --- ring --------------------------------------------------------------------------------


def ring_heightmap(cfg: SiteConfig, frame: LocalFrame, dems=None) -> np.ndarray:
    """DEM-only ring: centred square at ring_step_m, the largest odd sample count within ring_m
    (20 km at 30 m -> 667 x 667 over +-9990 m)."""
    from .rasters import dem_grid

    k = int(math.floor(cfg.ring_m / 2.0 / cfg.ring_step_m + 1e-9))
    return dem_grid(cfg, frame, k * cfg.ring_step_m, cfg.ring_step_m, dems).astype(np.float32)
