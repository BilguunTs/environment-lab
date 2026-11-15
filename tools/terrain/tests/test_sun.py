import dataclasses
from pathlib import Path

import pytest

from replica.site import SiteConfig
from replica.sun import Sun, sun_from_site

SUMBER = Path(__file__).resolve().parents[3] / "data" / "sites" / "sumber"


def _cfg(**kw):
    return dataclasses.replace(SiteConfig.load(SUMBER), **kw)


def test_sun_manual_wins():
    cal = [{"x": 0, "z": 0, "height_m": 2.4, "shadow_tip_x": 0, "shadow_tip_z": -4}]
    s = sun_from_site(_cfg(sun={"azimuth_deg": 135.0, "elevation_deg": 40.0}, calibration=cal))
    assert s == Sun(135.0, 40.0)


def test_sun_from_calibration():
    # 2.4 m object, shadow tip 4.0 m due north (-z) -> sun due south, atan(2.4/4).
    cal = [{"x": 10, "z": 5, "height_m": 2.4, "shadow_tip_x": 10, "shadow_tip_z": 1}]
    s = sun_from_site(_cfg(sun=None, calibration=cal))
    assert s.azimuth_deg == pytest.approx(180.0, abs=1e-6)
    assert s.elevation_deg == pytest.approx(30.96, abs=0.01)


def test_sun_calibration_averaged():
    # Shadows pointing north-west and north-east average to north -> sun due south.
    cal = [
        {"x": 0, "z": 0, "height_m": 2.0, "shadow_tip_x": -2, "shadow_tip_z": -2},
        {"x": 0, "z": 0, "height_m": 4.0, "shadow_tip_x": 2, "shadow_tip_z": -2},
    ]
    s = sun_from_site(_cfg(sun=None, calibration=cal))
    assert s.azimuth_deg == pytest.approx(180.0, abs=1e-6)
    assert 30.0 < s.elevation_deg < 60.0


def test_sun_azimuth_east():
    # Shadow pointing west (-x) -> sun in the east (90 deg).
    cal = [{"x": 0, "z": 0, "height_m": 1.0, "shadow_tip_x": -1, "shadow_tip_z": 0}]
    s = sun_from_site(_cfg(sun=None, calibration=cal))
    assert s.azimuth_deg == pytest.approx(90.0, abs=1e-6)
    assert s.elevation_deg == pytest.approx(45.0, abs=1e-6)


def test_shadow_direction():
    # Sun in the south-east: shadows fall to the north-west (-x, -z).
    dx, dz = Sun(135.0, 30.0).shadow_dir_xz()
    assert dx < 0 and dz < 0
    assert dx * dx + dz * dz == pytest.approx(1.0)


def test_no_sun_raises():
    with pytest.raises(ValueError, match="no sun: add calibration objects or a manual sun"):
        sun_from_site(_cfg(sun=None, calibration=[]))
