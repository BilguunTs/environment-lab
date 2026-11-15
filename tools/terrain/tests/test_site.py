import json
from pathlib import Path

import pytest

from replica.site import SiteConfig

SUMBER = Path(__file__).resolve().parents[3] / "data" / "sites" / "sumber"


def test_load_sumber():
    s = SiteConfig.load(SUMBER)
    assert s.core_m == 2000
    assert s.core_step_m == 1.0
    assert s.ring_m == 20000
    assert s.ring_step_m == 30.0
    assert s.imagery_zoom == 17
    assert s.ortho_m_per_px == 0.5
    assert s.rules == "steppe_granite"
    assert s.sun == {"azimuth_deg": 159.0, "elevation_deg": 28.5}
    assert s.sun_source.startswith("Esri metadata: WorldView-2 2023-10-28")
    assert len(s.calibration) == 2 and all(c["height_m"] == 2.4 for c in s.calibration)
    assert [st["type"] for st in s.structures] == ["ger", "ger"]
    assert all(5.5 <= st["diameter_m"] <= 7.1 for st in s.structures)
    assert s.cache_dir == SUMBER / "cache"
    assert s.build_dir == SUMBER / "build"
    assert s.edits_dir == SUMBER / "edits"


def test_missing_key_raises(tmp_path):
    data = json.loads((SUMBER / "site.json").read_text())
    del data["core_m"]
    (tmp_path / "site.json").write_text(json.dumps(data))
    with pytest.raises(ValueError, match="core_m"):
        SiteConfig.load(tmp_path)


def test_structures_default_empty(tmp_path):
    data = json.loads((SUMBER / "site.json").read_text())
    data.pop("structures", None)
    (tmp_path / "site.json").write_text(json.dumps(data))
    assert SiteConfig.load(tmp_path).structures == []


def test_sun_source_default_none(tmp_path):
    data = json.loads((SUMBER / "site.json").read_text())
    data.pop("sun_source", None)
    (tmp_path / "site.json").write_text(json.dumps(data))
    assert SiteConfig.load(tmp_path).sun_source is None
