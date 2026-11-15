class_name ReplicaSite
extends Node3D
## A walkable 1:1 replica of a site, built from the offline pipeline's output in
## `<site_dir>/build/` (tools/terrain: `python -I -m replica build <site_dir>`). Nothing here
## chooses a size or a position: every one comes from those files (manifest.json documents them).
##
## - Ground: ReplicaTerrain from core.r32 / ring.r32 / classes.png (y = height - base_elevation).
## - Rocks (rocks_placed.json, Ruling 19): a boulder is one granite shape scaled to
##   (length, top - base, width), long axis along its yaw (clockwise from north), base on the
##   lowest ground under its footprint (never floating), top at the ground under its centre +
##   its height (the pipeline's rock_top_y). Masses are drawn as their packed fill pieces
##   (scatter fill_round / fill_slab, the pipeline's own representation of them); a mass's node
##   is an empty marker and rock_aabb() is the union of its pieces.
## - Scatter (scatter.json): MultiMeshInstance3D per type x shape variant x CELL_M cell, with a
##   visibility range per type; base = the lowest ground under the l x w footprint + y (stacked
##   fill pieces rest on the piece below, Ruling 22).
## - Collision: convex hulls (of the unit shape, scaled per rock) for boulders and for fill
##   pieces over COLLIDE_MIN_M on any axis, one StaticBody3D per cell on layer 1; smaller fill
##   pieces (gap blocks among collided pieces), scree, stones and scrub have none.
## - Gers (manifest structures): ger.glb scaled across to the measured diameter at the measured
##   x/z; its height stays the model's own (the 2.4 m crown of the plan's ger reference).
## - Grass: ReplicaGrass streams GrassField tiles from grass_density.png around the player.
## - Sun: manifest sun azimuth / elevation.
## - Validation (`-- --capture-topdown | --walk-perf | --capture-views [--quit]`): ReplicaCapture.
##
## Build files live under data/, which has a .gdignore, so they are read from the filesystem
## (FileAccess / Image.load_from_file on the globalized path), never through ResourceLoader.

const ROCK_DIR := "res://assets/meshes/rocks_granite/"
const PALETTE_DIR := "res://assets/materials/"
const BUILD_HINT := "run `tools/terrain/.venv/Scripts/python.exe -I -m replica build %s` first"
## Shape variants per placed type (Ruling 23).
const SHAPES := {
	"round": ["granite_round_a", "granite_round_b", "granite_round_c"],
	"slab": ["granite_slab_a", "granite_slab_b"],
	"scree": ["granite_scree_a", "granite_scree_b", "granite_scree_c"],
}
const TYPE_SHAPES := {
	"scree": "scree", "stone": "scree", "fill_round": "round", "fill_slab": "slab",
	"scrub": "scrub", "tree": "tree",
}
## A boulder whose height is under this fraction of its smaller footprint side is a slab shape.
const SLAB_RATIO := 0.35
## Scatter cell size (m) and per-type draw distance (m, from the camera to a cell's centre;
## 0 = always drawn). Draw distances are a performance choice, never a size.
const CELL_M := 128.0
const DRAW_DISTANCE := {
	"stone": 60.0, "scree": 220.0, "scrub": 220.0, "tree": 0.0, "fill_round": 0.0, "fill_slab": 0.0,
}
## Types that get collision (packed tor pieces: the masses you climb).
const SOLID_TYPES := ["fill_round", "fill_slab"]
## A SOLID_TYPES piece gets collision only when it is over this size (m) on some axis: plan
## Task 10 "large rocks (> 1.5 m any axis) get ... collision" (Rulings 26 and 34).
const COLLIDE_MIN_M := 1.5
const ROCK_LAYER := 1
## Scrub has no modelled shape: a low-poly bush built in code (unit box, base y 0), this colour.
const SCRUB_COLOR := Color(0.34, 0.35, 0.22)
## The player starts this far south (+Z) of the first ger.
const SPAWN_SOUTH_M := 15.0

## Site folder (res:// path) holding site.json and build/.
@export var site_dir := "res://data/sites/sumber"
## Optional player (CharacterBody3D) placed at the spawn point; grass follows it.
@export var player: CharacterBody3D
## Optional camera snapped behind the player at spawn (FollowCamera).
@export var follow_camera: Camera3D
## Optional sun, aimed from the manifest's sun azimuth / elevation.
@export var sun: DirectionalLight3D

var terrain: ReplicaTerrain
var grass: ReplicaGrass
var manifest: Dictionary
## Seconds the last build() took, and per stage.
var build_seconds := 0.0
var build_stages := {}

var _built := false
var _core := PackedFloat32Array()
var _n := 0
var _step := 1.0
var _half := 0.0
var _base := 0.0
var _rocks: Array = []
var _rock_nodes := {}   # id -> Node3D
var _mass_boxes := {}   # id -> AABB of its fill pieces
var _rows: Array = []
var _types: PackedStringArray
var _row_base := PackedFloat32Array()  # absolute base (y) per scatter row
var _scatter_nodes := {}  # type -> Array of its MultiMeshInstance3D
var _group_nodes: Array[MultiMeshInstance3D] = []
var _row_group := PackedInt32Array()  # scatter row -> index into _group_nodes (-1: not drawn)
var _row_slot := PackedInt32Array()   # scatter row -> instance index in that MultiMesh
var _row_owner := PackedInt32Array()  # scatter row -> shape owner in its cell's body (-1: none)
var _gers: Array[Node3D] = []
var _shapes := {}       # shape name -> {mesh, scatter, hull, fit} (see _shape)
var _bodies := {}       # Vector2i cell -> StaticBody3D
var _spawn := Vector3.ZERO


func _ready() -> void:
	if not _built:
		build()
	var args := OS.get_cmdline_user_args()
	if _built and ("--capture-topdown" in args or "--walk-perf" in args or "--capture-views" in args):
		var capture := ReplicaCapture.new()
		capture.name = "Capture"
		add_child(capture)
		capture.run.call_deferred(self, args)


## Loads build/ and builds everything (again). Errors name the missing file and the command.
func build() -> void:
	var t0 := Time.get_ticks_msec()
	_clear()
	var data := _load()
	if data.is_empty():
		return
	_stage("load", t0)
	var t := Time.get_ticks_msec()
	terrain = ReplicaTerrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	var ring: Dictionary = manifest.ring
	terrain.setup(_core, _n, _step, data.ring, int(ring.n), float(ring.step_m), data.classes, _base)
	_stage("terrain", t)
	t = Time.get_ticks_msec()
	_aim_sun()
	_build_rocks()
	_stage("rocks", t)
	t = Time.get_ticks_msec()
	_build_scatter(data.scatter)
	_stage("scatter", t)
	t = Time.get_ticks_msec()
	_build_gers()
	grass = ReplicaGrass.new()
	grass.name = "Grass"
	grass.target = player
	add_child(grass)
	var gd: Dictionary = manifest.grass_density
	grass.setup(terrain, data.grass, float(gd.origin_x))
	_built = true
	reset_scene()
	_stage("gers+grass", t)
	build_seconds = (Time.get_ticks_msec() - t0) / 1000.0
	print("ReplicaSite %s: built in %.2f s %s" % [manifest.get("name", ""), build_seconds, build_stages])


## Back to the spawn point (15 m south of the first ger), at rest, grass around it.
func reset_scene() -> void:
	if player:
		player.global_position = _spawn
		player.velocity = Vector3.ZERO
	if follow_camera and follow_camera.has_method("snap"):
		follow_camera.snap()
	if grass:
		grass.fill_now()


## Ground y (DEM height - base_elevation) at world (x, z); NAN beyond the ring.
func ground_y(x: float, z: float) -> float:
	return terrain.height_at(x, z) if terrain else NAN


func spawn_point() -> Vector3:
	return _spawn


## Placed rocks (rocks_placed.json entries).
func rock_count() -> int:
	return _rock_nodes.size()


## The node of a placed rock: a boulder's MeshInstance3D, or a mass's (empty) marker node.
func rock_node(id: String) -> Node3D:
	return _rock_nodes.get(id)


## World bounds of a placed rock (a mass: of all its fill pieces).
func rock_aabb(id: String) -> AABB:
	if _mass_boxes.has(id):
		return _mass_boxes[id]
	var node := _rock_nodes.get(id) as MeshInstance3D
	return node.global_transform * node.mesh.get_aabb() if node else AABB()


## Instances drawn of a scatter type (summed over its MultiMeshes).
func scatter_count(type: String) -> int:
	var n := 0
	for node: MultiMeshInstance3D in _scatter_nodes.get(type, []):
		n += node.multimesh.instance_count
	return n


## World transform of scatter.json row `row` (unit shape: base y 0, 1 x 1 x 1).
func scatter_transform(row: int) -> Transform3D:
	var r: Array = _rows[row]
	return _place(r[1], r[2], _row_base[row], r[4], r[5], r[6], r[7])


## World transform scatter row `row` is actually drawn with (its MultiMesh instance, including
## the shape's fit into the unit box); identity if the row is not drawn.
func scatter_drawn_transform(row: int) -> Transform3D:
	var g := _row_group[row]
	if g < 0:
		return Transform3D()
	var node := _group_nodes[g]
	return node.global_transform * node.multimesh.get_instance_transform(_row_slot[row])


func ger_nodes() -> Array[Node3D]:
	return _gers


## rocks_placed.json entries.
func placed_rocks() -> Array:
	return _rocks


## Scatter types drawn, and the MultiMeshInstance3D nodes of one.
func scatter_types() -> Array:
	return _scatter_nodes.keys()


func scatter_nodes(type: String) -> Array:
	return _scatter_nodes.get(type, [])


## Whether scatter row `row` has a collision shape, and its transform (identity if none).
func scatter_has_collision(row: int) -> bool:
	return _row_owner[row] >= 0


func scatter_collision_transform(row: int) -> Transform3D:
	if _row_owner[row] < 0:
		return Transform3D()
	var r: Array = _rows[row]
	return _body(_cell(r[1], r[2])).shape_owner_get_transform(_row_owner[row])


## Collision shapes on the rock bodies (boulders and fill pieces; gers not counted).
func rock_shape_count() -> int:
	var n := 0
	for body: StaticBody3D in _bodies.values():
		n += body.get_shape_owners().size()
	return n


## Absolute filesystem path of the site's build/ folder.
func build_dir() -> String:
	return _build_dir()


# --- loading -------------------------------------------------------------------------------------

func _stage(stage: String, since: int) -> void:
	build_stages[stage] = snappedf((Time.get_ticks_msec() - since) / 1000.0, 0.01)


func _clear() -> void:
	for node in [terrain, grass]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	for child in get_children():
		if child.has_meta("replica_built"):
			remove_child(child)
			child.queue_free()
	terrain = null
	grass = null
	_built = false
	_rock_nodes.clear()
	_mass_boxes.clear()
	_scatter_nodes.clear()
	_group_nodes.clear()
	_row_group = PackedInt32Array()
	_row_slot = PackedInt32Array()
	_row_owner = PackedInt32Array()
	_row_base = PackedFloat32Array()
	_rows = []
	_gers.clear()
	_bodies.clear()
	build_stages.clear()


func _build_dir() -> String:
	return ProjectSettings.globalize_path(site_dir).path_join("build")


func _missing(file: String) -> void:
	push_error("ReplicaSite: missing %s; %s" % [_build_dir().path_join(file), BUILD_HINT % site_dir.trim_prefix("res://")])


func _read_json(file: String) -> Variant:
	var path := _build_dir().path_join(file)
	if not FileAccess.file_exists(path):
		_missing(file)
		return null
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value == null:
		push_error("ReplicaSite: %s is not valid JSON; %s" % [path, BUILD_HINT % site_dir.trim_prefix("res://")])
	return value


func _read_r32(file: String, n: int) -> PackedFloat32Array:
	var path := _build_dir().path_join(file)
	if not FileAccess.file_exists(path):
		_missing(file)
		return PackedFloat32Array()
	var values := FileAccess.get_file_as_bytes(path).to_float32_array()
	if values.size() != n * n:
		push_error("ReplicaSite: %s has %d samples, manifest says %d x %d" % [path, values.size(), n, n])
		return PackedFloat32Array()
	return values


func _read_image(file: String) -> Image:
	var path := _build_dir().path_join(file)
	if not FileAccess.file_exists(path):
		_missing(file)
		return null
	return Image.load_from_file(path)


## Everything from build/, or {} after an error.
func _load() -> Dictionary:
	var m: Variant = _read_json("manifest.json")
	if not m is Dictionary:
		return {}
	manifest = m
	# export_site writes these two only when it is given them; this builder needs both.
	for key in ["grass_density", "rocks_placed"]:
		if not manifest.has(key):
			push_error("ReplicaSite: %s has no \"%s\" entry (an incomplete export); %s" % [
					_build_dir().path_join("manifest.json"), key, BUILD_HINT % site_dir.trim_prefix("res://")])
			return {}
	var core: Dictionary = manifest.core
	_n = int(core.n)
	_step = float(core.step_m)
	_half = (_n - 1) * _step * 0.5
	_base = float(manifest.base_elevation)
	if not is_equal_approx(float(core.origin_x), -_half) or not is_equal_approx(float(core.origin_z), -_half):
		push_error("ReplicaSite: core grid is not centred on the origin (%s)" % core)
		return {}
	_core = _read_r32(core.file, _n)
	var ring_info: Dictionary = manifest.ring
	var ring := _read_r32(ring_info.file, int(ring_info.n))
	var classes := _read_image(manifest.classes.file)
	var grass_image := _read_image(manifest.grass_density.file)
	var placed: Variant = _read_json(manifest.rocks_placed.file)
	var scatter: Variant = _read_json(manifest.scatter.file)
	if _core.is_empty() or ring.is_empty() or classes == null or grass_image == null \
			or not placed is Dictionary or not scatter is Dictionary:
		return {}
	_rocks = placed.rocks
	return {"ring": ring, "classes": classes, "grass": grass_image, "scatter": scatter}


func _aim_sun() -> void:
	if sun == null:
		return
	var az := deg_to_rad(float(manifest.sun.azimuth_deg))
	var el := deg_to_rad(float(manifest.sun.elevation_deg))
	# Toward the sun: azimuth clockwise from north (-Z), elevation above the horizon.
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.global_basis = Basis.looking_at(-to_sun, Vector3.UP)


# --- geometry ------------------------------------------------------------------------------------

## Lowest core sample under an l x w footprint grown by one diagonal step (the pipeline's
## heightmap.rock_base_y for a boulder footprint), as ground y. Off the core: the ground there.
func footprint_base(x: float, z: float, l: float, w: float, yaw_deg: float) -> float:
	var yaw := deg_to_rad(yaw_deg)
	var ax := sin(yaw)
	var az := -cos(yaw)
	var bx := cos(yaw)
	var bz := sin(yaw)
	var m := _step * sqrt(2.0)
	var hl := l * 0.5 + m
	var hw := w * 0.5 + m
	var ex := absf(ax) * hl + absf(bx) * hw
	var ez := absf(az) * hl + absf(bz) * hw
	var c0 := maxi(0, ceili((x - ex + _half) / _step - 1e-9))
	var c1 := mini(_n - 1, floori((x + ex + _half) / _step + 1e-9))
	var r0 := maxi(0, ceili((z - ez + _half) / _step - 1e-9))
	var r1 := mini(_n - 1, floori((z + ez + _half) / _step + 1e-9))
	var lo := INF
	for r in range(r0, r1 + 1):
		var dz := -_half + r * _step - z
		var row := r * _n
		for c in range(c0, c1 + 1):
			var dx := -_half + c * _step - x
			if absf(dx * ax + dz * az) <= hl and absf(dx * bx + dz * bz) <= hw:
				var v := _core[row + c]
				if v < lo:
					lo = v
	if lo == INF:
		var r := clampi(roundi((z + _half) / _step), 0, _n - 1)
		var c := clampi(roundi((x + _half) / _step), 0, _n - 1)
		if absf(x) > _half or absf(z) > _half:
			return ground_y(x, z)
		lo = _core[r * _n + c]
	return lo - _base


## Ground y at (x, z), bilinear between core samples (the pipeline's rock_top_y reads it so).
func ground_bilinear(x: float, z: float) -> float:
	var u := clampf((x + _half) / _step, 0.0, _n - 1.0001)
	var v := clampf((z + _half) / _step, 0.0, _n - 1.0001)
	var j := int(u)
	var i := int(v)
	var k := i * _n + j
	var a := lerpf(_core[k], _core[k + 1], u - j)
	var b := lerpf(_core[k + _n], _core[k + _n + 1], u - j)
	return lerpf(a, b, v - i) - _base


## A unit shape (1 x 1 x 1, base y 0) placed at (x, base, z), scaled (l, h, w), its local +X
## (length) along yaw degrees clockwise from north (-Z), so +Z (width) points yaw + 90.
static func _place(x: float, z: float, base: float, yaw_deg: float, l: float, h: float, w: float) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(90.0 - yaw_deg)) * Basis.from_scale(Vector3(l, h, w))
	return Transform3D(basis, Vector3(x, base, z))


func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + _half) / CELL_M), floori((z + _half) / CELL_M))


func _cell_centre(cell: Vector2i) -> Vector3:
	return Vector3(-_half + (cell.x + 0.5) * CELL_M, 0.0, -_half + (cell.y + 0.5) * CELL_M)


func _variant(names: Array, key: Variant) -> String:
	return names[posmod(hash(key), names.size())]


# --- shapes --------------------------------------------------------------------------------------

## {mesh: palette-material mesh, scatter: the same for MultiMesh (no ground darkening),
##  hull: unit convex shape, fit: transform taking the mesh into the unit box}.
func _shape(shape_name: String) -> Dictionary:
	if _shapes.has(shape_name):
		return _shapes[shape_name]
	var mesh: Mesh
	var fit := Transform3D.IDENTITY
	if shape_name == "scrub":
		mesh = scrub_mesh()
		var m := ShaderMaterial.new()
		m.shader = preload("res://assets/materials/flat_color.gdshader")
		m.set_shader_parameter("albedo", Color.WHITE)
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("tint_variation", 0.12)
		mesh.surface_set_material(0, m)
	else:
		var path := "res://assets/meshes/tree_larch.glb" if shape_name == "tree" else ROCK_DIR + shape_name + ".glb"
		var scene: Node = load(path).instantiate()
		var source := scene.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		mesh = (source.mesh.duplicate() as Mesh)
		for i in mesh.get_surface_count():
			var material := mesh.surface_get_material(i)
			if material:
				var palette := PALETTE_DIR + material.resource_name + ".tres"
				if ResourceLoader.exists(palette):
					mesh.surface_set_material(i, load(palette))
		scene.free()
		if shape_name == "tree":
			# The kit larch is real size: normalise its bounds into the unit box.
			var box := mesh.get_aabb()
			fit = Transform3D(Basis.from_scale(Vector3.ONE / box.size),
					Vector3(-box.get_center().x / box.size.x, -box.position.y / box.size.y, -box.get_center().z / box.size.z))
	var scatter_mesh := mesh.duplicate() as Mesh
	for i in scatter_mesh.get_surface_count():
		var material := scatter_mesh.surface_get_material(i) as ShaderMaterial
		if material:
			# flat_color's contact shade reads world height above y 0; replica ground is far
			# above that, and a MultiMesh has no per-instance origin, so it is off for scatter.
			material = material.duplicate()
			material.set_shader_parameter("base_darkening", 0.0)
			scatter_mesh.surface_set_material(i, material)
	var hull := mesh.create_convex_shape(true, false) as ConvexPolygonShape3D
	if fit != Transform3D.IDENTITY:
		var points := hull.points
		for k in points.size():
			points[k] = fit * points[k]
		hull.points = points
	var entry := {"mesh": mesh, "scatter": scatter_mesh, "hull": hull, "fit": fit}
	_shapes[shape_name] = entry
	return entry


## Low-poly scrub: three 8-sided rings (base, widest at mid height, crown) and a top point,
## 40 triangles, exactly the unit box (x, z in [-0.5, 0.5] at the widest ring, y 0..1), one
## dull olive vertex colour (linear) for flat_color's use_vertex_color.
static func scrub_mesh() -> ArrayMesh:
	const SIDES := 8
	var rings := [Vector3(0.36, 0.0, 0.5), Vector3(0.5, 0.42, 0.0), Vector3(0.32, 0.82, 0.5)]  # radius, y, turn
	var verts := PackedVector3Array()
	for r: Vector3 in rings:
		for k in SIDES:
			var a := TAU * (k + r.z) / SIDES
			verts.append(Vector3(cos(a) * r.x, r.y, sin(a) * r.x))
	verts.append(Vector3(0.0, 1.0, 0.0))
	var idx := PackedInt32Array()
	for ring in 2:
		var lo := ring * SIDES
		var hi := lo + SIDES
		for k in SIDES:
			var k1 := (k + 1) % SIDES
			idx.append_array([lo + k, hi + k, lo + k1, lo + k1, hi + k, hi + k1])
	var top := verts.size() - 1
	for k in SIDES:
		idx.append_array([2 * SIDES + k, top, 2 * SIDES + (k + 1) % SIDES])
	var colors := PackedColorArray()
	colors.resize(verts.size())
	colors.fill(SCRUB_COLOR.srgb_to_linear())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- rocks ---------------------------------------------------------------------------------------

func _body(cell: Vector2i) -> StaticBody3D:
	if not _bodies.has(cell):
		var body := StaticBody3D.new()
		body.name = "RockCollision_%d_%d" % [cell.x, cell.y]
		body.collision_layer = ROCK_LAYER
		body.collision_mask = 0
		body.set_meta("replica_built", true)
		add_child(body)
		_bodies[cell] = body
	return _bodies[cell]


func _add_hull(shape: Dictionary, xf: Transform3D, cell: Vector2i) -> int:
	var body := _body(cell)
	var owner_id := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner_id, shape.hull)
	body.shape_owner_set_transform(owner_id, xf)
	return owner_id


func _build_rocks() -> void:
	var rocks_root := Node3D.new()
	rocks_root.name = "Rocks"
	rocks_root.set_meta("replica_built", true)
	add_child(rocks_root)
	for r: Dictionary in _rocks:
		var id: String = r.id
		var x: float = r.x
		var z: float = r.z
		if r.kind == "mass" and r.outline:
			var marker := Node3D.new()
			marker.name = "Mass_" + id
			rocks_root.add_child(marker)
			marker.position = Vector3(x, footprint_base(x, z, r.length, r.width, r.yaw_deg), z)
			_rock_nodes[id] = marker
			continue
		var base := footprint_base(x, z, r.length, r.width, r.yaw_deg)
		var top := ground_bilinear(x, z) + float(r.height)
		var family := "slab" if float(r.height) < SLAB_RATIO * minf(r.length, r.width) else "round"
		var shape := _shape(_variant(SHAPES[family], id))
		var node := MeshInstance3D.new()
		node.name = "Rock_" + id
		node.mesh = shape.mesh
		rocks_root.add_child(node)
		node.transform = _place(x, z, base, r.yaw_deg, r.length, top - base, r.width)
		node.set_instance_shader_parameter("height_from_origin", true)
		_rock_nodes[id] = node
		_add_hull(shape, node.transform, _cell(x, z))


# --- scatter -------------------------------------------------------------------------------------

func _build_scatter(doc: Dictionary) -> void:
	_types = PackedStringArray(doc.types)
	_rows = doc.rows
	var fields: Array = doc.fields
	if fields != ["type", "x", "z", "y", "yaw_deg", "l", "h", "w"]:
		push_error("ReplicaSite: scatter.json fields %s, expected type x z y yaw_deg l h w" % [fields])
		return
	_row_base.resize(_rows.size())
	var masses := _mass_index()
	# (type, shape, cell) -> group index; per group an Array of 12-float transforms (an Array,
	# not a PackedFloat32Array: a packed array read out of a container is a copy).
	var group_of := {}
	var keys: Array = []
	var buffers: Array[Array] = []
	_row_group.resize(_rows.size())
	_row_slot.resize(_rows.size())
	_row_owner.resize(_rows.size())
	_row_group.fill(-1)
	_row_owner.fill(-1)
	for k in _rows.size():
		var r: Array = _rows[k]
		var type: String = _types[int(r[0])]
		var x: float = r[1]
		var z: float = r[2]
		var base := footprint_base(x, z, r[5], r[7], r[4]) + float(r[3])
		_row_base[k] = base
		var family: String = TYPE_SHAPES.get(type, "")
		var shape_name: String = _variant(SHAPES[family], k) if SHAPES.has(family) else family
		if shape_name == "":
			continue
		var shape := _shape(shape_name)
		var placed := _place(x, z, base, r[4], r[5], r[6], r[7])
		var xf := placed * (shape.fit as Transform3D)
		var cell := _cell(x, z)
		var key := [type, shape_name, cell]
		if not group_of.has(key):
			group_of[key] = keys.size()
			keys.append(key)
			buffers.append([])
		var g: int = group_of[key]
		var buffer: Array = buffers[g]
		_row_group[k] = g
		_row_slot[k] = buffer.size() / 12
		var b: Basis = xf.basis
		var o: Vector3 = xf.origin - _cell_centre(cell)
		buffer.append_array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, o.y, b.x.z, b.y.z, b.z.z, o.z])
		if type in SOLID_TYPES:
			if maxf(float(r[5]), maxf(float(r[6]), float(r[7]))) > COLLIDE_MIN_M:
				_row_owner[k] = _add_hull(shape, xf, cell)
			_grow_mass(masses, x, z, placed * AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE))
	var root := Node3D.new()
	root.name = "Scatter"
	root.set_meta("replica_built", true)
	add_child(root)
	_group_nodes.clear()
	for g in keys.size():
		var key: Array = keys[g]
		var buffer := PackedFloat32Array(buffers[g])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _shape(key[1]).scatter
		mm.instance_count = buffer.size() / 12
		mm.buffer = buffer
		var node := MultiMeshInstance3D.new()
		node.name = "%s_%s_%d_%d" % [key[0], key[1], key[2].x, key[2].y]
		node.multimesh = mm
		node.position = _cell_centre(key[2])
		node.visibility_range_end = DRAW_DISTANCE.get(key[0], 0.0)
		if key[0] in ["stone", "scrub"]:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
		_group_nodes.append(node)
		if not _scatter_nodes.has(key[0]):
			_scatter_nodes[key[0]] = []
		_scatter_nodes[key[0]].append(node)


## Masses with outlines, bucketed by CELL_M cell of their outline's bounds.
func _mass_index() -> Dictionary:
	var index := {}
	for r: Dictionary in _rocks:
		if r.kind != "mass" or not r.outline:
			continue
		var poly := PackedVector2Array()
		for p: Array in r.outline:
			poly.append(Vector2(p[0], p[1]))
		var lo := poly[0]
		var hi := poly[0]
		for p in poly:
			lo = lo.min(p)
			hi = hi.max(p)
		var entry := {"id": r.id, "poly": poly, "rect": Rect2(lo, hi - lo)}
		var c0 := _cell(lo.x, lo.y)
		var c1 := _cell(hi.x, hi.y)
		for cz in range(c0.y, c1.y + 1):
			for cx in range(c0.x, c1.x + 1):
				var cell := Vector2i(cx, cz)
				if not index.has(cell):
					index[cell] = []
				index[cell].append(entry)
	return index


## Adds a fill piece's bounds to the mass whose outline holds its centre.
func _grow_mass(index: Dictionary, x: float, z: float, box: AABB) -> void:
	var p := Vector2(x, z)
	for entry: Dictionary in index.get(_cell(x, z), []):
		if (entry.rect as Rect2).grow(0.01).has_point(p) and Geometry2D.is_point_in_polygon(p, entry.poly):
			var id: String = entry.id
			_mass_boxes[id] = (_mass_boxes[id] as AABB).merge(box) if _mass_boxes.has(id) else box
			return


# --- gers ----------------------------------------------------------------------------------------

func _build_gers() -> void:
	var glb: PackedScene = load(ROCK_DIR + "ger.glb")
	for s: Dictionary in manifest.structures:
		if s.type != "ger":
			continue
		var x: float = s.x
		var z: float = s.z
		var d: float = s.diameter_m
		var root := Node3D.new()
		root.set_script(preload("res://scripts/environment/kit_asset.gd"))
		root.set("height_from_origin", true)
		root.name = "Ger_%d" % _gers.size()
		root.set_meta("replica_built", true)
		var model := glb.instantiate()
		root.add_child(model)
		var mesh := (model.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var size := mesh.get_aabb().size
		# Across: the measured diameter. Up: the model's own height (the 2.4 m crown reference,
		# plan Task 9; the ortho measures no ger height), so a wide ger is not taller.
		var across := d / maxf(size.x, size.z)
		root.scale = Vector3(across, 1.0, across)
		root.position = Vector3(x, footprint_base(x, z, d, d, 0.0), z)
		add_child(root)
		var body := StaticBody3D.new()
		body.collision_layer = ROCK_LAYER
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_convex_shape(true, false)
		body.add_child(cs)
		root.add_child(body)
		_gers.append(root)
	if _gers.is_empty():
		_spawn = Vector3(0.0, ground_y(0.0, 0.0), 0.0)
	else:
		var g := _gers[0].global_position
		_spawn = Vector3(g.x, ground_y(g.x, g.z + SPAWN_SOUTH_M) + 0.02, g.z + SPAWN_SOUTH_M)
