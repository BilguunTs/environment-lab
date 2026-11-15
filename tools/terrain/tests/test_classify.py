import dataclasses
from pathlib import Path

import numpy as np
import pytest
from PIL import Image
from scipy import ndimage as ndi

from replica import classify as C
from replica.classify import apply_overrides, classify
from replica.site import SiteConfig

SUMBER = Path(__file__).resolve().parents[3] / "data" / "sites" / "sumber"
ORTHO = SUMBER / "build" / "ortho.png"
N = 240


def _cfg():
    # Sun due south, 30 deg up: shadows fall north (towards row 0).
    return dataclasses.replace(
        SiteConfig.load(SUMBER), sun={"azimuth_deg": 180.0, "elevation_deg": 30.0}
    )


def _disc(cy, cx, r):
    yy, xx = np.mgrid[:N, :N]
    return (yy - cy) ** 2 + (xx - cx) ** 2 <= r * r


def _scene():
    """Tan sand, one grey textured granite blob with its shadow north of it, two scrub patches."""
    rng = np.random.default_rng(7)
    img = np.empty((N, N, 3), np.float32)
    img[:] = (150, 136, 106)
    img += rng.normal(0, 1.5, (N, N, 1))

    rock = _disc(170, 70, 30)
    shadow = np.roll(rock, -14, axis=0) & ~rock
    blocks = rng.uniform(95, 175, (N // 4, N // 4)).repeat(4, 0).repeat(4, 1)
    grey = np.stack([blocks - 4, blocks + 6, blocks], axis=-1)
    img[rock] = grey[rock]
    img[shadow] = (45, 60, 55)

    scrub = np.zeros((N, N), bool)
    scrub[20:80, 140:220] = True
    scrub[150:220, 150:220] = True
    speckle = rng.normal(0, 8, (N // 2, N // 2)).repeat(2, 0).repeat(2, 1)[..., None]
    img[scrub] = (np.array([70, 80, 62], np.float32) + speckle)[scrub]
    img = np.clip(np.rint(img), 0, 255).astype(np.uint8)
    return img, rock, shadow, scrub


def _frac(classes, mask, cls):
    return float((classes[mask] == cls).mean())


def test_class_ids():
    assert (C.UNKNOWN, C.ROCK, C.SAND, C.GRASS, C.SCRUB, C.CHANNEL, C.TRACK, C.STRUCTURE) == (
        0, 1, 2, 3, 4, 5, 6, 7,
    )
    assert C.CLASS_IDS["rock"] == 1 and C.CLASS_IDS["structure"] == 7


def test_classify_synthetic():
    img, rock, shadow, scrub = _scene()
    classes = classify(img, _cfg())
    assert classes.shape == (N, N) and classes.dtype == np.uint8
    near = ndi.binary_dilation(rock | shadow | scrub, iterations=8)
    border = np.zeros((N, N), bool)
    border[8:-8, 8:-8] = True
    sand = ~near & border
    assert _frac(classes, ndi.binary_erosion(rock, iterations=3), C.ROCK) >= 0.9
    assert _frac(classes, sand, C.SAND) >= 0.9
    assert _frac(classes, ndi.binary_erosion(scrub, iterations=3), C.SCRUB) >= 0.9


def test_classify_lines():
    """Thin dark line in sand -> CHANNEL, long thin light line -> TRACK."""
    rng = np.random.default_rng(3)
    img = np.empty((N, N, 3), np.float32)
    img[:] = (150, 136, 106)
    img += rng.normal(0, 1.5, (N, N, 1))
    yy, xx = np.mgrid[:N, :N]
    chan = np.abs((yy - 0.6 * xx) - 40) <= 1.5  # ~3 px wide, diagonal
    track = np.abs(xx - 170) <= 1  # 3 px wide, full height
    img[chan] = (112, 106, 86)
    img[track] = (182, 170, 140)
    img = np.clip(np.rint(img), 0, 255).astype(np.uint8)
    classes = classify(img, _cfg())
    inner = np.zeros((N, N), bool)
    inner[10:-10, 10:-10] = True
    assert _frac(classes, chan & inner, C.CHANNEL) >= 0.8
    assert _frac(classes, track & inner, C.TRACK) >= 0.8
    far = ~ndi.binary_dilation(chan | track, iterations=6) & inner
    assert _frac(classes, far, C.SAND) >= 0.95


def test_override_replaces(tmp_path):
    classes = np.full((50, 60), C.SAND, np.uint8)
    ov = np.zeros((50, 60), np.uint8)
    ov[10:20, 5:15] = C.STRUCTURE
    ov[30, 40] = C.ROCK
    path = tmp_path / "ov.png"
    Image.fromarray(ov, mode="L").save(path)
    out = apply_overrides(classes, path)
    assert (out[10:20, 5:15] == C.STRUCTURE).all()
    assert out[30, 40] == C.ROCK
    assert (out[ov == 0] == C.SAND).all()
    assert (classes == C.SAND).all()  # input untouched


def test_override_palette_and_missing(tmp_path):
    classes = np.full((8, 8), C.GRASS, np.uint8)
    ov = Image.new("P", (8, 8), 0)
    ov.putpalette([0, 0, 0, 255, 0, 0, 0, 255, 0] + [0] * (256 * 3 - 9))
    ov.putpixel((2, 3), C.TRACK)
    path = tmp_path / "ov.png"
    ov.save(path)
    out = apply_overrides(classes, path)
    assert out[3, 2] == C.TRACK and (out == C.GRASS).sum() == 63
    # Missing override file: no change.
    assert (apply_overrides(classes, tmp_path / "none.png") == classes).all()


def test_override_size_mismatch(tmp_path):
    path = tmp_path / "ov.png"
    Image.fromarray(np.zeros((4, 4), np.uint8), mode="L").save(path)
    with pytest.raises(ValueError, match="size"):
        apply_overrides(np.zeros((8, 8), np.uint8), path)


def _site(f):
    f = pytest.mark.skipif(not ORTHO.exists(), reason="real ortho missing (build/ortho.png)")(f)
    return pytest.mark.site(f)


@_site
def test_real_site_spots():
    """Known spots on the real Sumber ortho (pixel col, row), checked by eye on crops."""
    cfg = SiteConfig.load(SUMBER)
    img = np.asarray(Image.open(ORTHO).convert("RGB"))
    classes = apply_overrides(classify(img, cfg), cfg.edits_dir / "classes_override.png")
    # Gers (painted STRUCTURE in the override).
    assert classes[1778, 1744] == C.STRUCTURE and classes[1806, 1763] == C.STRUCTURE
    # Open sand of the main valley floor.
    assert _frac(classes, np.s_[2820:2880, 2220:2280], C.SAND) >= 0.8
    # Granite slabs on the northern hill.
    assert _frac(classes, np.s_[960:1040, 1640:1700], C.ROCK) >= 0.6
    # Dense scrub on the dark north-west slope.
    assert _frac(classes, np.s_[640:740, 1060:1140], C.SCRUB) >= 0.6
