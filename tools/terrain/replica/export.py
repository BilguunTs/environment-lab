"""Writers for build/: heightmaps (.r32), the 1 m class map, placed rocks, scatter, grass
density, manifest.

.r32 = raw little-endian float32, row-major (row 0 north / -z, col 0 west / -x), no header.
Committed: classes.png, rocks_placed.json, grass_density.png, scatter.json (gitignored when
over 5 MB: it is deterministic from the committed inputs). rocks.json = merge(detected, edits)
is written by rocks.write_site_rocks only, never here (Ruling 5). Local-only (gitignored):
*.r32, manifest.json, *_debug.png.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

from .classify import CLASS_IDS
from .heightmap import block_mode
from .rocks import Rock, write_rocks
from .scatter import Instance, scatter_doc, type_counts
from .site import SiteConfig


def write_r32(path: Path, a: np.ndarray) -> None:
    np.ascontiguousarray(a, dtype="<f4").tofile(path)


def classes_1m(classes: np.ndarray, cfg: SiteConfig) -> np.ndarray:
    """Class map at 1 m (core_step_m) by block mode -- ids are categorical, never averaged."""
    mpp = cfg.core_m / classes.shape[0]
    f = int(round(cfg.core_step_m / mpp))
    return block_mode(classes, f) if f > 1 else np.asarray(classes, np.uint8)


def _grid(file: str, n: int, step: float, extra: dict | None = None) -> dict:
    half = (n - 1) * step / 2.0
    d = {"file": file, "n": n, "step_m": step, "size_m": (n - 1) * step,
         "origin_x": -half, "origin_z": -half}
    d.update(extra or {})
    return d


def export_site(cfg: SiteConfig, core: np.ndarray, ring: np.ndarray, classes: np.ndarray,
                rocks: list[Rock], scatter: list[Instance], mass_tops: np.ndarray | None = None,
                stats: dict | None = None, placed: list[Rock] | None = None,
                grass: np.ndarray | None = None) -> None:
    """Write build/{core,ring,mass_tops}.r32, classes.png (1 m), scatter.json (columnar, Ruling
    21), rocks_placed.json (Ruling 19) and grass_density.png when given, and manifest.json.
    `rocks` (the build/rocks.json list) is only counted. base_elevation = floor(min core
    ground), so every exported core height is >= it."""
    b = cfg.build_dir
    b.mkdir(parents=True, exist_ok=True)
    n = core.shape[0]
    if core.shape != (n, n) or ring.shape != (ring.shape[0], ring.shape[0]):
        raise ValueError(f"heightmaps must be square: core {core.shape}, ring {ring.shape}")
    if mass_tops is None:
        mass_tops = np.full(core.shape, np.nan, np.float32)
    if mass_tops.shape != core.shape:
        raise ValueError(f"mass_tops {mass_tops.shape} != core {core.shape}")
    write_r32(b / "core.r32", core)
    write_r32(b / "ring.r32", ring)
    write_r32(b / "mass_tops.r32", mass_tops)
    cls = classes_1m(classes, cfg)
    Image.fromarray(cls, mode="L").save(b / "classes.png", optimize=True)
    (b / "scatter.json").write_text(json.dumps(scatter_doc(scatter), separators=(",", ":"))
                                    + "\n", encoding="utf-8")
    if placed is not None:
        write_rocks(b / "rocks_placed.json", placed)
    if grass is not None:
        if grass.shape != core.shape or grass.dtype != np.uint8:
            raise ValueError(f"grass density {grass.shape} {grass.dtype} != core grid uint8")
        Image.fromarray(grass, mode="L").save(b / "grass_density.png", optimize=True)
    base_elevation = float(math.floor(float(np.nanmin(core))))
    half = cfg.core_m / 2.0
    manifest = {
        "version": 1,
        "name": cfg.name,
        "lat": cfg.lat,
        "lon": cfg.lon,
        "units": "metres; 1 Godot unit = 1 m; heights absolute (Copernicus GLO-30, EGM2008)",
        "frame": "+x east, +z south (north = -z), origin at lat/lon",
        "base_elevation": base_elevation,
        "base_elevation_def": "floor(min core ground); every core height >= base_elevation",
        "grid": {
            "format": "raw little-endian float32, row-major, no header",
            "row0": "north (-z)",
            "col0": "west (-x)",
            "sample": "(i, j) at x = origin_x + j * step_m, z = origin_z + i * step_m",
        },
        "core": _grid("core.r32", n, cfg.core_step_m),
        "ring": _grid("ring.r32", ring.shape[0], cfg.ring_step_m,
                      {"note": "DEM only; its centre lies under the core"}),
        "mass_tops": _grid("mass_tops.r32", n, cfg.core_step_m,
                           {"nodata": "NaN", "note": "rock-top surface of masses >= 60 m long "
                            "(DEM inside the outline); NaN elsewhere"}),
        "classes": {
            "file": "classes.png", "n": int(cls.shape[0]), "m_per_px": cfg.core_m / cls.shape[0],
            "pixel": f"(r, c) covers x in [{-half} + c, {-half} + c + 1), z likewise with r",
            "ids": dict(CLASS_IDS),
        },
        "rocks": {"file": "rocks.json", "count": len(rocks)},
        "scatter": {
            "file": "scatter.json", "count": len(scatter), "counts": type_counts(scatter),
            "format": "columnar: rows of [index into types, x, z, y, yaw_deg, l, h, w]; "
                      "metres, rounded to 0.01; yaw clockwise from north; base = min ground "
                      "under the l x w footprint (heightmap.rock_base_y) + y; y > 0: stacked "
                      "fill piece resting on the one below (Ruling 22)",
        },
        "sun": cfg.sun,
        "structures": cfg.structures,
    }
    if placed is not None:
        manifest["rocks_placed"] = {
            "file": "rocks_placed.json", "count": len(placed),
            "note": "rocks.json minus boulders / small masses centred inside a large mass "
                    "(Ruling 19): the list to place; masses are packed by scatter fill_*",
        }
    if grass is not None:
        manifest["grass_density"] = _grid("grass_density.png", n, cfg.core_step_m, {
            "format": "8-bit grey, 0-255 = 0-1 relative grass density, one pixel per core "
                      "sample (row 0 north)"})
    if stats:
        manifest["stats"] = stats
    (b / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")


def hillshade(hm: np.ndarray, step: float, azimuth_deg: float = 315.0,
              elevation_deg: float = 45.0) -> np.ndarray:
    """uint8 hillshade (row 0 north) for eyeballing a heightmap."""
    dzdr, dzdc = np.gradient(hm.astype(np.float64), step)
    # Surface normal in (x east, y up, z south): (-dh/dx, 1, -dh/dz).
    nx, nz = -dzdc, -dzdr
    norm = np.sqrt(nx * nx + nz * nz + 1.0)
    az, el = math.radians(azimuth_deg), math.radians(elevation_deg)
    lx, ly, lz = math.sin(az) * math.cos(el), math.sin(el), -math.cos(az) * math.cos(el)
    shade = (nx * lx + ly + nz * lz) / norm
    return np.clip(np.rint(255.0 * np.clip(shade, 0.0, 1.0)), 0, 255).astype(np.uint8)


def write_hillshade_debug(cfg: SiteConfig, hm: np.ndarray,
                          name: str = "core_hillshade_debug.png") -> Path:
    path = cfg.build_dir / name
    Image.fromarray(hillshade(hm, cfg.core_step_m), mode="L").save(path)
    return path
