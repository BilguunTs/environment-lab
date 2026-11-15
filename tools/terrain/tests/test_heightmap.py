import json
import math
import shutil
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from replica import classify as C
from replica.export import export_site
from replica.geo import LocalFrame
from replica.heightmap import (
    core_heightmap,
    dem_agreement,
    mass_top_surface,
    ring_heightmap,
    rock_base_y,
    rock_top_y,
    upsample_dem,
)
from replica.rocks import Rock, read_rocks
from replica.scatter import Instance
from replica.site import SiteConfig

SUMBER = Path(__file__).resolve().parents[3] / "data" / "sites" / "sumber"
DEM_TIF = SUMBER / "cache" / "dem" / "Copernicus_DSM_COG_10_N46_00_E108_00_DEM.tif"
CORE_M = 200.0  # synthetic core: 201 x 201 samples at 1 m
N = 201
MPP = 0.5


def _cfg(tmp_path, structures=None, core_m=CORE_M, ring_m=2000.0):
    return SiteConfig(
        name="t", lat=46.25, lon=108.78, core_m=core_m, core_step_m=1.0, ring_m=ring_m,
        ring_step_m=30.0, ortho_m_per_px=MPP, imagery_zoom=17, rules="steppe_granite",
        sun={"azimuth_deg": 159.0, "elevation_deg": 28.5}, calibration=[],
        site_dir=tmp_path, cache_dir=tmp_path / "cache", build_dir=tmp_path / "build",
        edits_dir=tmp_path / "edits", structures=list(structures or []),
    )


def _dem30(fn, half=150.0):
    """30 m DEM grid centred on the origin (row 0 north), values fn(x, z)."""
    axis = np.arange(-half, half + 1e-6, 30.0)
    x, z = np.meshgrid(axis, axis)
    return fn(x, z).astype(np.float32)


def _classes(fill=C.SAND):
    n = int(CORE_M / MPP)
    return np.full((n, n), fill, np.uint8)


def _px_axis():
    """x (or z) of the 0.5 m class-map pixel centres."""
    return -CORE_M / 2 + (np.arange(int(CORE_M / MPP)) + 0.5) * MPP


def _at(hm, x, z):
    return float(hm[int(round(z + CORE_M / 2)), int(round(x + CORE_M / 2))])


def _square_mass(cx, cz, side, height, rid="m1"):
    h = side / 2
    outline = [[cx - h, cz - h], [cx + h, cz - h], [cx + h, cz + h], [cx - h, cz + h]]
    return Rock(id=rid, x=cx, z=cz, length=side, width=side, yaw_deg=0.0, height=height,
                kind="mass", outline=outline, height_source="footprint")


def test_flat_dem_flat_sand(tmp_path):
    cfg = _cfg(tmp_path)
    hm = core_heightmap(_dem30(lambda x, z: np.full_like(x, 1400.0)), _classes(), [], cfg)
    assert hm.shape == (N, N) and hm.dtype == np.float32
    assert np.all(np.abs(hm - 1400.0) <= 0.05)


def test_upsample_is_bicubic_and_exact_at_nodes(tmp_path):
    cfg = _cfg(tmp_path)
    dem30 = _dem30(lambda x, z: 1400.0 + 0.002 * x * x + 0.1 * z)
    up = upsample_dem(dem30, cfg)
    assert up.shape == (N, N)
    # Nodes at x, z = -90, -60, ..., 90 lie on the core grid: exact there.
    for x in (-90.0, 0.0, 60.0):
        for z in (-60.0, 30.0):
            assert abs(_at(up, x, z) - (1400.0 + 0.002 * x * x + 0.1 * z)) < 1e-3
    # Smooth between nodes (cubic): a quadratic is reproduced closely, no 30 m creases.
    assert abs(_at(up, 15.0, 15.0) - (1400.0 + 0.002 * 225 + 1.5)) < 0.1


def test_mass_lowers_ground(tmp_path):
    cfg = _cfg(tmp_path)
    dem30 = _dem30(lambda x, z: np.full_like(x, 1400.0))
    # Centred in one 30 m block (blocks start 10 m in: centres at -75.5 + 30 k).
    c = 14.5
    rock = _square_mass(c, c, 20.0, 5.0)
    classes = _classes()
    a = _px_axis()
    classes[np.ix_(np.abs(a - c) < 10, np.abs(a - c) < 10)] = C.ROCK
    hm = core_heightmap(dem30, classes, [rock], cfg)
    assert _at(hm, c, c) < 1400.0 - 1.5  # ground under the mass lowered (5 m x 4/9 of a block)
    assert rock_top_y(rock, hm, cfg) < 1400.0 + 5.0
    assert abs(_at(hm, 90.0, 90.0) - 1400.0) < 1.0  # far ground near the DEM
    rms, max_abs = dem_agreement(hm, [rock], dem30, cfg)
    assert rms <= 2.0 and max_abs <= 6.0
    assert rms <= 0.2  # re-levelled: block means of ground + rock top match the DEM


def test_mass_double_count_without_correction(tmp_path):
    """The agreement metric itself sees a rock stacked on an unlowered DEM (double counting)."""
    cfg = _cfg(tmp_path)
    dem30 = _dem30(lambda x, z: np.full_like(x, 1400.0))
    rock = _square_mass(14.5, 14.5, 20.0, 12.0)
    flat = np.full((N, N), 1400.0, np.float32)
    rms, max_abs = dem_agreement(flat, [rock], dem30, cfg)
    assert max_abs > 2.0


def test_channel_cut(tmp_path):
    cfg = _cfg(tmp_path)
    classes = _classes()
    a = _px_axis()
    classes[:, np.abs(a) < 1.5] = C.CHANNEL  # 3 m wide channel along z
    hm = core_heightmap(_dem30(lambda x, z: np.full_like(x, 1400.0)), classes, [], cfg)
    for z in (-40.0, 0.0, 35.0):
        neighbours = 0.5 * (_at(hm, -10.0, z) + _at(hm, 10.0, z))
        depth = neighbours - _at(hm, 0.0, z)
        assert 0.3 <= depth <= 1.5, (z, depth)


def test_rock_on_slope(tmp_path):
    cfg = _cfg(tmp_path)
    slope = math.tan(math.radians(30.0))
    dem30 = _dem30(lambda x, z: 1400.0 + slope * x)
    rock = Rock(id="b1", x=5.3, z=-4.7, length=3.0, width=2.0, yaw_deg=35.0, height=3.0,
                kind="boulder")
    hm = core_heightmap(dem30, _classes(C.GRASS), [rock], cfg)
    # Ground sampled densely over the rotated length x width rectangle.
    yaw = math.radians(rock.yaw_deg)
    ax = np.array([math.sin(yaw), -math.cos(yaw)])  # long axis, clockwise from north (-z)
    bx = np.array([math.cos(yaw), math.sin(yaw)])
    s, t = np.meshgrid(np.linspace(-1.5, 1.5, 31), np.linspace(-1.0, 1.0, 21))
    px = rock.x + s * ax[0] + t * bx[0]
    pz = rock.z + s * ax[1] + t * bx[1]
    from scipy.ndimage import map_coordinates

    ground = map_coordinates(hm.astype(np.float64), [pz.ravel() + 100, px.ravel() + 100], order=1)
    base = rock_base_y(rock, hm, cfg)
    assert base <= ground.min() + 1e-4
    assert base > ground.min() - 1.5  # not buried absurdly (one sample of 30 deg slope)
    centre = map_coordinates(hm.astype(np.float64), [[rock.z + 100], [rock.x + 100]], order=1)[0]
    assert abs(rock_top_y(rock, hm, cfg) - (centre + 3.0)) < 1e-3


def _tor(x, z):
    """Flat 1400 with a 14 m high round tor of radius ~45 m."""
    r = np.hypot(x, z)
    return 1400.0 + 14.0 * np.clip(1.0 - (r / 50.0) ** 2, 0.0, None)


def test_large_mass_top_from_dem(tmp_path):
    """Ruling 15: a mass wider than 60 m takes its rock-top surface from the DEM; the ground
    under it comes from the rim and stays below that top."""
    cfg = _cfg(tmp_path)
    dem30 = _dem30(_tor)
    ang = np.linspace(0, 2 * math.pi, 48, endpoint=False)
    outline = [[45 * math.cos(t), 45 * math.sin(t)] for t in ang]
    rock = Rock(id="big", x=0.0, z=0.0, length=90.0, width=90.0, yaw_deg=0.0, height=9.48,
                kind="mass", outline=outline, height_source="footprint")
    classes = _classes()
    a = _px_axis()
    classes[np.hypot(a[None, :], a[:, None]) < 45] = C.ROCK
    hm = core_heightmap(dem30, classes, [rock], cfg)
    tops = mass_top_surface(dem30, [rock], cfg)
    up = upsample_dem(dem30, cfg)
    inside = ~np.isnan(tops)
    assert inside.sum() > 0.9 * math.pi * 45 * 45
    assert np.allclose(tops[inside], up[inside])
    assert np.isnan(tops[0, 0])
    assert np.all(hm[inside] <= tops[inside] + 1e-4)
    # Ground under the tor centre is interpolated from the rim, far below the rock top.
    assert _at(hm, 0.0, 0.0) < _at(up, 0.0, 0.0) - 8.0
    assert _at(hm, 0.0, 0.0) < max(_at(hm, 50.0, 0.0), _at(hm, -50.0, 0.0)) + 2.0
    rms, max_abs = dem_agreement(hm, [rock], dem30, cfg)
    assert rms <= 0.5 and max_abs <= 2.0


def test_large_mass_is_two_dem_cells_long():
    """A long, narrow mass (>= 60 m along its axis) also takes its top from the DEM: one flat
    `height` top over 90 m of slope would stand metres above the DEM at its downhill end."""
    from replica.heightmap import is_large_mass

    long_narrow = _square_mass(0.0, 0.0, 30.0, 9.48)
    long_narrow.length = 90.0
    assert is_large_mass(long_narrow)
    assert not is_large_mass(_square_mass(0.0, 0.0, 55.0, 9.48))
    boulder = Rock(id="b", x=0, z=0, length=70, width=70, yaw_deg=0, height=3, kind="boulder")
    assert not is_large_mass(boulder)


def test_ger_ground_flat(tmp_path):
    cfg = _cfg(tmp_path, structures=[{"type": "ger", "x": -20.0, "z": 12.0, "diameter_m": 7.0}])
    dem30 = _dem30(lambda x, z: 1400.0 + 0.1 * x + 0.05 * z)
    hm = core_heightmap(dem30, _classes(C.GRASS), [], cfg)
    zz, xx = np.mgrid[0:N, 0:N] - 100.0
    under = np.hypot(xx + 20.0, zz - 12.0) <= 3.5
    assert np.ptp(hm[under]) <= 0.05


def test_ring_heightmap_shape(tmp_path):
    cfg = _cfg(tmp_path, ring_m=20000.0)

    class Flat:
        def sample(self, lat, lon):
            return np.full(np.shape(lat), 1300.0, np.float32)

    ring = ring_heightmap(cfg, LocalFrame(cfg.lat, cfg.lon), dems=Flat())
    assert ring.shape == (667, 667) and ring.dtype == np.float32
    assert np.all(ring == 1300.0)


def test_export_site(tmp_path):
    cfg = _cfg(tmp_path, structures=[{"type": "ger", "x": 1.0, "z": 2.0, "diameter_m": 6.5}])
    core = (1400.0 + np.arange(N * N, dtype=np.float32).reshape(N, N) * 1e-3).astype(np.float32)
    ring = np.full((5, 5), 1350.5, np.float32)
    tops = np.full((N, N), np.nan, np.float32)
    tops[3, 4] = 1410.0
    classes = _classes(C.SAND)
    classes[0:2, 0:2] = [[C.ROCK, C.ROCK], [C.ROCK, C.STRUCTURE]]  # mode ROCK (mean would be 2.5)
    classes[0:2, 2:4] = [[C.GRASS, C.CHANNEL], [C.CHANNEL, C.CHANNEL]]
    rocks = [Rock(id="r1", x=1.0, z=2.0, length=3.0, width=2.0, yaw_deg=10.0, height=1.5,
                  kind="boulder")]
    inst = [Instance("scree", 1.234, 2.0, 10.0, (0.5, 0.3, 0.4))]
    grass = np.zeros((N, N), np.uint8)
    grass[0, 1] = 200
    export_site(cfg, core, ring, classes, rocks, inst, mass_tops=tops, placed=rocks,
                grass=grass)
    b = cfg.build_dir
    got = np.fromfile(b / "core.r32", dtype="<f4").reshape(N, N)
    assert np.array_equal(got, core)
    assert np.array_equal(np.fromfile(b / "ring.r32", dtype="<f4").reshape(5, 5), ring)
    mt = np.fromfile(b / "mass_tops.r32", dtype="<f4").reshape(N, N)
    assert mt[3, 4] == 1410.0 and np.isnan(mt[0, 0])
    with Image.open(b / "classes.png") as im:
        cls = np.asarray(im)
    assert cls.shape == (200, 200)
    assert cls[0, 0] == C.ROCK and cls[0, 1] == C.CHANNEL and cls[5, 5] == C.SAND
    sc = json.loads((b / "scatter.json").read_text())
    assert sc["rows"] == [[0, 1.23, 2.0, 0.0, 10.0, 0.5, 0.3, 0.4]] and sc["types"][0] == "scree"
    assert read_rocks(b / "rocks_placed.json") == rocks
    with Image.open(b / "grass_density.png") as im:
        assert im.mode == "L" and np.array_equal(np.asarray(im), grass)
    assert not (b / "rocks.json").exists()  # Ruling 5: only merge(detected, edits) writes it
    m = json.loads((b / "manifest.json").read_text())
    assert m["base_elevation"] == 1400.0 == math.floor(core.min())  # one definition
    assert "floor" in m["base_elevation_def"]
    assert m["rocks"] == {"file": "rocks.json", "count": 1}
    assert m["core"]["n"] == N and m["core"]["step_m"] == 1.0 and m["core"]["size_m"] == 200.0
    assert m["ring"]["n"] == 5 and m["ring"]["step_m"] == 30.0 and m["ring"]["size_m"] == 120.0
    assert m["mass_tops"]["file"] == "mass_tops.r32"
    assert m["rocks_placed"]["file"] == "rocks_placed.json" and m["rocks_placed"]["count"] == 1
    assert m["grass_density"]["file"] == "grass_density.png" and m["grass_density"]["n"] == N
    assert m["scatter"]["count"] == 1 and m["scatter"]["counts"]["scree"] == 1
    assert m["classes"]["ids"]["rock"] == C.ROCK
    assert m["sun"] == cfg.sun and m["structures"] == cfg.structures
    assert m["lat"] == cfg.lat and m["lon"] == cfg.lon
    assert "north" in m["grid"]["row0"] and "west" in m["grid"]["col0"]


def test_block_mode_keeps_two_px_channel_offset_by_one():
    """A 2-px (1 m) channel starting on an odd pixel straddles two 2x2 blocks with a 2-2 tie in
    each: it must stay CHANNEL (continuous), not fall to the lower id."""
    from replica.heightmap import block_mode

    a = np.full((40, 40), C.SAND, np.uint8)
    a[:, 13:15] = C.CHANNEL  # columns 13-14: blocks 6 (cols 12-13) and 7 (cols 14-15)
    out = block_mode(a, 2)
    assert np.all(out[:, 6] == C.CHANNEL) and np.all(out[:, 7] == C.CHANNEL)
    assert np.all(out[:, :6] == C.SAND) and np.all(out[:, 8:] == C.SAND)
    b = np.full((4, 4), C.GRASS, np.uint8)
    b[0, 1] = b[1, 1] = C.TRACK
    b[0, 2] = b[1, 3] = C.STRUCTURE
    b[0, 3] = b[1, 2] = C.CHANNEL
    out = block_mode(b, 2)
    assert out[0, 0] == C.TRACK and out[0, 1] == C.STRUCTURE
    # Ties between ordinary classes follow the block's north-west pixel, not the lowest id.
    c = np.array([[C.SCRUB, C.ROCK], [C.ROCK, C.SCRUB]], np.uint8)
    assert block_mode(c, 2)[0, 0] == C.SCRUB
    assert block_mode(c[::-1], 2)[0, 0] == C.ROCK
    # A clear majority always wins.
    d = np.array([[C.ROCK, C.ROCK], [C.ROCK, C.CHANNEL]], np.uint8)
    assert block_mode(d, 2)[0, 0] == C.ROCK


def test_level_warns_at_iteration_cap(tmp_path, monkeypatch):
    from replica import heightmap as H

    monkeypatch.setitem(H.PARAMS, "level_max_iter", 1)
    cfg = _cfg(tmp_path)
    rock = _square_mass(14.5, 14.5, 20.0, 12.0)
    with pytest.warns(UserWarning, match="without converging"):
        core_heightmap(_dem30(lambda x, z: np.full_like(x, 1400.0)), _classes(), [rock], cfg)


def test_drift_check_sees_ground_offset(tmp_path):
    from replica.heightmap import agreement_failures, drift_check

    cfg = _cfg(tmp_path)
    dem30 = _dem30(lambda x, z: np.full_like(x, 1400.0))
    native = np.full((N, N), 1400.0)
    rock = Rock(id="b", x=14.5, z=14.5, length=4, width=3, yaw_deg=0, height=2, kind="boulder")
    hm = core_heightmap(dem30, _classes(), [rock], cfg)
    st = drift_check(hm, [rock], dem30, native, cfg)
    assert st["rock_free_blocks"] == 35 and st["rock_free_max_m"] < 0.05
    assert st["native_max_m"] < 0.1 and agreement_failures(st) == []
    st = drift_check(hm + 7.0, [rock], dem30, native, cfg)
    assert st["rock_free_rms_m"] > 6.9
    assert any(f.startswith("rock_free_max_m") for f in agreement_failures(st))
    assert any(f.startswith("native_rms_m") for f in agreement_failures(st))


def _synthetic_site(tmp_path, monkeypatch):
    """A 200 m site whose cache, ortho, classes and rocks steps are stubbed; flat 1400 m DEM."""
    from replica import classify, fetch, rasters, rocks

    site = tmp_path / "syn"
    site.mkdir()
    data = json.loads((SUMBER / "site.json").read_text())
    data.update(core_m=200, ring_m=600)
    (site / "site.json").write_text(json.dumps(data))

    class Flat:
        def sample(self, lat, lon):
            return np.full(np.shape(lat), 1400.0, np.float32)

    def write_classes(cfg):
        cfg.build_dir.mkdir(parents=True, exist_ok=True)
        Image.fromarray(_classes(), mode="L").save(cfg.build_dir / "classes_full.png")

    monkeypatch.setattr(fetch, "fetch_dem", lambda cfg, downloader=None: [])
    monkeypatch.setattr(fetch, "fetch_imagery", lambda cfg, downloader=None: [])
    monkeypatch.setattr(rasters, "write_ortho", lambda cfg, frame, tiles: None)
    monkeypatch.setattr(rasters, "read_dem", lambda paths: Flat())
    monkeypatch.setattr(classify, "write_classes", write_classes)
    monkeypatch.setattr(rocks, "write_site_rocks", lambda cfg: ([], []))
    return site


def test_build_synthetic_passes(tmp_path, monkeypatch, capsys):
    from replica.__main__ import main

    site = _synthetic_site(tmp_path, monkeypatch)
    assert main(["build", str(site)]) == 0
    m = json.loads((site / "build" / "manifest.json").read_text())
    for k in ("agreement_rms_m", "native_rms_m", "native_max_m", "rock_free_rms_m",
              "rock_free_max_m"):
        assert m["stats"][k] <= 0.05, k
    assert not (site / "build" / "rocks.json").exists()


def test_build_exits_nonzero_on_ground_drift(tmp_path, monkeypatch, capsys):
    """Synthetic failure: a heightmap 10 m above the DEM must fail the build."""
    from replica import heightmap as H
    from replica.__main__ import main

    site = _synthetic_site(tmp_path, monkeypatch)
    real = H.core_heightmap
    monkeypatch.setattr(H, "core_heightmap", lambda *a: real(*a) + np.float32(10.0))
    assert main(["build", str(site)]) == 1
    err = capsys.readouterr().err
    assert "rock_free_max_m" in err and "native_rms_m" in err and "agreement_rms_m" in err
    assert (site / "build" / "manifest.json").exists()  # written for inspection


def test_build_without_cache_points_to_fetch(tmp_path, capsys):
    from replica.__main__ import main

    site = tmp_path / "s"
    site.mkdir()
    shutil.copy(SUMBER / "site.json", site / "site.json")
    assert main(["build", str(site)]) == 1
    assert "fetch" in capsys.readouterr().err
    assert not (site / "cache").exists()


# --- real site -------------------------------------------------------------------------


@pytest.mark.site
@pytest.mark.skipif(
    not (DEM_TIF.exists() and (SUMBER / "build" / "classes_full.png").exists()
         and (SUMBER / "build" / "rocks.json").exists()),
    reason="real DEM cache or build/classes_full.png / rocks.json missing",
)
def test_real_site_agreement():
    from replica.heightmap import core_dem30
    from replica.rocks import read_rocks

    cfg = SiteConfig.load(SUMBER)
    dem30 = core_dem30(cfg, LocalFrame(cfg.lat, cfg.lon))
    with Image.open(cfg.build_dir / "classes_full.png") as im:
        classes = np.asarray(im)
    rocks = read_rocks(cfg.build_dir / "rocks.json")
    hm = core_heightmap(dem30, classes, rocks, cfg)
    assert hm.shape == (2001, 2001) and np.isfinite(hm).all()
    rms, max_abs = dem_agreement(hm, rocks, dem30, cfg)
    print(f"real site: rms {rms:.3f} m, max {max_abs:.3f} m")
    assert rms <= 2.0
    assert max_abs <= 6.0
