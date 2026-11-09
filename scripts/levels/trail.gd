@tool
class_name Trail
extends Path3D
## The authored trail centreline of the Heavens call climb: `curve` runs from the foot (offset 0)
## to the summit plateau. Progress along it (0..1) drives the mood, the respawn and the terrain.

## Width of the worn path surface, in metres (the terrain paints it in `trail_color`).
@export var width := 3.0

## How much a height difference counts when matching a position to the trail: 1 = true 3D
## distance, 0 = horizontal only. In between keeps a player who fell far below a ledge matched
## to that ledge, while a player standing on one leg of a switchback isn't matched to the leg
## above or below her.
const VERTICAL_WEIGHT := 0.35
## progress_at scans every this-many baked points first (the curve bakes every 0.5 m).
const COARSE_STEP := 6

var _points := PackedVector3Array()  # baked centreline, local space
var _offsets := PackedFloat32Array()  # distance along the curve of each baked point
var _cached_curve: Curve3D


## Total length of the centreline in metres.
func length() -> float:
	return curve.get_baked_length() if curve else 0.0


## The world position at `progress` (0 = foot, 1 = summit) along the centreline.
func point_at(progress: float) -> Vector3:
	if not curve:
		return global_position
	return global_transform * curve.sample_baked(clampf(progress, 0.0, 1.0) * length())


## Progress (0..1) of the centreline point closest to `world_pos`, with height differences
## down-weighted by VERTICAL_WEIGHT (see there).
func progress_at(world_pos: Vector3) -> float:
	var l := length()
	if l <= 0.0:
		return 0.0
	return _closest(to_local(world_pos)).x / l


## Horizontal distance from `world_pos` to the centreline (to the stretch progress_at matches).
func distance_to_centre(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	var c := _closest(local)
	var p := global_transform * Vector3(c.y, 0.0, c.z)
	p.y = 0.0
	return Vector2(world_pos.x - p.x, world_pos.z - p.z).length()


## Closest centreline point to `local`: returns (offset, x, z) in local space.
func _closest(local: Vector3) -> Vector3:
	_ensure_cache()
	var n := _points.size()
	if n == 0:
		return Vector3.ZERO
	# Coarse pass over every COARSE_STEP-th baked point, then a fine pass around the winner.
	var best := 0
	var best_d := INF
	for i in range(0, n, COARSE_STEP):
		var d := _metric(_points[i] - local)
		if d < best_d:
			best_d = d
			best = i
	var coarse := best
	for i in range(maxi(coarse - COARSE_STEP, 0), mini(coarse + COARSE_STEP + 1, n)):
		var d := _metric(_points[i] - local)
		if d < best_d:
			best_d = d
			best = i
	# Refine on the two segments either side of the nearest baked point.
	var result := Vector3(_offsets[best], _points[best].x, _points[best].z)
	for j in [best - 1, best]:
		if j < 0 or j + 1 >= n:
			continue
		var a := _points[j]
		var b := _points[j + 1]
		var ab := _squash(b - a)
		var len2 := ab.length_squared()
		if len2 <= 0.0:
			continue
		var t := clampf(_squash(local - a).dot(ab) / len2, 0.0, 1.0)
		var q := a.lerp(b, t)
		var d := _metric(q - local)
		if d < best_d:
			best_d = d
			result = Vector3(lerpf(_offsets[j], _offsets[j + 1], t), q.x, q.z)
	return result


static func _squash(v: Vector3) -> Vector3:
	return Vector3(v.x, v.y * VERTICAL_WEIGHT, v.z)


static func _metric(v: Vector3) -> float:
	return _squash(v).length_squared()


func _ensure_cache() -> void:
	if _cached_curve == curve and not _points.is_empty():
		return
	if _cached_curve and _cached_curve.changed.is_connected(_invalidate):
		_cached_curve.changed.disconnect(_invalidate)
	_cached_curve = curve
	_points = PackedVector3Array()
	_offsets = PackedFloat32Array()
	if not curve:
		return
	curve.changed.connect(_invalidate)
	_points = curve.get_baked_points()
	_offsets.resize(_points.size())
	var acc := 0.0
	for i in _points.size():
		if i > 0:
			acc += _points[i].distance_to(_points[i - 1])
		_offsets[i] = acc
	# The baked offsets sum the polyline; scale them to the curve's own baked length.
	if acc > 0.0:
		var k := curve.get_baked_length() / acc
		for i in _offsets.size():
			_offsets[i] *= k


func _invalidate() -> void:
	_points = PackedVector3Array()
