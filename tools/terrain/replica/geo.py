"""Local tangent frame (1 unit = 1 m) and web-mercator tile maths."""
from __future__ import annotations

import math

import numpy as np

# WGS84 ellipsoid.
WGS84_A = 6378137.0
WGS84_E2 = 6.69437999014e-3


class LocalFrame:
    """Equirectangular frame (WGS84 local radii) about (lat0, lon0): +x east, +z south, metres.

    Matches Godot's axes (north is -z). The east-west scale is fixed at lat0, so x drifts by
    about 0.16 % at +-10 km north/south of the origin: ~0.16 m at the 2 km core's corners,
    ~16 m at the 20 km ring's corners (Ruling 8, accepted: the DEM and the imagery are both
    sampled through this same frame). to_latlon is the exact inverse of to_local.
    """

    def __init__(self, lat0: float, lon0: float) -> None:
        self.lat0 = float(lat0)
        self.lon0 = float(lon0)
        phi = math.radians(self.lat0)
        w = math.sqrt(1.0 - WGS84_E2 * math.sin(phi) ** 2)
        radius_meridian = WGS84_A * (1.0 - WGS84_E2) / w**3
        radius_prime_vertical = WGS84_A / w
        self._m_per_deg_lat = math.radians(1.0) * radius_meridian
        self._m_per_deg_lon = math.radians(1.0) * radius_prime_vertical * math.cos(phi)

    def to_local(self, lat, lon):
        lat = np.asarray(lat, dtype=np.float64)
        lon = np.asarray(lon, dtype=np.float64)
        x = (lon - self.lon0) * self._m_per_deg_lon
        z = -(lat - self.lat0) * self._m_per_deg_lat
        return x, z

    def to_latlon(self, x, z):
        x = np.asarray(x, dtype=np.float64)
        z = np.asarray(z, dtype=np.float64)
        lat = self.lat0 - z / self._m_per_deg_lat
        lon = self.lon0 + x / self._m_per_deg_lon
        return lat, lon


def tile_xy(lat: float, lon: float, zoom: int) -> tuple[float, float]:
    """Fractional web-mercator (slippy map) tile coordinates."""
    n = 2.0**zoom
    lat_r = math.radians(lat)
    tx = (lon + 180.0) / 360.0 * n
    ty = (1.0 - math.asinh(math.tan(lat_r)) / math.pi) / 2.0 * n
    return tx, ty


def _tile_corner(tx: float, ty: float, zoom: int) -> tuple[float, float]:
    n = 2.0**zoom
    lon = tx / n * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1.0 - 2.0 * ty / n))))
    return lat, lon


def tile_bounds(tx: int, ty: int, zoom: int) -> tuple[float, float, float, float]:
    """(lat_n, lon_w, lat_s, lon_e) of tile (tx, ty)."""
    lat_n, lon_w = _tile_corner(tx, ty, zoom)
    lat_s, lon_e = _tile_corner(tx + 1, ty + 1, zoom)
    return lat_n, lon_w, lat_s, lon_e
