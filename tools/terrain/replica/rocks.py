"""Rock detection from the ortho + class map, the rock list JSON, and hand-edit merging.

Detection (detect_rocks); every number is in PARAMS:
  1. ROCK pixels of the class map are labelled into 8-connected components, split where they
     are joined only by necks narrower than split_neck_m (class-map growth links whole
     stony slopes into one web).
  2. Shadows come from classify.shadow_mask (the same rule the class map uses). From every
     rock pixel on a component's anti-sun edge, a ray is marched along the sun azimuth
     (away from the sun) over shadow pixels, tolerating up to shadow_gap_m of lit pixels in
     a row (blurred rock/shadow borders, speckle). A run is *valid* if it ends on lit
     ground. Runs that hit another rock, re-enter their own rock or leave the image are not
     measurements; nor are runs implying a height above shadow_height_max_ratio x
     sqrt(component area) -- that is dark ground (scrub), not a cast shadow.
  3. Components whose shadows merge -- a shadow run reaching another component, or the
     (bounded) shadow pixels of two components touching -- are one group. A group of two or
     more components, or one at least mass_min_length_m long, is a "mass" with an outline:
     its rock plus its shadow within mass_bridge_m of the rock and inside the hull (shaded
     rock between the parts), traced and simplified to outline_tolerance_m. Parts that this
     shaded rock does not link stay separate rocks (no rock pixel is ever dropped). Otherwise
     it is a "boulder".
  4. Footprint (of the rock, or the mass region): centroid, long axis from second moments,
     length / width = pixel extent along the long / short axis. Groups with
     sqrt(length * width) < min_footprint_m are dropped (specks).
  5. Height = the shadow_run_percentile of the group's valid run lengths x tan(sun
     elevation), clamped to [height_min_m, height_max_m] (height_source "shadow"). It needs
     at least shadow_min_runs valid runs covering shadow_min_run_frac of the anti-sun edge.
     Otherwise (steep / self-shadowed tors, shadows too short to resolve, shadow lost in
     dark ground) height_source is "footprint": width (a mass: its widest rock's width) x
     the median height/width of this run's shadow-measured boulders (footprint_height_ratio
     when fewer than footprint_ratio_min_samples), capped at footprint_cap_percentile of
     the shadow-measured heights, then clamped likewise.

Known limits: the footprint is the *lit* rock (self-shadowed faces are classified as shadow,
so a rock is slightly short on its anti-sun side); shadow lengths assume flat ground.

Rock ids are a hash of the centre rounded to 0.5 m, so re-detection of the same rock gives
the same id; edits key on ids and keep them even when they move a rock.

Frame: array centred on the local origin, row 0 north (-z), col 0 west (-x); pixel (r, c)
centre x = -W*mpp/2 + (c + 0.5) * mpp, z = -H*mpp/2 + (r + 0.5) * mpp.
"""
from __future__ import annotations

import dataclasses
import hashlib
import json
import math
import warnings
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components

from .classify import GRASS, ROCK, UNKNOWN, _disk, apply_overrides, debug_overlay, shadow_mask
from .site import SiteConfig
from .sun import Sun, sun_from_site

PARAMS = {
    # Groups smaller than this (sqrt(length * width), m) are not rocks.
    "min_footprint_m": 2.0,
    "height_min_m": 0.3,
    "height_max_m": 40.0,
    # Lit (non-shadow) steps tolerated in a row inside a shadow run: blurred borders at its
    # start and end, speckle in between.
    "shadow_gap_m": 1.0,
    "shadow_run_percentile": 90.0,
    "shadow_min_runs": 3,
    "shadow_min_run_frac": 0.3,
    # A shadow run may not imply a height above this x sqrt(component area): longer "shadows"
    # are dark ground (scrub), not a measurement, and do not join rocks into masses.
    "shadow_height_max_ratio": 1.5,
    # A group this long (m) is a "mass" (outcrop / tor group with an outline) even when it
    # is one component.
    "mass_min_length_m": 10.0,
    # Class-map rock joined only by necks narrower than this (m) is separate rocks (growth
    # artefacts link whole slopes into one web): cores = opening with a disk this wide; every
    # rock pixel joins the nearest core of its own component.
    "split_neck_m": 2.5,
    # Shadow pixels within this distance (m) of a mass's rock are shaded rock (gaps between its
    # parts, its foot); farther ones are ground and stay outside the outline.
    "mass_bridge_m": 2.0,
    # Footprint fallback: height = ratio x width (a mass: x the width of its widest rock),
    # capped at this percentile of this run's shadow-measured heights of the same kind (of
    # all kinds when a kind has too few), once footprint_ratio_min_samples were measured.
    "footprint_cap_percentile": 90.0,
    "footprint_height_ratio": 0.6,
    "footprint_ratio_min_samples": 20,
    # Douglas-Peucker tolerance for mass outlines.
    "outline_tolerance_m": 0.5,
    # Ruling 27 (reconcile_classes): a removed rock's footprint is grown by this (m) to take in
    # its edge pixels (box extents are pixel centres; outlines are simplified) ...
    "reclass_margin_m": 1.0,
    # ... and its ROCK pixels take the class most common in a ring this wide (m) around them.
    "reclass_ring_m": 4.0,
}

_ST_RUNNING, _ST_GROUND, _ST_OWN, _ST_OTHER, _ST_BORDER, _ST_UNBOUNDED = range(6)

_FIELDS = (
    "id", "x", "z", "length", "width", "yaw_deg", "height", "kind", "outline", "source",
    "height_source",
)


@dataclass
class Rock:
    id: str
    x: float
    z: float
    length: float
    width: float
    yaw_deg: float
    height: float
    kind: str  # "boulder" | "mass"
    outline: list[list[float]] | None = None  # masses: closed polygon [[x, z], ...]
    source: str = "detected"  # "detected" | "edit"
    height_source: str = "shadow"  # "shadow" | "footprint"

    def __post_init__(self) -> None:
        # length is the long axis: swap a wider-than-long footprint, yaw follows the long axis
        if self.width > self.length:
            self.length, self.width = self.width, self.length
            self.yaw_deg = round((self.yaw_deg + 90.0) % 180.0, 2)


@dataclass
class Edits:
    added: list[Rock] = field(default_factory=list)
    deleted: set[str] = field(default_factory=set)
    changed: dict[str, dict] = field(default_factory=dict)


def rock_id(x: float, z: float) -> str:
    """Stable id: hash of the centre rounded to 0.5 m."""
    key = f"{round(x * 2.0) / 2.0:.1f},{round(z * 2.0) / 2.0:.1f}"
    return hashlib.sha1(key.encode("ascii")).hexdigest()[:12]


# --- detection ---------------------------------------------------------------------------


def _shadow_runs(
    lab: np.ndarray, shadow: np.ndarray, sun: Sun, mpp: float, max_height_m: np.ndarray
):
    """March from every anti-sun edge pixel along the shadow direction. A run still in shadow
    past the shadow of max_height_m[label] is unbounded (dark ground, not a cast shadow).

    Returns (start_label, run_m, status, contacts, owned) where contacts is an (k, 2) array of
    label pairs joined by a shadow and owned is (pixel_flat_index, label) of shadow pixels on
    runs that ended (not unbounded / off-image)."""
    P = PARAMS
    h, w = lab.shape
    dx, dz = sun.shadow_dir_xz()
    gap = max(1, int(round(P["shadow_gap_m"] / mpp)))
    tan_el = math.tan(math.radians(sun.elevation_deg))
    limit = np.ceil(np.minimum(max_height_m, P["height_max_m"]) / tan_el / mpp).astype(np.int64)
    limit += gap + 1

    rr0, cc0 = np.nonzero(lab)
    own = lab[rr0, cc0]
    r1 = rr0 + int(round(dz))
    c1 = cc0 + int(round(dx))
    inb = (r1 >= 0) & (r1 < h) & (c1 >= 0) & (c1 < w)
    nxt = np.zeros_like(own)
    nxt[inb] = lab[r1[inb], c1[inb]]
    edge = nxt != own
    r0, c0, own = rr0[edge], cc0[edge], own[edge]
    n = own.size
    t_end = limit[own]
    t_max = int(t_end.max()) if n else 0

    status = np.zeros(n, np.int8)
    started = np.zeros(n, bool)
    last_t = np.zeros(n, np.int32)
    miss = np.zeros(n, np.int32)
    contacts = []
    owned_px, owned_start = [], []
    for t in range(1, t_max + 1):
        alive = np.nonzero(status == _ST_RUNNING)[0]
        if alive.size == 0:
            break
        r = r0[alive] + int(round(t * dz))
        c = c0[alive] + int(round(t * dx))
        oob = (r < 0) | (r >= h) | (c < 0) | (c >= w)
        status[alive[oob]] = _ST_BORDER
        alive, r, c = alive[~oob], r[~oob], c[~oob]
        lv = lab[r, c]
        sh = shadow[r, c] & (lv == 0)
        is_own = lv == own[alive]
        is_other = (lv > 0) & ~is_own
        # Shadow continues.
        started[alive[sh]] = True
        last_t[alive[sh]] = t
        owned_px.append(r[sh] * w + c[sh])
        owned_start.append(alive[sh])
        # Reached another rock through a shadow: contact.
        hit = alive[is_other]
        st = started[hit]
        contacts.append(np.stack([own[hit[st]], lv[is_other][st]], axis=1))
        status[hit] = _ST_OTHER
        status[alive[is_own]] = _ST_OWN
        # Lit ground: tolerated for up to `gap` consecutive steps (blurred shadow borders at
        # either end, speckle inside); after that the run has ended on ground.
        miss[alive[sh]] = 0
        lit = alive[(lv == 0) & ~sh]
        miss[lit] += 1
        status[lit[miss[lit] > gap]] = _ST_GROUND
        over = alive[(status[alive] == _ST_RUNNING) & (t >= t_end[alive])]
        status[over] = _ST_UNBOUNDED
    status[status == _ST_RUNNING] = _ST_UNBOUNDED

    run_m = last_t * mpp
    if owned_px:
        px = np.concatenate(owned_px)
        si = np.concatenate(owned_start)
        keep = np.isin(status[si], (_ST_GROUND, _ST_OTHER, _ST_OWN))
        owned = (px[keep], own[si[keep]])
    else:
        owned = (np.zeros(0, np.int64), np.zeros(0, own.dtype))
    contacts = np.concatenate(contacts) if contacts else np.zeros((0, 2), own.dtype)
    return own, run_m, status, contacts, owned


def _groups(lab: np.ndarray, n: int, contacts: np.ndarray, owned) -> tuple[np.ndarray, np.ndarray]:
    """Group id per component label (index 0 unused) and an owner-group image of shadows."""
    h, w = lab.shape
    px, plab = owned
    pairs = [contacts]
    own_img = np.zeros(h * w, lab.dtype)
    if px.size:
        # A pixel on the shadow of two components joins them.
        order = np.argsort(px, kind="stable")
        px_s, lab_s = px[order], plab[order]
        same_px = px_s[1:] == px_s[:-1]
        pairs.append(np.stack([lab_s[1:][same_px], lab_s[:-1][same_px]], axis=1))
        own_img[px_s] = lab_s
    own_img = own_img.reshape(h, w)
    # Touching shadows, or a shadow touching another component (8-neighbourhood).
    for dr, dc in ((0, 1), (1, 0), (1, 1), (1, -1)):
        for a_img, b_img in ((own_img, own_img), (own_img, lab), (lab, own_img)):
            a = a_img[max(0, -dr) : h - max(0, dr), max(0, -dc) : w - max(0, dc)]
            b = b_img[max(0, dr) : h - max(0, -dr), max(0, dc) : w - max(0, -dc)]
            m = (a > 0) & (b > 0) & (a != b)
            pairs.append(np.stack([a[m], b[m]], axis=1))
    pairs = np.concatenate(pairs).astype(np.int64)
    graph = coo_matrix(
        (np.ones(len(pairs), np.int8), (pairs[:, 0], pairs[:, 1])), shape=(n + 1, n + 1)
    )
    _, group = connected_components(graph, directed=False)
    return group, own_img


def _footprint(rows: np.ndarray, cols: np.ndarray, mpp: float, half_h: float, half_w: float):
    """(x, z, length, width, yaw_deg) of a pixel set."""
    x = -half_w + (cols + 0.5) * mpp
    z = -half_h + (rows + 0.5) * mpp
    cx, cz = float(x.mean()), float(z.mean())
    pts = np.stack([x - cx, z - cz])
    cov = pts @ pts.T / max(1, pts.shape[1])
    vals, vecs = np.linalg.eigh(cov)
    major, minor = vecs[:, 1], vecs[:, 0]
    pa, pb = major @ pts, minor @ pts
    length = float(pa.max() - pa.min()) + mpp
    width = float(pb.max() - pb.min()) + mpp
    yaw = math.degrees(math.atan2(major[0], -major[1])) % 180.0
    return cx, cz, length, width, yaw


def _hull(points: np.ndarray) -> np.ndarray:
    """Convex hull (CCW in the given axes) of (k, 2) points, monotone chain."""
    pts = np.unique(points, axis=0)
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in pts[::-1]:
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return np.array(lower[:-1] + upper[:-1])


def _in_hull(hull: np.ndarray, pts: np.ndarray) -> np.ndarray:
    if len(hull) < 3:
        return np.zeros(len(pts), bool)
    inside = np.ones(len(pts), bool)
    for i in range(len(hull)):
        o, a = hull[i], hull[(i + 1) % len(hull)]
        inside &= (a[0] - o[0]) * (pts[:, 1] - o[1]) - (a[1] - o[1]) * (pts[:, 0] - o[0]) >= -1e-9
    return inside


def _trace(mask: np.ndarray) -> list[tuple[int, int]]:
    """Outer boundary of a 4-connected, hole-free mask as pixel-corner (row, col) vertices,
    clockwise on screen (row down), collinear vertices removed."""
    nxt: dict[tuple[int, int], tuple[int, int]] = {}
    m = np.pad(mask, 1)
    rs, cs = np.nonzero(m[1:-1, 1:-1])
    for r, c in zip(rs.tolist(), cs.tolist()):
        if not m[r, c + 1]:  # top
            nxt[(r, c)] = (r, c + 1)
        if not m[r + 1, c + 2]:  # right
            nxt[(r, c + 1)] = (r + 1, c + 1)
        if not m[r + 2, c + 1]:  # bottom
            nxt[(r + 1, c + 1)] = (r + 1, c)
        if not m[r + 1, c]:  # left
            nxt[(r + 1, c)] = (r, c)
    start = min(nxt)
    loop = [start]
    v = nxt[start]
    while v != start:
        loop.append(v)
        v = nxt[v]
    out = []
    k = len(loop)
    for i in range(k):
        a, b, c = loop[i - 1], loop[i], loop[(i + 1) % k]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) != 0:
            out.append(b)
    return out


def _dp(pts: np.ndarray, tol: float) -> np.ndarray:
    """Douglas-Peucker on an open polyline (keeps both ends)."""
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    ab = b - a
    nrm = math.hypot(ab[0], ab[1])
    rel = pts - a
    if nrm == 0.0:
        d = np.hypot(rel[:, 0], rel[:, 1])
    else:
        d = np.abs(ab[0] * rel[:, 1] - ab[1] * rel[:, 0]) / nrm
    i = int(np.argmax(d))
    if d[i] <= tol:
        return np.array([a, b])
    return np.concatenate([_dp(pts[: i + 1], tol)[:-1], _dp(pts[i:], tol)])


def _simplify_closed(pts: np.ndarray, tol: float) -> np.ndarray:
    if len(pts) <= 4:
        return pts
    far = int(np.argmax(np.hypot(*(pts - pts[0]).T)))
    first = _dp(pts[: far + 1], tol)
    second = _dp(np.concatenate([pts[far:], pts[:1]]), tol)
    out = np.concatenate([first[:-1], second[:-1]])
    return out if len(out) >= 3 else pts


def _group_pieces(sub_rock: np.ndarray, sub_shadow: np.ndarray, bridge_px: float) -> list:
    """A shadow group's rock plus its shadow pixels inside the rock's convex hull and within
    bridge_px of the rock (shaded rock between / at the foot of the parts), closed. Returns
    each 4-connected piece that holds rock, holes filled: every rock pixel is in one piece."""
    rr, cc = np.nonzero(sub_rock)
    hull = _hull(np.stack([rr, cc], axis=1).astype(np.float64))
    region = sub_rock.copy()
    near = ndi.distance_transform_edt(~sub_rock) <= bridge_px
    sr, sc = np.nonzero(sub_shadow & near)
    if sr.size:
        inside = _in_hull(hull, np.stack([sr, sc], axis=1).astype(np.float64))
        region[sr[inside], sc[inside]] = True
    region = np.pad(region, 2)
    region = ndi.binary_closing(region, structure=np.ones((3, 3), bool))[2:-2, 2:-2]
    region |= sub_rock
    lab4, n4 = ndi.label(region)
    pieces = []
    for k, sl in enumerate(ndi.find_objects(lab4), start=1):
        piece = np.zeros_like(region)
        piece[sl] = ndi.binary_fill_holes(lab4[sl] == k)
        if (piece & sub_rock).any():
            pieces.append(piece)
    return pieces


def _r2(v: float) -> float:
    return round(float(v), 2)


def _split_components(rock: np.ndarray, mpp: float) -> tuple[np.ndarray, int]:
    """8-connected rock components, split at necks narrower than split_neck_m."""
    eight = np.ones((3, 3), bool)
    lab0, n0 = ndi.label(rock, structure=eight)
    r = max(1, int(round((PARAMS["split_neck_m"] / mpp - 1.0) / 2.0)))
    core = ndi.binary_opening(rock, structure=_disk(r))
    core_lab, nc = ndi.label(core, structure=eight)
    if nc == 0:
        return lab0, n0
    _, (ir, ic) = ndi.distance_transform_edt(~core, return_indices=True)
    near_same = rock & (lab0[ir, ic] == lab0)
    lab = np.where(near_same, core_lab[ir, ic], 0)
    # Rock with no core of its own component nearest (thin rocks, coreless components).
    rest = rock & ~near_same
    lab[rest] = nc + lab0[rest]
    uniq, inv = np.unique(lab, return_inverse=True)
    lab = inv.reshape(lab.shape).astype(np.int32)
    return lab, len(uniq) - 1 if uniq[0] == 0 else len(uniq)


def detect_rocks(
    ortho: np.ndarray, classes: np.ndarray, sun: Sun, cfg: SiteConfig
) -> list[Rock]:
    """Rocks from the class map's ROCK pixels, sized from footprint and shadow (module doc)."""
    P = PARAMS
    mpp = cfg.ortho_m_per_px
    h, w = classes.shape
    half_h, half_w = h * mpp / 2.0, w * mpp / 2.0
    rock = classes == ROCK
    if not rock.any():
        return []
    lab, n = _split_components(rock, mpp)
    shadow = shadow_mask(ortho, cfg) & ~rock
    area_m2 = np.bincount(lab.ravel(), minlength=n + 1) * mpp * mpp
    max_h = P["shadow_height_max_ratio"] * np.sqrt(area_m2)
    start_lab, run_m, status, contacts, owned = _shadow_runs(lab, shadow, sun, mpp, max_h)
    group, own_img = _groups(lab, n, contacts, owned)

    glab = group[lab]
    glab[lab == 0] = -1
    gshadow = np.where(own_img > 0, group[own_img], -1)
    members = np.bincount(group[1:], minlength=int(group.max()) + 1)
    tan_el = math.tan(math.radians(sun.elevation_deg))

    # Valid runs and anti-sun edge counts per component label.
    valid = (status == _ST_GROUND) & (run_m > 0)
    order = np.argsort(start_lab[valid], kind="stable")
    vl, vr = start_lab[valid][order], run_m[valid][order]
    lbounds = np.searchsorted(vl, np.arange(n + 2))
    l_starts = np.bincount(start_lab, minlength=n + 1)
    comp_slices = ndi.find_objects(lab)

    def place(piece_rock: np.ndarray, region: np.ndarray | None, r0: int, c0: int):
        """Append one rock (boulder if region is None) from pixel masks of a group slice."""
        ph, pw = piece_rock.shape
        labels = np.unique(lab[r0 : r0 + ph, c0 : c0 + pw][piece_rock])
        labels = labels[labels > 0]
        rows, cols = np.nonzero(piece_rock if region is None else region)
        x, z, length, width, yaw = _footprint(rows + r0, cols + c0, mpp, half_h, half_w)
        if math.sqrt(length * width) < P["min_footprint_m"]:
            return
        kind, outline, rock_width = "boulder", None, width
        if region is not None:
            kind = "mass"
            corners = np.array(_trace(region), np.float64)
            xz = np.stack(
                [-half_w + (corners[:, 1] + c0) * mpp, -half_h + (corners[:, 0] + r0) * mpp],
                axis=1,
            )
            xz = _simplify_closed(xz, P["outline_tolerance_m"])
            outline = [[_r2(a), _r2(b)] for a, b in xz]
            rock_width = 0.0
            for lbl in labels:
                cs = comp_slices[lbl - 1]
                rr, cc = np.nonzero(lab[cs] == lbl)
                fp = _footprint(rr + cs[0].start, cc + cs[1].start, mpp, half_h, half_w)
                rock_width = max(rock_width, min(fp[3], width))
        runs = np.concatenate([vr[lbounds[l] : lbounds[l + 1]] for l in labels])
        edge = int(l_starts[labels].sum())
        measured = (
            runs.size >= P["shadow_min_runs"] and runs.size >= P["shadow_min_run_frac"] * edge
        )
        height = (
            float(np.percentile(runs, P["shadow_run_percentile"])) * tan_el if measured else 0.0
        )
        pending.append([x, z, length, width, yaw, height, kind, outline, measured, rock_width])

    pending = []  # [x, z, length, width, yaw, height, kind, outline, measured, rock_width]
    # Bounding boxes per group (shift ids by one: find_objects ignores 0).
    for g, sl in enumerate(ndi.find_objects(np.where(glab >= 0, glab + 1, 0))):
        if sl is None:
            continue
        r0, c0 = sl[0].start, sl[1].start
        sub = glab[sl] == g
        if members[g] < 2:
            rows, cols = np.nonzero(sub)
            if _footprint(rows, cols, mpp, 0.0, 0.0)[2] < P["mass_min_length_m"]:
                place(sub, None, r0, c0)
                continue
        # Shaded rock between / inside the parts belongs to the mass; pieces that the shaded
        # rock does not link stay separate rocks.
        for region in _group_pieces(sub, gshadow[sl] == g, P["mass_bridge_m"] / mpp):
            piece_rock = sub & region
            labels = np.unique(lab[sl][piece_rock])
            rows, cols = np.nonzero(piece_rock)
            single_short = (
                len(labels) < 2
                and _footprint(rows, cols, mpp, 0.0, 0.0)[2] < P["mass_min_length_m"]
            )
            place(piece_rock, None if single_short else region, r0, c0)

    ratios = [p[5] / p[3] for p in pending if p[8] and p[6] == "boulder"]
    ratio = (
        float(np.median(ratios))
        if len(ratios) >= P["footprint_ratio_min_samples"]
        else P["footprint_height_ratio"]
    )
    lo, hi = P["height_min_m"], P["height_max_m"]
    caps = {}
    min_n = P["footprint_ratio_min_samples"]
    all_h = [p[5] for p in pending if p[8]]
    for kind in ("boulder", "mass"):
        hs = [p[5] for p in pending if p[8] and p[6] == kind]
        hs = hs if len(hs) >= min_n else all_h
        caps[kind] = (
            float(np.percentile(hs, P["footprint_cap_percentile"])) if len(hs) >= min_n else hi
        )
    rocks = []
    for x, z, length, width, yaw, height, kind, outline, measured, rock_width in pending:
        if not measured:
            height = min(ratio * rock_width, caps[kind])
        rocks.append(
            Rock(
                id=rock_id(_r2(x), _r2(z)), x=_r2(x), z=_r2(z),
                length=_r2(length), width=_r2(width),
                yaw_deg=_r2(yaw), height=_r2(min(hi, max(lo, height))), kind=kind,
                outline=outline, source="detected",
                height_source="shadow" if measured else "footprint",
            )
        )
    return rocks


# --- rock list / edits I/O and merge ------------------------------------------------------


def _rock_from_dict(d: dict) -> Rock:
    unknown = set(d) - set(_FIELDS)
    if unknown:
        raise ValueError(f"unknown rock field(s): {sorted(unknown)}")
    return Rock(**d)


def write_rocks(path: Path, rocks: list[Rock]) -> None:
    """{"version": 1, "rocks": [...]}, one rock per line (diff-friendly)."""
    lines = [json.dumps(dataclasses.asdict(r), separators=(",", ":")) for r in rocks]
    body = ",\n".join(lines)
    Path(path).write_text(
        '{"version": 1, "rocks": [\n' + body + ("\n" if lines else "") + "]}\n", encoding="utf-8"
    )


def read_rocks(path: Path) -> list[Rock]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if data.get("version") != 1:
        raise ValueError(f"{path}: unsupported rock list version {data.get('version')}")
    return [_rock_from_dict(d) for d in data["rocks"]]


def load_edits(path: Path) -> Edits:
    """Edits JSON {"added": [Rock...], "deleted": [ids], "changed": {id: {field: value}}};
    a missing file means no edits."""
    path = Path(path)
    if not path.exists():
        return Edits()
    data = json.loads(path.read_text(encoding="utf-8"))
    return Edits(
        added=[_rock_from_dict(d) for d in data.get("added", [])],
        deleted=set(data.get("deleted", [])),
        changed={str(k): dict(v) for k, v in data.get("changed", {}).items()},
    )


def write_edits(path: Path, edits: Edits) -> None:
    data = {
        "added": [dataclasses.asdict(r) for r in edits.added],
        "deleted": sorted(edits.deleted),
        "changed": {k: edits.changed[k] for k in sorted(edits.changed)},
    }
    Path(path).write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")


def _unique_added(detected: list[Rock], added: list[Rock]) -> list[Rock]:
    """Added rocks with source "edit"; one whose id is already taken (by a detected rock or an
    earlier added one) gets a fresh id, derived deterministically from the old one."""
    used = {r.id for r in detected}
    out = []
    for a in added:
        rid, n = a.id, 0
        while rid in used:
            n += 1
            rid = hashlib.sha1(f"{a.id}#{n}".encode("ascii")).hexdigest()[:12]
        used.add(rid)
        out.append(dataclasses.replace(a, id=rid, source="edit"))
    return out


def merge(detected: list[Rock], edits: Edits) -> list[Rock]:
    """detected minus deleted ids, with changed fields applied (source -> "edit"), plus added.
    Ids never change (an edit that moves a rock keeps its id), except an added rock whose id
    collides with another rock's, which gets a fresh one. Edit ids matching no rock are
    reported with a warning, not dropped from the edits file."""
    out = []
    seen = set()
    for r in list(detected) + _unique_added(detected, edits.added):
        seen.add(r.id)
        if r.id in edits.deleted:
            continue
        change = edits.changed.get(r.id)
        if change:
            bad = set(change) - set(_FIELDS) | ({"id", "source"} & set(change))
            if bad:
                raise ValueError(f"edit for {r.id}: cannot change field(s) {sorted(bad)}")
            r = dataclasses.replace(r, **change, source="edit")
        out.append(r)
    orphans = (edits.deleted | set(edits.changed)) - seen
    if orphans:
        warnings.warn(f"rock edits refer to ids not detected: {sorted(orphans)}", stacklevel=2)
    return out


# --- class map vs rock list (Ruling 27) ------------------------------------------------------


def footprint_mask(rock: Rock, shape: tuple[int, int], mpp: float, grow_m: float = 0.0,
                   ellipse: bool = False) -> tuple[int, int, np.ndarray]:
    """(r0, c0, mask) of the class-map pixels (module frame) whose centres lie in the rock's
    footprint grown by grow_m: the outline polygon of a mass, else the length x width box along
    the yaw (the detected pixel extents) or, with ellipse, the inscribed ellipse (the boulder as
    drawn). The mask is clipped to the image; an empty one has size 0."""
    h, w = shape
    half_h, half_w = h * mpp / 2.0, w * mpp / 2.0
    is_poly = rock.kind == "mass" and bool(rock.outline)
    if is_poly:
        pts = np.asarray(rock.outline, np.float64)
        ext = (pts[:, 0].min() - grow_m, pts[:, 0].max() + grow_m,
               pts[:, 1].min() - grow_m, pts[:, 1].max() + grow_m)
    else:
        yaw = math.radians(rock.yaw_deg)
        (ax, az), (bx, bz) = (math.sin(yaw), -math.cos(yaw)), (math.cos(yaw), math.sin(yaw))
        hl, hw = rock.length / 2.0 + grow_m, rock.width / 2.0 + grow_m
        ex, ez = abs(ax) * hl + abs(bx) * hw, abs(az) * hl + abs(bz) * hw
        ext = (rock.x - ex, rock.x + ex, rock.z - ez, rock.z + ez)
    c0 = max(0, int(math.floor((ext[0] + half_w) / mpp - 0.5)))
    c1 = min(w - 1, int(math.ceil((ext[1] + half_w) / mpp - 0.5)))
    r0 = max(0, int(math.floor((ext[2] + half_h) / mpp - 0.5)))
    r1 = min(h - 1, int(math.ceil((ext[3] + half_h) / mpp - 0.5)))
    if r1 < r0 or c1 < c0:
        return r0, c0, np.zeros((0, 0), bool)
    xs = -half_w + (np.arange(c0, c1 + 1) + 0.5) * mpp
    zs = -half_h + (np.arange(r0, r1 + 1) + 0.5) * mpp
    X, Z = np.meshgrid(xs, zs)
    if is_poly:
        inside = np.zeros(X.shape, bool)
        x0, z0 = pts[:, 0], pts[:, 1]
        x1, z1 = np.roll(x0, -1), np.roll(z0, -1)
        for a, b, c, d in zip(x0, z0, x1, z1):
            if b == d:
                continue
            crosses = (b > Z) != (d > Z)
            inside ^= crosses & (X < a + (Z - b) * (c - a) / (d - b))
        if grow_m > 0:
            inside = ndi.binary_dilation(inside, _disk(int(math.ceil(grow_m / mpp))))
        return r0, c0, inside
    u = (X - rock.x) * ax + (Z - rock.z) * az
    v = (X - rock.x) * bx + (Z - rock.z) * bz
    if ellipse:
        inside = (u / max(hl, 1e-6)) ** 2 + (v / max(hw, 1e-6)) ** 2 <= 1.0
    else:
        inside = (np.abs(u) <= hl) & (np.abs(v) <= hw)
    return r0, c0, inside


def _paint(dst: np.ndarray, rock: Rock, mpp: float, grow_m: float = 0.0,
           ellipse: bool = False) -> None:
    r0, c0, m = footprint_mask(rock, dst.shape, mpp, grow_m, ellipse)
    if m.size:
        dst[r0 : r0 + m.shape[0], c0 : c0 + m.shape[1]] |= m


def _geometry(r: Rock) -> tuple:
    return (r.x, r.z, r.length, r.width, r.yaw_deg, r.kind,
            json.dumps(r.outline) if r.outline else None)


def reconcile_classes(classes: np.ndarray, detected: list[Rock], merged: list[Rock],
                      edits: Edits, mpp: float) -> tuple[np.ndarray, dict]:
    """Ruling 27: make the class map agree with the hand-corrected rock list.

    - A rock the edits *removed* (a deleted detected rock, or the old place of a detected rock
      whose geometry an edit changed): its footprint grown by reclass_margin_m, minus every
      rock of the merged list, is no rock any more. Its ROCK pixels, per 8-connected region,
      take the most common class in a reclass_ring_m ring around the region (ROCK, UNKNOWN and
      the region itself do not vote; GRASS if nothing votes).
    - A rock the edits *added* (and a changed boulder's new place) is painted ROCK: the outline
      of a mass, the length x width ellipse of a boulder (as drawn). A changed mass's outline
      is not painted: it encloses non-rock interior by design.
    Returns (new class map, {"reclassified_px", "painted_px"})."""
    P = PARAMS
    out = np.array(classes, dtype=np.uint8, copy=True)
    det = {r.id: r for r in detected}
    mer = {r.id: r for r in merged}
    removed = [det[i] for i in sorted(edits.deleted) if i in det]
    paint = [r for r in merged if r.id not in det]  # added
    for i in sorted(edits.changed):
        if i in det and i in mer and _geometry(det[i]) != _geometry(mer[i]):
            removed.append(det[i])
            if mer[i].kind == "boulder":
                paint.append(mer[i])
    stats = {"reclassified_px": 0, "painted_px": 0}
    if removed:
        drop = np.zeros(out.shape, bool)
        for r in removed:
            _paint(drop, r, mpp, P["reclass_margin_m"])
        keep = np.zeros(out.shape, bool)
        for r in merged:
            _paint(keep, r, mpp)
        target = drop & ~keep & (out == ROCK)
        lab, _ = ndi.label(target, structure=np.ones((3, 3), bool))
        ring_px = int(math.ceil(P["reclass_ring_m"] / mpp))
        for k, sl in enumerate(ndi.find_objects(lab), 1):
            r0, r1 = max(0, sl[0].start - ring_px), min(out.shape[0], sl[0].stop + ring_px)
            c0, c1 = max(0, sl[1].start - ring_px), min(out.shape[1], sl[1].stop + ring_px)
            comp = lab[r0:r1, c0:c1] == k
            ring = (ndi.distance_transform_edt(~comp) <= ring_px) & ~comp
            votes = classes[r0:r1, c0:c1][ring & ~target[r0:r1, c0:c1]]
            votes = votes[(votes != ROCK) & (votes != UNKNOWN)]
            cls = int(np.bincount(votes).argmax()) if votes.size else GRASS
            out[r0:r1, c0:c1][comp] = cls
        stats["reclassified_px"] = int(target.sum())
    if paint:
        add = np.zeros(out.shape, bool)
        for r in paint:
            _paint(add, r, mpp, ellipse=True)
        stats["painted_px"] = int((add & (out != ROCK)).sum())
        out[add] = ROCK
    return out, stats


# --- site --------------------------------------------------------------------------------


def merge_site_rocks(cfg: SiteConfig, detected: list[Rock]) -> list[Rock]:
    return merge(detected, load_edits(cfg.edits_dir / "rocks_edits.json"))


def write_site_rocks(cfg: SiteConfig) -> tuple[list[Rock], list[Rock]]:
    """Detect on build/ortho.png + build/classes_full.png, write build/rocks_detected.json and
    build/rocks.json = merge(detected, edits/rocks_edits.json), then rewrite classes_full.png
    (and the local classes_debug.png) to agree with the merged list (Ruling 27), with
    edits/classes_override.png applied again on top so its pixels still win."""
    with Image.open(cfg.build_dir / "ortho.png") as im:
        ortho = np.asarray(im.convert("RGB"))
    with Image.open(cfg.build_dir / "classes_full.png") as im:
        classes = np.asarray(im)
    detected = detect_rocks(ortho, classes, sun_from_site(cfg), cfg)
    write_rocks(cfg.build_dir / "rocks_detected.json", detected)
    edits = load_edits(cfg.edits_dir / "rocks_edits.json")
    merged = merge(detected, edits)
    write_rocks(cfg.build_dir / "rocks.json", merged)
    fixed, stats = reconcile_classes(classes, detected, merged, edits, cfg.ortho_m_per_px)
    # The hand override wins over the rock edits too (any non-zero pixel, as in write_classes).
    fixed = apply_overrides(fixed, cfg.edits_dir / "classes_override.png")
    print(f"  class map vs rock edits: {stats['reclassified_px']} ROCK px reclassified, "
          f"{stats['painted_px']} px painted ROCK")
    Image.fromarray(fixed, mode="L").save(cfg.build_dir / "classes_full.png", optimize=True)
    Image.fromarray(debug_overlay(ortho, fixed)).save(cfg.build_dir / "classes_debug.png")
    return detected, merged
