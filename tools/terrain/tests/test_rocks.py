import dataclasses
import json
import math
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from replica import classify as C
from replica.rocks import (
    Edits,
    Rock,
    detect_rocks,
    load_edits,
    merge,
    read_rocks,
    rock_id,
    write_edits,
    write_rocks,
)
from replica.site import SiteConfig
from replica.sun import Sun

SUMBER = Path(__file__).resolve().parents[3] / "data" / "sites" / "sumber"
MPP = 0.5
N = 160  # 80 x 80 m synthetic scene


def _cfg():
    return SiteConfig.load(SUMBER)


def _xz_to_rc(x, z):
    half = N * MPP / 2.0
    return (z + half) / MPP - 0.5, (x + half) / MPP - 0.5


def _rect(x0, z0, x1, z1):
    """Bool mask of the pixels whose centres lie in [x0, x1) x [z0, z1) (metres)."""
    axis = -N * MPP / 2.0 + (np.arange(N) + 0.5) * MPP
    xs = (axis >= x0) & (axis < x1)
    zs = (axis >= z0) & (axis < z1)
    return zs[:, None] & xs[None, :]


def _cast(mask, sun, length_m):
    """Pixels swept by mask moved 0..length_m along the shadow direction, minus mask."""
    dx, dz = sun.shadow_dir_xz()
    out = np.zeros_like(mask)
    steps = int(round(length_m / MPP))
    for t in range(1, steps + 1):
        dr, dc = int(round(t * dz)), int(round(t * dx))
        out |= np.roll(np.roll(mask, dr, axis=0), dc, axis=1)
    return out & ~mask


def _scene(rocks, sun):
    """rocks: list of (rect mask, shadow length m). Returns (ortho, classes)."""
    rng = np.random.default_rng(3)
    lum = np.full((N, N), 120.0) + rng.normal(0, 2.0, (N, N))
    classes = np.full((N, N), C.GRASS, np.uint8)
    any_rock = np.zeros((N, N), bool)
    for mask, _ in rocks:
        any_rock |= mask
    for mask, shadow_m in rocks:
        lum[_cast(mask, sun, shadow_m) & ~any_rock] = 30.0
    lum[any_rock] = 200.0
    classes[any_rock] = C.ROCK
    ortho = np.clip(np.rint(np.repeat(lum[..., None], 3, axis=2)), 0, 255).astype(np.uint8)
    return ortho, classes


@pytest.mark.parametrize("azimuth", [180.0, 159.0])
def test_height_from_shadow(azimuth):
    sun = Sun(azimuth, 45.0)
    blob = _rect(-2.0, -1.5, 2.0, 1.5)  # 4 m E-W x 3 m N-S
    ortho, classes = _scene([(blob, 2.0)], sun)
    rocks = detect_rocks(ortho, classes, sun, _cfg())
    assert len(rocks) == 1
    r = rocks[0]
    assert r.kind == "boulder" and r.source == "detected" and r.outline is None
    assert r.height_source == "shadow"
    assert abs(r.length - 4.0) <= 0.6 and abs(r.width - 3.0) <= 0.6
    assert abs(r.height - 2.0) <= 0.5
    assert abs(r.x) <= 0.3 and abs(r.z) <= 0.3
    assert min(abs(r.yaw_deg - 90.0), abs(r.yaw_deg - 270.0)) <= 5.0  # long axis E-W
    assert r.id == rock_id(r.x, r.z)


def test_yaw_clockwise_from_north():
    sun = Sun(180.0, 45.0)
    # Long axis N-S: yaw 0 (mod 180).
    blob = _rect(-1.0, -3.0, 1.0, 3.0)
    ortho, classes = _scene([(blob, 1.0)], sun)
    (r,) = detect_rocks(ortho, classes, sun, _cfg())
    assert min(r.yaw_deg % 180.0, 180.0 - r.yaw_deg % 180.0) <= 5.0
    assert abs(r.length - 6.0) <= 0.6 and abs(r.width - 2.0) <= 0.6


def test_small_blob_ignored():
    sun = Sun(180.0, 45.0)
    blob = _rect(-0.5, -0.5, 0.5, 0.5)  # 1 x 1 m
    ortho, classes = _scene([(blob, 1.0)], sun)
    assert detect_rocks(ortho, classes, sun, _cfg()) == []


def test_merged_shadows_make_mass():
    # Sun due south: shadows fall north (-z). Three 3 x 3 m blobs in a N-S row, 1.5 m apart;
    # each one's shadow covers the gap and touches the next blob.
    sun = Sun(180.0, 45.0)
    blobs = [_rect(-1.5, z, 1.5, z + 3.0) for z in (-6.75, -2.25, 2.25)]
    ortho, classes = _scene([(b, 2.0) for b in blobs], sun)
    rocks = detect_rocks(ortho, classes, sun, _cfg())
    assert len(rocks) == 1
    m = rocks[0]
    assert m.kind == "mass"
    assert m.outline is not None and len(m.outline) >= 4
    # Outline encloses all three blob centres.
    for zc in (-5.25, -0.75, 3.75):
        assert _inside(m.outline, 0.0, zc)
    assert abs(m.length - 12.0) <= 1.0 and abs(m.width - 3.0) <= 0.6
    assert abs(m.height - 2.0) <= 0.5


def test_separate_shadows_stay_boulders():
    sun = Sun(180.0, 45.0)
    blobs = [_rect(x, -1.5, x + 3.0, 1.5) for x in (-15.0, 0.0, 15.0)]
    ortho, classes = _scene([(b, 2.0) for b in blobs], sun)
    rocks = detect_rocks(ortho, classes, sun, _cfg())
    assert sorted(r.kind for r in rocks) == ["boulder"] * 3


def test_unmeasurable_shadow_falls_back_to_footprint():
    sun = Sun(180.0, 45.0)
    blob = _rect(-2.0, -1.5, 2.0, 1.5)
    ortho, classes = _scene([(blob, 0.0)], sun)  # no visible shadow
    (r,) = detect_rocks(ortho, classes, sun, _cfg())
    assert r.height_source == "footprint"
    assert 0.3 <= r.height <= r.width


def _inside(poly, x, z):
    inside = False
    n = len(poly)
    for i in range(n):
        (x1, z1), (x2, z2) = poly[i], poly[(i + 1) % n]
        if (z1 > z) != (z2 > z) and x < x1 + (z - z1) * (x2 - x1) / (z2 - z1):
            inside = not inside
    return inside


def _three_boulders():
    sun = Sun(180.0, 45.0)
    blobs = [_rect(x, -1.5, x + 3.0, 1.5) for x in (-20.0, -5.0, 10.0)]
    return (*_scene([(b, 2.0) for b in blobs], sun), sun)


def test_edits_survive_redetect(tmp_path):
    ortho, classes, sun = _three_boulders()
    detected = detect_rocks(ortho, classes, sun, _cfg())
    assert len(detected) == 3
    a, b, c = sorted(detected, key=lambda r: r.x)
    new = Rock(
        id=rock_id(30.0, 30.0), x=30.0, z=30.0, length=2.5, width=2.0, yaw_deg=45.0,
        height=1.2, kind="boulder", outline=None, source="edit", height_source="footprint",
    )
    edits = Edits(added=[new], deleted={a.id}, changed={b.id: {"height": 5.0}})
    path = tmp_path / "rocks_edits.json"
    write_edits(path, edits)

    first = merge(detected, load_edits(path))
    redetected = detect_rocks(ortho, classes, sun, _cfg())
    second = merge(redetected, load_edits(path))

    for merged in (first, second):
        ids = {r.id for r in merged}
        assert a.id not in ids
        assert new.id in ids and c.id in ids
        assert len(merged) == 3
        changed = next(r for r in merged if r.id == b.id)
        assert changed.height == 5.0 and changed.source == "edit"
        assert next(r for r in merged if r.id == c.id).source == "detected"
    assert first == second


def test_merge_without_edits_file(tmp_path):
    ortho, classes, sun = _three_boulders()
    detected = detect_rocks(ortho, classes, sun, _cfg())
    edits = load_edits(tmp_path / "missing.json")
    assert edits == Edits()
    assert merge(detected, edits) == detected


def test_merge_rejects_unknown_field():
    ortho, classes, sun = _three_boulders()
    detected = detect_rocks(ortho, classes, sun, _cfg())
    with pytest.raises(ValueError, match="colour"):
        merge(detected, Edits(changed={detected[0].id: {"colour": 3}}))


def test_rocks_json_round_trip(tmp_path):
    sun = Sun(180.0, 45.0)
    blobs = [_rect(-1.5, z, 1.5, z + 3.0) for z in (-6.75, -2.25, 2.25)]
    blobs.append(_rect(20.0, 0.0, 23.0, 3.0))
    ortho, classes = _scene([(b, 2.0) for b in blobs], sun)
    rocks = detect_rocks(ortho, classes, sun, _cfg())
    assert {r.kind for r in rocks} == {"mass", "boulder"}
    path = tmp_path / "rocks.json"
    write_rocks(path, rocks)
    data = json.loads(path.read_text())
    assert data["version"] == 1 and len(data["rocks"]) == len(rocks)
    assert read_rocks(path) == rocks


def test_rock_id_stable():
    assert rock_id(10.1, -3.2) == rock_id(10.0, -3.1)
    assert rock_id(10.0, -3.0) != rock_id(10.5, -3.0)


# --- real site ----------------------------------------------------------------------------

ORTHO = SUMBER / "build" / "ortho.png"
CLASSES = SUMBER / "build" / "classes_full.png"
ROCKS = SUMBER / "build" / "rocks.json"
DETECTED = SUMBER / "build" / "rocks_detected.json"


@pytest.mark.site
@pytest.mark.skipif(not DETECTED.exists(), reason="build/rocks_detected.json missing")
def test_real_rock_lists():
    from replica.rocks import merge_site_rocks

    detected = read_rocks(DETECTED)
    assert len({r.id for r in detected}) == len(detected)
    assert all(r.source == "detected" for r in detected)
    assert all(math.sqrt(r.length * r.width) >= 2.0 for r in detected)
    assert all(0.3 <= r.height <= 40.0 for r in detected)
    assert all(-1000 <= r.x <= 1000 and -1000 <= r.z <= 1000 for r in detected)
    assert read_rocks(ROCKS) == merge_site_rocks(_cfg(), detected)


def test_dark_ground_is_not_a_shadow():
    # A 3 x 3 m rock at the edge of a 40 m patch of dark ground: the "shadow" would make it
    # tens of metres tall. It is not a measurement, and it does not join the rock beyond.
    sun = Sun(180.0, 45.0)
    a = _rect(-1.5, 10.0, 1.5, 13.0)
    b = _rect(-1.5, -33.0, 1.5, -30.0)
    ortho, classes = _scene([(a, 0.0), (b, 0.0)], sun)
    ortho[_rect(-10.0, -30.0, 10.0, 10.0)] = 30
    rocks = detect_rocks(ortho, classes, sun, _cfg())
    assert sorted(r.kind for r in rocks) == ["boulder", "boulder"]
    for r in rocks:
        assert r.height <= 1.5 * math.sqrt(r.length * r.width)


def test_large_single_outcrop_is_mass():
    sun = Sun(180.0, 45.0)
    blob = _rect(-10.0, -4.0, 10.0, 4.0)
    ortho, classes = _scene([(blob, 3.0)], sun)
    (r,) = detect_rocks(ortho, classes, sun, _cfg())
    assert r.kind == "mass" and r.outline is not None
    assert abs(r.length - 20.0) <= 0.6 and abs(r.width - 8.0) <= 0.6
    assert abs(r.height - 3.0) <= 0.5


def test_thin_neck_splits_rocks():
    # Two 4 x 4 m rocks joined by a 0.5 m wide rock "neck" (class-map growth artefact).
    sun = Sun(180.0, 45.0)
    a = _rect(-6.0, -2.0, -2.0, 2.0)
    b = _rect(2.0, -2.0, 6.0, 2.0)
    neck = _rect(-2.0, 0.0, 2.0, 0.5)
    ortho, classes = _scene([(a, 2.0), (b, 2.0), (neck, 0.0)], sun)
    rocks = sorted(detect_rocks(ortho, classes, sun, _cfg()), key=lambda r: r.x)
    assert [r.kind for r in rocks] == ["boulder", "boulder"]
    assert abs(rocks[0].x + 4.0) <= 1.0 and abs(rocks[1].x - 4.0) <= 1.0
    for r in rocks:
        assert abs(r.width - 4.0) <= 0.6 and abs(r.height - 2.0) <= 0.5


def test_unmeasured_mass_height_from_members():
    # Three staggered 6 x 3 m rocks linked only by the shadows in the gaps between them (no
    # shadow reaches open ground): a mass ~10 m wide whose height comes from its rocks.
    sun = Sun(180.0, 45.0)
    blobs = [
        _rect(-8.0, 2.25, -2.0, 5.25),
        _rect(-5.0, -2.25, 1.0, 0.75),
        _rect(-2.0, -6.75, 4.0, -3.75),
    ]
    ortho, classes = _scene([(b, 0.0) for b in blobs], sun)
    ortho[_rect(-5.0, 0.75, -2.0, 2.25)] = 30
    ortho[_rect(-2.0, -3.75, 1.0, -2.25)] = 30
    (m,) = detect_rocks(ortho, classes, sun, _cfg())
    assert m.kind == "mass" and m.height_source == "footprint"
    assert m.width >= 6.0
    assert abs(m.height - 0.6 * 3.0) <= 0.2


def test_footprint_height_capped_by_measured_heights():
    # 20 measured 3 x 3 m boulders 2 m tall, and a 20 x 8 m outcrop with no visible shadow:
    # its footprint guess (2/3 x 8 m) may not exceed what the shadows measured (P90 = 2 m).
    sun = Sun(180.0, 45.0)
    items = [
        (_rect(x, z, x + 3.0, z + 3.0), 2.0)
        for x in (-36.0, -28.0, -20.0, -12.0, -4.0)
        for z in (-36.0, -28.0, -20.0, -12.0)
    ]
    items.append((_rect(-10.0, 10.0, 10.0, 18.0), 0.0))
    ortho, classes = _scene(items, sun)
    rocks = detect_rocks(ortho, classes, sun, _cfg())
    assert sum(r.height_source == "shadow" for r in rocks) == 20
    (big,) = [r for r in rocks if r.height_source == "footprint"]
    assert big.kind == "mass" and abs(big.height - 2.0) <= 0.4


def test_mass_outline_excludes_far_shadow():
    # U-shaped outcrop open to the north; the base casts a 12 m shadow into the U. Shadow more
    # than 2 m from the rock is ground, not part of the mass outline.
    sun = Sun(180.0, 45.0)
    base = _rect(-10.0, 8.0, 10.0, 11.0)
    arms = _rect(-10.0, -10.0, -7.0, 8.0) | _rect(7.0, -10.0, 10.0, 8.0)
    ortho, classes = _scene([(base, 12.0), (arms, 2.0)], sun)
    (m,) = detect_rocks(ortho, classes, sun, _cfg())
    assert m.kind == "mass"
    assert _inside(m.outline, -8.5, 0.0) and _inside(m.outline, 0.0, 9.5)
    assert not _inside(m.outline, 0.0, -2.0)
    assert _inside(m.outline, 0.0, 7.0)  # within 2 m of the base: shaded rock foot


def test_group_pieces_beyond_bridge_are_all_kept():
    # A 4 x 4 m rock whose 7 m shadow reaches another rock 6 m north of it: one shadow group,
    # but the shadow between them is mostly > mass_bridge_m from rock. Neither may be lost.
    sun = Sun(180.0, 45.0)
    a = _rect(-2.0, 4.0, 2.0, 8.0)
    b = _rect(-2.0, -6.0, 2.0, -2.0)
    ortho, classes = _scene([(a, 7.0), (b, 2.0)], sun)
    rocks = sorted(detect_rocks(ortho, classes, sun, _cfg()), key=lambda r: r.z)
    assert len(rocks) == 2
    assert abs(rocks[0].z + 4.0) <= 0.5 and abs(rocks[1].z - 6.0) <= 0.5
    assert all(abs(r.length - 4.0) <= 0.6 and abs(r.width - 4.0) <= 0.6 for r in rocks)


# --- invariants (Ruling 16) -----------------------------------------------------------------


def _rock(rid, x=0.0, z=0.0, length=3.0, width=2.0, yaw=30.0, **kw):
    return Rock(id=rid, x=x, z=z, length=length, width=width, yaw_deg=yaw, height=1.0,
                kind="boulder", **kw)


def test_length_never_below_width():
    r = _rock("a", length=2.0, width=5.0, yaw=30.0)
    assert (r.length, r.width) == (5.0, 2.0)
    assert r.yaw_deg == pytest.approx(120.0)
    r = _rock("b", length=2.0, width=5.0, yaw=150.0)
    assert r.yaw_deg == pytest.approx(60.0)
    # a change through merge is normalised too
    merged = merge([_rock("c")], Edits(changed={"c": {"width": 9.0}}))
    assert (merged[0].length, merged[0].width) == (9.0, 3.0)
    assert merged[0].yaw_deg == pytest.approx(120.0)


def test_merge_rejects_source_change():
    with pytest.raises(ValueError, match="source"):
        merge([_rock("a")], Edits(changed={"a": {"source": "detected"}}))


def test_added_id_collision_gets_fresh_id():
    det = [_rock("same", x=1.0)]
    added = [_rock("same", x=50.0, source="edit"), _rock("same", x=60.0, source="edit")]
    merged = merge(det, Edits(added=added))
    assert len(merged) == 3
    assert len({r.id for r in merged}) == 3
    assert next(r for r in merged if r.x == 1.0).id == "same"
    # deterministic
    assert [r.id for r in merge(det, Edits(added=added))] == [r.id for r in merged]


# --- Ruling 27: the class map agrees with the corrected rock list -------------------------------


def _reclass(classes, detected, edits):
    from replica.rocks import reconcile_classes

    return reconcile_classes(classes, detected, merge(detected, edits), edits, MPP)


def test_deleted_rock_pixels_take_the_surrounding_class():
    classes = np.full((N, N), C.SCRUB, np.uint8)
    classes[_rect(-40, -40, 40, -30)] = C.GRASS  # far: outside the ring
    gone = _rect(-12, -2, -4, 4)  # 8 x 6 m rock, deleted
    kept = _rect(10, -3, 16, 3)  # 6 x 6 m rock, kept
    classes[gone | kept] = C.ROCK
    detected = [_rock("gone", x=-8.0, z=1.0, length=8.0, width=6.0, yaw=90.0),
                _rock("kept", x=13.0, z=0.0, length=6.0, width=6.0, yaw=0.0)]
    out, stats = _reclass(classes, detected, Edits(deleted={"gone"}))
    assert (out[gone] == C.SCRUB).all()  # dominant non-rock class around it
    assert (out[kept] == C.ROCK).all()
    assert (out[~(gone | kept)] == classes[~(gone | kept)]).all()  # nothing else changes
    assert stats["reclassified_px"] == int(gone.sum())
    assert classes[gone].tolist().count(C.ROCK) == gone.sum()  # input not modified


def test_deleted_rock_ring_vote_ignores_rock_and_unknown():
    classes = np.full((N, N), C.SAND, np.uint8)
    gone = _rect(-4, -4, 4, 4)
    ring = _rect(-8, -8, 8, 8) & ~gone
    classes[ring] = C.GRASS
    classes[_rect(-8, -8, 8, -5)] = C.UNKNOWN  # big but not a candidate
    classes[_rect(4, -4, 8, 4)] = C.ROCK  # rock next to it, not in any rock
    classes[gone] = C.ROCK
    detected = [_rock("gone", x=0.0, z=0.0, length=8.0, width=8.0, yaw=0.0)]
    out, _ = _reclass(classes, detected, Edits(deleted={"gone"}))
    assert (out[gone] == C.GRASS).all()


def test_deleted_rock_overlapping_a_kept_rock_keeps_its_pixels():
    classes = np.full((N, N), C.GRASS, np.uint8)
    both = _rect(-10, -3, 10, 3)
    classes[both] = C.ROCK
    detected = [_rock("gone", x=-5.0, z=0.0, length=10.0, width=6.0, yaw=90.0),
                _rock("kept", x=5.0, z=0.0, length=10.0, width=6.0, yaw=90.0)]
    out, _ = _reclass(classes, detected, Edits(deleted={"gone"}))
    assert (out[_rect(0.5, -3, 10, 3)] == C.ROCK).all()
    assert (out[_rect(-10, -3, -1, 3)] == C.GRASS).all()


def test_deleted_mass_outline_is_reclassified():
    classes = np.full((N, N), C.SCRUB, np.uint8)
    blob = _rect(-20, -10, 0, 0) | _rect(-20, 0, -10, 10)  # an L of rock
    classes[blob] = C.ROCK
    mass = Rock(id="m", x=-12.0, z=-2.0, length=20.0, width=20.0, yaw_deg=0.0, height=3.0,
                kind="mass", outline=[[-20, -10], [0, -10], [0, 0], [-10, 0], [-10, 10],
                                      [-20, 10]])
    out, _ = _reclass(classes, [mass], Edits(deleted={"m"}))
    assert (out == C.SCRUB).all()


def test_added_rock_is_painted_rock():
    classes = np.full((N, N), C.GRASS, np.uint8)
    added = _rock("new", x=5.0, z=-5.0, length=8.0, width=4.0, yaw=90.0, source="edit")
    out, stats = _reclass(classes, [], Edits(added=[added]))
    assert out[_xz_rc_int(5.0, -5.0)] == C.ROCK  # centre
    assert out[_xz_rc_int(8.5, -5.0)] == C.ROCK  # along the long axis (E-W, yaw 90)
    assert out[_xz_rc_int(5.0, -8.5)] == C.GRASS  # beyond the half width
    area = math.pi * 4.0 * 2.0 / (MPP * MPP)  # an ellipse, as the boulder is drawn
    assert abs(stats["painted_px"] - area) / area < 0.1
    assert int((out == C.ROCK).sum()) == stats["painted_px"]


def test_changed_rock_frees_the_area_it_left():
    classes = np.full((N, N), C.GRASS, np.uint8)
    classes[_rect(-10, -3, 10, 3)] = C.ROCK
    detected = [_rock("r", x=0.0, z=0.0, length=20.0, width=6.0, yaw=90.0)]
    edits = Edits(changed={"r": {"x": -5.0, "length": 10.0}})  # shrunk to its west half
    out, _ = _reclass(classes, detected, edits)
    assert (out[_rect(-10, -3, -0.5, 3)] == C.ROCK).all()
    assert (out[_rect(1, -3, 10, 3)] == C.GRASS).all()


def test_no_edits_no_change():
    classes = np.full((N, N), C.GRASS, np.uint8)
    classes[_rect(-5, -5, 5, 5)] = C.ROCK
    detected = [_rock("a", x=0.0, z=0.0, length=10.0, width=10.0, yaw=0.0)]
    out, stats = _reclass(classes, detected, Edits())
    assert (out == classes).all()
    assert stats == {"reclassified_px": 0, "painted_px": 0}


def _xz_rc_int(x, z):
    r, c = _xz_to_rc(x, z)
    return int(round(r)), int(round(c))


def test_class_override_wins_over_rock_edits(tmp_path):
    """classes_override.png pixels win everywhere (docs/TERRAIN_REPLICA.md), also inside a
    deleted rock's footprint, which reconcile_classes would otherwise reclassify."""
    from replica.rocks import write_site_rocks

    ortho, classes, sun = _three_boulders()
    cfg = dataclasses.replace(_cfg(), build_dir=tmp_path / "build", edits_dir=tmp_path / "edits",
                              sun={"azimuth_deg": sun.azimuth_deg, "elevation_deg": sun.elevation_deg})
    cfg.build_dir.mkdir()
    cfg.edits_dir.mkdir()
    Image.fromarray(ortho).save(cfg.build_dir / "ortho.png")
    Image.fromarray(classes, mode="L").save(cfg.build_dir / "classes_full.png")
    detected = detect_rocks(ortho, classes, sun, cfg)
    gone = min(detected, key=lambda r: r.x)  # the boulder at x -20..-17
    write_edits(cfg.edits_dir / "rocks_edits.json", Edits(deleted={gone.id}))
    ov = np.zeros((N, N), np.uint8)
    inside = _xz_rc_int(gone.x, gone.z)
    ov[inside] = C.SAND  # hand-painted inside the deleted footprint
    Image.fromarray(ov, mode="L").save(cfg.edits_dir / "classes_override.png")

    write_site_rocks(cfg)

    with Image.open(cfg.build_dir / "classes_full.png") as im:
        out = np.asarray(im)
    assert out[inside] == C.SAND
    # The rest of the deleted footprint is still reclassified (the edit itself is honoured).
    r, c = _xz_rc_int(gone.x + 1.0, gone.z)
    assert out[r, c] != C.ROCK
