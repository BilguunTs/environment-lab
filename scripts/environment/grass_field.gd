@tool
class_name GrassField
extends Node3D
## Painted grass over a rectangle centred on this node (unrotated, unscaled).
##
## The `mask` image holds R = density (0 = none, 1 = full) and G = height (0 = min_height,
## 1 = max_height), one texel per `texel_size` metres, texel (0, 0) at the field's -X/-Z corner.
## Blades are MultiMesh chunks of CHUNK_SIZE metres, chunk (0, 0) also at the -X/-Z corner.
##
## Each chunk is reproducible on its own: an RNG seeded from (random_seed, chunk), a fixed
## number of candidates, and every candidate draws all of its random numbers up front, so a
## stroke only changes blades where it painted and a rebuild of the same mask gives the same
## blades. Blades sit on a height cache raycast against `ground_layer` once per texel; points
## with no ground hit get no blade.
##
## Chunk nodes are internal (no owner) and not saved with the scene. Runs in the editor too.

signal rebuilt(blade_count: int)

enum PaintMode { DENSITY, HEIGHT, ERASE }

const CHUNK_SIZE := 16.0
const SHADER := preload("res://assets/shaders/grass.gdshader")
const HEIGHT_JITTER := 0.15
const MAX_LEAN_DEG := 10.0

@export var extent := Vector2(74, 104):
	set(v):
		if v != extent:
			extent = v
			_invalidate_ground()
			mark_dirty()
## Metres per mask texel.
@export_range(0.1, 4.0, 0.05) var texel_size := 0.5:
	set(v):
		if not is_equal_approx(v, texel_size):
			texel_size = v
			_invalidate_ground()
			mark_dirty()
## R = density, G = height. Created by ensure_mask() when missing.
@export var mask: Image:
	set(v):
		mask = v
		mark_dirty()
## Blades per square metre at full density.
@export_range(0.0, 200.0, 0.5) var blades_per_m2 := 24.0:
	set(v):
		if not is_equal_approx(v, blades_per_m2):
			blades_per_m2 = v
			mark_dirty()
@export var min_height := 0.25:
	set(v):
		if not is_equal_approx(v, min_height):
			min_height = v
			mark_dirty()
@export var max_height := 0.9:
	set(v):
		if not is_equal_approx(v, max_height):
			max_height = v
			mark_dirty()
@export var random_seed := 1:
	set(v):
		if v != random_seed:
			random_seed = v
			mark_dirty()
## Physics layer (1-based) the ground ray hits. Walkable ground is on layer 2 ("ground").
@export_range(1, 32) var ground_layer := 2:
	set(v):
		if v != ground_layer:
			ground_layer = v
			_invalidate_ground()
			mark_dirty()
## The ground ray starts this far above the field's own height (its node y)...
@export var ray_above := 40.0:
	set(v):
		if not is_equal_approx(v, ray_above):
			ray_above = v
			_invalidate_ground()
			mark_dirty()
## ...and ends this far below it. Widen both for a field over steep or high ground (a mountain
## trail); the first ground-layer hit from the top wins.
@export var ray_below := 5.0:
	set(v):
		if not is_equal_approx(v, ray_below):
			ray_below = v
			_invalidate_ground()
			mark_dirty()

@export_group("Look")
@export var base_color := Color(0.12, 0.14, 0.10):
	set(v):
		base_color = v
		_update_material()
@export var tip_color := Color(0.30, 0.31, 0.19):
	set(v):
		tip_color = v
		_update_material()
## Blades start thinning out at this camera distance...
@export var fade_start := 25.0:
	set(v):
		fade_start = v
		_update_material()
## ...and are gone by this one. Chunks are culled a chunk beyond it.
@export var fade_end := 45.0:
	set(v):
		fade_end = v
		_update_material()
		for node: MultiMeshInstance3D in _chunks.values():
			node.visibility_range_end = fade_end + CHUNK_SIZE

static var _mesh: ArrayMesh  # one blade mesh shared by every field

var _dirty := true
var _chunks := {}  # Vector2i -> MultiMeshInstance3D (only non-empty chunks)
var _material: ShaderMaterial
var _ground := PackedFloat32Array()  # one height per texel centre, NAN where the ray missed
var _ground_valid := false
var _ground_origin := Vector3.ZERO
var _ground_size := Vector2i.ZERO


func _ready() -> void:
	mark_dirty()


func mark_dirty() -> void:
	_dirty = true


# The first build waits for the physics step: the space state is ready to raycast there.
func _physics_process(_delta: float) -> void:
	if _dirty and is_inside_tree():
		rebuild()


# --- mask --------------------------------------------------------------------------------

func mask_size() -> Vector2i:
	return Vector2i(ceili(extent.x / texel_size), ceili(extent.y / texel_size))


## Creates an empty mask (no grass, mid height) if there is none, or resizes a mask of the
## wrong size (bilinear).
func ensure_mask() -> void:
	var size := mask_size()
	if mask == null:
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RG8)
		image.fill(Color(0.0, 0.5, 0.0))
		mask = image
		return
	if mask.get_format() != Image.FORMAT_RG8:
		mask.convert(Image.FORMAT_RG8)
	if mask.get_size() != size:
		mask.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		mark_dirty()


## Bilinear (density, height) at a world position; (0, 0) outside the field.
func sample(world_xz: Vector2) -> Vector2:
	if mask == null:
		return Vector2.ZERO
	return _sample(mask.get_data(), mask.get_width(), mask.get_height(), world_xz)


## Paints a disc. Each texel centre within `radius` moves toward `target` by
## w = strength * (1 - smoothstep(radius * (1 - falloff), radius, d)). DENSITY paints R,
## HEIGHT paints G, ERASE moves R to 0 (target is ignored). Returns the rect of texels that
## changed, clipped to the mask; empty if nothing changed. Call rebuild(rect) afterwards.
func paint(world_pos: Vector3, radius: float, mode: PaintMode, target: float, strength: float,
		falloff := 0.5) -> Rect2i:
	ensure_mask()
	var size := mask_size()
	var corner := _corner()
	var centre := Vector2(world_pos.x, world_pos.z) - corner  # field-local metres
	var lo := Vector2i(((centre - Vector2.ONE * radius) / texel_size).floor())
	var hi := Vector2i(((centre + Vector2.ONE * radius) / texel_size).ceil())
	lo = lo.clamp(Vector2i.ZERO, size)
	hi = hi.clamp(Vector2i.ZERO, size)
	if lo.x >= hi.x or lo.y >= hi.y:
		return Rect2i()
	var channel := 1 if mode == PaintMode.HEIGHT else 0
	var goal := 0.0 if mode == PaintMode.ERASE else clampf(target, 0.0, 1.0)
	var inner := radius * (1.0 - clampf(falloff, 0.0, 1.0))
	var data := mask.get_data()
	var changed_lo := size
	var changed_hi := Vector2i(-1, -1)
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			var d := centre.distance_to((Vector2(x, y) + Vector2(0.5, 0.5)) * texel_size)
			if d > radius:
				continue
			var w := strength * (1.0 - smoothstep(inner, radius, d)) if inner < radius else strength
			if w <= 0.0:
				continue
			var i := (y * size.x + x) * 2 + channel
			var value := lerpf(data[i] / 255.0, goal, clampf(w, 0.0, 1.0))
			var byte := clampi(roundi(value * 255.0), 0, 255)
			if byte == data[i]:
				continue
			data[i] = byte
			changed_lo = changed_lo.min(Vector2i(x, y))
			changed_hi = changed_hi.max(Vector2i(x, y))
	if changed_hi.x < 0:
		return Rect2i()
	mask.set_data(size.x, size.y, false, Image.FORMAT_RG8, data)
	return Rect2i(changed_lo, changed_hi - changed_lo + Vector2i.ONE)


## Replaces the mask contents (undo) and rebuilds every chunk.
func set_mask_data(image: Image) -> void:
	if mask == null:
		mask = image.duplicate()
	else:
		mask.copy_from(image)
	ensure_mask()
	rebuild()


# --- blades ------------------------------------------------------------------------------

## Rebuilds the blades. An empty rect rebuilds every chunk; otherwise only the chunks touching
## the texel rect grown by one texel (bilinear sampling reaches one texel out).
func rebuild(texel_rect := Rect2i()) -> void:
	if not is_inside_tree():
		mark_dirty()
		return
	if mask != null:
		ensure_mask()
	if not _ground_is_valid():
		_cache_ground()
	var counts := _chunk_count()
	var targets: Array[Vector2i] = []
	if texel_rect.has_area():
		var grown := texel_rect.grow(1)
		var c0 := _texel_to_chunk(grown.position)
		var c1 := _texel_to_chunk(grown.end - Vector2i.ONE)
		for cy in range(maxi(c0.y, 0), mini(c1.y, counts.y - 1) + 1):
			for cx in range(maxi(c0.x, 0), mini(c1.x, counts.x - 1) + 1):
				targets.append(Vector2i(cx, cy))
	else:
		_dirty = false
		for node: Node in _chunks.values():
			remove_child(node)
			node.free()
		_chunks.clear()
		for cy in counts.y:
			for cx in counts.x:
				targets.append(Vector2i(cx, cy))
	var data := mask.get_data() if mask != null else PackedByteArray()
	for chunk in targets:
		_build_chunk(chunk, data)
	rebuilt.emit(blade_count())


## Re-raycasts the ground height cache (after the ground moved), then rebuilds.
func refresh_ground() -> void:
	_invalidate_ground()
	rebuild()


## Ground height at a world position, bilinear between texel centres; NAN outside the field or
## if any of the surrounding samples found no ground.
func ground_height_at(world_xz: Vector2) -> float:
	if not _ground_is_valid():
		if not is_inside_tree():
			return NAN
		_cache_ground()
	var local := world_xz - _corner()
	if local.x < 0.0 or local.y < 0.0 or local.x > extent.x or local.y > extent.y:
		return NAN
	var size := _ground_size
	var u := local / texel_size - Vector2(0.5, 0.5)
	var x0 := clampi(floori(u.x), 0, size.x - 1)
	var y0 := clampi(floori(u.y), 0, size.y - 1)
	var x1 := mini(x0 + 1, size.x - 1)
	var y1 := mini(y0 + 1, size.y - 1)
	var fx := clampf(u.x - x0, 0.0, 1.0)
	var fy := clampf(u.y - y0, 0.0, 1.0)
	var a := _ground[y0 * size.x + x0]
	var b := _ground[y0 * size.x + x1]
	var c := _ground[y1 * size.x + x0]
	var d := _ground[y1 * size.x + x1]
	if is_nan(a) or is_nan(b) or is_nan(c) or is_nan(d):
		return NAN
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


func blade_count() -> int:
	var n := 0
	for node: MultiMeshInstance3D in _chunks.values():
		n += node.multimesh.instance_count
	return n


## The node drawing a chunk, or null if the chunk has no blades.
func chunk_instance(chunk: Vector2i) -> MultiMeshInstance3D:
	return _chunks.get(chunk)


## A tapered blade: 3 segments (7 vertices), 1 unit tall, facing +Z. UV.y = 0 at the base,
## 1 at the tip.
static func blade_mesh() -> ArrayMesh:
	const HALF_WIDTH := [0.04, 0.032, 0.02]
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	for s in 3:
		var y := s / 3.0
		for side: float in [-1.0, 1.0]:
			verts.append(Vector3(side * HALF_WIDTH[s], y, 0.0))
			uvs.append(Vector2(0.5 + side * 0.5, y))
			normals.append(Vector3.BACK)
	verts.append(Vector3(0.0, 1.0, 0.0))
	uvs.append(Vector2(0.5, 1.0))
	normals.append(Vector3.BACK)
	var indices := PackedInt32Array([0, 1, 2, 1, 3, 2, 2, 3, 4, 3, 5, 4, 4, 5, 6])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- internals ---------------------------------------------------------------------------

func _corner() -> Vector2:
	return Vector2(global_position.x, global_position.z) - extent * 0.5


func _chunk_count() -> Vector2i:
	return Vector2i(ceili(extent.x / CHUNK_SIZE), ceili(extent.y / CHUNK_SIZE))


func _texel_to_chunk(texel: Vector2i) -> Vector2i:
	return Vector2i(floori((texel.x + 0.5) * texel_size / CHUNK_SIZE),
			floori((texel.y + 0.5) * texel_size / CHUNK_SIZE))


func _sample(data: PackedByteArray, w: int, h: int, world_xz: Vector2) -> Vector2:
	var local := world_xz - _corner()
	if w == 0 or h == 0 or local.x < 0.0 or local.y < 0.0 or local.x > extent.x or local.y > extent.y:
		return Vector2.ZERO
	var u := local / texel_size - Vector2(0.5, 0.5)
	var x0 := clampi(floori(u.x), 0, w - 1)
	var y0 := clampi(floori(u.y), 0, h - 1)
	var x1 := mini(x0 + 1, w - 1)
	var y1 := mini(y0 + 1, h - 1)
	var fx := clampf(u.x - x0, 0.0, 1.0)
	var fy := clampf(u.y - y0, 0.0, 1.0)
	var i00 := (y0 * w + x0) * 2
	var i10 := (y0 * w + x1) * 2
	var i01 := (y1 * w + x0) * 2
	var i11 := (y1 * w + x1) * 2
	var r := lerpf(lerpf(data[i00], data[i10], fx), lerpf(data[i01], data[i11], fx), fy)
	var g := lerpf(lerpf(data[i00 + 1], data[i10 + 1], fx), lerpf(data[i01 + 1], data[i11 + 1], fx), fy)
	return Vector2(r, g) / 255.0


## True if no texel a bilinear sample inside the chunk can reach has any density.
func _chunk_is_empty(chunk: Vector2i, data: PackedByteArray) -> bool:
	if data.is_empty():
		return true
	var size := mask_size()
	var per := CHUNK_SIZE / texel_size
	var lo := Vector2i(floori(chunk.x * per) - 1, floori(chunk.y * per) - 1).clamp(Vector2i.ZERO, size)
	var hi := Vector2i(ceili((chunk.x + 1) * per) + 1, ceili((chunk.y + 1) * per) + 1).clamp(Vector2i.ZERO, size)
	for y in range(lo.y, hi.y):
		for x in range(lo.x, hi.x):
			if data[(y * size.x + x) * 2] > 0:
				return false
	return true


func _build_chunk(chunk: Vector2i, data: PackedByteArray) -> void:
	if _chunks.has(chunk):
		var old: Node = _chunks[chunk]
		_chunks.erase(chunk)
		remove_child(old)
		old.free()
	if _chunk_is_empty(chunk, data):
		return
	var size := mask_size()
	var corner := _corner() + Vector2(chunk) * CHUNK_SIZE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([random_seed, chunk.x, chunk.y])
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var origin := global_position
	for i in int(blades_per_m2 * CHUNK_SIZE * CHUNK_SIZE):
		var p := corner + Vector2(rng.randf(), rng.randf()) * CHUNK_SIZE
		var keep := rng.randf()
		var jitter := 1.0 + rng.randf_range(-HEIGHT_JITTER, HEIGHT_JITTER)
		var yaw := rng.randf() * TAU
		var lean := deg_to_rad(rng.randf_range(-MAX_LEAN_DEG, MAX_LEAN_DEG))
		var custom := Color(rng.randf(), rng.randf(), rng.randf(), 0.0)  # tint, phase, fade

		var s := _sample(data, size.x, size.y, p)
		if keep >= s.x:
			continue
		var y := ground_height_at(p)
		if is_nan(y):
			continue
		var height := lerpf(min_height, max_height, s.y) * jitter
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean) * Basis.from_scale(Vector3(1.0, height, 1.0))
		transforms.append(Transform3D(basis, Vector3(p.x, y, p.y) - origin))
		customs.append(custom)
	if transforms.is_empty():
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _shared_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_custom_data(i, customs[i])
	var node := MultiMeshInstance3D.new()
	node.name = "Chunk_%d_%d" % [chunk.x, chunk.y]
	node.multimesh = mm
	node.material_override = _get_material()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = fade_end + CHUNK_SIZE
	add_child(node)  # internal: no owner, never saved
	_chunks[chunk] = node


static func _shared_mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = blade_mesh()
	return _mesh


func _get_material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_update_material()
	return _material


func _update_material() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("base_color", base_color)
	_material.set_shader_parameter("tip_color", tip_color)
	_material.set_shader_parameter("fade_start", fade_start)
	_material.set_shader_parameter("fade_end", fade_end)


# --- ground cache ------------------------------------------------------------------------

func _invalidate_ground() -> void:
	_ground_valid = false


func _ground_is_valid() -> bool:
	return _ground_valid and _ground_size == mask_size() and _ground_origin.is_equal_approx(global_position)


## One downward ray per texel centre against `ground_layer`, from ray_above over the field's
## height down to ray_below under it.
func _cache_ground() -> void:
	var size := mask_size()
	_ground.resize(size.x * size.y)
	_ground.fill(NAN)
	_ground_size = size
	_ground_origin = global_position
	_ground_valid = true
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		_ground_valid = false
		return
	var corner := _corner()
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1 << (ground_layer - 1)
	for y in size.y:
		for x in size.x:
			var p := corner + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel_size
			query.from = Vector3(p.x, _ground_origin.y + ray_above, p.y)
			query.to = Vector3(p.x, _ground_origin.y - ray_below, p.y)
			var hit := space.intersect_ray(query)
			if hit:
				_ground[y * size.x + x] = hit.position.y
