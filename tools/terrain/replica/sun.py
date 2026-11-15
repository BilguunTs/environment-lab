"""Sun direction for the imagery: manual, or measured from calibration objects' shadows.

Azimuth is clockwise from north and names the direction the sun is *in*.
Local frame: +x east, +z south (north is -z).

Limitation of the calibration path: a ger's far shadow tip is cast by the anti-sun wall top
(~1.5 m high at r ~3.3 m from the centre), not by the 2.4 m crown, so using the crown height
with the centre-to-tip length under-reads the elevation. Prefer a manual sun from imagery
metadata when it exists (site.json "sun" + "sun_source"); the calibration items are kept as
an azimuth cross-check.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from .site import SiteConfig


@dataclass(frozen=True)
class Sun:
    azimuth_deg: float
    elevation_deg: float

    def shadow_dir_xz(self) -> tuple[float, float]:
        """Unit ground vector (dx, dz) along which shadows fall (pointing away from the sun)."""
        a = math.radians(self.azimuth_deg)
        return -math.sin(a), math.cos(a)

    def shadow_length(self, height_m: float) -> float:
        """Ground length of the shadow cast by a point height_m above flat ground."""
        return height_m / math.tan(math.radians(self.elevation_deg))


def _from_calibration(items: list[dict]) -> Sun:
    """Circular mean of the shadow azimuths; mean of the per-object elevations."""
    sx = sz = 0.0
    elevations = []
    for it in items:
        vx = float(it["shadow_tip_x"]) - float(it["x"])
        vz = float(it["shadow_tip_z"]) - float(it["z"])
        length = math.hypot(vx, vz)
        if length <= 0.0:
            raise ValueError(f"calibration item has zero-length shadow: {it}")
        sx += vx / length
        sz += vz / length
        elevations.append(math.degrees(math.atan2(float(it["height_m"]), length)))
    # Shadow points along (vx, vz); east = +x, north = -z.
    shadow_az = math.degrees(math.atan2(sx, -sz))
    return Sun((shadow_az + 180.0) % 360.0, sum(elevations) / len(elevations))


def sun_from_site(cfg: SiteConfig) -> Sun:
    """Manual cfg.sun wins; else averaged from cfg.calibration; else ValueError."""
    if cfg.sun:
        return Sun(float(cfg.sun["azimuth_deg"]), float(cfg.sun["elevation_deg"]))
    if cfg.calibration:
        return _from_calibration(cfg.calibration)
    raise ValueError("no sun: add calibration objects or a manual sun")
