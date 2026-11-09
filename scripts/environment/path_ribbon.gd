@tool
extends MeshInstance3D
## Builds a flat ground ribbon through `points` (x, z) using a Catmull-Rom curve.
## Edit the points in the Inspector; the mesh rebuilds live in the editor.

@export var points: PackedVector2Array = PackedVector2Array():
	set(v):
		points = v
		_rebuild()
@export_range(0.5, 10.0, 0.1) var width := 2.4:
	set(v):
		width = v
		_rebuild()
## Width multiplier at the end of the path, so it can open up into a destination.
@export_range(0.2, 4.0, 0.05) var end_width_scale := 1.6:
	set(v):
		end_width_scale = v
		_rebuild()
@export_range(2, 32) var samples_per_segment := 10:
	set(v):
		samples_per_segment = v
		_rebuild()
## Edge wobble as a fraction of the half-width; each side wanders independently.
## 0 = a clean ribbon. Worn paths are never parallel-sided.
@export_range(0.0, 0.8, 0.01) var edge_noise := 0.0:
	set(v):
		edge_noise = v
		_rebuild()
@export var edge_noise_seed := 0:
	set(v):
		edge_noise_seed = v
		_rebuild()
## Width multiplier at the start, so a side trail can thin out where it branches off.
@export_range(0.1, 2.0, 0.05) var start_width_scale := 1.0:
	set(v):
		start_width_scale = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree() or points.size() < 2:
		return
	var samples := _sample()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := samples.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var noise := FastNoiseLite.new()
	noise.seed = edge_noise_seed
	noise.frequency = 0.18  # roughly one bulge every 5 m
	var dist := 0.0
	for i in n:
		var p := samples[i]
		if i > 0:
			dist += p.distance_to(samples[i - 1])
		var tangent := (samples[mini(i + 1, n - 1)] - samples[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		var t := float(i) / float(n - 1)
		var half := width * 0.5 * lerpf(1.0, end_width_scale, smoothstep(0.7, 1.0, t))
		half *= lerpf(start_width_scale, 1.0, smoothstep(0.0, 0.25, t))
		var half_l := half * (1.0 + edge_noise * noise.get_noise_2d(dist, 0.0) * 1.6)
		var half_r := half * (1.0 + edge_noise * noise.get_noise_2d(dist, 100.0) * 1.6)
		left.append(Vector3(p.x + side.x * half_l, 0.0, p.y + side.y * half_l))
		right.append(Vector3(p.x - side.x * half_r, 0.0, p.y - side.y * half_r))
	st.set_normal(Vector3.UP)
	for i in n - 1:
		_add_tri(st, left[i], right[i], right[i + 1])
		_add_tri(st, left[i], right[i + 1], left[i + 1])
	mesh = st.commit()


## Godot treats clockwise triangles (seen from the camera) as front faces; seen from above
## that means the cross product points down. Flip as needed so the ribbon faces the sky.
static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y > 0.0:
		var tmp := b
		b = c
		c = tmp
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## The sampled centre line in world x/z (used by scatter masks).
func get_centerline_world() -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() < 2:
		return out
	for p in _sample():
		var w := global_transform * Vector3(p.x, 0.0, p.y)
		out.append(Vector2(w.x, w.z))
	return out


func _sample() -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := points.size()
	for i in count - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, count - 1)]
		for s in samples_per_segment:
			var t := float(s) / samples_per_segment
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(points[count - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
