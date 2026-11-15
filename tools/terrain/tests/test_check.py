import json
import math

import numpy as np
from PIL import Image

from replica import check as K
from replica.classify import GRASS, ROCK, SAND

MPP = 0.5
N = 400  # 200 x 200 m synthetic scene


def _rocks_mask():
    """Elliptical rocks 3-12 m across, 40 m apart (far more than the search radius)."""
    rr, cc = np.mgrid[0:N, 0:N]
    mask = np.zeros((N, N), bool)
    sizes = [(3.0, 3.0), (6.0, 4.0), (12.0, 7.0), (8.0, 8.0), (4.5, 3.5), (10.0, 5.0)]
    k = 0
    for r0 in range(40, N - 40, 80):
        for c0 in range(40, N - 40, 80):
            a, b = sizes[k % len(sizes)]
            k += 1
            mask |= ((rr - r0) / (a / MPP / 2)) ** 2 + ((cc - c0) / (b / MPP / 2)) ** 2 <= 1.0
    return mask


def test_check_identical_masks():
    ref = _rocks_mask()
    res = K.compare(ref, ref.copy(), MPP)
    assert res["iou"] == 1.0
    assert res["rocks"] == 16
    assert res["matched"] == 16
    assert res["median_offset_m"] == 0.0
    assert res["mean_dx_m"] == 0.0 and res["mean_dz_m"] == 0.0


def test_check_shifted():
    ref = _rocks_mask()
    got = np.roll(ref, 10, axis=1)  # 10 px = 5 m east (+x)
    res = K.compare(ref, got, MPP)
    assert abs(res["median_offset_m"] - 5.0) <= 0.5
    # The direction is reported, so a frame / axis bug shows as a consistent mean offset.
    assert abs(res["mean_dx_m"] - 5.0) <= 0.5
    assert abs(res["mean_dz_m"]) <= 0.5
    assert res["iou"] < 0.5


def test_small_rocks_not_traced():
    """Rocks under 3 m across take part in the IoU but get no centroid offset."""
    ref = np.zeros((N, N), bool)
    ref[100:104, 100:104] = True  # 2 m
    ref[200:220, 200:220] = True  # 10 m
    res = K.compare(ref, ref.copy(), MPP)
    assert res["rocks"] == 1


def test_topdown_rock_mask_by_colour():
    img = np.zeros((4, 4, 3), np.uint8)
    img[...] = (128, 115, 89)  # a ground colour
    img[1, 2] = K.CAPTURE_ROCK_RGB
    img[3, 0] = (250, 5, 252)  # within tolerance (8-bit rounding)
    mask = K.topdown_rock_mask(img)
    assert mask.sum() == 2 and mask[1, 2] and mask[3, 0]


def test_check_site_passes_and_fails(tmp_path):
    ref = _rocks_mask()
    classes = np.where(ref, ROCK, SAND).astype(np.uint8)
    classes[:50] = GRASS
    classes[:50][ref[:50]] = ROCK
    build = tmp_path / "build"
    build.mkdir()
    Image.fromarray(classes).save(build / "classes_full.png")
    top = np.zeros((N, N, 3), np.uint8)
    top[...] = (128, 115, 89)
    top[ref] = K.CAPTURE_ROCK_RGB
    Image.fromarray(top).save(build / "topdown.png")
    assert K.check_site(tmp_path) == 0
    res = json.loads((build / "check.json").read_text(encoding="utf-8"))
    assert res["iou"] == 1.0 and res["pass"]
    top = np.roll(top, 10, axis=1)
    Image.fromarray(top).save(build / "topdown.png")
    assert K.check_site(tmp_path) == 1


def test_iou_rocklist_ignores_specks():
    """Ruling 29: IoU (b) counts only ROCK components of rock-list size (footprint >= the 2 m
    detection minimum); specks are rule-fill territory."""
    ref = np.zeros((N, N), bool)
    ref[100:120, 100:116] = True  # 10 x 8 m rock
    for k in range(10):
        ref[300 + 2 * k, 50 + 6 * k] = True  # 0.5 m specks
        ref[200:202, 300 + 6 * k:302 + 6 * k] = True  # 1 m specks
    got = np.zeros((N, N), bool)
    got[100:120, 100:116] = True
    res = K.compare(ref, got, MPP)
    assert res["iou"] < 1.0
    assert res["iou_rocklist"] == 1.0
    assert res["rocklist_px"] == 20 * 16


def test_footprint_of_component():
    """sqrt(length x width) along the principal axes, as rock detection measures it."""
    blob = np.zeros((40, 40), bool)
    blob[10:14, 5:25] = True  # 2 m x 10 m
    assert abs(K.footprint_m(blob, MPP) - math.sqrt(2.0 * 10.0)) < 0.3
    speck = np.zeros((10, 10), bool)
    speck[2:5, 2:5] = True  # 1.5 m square
    assert abs(K.footprint_m(speck, MPP) - 1.5) < 0.01


def test_outline_coverage():
    """Ruling 28: share of the mass outlines (rocks_placed.json) the render covers."""
    base = {"id": "a", "x": 0.0, "z": 0.0, "length": 20.0, "width": 20.0, "yaw_deg": 0.0,
            "height": 3.0}
    rocks = [{**base, "kind": "mass", "outline": [[-10, -10], [10, -10], [10, 10], [-10, 10]]},
             {**base, "id": "b", "x": 60.0, "length": 4.0, "width": 4.0, "kind": "boulder"}]
    got = np.zeros((N, N), bool)  # 200 m scene centred on 0: pixel 200 is x = 0
    got[180:220, 180:200] = True  # west half of the mass
    cov = K.outline_coverage(rocks, got, MPP)
    assert abs(cov - 0.5) < 0.01


def test_check_site_nothing_matched_writes_null(tmp_path):
    """No traced rock has rendered rock within the search radius: the offset fields are JSON
    null (json.dumps would write bare NaN, which is not JSON), and the check fails."""
    ref = _rocks_mask()
    build = tmp_path / "build"
    build.mkdir()
    Image.fromarray(np.where(ref, ROCK, SAND).astype(np.uint8)).save(build / "classes_full.png")
    top = np.zeros((N, N, 3), np.uint8)
    top[...] = (128, 115, 89)  # nothing rendered
    Image.fromarray(top).save(build / "topdown.png")
    assert K.check_site(tmp_path) == 1
    text = (build / "check.json").read_text(encoding="utf-8")
    assert "NaN" not in text
    res = json.loads(text)
    assert res["matched"] == 0 and not res["pass"]
    for key in ("median_offset_m", "p90_offset_m", "mean_dx_m", "mean_dz_m"):
        assert res[key] is None
