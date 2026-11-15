import copy
import json
import math

import numpy as np
import pytest

from replica import classify as C
from replica.heightmap import rock_base_y
from replica.rocks import Rock
from replica.scatter import (
    INSTANCE_TYPES,
    Instance,
    fill_mass,
    grass_density,
    instance_rock,
    load_rules,
    placed_rocks,
    rule_fill,
    scatter_doc,
)
from replica.site import SiteConfig

CORE_M = 200.0  # synthetic core: 201 x 201 samples at 1 m
N = 201
MPP = 0.5
NPX = int(CORE_M / MPP)


@pytest.fixture(scope="module")
def rules():
    return load_rules("steppe_granite")


def _cfg(tmp_path, structures=None):
    return SiteConfig(
        name="t", lat=46.25, lon=108.78, core_m=CORE_M, core_step_m=1.0, ring_m=2000.0,
        ring_step_m=30.0, ortho_m_per_px=MPP, imagery_zoom=17, rules="steppe_granite",
        sun={"azimuth_deg": 159.0, "elevation_deg": 28.5}, calibration=[],
        site_dir=tmp_path, cache_dir=tmp_path / "cache", build_dir=tmp_path / "build",
        edits_dir=tmp_path / "edits", structures=list(structures or []),
    )


def _axis():
    return -CORE_M / 2 + np.arange(N, dtype=np.float64)


def _hm(fn=lambda x, z: np.full_like(x, 1400.0)):
    x, z = np.meshgrid(_axis(), _axis())
    return fn(x, z).astype(np.float32)


def _classes(fill=C.SAND):
    return np.full((NPX, NPX), fill, np.uint8)


def _px_xz():
    a = -CORE_M / 2 + (np.arange(NPX) + 0.5) * MPP
    return np.meshgrid(a, a)


def _paint_rock(classes, rock, cls=C.ROCK):
    """Paint a rock's footprint (ellipse / outline polygon) into the 0.5 m class map."""
    x, z = _px_xz()
    classes[_inside_rock(rock, x, z)] = cls
    return classes


def _boulder(x, z, length, width, height, yaw=0.0, rid=None):
    return Rock(id=rid or f"b{x:+.0f}{z:+.0f}", x=x, z=z, length=length, width=width,
                yaw_deg=yaw, height=height, kind="boulder")


def _square_mass(cx, cz, side, height, rid="m1"):
    h = side / 2
    outline = [[cx - h, cz - h], [cx + h, cz - h], [cx + h, cz + h], [cx - h, cz + h]]
    return Rock(id=rid, x=cx, z=cz, length=side, width=side, yaw_deg=0.0, height=height,
                kind="mass", outline=outline, height_source="footprint")


# --- independent geometry for the checks ----------------------------------------------------


def _uv(x, z, cx, cz, yaw_deg):
    """Coordinates along (long axis, short axis) of a footprint with this yaw (clockwise from
    north: yaw 0 -> long axis along -z)."""
    y = math.radians(yaw_deg)
    ax, az = math.sin(y), -math.cos(y)
    bx, bz = math.cos(y), math.sin(y)
    dx, dz = np.asarray(x) - cx, np.asarray(z) - cz
    return dx * ax + dz * az, dx * bx + dz * bz


def _in_poly(poly, x, z):
    p = np.asarray(poly, np.float64)
    x, z = np.asarray(x, np.float64), np.asarray(z, np.float64)
    inside = np.zeros(np.broadcast(x, z).shape, bool)
    x0, z0 = p[:, 0], p[:, 1]
    x1, z1 = np.roll(x0, -1), np.roll(z0, -1)
    for a, b, c, d in zip(x0, z0, x1, z1):
        if b == d:
            continue
        crosses = (b > z) != (d > z)
        xc = a + (z - b) * (c - a) / (d - b)
        inside ^= crosses & (x < xc)
    return inside


def _inside_rock(rock, x, z):
    if rock.kind == "mass" and rock.outline:
        return _in_poly(rock.outline, x, z)
    u, v = _uv(x, z, rock.x, rock.z, rock.yaw_deg)
    return (u / (rock.length / 2)) ** 2 + (v / (rock.width / 2)) ** 2 <= 1.0


def _ellipse_pts(cx, cz, length, width, yaw, k=48):
    """Boundary + centre points of an l x w ellipse footprint."""
    t = np.linspace(0, 2 * np.pi, k, endpoint=False)
    u, v = np.cos(t) * length / 2, np.sin(t) * width / 2
    y = math.radians(yaw)
    ax, az, bx, bz = math.sin(y), -math.cos(y), math.cos(y), math.sin(y)
    xs = np.concatenate([[cx], cx + u * ax + v * bx])
    zs = np.concatenate([[cz], cz + u * az + v * bz])
    return xs, zs


def _overlaps(inst: Instance, rock: Rock) -> bool:
    l, _, w = inst.size
    xs, zs = _ellipse_pts(inst.x, inst.z, l, w, inst.yaw_deg)
    if _inside_rock(rock, xs, zs).any():
        return True
    # rock boundary points inside the instance ellipse (a small rock poking into a big one)
    if rock.kind == "mass" and rock.outline:
        rx, rz = np.asarray(rock.outline, np.float64).T
    else:
        rx, rz = _ellipse_pts(rock.x, rock.z, rock.length, rock.width, rock.yaw_deg)
    u, v = _uv(rx, rz, inst.x, inst.z, inst.yaw_deg)
    return bool(((u / (l / 2)) ** 2 + (v / (w / 2)) ** 2 <= 1.0).any())


def _hm_at(hm, x, z):
    return float(hm[int(round(z + CORE_M / 2)), int(round(x + CORE_M / 2))])


# --- rules file --------------------------------------------------------------------------------


def test_rules_file_has_every_number(rules):
    for key in ("scree_band_m", "downslope_bias", "cluster_radius_m", "near_rock_boost",
                "channel_boost", "seed"):
        assert key in rules, key
    for t in ("scree", "stone", "scrub", "tree"):
        spec = rules["types"][t]
        assert set(spec["size_m"]) == {"l", "h", "w"}
        for lo, hi in spec["size_m"].values():
            assert 0 < lo <= hi
        assert isinstance(spec["density_per_100m2"], dict)
    # This site has no trees: the type exists with zero density everywhere.
    assert not any(rules["types"]["tree"]["density_per_100m2"].values())
    assert set(INSTANCE_TYPES) == {"scree", "stone", "scrub", "tree", "fill_round", "fill_slab"}


# --- rule_fill -------------------------------------------------------------------------------


def _one_boulder_site(tmp_path, hm=None):
    cfg = _cfg(tmp_path)
    rock = _boulder(-60.0, 0.0, 8.0, 6.0, 4.0)
    classes = _paint_rock(_classes(C.SAND), rock)
    return cfg, classes, (hm if hm is not None else _hm()), [rock]


def test_no_scatter_rock_on_sand_far_from_rock(tmp_path, rules):
    cfg, classes, hm, rocks = _one_boulder_site(tmp_path)
    out = rule_fill(classes, hm, rocks, rules, 7, cfg=cfg)
    rocky = [i for i in out if i.type in ("scree", "stone")]
    assert rocky, "no scree/stone at all around the rock"
    r = rocks[0]
    for i in rocky:
        # distance from the rock's footprint edge (its long-axis circle is a lower bound)
        assert math.hypot(i.x - r.x, i.z - r.z) - r.length / 2 <= 30.0, i
    # the open sand on the far side (x > 0, > 50 m from the rock) gets none
    assert not [i for i in rocky if i.x > 0.0]


def test_scree_downslope(tmp_path, rules):
    # Ground falls towards +x (east) at 25 %.
    hm = _hm(lambda x, z: 1400.0 - 0.25 * x)
    cfg = _cfg(tmp_path)
    rock = _boulder(0.0, 0.0, 12.0, 9.0, 8.0)  # a tor: sheds a full-width band
    classes = _paint_rock(_classes(C.GRASS), rock)
    out = rule_fill(classes, hm, [rock], rules, 3, cfg=cfg)
    scree = [i for i in out if i.type == "scree"]
    assert len(scree) >= 10
    cx = float(np.mean([i.x for i in scree]))
    assert cx > rock.x + 2.0  # centroid downhill (east) of the rock
    ground = np.mean([_hm_at(hm, i.x, i.z) for i in scree])
    assert ground < _hm_at(hm, rock.x, rock.z)
    # downhill side holds the majority
    assert sum(i.x > rock.x for i in scree) >= 2 * sum(i.x < rock.x for i in scree)


def test_large_mass_sheds_by_its_thickness(tmp_path, rules):
    """A DEM-topped mass is ~0 thick at its rim; its scree band follows its thick parts."""
    cfg = _cfg(tmp_path)
    mass = _square_mass(0.0, 0.0, 60.0, 9.48, rid="big")
    X, Z = np.meshgrid(_axis(), _axis())
    inside = (np.abs(X) <= 30) & (np.abs(Z) <= 30)
    tops = np.full((N, N), np.nan, np.float32)
    # dome: 10 m in the middle, 0 at the rim
    tops[inside] = 1400.0 + 10.0 * (1 - np.maximum(np.abs(X), np.abs(Z))[inside] / 30.0)
    classes = _paint_rock(_classes(C.GRASS), mass)

    def reach(r):
        out = rule_fill(classes, _hm(), [mass], r, 8, cfg=cfg, tops=tops)
        return max(max(abs(i.x), abs(i.z)) - 30.0 for i in out if i.type == "scree")

    flat = copy.deepcopy(rules)
    flat["scree_source_percentile"] = 0.0  # = rim thickness
    assert reach(flat) <= rules["scree_band_min_m"] + 3.0
    assert reach(rules) >= 6.0


def test_grass_denser_at_rock_feet_and_channels(tmp_path, rules):
    cfg = _cfg(tmp_path)
    rock = _boulder(-50.0, -50.0, 10.0, 8.0, 4.0)
    classes = _paint_rock(_classes(C.SAND), rock)
    x, z = _px_xz()
    channel = (np.abs(x - 50.0) < 1.0) & (z > -80) & (z < 80)
    classes[channel] = C.CHANNEL
    g = grass_density(classes, _hm(), [rock], rules, cfg=cfg).astype(np.float64) / 255.0
    assert g.shape == (N, N)
    X, Z = np.meshgrid(_axis(), _axis())
    d_rock = np.hypot(X - rock.x, Z - rock.z)
    feet = (d_rock > rock.length / 2 + 0.5) & (d_rock <= rock.length / 2 + 3.0)
    chan = (np.abs(X - 50.0) <= 1.0) & (np.abs(Z) < 70)
    open_sand = (d_rock > 40) & (np.abs(X - 50.0) > 20)
    base = g[open_sand].mean()
    assert base > 0
    assert g[feet].mean() >= 2.0 * base
    assert g[chan].mean() >= 2.0 * base
    # under the rock: no grass
    assert g[d_rock < rock.width / 2 - 1.0].max() == 0


def test_scrub_follows_the_dark_patches(tmp_path, rules):
    cfg = _cfg(tmp_path)
    classes = _classes(C.SAND)
    x, z = _px_xz()
    classes[(x < 0)] = C.SCRUB
    out = rule_fill(classes, _hm(), [], rules, 11, cfg=cfg)
    scrub = [i for i in out if i.type == "scrub"]
    west = sum(i.x < -2 for i in scrub)
    east = sum(i.x > 2 for i in scrub)
    assert west > 100
    assert west >= 5 * max(east, 1)


def test_deterministic(tmp_path, rules):
    cfg, classes, hm, rocks = _one_boulder_site(tmp_path)
    a = rule_fill(classes, hm, rocks, rules, 5, cfg=cfg)
    b = rule_fill(classes, hm, rocks, rules, 5, cfg=cfg)
    c = rule_fill(classes, hm, rocks, rules, 6, cfg=cfg)
    assert a == b
    assert a != c
    mass = _square_mass(40.0, 40.0, 20.0, 5.0)
    assert fill_mass(mass, hm, rules, cfg=cfg) == fill_mass(mass, hm, rules, cfg=cfg)


def test_no_instance_overlaps_traced_rock(tmp_path, rules):
    cfg = _cfg(tmp_path)
    rocks = [
        _boulder(-40.0, -30.0, 8.0, 3.0, 3.0, yaw=30.0),
        _boulder(-30.0, -20.0, 5.0, 4.0, 2.0, yaw=100.0),
        _boulder(20.0, 30.0, 3.0, 1.5, 1.5, yaw=60.0),
        _square_mass(30.0, -40.0, 16.0, 6.0),
    ]
    classes = _classes(C.GRASS)
    x, z = _px_xz()
    classes[(x > 0) & (z > 0)] = C.SCRUB
    classes[(x < 0) & (z > 0)] = C.SAND
    for r in rocks:
        _paint_rock(classes, r)
    out = rule_fill(classes, _hm(lambda x, z: 1400.0 + 0.1 * x - 0.05 * z), rocks, rules, 1,
                    cfg=cfg)
    assert len(out) > 200
    for i in out:
        for r in rocks:
            assert not _overlaps(i, r), (i, r.id)


def test_tiny_offgrid_boulder_is_kept_clear(tmp_path, rules):
    """A traced rock smaller than one core sample, off the grid, still blocks placement."""
    cfg = _cfg(tmp_path)
    rocks = [_boulder(x + 0.43, z + 0.57, 1.2, 1.0, 0.8, yaw=37.0)
             for x in range(-80, 81, 8) for z in range(-80, 81, 8)]
    classes = _classes(C.SCRUB)
    for r in rocks:
        _paint_rock(classes, r)
    out = rule_fill(classes, _hm(), rocks, rules, 13, cfg=cfg)
    assert len(out) > 500
    for i in out:
        for r in rocks:
            if abs(i.x - r.x) < 4 and abs(i.z - r.z) < 4:
                assert not _overlaps(i, r), (i, r.id)


def test_nothing_on_track_or_near_structures(tmp_path, rules):
    ger = {"type": "ger", "x": 20.0, "z": 20.0, "diameter_m": 7.0}
    cfg = _cfg(tmp_path, structures=[ger])
    classes = _classes(C.SCRUB)
    x, z = _px_xz()
    track = np.abs(z + 30.0) < 2.0
    classes[track] = C.TRACK
    rock = _boulder(-30.0, -36.0, 6.0, 4.0, 3.0)
    _paint_rock(classes, rock)
    out = rule_fill(classes, _hm(), [rock], rules, 2, cfg=cfg)
    assert len(out) > 200
    for i in out:
        assert not (abs(i.z + 30.0) < 2.0), i
        r = math.hypot(i.size[0], i.size[2]) / 2
        assert math.hypot(i.x - 20.0, i.z - 20.0) >= 3.5 + 2.0 + r - 1e-6, i
    g = grass_density(classes, _hm(), [rock], rules, cfg=cfg)
    X, Z = np.meshgrid(_axis(), _axis())
    assert g[np.abs(Z + 30.0) < 1.5].max() == 0
    assert g[np.hypot(X - 20.0, Z - 20.0) <= 5.5].max() == 0


def test_trees_only_where_rules_say(tmp_path, rules):
    cfg = _cfg(tmp_path)
    classes = _classes(C.GRASS)
    x, z = _px_xz()
    classes[np.abs(x - 10.0) < 2.0] = C.CHANNEL
    assert not [i for i in rule_fill(classes, _hm(), [], rules, 4, cfg=cfg) if i.type == "tree"]
    treed = copy.deepcopy(rules)
    treed["types"]["tree"]["density_per_100m2"] = {"CHANNEL": 8.0}
    trees = [i for i in rule_fill(classes, _hm(), [], treed, 4, cfg=cfg) if i.type == "tree"]
    assert len(trees) >= 10
    for t in trees:
        assert abs(t.x - 10.0) <= 2.5, t  # on a channel sample (1 m grid)
        lo, hi = treed["types"]["tree"]["size_m"]["h"]
        assert lo <= t.size[1] <= hi


def test_sizes_from_rules(tmp_path, rules):
    cfg, classes, hm, rocks = _one_boulder_site(tmp_path)
    classes[:, : NPX // 2] = C.SCRUB
    out = rule_fill(classes, hm, rocks, rules, 9, cfg=cfg)
    seen = set()
    for i in out:
        spec = rules["types"][i.type]["size_m"]
        l, h, w = i.size
        seen.add(i.type)
        assert l >= w
        for v, (lo, hi) in ((l, spec["l"]), (h, spec["h"])):
            assert lo - 0.01 <= v <= hi + 0.01, i
        assert min(spec["w"]) - 0.01 <= w
    assert {"scree", "stone", "scrub"} <= seen


# --- fill_mass -----------------------------------------------------------------------------------


def _assert_inside_outline(pieces, rock):
    for p in pieces:
        xs, zs = _ellipse_pts(p.x, p.z, p.size[0], p.size[2], p.yaw_deg)
        assert _in_poly(rock.outline, xs, zs).all(), p


_BASE_CACHE: dict = {}


def _abs_base(p, hm, cfg):
    """A piece's absolute base: min ground under its footprint + y (Ruling 22)."""
    key = (p, id(hm))
    if key not in _BASE_CACHE:
        _BASE_CACHE[key] = rock_base_y(instance_rock(p), hm, cfg) + p.y
    return _BASE_CACHE[key]


def _top(p, hm, cfg):
    return _abs_base(p, hm, cfg) + p.size[1]


def _surface(pieces, hm, cfg, x, z):
    """Fill top surface at points (x, z): highest piece top over each point (ground if none)."""
    s = np.array([_hm_at(hm, a, b) for a, b in zip(x, z)])
    for p in pieces:
        u, v = _uv(x, z, p.x, p.z, p.yaw_deg)
        inside = (u / (p.size[0] / 2)) ** 2 + (v / (p.size[2] / 2)) ** 2 <= 1.0
        s[inside] = np.maximum(s[inside], _top(p, hm, cfg))
    return s


def _assert_stacked_rest_on_pieces(pieces, hm, cfg):
    """Every piece with y > 0 rests on a piece whose footprint holds its centre and whose top
    is its base."""
    for p in pieces:
        if p.y <= 0:
            continue
        base = _abs_base(p, hm, cfg)
        near = [q for q in pieces if abs(q.x - p.x) < 10 and abs(q.z - p.z) < 10]
        under = [q for q in near if q is not p
                 and abs(_top(q, hm, cfg) - base) <= 0.02
                 and _inside_rock(instance_rock(q), np.array(p.x), np.array(p.z))]
        assert under, p


def _interior_points(rock, rim, step=0.5):
    p = np.asarray(rock.outline)
    x0, x1, z0, z1 = p[:, 0].min(), p[:, 0].max(), p[:, 1].min(), p[:, 1].max()
    gx, gz = np.meshgrid(np.arange(x0 + rim, x1 - rim + 1e-9, step),
                         np.arange(z0 + rim, z1 - rim + 1e-9, step))
    return gx.ravel(), gz.ravel()


def test_mass_fill_height(tmp_path, rules):
    """Brief + Ruling 22: a thick mass (16 m) is filled to its top by stacking pieces."""
    cfg = _cfg(tmp_path)
    hm = _hm(lambda x, z: 1400.0 + 0.05 * x)
    mass = _square_mass(10.0, -10.0, 50.0, 16.0)  # < 60 m: top = rock_top_y (ground + height)
    pieces = fill_mass(mass, hm, rules, cfg=cfg)
    assert pieces and all(p.type == "fill_round" for p in pieces)
    _assert_inside_outline(pieces, mass)
    assert all(p.y >= 0 for p in pieces) and any(p.y > 0 for p in pieces)
    _assert_stacked_rest_on_pieces(pieces, hm, cfg)
    target = _hm_at(hm, mass.x, mass.z) + mass.height  # rock_top_y on this plane
    tol = 0.1 * mass.height
    assert max(_top(p, hm, cfg) for p in pieces) <= target + tol  # nothing pokes above
    rim = rules["types"]["fill_round"]["size_m"]["l"][1]  # one (largest) piece wide
    x, z = _interior_points(mass, rim)
    surf = _surface(pieces, hm, cfg, x, z)
    assert (np.abs(surf - target) <= tol).mean() >= 0.9


def test_mass_fill_follows_mass_tops(tmp_path, rules):
    """Large mass (Ruling 15/18/22): fill up to the local DEM top (16 m tor, stacked); thin
    parts are slab pavement."""
    cfg = _cfg(tmp_path)
    hm = _hm()
    mass = _square_mass(0.0, 0.0, 80.0, 9.48, rid="big")
    X, Z = np.meshgrid(_axis(), _axis())
    tops = np.full((N, N), np.nan, np.float32)
    inside = (np.abs(X) <= 40) & (np.abs(Z) <= 40)
    # thick tor (16 m) on the west half, 0.6 m pavement on the east half
    tops[inside] = np.where(X[inside] < 0, 1416.0, 1400.6)
    pieces = fill_mass(mass, hm, rules, cfg=cfg, tops=tops)
    _assert_inside_outline(pieces, mass)
    _assert_stacked_rest_on_pieces(pieces, hm, cfg)
    west = [p for p in pieces if p.x < -8]
    east = [p for p in pieces if p.x > 8]
    assert west and east
    assert all(p.type == "fill_round" for p in west)
    assert all(p.type == "fill_slab" and p.y == 0 for p in east)
    assert max(_top(p, hm, cfg) for p in west) <= 1416.0 + 1.6
    rim = rules["types"]["fill_round"]["size_m"]["l"][1]
    x, z = _interior_points(mass, rim)
    w = x < -rim
    surf = _surface([p for p in pieces if p.x < 0], hm, cfg, x[w], z[w])
    assert (np.abs(surf - 1416.0) <= 1.6).mean() >= 0.9
    for p in east:
        assert _top(p, hm, cfg) <= 1400.6 + 0.3
        assert p.size[0] >= p.size[1]  # flat


def test_placed_rocks_drops_inside_large_mass():
    big = _square_mass(0.0, 0.0, 80.0, 6.0, rid="big")
    small_in = _square_mass(10.0, 10.0, 12.0, 4.0, rid="small_in")
    b_in = _boulder(-20.0, 5.0, 4.0, 3.0, 2.0, rid="b_in")
    b_out = _boulder(60.0, 0.0, 4.0, 3.0, 2.0, rid="b_out")
    small_out = _square_mass(-70.0, 0.0, 12.0, 4.0, rid="small_out")
    kept = placed_rocks([big, small_in, b_in, b_out, small_out])
    assert [r.id for r in kept] == ["big", "b_out", "small_out"]


# --- scatter.json --------------------------------------------------------------------------------


def test_scatter_doc_columnar():
    inst = [
        Instance("scree", 1.23456, -2.0, 33.333, (0.987, 0.5, 0.4)),
        Instance("scrub", 5.0, 6.004, 0.0, (1.0, 0.8, 0.9)),
    ]
    doc = scatter_doc(inst)
    assert doc["version"] == 1
    assert doc["fields"] == ["type", "x", "z", "y", "yaw_deg", "l", "h", "w"]
    assert doc["types"] == list(INSTANCE_TYPES)
    t = doc["types"]
    assert doc["rows"][0] == [t.index("scree"), 1.23, -2.0, 0.0, 33.33, 0.99, 0.5, 0.4]
    assert doc["rows"][1] == [t.index("scrub"), 5.0, 6.0, 0.0, 0.0, 1.0, 0.8, 0.9]
    stacked = Instance("fill_round", 1.0, 2.0, 0.0, (4.0, 3.0, 3.0), y=5.678)
    assert scatter_doc([stacked])["rows"][0][3] == 5.68
    json.dumps(doc)


# --- Ruling 28: the fill covers its outline in plan -------------------------------------------


def _plan_coverage(pieces, rock, step=0.25):
    """Share of the outline area (grid points) inside at least one piece's l x w ellipse."""
    p = np.asarray(rock.outline)
    gx, gz = np.meshgrid(np.arange(p[:, 0].min(), p[:, 0].max(), step) + step / 2,
                         np.arange(p[:, 1].min(), p[:, 1].max(), step) + step / 2)
    x, z = gx.ravel(), gz.ravel()
    x, z = x[_in_poly(rock.outline, x, z)], z[_in_poly(rock.outline, x, z)]
    hit = np.zeros(x.shape, bool)
    for q in pieces:
        r = q.size[0] / 2
        near = (np.abs(x - q.x) <= r) & (np.abs(z - q.z) <= r)
        u, v = _uv(x[near], z[near], q.x, q.z, q.yaw_deg)
        hit[np.flatnonzero(near)[(u / r) ** 2 + (v / (q.size[2] / 2)) ** 2 <= 1.0]] = True
    return hit.mean()


def _blob_mass(height, rid="blob"):
    """An irregular 40 x 30 m outline (concave notch on the south side)."""
    outline = [[-20, -15], [20, -15], [20, 15], [5, 15], [0, 6], [-5, 15], [-20, 15]]
    return Rock(id=rid, x=0.0, z=0.0, length=40.0, width=30.0, yaw_deg=90.0, height=height,
                kind="mass", outline=outline, height_source="footprint")


def test_mass_fill_covers_outline_in_plan(tmp_path, rules):
    """Ruling 28: seen from above the pieces cover >= 85 % of the outline (stacked tor)."""
    cfg = _cfg(tmp_path)
    hm = _hm(lambda x, z: 1400.0 + 0.05 * x)
    mass = _blob_mass(8.0)
    pieces = fill_mass(mass, hm, rules, cfg=cfg)
    assert _plan_coverage(pieces, mass) >= 0.85
    _assert_inside_outline(pieces, mass)
    _assert_stacked_rest_on_pieces(pieces, hm, cfg)


def test_pavement_fill_covers_outline_in_plan(tmp_path, rules):
    """Ruling 28 for slab pavement (a large mass < pavement_thickness_m thick)."""
    cfg = _cfg(tmp_path)
    hm = _hm()
    mass = _square_mass(0.0, 0.0, 70.0, 1.0, rid="pave")
    tops = np.full((N, N), np.nan, np.float32)
    X, Z = np.meshgrid(_axis(), _axis())
    tops[(np.abs(X) <= 35) & (np.abs(Z) <= 35)] = 1400.6
    pieces = fill_mass(mass, hm, rules, cfg=cfg, tops=tops)
    assert pieces and all(p.type == "fill_slab" for p in pieces)
    assert _plan_coverage(pieces, mass) >= 0.85


def test_gap_pieces_are_single_small_blocks(tmp_path, rules):
    """Gap-pass pieces (below the round type's minimum l) sit on the ground (y = 0), one block
    each, no higher than max_h_over_l x l, within fill.gap.l_m."""
    cfg = _cfg(tmp_path)
    hm = _hm()
    pieces = fill_mass(_blob_mass(8.0), hm, rules, cfg=cfg)
    rs = rules["types"]["fill_round"]
    lo, hi = rules["fill"]["gap"]["l_m"]
    small = [p for p in pieces if p.size[0] < rs["size_m"]["l"][0] - 1e-6]
    assert small  # the gap pass ran
    for p in small:
        assert lo - 1e-6 <= p.size[0] <= hi + 1e-6
        assert p.y == 0.0
        assert p.size[1] <= rs["max_h_over_l"] * p.size[0] + 1e-6


def test_slab_shows_above_sloping_ground(tmp_path, rules):
    """A pavement slab on a slope reaches slab_reveal_m above the highest ground under it, so
    the terrain upslope does not bury it."""
    cfg = _cfg(tmp_path)
    hm = _hm(lambda x, z: 1400.0 + 0.15 * x)  # 15 % slope
    mass = _square_mass(0.0, 0.0, 70.0, 1.0, rid="pave")
    tops = np.full((N, N), np.nan, np.float32)
    X, Z = np.meshgrid(_axis(), _axis())
    sel = (np.abs(X) <= 35) & (np.abs(Z) <= 35)
    tops[sel] = hm[sel] + 0.6
    pieces = [p for p in fill_mass(mass, hm, rules, cfg=cfg, tops=tops) if p.type == "fill_slab"]
    assert pieces
    reveal = rules["fill"]["slab_reveal_m"]
    from replica.heightmap import base_samples

    for p in pieces:
        if p.size[1] >= p.size[0] - 1e-6:  # capped at h <= l (tiny slab on a steep cell)
            continue
        rr, cc = base_samples(instance_rock(p), cfg)
        assert _top(p, hm, cfg) >= float(hm[rr, cc].max()) + reveal - 1e-4, p
