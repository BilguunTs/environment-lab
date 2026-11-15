"""Download and cache Copernicus GLO-30 DEM tiles and Esri z17 imagery tiles.

Cache contents are untrusted input and local-only (imagery must never be
committed or shipped; see the licence rule).
"""
from __future__ import annotations

import io
import math
import os
import urllib.request
from pathlib import Path
from typing import Callable

import numpy as np
from PIL import Image

from .geo import LocalFrame, tile_xy
from .site import SiteConfig

USER_AGENT = "terrain-replica"
IMAGERY_MARGIN_M = 50.0
DEM_URL = (
    "https://copernicus-dem-30m.s3.amazonaws.com/{n}/{n}.tif"
)
IMAGERY_URL = (
    "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
)
PLACEHOLDER_MAX_BYTES = 4096
PLACEHOLDER_MAX_STD = 6.0

Downloader = Callable[[str], bytes]


class FetchError(Exception):
    pass


def http_download(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def dem_tile_names(lat_min: float, lat_max: float, lon_min: float, lon_max: float) -> list[str]:
    """Names of every 1-degree Copernicus tile touched by the lat/lon box."""
    names = []
    for la in range(math.floor(lat_min), math.floor(lat_max) + 1):
        for lo in range(math.floor(lon_min), math.floor(lon_max) + 1):
            ns = "N" if la >= 0 else "S"
            ew = "E" if lo >= 0 else "W"
            names.append(
                f"Copernicus_DSM_COG_10_{ns}{abs(la):02d}_00_{ew}{abs(lo):03d}_00_DEM"
            )
    return names


def is_placeholder(jpeg_bytes: bytes) -> bool:
    """True for Esri's 'no data at this zoom' tile: small AND near-uniform pixels."""
    if len(jpeg_bytes) >= PLACEHOLDER_MAX_BYTES:
        return False
    try:
        with Image.open(io.BytesIO(jpeg_bytes)) as im:
            arr = np.asarray(im.convert("RGB"), dtype=np.float64)
    except Exception:
        return False
    return float(arr.std(axis=(0, 1)).max()) < PLACEHOLDER_MAX_STD


TIFF_MAGICS = (b"II*\x00", b"MM\x00*", b"II+\x00", b"MM\x00+")
DEM_MIN_BYTES = 1024


def _check_tiff(data: bytes, name: str) -> None:
    if len(data) < DEM_MIN_BYTES or not data.startswith(TIFF_MAGICS):
        raise FetchError(f"DEM {name}: response is not a valid GeoTIFF ({len(data)} bytes)")


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".part")
    try:
        tmp.write_bytes(data)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            tmp.unlink()


def _get(downloader: Downloader, url: str, what: str) -> bytes:
    try:
        return downloader(url)
    except Exception as exc:
        raise FetchError(f"{what}: download failed ({url}): {exc}") from exc


def fetch_dem(cfg: SiteConfig, downloader: Downloader = http_download) -> list[Path]:
    """Cache the DEM tiles covering the ring (a square of side ring_m)."""
    frame = LocalFrame(cfg.lat, cfg.lon)
    h = cfg.ring_m / 2.0
    lat_n, lon_w = (float(v) for v in frame.to_latlon(-h, -h))
    lat_s, lon_e = (float(v) for v in frame.to_latlon(h, h))
    out = []
    for name in dem_tile_names(lat_s, lat_n, lon_w, lon_e):
        path = cfg.cache_dir / "dem" / f"{name}.tif"
        if not path.exists():
            data = _get(downloader, DEM_URL.format(n=name), f"DEM {name}")
            _check_tiff(data, name)
            _atomic_write(path, data)
        out.append(path)
    return out


def imagery_tile_range(cfg: SiteConfig) -> tuple[range, range]:
    frame = LocalFrame(cfg.lat, cfg.lon)
    h = cfg.core_m / 2.0 + IMAGERY_MARGIN_M
    lat_n, lon_w = (float(v) for v in frame.to_latlon(-h, -h))
    lat_s, lon_e = (float(v) for v in frame.to_latlon(h, h))
    x0, y0 = tile_xy(lat_n, lon_w, cfg.imagery_zoom)
    x1, y1 = tile_xy(lat_s, lon_e, cfg.imagery_zoom)
    return range(math.floor(x0), math.floor(x1) + 1), range(math.floor(y0), math.floor(y1) + 1)


def fetch_imagery(
    cfg: SiteConfig, downloader: Downloader = http_download
) -> list[tuple[int, int, Path]]:
    """Cache the z-level imagery tiles covering the core plus margin; returns (tx, ty, path)."""
    z = cfg.imagery_zoom
    xs, ys = imagery_tile_range(cfg)
    out = []
    for ty in ys:
        for tx in xs:
            path = cfg.cache_dir / "imagery" / str(z) / f"{tx}_{ty}.jpg"
            if not path.exists():
                data = _get(
                    downloader, IMAGERY_URL.format(z=z, y=ty, x=tx), f"imagery tile {z}/{ty}/{tx}"
                )
                if is_placeholder(data):
                    raise FetchError(
                        f"imagery tile {z}/{ty}/{tx} is Esri's no-data placeholder "
                        f"(zoom {z} not available here)"
                    )
                try:
                    with Image.open(io.BytesIO(data)) as im:
                        im.load()
                except Exception as exc:
                    raise FetchError(
                        f"imagery tile {z}/{ty}/{tx} is not a decodable image: {exc}"
                    ) from exc
                _atomic_write(path, data)
            out.append((tx, ty, path))
    return out
