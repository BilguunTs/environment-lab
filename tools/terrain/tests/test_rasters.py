import dataclasses
from pathlib import Path

import numpy as np
import pytest
import tifffile
from PIL import Image

from replica.geo import LocalFrame, tile_bounds
from replica.rasters import build_ortho, dem_grid, read_dem, write_ortho
from replica.site import SiteConfig

SITE = Path(__file__).resolve().parents[3] / "data" / "sites" / "sumber"
DEM_TIF = SITE / "cache" / "dem" / "Copernicus_DSM_COG_10_N46_00_E108_00_DEM.tif"

def site(f):
    f = pytest.mark.skipif(
        not DEM_TIF.exists(), reason="real DEM cache missing (run `python -m replica fetch`)"
    )(f)
    return pytest.mark.site(f)


def _write_dem(path, arr, lon_w, lat_n, step, raster_type):
    """Synthetic GeoTIFF: raster_type 1 = PixelIsArea, 2 = PixelIsPoint; tiepoint at pixel (0,0)."""
    keys = [1, 1, 0, 3, 1024, 0, 1, 2, 1025, 0, 1, raster_type, 2048, 0, 1, 4326]
    tifffile.imwrite(
        path,
        arr.astype(np.float32),
        extratags=[
            (33550, "d", 3, (step, step, 0.0), True),
            (33922, "d", 6, (0.0, 0.0, 0.0, lon_w, lat_n, 0.0), True),
            (34735, "H", len(keys), keys, True),
        ],
    )
    return path


def _ramp(path, raster_type):
    # value = 100*row + col, so a sample position decodes straight from the value.
    arr = (100.0 * np.arange(10)[:, None] + np.arange(10)[None, :]).astype(np.float32)
    return _write_dem(path, arr, 10.0, 50.0, 0.01, raster_type)


def test_dem_pixel_is_point_half_pixel(tmp_path):
    dem = read_dem([_ramp(tmp_path / "p.tif", 2)])
    # PixelIsPoint: sample (r=2, c=3) sits exactly on the tiepoint-relative node.
    assert dem.sample(50.0 - 0.02, 10.0 + 0.03) == pytest.approx(203.0, abs=1e-3)
    assert dem.sample(50.0 - 0.025, 10.0 + 0.035) == pytest.approx(2.5 * 100 + 3.5, abs=1e-3)


def test_dem_pixel_is_area_half_pixel(tmp_path):
    dem = read_dem([_ramp(tmp_path / "a.tif", 1)])
    # PixelIsArea: tiepoint is the NW corner, sample (r, c) centre is at (r+.5, c+.5) pixels.
    assert dem.sample(50.0 - 0.025, 10.0 + 0.035) == pytest.approx(203.0, abs=1e-3)
    assert dem.sample(50.0 - 0.03, 10.0 + 0.04) == pytest.approx(2.5 * 100 + 3.5, abs=1e-3)


def test_nodata_raises(tmp_path):
    arr = np.full((10, 10), 1500.0, dtype=np.float32)
    arr[4, 4] = -32767
    dem = read_dem([_write_dem(tmp_path / "n.tif", arr, 10.0, 50.0, 0.01, 1)])
    with pytest.raises(ValueError, match="lat=49.955.*lon=10.045"):
        dem.sample(49.955, 10.045)
    assert dem.sample(49.99, 10.01) == pytest.approx(1500.0)  # away from the bad cell
    arr[4, 4] = np.nan
    dem = read_dem([_write_dem(tmp_path / "n2.tif", arr, 10.0, 50.0, 0.01, 1)])
    with pytest.raises(ValueError):
        dem.sample(49.955, 10.045)


def test_dem_outside_raises(tmp_path):
    dem = read_dem([_ramp(tmp_path / "a.tif", 1)])
    with pytest.raises(ValueError, match="lat=40"):
        dem.sample(40.0, 10.05)


def test_dem_grid_orientation(tmp_path):
    # Elevation = latitude-ish ramp: higher to the north and east.
    n = 400
    lat = 46.5 - np.arange(n) * 0.0005
    lon = 108.5 + np.arange(n) * 0.0005
    arr = (1000.0 + 1e4 * (lat[:, None] - 46.3) + 1e4 * (lon[None, :] - 108.5)).astype(np.float32)
    tif = _write_dem(tmp_path / "o.tif", arr, 108.5 - 0.00025, 46.5 + 0.00025, 0.0005, 1)
    cfg = SiteConfig.load(SITE)
    frame = LocalFrame(46.4, 108.6)
    g = dem_grid(cfg, frame, 1000.0, 100.0, dems=read_dem([tif]))
    assert g.shape == (21, 21) and g.dtype == np.float32
    assert g[0, 10] > g[20, 10]  # row 0 = north = higher
    assert g[10, 20] > g[10, 0]  # col 0 = west = lower


@site
def test_dem_grid_matches_recon():
    cfg = SiteConfig.load(SITE)
    frame = LocalFrame(cfg.lat, cfg.lon)
    g = dem_grid(cfg, frame, 3000.0, 30.0)
    n = g.shape[0]
    assert g.shape == (201, 201)
    assert 1370 <= g.min() <= 1395, g.min()
    # Brief band was 1630-1670 (SRTM recon); Copernicus GLO-30 (30 m DSM) peaks at ~1688 on the
    # same smooth NW summit, so the upper bound is widened to 1700.
    assert 1630 <= g.max() <= 1700, g.max()
    r, c = np.unravel_index(np.argmax(g), g.shape)
    assert r < n / 2 and c < n / 2, (r, c)


def _tile(color):
    return np.full((256, 256, 3), color, dtype=np.uint8)


def _synthetic_tiles(tmp_path, tx, ty):
    colors = {(0, 0): (255, 0, 0), (1, 0): (0, 255, 0), (0, 1): (0, 0, 255), (1, 1): (255, 255, 255)}
    out = []
    for (dx, dy), col in colors.items():
        p = tmp_path / f"{tx + dx}_{ty + dy}.png"
        Image.fromarray(_tile(col)).save(p)
        out.append((tx + dx, ty + dy, p))
    return out


def _small_cfg(tmp_path):
    cfg = SiteConfig.load(SITE)
    return dataclasses.replace(cfg, core_m=100.0, build_dir=tmp_path / "build")


def test_ortho_orientation(tmp_path):
    tx, ty = 100000, 50000
    # Frame origin on the shared corner of the 4 tiles.
    lat0, lon0 = tile_bounds(tx, ty, 17)[2:]
    frame = LocalFrame(lat0, lon0)
    cfg = _small_cfg(tmp_path)
    img = build_ortho(cfg, frame, _synthetic_tiles(tmp_path, tx, ty))
    h, w, ch = img.shape
    assert (h, w, ch) == (200, 200, 3) and img.dtype == np.uint8
    assert tuple(img[0, 0]) == (255, 0, 0)  # NW red
    assert tuple(img[0, -1]) == (0, 255, 0)  # NE green
    assert tuple(img[-1, 0]) == (0, 0, 255)  # SW blue
    assert tuple(img[-1, -1]) == (255, 255, 255)  # SE white


def test_ortho_missing_tile_raises(tmp_path):
    tx, ty = 100000, 50000
    lat0, lon0 = tile_bounds(tx, ty, 17)[2:]
    tiles = _synthetic_tiles(tmp_path, tx, ty)[:3]
    with pytest.raises(ValueError, match="missing"):
        build_ortho(_small_cfg(tmp_path), LocalFrame(lat0, lon0), tiles)


def test_write_ortho(tmp_path):
    tx, ty = 100000, 50000
    lat0, lon0 = tile_bounds(tx, ty, 17)[2:]
    cfg = _small_cfg(tmp_path)
    path = write_ortho(cfg, LocalFrame(lat0, lon0), _synthetic_tiles(tmp_path, tx, ty))
    assert path == cfg.build_dir / "ortho.png" and path.exists()
    assert Image.open(path).size == (200, 200)
