"""Terrain replica - granite rock shape set + ger.

Run headless: `blender -b --factory-startup -P assets/blender/build_granite.py`.
Builds every shape from scratch in an empty scene and exports one GLB per shape into
assets/meshes/rocks_granite/. Separate from build_kit.py: the kit GLBs stay byte-for-byte.

Conventions (docs/ASSET_PIPELINE.md, "Granite shape set"):
  * Rock shapes are normalised to a unit box: 1 x 1 x 1 m, base at z = 0 (Godot y = 0), centred
    on X/Y (Godot X/Z). Godot scales each instance to the measured (length, height, width), so the
    proportions modelled here only shape the surface, never the size.
  * The ger is real size: 6.0 m diameter, 1.6 m wall, 2.4 m crown; scaled in Godot per ger.
  * Colour is flat per-face vertex colour (COLOR_0). Material names are palette names: `granite`,
    `felt` (res://assets/materials/<name>.tres, flat_color with use_vertex_color on).
  * Blender Z up; the exporter converts to Godot Y up (Godot z = -Blender y, so the ger's door at
    Blender -y faces Godot +z = south in the replica frame).
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

PROJECT = os.environ.get("ENV_FORGE_ROOT", r"D:/DevEnv/GDOT/environment-lab")
EXPORT_DIR = os.path.join(PROJECT, "assets", "meshes", "rocks_granite")


def srgb(r, g, b):
    """Display (sRGB) colour -> linear, which is what colour attributes and glTF COLOR_0 store."""
    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), 1.0)


# Vertex colours (sRGB as authored). Granite sits next to the kit's `rock` (0.31, 0.32, 0.32): the
# same grey value range, warmed towards tan/ochre where the surface has weathered longest.
COLOURS = {
    "granite": srgb(0.40, 0.395, 0.38),       # exposed inner sheet, mid grey
    "granite_fresh": srgb(0.52, 0.50, 0.47),  # fresh break / sheet edge, lighter, faintly pink
    "granite_weathered": srgb(0.50, 0.43, 0.32),  # old outer skin, tan/ochre
    "granite_crack": srgb(0.24, 0.235, 0.225),    # joint crack, shadowed groove
    "felt": srgb(0.86, 0.85, 0.81),           # white felt
    "felt_dust": srgb(0.60, 0.56, 0.49),      # dusty skirt at the ground
    "rope": srgb(0.36, 0.30, 0.24),           # girth ropes
    "door": srgb(0.66, 0.33, 0.13),           # painted wooden door, orange
    "wood": srgb(0.30, 0.22, 0.15),           # toono (crown ring)
}


# --- helpers ----------------------------------------------------------------------

def material(name):
    """Palette-named material; preview shows the colour attribute (Godot swaps in <name>.tres)."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)  # Blender 5: node tree on by default
        nodes = mat.node_tree.nodes
        bsdf = next(n for n in nodes if n.type == "BSDF_PRINCIPLED")
        attr = nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Color"
        mat.node_tree.links.new(attr.outputs[0], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.95
    return mat


class Shape:
    """One bmesh with a per-face colour key; finish() writes flat corner colours."""

    def __init__(self, seed):
        self.bm = bmesh.new()
        self.rng = random.Random(seed)
        self.colour = self.bm.faces.layers.int.new("colour")
        self.keys = []

    def paint(self, faces, key):
        if key not in self.keys:
            self.keys.append(key)
        for f in faces:
            f[self.colour] = self.keys.index(key)

    def normalise(self):
        """Non-uniform scale to the unit box: x, y in [-0.5, 0.5], z in [0, 1]."""
        lo = Vector([min(v.co[i] for v in self.bm.verts) for i in range(3)])
        hi = Vector([max(v.co[i] for v in self.bm.verts) for i in range(3)])
        size = hi - lo
        for v in self.bm.verts:
            v.co = Vector((
                (v.co.x - lo.x) / size.x - 0.5,
                (v.co.y - lo.y) / size.y - 0.5,
                (v.co.z - lo.z) / size.z,
            ))

    def finish(self, name, mat_name):
        bmesh.ops.triangulate(self.bm, faces=self.bm.faces[:])
        self.bm.normal_update()
        mesh = bpy.data.meshes.new(name)
        colours = [COLOURS[self.keys[f[self.colour]]] for f in self.bm.faces]
        self.bm.to_mesh(mesh)
        self.bm.free()
        attr = mesh.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
        for poly in mesh.polygons:
            poly.use_smooth = False
            for li in poly.loop_indices:
                attr.data[li].color = colours[poly.index]
        mesh.color_attributes.active_color = attr
        mesh.color_attributes.render_color_index = 0
        mesh.materials.append(material(mat_name))
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def rounded_block(shape, size, cuts, roundness, rough, freq):
    """Subdivided cube pulled towards an ellipsoid, then displaced with low-frequency noise."""
    bm = shape.bm
    bmesh.ops.create_cube(bm, size=2.0)
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    offset = Vector([shape.rng.uniform(-50, 50) for _ in range(3)])
    for v in bm.verts:
        sphere = v.co.normalized()
        d = v.co.lerp(sphere, roundness)
        d *= 1.0 + rough * noise.noise(d * freq + offset)
        v.co = Vector((d.x * size[0], d.y * size[1], d.z * size[2]))
    shape.paint(bm.faces, "granite")


def flatten_bottom(shape, keep=0.12):
    """Squash everything below `keep` of the height onto a near-flat base (pieces stack)."""
    zs = [v.co.z for v in shape.bm.verts]
    lo, hi = min(zs), max(zs)
    floor = lo + (hi - lo) * keep
    for v in shape.bm.verts:
        if v.co.z < floor:
            v.co.z = floor - (floor - v.co.z) * 0.12


def exfoliate(shape, direction, cos_limit, thickness, top_key="granite_weathered"):
    """Onion-skin sheet: faces facing `direction` rise by `thickness` as one outer layer.

    The raised top keeps the old weathered skin; its rim is a fresh break; the rest of the rock is
    the exposed inner sheet."""
    bm = shape.bm
    bm.normal_update()
    centre = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    d = direction.normalized()
    region = [f for f in bm.faces if (f.calc_center_median() - centre).normalized().dot(d) > cos_limit]
    if not region:
        return
    out = bmesh.ops.extrude_face_region(bm, geom=region)
    verts = [e for e in out["geom"] if isinstance(e, bmesh.types.BMVert)]
    for v in verts:
        v.co += (v.co - centre).normalized() * thickness
    tops = set(region)
    rim = {f for v in verts for f in v.link_faces} - tops
    shape.paint(rim, "granite_fresh")
    shape.paint(tops, top_key)


def joint_crack(shape, normal, offset, width, depth):
    """A joint: faces straddling a plane turn dark and their verts sink towards the core."""
    bm = shape.bm
    n = normal.normalized()
    centre = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
    plane = centre + n * offset
    band = [v for v in bm.verts if abs((v.co - plane).dot(n)) < width]
    for v in band:
        radial = v.co - centre
        radial -= n * radial.dot(n)
        v.co -= radial.normalized() * depth if radial.length > 1e-6 else Vector()
    faces = {f for f in bm.faces if any(abs((v.co - plane).dot(n)) < width * 0.5 for v in f.verts)
             and min((v.co - plane).dot(n) for v in f.verts) < 0 < max((v.co - plane).dot(n) for v in f.verts)}
    shape.paint(faces, "granite_crack")


def polar(azimuth_deg, elevation_deg):
    a, e = math.radians(azimuth_deg), math.radians(elevation_deg)
    return Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))


# --- shapes ---------------------------------------------------------------------------

def granite_round(name, seed, size, sheets, crack):
    """Rounded weathered boulder: ellipsoidal block, exfoliation sheets (thickness as a fraction
    of the smallest axis), an optional joint crack (azimuth, elevation, offset along x)."""
    s = Shape(seed)
    rounded_block(s, size, cuts=3, roundness=0.8, rough=0.12, freq=1.1)
    flatten_bottom(s)
    for azimuth, elevation, cos_limit, thickness in sheets:
        exfoliate(s, polar(azimuth, elevation), cos_limit, thickness * min(size))
    if crack:
        joint_crack(s, polar(crack[0], crack[1]), crack[2] * size[0], 0.16 * min(size), 0.06 * min(size))
    s.normalise()
    return s.finish(name, "granite")


def granite_slab(name, seed, size, taper, sheet):
    """Flattened sheet rock: low rounded block, gently domed top, one end thicker."""
    s = Shape(seed)
    rounded_block(s, size, cuts=3, roundness=0.45, rough=0.08, freq=0.9)
    for v in s.bm.verts:
        t = v.co.x / size[0]  # -1..1 along the slab
        if v.co.z > 0:
            v.co.z *= 1.0 + taper * t
    flatten_bottom(s, keep=0.3)
    exfoliate(s, polar(sheet[0], 80), sheet[1], 0.18 * size[2])
    s.normalise()
    return s.finish(name, "granite")


def granite_split(name, seed, size, cut_azimuth, gap, lean_deg):
    """A boulder cleaved along a joint: a boolean slot through it leaves two halves with fresh
    faces, and the half on the +n side leans out about its outer foot."""
    s = Shape(seed)
    rounded_block(s, size, cuts=2, roundness=0.8, rough=0.1, freq=1.0)
    flatten_bottom(s)
    exfoliate(s, polar(cut_azimuth + 90, 55), 0.55, 0.08 * min(size))
    rock_mesh = bpy.data.meshes.new(name + "_uncut")
    s.bm.to_mesh(rock_mesh)
    rock = bpy.data.objects.new(rock_mesh.name, rock_mesh)
    cutter_mesh = bpy.data.meshes.new(name + "_cutter")
    cbm = bmesh.new()
    bmesh.ops.create_cube(cbm, size=1.0)
    cbm.to_mesh(cutter_mesh)
    cbm.free()
    cutter = bpy.data.objects.new(cutter_mesh.name, cutter_mesh)
    tilt = math.radians(6.0)  # joints are rarely plumb
    cutter.matrix_world = (Matrix.Rotation(math.radians(cut_azimuth), 4, "Z") @ Matrix.Rotation(tilt, 4, "Y")
                           @ Matrix.Diagonal((gap, 4 * max(size), 4 * max(size), 1)))
    for obj in (rock, cutter):
        bpy.context.scene.collection.objects.link(obj)
    mod = rock.modifiers.new("cleave", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cutter
    mod.solver = "EXACT"
    depsgraph = bpy.context.evaluated_depsgraph_get()
    s.bm.free()
    s.bm = bmesh.new()
    s.bm.from_object(rock, depsgraph)
    for obj, mesh in ((rock, rock_mesh), (cutter, cutter_mesh)):
        bpy.data.objects.remove(obj)
        bpy.data.meshes.remove(mesh)
    bm = s.bm
    s.colour = bm.faces.layers.int.get("colour") or bm.faces.layers.int.new("colour")
    bm.normal_update()
    n = (Matrix.Rotation(math.radians(cut_azimuth), 3, "Z") @ Matrix.Rotation(tilt, 3, "Y")) @ Vector((1, 0, 0))
    s.paint([f for f in bm.faces if abs(f.normal.dot(n)) > 0.98
             and abs(f.calc_center_median().dot(n)) < gap * 0.6], "granite_fresh")
    # the half on the +n side leans out about its outer foot (pieces: connected components)
    plus = [v for v in bm.verts if v.co.dot(n) > 0]
    foot_d = max(v.co.dot(n) for v in plus)
    foot = Vector((n.x, n.y, 0.0)).normalized() * foot_d
    foot.z = min(v.co.z for v in bm.verts)
    axis = Vector((0, 0, 1)).cross(n).normalized()
    rot = Matrix.Rotation(-math.radians(lean_deg), 3, axis)
    for v in plus:
        v.co = foot + rot @ (v.co - foot)
    s.normalise()
    return s.finish(name, "granite")


def granite_scree(name, seed, points):
    """Small angular fragment: convex hull of a few points, flat-ish base on z = 0."""
    s = Shape(seed)
    rng = s.rng
    bm = s.bm
    pts = []
    for i in range(3):  # three base corners on the ground
        a = math.radians(i * 120 + rng.uniform(-25, 25))
        r = rng.uniform(0.75, 1.0)
        pts.append(Vector((math.cos(a) * r, math.sin(a) * r * 0.8, 0.0)))
    for i in range(points - 3):  # the rest on a jittered upper shell, so most land on the hull
        a = 2 * math.pi * (i + rng.uniform(0.0, 0.8)) / (points - 3)
        e = math.radians(rng.choice((25, 50, 70)) + rng.uniform(-12, 12))
        r = rng.uniform(0.8, 1.05)
        pts.append(Vector((math.cos(a) * math.cos(e) * r, math.sin(a) * math.cos(e) * r * 0.8,
                           0.15 + math.sin(e) * r * 0.75)))
    for p in pts:
        bm.verts.new(p)
    hull = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    unused = {g for g in hull["geom_unused"] + hull["geom_interior"] if isinstance(g, bmesh.types.BMVert)}
    bmesh.ops.delete(bm, geom=list(unused), context="VERTS")
    bm.normal_update()
    s.paint(bm.faces, "granite")
    s.paint([f for f in bm.faces if f.normal.z > 0.55], "granite_weathered")
    s.paint([f for f in bm.faces if -0.2 < f.normal.z < 0.3 and rng.random() < 0.4], "granite_fresh")
    s.normalise()
    return s.finish(name, "granite")


def ger(name, radius=3.0, wall=1.6, crown=2.4, segments=24):
    """Mongolian ger, real size: felt wall cylinder, shallow roof cone, toono ring on top.

    The footprint is the wall cylinder exactly (no eave overhang), so Godot can scale it to each
    ger's measured diameter. Door faces Blender -y (Godot +z, south)."""
    s = Shape(0)
    bm = s.bm
    toono_r, toono_h = 0.55, 0.06
    rings = [  # (z, radius, colour of the band above this ring)
        (0.0, radius, "felt_dust"),
        (0.22, radius, "felt"),
        (1.05, radius, "rope"),
        (1.12, radius, "felt"),
        (wall - 0.1, radius, "rope"),
        (wall, radius, "felt"),
        (crown - toono_h, toono_r, "wood"),
        (crown, toono_r, None),
    ]
    # Vertices at multiples of 360/segments include +-x and +-y, so the footprint AABB is exactly
    # the diameter. The door is the wall face just east of -y (Blender), i.e. facing south.
    loops = [[bm.verts.new((r * math.cos(2 * math.pi * i / segments), r * math.sin(2 * math.pi * i / segments), z))
              for i in range(segments)] for z, r, _ in rings]
    for k in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            s.paint([bm.faces.new((loops[k][i], loops[k][j], loops[k + 1][j], loops[k + 1][i]))], rings[k][2])
    s.paint([bm.faces.new(loops[-1])], "wood")
    s.paint([bm.faces.new(list(reversed(loops[0])))], "felt_dust")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    door = (-math.pi / 2, -math.pi / 2 + 2 * math.pi / segments)
    for f in bm.faces:
        c = f.calc_center_median()
        if 0.0 < c.z < 1.05 and door[0] < math.atan2(c.y, c.x) < door[1]:
            s.paint([f], "door")
    return s.finish(name, "felt")


SHAPES = [
    # name, builder, kwargs
    ("granite_round_a", granite_round, dict(seed=11, size=(1.3, 1.0, 0.85),
                                            sheets=[(30, 60, 0.45, 0.098)], crack=(100, 10, 0.25))),
    ("granite_round_b", granite_round, dict(seed=23, size=(1.0, 0.9, 0.8),
                                            sheets=[(200, 50, 0.45, 0.098)], crack=(60, 0, 0.3))),
    ("granite_round_c", granite_round, dict(seed=37, size=(1.4, 1.1, 0.7),
                                            sheets=[(300, 75, 0.35, 0.112)], crack=(10, 0, -0.2))),
    ("granite_slab_a", granite_slab, dict(seed=41, size=(1.6, 1.2, 0.35), taper=0.25, sheet=(40, 0.3))),
    ("granite_slab_b", granite_slab, dict(seed=53, size=(1.5, 1.0, 0.3), taper=-0.5, sheet=(220, 0.45))),
    ("granite_split_a", granite_split, dict(seed=67, size=(1.2, 1.0, 0.9), cut_azimuth=15, gap=0.2, lean_deg=10)),
    ("granite_scree_a", granite_scree, dict(seed=71, points=10)),
    ("granite_scree_b", granite_scree, dict(seed=83, points=11)),
    ("granite_scree_c", granite_scree, dict(seed=97, points=12)),
]


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objects = [builder(name, **kwargs) for name, builder, kwargs in SHAPES]
    objects.append(ger("ger"))
    return objects


def export(objects):
    os.makedirs(EXPORT_DIR, exist_ok=True)
    for obj in objects:
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        path = os.path.join(EXPORT_DIR, obj.name + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                                  export_apply=True, export_yup=True, export_materials="EXPORT",
                                  export_vertex_color="ACTIVE")
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        dims = obj.dimensions
        print("exported %s  tris=%d  dims(x, y, z)=(%.3f, %.3f, %.3f)" % (path, tris, dims.x, dims.y, dims.z))


export(build())
