"""Environment Forge - procedural low-poly asset kit.

Run inside Blender (Text editor > Run Script, or `blender -b -P build_kit.py`).
Rebuilds every asset from scratch into the open file, then exports one GLB per asset.

Conventions (see docs/ASSET_PIPELINE.md):
  * 1 unit = 1 m, Z up, asset origin at its base centre (ground contact at z = 0).
  * Material names must match a palette file in res://assets/materials/<name>.tres.
  * Collision by Godot name suffix: -col (trimesh), -convcol (convex),
    -convcolonly (invisible convex collider).
Change a parameter in ASSETS / the builders and re-run; nothing is edited by hand.
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

PROJECT = os.environ.get("ENV_FORGE_ROOT", r"D:/DevEnv/GDOT/environment-lab")
EXPORT_DIR = os.path.join(PROJECT, "assets", "meshes")
BLEND_PATH = os.path.join(PROJECT, "assets", "blender", "environment_kit.blend")

# Preview colours only; Godot swaps in the palette materials by name.
PALETTE = {
    "foliage": (0.07, 0.10, 0.09),
    "larch": (0.20, 0.17, 0.08),
    "bark": (0.12, 0.10, 0.09),
    "deadwood": (0.30, 0.29, 0.27),
    "rock": (0.31, 0.32, 0.32),
    "monolith": (0.07, 0.07, 0.08),
    "ground": (0.16, 0.17, 0.15),
    "cloth": (0.40, 0.50, 0.64),
    "cloak": (0.62, 0.42, 0.16),
    "rusted_metal": (0.33, 0.19, 0.11),
    "weathered_wood": (0.32, 0.29, 0.25),
}

# Godot (Y up) -> Blender (Z up) change of basis: (x, y, z)_godot = (x, -y, z)... see godot_xform.
GODOT_TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


# --- helpers ----------------------------------------------------------------------

def material(name):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    rgb = PALETTE[name]
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.95
    mat.diffuse_color = (*rgb, 1.0)
    return mat


class Builder:
    """Accumulates parts into one bmesh, tracking a material slot per part."""

    def __init__(self, seed):
        self.bm = bmesh.new()
        self.rng = random.Random(seed)
        self.materials = []

    def _slot(self, mat_name):
        if mat_name not in self.materials:
            self.materials.append(mat_name)
        return self.materials.index(mat_name)

    def part(self, mat_name, create, matrix=Matrix.Identity(4), jitter=0.0):
        before = set(self.bm.verts)
        create(self.bm, matrix)
        new = [v for v in self.bm.verts if v not in before]
        if jitter:
            for v in new:
                v.co += Vector((self.rng.uniform(-1, 1), self.rng.uniform(-1, 1), self.rng.uniform(-1, 1))) * jitter
        slot = self._slot(mat_name)
        for f in {f for v in new for f in v.link_faces}:
            f.material_index = slot
        return new

    def finish(self, name, collection, parent=None):
        mesh = bpy.data.meshes.new(name)
        self.bm.normal_update()
        self.bm.to_mesh(mesh)
        self.bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = False
        for m in self.materials:
            mesh.materials.append(material(m))
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        obj.parent = parent
        return obj


def cone(r1, r2, depth, segments):
    def create(bm, matrix):
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments,
                              radius1=r1, radius2=r2, depth=depth, matrix=matrix)
    return create


def ico(radius, subdivisions=1):
    def create(bm, matrix):
        bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius, matrix=matrix)
    return create


def box(x, y, z):
    def create(bm, matrix):
        bmesh.ops.create_cube(bm, size=1.0, matrix=matrix @ Matrix.Diagonal((x, y, z, 1)))
    return create


def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def R(angle, axis):
    return Matrix.Rotation(angle, 4, axis)


def S(x, y, z):
    return Matrix.Diagonal((x, y, z, 1))


def collider(name, create, matrix, collection, parent):
    """Invisible convex collision proxy (Godot: -convcolonly)."""
    b = Builder(0)
    b.part("bark", create, matrix)
    obj = b.finish(f"{name}-convcolonly", collection, parent)
    obj.display_type = "WIRE"
    return obj


# --- trees --------------------------------------------------------------------------

def spruce(root, col, seed, height, tiers, radius, lean, crooked_top=False, squash=1.0):
    b = Builder(seed)
    rng = b.rng
    lean_dir = Vector((math.cos(rng.uniform(0, 6.28)), math.sin(rng.uniform(0, 6.28)), 0)) * lean
    trunk_h = height * 0.7
    b.part("bark", cone(0.3, 0.1, trunk_h, 6), T(z=trunk_h / 2) @ R(0, "Z"), jitter=0.02)
    for i in range(tiers):
        t = i / max(tiers - 1, 1)
        z0 = height * (0.2 + 0.62 * t)
        h = height * (0.36 - 0.16 * t)
        r = radius * (1.0 - 0.72 * t) * rng.uniform(0.88, 1.1)
        off = lean_dir * z0
        if crooked_top and i == tiers - 1:
            off += lean_dir.normalized() * 0.25
            z0 -= h * 0.25
        m = T(off.x, off.y, z0 + h / 2) @ R(rng.uniform(0, 6.28), "Z") @ S(1.0, squash * rng.uniform(0.85, 1.0), 1.0)
        verts = b.part("foliage", cone(r, 0.0, h, 7), m, jitter=0.1 * r)
        # droop the skirt: lower ring sags, more at the outer tips
        for v in verts:
            if v.co.z < z0 + h * 0.15:
                v.co.z -= rng.uniform(0.1, 0.35) * r
    obj = b.finish(f"{root.name}_mesh", col, root)
    collider(root.name + "_trunk", cone(0.35, 0.3, 3.0, 6), T(z=1.5), col, root)
    return obj


def larch(root, col, seed, height):
    """Sparse, asymmetric crown: reads differently from the spruce cones at any distance."""
    b = Builder(seed)
    rng = b.rng
    # slightly kinked trunk in three segments
    z, x = 0.0, 0.0
    for seg, (r1, r2) in enumerate([(0.26, 0.18), (0.18, 0.11), (0.11, 0.04)]):
        h = height * (0.42, 0.33, 0.3)[seg]
        dx = rng.uniform(-0.25, 0.25)
        tilt = math.atan2(dx, h)
        b.part("bark", cone(r1, r2, h, 6), T(x + dx / 2, 0, z + h / 2) @ R(tilt, "Y"))
        z += h * 0.97
        x += dx
    # Sparse narrow cone of small tufts: lots of sky shows through the crown.
    tufts = 11
    for i in range(tufts):
        t = i / (tufts - 1)
        cz = height * (0.35 + 0.58 * t) + rng.uniform(-0.3, 0.3)
        a = rng.uniform(0, 6.28)
        reach = rng.uniform(0.35, 1.0) * (1.25 - t) * 1.4
        r = rng.uniform(0.55, 0.9) * (1.1 - 0.5 * t)
        m = (T(math.cos(a) * reach + x * t, math.sin(a) * reach, cz)
             @ R(a, "Z") @ S(1.4, 1.0, 0.6))
        b.part("larch", ico(r, 1), m, jitter=0.15 * r)
    b.part("larch", cone(0.35, 0.0, 1.4, 5), T(x, 0, height * 0.98))
    obj = b.finish(f"{root.name}_mesh", col, root)
    collider(root.name + "_trunk", cone(0.3, 0.25, 3.0, 6), T(z=1.5), col, root)
    return obj


# --- rocks ----------------------------------------------------------------------------

def boulder(root, col, seed, size, sink=0.18, flat_top=0.0):
    b = Builder(seed)
    sx, sy, sz = size
    verts = b.part("rock", ico(1.0, 1), S(sx, sy, sz), jitter=0.16 * min(size))
    for v in verts:
        if flat_top and v.co.z > sz * (1 - flat_top):
            v.co.z = sz * (1 - flat_top) + (v.co.z - sz * (1 - flat_top)) * 0.25
        v.co.z += sz * (1 - sink)
    return b.finish(f"{root.name}-convcol", col, root)


def shard(root, col, seed, height, base_r):
    b = Builder(seed)
    rng = b.rng
    verts = b.part("rock", cone(base_r, base_r * 0.4, height, 6), T(z=height / 2) @ S(1.0, 0.72, 1.0), jitter=0.07)
    slant = rng.uniform(0.2, 0.45) * rng.choice((-1, 1))
    for v in verts:
        v.co.x += 0.035 * v.co.z ** 2  # slight bend
        if v.co.z > height * 0.9:
            v.co.z += v.co.x * slant  # broken, slanted top
    return b.finish(f"{root.name}-convcol", col, root)


# --- ground ----------------------------------------------------------------------------

def mound(root, col, seed, length, width, height, segments=10):
    """Gentle walkable hill. Edges dip below z = 0 so it melts into the ground plane."""
    b = Builder(seed)
    rng = b.rng

    def create(bm, matrix):
        bmesh.ops.create_grid(bm, x_segments=segments, y_segments=segments, size=0.5, matrix=matrix)

    verts = b.part("ground", create, S(length, width, 1.0))
    for v in verts:
        d = math.sqrt((v.co.x / (length / 2)) ** 2 + (v.co.y / (width / 2)) ** 2)
        falloff = max(0.0, 1.0 - d) ** 1.6
        v.co.z = height * falloff + rng.uniform(-0.08, 0.08) * height - 0.25
        if d >= 0.98:
            v.co.z = -0.3
    return b.finish(f"{root.name}-col", col, root)


# --- props ------------------------------------------------------------------------------

def cairn(root, col, seed, height=1.3):
    """Ovoo-style stone stack."""
    b = Builder(seed)
    rng = b.rng
    z = 0.0
    r = height * 0.42
    for _ in range(6):
        hz = r * 0.62
        b.part("rock", ico(1.0, 1), T(rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06), z + hz * 0.8)
               @ R(rng.uniform(0, 6.28), "Z") @ S(r, r * rng.uniform(0.8, 1.0), hz), jitter=0.05)
        z += hz * 1.35
        r *= 0.76
    return b.finish(f"{root.name}-convcol", col, root)


def fallen_log(root, col, seed, length=4.2):
    b = Builder(seed)
    rng = b.rng
    verts = b.part("deadwood", cone(0.42, 0.32, length, 7), T(z=0.3) @ R(math.pi / 2, "Y"), jitter=0.04)
    for v in verts:
        v.co.y += 0.06 * v.co.x ** 2  # bowed
        if abs(v.co.x) > length / 2 - 0.05:  # splintered ends
            v.co.x += math.copysign(rng.uniform(0, 0.45), v.co.x)
    b.part("deadwood", cone(0.09, 0.03, 1.1, 5), T(0.8, 0.25, 0.55) @ R(-0.7, "X") @ R(0.3, "Y"))
    return b.finish(f"{root.name}-convcol", col, root)


def stump(root, col, seed):
    """Cut stump: the slanted axe cut implies people were here."""
    b = Builder(seed)
    rng = b.rng
    verts = b.part("bark", cone(0.48, 0.4, 0.8, 7), T(z=0.4), jitter=0.02)
    for v in verts:
        if v.co.z > 0.7:
            v.co.z = 0.62 + v.co.x * 0.25
    for i in range(3):
        a = i * 2.1 + rng.uniform(-0.3, 0.3)
        b.part("bark", cone(0.16, 0.04, 0.9, 5),
               T(math.cos(a) * 0.45, math.sin(a) * 0.45, 0.12) @ R(a, "Z") @ R(1.25, "Y"))
    return b.finish(f"{root.name}-convcol", col, root)


def bar(a, b_, thickness):
    """Matrix for a unit cube stretched into a bar from point a to point b_."""
    a, b_ = Vector(a), Vector(b_)
    d = b_ - a
    rot = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    return T(*((a + b_) / 2)) @ rot @ S(thickness, thickness, d.length)


# --- modular / storytelling pieces (Stage 6) --------------------------------------------------

def khadag_post(root, col, seed, height=2.6):
    """Wooden post with a blue khadag (ceremonial scarf) tied near the top."""
    b = Builder(seed)
    rng = b.rng
    lean = rng.uniform(-0.06, 0.06)
    b.part("deadwood", cone(0.08, 0.05, height, 5), T(z=height / 2) @ R(lean, "Y"), jitter=0.01)
    top = height * 0.9
    b.part("cloth", box(0.03, 0.32, 1.4), T(0.16, 0, top - 0.6) @ R(0.35, "Y"))
    b.part("cloth", box(0.03, 0.26, 0.9), T(-0.12, 0.05, top - 0.4) @ R(-0.25, "Y") @ R(0.4, "Z"))
    obj = b.finish(f"{root.name}_mesh", col, root)
    collider(root.name + "_post", cone(0.12, 0.12, height, 6), T(z=height / 2), col, root)
    return obj


def spirit_banner(root, col, seed, height=14.0):
    """Tug: a tall spirit banner - spear tip, black tassel, trailing cloth. A secondary landmark."""
    b = Builder(seed)
    b.part("deadwood", cone(0.15, 0.08, height, 6), T(z=height / 2))
    b.part("deadwood", box(1.8, 0.1, 0.1), T(z=height - 1.6))
    b.part("monolith", cone(0.12, 0.0, 1.0, 4), T(z=height + 0.5))
    for a in (-0.5, 0.5):
        b.part("monolith", cone(0.05, 0.0, 0.6, 4), T(a * 0.35, 0, height + 0.1) @ R(a * 0.6, "Y"))
    b.part("monolith", cone(0.45, 0.05, 1.8, 7), T(z=height - 0.6) @ R(math.pi, "X"), jitter=0.06)
    b.part("cloth", box(0.04, 0.4, 4.0), T(0.85, 0, height - 3.7) @ R(0.18, "Y"))
    b.part("cloth", box(0.04, 0.3, 2.6), T(-0.85, 0.05, height - 3.0) @ R(-0.12, "Y"))
    obj = b.finish(f"{root.name}_mesh", col, root)
    collider(root.name + "_pole", cone(0.2, 0.2, 3.0, 6), T(z=1.5), col, root)
    return obj


def wall_segment(root, col, seed, length=4.0, height=0.9, crumble=0.3):
    """Dry-stone wall from x = 0 to x = length: modular, snap the next one at +length.
    Pieces shorter than 3 m are end pieces: the wall decays toward its end."""
    b = Builder(seed)
    rng = b.rng
    courses = 3
    course_h = height / courses
    is_end = length < 3.0
    for c in range(courses):
        x = rng.uniform(0.0, 0.3) if c % 2 else 0.0
        while x < length - 0.15:
            w = min(rng.uniform(0.45, 0.85), length - x)
            keep_h = height * (1.0 - 0.75 * (x / length)) if is_end else height
            skip = (c == courses - 1 and rng.random() < crumble) or c * course_h > keep_h
            if not skip:
                b.part("rock", box(w * 0.94, rng.uniform(0.55, 0.72), course_h * rng.uniform(0.85, 1.05)),
                       T(x + w / 2, rng.uniform(-0.05, 0.05), c * course_h + course_h / 2)
                       @ R(rng.uniform(-0.08, 0.08), "Z"), jitter=0.03)
            x += w
    if is_end:  # tumbled stones past the broken end
        for i in range(4):
            r = rng.uniform(0.15, 0.25)
            b.part("rock", ico(r, 1), T(length + rng.uniform(-0.3, 0.6), rng.uniform(-0.8, 0.8), r * 0.6)
                   @ S(1.3, 1.0, 0.7), jitter=0.04)
    return b.finish(f"{root.name}-convcol", col, root)


def fire_ring(root, col, seed):
    """Cold hearth: a ring of stones around charred logs."""
    b = Builder(seed)
    rng = b.rng
    for i in range(9):
        a = i / 9 * math.tau + rng.uniform(-0.1, 0.1)
        r = rng.uniform(0.16, 0.22)
        b.part("rock", ico(r, 1), T(math.cos(a) * 0.75, math.sin(a) * 0.75, r * 0.5) @ S(1.2, 1.0, 0.75), jitter=0.03)
    for i in range(3):
        a = i * 2.2
        b.part("bark", cone(0.07, 0.05, 0.9, 5), T(math.cos(a) * 0.1, math.sin(a) * 0.1, 0.08)
               @ R(a, "Z") @ R(math.pi / 2 - 0.15, "Y"))
    return b.finish(f"{root.name}_mesh", col, root)


def ger_ruin(root, col, seed, radius=3.0):
    """Collapsed ger: a broken lattice wall, fallen roof poles, the crown ring on the ground,
    and a door frame still standing (faded ochre - the player's colour). Door faces -x."""
    b = Builder(seed)
    rng = b.rng
    wall_h = 1.3
    a0, a1 = math.radians(-125), math.radians(125)  # wall runs round the +x side
    steps = 26
    da = (a1 - a0) / steps
    for i in range(steps):
        a = a0 + da * i
        sag = 0.6 + 0.4 * math.sin(i * 0.7 + seed)  # parts of the wall have slumped
        h = wall_h * sag
        p0 = Vector((math.cos(a) * radius, math.sin(a) * radius, 0.0))
        p1 = Vector((math.cos(a + da) * radius, math.sin(a + da) * radius, 0.0))
        b.part("deadwood", box(1, 1, 1), bar(p0, p1 + Vector((0, 0, h)), 0.04))
        b.part("deadwood", box(1, 1, 1), bar(p1, p0 + Vector((0, 0, h)), 0.04))
        if i % 3 == 0 and sag > 0.75:  # rim survives in places
            b.part("deadwood", box(1, 1, 1), bar(p0 + Vector((0, 0, h)), p1 + Vector((0, 0, h)), 0.05))
    for i in range(12):  # roof poles fallen inward
        a = rng.uniform(a0, a1)
        start = Vector((math.cos(a) * radius, math.sin(a) * radius, rng.uniform(0.2, 1.0)))
        end = Vector((math.cos(a + rng.uniform(-0.5, 0.5)) * rng.uniform(0.0, 1.2),
                      math.sin(a + rng.uniform(-0.5, 0.5)) * rng.uniform(0.0, 1.2), 0.05))
        b.part("deadwood", box(1, 1, 1), bar(start, end, 0.05))
    crown = R(0.25, "X")
    for i in range(8):  # toono (crown ring) lying tilted near the centre
        a, a2 = i / 8 * math.tau, (i + 1) / 8 * math.tau
        p0 = Vector((math.cos(a) * 0.6 + 0.4, math.sin(a) * 0.6, 0.25))
        p1 = Vector((math.cos(a2) * 0.6 + 0.4, math.sin(a2) * 0.6, 0.25))
        b.part("deadwood", box(1, 1, 1), crown @ bar(p0, p1, 0.08))
    door_x = -radius - 0.05
    for y in (-0.45, 0.45):
        b.part("cloak", box(0.1, 0.1, 1.6), T(door_x, y, 0.8))
    b.part("cloak", box(0.12, 1.05, 0.12), T(door_x, 0, 1.6) @ R(0.12, "X"))
    return b.finish(f"{root.name}_mesh", col, root)


# --- war debris and traveller traces (Heavens call) -----------------------------------------
# Remnants of a forgotten battle: weapons and armour only, never bodies or bones.

def sector(r, thickness, a0, a1, segs, centre=(0.0, 0.0)):
    """Pie slice prism from angle a0 to a1 (CCW), `segs` facets round the arc, apex at `centre`:
    a round shield with a wedge missing (an arc of less than a full turn)."""
    def create(bm, matrix):
        h = thickness / 2
        c = Vector((centre[0], centre[1], 0.0))
        tc = bm.verts.new(matrix @ (c + Vector((0, 0, h))))
        bc = bm.verts.new(matrix @ (c + Vector((0, 0, -h))))
        tops, bots = [], []
        for i in range(segs + 1):
            a = a0 + (a1 - a0) * i / segs
            p = Vector((math.cos(a) * r, math.sin(a) * r, 0.0))
            tops.append(bm.verts.new(matrix @ (p + Vector((0, 0, h)))))
            bots.append(bm.verts.new(matrix @ (p + Vector((0, 0, -h)))))
        for i in range(segs):
            bm.faces.new((tc, tops[i], tops[i + 1]))
            bm.faces.new((bc, bots[i + 1], bots[i]))
            bm.faces.new((tops[i], bots[i], bots[i + 1], tops[i + 1]))
        bm.faces.new((tc, bc, bots[0], tops[0]))
        bm.faces.new((tc, tops[-1], bots[-1], bc))
    return create


def dome(radius, u=10, v=6):
    """Upper half of a UV sphere with its rim capped (a helmet shell)."""
    def create(bm, matrix):
        before = set(bm.verts)
        bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
        below = [x for x in bm.verts if x not in before and x.co.z < -1e-4]
        bmesh.ops.delete(bm, geom=below, context="VERTS")
        new = [x for x in bm.verts if x not in before]
        rim = [e for e in bm.edges if e.is_boundary and e.verts[0] in new and e.verts[1] in new]
        bmesh.ops.holes_fill(bm, edges=rim, sides=0)
        bmesh.ops.transform(bm, matrix=matrix, verts=new)
    return create


def plate(w, h, shape, nx=4, ny=5, thickness=0.018):
    """Curved sheet of armour: a grid spanning [-w/2, w/2] x [-h/2, h/2], each vertex moved by
    shape(x, y) -> (x, y, z), then given thickness."""
    def create(bm, matrix):
        before = set(bm.verts)
        bmesh.ops.create_grid(bm, x_segments=nx, y_segments=ny, size=1.0)
        new = [x for x in bm.verts if x not in before]
        mx = max(abs(x.co.x) for x in new) or 1.0
        my = max(abs(x.co.y) for x in new) or 1.0
        for x in new:
            x.co = Vector(shape(x.co.x / mx * w / 2, x.co.y / my * h / 2))
        faces = list({f for x in new for f in x.link_faces})
        bmesh.ops.solidify(bm, geom=faces, thickness=thickness)
        new = [x for x in bm.verts if x not in before]
        bmesh.ops.transform(bm, matrix=matrix, verts=new)
    return create


def ribbon(points, width, thickness=0.012):
    """Flat strip of cloth along `points` (x, y, z), `width` wide across the strip's own
    horizontal side vector, with both faces showing (two strips, opposite windings)."""
    def create(bm, matrix):
        pts = [Vector(p) for p in points]
        rows = []
        for i, p in enumerate(pts):
            d = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            side = d.cross(Vector((0, 0, 1)))
            side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
            up = side.cross(d).normalized()
            rows.append((p, side * width / 2, up * thickness / 2))
        for sign in (1, -1):
            vs = [(bm.verts.new(matrix @ (p - s + u * sign)), bm.verts.new(matrix @ (p + s + u * sign)))
                  for p, s, u in rows]
            for i in range(len(vs) - 1):
                quad = (vs[i][0], vs[i][1], vs[i + 1][1], vs[i + 1][0])
                bm.faces.new(quad if sign > 0 else tuple(reversed(quad)))
    return create


def shield_broken(root, col, seed, radius=0.45):
    """Round wooden shield with an iron rim and boss, a wedge broken out; lies tilted on the
    ground, half sunk, with the broken wedge fallen beside it."""
    b = Builder(seed)
    rng = b.rng
    gap0, gap1 = math.radians(20), math.radians(78)  # the missing wedge
    tilt = T(0.0, 0.0, 0.06) @ R(0.24, "Y") @ R(-0.08, "X")
    segs = 11
    verts = b.part("weathered_wood", sector(radius, 0.035, gap1, gap0 + math.tau, segs, centre=(0.07, 0.09)),
                   tilt, jitter=0.006)
    inv = tilt.inverted()
    for v in verts:  # ragged wood where the wedge broke away
        local = inv @ v.co
        a = math.atan2(local.y, local.x) % math.tau
        near_gap = min(abs(a - gap0), abs(a - gap1), abs(a - gap0 - math.tau)) < 0.45
        if near_gap and local.xy.length > radius * 0.6:
            shrink = rng.uniform(0.82, 0.93)
            local.x *= shrink
            local.y *= shrink
            v.co = tilt @ local
    for i in range(segs):  # rusted iron rim, broken off past the gap
        if i in (0, segs - 1):
            continue
        a, a2 = gap1 + (math.tau - (gap1 - gap0)) * i / segs, gap1 + (math.tau - (gap1 - gap0)) * (i + 1) / segs
        p0 = Vector((math.cos(a), math.sin(a), 0)) * (radius + 0.01)
        p1 = Vector((math.cos(a2), math.sin(a2), 0)) * (radius + 0.01)
        b.part("rusted_metal", box(1, 1, 1), tilt @ bar(p0, p1, 0.035))
    b.part("rusted_metal", ico(0.1, 1), tilt @ T(z=0.02) @ S(1.0, 1.0, 0.55), jitter=0.008)
    b.part("rusted_metal", box(0.5, 0.05, 0.012), tilt @ T(-0.08, -0.05, -0.02) @ R(0.5, "Z"))  # back strap iron
    # the broken wedge, fallen flat a little way off
    b.part("weathered_wood", sector(radius * 0.72, 0.035, gap0 + 0.06, gap1 - 0.08, 2),
           T(0.62, 0.42, 0.018) @ R(2.4, "Z") @ R(math.pi, "X"), jitter=0.008)
    return b.finish(f"{root.name}_mesh", col, root)


def sword_planted(root, col, seed):
    """Rusted sword driven into the ground at an angle, its crossguard bent."""
    b = Builder(seed)
    rng = b.rng
    m = R(0.36, "Y") @ R(-0.14, "X")  # planted at an angle; tip ~0.2 m in the ground
    verts = b.part("rusted_metal", cone(0.006, 0.032, 1.0, 4), m @ T(z=0.3) @ S(1.0, 0.25, 1.0))
    for v in verts:  # notched, pitted edge
        local = m.inverted() @ v.co
        if abs(local.x) > 0.012 and local.z > 0.0:
            local.x *= rng.uniform(0.75, 1.0)
            v.co = m @ local
    b.part("rusted_metal", box(0.14, 0.03, 0.026), m @ T(-0.065, 0, 0.8) @ R(0.42, "Y"))  # bent down
    b.part("rusted_metal", box(0.13, 0.03, 0.026), m @ T(0.064, 0, 0.81) @ R(-0.06, "Y"))
    b.part("weathered_wood", cone(0.017, 0.015, 0.14, 5), m @ T(z=0.89), jitter=0.002)
    b.part("rusted_metal", ico(0.032, 1), m @ T(z=0.975) @ S(1.0, 0.7, 0.9))
    for i in range(3):  # stones kicked up around the blade
        a = i * 2.3 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.04, 0.07)
        b.part("rock", ico(r, 1), T(math.cos(a) * 0.12 - 0.05, math.sin(a) * 0.1, r * 0.3) @ S(1.3, 1.0, 0.6), jitter=0.01)
    return b.finish(f"{root.name}_mesh", col, root)


def helmet(root, col, seed):
    """Dented open-faced helmet with a nasal guard, lying on its side."""
    b = Builder(seed)
    m = T(-0.04, 0.0, 0.135) @ R(1.42, "Y") @ R(0.3, "Z")  # on its side; opening faces -x
    shape = S(1.0, 1.18, 1.08)
    verts = b.part("rusted_metal", dome(0.15), m @ shape)
    inv = m.inverted()
    for v in verts:  # the dent, on the side that faces the sky
        local = inv @ v.co
        if local.x < -0.07 and local.z > 0.05:
            local.x += 0.045 * min((-local.x - 0.07) / 0.08, 1.0)
            v.co = m @ local
    b.part("rusted_metal", cone(0.156, 0.16, 0.03, 10), m @ S(1.0, 1.18, 1.0) @ T(z=0.012))  # brow band
    b.part("monolith", cone(0.145, 0.145, 0.004, 10), m @ S(1.0, 1.18, 1.0) @ T(z=-0.004))  # dark inside
    b.part("rusted_metal", box(0.032, 0.012, 0.1), m @ T(0, -0.182, -0.035) @ R(-0.12, "X"))  # nasal
    b.part("rusted_metal", box(0.075, 0.012, 0.11), m @ T(0.13, 0.08, -0.06) @ R(0.25, "Z") @ R(0.35, "Y"))  # cheek plate
    return b.finish(f"{root.name}_mesh", col, root)


def breastplate(root, col, seed):
    """Breastplate lying face down on its keel, split by a crack; rolled rims at the neck and
    the waist, cut-outs for the arms."""
    b = Builder(seed)
    rng = b.rng
    w, h = 0.42, 0.5

    def curve(x, y):
        t = y / h + 0.5  # 0 at the waist, 1 at the shoulders
        x *= 0.8 + 0.2 * t  # narrower at the waist
        if t > 0.7 and abs(x) > 0.12:
            x *= 1.0 - 0.6 * (t - 0.7)  # arm holes
        if t > 0.75 and abs(x) < 0.1:
            y -= 0.08 * (1.0 - (x / 0.1) ** 2)  # neck opening
        z = 0.3 * abs(x) + 0.9 * x * x + 0.4 * y * y  # the keel rests on the ground
        return (x, y, z)

    def half(left):
        """Shape for one half: the w/2-wide grid moved to its side, the crack at x = 0."""
        return lambda x, y: curve(x - w / 4 if left else x + w / 4, y)

    def rim(points, place):
        pts = [Vector(curve(x, y)) + Vector((0, 0, 0.012)) for x, y in points]
        for p0, p1 in zip(pts, pts[1:]):
            b.part("rusted_metal", box(1, 1, 1), place @ bar(p0, p1, 0.024))

    left_place = T(0, 0, 0.004)
    right_place = T(0.014, -0.012, 0.008) @ R(-0.05, "Z") @ R(-0.04, "Y")
    for left, place in ((True, left_place), (False, right_place)):
        verts = b.part("rusted_metal", plate(w / 2, h, half(left), nx=3, ny=6), place)
        inv = place.inverted()
        for v in verts:  # jagged crack along the inner edge
            local = inv @ v.co
            if abs(local.x) < 0.012:
                local.x += rng.uniform(-0.014, 0.014)
                v.co = place @ local
    rim([(-0.2, 0.23), (-0.1, 0.25), (-0.06, 0.205), (-0.01, 0.19)], left_place)  # neck, left
    rim([(0.01, 0.19), (0.06, 0.205), (0.1, 0.25)], right_place)  # neck, right
    rim([(-0.2, -0.25), (-0.1, -0.25), (-0.01, -0.25)], left_place)  # waist; the right part broke off
    return b.finish(f"{root.name}_mesh", col, root)


def spear_broken(root, col, seed):
    """Spear snapped in two: the head end with its rusted blade, and the splintered butt end."""
    b = Builder(seed)
    rng = b.rng

    def shaft(length, place):
        verts = b.part("weathered_wood", cone(0.021, 0.019, length, 5), place @ R(math.pi / 2, "Y"), jitter=0.002)
        inv = place.inverted()
        for v in verts:  # splintered snapped end at -x
            local = inv @ v.co
            if local.x < -length / 2 + 0.01:
                local.x -= rng.uniform(0.0, 0.07)
                v.co = place @ local
        for i in range(2):
            b.part("weathered_wood", cone(0.008, 0.0, 0.12, 3),
                   place @ T(-length / 2 - 0.03, rng.uniform(-0.01, 0.01), rng.uniform(-0.01, 0.01))
                   @ R(-math.pi / 2 + rng.uniform(-0.25, 0.25), "Y"))

    head_end = T(0.0, 0.0, 0.021) @ R(0.12, "Z")
    shaft(0.95, head_end)
    b.part("rusted_metal", cone(0.024, 0.017, 0.11, 5), head_end @ T(0.53, 0, 0.002) @ R(math.pi / 2, "Y"))
    b.part("rusted_metal", cone(0.045, 0.0, 0.3, 4), head_end @ T(0.73, 0, 0.004) @ R(math.pi / 2, "Y") @ S(1.0, 0.28, 1.0))
    butt = T(-0.35, 0.38, 0.021) @ R(2.6, "Z")
    shaft(0.7, butt)
    b.part("rusted_metal", cone(0.024, 0.024, 0.05, 5), butt @ T(0.37, 0, 0) @ R(math.pi / 2, "Y"))  # ferrule
    return b.finish(f"{root.name}_mesh", col, root)


def scarf_worn(root, col, seed):
    """A traveller's faded blue scarf draped over a standing stone, one end lifting in the wind.
    The cloth uses the `cloth` palette material, so it sways."""
    b = Builder(seed)
    sx, sy, sz = 0.32, 0.26, 0.5
    b.part("rock", ico(1.0, 1), T(z=0.42) @ S(sx, sy, sz), jitter=0.02)
    over = [(-0.02, -0.62, 0.012), (-0.03, -0.42, 0.02), (-0.02, -0.32, 0.16), (0.0, -0.3, 0.46),
            (0.01, -0.22, 0.74), (0.0, -0.1, 0.88), (0.0, 0.06, 0.9), (0.01, 0.2, 0.76),
            (0.02, 0.29, 0.58), (0.05, 0.36, 0.48), (0.12, 0.5, 0.5), (0.2, 0.66, 0.56)]
    b.part("cloth", ribbon(over, 0.2))
    obj = b.finish(f"{root.name}_mesh", col, root)
    collider(root.name + "_stone", ico(1.0, 1), T(z=0.42) @ S(sx, sy, sz), col, root)
    return obj


# --- landmark ----------------------------------------------------------------------------

def godot_xform(pos, yaw=0.0, roll=0.0):
    """Blender matrix for a Godot node transform (Ry(yaw) * Rz(roll), Y up)."""
    g = Matrix.Rotation(yaw, 3, "Y") @ Matrix.Rotation(roll, 3, "Z")
    c = GODOT_TO_BLENDER
    m = (c @ g @ c.transposed()).to_4x4()
    m.translation = c @ Vector(pos)
    return m


def landmark(root, col, seed):
    """Outcrop + leaning monolith with a hole + capstone. Placement matches the Stage 1-3
    blockout (same Godot transforms), so the composition is unchanged."""
    b = Builder(seed)
    rng = b.rng
    verts = b.part("rock", ico(1.0, 2), S(11.0, 9.0, 5.5), jitter=0.0)
    for v in verts:  # broken ledges: random push along the normal, then a flattened crown
        n = v.co.normalized()
        v.co += n * rng.uniform(-0.9, 1.1)
        if v.co.z > 4.3:
            v.co.z = 4.3 + (v.co.z - 4.3) * 0.3
    for i in range(4):  # rubble fallen from the outcrop
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.8, 1.6)
        b.part("rock", ico(r, 1), T(math.cos(a) * 11.5, math.sin(a) * 9.5, r * 0.5)
               @ S(1.2, 1.0, 0.75), jitter=0.15 * r)
    outcrop = b.finish(f"{root.name}_outcrop", col, root)

    b = Builder(seed + 1)
    mono_m = godot_xform((0.5, 14.5, -0.5), yaw=0.35, roll=-0.14)

    def slab(bm, matrix):
        res = bmesh.ops.create_cube(bm, size=1.0, matrix=matrix @ Matrix.Diagonal((2.6, 1.3, 22.0, 1)))
        bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if e.verts[0] in res["verts"] and e.verts[1] in res["verts"]
                                             and abs((e.verts[0].co - e.verts[1].co).normalized().dot(matrix.to_3x3() @ Vector((0, 0, 1)))) > 0.9],
                                  cuts=5, use_grid_fill=True)

    verts = b.part("monolith", slab, mono_m)
    inv = mono_m.inverted()
    for v in verts:  # taper toward the top and chip the edges
        local = inv @ v.co
        k = (local.z + 11.0) / 22.0
        local.x *= 1.0 - 0.18 * k
        local.x += rng.uniform(-0.08, 0.08)
        local.y += rng.uniform(-0.05, 0.05)
        v.co = mono_m @ local
    b.part("monolith", box(4.2, 1.6, 0.9), godot_xform((2.0, 25.2, -0.6), yaw=0.35, roll=-0.3), jitter=0.06)
    mono = b.finish(f"{root.name}_monolith", col, root)

    # The hole: sky shows through near the top - a silhouette nobody forgets.
    cutter_mesh = bpy.data.meshes.new("cutter")
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=7, radius1=0.75, radius2=0.75, depth=4.0,
                          matrix=mono_m @ T(z=6.0) @ R(math.pi / 2, "X"))
    bm.to_mesh(cutter_mesh)
    bm.free()
    cutter = bpy.data.objects.new("cutter", cutter_mesh)
    col.objects.link(cutter)
    mod = mono.modifiers.new("hole", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    evaluated = mono.evaluated_get(deps)
    mono.data = bpy.data.meshes.new_from_object(evaluated)
    mono.modifiers.clear()
    bpy.data.objects.remove(cutter)
    for poly in mono.data.polygons:
        poly.use_smooth = False
    return outcrop, mono


# --- kit definition -------------------------------------------------------------------------

ASSETS = [
    # name, builder, kwargs
    ("tree_spruce_a", spruce, dict(seed=11, height=10.0, tiers=4, radius=2.0, lean=0.03)),
    ("tree_spruce_b", spruce, dict(seed=23, height=12.5, tiers=6, radius=1.45, lean=0.05, crooked_top=True, squash=0.8)),
    ("tree_larch", larch, dict(seed=37, height=11.0)),
    ("rock_boulder_a", boulder, dict(seed=5, size=(1.4, 1.1, 0.95))),
    ("rock_boulder_b", boulder, dict(seed=8, size=(1.8, 1.2, 0.6), flat_top=0.3)),
    ("rock_shard", shard, dict(seed=13, height=3.6, base_r=0.75)),
    ("ground_mound_a", mound, dict(seed=3, length=16.0, width=12.0, height=1.6)),
    ("ground_mound_b", mound, dict(seed=4, length=26.0, width=9.0, height=2.4)),
    ("prop_cairn", cairn, dict(seed=17)),
    ("prop_log", fallen_log, dict(seed=19)),
    ("prop_stump", stump, dict(seed=29)),
    ("landmark_monolith", landmark, dict(seed=41)),
    ("prop_khadag_post", khadag_post, dict(seed=43)),
    ("landmark_spirit_banner", spirit_banner, dict(seed=47, height=18.0)),
    ("wall_segment", wall_segment, dict(seed=53)),
    ("wall_end", wall_segment, dict(seed=59, length=2.0)),
    ("prop_fire_ring", fire_ring, dict(seed=61)),
    ("prop_ger_ruin", ger_ruin, dict(seed=67)),
    ("prop_shield_broken", shield_broken, dict(seed=71)),
    ("prop_sword_planted", sword_planted, dict(seed=73)),
    ("prop_helmet", helmet, dict(seed=79)),
    ("prop_breastplate", breastplate, dict(seed=83)),
    ("prop_spear_broken", spear_broken, dict(seed=89)),
    ("prop_scarf_worn", scarf_worn, dict(seed=97)),
]


def build():
    kit = bpy.data.collections.get("Kit")
    if kit:
        for obj in list(kit.all_objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        for child in list(kit.children):
            bpy.data.collections.remove(child)
    else:
        kit = bpy.data.collections.new("Kit")
        bpy.context.scene.collection.children.link(kit)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    roots = []
    x = 0.0
    for name, builder, kwargs in ASSETS:
        col = bpy.data.collections.new(name)
        kit.children.link(col)
        root = bpy.data.objects.new(name, None)
        root.empty_display_size = 0.5
        col.objects.link(root)
        builder(root, col, **kwargs)
        # lay assets out in a row for previewing; export puts each back at the origin
        width = {"landmark_monolith": 30.0, "prop_ger_ruin": 10.0}.get(name, 28.0 if name.startswith("ground") else 6.0)
        root.location.x = x + width / 2
        x += width
        roots.append(root)
    return roots


def export(roots):
    os.makedirs(EXPORT_DIR, exist_ok=True)
    for root in roots:
        saved = root.location.copy()
        root.location = (0, 0, 0)
        bpy.context.view_layer.update()
        bpy.ops.object.select_all(action="DESELECT")
        for obj in [root, *root.children_recursive]:
            obj.select_set(True)
        path = os.path.join(EXPORT_DIR, root.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                  export_apply=True, export_yup=True, export_materials="EXPORT")
        root.location = saved
        print("exported", path)
    bpy.ops.object.select_all(action="DESELECT")


_roots = build()
export(_roots)
os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print("saved", BLEND_PATH)
