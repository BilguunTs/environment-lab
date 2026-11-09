@tool
class_name MountainTerrain
extends Node3D
## The Heavens call mountain, generated around `trail`: one faceted ArrayMesh plus a trimesh
## StaticBody3D (layers 1 + 2), both internal children with no owner, so the scene file stays
## small. Rebuilt when the node enters the tree (editor and game) and live in the editor when the
## trail's curve or a setting changes.
##
## How a height is made:
## - The massif: a steep flat-topped block whose top is the summit plateau (`summit_size`,
##   centred on the trail's end, long side across the final approach) and whose sides fall at
##   `cliff_slope`, roughened with noise. The trail was authored along its contours, so the
##   massif rises above the uphill side of the trail and falls away below the downhill side.
## - The corridor: within `corridor` metres of the centreline (narrowed at `narrows`), the ground
##   follows the trail's height with a gentle cross-slope. Where two legs of a switchback are
##   close, their heights blend, which leaves a steep bank between them.
## - Under the corridor: wherever the trail runs above the massif (the summit ridge, the
##   switchback landings), a cliff falls from the corridor's edge at `cliff_slope`, so the trail
##   never floats.
## - Beyond the corridor's edge the ground ramps over `RAMP` metres into whichever is higher:
##   a wall rises or a drop falls, both steeper than 50 degrees, so the corridor is bounded.
## - The flanks: the old mountain's broad, rounded body (envelope_at(): steep under the summit,
##   easing into long spurs and gullies that run some 450 m out into the land and end under the
##   steppe). Away from the trail the ground is raised to it, so the massif reads as a big old
##   mountain, the highest of the hills, rather than a pillar. The raise only ever adds ground,
##   and the trail is protected three ways: nothing changes within PROTECT.x metres of the
##   corridor's edge (full effect from PROTECT.y); below a trail point (a drop beside the path)
##   the raise stays under a cone CONE_DROP metres below it, rising CONE_SLOPE per metre away;
##   above one (a wall over the path) only under a cap CONE_LOOM above it rising LOOM_SLOPE per
##   metre (_trail_bound). The flanks are grassy low down and rock toward the summit. Near the
##   square's edge they sink under the envelope, and Vista builds the same flanks on past the
##   square (burying its edge).

## Width of the blend from the corridor's edge into the rock, in metres.
const RAMP := 2.0
## Rise of the corridor's cross-slope toward the uphill side, per metre.
const CROSS_SLOPE := 0.06
## Trail samples further apart than this along the trail belong to different legs.
const LEG_SEPARATION := 30.0
## The outermost ring of the mesh drops to this height, a cliff edge into the fog.
const SKIRT_Y := -200.0
## The flank envelope falls from the summit in two parts, each (metres of fall, horizontal metres
## over which most of it happens, as 1 - exp(-d / that)): a steep crown under the summit and a
## broad skirt; together they end under the steppe. Spurs push the skirt out (+) and gullies pull
## it in (-) by up to FLANK_SPUR of its reach; FLANK_ROLL is a broad roll on it, in metres.
const FLANK_CROWN := Vector2(90.0, 70.0)
const FLANK_SKIRT := Vector2(150.0, 260.0)
const FLANK_SPUR := 0.45
const FLANK_ROLL := 7.0
## Distance from the corridor's edge (m) where the flank raise starts / is at full strength.
const PROTECT := Vector2(4.0, 20.0)
## The drop cone the raised flanks stay under below a trail point: metres below it, rise per
## metre away from it (the vista's ground uses it too, see Vista).
const CONE_DROP := 18.0
const CONE_SLOPE := 0.55
## Over the path (ground that already stands above a trail point) the raise stays under a cap
## this far above the trail point, rising this much per metre away from it.
const CONE_LOOM := 6.0
const LOOM_SLOPE := 2.2
## Near the square's edge the ground sinks this far under the (coned) flank envelope, over
## EDGE_BAND metres, so Vista's ground (Vista.FLANK_SINK under the envelope) covers the edge.
const EDGE_SINK := 14.0
const EDGE_BAND := 50.0
## Colour of the grassy lower flanks (dry, olive-tan), shared with Vista's ground.
const FLANK_GRASS := Color(0.5, 0.44, 0.27)

@export var trail: Trail:
	set(value):
		trail = value
		_queue_rebuild()
## Size of the generated ground in metres, centred on this node.
@export var extent := Vector2(360, 360):
	set(value):
		extent = value
		_queue_rebuild()
## Grid spacing in metres.
@export var cell := 1.5:
	set(value):
		cell = maxf(value, 0.25)
		_queue_rebuild()
## Seeds the rock noise.
@export var seed := 7:
	set(value):
		seed = value
		_queue_rebuild()
## Walkable half-width either side of the centreline, in metres.
@export var corridor := 9.0:
	set(value):
		corridor = value
		_queue_rebuild()
## Chokepoints: each (progress, half-width) narrows the corridor to that half-width, easing back
## out over NARROW_FALLOFF metres of trail either side.
@export var narrows := PackedVector2Array():
	set(value):
		narrows = value
		_queue_rebuild()
## Summit plateau size (across the final approach, along it), centred on the trail's end.
@export var summit_size := Vector2(40, 25):
	set(value):
		summit_size = value
		_queue_rebuild()
## Steepness of the massif's sides and of the drops below the trail (rise per metre; 1.7 = 60 deg).
@export var cliff_slope := 1.7:
	set(value):
		cliff_slope = value
		_queue_rebuild()
@export var trail_color := Color(0.47, 0.41, 0.32):
	set(value):
		trail_color = value
		_queue_rebuild()
@export var rock_color := Color(0.28, 0.29, 0.3):
	set(value):
		rock_color = value
		_queue_rebuild()

const NARROW_FALLOFF := 14.0
const SAMPLE_STEP := 0.75

var _heights := PackedFloat32Array()
var _nx := 0
var _nz := 0
var _mesh_instance: MeshInstance3D
var _body: StaticBody3D
var _rebuild_queued := false
var _watched_curve: Curve3D

# Massif frame, in this node's space.
var _summit_y := 0.0
var _summit_centre := Vector2.ZERO
var _summit_axis := Vector2.RIGHT
var _built := false
var _spur: FastNoiseLite
var _roll: FastNoiseLite


func _ready() -> void:
	rebuild()


## Regenerates the mesh and the collision from the trail and the settings.
func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	_watch_curve()
	_clear()
	if trail == null or trail.curve == null or trail.length() <= 0.0:
		return
	_build()


## Ground height at world `xz`, as the mesh and the collision have it.
func height_at(xz: Vector2) -> float:
	if _heights.is_empty():
		return global_position.y
	var local := to_local(Vector3(xz.x, 0.0, xz.y))
	var fx := clampf((local.x + extent.x * 0.5) / cell, 0.0, _nx - 0.0001)
	var fz := clampf((local.z + extent.y * 0.5) / cell, 0.0, _nz - 0.0001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _heights[iz * (_nx + 1) + ix]
	var h10 := _heights[iz * (_nx + 1) + ix + 1]
	var h01 := _heights[(iz + 1) * (_nx + 1) + ix]
	var h11 := _heights[(iz + 1) * (_nx + 1) + ix + 1]
	# Same split as the mesh: triangles (00, 10, 01) and (10, 11, 01).
	var y: float
	if tx + tz <= 1.0:
		y = h00 + (h10 - h00) * tx + (h01 - h00) * tz
	else:
		y = h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)
	return (global_transform * Vector3(local.x, y, local.z)).y


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _watch_curve() -> void:
	if not Engine.is_editor_hint():
		return
	var c: Curve3D = trail.curve if trail else null
	if c == _watched_curve:
		return
	if _watched_curve and _watched_curve.changed.is_connected(_queue_rebuild):
		_watched_curve.changed.disconnect(_queue_rebuild)
	_watched_curve = c
	if c:
		c.changed.connect(_queue_rebuild)


func _clear() -> void:
	for child in [_mesh_instance, _body]:
		if is_instance_valid(child):
			remove_child(child)
			child.queue_free()
	_mesh_instance = null
	_body = null
	_heights = PackedFloat32Array()
	_built = false


## The old mountain's broad body at world `xz` (world height), before the trail's protection:
## steep under the summit, easing out into spurs and gullies. -INF until the terrain is built.
func envelope_at(xz: Vector2) -> float:
	if not _built:
		return -INF
	var local := to_local(Vector3(xz.x, 0.0, xz.y))
	return (global_transform * Vector3(local.x, _envelope(local.x, local.z), local.z)).y


func _envelope(x: float, z: float) -> float:
	var d := maxf(_summit_sdf(x, z), 0.0)
	var q := Vector2(x, z) - _summit_centre
	var dir := q.normalized() if q.length_squared() > 1e-6 else Vector2.RIGHT
	# Spurs: noise around the summit (sampled on a circle, so it wraps), drifting slowly with
	# distance so the spurs curve a little as they run out.
	var drift := d * 0.0025
	var s := _spur.get_noise_2d(dir.x * 1.3 + drift, dir.y * 1.3) * 0.7 \
			+ _spur.get_noise_2d(dir.x * 3.2 + 40.0, dir.y * 3.2 - drift) * 0.3
	var reach := FLANK_SKIRT.y * (1.0 + FLANK_SPUR * clampf(s * 1.8, -1.0, 1.0))
	var y := _summit_y - FLANK_CROWN.x * (1.0 - exp(-d / FLANK_CROWN.y)) - FLANK_SKIRT.x * (1.0 - exp(-d / reach))
	return y + FLANK_ROLL * _roll.get_noise_2d(x, z) * smoothstep(0.0, 40.0, d)


func _massif(x: float, z: float) -> float:
	return _summit_y - cliff_slope * maxf(_summit_sdf(x, z), 0.0)


## Signed horizontal distance from the summit plateau's edge (negative inside).
func _summit_sdf(x: float, z: float) -> float:
	var q := Vector2(x, z) - _summit_centre
	var along := q.dot(_summit_axis)
	var half := maxf(summit_size.x - summit_size.y, 0.0) * 0.5
	var c := _summit_axis * clampf(along, -half, half)
	return (q - c).length() - summit_size.y * 0.5


func _corridor_at(s: float, total: float) -> float:
	var c := corridor
	for n in narrows:
		var d := absf(s - n.x * total)
		var w := 1.0 - smoothstep(0.0, NARROW_FALLOFF, d)
		c = minf(c, lerpf(corridor, n.y, w))
	return c


func _build() -> void:
	var total := trail.length()
	# Trail samples in this node's space.
	var count := int(ceil(total / SAMPLE_STEP)) + 1
	var sp := PackedVector3Array()
	var sc := PackedFloat32Array()  # corridor half-width
	var ss := PackedFloat32Array()  # distance along the trail
	sp.resize(count)
	sc.resize(count)
	ss.resize(count)
	for i in count:
		var s := minf(i * SAMPLE_STEP, total)
		sp[i] = to_local(trail.point_at(s / total))
		sc[i] = _corridor_at(s, total)
		ss[i] = s
	var end := sp[count - 1]
	var before := sp[maxi(count - 4, 0)]
	var approach := Vector2(end.x - before.x, end.z - before.z).normalized()
	_summit_y = end.y
	_summit_centre = Vector2(end.x, end.z)
	_summit_axis = Vector2(-approach.y, approach.x)
	_spur = FastNoiseLite.new()
	_spur.seed = seed + 3
	_spur.frequency = 1.0
	_roll = FastNoiseLite.new()
	_roll.seed = seed + 4
	_roll.frequency = 0.012
	_roll.fractal_octaves = 2
	# Uphill direction of the massif at each sample, for the cross-slope.
	var su := PackedVector2Array()
	su.resize(count)
	for i in count:
		var x := sp[i].x
		var z := sp[i].z
		var g := Vector2(_massif(x + 0.5, z) - _massif(x - 0.5, z), _massif(x, z + 0.5) - _massif(x, z - 0.5))
		su[i] = g.normalized() if g.length_squared() > 1e-6 else Vector2.ZERO

	_nx = int(round(extent.x / cell))
	_nz = int(round(extent.y / cell))
	var w := _nx + 1
	var n := w * (_nz + 1)
	var x0 := -extent.x * 0.5
	var z0 := -extent.y * 0.5

	# Nearest sample (and nearest sample on a different leg) for every vertex near the trail.
	var d1 := PackedFloat32Array()
	var d2 := PackedFloat32Array()
	var i1 := PackedInt32Array()
	var i2 := PackedInt32Array()
	d1.resize(n)
	d2.resize(n)
	i1.resize(n)
	i2.resize(n)
	d1.fill(INF)
	d2.fill(INF)
	i1.fill(-1)
	i2.fill(-1)
	for si in count:
		var p := sp[si]
		var reach := sc[si] + RAMP + cell
		var ix_a := maxi(int(floor((p.x - reach - x0) / cell)), 0)
		var ix_b := mini(int(ceil((p.x + reach - x0) / cell)), _nx)
		var iz_a := maxi(int(floor((p.z - reach - z0) / cell)), 0)
		var iz_b := mini(int(ceil((p.z + reach - z0) / cell)), _nz)
		var reach2 := reach * reach
		var s := ss[si]
		for iz in range(iz_a, iz_b + 1):
			var dz := z0 + iz * cell - p.z
			for ix in range(ix_a, ix_b + 1):
				var dx := x0 + ix * cell - p.x
				var dd := dx * dx + dz * dz
				if dd > reach2:
					continue
				var d := sqrt(dd)
				var k := iz * w + ix
				var b1 := i1[k]
				if b1 < 0 or absf(s - ss[b1]) < LEG_SEPARATION:
					if d < d1[k]:
						d1[k] = d
						i1[k] = si
				elif i2[k] < 0 or absf(s - ss[i2[k]]) < LEG_SEPARATION:
					if d < d1[k]:
						d2[k] = d1[k]
						i2[k] = b1
						d1[k] = d
						i1[k] = si
					elif d < d2[k]:
						d2[k] = d
						i2[k] = si
				elif d < d1[k]:
					d2[k] = d1[k]
					i2[k] = b1
					d1[k] = d
					i1[k] = si
				elif d < d2[k]:
					d2[k] = d
					i2[k] = si

	# Corridor height (ht) and membership (m) per vertex.
	var ht := PackedFloat32Array()
	var m := PackedFloat32Array()
	ht.resize(n)
	m.resize(n)
	var cliff := PackedFloat32Array()  # seeds of the drop below the trail
	cliff.resize(n)
	cliff.fill(-INF)
	for k in n:
		var a := i1[k]
		if a < 0:
			continue
		var x := x0 + (k % w) * cell
		var z := z0 + (k / w) * cell
		var a1 := 1.0 - smoothstep(sc[a], sc[a] + RAMP, d1[k])
		var h1 := _corridor_height(sp[a], su[a], x, z)
		var wt1 := a1 / (d1[k] * d1[k] + 0.01)
		var sum := h1 * wt1
		var wsum := wt1
		var mm := a1
		var b := i2[k]
		if b >= 0:
			var a2 := 1.0 - smoothstep(sc[b], sc[b] + RAMP, d2[k])
			var wt2 := a2 / (d2[k] * d2[k] + 0.01)
			sum += _corridor_height(sp[b], su[b], x, z) * wt2
			wsum += wt2
			mm = maxf(mm, a2)
		if wsum > 0.0:
			ht[k] = sum / wsum
			m[k] = mm
			if mm >= 1.0:
				cliff[k] = ht[k]

	# The drop below the trail: max over corridor vertices of (height - slope * distance),
	# a two-pass chamfer distance transform.
	var straight := cliff_slope * cell
	var diagonal := straight * sqrt(2.0)
	for iz in _nz + 1:
		for ix in w:
			var k := iz * w + ix
			var v := cliff[k]
			if ix > 0:
				v = maxf(v, cliff[k - 1] - straight)
			if iz > 0:
				v = maxf(v, cliff[k - w] - straight)
				if ix > 0:
					v = maxf(v, cliff[k - w - 1] - diagonal)
				if ix < _nx:
					v = maxf(v, cliff[k - w + 1] - diagonal)
			cliff[k] = v
	for iz in range(_nz, -1, -1):
		for ix in range(_nx, -1, -1):
			var k := iz * w + ix
			var v := cliff[k]
			if ix < _nx:
				v = maxf(v, cliff[k + 1] - straight)
			if iz < _nz:
				v = maxf(v, cliff[k + w] - straight)
				if ix < _nx:
					v = maxf(v, cliff[k + w + 1] - diagonal)
				if ix > 0:
					v = maxf(v, cliff[k + w - 1] - diagonal)
			cliff[k] = v

	# The flanks' protection: distance from the corridor (seeded inside it) and the cone under
	# the trail (seeded at the centreline samples), both as two-pass chamfer transforms (min).
	var away := PackedFloat32Array()
	away.resize(n)
	for k in n:
		away[k] = 0.0 if m[k] >= 1.0 else INF
	var cone := PackedFloat32Array()
	cone.resize(n)
	cone.fill(INF)
	for si in count:
		var ix := clampi(roundi((sp[si].x - x0) / cell), 0, _nx)
		var iz := clampi(roundi((sp[si].z - z0) / cell), 0, _nz)
		var k := iz * w + ix
		cone[k] = minf(cone[k], sp[si].y - CONE_DROP)
	_chamfer_min(away, cell, cell * sqrt(2.0))
	_chamfer_min(cone, CONE_SLOPE * cell, CONE_SLOPE * cell * sqrt(2.0))

	# Final heights and colours.
	var broad := FastNoiseLite.new()
	broad.seed = seed
	broad.frequency = 0.011
	broad.fractal_octaves = 3
	var crag := FastNoiseLite.new()
	crag.seed = seed + 1
	crag.frequency = 0.07
	crag.fractal_octaves = 2
	var tint := FastNoiseLite.new()
	tint.seed = seed + 2
	tint.frequency = 0.05
	_heights.resize(n)
	var colors := PackedColorArray()
	colors.resize(n)
	var path_in := trail.width * 0.5
	var raised := PackedFloat32Array()  # how much each vertex belongs to the flanks (0..1)
	raised.resize(n)
	var tx_ := PackedFloat32Array()  # trail samples every 3 m, for _trail_bound
	var tz_ := PackedFloat32Array()
	var ty_ := PackedFloat32Array()
	for si in range(0, count, 4):
		tx_.append(sp[si].x)
		tz_.append(sp[si].z)
		ty_.append(sp[si].y)
	for k in n:
		var ix := k % w
		var iz := k / w
		var x := x0 + ix * cell
		var z := z0 + iz * cell
		var rough := smoothstep(-1.0, 6.0, _summit_sdf(x, z))
		var rock := _massif(x, z) + rough * (8.0 * broad.get_noise_2d(x, z) + 2.5 * crag.get_noise_2d(x, z))
		rock = maxf(rock, cliff[k] + 2.0 * crag.get_noise_2d(x + 300.0, z))
		var y := lerpf(rock, ht[k], m[k])
		# The flanks, only ever adding ground, kept off the corridor and under the trail's cones.
		var env := _envelope(x, z)
		var flank := env
		var wf := smoothstep(PROTECT.x, PROTECT.y, away[k])
		if wf > 0.0 and flank > y and flank > cone[k]:
			flank = minf(flank, _trail_bound(x, z, y, tx_, tz_, ty_))
		var y_raised := lerpf(y, maxf(y, flank), wf)
		raised[k] = wf * smoothstep(-1.0, 3.0, flank - y)
		# Near the square's edge, sink under the envelope so Vista's ground covers the edge.
		var edge := minf(minf(ix, _nx - ix), minf(iz, _nz - iz)) * cell
		var sink := maxf(minf(env, cone[k]) - EDGE_SINK, y)
		y = lerpf(y_raised, minf(y_raised, sink), 1.0 - smoothstep(3.0 * cell, EDGE_BAND, edge))
		if ix == 0 or iz == 0 or ix == _nx or iz == _nz:
			y = SKIRT_Y
		_heights[k] = y
	for k in n:
		var ix := k % w
		var iz := k / w
		var x := x0 + ix * cell
		var z := z0 + iz * cell
		var dc := INF
		if i1[k] >= 0:
			dc = d1[k]
		if i2[k] >= 0:
			dc = minf(dc, d2[k])
		var c := trail_color.lerp(rock_color, smoothstep(path_in, path_in + 1.5, dc))
		if raised[k] > 0.0:
			# The raised flanks are old grassy ground low down, giving way to rock toward the
			# summit and on the steepest pitches.
			var gx := _heights[iz * w + mini(ix + 1, _nx)] - _heights[iz * w + maxi(ix - 1, 0)]
			var gz := _heights[mini(iz + 1, _nz) * w + ix] - _heights[maxi(iz - 1, 0) * w + ix]
			var slope := Vector2(gx, gz).length() / (2.0 * cell)
			var grass := 1.0 - 0.6 * smoothstep(1.3, 2.6, slope)
			grass *= 1.0 - smoothstep(-150.0, -55.0, _heights[k] - _summit_y)
			c = c.lerp(FLANK_GRASS, raised[k] * grass)
		var v := 1.0 + 0.08 * tint.get_noise_2d(x, z)
		colors[k] = Color(c.r * v, c.g * v, c.b * v)

	_built = true
	_make_nodes(colors)


## The highest the flanks may be raised at (x, z), whose unraised ground is `y`: under each trail
## point it lies below (a drop beside the path) the drop cone, CONE_DROP below it rising
## CONE_SLOPE per metre; where it already stands above a trail point (a wall over the path), only
## a cap CONE_LOOM above it rising LOOM_SLOPE per metre, so nothing new looms over the path.
func _trail_bound(x: float, z: float, y: float, tx: PackedFloat32Array, tz: PackedFloat32Array, ty: PackedFloat32Array) -> float:
	var bound := INF
	for i in tx.size():
		var dx := x - tx[i]
		var dz := z - tz[i]
		var d := sqrt(dx * dx + dz * dz)
		var py := ty[i]
		var down := py - CONE_DROP + CONE_SLOPE * d
		if down >= bound:
			continue
		var s := smoothstep(-6.0, 2.0, y - py)
		bound = minf(bound, lerpf(down, py + CONE_LOOM + LOOM_SLOPE * d, s))
	return bound


## Two-pass chamfer transform keeping the minimum of (neighbour + step) on the vertex grid.
func _chamfer_min(f: PackedFloat32Array, straight: float, diagonal: float) -> void:
	var w := _nx + 1
	for iz in _nz + 1:
		for ix in w:
			var k := iz * w + ix
			var v := f[k]
			if ix > 0:
				v = minf(v, f[k - 1] + straight)
			if iz > 0:
				v = minf(v, f[k - w] + straight)
				if ix > 0:
					v = minf(v, f[k - w - 1] + diagonal)
				if ix < _nx:
					v = minf(v, f[k - w + 1] + diagonal)
			f[k] = v
	for iz in range(_nz, -1, -1):
		for ix in range(_nx, -1, -1):
			var k := iz * w + ix
			var v := f[k]
			if ix < _nx:
				v = minf(v, f[k + 1] + straight)
			if iz < _nz:
				v = minf(v, f[k + w] + straight)
				if ix < _nx:
					v = minf(v, f[k + w + 1] + diagonal)
				if ix > 0:
					v = minf(v, f[k + w - 1] + diagonal)
			f[k] = v


## Trail height at sample `p` extended to (x, z) with the cross-slope rising uphill.
func _corridor_height(p: Vector3, uphill: Vector2, x: float, z: float) -> float:
	var lateral := uphill.dot(Vector2(x - p.x, z - p.z))
	return p.y + clampf(CROSS_SLOPE * lateral, -0.6, 0.6)


func _make_nodes(colors: PackedColorArray) -> void:
	var w := _nx + 1
	var x0 := -extent.x * 0.5
	var z0 := -extent.y * 0.5
	var quads := _nx * _nz
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(quads * 6)
	normals.resize(quads * 6)
	cols.resize(quads * 6)
	var o := 0
	for iz in _nz:
		for ix in _nx:
			var k := iz * w + ix
			var p00 := Vector3(x0 + ix * cell, _heights[k], z0 + iz * cell)
			var p10 := Vector3(p00.x + cell, _heights[k + 1], p00.z)
			var p01 := Vector3(p00.x, _heights[k + w], p00.z + cell)
			var p11 := Vector3(p00.x + cell, _heights[k + w + 1], p00.z + cell)
			# Clockwise seen from above, so the faces point up.
			var n1 := (p01 - p00).cross(p10 - p00).normalized()
			var n2 := (p01 - p10).cross(p11 - p10).normalized()
			verts[o] = p00
			verts[o + 1] = p10
			verts[o + 2] = p01
			verts[o + 3] = p10
			verts[o + 4] = p11
			verts[o + 5] = p01
			normals[o] = n1
			normals[o + 1] = n1
			normals[o + 2] = n1
			normals[o + 3] = n2
			normals[o + 4] = n2
			normals[o + 5] = n2
			cols[o] = colors[k]
			cols[o + 1] = colors[k + 1]
			cols[o + 2] = colors[k + w]
			cols[o + 3] = colors[k + 1]
			cols[o + 4] = colors[k + w + 1]
			cols[o + 5] = colors[k + w]
			o += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "TerrainMesh"
	_mesh_instance.mesh = mesh
	add_child(_mesh_instance, false, Node.INTERNAL_MODE_BACK)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(verts)
	var col := CollisionShape3D.new()
	col.shape = shape
	_body = StaticBody3D.new()
	_body.name = "TerrainBody"
	_body.collision_layer = 3
	_body.add_child(col)
	add_child(_body, false, Node.INTERNAL_MODE_BACK)
