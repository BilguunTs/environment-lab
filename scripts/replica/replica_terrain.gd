class_name ReplicaTerrain
extends Node3D
## Ground of a terrain replica: the 1 m core heightmap and the 30 m DEM ring around it.
##
## Chosen implementation (Task 10, step 1): the chunked-mesh fallback, not Terrain3D. Terrain3D
## v1.1.0 does support Godot 4.5-4.8, but it is a 45.7 MB native GDExtension (binaries for every
## platform committed to the repo) whose texture-splat material would have to be replaced to get
## this project's flat-colour look; the replica needs neither its painting tools nor its streaming.
##
## Drawing: one flat grid mesh per tile size, shared by every tile; replica_terrain.gdshader
## lifts each vertex to its sample's height (texelFetch, so the drawn surface passes through every
## sample exactly) and colours the ground per surface class from PALETTE. Core tiles are TILE_M
## metres with two LODs (1 m and LOD1_STEP m vertex spacing, switched by visibility range); each
## tile has a skirt so LOD steps never show a gap. The ring is one LOD at its own step.
##
## The seam: the core edge (x or z = +-core half) is generally not on a ring grid line, so the core
## grid is extended by an apron out to the first ring line around it (+-outer; 1020 m for a 2 km
## core in a 30 m ring starting at -9990). An apron sample blends linearly, over the apron width,
## from the core edge sample nearest it (the clamp of its position to the core square) to the ring
## surface on the outer line along the same direction. So the ground is continuous at the core
## edge and meets the ring exactly on its grid line (the ring is linear along that line, and so is
## the apron there). The ring shader discards everything inside +-outer and the ring's collision is
## four HeightMapShape3D bands outside +-outer, so inside it the core grid is the only drawn and
## walkable surface; ring vertices inside are also sunk under the core. The apron is derived ground
## (no DEM sample of its own), at most one ring step wide.
##
## Walking: one HeightMapShape3D for the core + apron (layers 1 + 2, the project's ground rule) and
## four for the ring bands (heights / step on a uniformly scaled shape, keeping the 30 m spacing).
## height_at() interpolates on the same triangles as the mesh and the HeightMapShape3D (each cell
## split along its (x+1, z) - (x, z+1) diagonal).
##
## Grids are square and centred on the origin: sample (i, j) at x = -(n - 1) * step / 2 + j * step,
## z likewise with i; row 0 north (-Z). Heights are absolute; y = height - base.

const SHADER := preload("res://assets/shaders/replica_terrain.gdshader")
## Surface class ids (manifest `classes.ids`).
enum Class { UNKNOWN, ROCK, SAND, GRASS, SCRUB, CHANNEL, TRACK, STRUCTURE }
## Ground colour per class (sRGB), the project's dry, desaturated flat palette: granite grus and
## sand pale tan, steppe grass dry olive, scrub a darker olive, channels darker damp gravel, tracks
## the lighter compacted path colour, ger yards trampled tan. UNKNOWN reads as sand.
const PALETTE: Array[Color] = [
	Color(0.50, 0.45, 0.35),  # UNKNOWN
	Color(0.42, 0.41, 0.38),  # ROCK (bare granite pavement; boulders carry their own colour)
	Color(0.50, 0.45, 0.35),  # SAND
	Color(0.43, 0.41, 0.27),  # GRASS
	Color(0.33, 0.33, 0.22),  # SCRUB
	Color(0.40, 0.36, 0.29),  # CHANNEL
	Color(0.55, 0.50, 0.41),  # TRACK
	Color(0.47, 0.43, 0.34),  # STRUCTURE
]
## The ring has no class map (DEM only): one colour between steppe grass and sand.
const RING_COLOR := Color(0.46, 0.43, 0.31)
const TILE_M := 64.0
const LOD1_STEP := 4
## Camera distance (m) at which a core tile switches from 1 m to LOD1_STEP m vertices.
const LOD_SWITCH_M := 320.0
const SKIRT_M := 6.0
## Ring tiles are this many ring cells on a side.
const RING_TILE_CELLS := 64
## Ring vertices inside the core sit this far under the lowest core ground around them.
const RING_SINK_M := 1.0
## Core heights are reduced to min/max per block of this many cells (tile bounds, ring sinking).
const BLOCK := 8
const GROUND_LAYERS := 3

var _core := PackedFloat32Array()  # core + apron: _n x _n samples over +-_half (the outer line)
var _n := 0
var _step := 1.0
var _half := 0.0
var _core_half := 0.0  # the core square proper (no apron)
var _ring := PackedFloat32Array()     # true ring heights (height_at)
var _ring_drawn := PackedFloat32Array()  # sunk inside the core (mesh and collision)
var _ring_n := 0
var _ring_step := 30.0
var _ring_half := 0.0
var _base := 0.0
var _block_min := PackedFloat32Array()
var _block_max := PackedFloat32Array()
var _blocks := 0
var _tiles: Array[MeshInstance3D] = []


## Builds the drawn and walkable ground. `core` / `ring`: absolute heights, n x n / ring_n x ring_n,
## row-major, row 0 north; `classes`: the class map (value = class id) covering the core square.
func setup(core: PackedFloat32Array, n: int, step: float, ring: PackedFloat32Array, ring_n: int,
		ring_step: float, classes: Image, base: float) -> void:
	_clear()
	_step = step
	_core_half = (n - 1) * step * 0.5
	_ring = ring
	_ring_n = ring_n
	_ring_step = ring_step
	_ring_half = (ring_n - 1) * ring_step * 0.5
	_base = base
	_extend_core(core, n)
	_reduce_blocks()
	_build_core(classes)
	_ring_drawn = _sunk_ring()
	_build_ring()
	_build_collision()


## Ground y (height - base) at world (x, z): the core (and its apron) inside +-outer_half(), the
## ring outside, NAN beyond the ring. Same triangles as the drawn and walkable surface.
func height_at(x: float, z: float) -> float:
	if absf(x) <= _half and absf(z) <= _half and _n > 0:
		return _tri(_core, _n, _step, _half, x, z) - _base
	if absf(x) <= _ring_half and absf(z) <= _ring_half and _ring_n > 0:
		return _tri(_ring, _ring_n, _ring_step, _ring_half, x, z) - _base
	return NAN


## The ring's drawn surface at (x, z) (sunk inside the core), y as height_at.
func ring_surface_at(x: float, z: float) -> float:
	if _ring_n == 0 or absf(x) > _ring_half or absf(z) > _ring_half:
		return NAN
	return _tri(_ring_drawn, _ring_n, _ring_step, _ring_half, x, z) - _base


## Half size of the core grid with its apron: the first ring grid line around the core.
func outer_half() -> float:
	return _half


## Every drawn tile (core LOD0, core LOD1 and ring).
func tiles() -> Array[MeshInstance3D]:
	return _tiles


## Builds _core: the core samples plus the apron out to the first ring line at or beyond the core
## edge (see the class doc).
func _extend_core(core: PackedFloat32Array, n: int) -> void:
	var lines := floorf((_ring_half - _core_half) / _ring_step + 1e-6)
	var outer := _ring_half - lines * _ring_step
	var pad := roundi((outer - _core_half) / _step)
	if not is_equal_approx(_core_half + pad * _step, outer):
		push_error("ReplicaTerrain: apron %.2f m is not a whole number of %.2f m core steps" % [outer - _core_half, _step])
	_half = _core_half + pad * _step
	_n = n + 2 * pad
	if pad == 0:
		_core = core
		return
	var width := float(pad) * _step
	var out := PackedFloat32Array()
	for i in _n:
		var z := -_half + i * _step
		var ci := clampi(i - pad, 0, n - 1)
		if i >= pad and i < pad + n:
			for j in pad:
				out.append(_apron(core, n, pad, width, j, ci, z))
			out.append_array(core.slice(ci * n, ci * n + n))  # the core row as it is
			for j in range(pad + n, _n):
				out.append(_apron(core, n, pad, width, j, ci, z))
		else:
			for j in _n:
				out.append(_apron(core, n, pad, width, j, ci, z))
	_core = out


## Apron sample at extended column j (row: core row ci clamped, world z): from the nearest core
## edge sample to the ring on the outer line, linear over the apron width.
func _apron(core: PackedFloat32Array, n: int, pad: int, width: float, j: int, ci: int, z: float) -> float:
	var x := -_half + j * _step
	var cj := clampi(j - pad, 0, n - 1)
	var q := Vector2(-_core_half + cj * _step, -_core_half + ci * _step)
	var d := Vector2(x, z) - q
	var m := maxf(absf(d.x), absf(d.y))
	var o := q + d * (width / m)
	var ring := _tri(_ring, _ring_n, _ring_step, _ring_half, o.x, o.y)
	return lerpf(core[ci * n + cj], ring, m / width)


static func _tri(h: PackedFloat32Array, n: int, step: float, half: float, x: float, z: float) -> float:
	var u := clampf((x + half) / step, 0.0, n - 1.0001)
	var v := clampf((z + half) / step, 0.0, n - 1.0001)
	var j := int(u)
	var i := int(v)
	var tx := u - j
	var tz := v - i
	var k := i * n + j
	var h00 := h[k]
	var h10 := h[k + 1]
	var h01 := h[k + n]
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	var h11 := h[k + n + 1]
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_tiles.clear()


## Min / max of the core per BLOCK x BLOCK cells (each block includes its edge samples).
func _reduce_blocks() -> void:
	_blocks = ceili(float(_n - 1) / BLOCK)
	_block_min.resize(_blocks * _blocks)
	_block_max.resize(_blocks * _blocks)
	_block_min.fill(INF)
	_block_max.fill(-INF)
	var core := _core
	for i in _n:
		var rows: Array[int] = [mini(i / BLOCK, _blocks - 1)]
		if i % BLOCK == 0 and i > 0 and i / BLOCK < _blocks:
			rows.append(i / BLOCK - 1)
		var row := i * _n
		for b in _blocks:
			var j0 := b * BLOCK
			var j1 := mini(j0 + BLOCK, _n - 1)
			var lo := INF
			var hi := -INF
			for j in range(j0, j1 + 1):
				var v := core[row + j]
				if v < lo:
					lo = v
				if v > hi:
					hi = v
			for r in rows:
				var k := r * _blocks + b
				if lo < _block_min[k]:
					_block_min[k] = lo
				if hi > _block_max[k]:
					_block_max[k] = hi


## Core min / max over the blocks covering world rect [x0, x1] x [z0, z1].
func _core_range(x0: float, x1: float, z0: float, z1: float) -> Vector2:
	var b0 := clampi(floori((x0 + _half) / _step / BLOCK), 0, _blocks - 1)
	var b1 := clampi(ceili((x1 + _half) / _step / BLOCK) - 1, 0, _blocks - 1)
	var r0 := clampi(floori((z0 + _half) / _step / BLOCK), 0, _blocks - 1)
	var r1 := clampi(ceili((z1 + _half) / _step / BLOCK) - 1, 0, _blocks - 1)
	var lo := INF
	var hi := -INF
	for r in range(r0, r1 + 1):
		for b in range(b0, b1 + 1):
			lo = minf(lo, _block_min[r * _blocks + b])
			hi = maxf(hi, _block_max[r * _blocks + b])
	return Vector2(lo, hi)


func _height_texture(h: PackedFloat32Array, n: int) -> ImageTexture:
	var image := Image.create_from_data(n, n, false, Image.FORMAT_RF, h.to_byte_array())
	return ImageTexture.create_from_image(image)


func _material(heights: ImageTexture, n: int, step: float, half: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("heights", heights)
	m.set_shader_parameter("origin", Vector2(-half, -half))
	m.set_shader_parameter("step_m", step)
	m.set_shader_parameter("grid_n", n)
	m.set_shader_parameter("base", _base)
	m.set_shader_parameter("skirt_depth", SKIRT_M)
	return m


func _build_core(classes: Image) -> void:
	var m := _material(_height_texture(_core, _n), _n, _step, _half)
	var image := classes.duplicate() as Image
	if image.get_format() != Image.FORMAT_R8:
		image.convert(Image.FORMAT_R8)
	m.set_shader_parameter("use_classes", true)
	m.set_shader_parameter("classes", ImageTexture.create_from_image(image))
	m.set_shader_parameter("classes_n", image.get_width())
	m.set_shader_parameter("classes_m_per_px", 2.0 * _core_half / image.get_width())
	m.set_shader_parameter("classes_origin", Vector2(-_core_half, -_core_half))
	m.set_shader_parameter("palette", PackedColorArray(PALETTE))
	var cells := _n - 1
	var per := int(TILE_M / _step)
	var meshes := {}
	for ti in ceili(float(cells) / per):
		for tj in ceili(float(cells) / per):
			var cz := mini(per, cells - ti * per)
			var cx := mini(per, cells - tj * per)
			var pos := Vector3(-_half + tj * per * _step, 0.0, -_half + ti * per * _step)
			var r := _core_range(pos.x, pos.x + cx * _step, pos.z, pos.z + cz * _step)
			var box := AABB(Vector3(0.0, r.x - _base - SKIRT_M, 0.0),
					Vector3(cx * _step, r.y - r.x + SKIRT_M, cz * _step))
			for lod in 2:
				# LOD1 needs a whole number of its cells (a ragged edge tile stays at 1 m).
				var coarse := cx % LOD1_STEP == 0 and cz % LOD1_STEP == 0
				var s := LOD1_STEP if lod == 1 and coarse else 1
				var key := Vector3i(cx, cz, s)
				if not meshes.has(key):
					meshes[key] = grid_mesh(cx / s, cz / s, s * _step)
				var tile := _tile("Core_%d_%d_lod%d" % [ti, tj, lod], meshes[key], m, pos, box)
				if lod == 0:
					tile.visibility_range_end = LOD_SWITCH_M
				else:
					tile.visibility_range_begin = LOD_SWITCH_M


## Ring heights as drawn: every vertex inside the core square goes RING_SINK_M under the lowest
## core ground within one ring step of it, so no ring triangle inside the core reaches the core.
func _sunk_ring() -> PackedFloat32Array:
	var out := _ring.duplicate()
	for i in _ring_n:
		var z := -_ring_half + i * _ring_step
		if absf(z) >= _half:
			continue
		for j in _ring_n:
			var x := -_ring_half + j * _ring_step
			if absf(x) >= _half:
				continue
			var r := _core_range(x - _ring_step, x + _ring_step, z - _ring_step, z + _ring_step)
			out[i * _ring_n + j] = minf(out[i * _ring_n + j], r.x - RING_SINK_M)
	return out


func _build_ring() -> void:
	var m := _material(_height_texture(_ring_drawn, _ring_n), _ring_n, _ring_step, _ring_half)
	m.set_shader_parameter("ring_color", RING_COLOR)
	m.set_shader_parameter("hole", _half)
	var cells := _ring_n - 1
	var lo := INF
	var hi := -INF
	for v in _ring_drawn:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var meshes := {}
	for ti in ceili(float(cells) / RING_TILE_CELLS):
		for tj in ceili(float(cells) / RING_TILE_CELLS):
			var cz := mini(RING_TILE_CELLS, cells - ti * RING_TILE_CELLS)
			var cx := mini(RING_TILE_CELLS, cells - tj * RING_TILE_CELLS)
			var key := Vector2i(cx, cz)
			if not meshes.has(key):
				meshes[key] = grid_mesh(cx, cz, _ring_step)
			var pos := Vector3(-_ring_half + tj * RING_TILE_CELLS * _ring_step, 0.0,
					-_ring_half + ti * RING_TILE_CELLS * _ring_step)
			var box := AABB(Vector3(0.0, lo - _base - SKIRT_M, 0.0),
					Vector3(cx * _ring_step, hi - lo + SKIRT_M, cz * _ring_step))
			var tile := _tile("Ring_%d_%d" % [ti, tj], meshes[key], m, pos, box)
			tile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _tile(tile_name: String, mesh: ArrayMesh, m: ShaderMaterial, pos: Vector3, box: AABB) -> MeshInstance3D:
	var tile := MeshInstance3D.new()
	tile.name = tile_name
	tile.mesh = mesh
	tile.material_override = m
	tile.position = pos
	tile.custom_aabb = box
	add_child(tile)
	_tiles.append(tile)
	return tile


func _build_collision() -> void:
	add_child(_heightmap_body("CoreCollision", _core, _n, _n, _step, Vector2.ZERO))
	# The ring outside +-outer: north and south bands full width, west and east bands between.
	var lo := roundi((_ring_half - _half) / _ring_step)  # ring index of the -outer line
	var hi := _ring_n - 1 - lo                            # and of the +outer line
	var last := _ring_n - 1
	for band: Array in [["North", 0, lo, 0, last], ["South", hi, last, 0, last],
			["West", lo, hi, 0, lo], ["East", lo, hi, hi, last]]:
		var r0: int = band[1]
		var r1: int = band[2]
		var c0: int = band[3]
		var c1: int = band[4]
		if r1 <= r0 or c1 <= c0:
			continue
		var h := PackedFloat32Array()
		for r in range(r0, r1 + 1):
			h.append_array(_ring_drawn.slice(r * _ring_n + c0, r * _ring_n + c1 + 1))
		var centre := Vector2(-_ring_half + (c0 + c1) * 0.5 * _ring_step,
				-_ring_half + (r0 + r1) * 0.5 * _ring_step)
		add_child(_heightmap_body("Ring%sCollision" % band[0], h, c1 - c0 + 1, r1 - r0 + 1, _ring_step, centre))


## A HeightMapShape3D body for a width x depth grid of `step` m cells centred on `centre` (x, z):
## the shape has 1 m cells, so its heights are divided by `step` and the shape is scaled by `step`
## (uniformly, which physics supports), and the body is lowered by base.
func _heightmap_body(body_name: String, h: PackedFloat32Array, width: int, depth: int, step: float,
		centre: Vector2) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = GROUND_LAYERS
	body.position = Vector3(centre.x, -_base, centre.y)
	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = h if is_equal_approx(step, 1.0) else _scaled(h, 1.0 / step)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * step
	body.add_child(cs)
	return body


static func _scaled(h: PackedFloat32Array, f: float) -> PackedFloat32Array:
	var out := h.duplicate()
	for k in out.size():
		out[k] *= f
	return out


## A flat grid of cx x cz cells of `step` metres, vertex (j, i) at (j * step, 0, i * step), with a
## skirt (vertices at y = -1) hanging from all four edges. Cells split along (x+1, z)-(x, z+1).
static func grid_mesh(cx: int, cz: int, step: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in cz + 1:
		for j in cx + 1:
			verts.append(Vector3(j * step, 0.0, i * step))
	var w := cx + 1
	for i in cz:
		for j in cx:
			var a := i * w + j
			idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	# Skirt: the edge loop, each edge vertex duplicated at y = -1.
	var loop: Array[int] = []
	for j in cx:
		loop.append(j)
	for i in cz:
		loop.append(i * w + cx)
	for j in range(cx, 0, -1):
		loop.append(cz * w + j)
	for i in range(cz, 0, -1):
		loop.append(i * w)
	var first := verts.size()
	for k in loop:
		verts.append(Vector3(verts[k].x, -1.0, verts[k].z))
	for e in loop.size():
		var a: int = loop[e]
		var b: int = loop[(e + 1) % loop.size()]
		var da := first + e
		var db := first + (e + 1) % loop.size()
		# Both windings: a skirt is seen from either side of the seam it covers.
		idx.append_array([a, b, da, b, db, da, a, da, b, b, da, db])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
