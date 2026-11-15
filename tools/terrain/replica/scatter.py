"""Rule fill: what the photo cannot resolve (rocks < ~2 m, shrubs, grass), placed by rules that
follow the traced layout, plus the packing of rock masses.

Every number comes from the rules file (tools/terrain/rules/<site.rules>.json, see its "_why").
The rules only ever *add detail around what the imagery shows*: scree and stones exist only near
traced rock, scrub where the class map has scrub (and sparsely elsewhere), nothing on track,
under rock or at the site structures.

Grid: the core grid of heightmap.py (sample (i, j) at x = -core_m/2 + j*step, z likewise with i;
row 0 north). Densities are evaluated per sample (one sample = one step x step cell):

  scree  D_scree(class) x band(d) x dir           below rock edges, downhill-weighted
  stone  D_stone(class) x max(0, 1 - d / stone_reach_m)
  scrub, tree  D(class) x (1 + near_rock_boost x foot(d)) x (1 + channel_boost x chan(dc))
  grass  (density map, not instances) the same cover formula on relative densities, <= 1

  d = distance (m) to the nearest rock-covered sample, dc = distance to the nearest CHANNEL
  sample; foot = max(0, 1 - d / near_rock_band_m), chan = max(0, 1 - dc / channel_band_m);
  band = max(0, 1 - d / B) with B = clip(scree_band_per_height x source height, scree_band_min_m,
  scree_band_m) (source = the nearest rock; DEM-topped masses use their local thickness);
  dir = (1 - b) + b x max(0, cos(angle between the away-from-rock direction and the fall
  line)), b = downslope_bias x min(1, slope / downslope_full_deg), slope from the ground
  smoothed over slope_smooth_m.

Instances are drawn per tile_m tile (rng seeded by (seed, type, tile): an edit only changes its
own tiles) as clusters: parents ~ Poisson(D / cluster_size) per cell, each with
1 + Poisson(cluster_size - 1) members within cluster_radius_m. A member is kept only where its
own cell has density > 0 (so the class / reach / band limits hold for every instance), its disk
(radius = half the l x w diagonal) clears every rock footprint, and it is structure_clear_m
clear of the structures.

Masses: fill_mass packs a mass outline with pieces whose tops reach the mass top (Ruling 15/18).
"""
from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from scipy import ndimage as ndi

from .classify import CHANNEL, CLASS_IDS, STRUCTURE, TRACK
from .heightmap import (
    _bilinear, _half, base_samples, classes_at_samples, core_n, is_large_mass, rock_base_y,
    rock_top_y, top_samples,
)
from .rocks import Rock
from .site import SiteConfig

INSTANCE_TYPES = ("scree", "stone", "scrub", "tree", "fill_round", "fill_slab")
RULE_TYPES = ("scree", "stone", "scrub", "tree")  # rule_fill; the fill_* types come from masses
FIELDS = ("type", "x", "z", "y", "yaw_deg", "l", "h", "w")
RULES_DIR = Path(__file__).resolve().parents[1] / "rules"

# Rock clearance: a candidate whose nearest sample is farther than its radius + this from every
# rock-covered sample clears all footprints without the exact test (a footprint point is never
# farther than ~one diagonal step from a covered sample of its own footprint).
_EXACT_MARGIN_STEPS = 2.0
# Ellipse footprints are tested as this circumscribed polygon (conservative).
_ELLIPSE_SIDES = 32


@dataclass(frozen=True)
class Instance:
    type: str
    x: float
    z: float
    yaw_deg: float
    size: tuple[float, float, float]  # (l, h, w), l >= w
    # Base height (m) above the local ground = min ground under the l x w footprint
    # (heightmap.rock_base_y); 0 stands on the ground, > 0 rests on a piece below (Ruling 22).
    y: float = 0.0


def load_rules(name: str | Path) -> dict:
    """Rules by name (tools/terrain/rules/<name>.json) or by path."""
    p = Path(name)
    if p.suffix != ".json":
        p = RULES_DIR / f"{name}.json"
    rules = json.loads(p.read_text(encoding="utf-8"))
    for t in RULE_TYPES:
        spec = rules["types"][t]
        for c in spec["density_per_100m2"]:
            if c.lower() not in CLASS_IDS:
                raise ValueError(f"{p}: {t}: unknown class {c!r}")
        if set(spec["size_m"]) != {"l", "h", "w"}:
            raise ValueError(f"{p}: {t}: size_m needs l, h, w")
    return rules


def instance_rock(inst: Instance) -> Rock:
    """The instance as a boulder footprint (to seat it with heightmap.rock_base_y)."""
    l, h, w = inst.size
    return Rock(id="", x=inst.x, z=inst.z, length=l, width=w, yaw_deg=inst.yaw_deg, height=h,
                kind="boulder")


# --- geometry -----------------------------------------------------------------------------------


def _in_poly(poly: np.ndarray, x: np.ndarray, z: np.ndarray) -> np.ndarray:
    inside = np.zeros(np.broadcast(x, z).shape, bool)
    x0, z0 = poly[:, 0], poly[:, 1]
    x1, z1 = np.roll(x0, -1), np.roll(z0, -1)
    for a, b, c, d in zip(x0, z0, x1, z1):
        if b == d:
            continue
        crosses = (b > z) != (d > z)
        xc = a + (z - b) * (c - a) / (d - b)
        inside ^= crosses & (x < xc)
    return inside


def _dist_to_edges(poly: np.ndarray, x: np.ndarray, z: np.ndarray, chunk: int = 4096) -> np.ndarray:
    """Distance from each point to the polygon boundary."""
    a = poly
    b = np.roll(poly, -1, axis=0)
    ab = b - a
    ll = np.maximum((ab * ab).sum(axis=1), 1e-12)
    out = np.empty(x.shape, np.float64)
    for s in range(0, x.size, chunk):
        px, pz = x[s : s + chunk, None], z[s : s + chunk, None]
        t = np.clip(((px - a[:, 0]) * ab[:, 0] + (pz - a[:, 1]) * ab[:, 1]) / ll, 0.0, 1.0)
        dx = px - (a[:, 0] + t * ab[:, 0])
        dz = pz - (a[:, 1] + t * ab[:, 1])
        out[s : s + chunk] = np.sqrt((dx * dx + dz * dz).min(axis=1))
    return out


def _footprint_poly(rock: Rock) -> np.ndarray:
    if rock.kind == "mass" and rock.outline:
        return np.asarray(rock.outline, np.float64)
    k = _ELLIPSE_SIDES
    t = (np.arange(k) + 0.5) * 2 * np.pi / k
    s = 1.0 / math.cos(math.pi / k)  # circumscribes the ellipse
    u, v = np.cos(t) * rock.length / 2 * s, np.sin(t) * rock.width / 2 * s
    y = math.radians(rock.yaw_deg)
    ax, az, bx, bz = math.sin(y), -math.cos(y), math.cos(y), math.sin(y)
    return np.stack([rock.x + u * ax + v * bx, rock.z + u * az + v * bz], axis=1)


def placed_rocks(rocks: list[Rock]) -> list[Rock]:
    """Ruling 19: rocks.json minus the boulders / small masses whose centre lies inside a large
    mass outline (fill_mass covers that area)."""
    large = [np.asarray(r.outline, np.float64) for r in rocks if is_large_mass(r)]
    boxes = [(p[:, 0].min(), p[:, 0].max(), p[:, 1].min(), p[:, 1].max()) for p in large]
    out = []
    for r in rocks:
        if not is_large_mass(r):
            hit = False
            for p, (x0, x1, z0, z1) in zip(large, boxes):
                if x0 <= r.x <= x1 and z0 <= r.z <= z1 and _in_poly(p, np.array(r.x), np.array(r.z)):
                    hit = True
                    break
            if hit:
                continue
        out.append(r)
    return out


# --- per-sample fields ------------------------------------------------------------------------


class _Fields:
    """Everything the rules read per core sample (computed once per site)."""

    def __init__(self, classes, hm, rocks, rules, cfg: SiteConfig, tops=None) -> None:
        self.cfg, self.rules, self.rocks = cfg, rules, list(rocks)
        n, s = core_n(cfg), cfg.core_step_m
        if hm.shape != (n, n):
            raise ValueError(f"heightmap {hm.shape} != core grid {(n, n)}")
        self.n, self.s, self.half = n, s, _half(cfg)
        self.hm = hm.astype(np.float64)
        self.cls = classes_at_samples(classes, cfg)
        axis = -self.half + np.arange(n) * s
        self.X, self.Z = np.meshgrid(axis, axis)

        owner = np.full((n, n), -1, np.int64)
        for k, r in enumerate(self.rocks):
            rr, cc = top_samples(r, cfg)
            owner[rr, cc] = k
        # every rock covers at least the sample nearest its centre, so a footprint smaller
        # than a sample is never invisible to d_rock (and the exact footprint test near it)
        for k, r in enumerate(self.rocks):
            ri, ci = self.sample_index(np.array(r.x), np.array(r.z))
            if owner[ri, ci] < 0:
                owner[ri, ci] = k
        self.covered = owner >= 0
        if self.covered.any():
            d, (ir, ic) = ndi.distance_transform_edt(~self.covered, return_indices=True)
            self.d_rock = d * s
            # source height: rock height, or the DEM-top thickness of a large mass
            per_rock = np.array([r.height for r in self.rocks], np.float64)
            if tops is not None:
                # a large mass sheds like its thick parts: its rim thickness is ~0 by
                # construction (DEM top meets the ground there)
                t = tops.astype(np.float64) - self.hm
                for k, r in enumerate(self.rocks):
                    if is_large_mass(r):
                        tk = t[owner == k]
                        tk = tk[np.isfinite(tk)]
                        if tk.size:
                            per_rock[k] = max(0.0, float(np.percentile(
                                tk, rules["scree_source_percentile"])))
            self.src_h = per_rock[np.maximum(owner, 0)][ir, ic]
            self.src_dx = self.X - self.X[ir, ic]
            self.src_dz = self.Z - self.Z[ir, ic]
        else:
            self.d_rock = np.full((n, n), np.inf)
            self.src_h = np.zeros((n, n))
            self.src_dx = self.src_dz = np.zeros((n, n))

        ch = self.cls == CHANNEL
        self.d_chan = ndi.distance_transform_edt(~ch) * s if ch.any() else np.full((n, n), np.inf)

        # fall line of the ground smoothed over slope_smooth_m
        sm = ndi.gaussian_filter(self.hm, rules["slope_smooth_m"] / s, mode="nearest")
        gz, gx = np.gradient(sm, s)
        g = np.hypot(gx, gz)
        self.down_x = np.where(g > 0, -gx / np.maximum(g, 1e-12), 0.0)
        self.down_z = np.where(g > 0, -gz / np.maximum(g, 1e-12), 0.0)
        self.slope_deg = np.degrees(np.arctan(g))

        # nothing on track, structures, under rock, or within structure_clear_m of a structure
        blocked = self.covered | (self.cls == TRACK) | (self.cls == STRUCTURE)
        for st in cfg.structures:
            rad = float(st["diameter_m"]) / 2.0 + rules["structure_clear_m"]
            blocked |= np.hypot(self.X - float(st["x"]), self.Z - float(st["z"])) <= rad
        self.open = ~blocked

    def class_value(self, table: dict) -> np.ndarray:
        lut = np.zeros(256, np.float64)
        for name, v in table.items():
            lut[CLASS_IDS[name.lower()]] = float(v)
        return lut[self.cls]

    def foot(self) -> np.ndarray:
        return np.clip(1.0 - self.d_rock / self.rules["near_rock_band_m"], 0.0, 1.0)

    def chan(self) -> np.ndarray:
        return np.clip(1.0 - self.d_chan / self.rules["channel_band_m"], 0.0, 1.0)

    def cover(self, table: dict) -> np.ndarray:
        R = self.rules
        return (self.class_value(table) * (1.0 + R["near_rock_boost"] * self.foot())
                * (1.0 + R["channel_boost"] * self.chan()) * self.open)

    def density(self, t: str) -> np.ndarray:
        """Expected instances per sample cell."""
        R = self.rules
        per_cell = self.class_value(R["types"][t]["density_per_100m2"]) * self.s * self.s / 100.0
        if t == "scree":
            band = np.clip(R["scree_band_per_height"] * self.src_h, R["scree_band_min_m"],
                           R["scree_band_m"])
            w_band = np.clip(1.0 - self.d_rock / band, 0.0, 1.0)
            dist = np.maximum(np.hypot(self.src_dx, self.src_dz), 1e-9)
            cos = (self.src_dx * self.down_x + self.src_dz * self.down_z) / dist
            b = R["downslope_bias"] * np.clip(self.slope_deg / R["downslope_full_deg"], 0.0, 1.0)
            w_dir = (1.0 - b) + b * np.clip(cos, 0.0, 1.0)
            return per_cell * w_band * w_dir * self.open
        if t == "stone":
            return per_cell * np.clip(1.0 - self.d_rock / R["stone_reach_m"], 0.0, 1.0) * self.open
        R_t = R["types"][t]["density_per_100m2"]
        return self.cover(R_t) * self.s * self.s / 100.0

    def sample_index(self, x, z):
        r = np.clip(np.rint((z + self.half) / self.s).astype(np.int64), 0, self.n - 1)
        c = np.clip(np.rint((x + self.half) / self.s).astype(np.int64), 0, self.n - 1)
        return r, c


# --- rule fill ---------------------------------------------------------------------------------


def _draw(lam: np.ndarray, spec: dict, rules: dict, seed: int, t_idx: int, f: _Fields):
    """Candidates (x, z, yaw, l, h, w arrays) drawn tile by tile."""
    tile = max(1, int(round(rules["tile_m"] / f.s)))
    cs = max(1.0, float(spec.get("cluster_size", 1)))
    rad = float(rules["cluster_radius_m"]) if cs > 1 else 0.0
    sz = spec["size_m"]
    out = []
    for ti in range(0, f.n, tile):
        for tj in range(0, f.n, tile):
            sub = lam[ti : ti + tile, tj : tj + tile]
            if not sub.any():
                continue
            rng = np.random.default_rng([seed, t_idx, ti, tj])
            cnt = rng.poisson(sub / cs)
            rr, cc = np.nonzero(cnt)
            if rr.size == 0:
                continue
            rep = cnt[rr, cc]
            rr, cc = np.repeat(rr, rep), np.repeat(cc, rep)
            px = -f.half + (tj + cc + rng.random(rr.size) - 0.5) * f.s
            pz = -f.half + (ti + rr + rng.random(rr.size) - 0.5) * f.s
            k = 1 + rng.poisson(cs - 1.0, rr.size)
            px, pz = np.repeat(px, k), np.repeat(pz, k)
            m = px.size
            rho = rad * np.sqrt(rng.random(m))
            ang = 2 * np.pi * rng.random(m)
            x, z = px + rho * np.cos(ang), pz + rho * np.sin(ang)
            yaw = 360.0 * rng.random(m)
            l = rng.uniform(*sz["l"], m)
            h = rng.uniform(*sz["h"], m)
            w = rng.uniform(*sz["w"], m)
            out.append((x, z, yaw, np.maximum(l, w), h, np.minimum(l, w)))
    if not out:
        return [np.zeros(0)] * 6
    return [np.concatenate(a) for a in zip(*out)]


def _clear_of_rocks(x, z, r, f: _Fields) -> np.ndarray:
    """Disk (x, z, r) touches no rock footprint."""
    ok = np.ones(x.size, bool)
    if not f.rocks or x.size == 0:
        return ok
    ri, ci = f.sample_index(x, z)
    ok &= ~f.covered[ri, ci]
    amb = np.nonzero(ok & (f.d_rock[ri, ci] <= r + _EXACT_MARGIN_STEPS * f.s))[0]
    if amb.size == 0:
        return ok
    cell = 16.0
    keys = np.floor(x[amb] / cell).astype(np.int64) * 100003 + np.floor(z[amb] / cell).astype(np.int64)
    order = np.argsort(keys, kind="stable")
    sk = keys[order]
    uniq, start = np.unique(sk, return_index=True)
    buckets = dict(zip(uniq.tolist(), np.split(amb[order], start[1:])))
    rmax = float(r[amb].max())
    for rock in f.rocks:
        poly = _footprint_poly(rock)
        x0, x1 = poly[:, 0].min() - rmax, poly[:, 0].max() + rmax
        z0, z1 = poly[:, 1].min() - rmax, poly[:, 1].max() + rmax
        idx = [buckets.get(i * 100003 + j)
               for i in range(int(math.floor(x0 / cell)), int(math.floor(x1 / cell)) + 1)
               for j in range(int(math.floor(z0 / cell)), int(math.floor(z1 / cell)) + 1)]
        idx = [a for a in idx if a is not None]
        if not idx:
            continue
        cand = np.concatenate(idx)
        cand = cand[ok[cand]]
        if cand.size == 0:
            continue
        hit = _in_poly(poly, x[cand], z[cand]) | (_dist_to_edges(poly, x[cand], z[cand]) < r[cand])
        ok[cand[hit]] = False
    return ok


def _fields(classes, hm, rocks, rules, cfg, tops, fields):
    return fields if fields is not None else _Fields(classes, hm, rocks, rules, cfg, tops)


def rule_fill(classes: np.ndarray, hm: np.ndarray, rocks: list[Rock], rules: dict, seed: int,
              *, cfg: SiteConfig, tops: np.ndarray | None = None,
              fields: _Fields | None = None) -> list[Instance]:
    """Scree, stones, scrub and trees (in that order) for the core. `rocks` = the placed rocks
    (their footprints are kept clear); `classes` = the 0.5 m class map; `tops` = mass_tops."""
    f = _fields(classes, hm, rocks, rules, cfg, tops, fields)
    out: list[Instance] = []
    for t in RULE_TYPES:
        spec = rules["types"][t]
        lam = f.density(t)
        x, z, yaw, l, h, w = _draw(lam, spec, rules, seed, INSTANCE_TYPES.index(t), f)
        if x.size == 0:
            continue
        rad = np.hypot(l, w) / 2.0
        ok = (np.abs(x) <= f.half) & (np.abs(z) <= f.half)
        ri, ci = f.sample_index(x, z)
        ok &= lam[ri, ci] > 0
        for st in cfg.structures:
            clear = float(st["diameter_m"]) / 2.0 + rules["structure_clear_m"] + rad
            ok &= np.hypot(x - float(st["x"]), z - float(st["z"])) >= clear
        sel = np.nonzero(ok)[0]
        keep = sel[_clear_of_rocks(x[sel], z[sel], rad[sel], f)]
        out.extend(Instance(t, float(x[k]), float(z[k]), float(yaw[k]),
                            (float(l[k]), float(h[k]), float(w[k]))) for k in keep)
    return out


def grass_density(classes: np.ndarray, hm: np.ndarray, rocks: list[Rock], rules: dict, *,
                  cfg: SiteConfig, tops: np.ndarray | None = None,
                  fields: _Fields | None = None) -> np.ndarray:
    """Relative grass density per core sample, uint8 0-255 = 0-1 (row 0 north)."""
    f = _fields(classes, hm, rocks, rules, cfg, tops, fields)
    g = np.clip(f.cover(rules["types"]["grass"]["density"]), 0.0, 1.0)
    return np.rint(g * 255.0).astype(np.uint8)


# --- mass fill ----------------------------------------------------------------------------------


def _rock_seed(rules: dict, rock: Rock) -> list[int]:
    return [int(rules["seed"]), int(hashlib.sha1(rock.id.encode("utf-8")).hexdigest()[:12], 16)]


def fill_mass(rock: Rock, hm: np.ndarray, rules: dict, *, cfg: SiteConfig,
              tops: np.ndarray | None = None) -> list[Instance]:
    """Pack a mass outline with pieces whose tops reach the mass top.

    Top: the DEM rock-top surface (`tops`, Ruling 15) for large masses, else rock_top_y (ground
    at the centre + height). Pieces sit on the min ground under their footprint (rock_base_y),
    so h = top - base. Large-mass parts thinner than pavement_thickness_m are fill_slab
    (Ruling 18), the rest fill_round. Greedy packing over a jittered candidate grid in random
    order: each piece takes the largest size (up to its random target) that keeps its l/2
    circle inside the outline and its mean radius (l + w)/4 overlapping neighbours by at most
    overlap_frac. A round piece's h is at most max_h_over_l x l (edge pieces taper); a top is
    lowered by up to top_jitter_frac of the local thickness. A slab reaches at least
    slab_reveal_m above the highest ground under it (else the terrain hides it on a slope).

    Gap pass (Ruling 28): the outline is then packed again over a finer candidate grid with
    smaller pieces (fill.gap: l_m, candidate_step_m, overlap_frac), so the plan view of the
    pieces covers the outline instead of leaving the gaps of a loose circle packing. A round gap
    piece is a single block (at most max_h_over_l x l high), not a stack to the top."""
    if rock.kind != "mass" or not rock.outline:
        return []
    F = rules["fill"]
    spec = {t: rules["types"][t] for t in ("fill_round", "fill_slab")}
    poly = np.asarray(rock.outline, np.float64)
    rng = np.random.default_rng(_rock_seed(rules, rock))
    x0, x1 = poly[:, 0].min(), poly[:, 0].max()
    z0, z1 = poly[:, 1].min(), poly[:, 1].max()
    levels = int(spec["fill_round"]["max_stack"])
    large = is_large_mass(rock) and tops is not None
    n, half, s = core_n(cfg), _half(cfg), cfg.core_step_m

    def candidates(step: float) -> dict | None:
        """Jittered grid points inside the outline in random order, with their random draws,
        distance to the outline, local top / thickness and slab flag."""
        gx, gz = np.meshgrid(np.arange(x0 + step / 2, x1, step), np.arange(z0 + step / 2, z1, step))
        cx = gx.ravel() + (rng.random(gx.size) - 0.5) * step
        cz = gz.ravel() + (rng.random(gx.size) - 0.5) * step
        inside = _in_poly(poly, cx, cz)
        cx, cz = cx[inside], cz[inside]
        if cx.size == 0:
            return None
        perm = rng.permutation(cx.size)
        c = {"x": cx[perm], "z": cz[perm]}
        m = cx.size
        c["d_out"] = _dist_to_edges(poly, c["x"], c["z"])
        for k in ("l", "q", "jit", "yaw"):
            c[k] = rng.random(m)
        c["shrink"], c["turn"] = rng.random((m, levels)), rng.random((m, levels))
        if large:
            ground = _bilinear(hm, c["x"], c["z"], cfg)
            ri = np.clip(np.rint((c["z"] + half) / s).astype(np.int64), 0, n - 1)
            ci = np.clip(np.rint((c["x"] + half) / s).astype(np.int64), 0, n - 1)
            top = tops[ri, ci].astype(np.float64)
            c["top"] = np.where(np.isfinite(top), top, rock_top_y(rock, hm, cfg))
            c["thick"] = np.maximum(c["top"] - ground, 0.0)
            c["slab"] = c["thick"] < F["pavement_thickness_m"]
        else:
            c["top"] = np.full(m, rock_top_y(rock, hm, cfg))
            c["thick"] = np.full(m, float(rock.height))
            c["slab"] = np.zeros(m, bool)
        return c

    # Neighbour search: first-pass pieces in cells of the largest piece length; gap pieces in
    # cells of twice the largest gap length (3 x 3 cells reach every piece that can limit one).
    G = F["gap"]
    l_gap = (float(G["l_m"][0]), float(G["l_m"][1]))
    cells = (max(spec[t]["size_m"]["l"][1] for t in spec), 2.0 * l_gap[1])
    grids: tuple[dict, dict] = ({}, {})
    out: list[Instance] = []
    reveal = float(F["slab_reveal_m"])

    def place(c: dict, k: int, ov: float, l_range: tuple[float, float] | None) -> None:
        cx, cz = float(c["x"][k]), float(c["z"][k])
        thick = float(c["thick"][k])
        t = "fill_slab" if c["slab"][k] else "fill_round"
        sp = spec[t]
        (l_lo, l_hi), (h_lo, h_hi), (w_lo, _) = sp["size_m"]["l"], sp["size_m"]["h"], sp["size_m"]["w"]
        if l_range is not None:  # gap pass: its own (smaller) sizes
            l_lo, l_hi = l_range
            w_lo = min(w_lo, l_lo * sp["w_over_l"][0])
        if 2.0 * c["d_out"][k] < l_lo:
            return
        q = sp["w_over_l"][0] + c["q"][k] * (sp["w_over_l"][1] - sp["w_over_l"][0])
        l_t = l_lo + c["l"][k] * (l_hi - l_lo)
        if t == "fill_round":
            l_t = max(l_t, min(l_hi, thick / sp["max_h_over_l"]))
        rho_fit = math.inf
        for cell, grid in zip(cells, grids):
            ix, iz = int(math.floor(cx / cell)), int(math.floor(cz / cell))
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    for px, pz, pr in grid.get((ix + di, iz + dj), ()):
                        rho_fit = min(rho_fit, math.hypot(cx - px, cz - pz) / (1.0 - ov) - pr)
        l = min(l_t, 2.0 * c["d_out"][k], 4.0 * rho_fit / (1.0 + q))
        if l < l_lo:
            return
        w = min(l, max(w_lo, q * l))
        yaw = 180.0 * float(c["yaw"][k])
        piece = Instance(t, cx, cz, yaw, (l, 1.0, w))
        prock = instance_rock(piece)
        base = rock_base_y(prock, hm, cfg)
        target = c["top"][k] - F["top_jitter_frac"] * c["jit"][k] * thick
        if t == "fill_slab":
            rr, cc = base_samples(prock, cfg)
            relief = float(hm[rr, cc].max()) - base
            h = min(l, max(h_lo, min(h_hi, target - base), relief + reveal))
            out.append(Instance(t, cx, cz, yaw, (float(l), float(h), float(w))))
        elif l_range is not None:
            # Gap pieces are one block each, not a column to the mass top: fallen blocks in the
            # joints between the stacks (stacking them multiplied the piece count ~8x).
            h = max(h_lo, min(target - base, sp["max_h_over_l"] * l))
            out.append(Instance(t, cx, cz, yaw, (float(l), float(h), float(w))))
        else:
            out.extend(_stack(piece, base, target, sp, hm, cfg, c["shrink"][k], c["turn"][k]))
        g = 0 if l_range is None else 1
        key = (int(math.floor(cx / cells[g])), int(math.floor(cz / cells[g])))
        grids[g].setdefault(key, []).append((cx, cz, l * (1.0 + q) / 4.0))

    c = candidates(float(F["candidate_step_m"]))
    if c is None:
        return []
    for k in range(c["x"].size):
        place(c, k, float(F["overlap_frac"]), None)
    # Gap pass: a finer candidate grid, smaller pieces, more overlap.
    c = candidates(float(G["candidate_step_m"]))
    if c is not None:
        for k in range(c["x"].size):
            place(c, k, float(G["overlap_frac"]), l_gap)
    return out


def _stack(piece: Instance, base: float, target: float, sp: dict, hm, cfg: SiteConfig,
           u_shrink: np.ndarray, u_turn: np.ndarray) -> list[Instance]:
    """A column of round pieces from `base` up to `target` (Ruling 22): each piece at most
    max_h_over_l x its l high; each one up is stack_shrink x the one below (not below the
    minimum l), turned by up to +-stack_turn_deg, centred on it and resting on its top. The
    heights share the column in proportion to their caps, so the top lands on `target`."""
    l_lo, h_lo = sp["size_m"]["l"][0], sp["size_m"]["h"][0]
    ratio = sp["max_h_over_l"]
    s_lo, s_hi = sp["stack_shrink"]
    need = max(target - base, h_lo)
    l0, _, w0 = piece.size
    dims = [(l0, w0, piece.yaw_deg)]
    while sum(ratio * d[0] for d in dims) < need and len(dims) < len(u_shrink):
        i = len(dims)
        f = s_lo + u_shrink[i] * (s_hi - s_lo)
        pl, pw, py = dims[-1]
        nl = max(l_lo, pl * f)
        nw = min(nl, pw * nl / pl)
        dims.append((nl, nw, (py + (2.0 * u_turn[i] - 1.0) * sp["stack_turn_deg"]) % 180.0))
    caps = [ratio * d[0] for d in dims]
    scale = need / sum(caps)
    out, abs_base = [], base
    for (l, w, yaw), c in zip(dims, caps):
        h = c * scale
        p = Instance(piece.type, piece.x, piece.z, yaw, (float(l), float(h), float(w)))
        y = 0.0 if not out else abs_base - rock_base_y(instance_rock(p), hm, cfg)
        out.append(Instance(p.type, p.x, p.z, yaw, p.size, float(max(y, 0.0))))
        abs_base += h
    return out


# --- output -------------------------------------------------------------------------------------


def scatter_doc(instances: list[Instance]) -> dict:
    """Compact columnar scatter.json (Ruling 21); numbers rounded to 0.01."""
    tid = {t: i for i, t in enumerate(INSTANCE_TYPES)}
    rows = [[tid[i.type], round(i.x, 2), round(i.z, 2), round(i.y, 2), round(i.yaw_deg, 2),
             round(i.size[0], 2), round(i.size[1], 2), round(i.size[2], 2)] for i in instances]
    return {"version": 1, "types": list(INSTANCE_TYPES), "fields": list(FIELDS), "rows": rows}


def type_counts(instances: list[Instance]) -> dict[str, int]:
    c = {t: 0 for t in INSTANCE_TYPES}
    for i in instances:
        c[i.type] += 1
    return c


def site_scatter(cfg: SiteConfig, classes: np.ndarray, hm: np.ndarray, rocks: list[Rock],
                 tops: np.ndarray | None, rules: dict | None = None):
    """(placed rocks, instances, grass density) for a site: Ruling 19 placement, rule fill
    around the placed rocks, every mass packed."""
    rules = rules or load_rules(cfg.rules)
    placed = placed_rocks(rocks)
    f = _Fields(classes, hm, placed, rules, cfg, tops)
    inst = rule_fill(classes, hm, placed, rules, int(rules["seed"]), cfg=cfg, fields=f)
    for r in placed:
        inst.extend(fill_mass(r, hm, rules, cfg=cfg, tops=tops))
    grass = grass_density(classes, hm, placed, rules, cfg=cfg, fields=f)
    return placed, inst, grass
