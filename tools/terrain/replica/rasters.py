"""Rasters in the local frame: DEM sampling and the 0.5 m ortho mosaic.

Orientation everywhere: row 0 = north (-Z), col 0 = west (-X); the local frame
is +x east, +z south (see geo.LocalFrame).
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import tifffile
from PIL import Image
from scipy.ndimage import map_coordinates

from .geo import LocalFrame
from .site import SiteConfig

NODATA = -32767.0
TILE_PX = 256

_GT_RASTER_AREA = 1
_GT_RASTER_POINT = 2


class _DemTile:
    def __init__(self, path: Path) -> None:
        with tifffile.TiffFile(path) as tf:
            page = tf.pages[0]
            tags = page.geotiff_tags
            data = page.asarray()
        if data.ndim != 2:
            raise ValueError(f"{path}: expected a single-band DEM, got shape {data.shape}")
        try:
            sx, sy = tags["ModelPixelScale"][:2]
            i, j, _, lon_t, lat_t, _ = tags["ModelTiepoint"][:6]
        except KeyError as exc:
            raise ValueError(f"{path}: missing GeoTIFF tag {exc}") from exc
        raster_type = tags.get("GTRasterTypeGeoKey", _GT_RASTER_AREA)
        if raster_type not in (_GT_RASTER_AREA, _GT_RASTER_POINT):
            raise ValueError(f"{path}: unsupported GTRasterTypeGeoKey {raster_type}")
        self.data = data.astype(np.float32, copy=False)
        self.step_lon = float(sx)
        self.step_lat = float(sy)
        # Location of the *centre* of sample (0, 0). PixelIsArea: the tiepoint is the pixel's
        # outer corner, so the centre is half a pixel inside; PixelIsPoint: tiepoint is the sample.
        half = 0.5 if raster_type == _GT_RASTER_AREA else 0.0
        self.lon0 = float(lon_t) - float(i) * self.step_lon + half * self.step_lon
        self.lat0 = float(lat_t) + float(j) * self.step_lat - half * self.step_lat
        self.path = path

    def frac_index(self, lat, lon):
        """Fractional (row, col) of lat/lon in sample units (row grows south)."""
        return (self.lat0 - lat) / self.step_lat, (lon - self.lon0) / self.step_lon


class DemMosaic:
    """One or more GeoTIFF DEM tiles (EPSG:4326) with bilinear sampling."""

    def __init__(self, tiles: list[_DemTile]) -> None:
        self.tiles = tiles

    def sample(self, lat, lon) -> np.ndarray:
        """Bilinear elevation (float32) at lat/lon (broadcast arrays).

        Raises ValueError (naming lat/lon) outside coverage or if any of the four
        neighbouring samples is no-data (-32767) or NaN. Within half a pixel of a
        tile edge the edge sample is used (no cross-tile blending).
        """
        lat_a, lon_a = np.broadcast_arrays(
            np.asarray(lat, dtype=np.float64), np.asarray(lon, dtype=np.float64)
        )
        out = np.full(lat_a.shape, np.nan, dtype=np.float32)
        todo = np.ones(lat_a.shape, dtype=bool)
        for t in self.tiles:
            row, col = t.frac_index(lat_a, lon_a)
            h, w = t.data.shape
            inside = todo & (row >= -0.5) & (row <= h - 0.5) & (col >= -0.5) & (col <= w - 0.5)
            if not inside.any():
                continue
            r = np.clip(row[inside], 0.0, h - 1.0)
            c = np.clip(col[inside], 0.0, w - 1.0)
            r0 = np.clip(np.floor(r).astype(np.intp), 0, max(h - 2, 0))
            c0 = np.clip(np.floor(c).astype(np.intp), 0, max(w - 2, 0))
            r1 = np.minimum(r0 + 1, h - 1)
            c1 = np.minimum(c0 + 1, w - 1)
            fr = (r - r0).astype(np.float32)
            fc = (c - c0).astype(np.float32)
            corners = [t.data[r0, c0], t.data[r0, c1], t.data[r1, c0], t.data[r1, c1]]
            bad = np.zeros(r.shape, dtype=bool)
            for v in corners:
                bad |= ~np.isfinite(v) | (v == NODATA)
            if bad.any():
                k = int(np.flatnonzero(bad)[0])
                la = lat_a[inside][k]
                lo = lon_a[inside][k]
                raise ValueError(f"DEM no-data at lat={la:.6f} lon={lo:.6f} ({t.path.name})")
            top = corners[0] * (1 - fc) + corners[1] * fc
            bot = corners[2] * (1 - fc) + corners[3] * fc
            out[inside] = top * (1 - fr) + bot * fr
            todo &= ~inside
        if todo.any():
            k = int(np.flatnonzero(todo)[0])
            raise ValueError(
                f"DEM does not cover lat={lat_a.ravel()[k]:.6f} lon={lon_a.ravel()[k]:.6f}"
            )
        return out


def read_dem(paths: list[Path]) -> DemMosaic:
    if not paths:
        raise ValueError("read_dem: no DEM files given")
    return DemMosaic([_DemTile(Path(p)) for p in paths])


def _no_download(url: str) -> bytes:
    raise RuntimeError(f"cache miss, refusing to download from rasters: {url}")


def dem_grid(
    cfg: SiteConfig,
    frame: LocalFrame,
    half_extent_m: float,
    step_m: float,
    dems: DemMosaic | None = None,
) -> np.ndarray:
    """Elevations (float32, shape (n, n)) on a square metric grid about the frame origin.

    Sample (row i, col j) is at x = -half + j*step (east), z = -half + i*step (south),
    so row 0 is north and col 0 is west. n = 2*half/step + 1. `dems` defaults to the
    cached Copernicus tiles for the site (never downloads).
    """
    if dems is None:
        from .fetch import fetch_dem

        dems = read_dem(fetch_dem(cfg, downloader=_no_download))
    n = int(round(2.0 * half_extent_m / step_m)) + 1
    axis = -half_extent_m + np.arange(n, dtype=np.float64) * step_m
    x, z = np.meshgrid(axis, axis)  # x varies along columns, z along rows
    lat, lon = frame.to_latlon(x, z)
    return dems.sample(lat, lon).astype(np.float32)


def build_ortho(cfg: SiteConfig, frame: LocalFrame, tiles) -> np.ndarray:
    """Ortho (H, W, 3) uint8 over the core at cfg.ortho_m_per_px; row 0 north, col 0 west.

    `tiles` is the list of (tx, ty, path) from fetch_imagery. Every output pixel
    centre is mapped lat/lon -> web-mercator pixel at cfg.imagery_zoom and sampled
    bilinearly. A required tile that is absent raises ValueError (never black).
    """
    z = cfg.imagery_zoom
    n = int(round(cfg.core_m / cfg.ortho_m_per_px))
    half = cfg.core_m / 2.0
    axis = -half + (np.arange(n, dtype=np.float64) + 0.5) * cfg.ortho_m_per_px
    x, zz = np.meshgrid(axis, axis)
    lat, lon = frame.to_latlon(x, zz)
    n_tiles = 2.0**z
    px = (lon + 180.0) / 360.0 * n_tiles * TILE_PX
    py = (1.0 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2.0 * n_tiles * TILE_PX
    # Pixel k covers [k, k+1) with its centre at k+0.5; bilinear touches centres within 1 px.
    tx_lo = int(np.floor((px.min() - 0.5) / TILE_PX))
    tx_hi = int(np.floor((px.max() + 0.5) / TILE_PX))
    ty_lo = int(np.floor((py.min() - 0.5) / TILE_PX))
    ty_hi = int(np.floor((py.max() + 0.5) / TILE_PX))
    have = {(tx, ty): p for tx, ty, p in tiles}
    missing = [
        (tx, ty)
        for ty in range(ty_lo, ty_hi + 1)
        for tx in range(tx_lo, tx_hi + 1)
        if (tx, ty) not in have
    ]
    if missing:
        raise ValueError(f"ortho: missing imagery tiles at z{z}: {missing[:10]}")
    nx, ny = tx_hi - tx_lo + 1, ty_hi - ty_lo + 1
    mosaic = np.zeros((ny * TILE_PX, nx * TILE_PX, 3), dtype=np.uint8)
    for ty in range(ty_lo, ty_hi + 1):
        for tx in range(tx_lo, tx_hi + 1):
            with Image.open(have[(tx, ty)]) as im:
                arr = np.asarray(im.convert("RGB"))
            if arr.shape != (TILE_PX, TILE_PX, 3):
                raise ValueError(f"ortho: tile {tx},{ty} is {arr.shape}, expected 256x256")
            y0, x0 = (ty - ty_lo) * TILE_PX, (tx - tx_lo) * TILE_PX
            mosaic[y0 : y0 + TILE_PX, x0 : x0 + TILE_PX] = arr
    rows = py - ty_lo * TILE_PX - 0.5
    cols = px - tx_lo * TILE_PX - 0.5
    out = np.empty((n, n, 3), dtype=np.uint8)
    for ch in range(3):
        v = map_coordinates(
            mosaic[:, :, ch].astype(np.float32), [rows, cols], order=1, mode="nearest"
        )
        out[:, :, ch] = np.clip(np.rint(v), 0, 255).astype(np.uint8)
    return out


def write_ortho(cfg: SiteConfig, frame: LocalFrame, tiles) -> Path:
    """Build the ortho and write build/ortho.png (local-only imagery; never commit)."""
    img = build_ortho(cfg, frame, tiles)
    path = cfg.build_dir / "ortho.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img).save(path)
    return path
