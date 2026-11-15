import io
from pathlib import Path
from unittest import mock

import numpy as np
import pytest
from PIL import Image

from replica import fetch
from replica.fetch import FetchError, dem_tile_names, fetch_dem, fetch_imagery, is_placeholder
from replica.geo import LocalFrame
from replica.site import SiteConfig

SITE = Path(__file__).resolve().parents[3] / "data" / "sites" / "sumber"


def _jpeg(arr) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, "JPEG", quality=75)
    return buf.getvalue()


# Synthetic stand-ins (no Esri imagery is committed): small uniform tile vs noisy tile.
PLACEHOLDER = _jpeg(np.full((256, 256, 3), 235, dtype=np.uint8))
REAL = _jpeg(np.random.default_rng(0).integers(0, 256, (256, 256, 3), dtype=np.uint8))
FAKE_TIF = b"II*\x00" + bytes(4096)


def test_dem_tiles_single():
    cfg = SiteConfig.load(SITE)
    f = LocalFrame(cfg.lat, cfg.lon)
    h = cfg.ring_m / 2
    lat_n, lon_w = f.to_latlon(-h, -h)
    lat_s, lon_e = f.to_latlon(h, h)
    assert dem_tile_names(float(lat_s), float(lat_n), float(lon_w), float(lon_e)) == [
        "Copernicus_DSM_COG_10_N46_00_E108_00_DEM"
    ]


def test_dem_tiles_crossing():
    names = dem_tile_names(45.95, 46.05, 108.95, 109.05)
    assert sorted(names) == sorted(
        f"Copernicus_DSM_COG_10_N{la}_00_E{lo}_00_DEM" for la in (45, 46) for lo in (108, 109)
    )


def test_placeholder_detected():
    assert len(PLACEHOLDER) < 4096 < len(REAL)
    assert is_placeholder(PLACEHOLDER) is True
    assert is_placeholder(REAL) is False


def test_imagery_placeholder_raises(tmp_path):
    cfg = _cfg(tmp_path)
    with pytest.raises(FetchError, match=r"17/\d+/\d+"):
        fetch_imagery(cfg, downloader=lambda url: PLACEHOLDER)


def test_imagery_downloads_and_caches(tmp_path):
    cfg = _cfg(tmp_path)
    calls = []

    def dl(url):
        calls.append(url)
        return REAL

    tiles = fetch_imagery(cfg, downloader=dl)
    assert len(tiles) == len(calls) > 0
    assert all(p.exists() for _, _, p in tiles)
    assert all("/tile/17/" in u for u in calls)
    fetch_imagery(cfg, downloader=lambda url: pytest.fail("should use cache"))


def test_dem_cached_and_atomic(tmp_path):
    cfg = _cfg(tmp_path)
    paths = fetch_dem(cfg, downloader=lambda url: FAKE_TIF)
    assert [p.name for p in paths] == ["Copernicus_DSM_COG_10_N46_00_E108_00_DEM.tif"]
    assert paths[0].read_bytes() == FAKE_TIF
    assert not list(paths[0].parent.glob("*.part"))
    fetch_dem(cfg, downloader=lambda url: pytest.fail("should use cache"))

    def boom(url):
        raise OSError("interrupted")

    cfg2 = _cfg(tmp_path / "b")
    with pytest.raises(FetchError):
        fetch_dem(cfg2, downloader=boom)
    assert not list((cfg2.cache_dir).rglob("*.tif"))


def _cfg(tmp_path):
    cfg = SiteConfig.load(SITE)
    cfg.cache_dir = tmp_path / "cache"
    return cfg


@pytest.mark.site
def test_real_cache_present():
    cfg = SiteConfig.load(SITE)
    dem = list((cfg.cache_dir / "dem").glob("*.tif"))
    if not dem:
        pytest.skip("real DEM cache missing; run `python -I -m replica fetch data/sites/sumber`")
    assert dem


def test_imagery_non_image_raises_and_not_cached(tmp_path):
    cfg = _cfg(tmp_path)
    with pytest.raises(FetchError, match=r"17/\d+/\d+"):
        fetch_imagery(cfg, downloader=lambda url: b"<html>error</html>")
    with pytest.raises(FetchError, match=r"17/\d+/\d+"):
        fetch_imagery(cfg, downloader=lambda url: REAL[:500])
    assert not list(cfg.cache_dir.rglob("*.jpg"))


@pytest.mark.parametrize("body", [b"<html>nope</html>" * 100, b"II*\x00", b""])
def test_dem_invalid_raises_and_not_cached(tmp_path, body):
    cfg = _cfg(tmp_path)
    with pytest.raises(FetchError, match="N46_00_E108"):
        fetch_dem(cfg, downloader=lambda url: body)
    assert not list(cfg.cache_dir.rglob("*.tif"))


def test_user_agent_is_generic():
    seen = {}

    def fake_urlopen(req, timeout=None):
        seen["ua"] = req.get_header("User-agent")
        return io.BytesIO(b"x")

    with mock.patch("urllib.request.urlopen", fake_urlopen):
        fetch.http_download("https://example.invalid/x")
    assert seen["ua"] == "terrain-replica"
