"""Site configuration (data/sites/<site>/site.json)."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

_REQUIRED = (
    "name", "lat", "lon", "core_m", "core_step_m", "ring_m", "ring_step_m",
    "ortho_m_per_px", "imagery_zoom", "rules", "sun", "calibration",
)


@dataclass
class SiteConfig:
    name: str
    lat: float
    lon: float
    core_m: float
    core_step_m: float
    ring_m: float
    ring_step_m: float
    ortho_m_per_px: float
    imagery_zoom: int
    rules: str
    sun: dict | None
    calibration: list[dict]
    site_dir: Path
    cache_dir: Path
    build_dir: Path
    edits_dir: Path
    # Measured man-made objects, e.g. {"type": "ger", "x": .., "z": .., "diameter_m": ..}.
    structures: list[dict] = field(default_factory=list)
    # Free-text provenance of a manual sun (e.g. imagery metadata), or None.
    sun_source: str | None = None

    @classmethod
    def load(cls, site_dir: Path) -> "SiteConfig":
        site_dir = Path(site_dir)
        data = json.loads((site_dir / "site.json").read_text(encoding="utf-8"))
        for key in _REQUIRED:
            if key not in data:
                raise ValueError(f"site.json missing required key: {key}")
        return cls(
            name=str(data["name"]),
            lat=float(data["lat"]),
            lon=float(data["lon"]),
            core_m=float(data["core_m"]),
            core_step_m=float(data["core_step_m"]),
            ring_m=float(data["ring_m"]),
            ring_step_m=float(data["ring_step_m"]),
            ortho_m_per_px=float(data["ortho_m_per_px"]),
            imagery_zoom=int(data["imagery_zoom"]),
            rules=str(data["rules"]),
            sun=data["sun"],
            calibration=list(data["calibration"]),
            site_dir=site_dir,
            cache_dir=site_dir / "cache",
            build_dir=site_dir / "build",
            edits_dir=site_dir / "edits",
            structures=list(data.get("structures", [])),
            sun_source=data.get("sun_source"),
        )
