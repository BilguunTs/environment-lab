import numpy as np

from replica.geo import LocalFrame, tile_bounds, tile_xy

F = LocalFrame(46.252564, 108.779433)


def test_origin():
    assert np.allclose(F.to_local(46.252564, 108.779433), (0, 0), atol=1e-6)


def test_north_is_negative_z():
    x, z = F.to_local(46.252564 + 0.01, 108.779433)
    assert abs(x) < 0.01 and -1113 < z < -1110


def test_east_is_positive_x():
    x, z = F.to_local(46.252564, 108.779433 + 0.01)
    assert 769 < x < 772 and abs(z) < 0.5


def test_roundtrip_10km():
    lat, lon = F.to_latlon(7000.0, -7000.0)
    x, z = F.to_local(lat, lon)
    assert abs(x - 7000) < 0.05 and abs(z + 7000) < 0.05


def test_broadcast():
    lats = np.array([46.25, 46.26])
    lons = np.array([108.77, 108.78])
    x, z = F.to_local(lats, lons)
    assert x.shape == (2,) and z.shape == (2,)


def test_tile_xy_matches_recon():
    # recon: z17 tile x=105141, y=46497
    tx, ty = tile_xy(46.252564, 108.779433, 17)
    assert int(tx) == 105141 and int(ty) == 46497


def test_tile_bounds_contains_point():
    lat_n, lon_w, lat_s, lon_e = tile_bounds(105141, 46497, 17)
    assert lat_s < 46.252564 < lat_n and lon_w < 108.779433 < lon_e
