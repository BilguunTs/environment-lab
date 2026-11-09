@tool
class_name Vista
extends Node3D
## The Heavens call summit vista: the world the fog opens on, Mongolia seen from the top of an old
## mountain. Everything far is generated (one faceted mesh per piece, internal children with no
## owner, so the scene file stays small); the ovoos are authored children under `Ovoos`.
##
## - Ground: one faceted polar heightfield of `steppe_radius` at `steppe_y`, made of
##   - the steppe floor: golden grass, flat under the massif and gently rolling further out;
##   - the massif's flanks (MountainTerrain.envelope_at(), continued past the terrain's square,
##     whose edge it buries), held under the trail's cone (MountainTerrain.CONE_DROP/CONE_SLOPE);
##   - three layers of rolling Khangai hills at `ring_radii`: broad rounded ridges with soft
##     saddles, higher further out (the last almost at summit height), golden-tan near and
##     blue-grey far. They part toward -Z (the way she looks from the summit), so a wide valley
##     leads the eye out to the horizon between them.
##   It dips under the lowest stretch of the trail so the foot is never under it.
## - Altai: a thin, sparse band of snow-capped peaks on the far horizon (ALTAI), in their own haze
##   (assets/shaders/far_peaks.gdshader) so they read small, pale and distant, never dominant.
## - Mist sea: MIST_LAYERS flat slabs of mist (assets/shaders/mist_sea.gdshader) low over the
##   steppe. They lie in the valleys and thin over the rises (each fades as the ground comes up to
##   it), a thin veil looking down and a solid sea toward the horizon, so the land rises out of it
##   and the ground's edge vanishes under it.
## - Cloud deck: one more slab of the same shader high overhead, dark slate, for a stormy sky.
##
## `reveal` (0..1, driven by the summit sequence) opens the view: MoodDirector multiplies its fog
## by fog_scale() and its ground mist by mist_scale(), tints its sky with horizon_tint() and
## zenith_tint(), and the mist sea thins. At 0 the far world
## isn't drawn at all (it can't show through the fog on the climb) and the mood is untouched.
## No collision, and no shadows: the far pieces neither cast nor need them.

## Mood fog left at reveal 1 (a fraction). Opened geometrically, pow(OPEN_FOG, reveal), so the
## seen distance grows steadily rather than all at the end.
const OPEN_FOG := 0.07
## Ground mist (the Mist FogVolume around her) left at reveal 1.
const OPEN_MIST := 0.12
## Sky at full reveal (blended in by OPEN_TINT): the horizon cools to a blue-grey distance haze,
## so the hills fade bluer, and the zenith darkens toward storm.
const OPEN_HORIZON := Color(0.56, 0.6, 0.67)
const OPEN_ZENITH := Color(0.19, 0.22, 0.29)
const OPEN_TINT := 0.6
## The far world fades in over reveal 0..FAR_FADE (see far_fade()) instead of popping in when
## `far` starts drawing: the mood's fog alone doesn't hide the hills and the cloud deck.
const FAR_FADE := 0.3
## Radius of the mist sea, past the ground's edge; the camera must see this far.
const MIST_RADIUS := 4500.0
## Heights of the mist layers above the steppe, their optical depth closed / open, and the height
## (m) above the ground beneath over which each fades in (so they pool in the valleys).
const MIST_LAYERS := [
	{"above": 16.0, "closed": 1.2, "open": 0.3, "soft": 14.0},
	{"above": 42.0, "closed": 0.9, "open": 0.1, "soft": 34.0},
]
## Mist drift, noise-space units per second per unit of wind.
const MIST_DRIFT := 0.004
## The cloud deck: height above the steppe, optical depth, noise scale, colour (stormy slate),
## drift relative to the mist.
const CLOUD := {"above": 1200.0, "thickness": 0.4, "noise_scale": 0.0004, "color": Color(0.27, 0.29, 0.34), "drift": 3.0}
## Rolling noise on the steppe floor, in metres, reached between ROLL_FROM.x and .y from the centre.
const ROLL := 12.0
const ROLL_FROM := Vector2(320.0, 1000.0)
## The steppe stays this far under the trail, flat within FOOT_FLAT metres of it and rising at
## FOOT_SLOPE beyond.
const FOOT_CLEAR := 3.0
const FOOT_FLAT := 15.0
const FOOT_SLOPE := 0.25
## The massif's flanks in the ground sit this far under MountainTerrain's own (no z-fighting
## where both are drawn; the terrain shows wherever it is raised).
const FLANK_SINK := 4.0
## The cone grid the flanks stay under: half-size (m) around this node and cell size.
const CONE_EXTENT := 520.0
const CONE_CELL := 4.0
## Hill layers, one per ring radius: crest height range above the steppe floor, half-width as a
## fraction of the radius (a broad rounded profile), the number of swells round the ring, how far
## the crest line wanders in and out (fraction of the radius), and the valley toward -Z (angle
## where it starts to close, angle where it is closed, fraction of the crest height left in it).
const HILLS := [
	{"low": 30.0, "high": 110.0, "width": 0.5, "lobes": 6.0, "wander": 0.14, "gap": Vector3(0.3, 0.95, 0.25)},
	{"low": 55.0, "high": 160.0, "width": 0.44, "lobes": 7.0, "wander": 0.12, "gap": Vector3(0.22, 0.75, 0.4)},
	{"low": 90.0, "high": 205.0, "width": 0.4, "lobes": 8.0, "wander": 0.1, "gap": Vector3(0.12, 0.5, 0.62)},
]
## Low rounded domes scattered over the hill country (m), so the layers never read as rings.
const DOMES := 38.0
## Gullies carved down the hillsides along winding lines (fraction of the local hill height lost
## at a gully's floor), so the hills have spurs and draws instead of reading as smooth dunes.
const GULLY := 0.24
## Ground colours: pale straw on the dry crests, olive in the hollows, and the blue-grey the
## hills fade toward with distance (on top of the fog's own aerial perspective).
const STRAW := Color(0.86, 0.73, 0.43)
const OLIVE := Color(0.5, 0.49, 0.27)
const FAR_TINT := Color(0.44, 0.48, 0.55)
## Darker, greener grass and larch on the north faces of the hills.
const SHADE := Color(0.3, 0.32, 0.22)
## How dark the storm clouds' broad shadows lie on the land.
const CLOUD_SHADOW := 0.3
## The Altai band: how many places round the horizon may hold a peak, the radius range, the height
## range above the steppe (main summit), half-length along the horizon per metre of height, the snow line (fraction of a peak's
## height), the haze they keep at full reveal, and the heights above the steppe over which their
## lower slopes rise out of full haze (so only the snowy tops stand clear).
const ALTAI := {"slots": 16, "radius": Vector2(3000.0, 3950.0), "height": Vector2(260.0, 440.0),
	"spread": Vector2(1.4, 2.0), "snow": 0.55, "haze": 0.5, "veil": Vector2(60.0, 300.0)}
## The peaks' haze follows the mood's fog as if they stood this far away (so on the climb's thick
## fog they are gone, and they come out last as it opens).
const ALTAI_FOG_DISTANCE := 900.0
const ALTAI_SNOW := Color(0.9, 0.92, 0.95)
const ALTAI_ROCK := Color(0.34, 0.38, 0.46)

## 0 = hidden behind the mood's fog, 1 = fully open.
@export_range(0.0, 1.0) var reveal := 0.0:
	set(value):
		reveal = clampf(value, 0.0, 1.0)
		_apply_reveal()
@export var steppe_y := 3.0:
	set(value):
		steppe_y = value
		_queue_rebuild()
@export var steppe_radius := 4200.0:
	set(value):
		steppe_radius = value
		_queue_rebuild()
## Radii of the three hill layers (their crest lines), metres from this node.
@export var ring_radii := PackedFloat32Array([720.0, 1250.0, 1900.0]):
	set(value):
		ring_radii = value
		_queue_rebuild()
@export var seed := 11:
	set(value):
		seed = value
		_queue_rebuild()
@export var steppe_color := Color(0.8, 0.64, 0.33)
## The trail, so the steppe can dip under its foot and the flanks stay under its cone.
@export var trail: Trail:
	set(value):
		trail = value
		_queue_rebuild()
## Optional: the mountain whose flanks (MountainTerrain.envelope_at) the ground carries on.
@export var terrain: MountainTerrain:
	set(value):
		terrain = value
		_queue_rebuild()
## Optional: the mist sea takes its horizon colour from this environment's fog.
@export var world_environment: WorldEnvironment
## Optional: the mist sea drifts with this wind.
@export var wind: Wind

## Parent of everything generated far away; hidden while reveal is 0.
var far: Node3D

var _roll: FastNoiseLite
var _patch: FastNoiseLite
var _domes: FastNoiseLite
var _gully: FastNoiseLite
var _hill_noise: Array[FastNoiseLite] = []
var _foot := PackedVector3Array()  # trail points low enough to need the dip
var _cone := PackedFloat32Array()  # the trail's cone, CONE_CELL grid over +-CONE_EXTENT
var _cone_n := 0
var _mist: Array[ShaderMaterial] = []
var _mist_offset := Vector2.ZERO
var _cloud: ShaderMaterial
var _altai: ShaderMaterial
var _solids: Array[StandardMaterial3D] = []  # the ground's materials (far_fade)
var _rebuild_queued := false
var _noise_ready := false


func _ready() -> void:
	rebuild()


func _process(delta: float) -> void:
	if far == null or not far.visible:
		return
	if wind:
		_mist_offset -= wind.vector() * wind.strength * MIST_DRIFT * delta
	var horizon := Color(0.5, 0.5, 0.52)
	var fog_density := 0.0
	if world_environment and world_environment.environment:
		horizon = world_environment.environment.fog_light_color
		fog_density = world_environment.environment.fog_density
	for m in _mist:
		m.set_shader_parameter("offset", _mist_offset)
		m.set_shader_parameter("horizon_color", horizon)
		m.set_shader_parameter("color", horizon.lerp(Color(0.88, 0.9, 0.93), 0.6))
	if _cloud:
		_cloud.set_shader_parameter("offset", _mist_offset * CLOUD.drift)
		_cloud.set_shader_parameter("horizon_color", horizon)
		_cloud.set_shader_parameter("color", CLOUD.color)
	if _altai:
		_altai.set_shader_parameter("haze_color", horizon)
		_altai.set_shader_parameter("haze", altai_haze(fog_density))


## How much of the mood's fog is left (1 = all of it at reveal 0).
func fog_scale() -> float:
	return pow(OPEN_FOG, reveal)


## How far the far world has faded in: 0 at reveal 0, 1 from reveal FAR_FADE on (smoothstep).
func far_fade() -> float:
	return smoothstep(0.0, FAR_FADE, reveal)


## How much of the mood's ground mist is left.
func mist_scale() -> float:
	return lerpf(1.0, OPEN_MIST, reveal)


## The Altai's veil (0..1, 1 = gone) under fog of `fog_density`: never under ALTAI.haze, and
## all veil until the far world has faded in.
func altai_haze(fog_density: float) -> float:
	var h := maxf(ALTAI.haze, 1.0 - exp(-fog_density * ALTAI_FOG_DISTANCE))
	return maxf(h, 1.0 - far_fade())


## The mood's horizon (fog, background) colour as the reveal leaves it.
func horizon_tint(c: Color) -> Color:
	return c.lerp(OPEN_HORIZON, OPEN_TINT * reveal)


## The mood's zenith colour as the reveal leaves it.
func zenith_tint(c: Color) -> Color:
	return c.lerp(OPEN_ZENITH, OPEN_TINT * reveal)


## How far the camera must see to reach the edge of the mist sea.
func horizon_distance() -> float:
	return MIST_RADIUS


## The ground's height at world `xz` (the mesh is this, sampled on its rings): the steppe floor
## and the hills, dipped under the trail's foot, or the massif's flanks where they are higher.
func steppe_height_at(xz: Vector2) -> float:
	_ensure_noise()
	var local := xz - Vector2(global_position.x, global_position.z)
	var r := local.length()
	var y := steppe_y + global_position.y
	y += ROLL * _roll.get_noise_2d(local.x, local.y) * smoothstep(ROLL_FROM.x, ROLL_FROM.y, r)
	y += _hills(local, r)
	for p in _foot:
		var d := Vector2(p.x, p.z).distance_to(xz)
		y = minf(y, p.y - FOOT_CLEAR + FOOT_SLOPE * maxf(d - FOOT_FLAT, 0.0))
	if terrain:
		var flank := minf(terrain.envelope_at(xz), _cone_at(local)) - FLANK_SINK
		y = maxf(y, flank)
	return y


## Regenerates the ground, the Altai, the mist sea and the cloud deck.
func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if is_instance_valid(far):
		remove_child(far)
		far.queue_free()
	_mist.clear()
	_solids.clear()
	_noise_ready = false
	_foot = PackedVector3Array()
	_ensure_noise()
	far = Node3D.new()
	far.name = "Far"
	add_child(far, false, Node.INTERNAL_MODE_BACK)
	far.add_child(_mesh_node("Steppe", _ground_mesh()))
	var altai := _mesh_node("Altai", _altai_mesh())
	_altai = ShaderMaterial.new()
	_altai.shader = preload("res://assets/shaders/far_peaks.gdshader")
	_altai.render_priority = -1  # before the mist slabs, which veil their feet
	_altai.set_shader_parameter("veil", Vector2(steppe_y, steppe_y) + ALTAI.veil + Vector2.ONE * global_position.y)
	altai.material_override = _altai
	far.add_child(altai)
	var noise_tex := NoiseTexture2D.new()
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.generate_mipmaps = true
	var n := FastNoiseLite.new()
	n.seed = seed + 5
	n.frequency = 0.02
	n.fractal_octaves = 3
	noise_tex.noise = n
	for i in MIST_LAYERS.size():
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://assets/shaders/mist_sea.gdshader")
		mat.set_shader_parameter("noise_tex", noise_tex)
		mat.set_shader_parameter("noise_scale", 0.0007 * (1.0 + 0.5 * i))
		mat.set_shader_parameter("soft", MIST_LAYERS[i].soft)
		mat.render_priority = i
		_mist.append(mat)
		var node := _mesh_node("Mist%d" % (i + 1), _disc_mesh(MIST_RADIUS, 72))
		node.position.y = steppe_y + MIST_LAYERS[i].above
		node.material_override = mat
		far.add_child(node)
	# The storm's cloud deck overhead: the same slab shader, dark, thickening toward the horizon.
	_cloud = ShaderMaterial.new()
	_cloud.shader = preload("res://assets/shaders/mist_sea.gdshader")
	_cloud.set_shader_parameter("noise_tex", noise_tex)
	_cloud.set_shader_parameter("noise_scale", CLOUD.noise_scale)
	_cloud.set_shader_parameter("thickness", CLOUD.thickness)
	_cloud.set_shader_parameter("soft", 1.0)
	_cloud.set_shader_parameter("banks_range", Vector2(0.35, 1.7))
	_cloud.set_shader_parameter("rim_fade", Vector2(MIST_RADIUS * 0.55, MIST_RADIUS * 0.97))
	var deck := _mesh_node("Clouds", _disc_mesh(MIST_RADIUS, 72))
	deck.position.y = steppe_y + CLOUD.above
	deck.material_override = _cloud
	far.add_child(deck)
	_apply_reveal()
	_process(0.0)


func _apply_reveal() -> void:
	if far:
		far.visible = reveal > 0.0
	var fade := far_fade()
	for i in _mist.size():
		var layer: Dictionary = MIST_LAYERS[i]
		_mist[i].set_shader_parameter("thickness", lerpf(layer.closed, layer.open, reveal))
		_mist[i].set_shader_parameter("opacity", fade)
	if _cloud:
		_cloud.set_shader_parameter("opacity", fade)
	# While fading the solids blend (a depth pre-pass keeps their own faces sorted; render_priority
	# -1 draws them before the mist slabs); once fully in they are plain opaque again.
	for m in _solids:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if fade < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		m.albedo_color.a = fade
	if _altai:
		var fog := 0.0
		if world_environment and world_environment.environment:
			fog = world_environment.environment.fog_density
		_altai.set_shader_parameter("haze", altai_haze(fog))


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _ensure_noise() -> void:
	if _noise_ready:
		return
	_noise_ready = true
	_roll = FastNoiseLite.new()
	_roll.seed = seed
	_roll.frequency = 1.0 / 700.0
	_roll.fractal_octaves = 2
	_patch = FastNoiseLite.new()
	_patch.seed = seed + 1
	_patch.frequency = 1.0 / 260.0
	_patch.fractal_octaves = 2
	_domes = FastNoiseLite.new()
	_domes.seed = seed + 2
	_domes.frequency = 1.0 / 420.0
	_domes.fractal_octaves = 2
	_gully = FastNoiseLite.new()
	_gully.seed = seed + 3
	_gully.frequency = 1.0 / 300.0
	_gully.fractal_octaves = 1
	_hill_noise.clear()
	for i in HILLS.size():
		var h := FastNoiseLite.new()
		h.seed = seed + 10 + i
		h.frequency = 1.0
		h.fractal_octaves = 2
		_hill_noise.append(h)
	if _foot.is_empty():
		_find_foot()
	_build_cone()


func _find_foot() -> void:
	_foot = PackedVector3Array()
	if trail == null or trail.curve == null or trail.length() <= 0.0:
		return
	var top := steppe_y + global_position.y + FOOT_CLEAR + 1.0
	var count := int(trail.length() / 4.0)
	for i in count + 1:
		var p := trail.point_at(float(i) / count)
		if p.y < top:
			_foot.append(p)


## The cone under the trail (MountainTerrain.CONE_DROP below every trail point, rising
## MountainTerrain.CONE_SLOPE per metre away), as a two-pass chamfer transform on a grid.
func _build_cone() -> void:
	_cone_n = int(ceil(2.0 * CONE_EXTENT / CONE_CELL))
	var w := _cone_n + 1
	_cone = PackedFloat32Array()
	_cone.resize(w * w)
	_cone.fill(INF)
	if trail == null or trail.curve == null or trail.length() <= 0.0:
		return
	var count := int(trail.length() / 1.0)
	for i in count + 1:
		var p := trail.point_at(float(i) / count) - global_position
		var ix := clampi(roundi((p.x + CONE_EXTENT) / CONE_CELL), 0, _cone_n)
		var iz := clampi(roundi((p.z + CONE_EXTENT) / CONE_CELL), 0, _cone_n)
		_cone[iz * w + ix] = minf(_cone[iz * w + ix], p.y + global_position.y - MountainTerrain.CONE_DROP)
	var straight := MountainTerrain.CONE_SLOPE * CONE_CELL
	var diagonal := straight * sqrt(2.0)
	for iz in w:
		for ix in w:
			var k := iz * w + ix
			var v := _cone[k]
			if ix > 0:
				v = minf(v, _cone[k - 1] + straight)
			if iz > 0:
				v = minf(v, _cone[k - w] + straight)
				if ix > 0:
					v = minf(v, _cone[k - w - 1] + diagonal)
				if ix < _cone_n:
					v = minf(v, _cone[k - w + 1] + diagonal)
			_cone[k] = v
	for iz in range(_cone_n, -1, -1):
		for ix in range(_cone_n, -1, -1):
			var k := iz * w + ix
			var v := _cone[k]
			if ix < _cone_n:
				v = minf(v, _cone[k + 1] + straight)
			if iz < _cone_n:
				v = minf(v, _cone[k + w] + straight)
				if ix < _cone_n:
					v = minf(v, _cone[k + w + 1] + diagonal)
				if ix > 0:
					v = minf(v, _cone[k + w - 1] + diagonal)
			_cone[k] = v


## The trail's cone at `local` (bilinear on the grid; unbounded outside it).
func _cone_at(local: Vector2) -> float:
	if _cone.is_empty():
		return INF
	var fx := (local.x + CONE_EXTENT) / CONE_CELL
	var fz := (local.y + CONE_EXTENT) / CONE_CELL
	if fx < 0.0 or fz < 0.0 or fx >= _cone_n or fz >= _cone_n:
		return INF
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var w := _cone_n + 1
	var a := lerpf(_cone[iz * w + ix], _cone[iz * w + ix + 1], tx)
	var b := lerpf(_cone[(iz + 1) * w + ix], _cone[(iz + 1) * w + ix + 1], tx)
	return lerpf(a, b, tz)


## The hills' height above the floor at `local` (r = its length): broad rounded ridges along
## each ring, with soft saddles where the crest swells and dips, plus low domes in between.
func _hills(local: Vector2, r: float) -> float:
	if r < 1.0:
		return 0.0
	var dir := local / r
	var off := absf(atan2(dir.x, -dir.y))  # 0 toward -Z
	var h := 0.0
	for i in mini(ring_radii.size(), HILLS.size()):
		var layer: Dictionary = HILLS[i]
		var noise := _hill_noise[i]
		var radius: float = ring_radii[i]
		# Noise sampled on a circle, so it wraps round the ring.
		var wander: float = noise.get_noise_2d(dir.x * 0.7 + 50.0, dir.y * 0.7) * layer.wander * radius
		var t: float = (r - radius - wander) / (layer.width * radius)
		if absf(t) >= 1.0:
			continue
		var k: float = layer.lobes * 0.25  # about `lobes` swells round the ring
		var s := noise.get_noise_2d(dir.x * k, dir.y * k) * 0.8 + noise.get_noise_2d(dir.x * k * 2.1 - 30.0, dir.y * k * 2.1) * 0.2
		var crest := lerpf(layer.low, layer.high, smoothstep(-0.45, 0.45, s))
		var gap: Vector3 = layer.gap
		crest *= lerpf(gap.z, 1.0, smoothstep(gap.x, gap.y, off))
		# Rounded across: a raised cosine, the near side a little steeper than the far.
		var tt := t * (1.15 if t < 0.0 else 0.9)
		var b := 0.5 + 0.5 * cos(PI * clampf(tt, -1.0, 1.0))
		h = maxf(h, crest * b)
	# Gullies: V-shaped draws along the noise's zero lines, deepest where the hills are high.
	h *= 1.0 - GULLY * (1.0 - smoothstep(0.0, 0.3, absf(_gully.get_noise_2d(local.x, local.y))))
	var dome := _domes.get_noise_2d(local.x, local.y)
	h += DOMES * smoothstep(0.0, 0.5, dome) * smoothstep(420.0, 900.0, r) * (1.0 - smoothstep(2300.0, 2800.0, r))
	return h


func _mesh_node(node_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node


## Faceted triangles: every face its own normal, colours per vertex.
func _faceted(verts: PackedVector3Array, cols: PackedColorArray, solid := true) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var nrm := (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i]).normalized()
		normals[i] = nrm
		normals[i + 1] = nrm
		normals[i + 2] = nrm
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if solid:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.roughness = 1.0
		mat.render_priority = -1
		_solids.append(mat)
		mesh.surface_set_material(0, mat)
	return mesh


## A grid of rows x columns (columns wrap around) as faceted quads, upward-facing.
func _grid(points: Array[PackedVector3Array], colors: Array[PackedColorArray]) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for r in points.size() - 1:
		var a := points[r]
		var b := points[r + 1]
		var ca := colors[r]
		var cb := colors[r + 1]
		var n := a.size()
		for j in n:
			var k := (j + 1) % n
			# Rows run outward and columns clockwise seen from above, so these face up.
			verts.append_array([a[j], b[j], a[k], a[k], b[j], b[k]])
			cols.append_array([ca[j], cb[j], ca[k], ca[k], cb[j], cb[k]])
	return _faceted(verts, cols)


## The ground's polar grid: rings dense near the massif and sparser out to the edge.
func _ground_mesh() -> ArrayMesh:
	const RINGS_N := 150
	const SEGMENTS := 320
	var points: Array[PackedVector3Array] = []
	var origin := Vector2(global_position.x, global_position.z)
	var radii := PackedFloat32Array()
	for i in range(1, RINGS_N + 1):
		var r := steppe_radius * pow(float(i) / RINGS_N, 1.6)
		radii.append(r)
		var row := PackedVector3Array()
		for j in SEGMENTS:
			var a := TAU * j / SEGMENTS
			var local := Vector2(sin(a), -cos(a)) * r
			var y := steppe_height_at(origin + local) - global_position.y
			row.append(Vector3(local.x, y, local.y))
		points.append(row)
	var colors: Array[PackedColorArray] = []
	for i in RINGS_N:
		var crow := PackedColorArray()
		var row := points[i]
		var dr := radii[mini(i + 1, RINGS_N - 1)] - radii[maxi(i - 1, 0)]
		for j in SEGMENTS:
			var p := row[j]
			# Gradient from the neighbours: outward and round the ring, turned into x/z.
			var rise := points[mini(i + 1, RINGS_N - 1)][j].y - points[maxi(i - 1, 0)][j].y
			var side := row[(j + 1) % SEGMENTS].y - row[(j + SEGMENTS - 1) % SEGMENTS].y
			var across := TAU * radii[i] * 2.0 / SEGMENTS
			var a := TAU * j / SEGMENTS
			var grad := Vector2(sin(a), -cos(a)) * rise / maxf(dr, 0.01) + Vector2(cos(a), sin(a)) * side / maxf(across, 0.01)
			crow.append(_ground_tint(Vector2(p.x, p.z), radii[i], p.y, grad))
		colors.append(crow)
	return _grid(points, colors)


## The ground's colour at `local` (radius r, height y, gradient `grad` in rise per metre, x/z).
func _ground_tint(local: Vector2, r: float, y: float, grad: Vector2) -> Color:
	var n := _patch.get_noise_2d(local.x, local.y) * 0.7 + _patch.get_noise_2d(local.x * 3.7, local.y * 3.7) * 0.3
	var c := steppe_color
	if n < 0.0:
		c = c.lerp(OLIVE, 0.7 * smoothstep(0.0, -0.6, n))  # olive hollows
	else:
		c = c.lerp(STRAW, 0.55 * smoothstep(0.0, 0.6, n))  # pale dry grass
	var above := y - steppe_y
	var slope := grad.length()
	# Dry, pale crests; darker, more olive on the steeper sides.
	c = c.lerp(STRAW, 0.25 * smoothstep(50.0, 190.0, above))
	c = c.lerp(OLIVE.darkened(0.2), 0.4 * smoothstep(0.12, 0.55, slope))
	# Darker, greener grass and larch on the hills' north (-Z) faces, in patches.
	var north := smoothstep(0.05, 0.22, grad.y) * smoothstep(15.0, 45.0, above)
	c = c.lerp(SHADE, 0.75 * north * smoothstep(-0.35, 0.25, n))
	# Broad shadows of the storm clouds lying over the land.
	c = c.darkened(CLOUD_SHADOW * smoothstep(0.1, 0.45, _roll.get_noise_2d(local.x * 0.6 + 5000.0, local.y * 0.6)))
	var hollow := clampf(-above / ROLL, 0.0, 1.0)
	c = c.darkened(0.12 * hollow)
	# The massif's grassy flanks, matching MountainTerrain's raised ground.
	if terrain and r < 600.0:
		var flank := clampf((above - 6.0) / 30.0, 0.0, 1.0) * (1.0 - smoothstep(350.0, 600.0, r))
		c = c.lerp(MountainTerrain.FLANK_GRASS, flank)
	# Blue-grey with distance: each layer of hills paler and bluer than the one before.
	return c.lerp(FAR_TINT, 0.8 * smoothstep(500.0, 2600.0, r))


## The Altai: a sparse band of short snowy ranges on the far horizon, more of them (and the tallest)
## toward -Z where she looks. Each is a small faceted heightfield laid along the horizon, with a
## main summit and two or three lesser ones on a jagged ridge.
func _altai_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 30
	var slots: int = ALTAI.slots
	var radius: Vector2 = ALTAI.radius
	var height: Vector2 = ALTAI.height
	for i in slots:
		var a := TAU * (i + rng.randf_range(-0.3, 0.3)) / slots
		var off := absf(wrapf(a, -PI, PI))
		var keep := lerpf(0.85, 0.35, smoothstep(0.9, 2.4, off))
		var roll := rng.randf()
		var r := rng.randf_range(radius.x, radius.y)
		var h := rng.randf_range(height.x, height.y) * lerpf(1.0, 0.75, smoothstep(0.9, 2.4, off))
		if roll > keep:
			continue
		_range(verts, cols, Vector2(sin(a), -cos(a)) * r, Vector2(cos(a), sin(a)), h, rng)
	return _faceted(verts, cols, false)


## One short range centred at `centre` (local xz), its ridge along `tangent`, its main summit `h`
## above the steppe: faces above the snow line white, the rest blue-grey rock.
func _range(verts: PackedVector3Array, cols: PackedColorArray, centre: Vector2, tangent: Vector2, h: float, rng: RandomNumberGenerator) -> void:
	const NU := 14
	const NV := 7
	var outward := centre.normalized()
	var spread: Vector2 = ALTAI.spread
	var half_u := h * rng.randf_range(spread.x, spread.y)
	var half_v := h * 1.5
	# Summits kept clear of the edges, so no slope is cut off by the buried border.
	var summits: Array[Vector3] = [Vector3(rng.randf_range(-1.0, 1.0) * maxf(half_u - h * 1.2, 0.0), rng.randf_range(-0.1, 0.1) * half_v, h)]
	for k in rng.randi_range(2, 3):
		var sh := h * rng.randf_range(0.45, 0.78)
		var room := maxf(half_u - sh * 1.25, 0.0)
		summits.append(Vector3(rng.randf_range(-room, room), rng.randf_range(-0.15, 0.15) * half_v, sh))
	var floor_y := steppe_y - 40.0
	var rows: Array[PackedVector3Array] = []
	for iv in NV + 1:
		var row := PackedVector3Array()
		for iu in NU + 1:
			var inner := iu > 0 and iu < NU and iv > 0 and iv < NV
			var u := lerpf(-half_u, half_u, (iu + (rng.randf_range(-0.3, 0.3) if inner else 0.0)) / NU)
			var v := lerpf(-half_v, half_v, (iv + (rng.randf_range(-0.3, 0.3) if inner else 0.0)) / NV)
			var y := floor_y
			if inner:
				for s in summits:
					# Anisotropic: long along the ridge, steep across it; a little concave.
					var d := Vector2((u - s.x) / (s.z * 1.15), (v - s.y) / (s.z * 1.0)).length()
					y = maxf(y, floor_y + (s.z + 40.0) * pow(maxf(1.0 - d, 0.0), 1.2))
				y *= rng.randf_range(0.96, 1.04) if y > floor_y + 1.0 else 1.0
			var xz := centre + tangent * u + outward * v
			row.append(Vector3(xz.x, y, xz.y))
		rows.append(row)
	var snow_y: float = steppe_y + h * ALTAI.snow
	for iv in NV:
		var a := rows[iv]
		var b := rows[iv + 1]
		for j in NU:
			var k := j + 1
			# Rows run outward and columns along the tangent, as the ground's grid, so these face up.
			for tri: PackedVector3Array in [PackedVector3Array([a[j], b[j], a[k]]), PackedVector3Array([a[k], b[j], b[k]])]:
				var cy := (tri[0].y + tri[1].y + tri[2].y) / 3.0
				if cy < floor_y + 0.5:
					continue  # flat, buried floor
				var top := maxf(tri[0].y, maxf(tri[1].y, tri[2].y))
				var c := ALTAI_ROCK.darkened(0.25 * (1.0 - clampf((cy - steppe_y) / h, 0.0, 1.0)))
				if top > snow_y + rng.randf_range(-0.1, 0.06) * h and cy > snow_y - 0.15 * h:
					c = ALTAI_SNOW.darkened(rng.randf_range(0.0, 0.07))
				verts.append_array(tri)
				cols.append_array(PackedColorArray([c, c, c]))


func _disc_mesh(radius: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	for j in segments:
		var a0 := TAU * j / segments
		var a1 := TAU * (j + 1) / segments
		verts.append_array([Vector3.ZERO, Vector3(sin(a0), 0.0, -cos(a0)) * radius, Vector3(sin(a1), 0.0, -cos(a1)) * radius])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
