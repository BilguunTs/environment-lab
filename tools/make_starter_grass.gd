extends SceneTree
## Run once to (re)write the starter meadow mask:
##   godot --headless --path . -s res://tools/make_starter_grass.gd
## Density is patchy noise, zero on the path and the clearing; height grows with distance from
## the path. Texels are written directly (R density, G height, byte-scaled).

const OUT := "res://assets/grass/playground_grass.res"
const FIELD_CENTRE := Vector2(0, 6)
const FIELD_EXTENT := Vector2(74, 104)
const TEXEL := 0.5
const PATH_CLEAR := 1.0  ## metres beyond the path's half-width with no grass
const PATH_RAMP := 2.0  ## ...then density ramps to full over this much more
const HEIGHT_NEAR := 0.3
const HEIGHT_FAR := 0.9
const HEIGHT_FAR_AT := 15.0


func _init() -> void:
	var scene: Node = load("res://scenes/playground.tscn").instantiate()
	var image := build_mask(scene)
	var err := ResourceSaver.save(image, OUT)
	print("starter grass mask %s: %s" % [image.get_size(), "saved" if err == OK else "error %d" % err])
	scene.free()
	quit(0 if err == OK else 1)


## The starter mask for `scene` (a playground), built in memory; nothing is written.
static func build_mask(scene: Node) -> Image:
	var lines: Array = []  # [PackedVector2Array centreline, PackedFloat32Array half widths]
	for node_name in ["Path", "SideTrail"]:
		var n: Node = scene.get_node(node_name)
		var xf: Transform3D = Transform3D(n.transform)
		var pts := PackedVector2Array()
		var halves := PackedFloat32Array()
		var samples: PackedVector2Array = n.call("_sample")
		for i in samples.size():
			var w := xf * Vector3(samples[i].x, 0.0, samples[i].y)
			pts.append(Vector2(w.x, w.z))
			# Same width profile as PathRibbon, plus allowance for the edge noise bulges.
			var t := float(i) / float(samples.size() - 1)
			var half: float = float(n.get("width")) * 0.5 * lerpf(1.0, float(n.get("end_width_scale")), smoothstep(0.7, 1.0, t))
			half *= lerpf(float(n.get("start_width_scale")), 1.0, smoothstep(0.0, 0.25, t))
			halves.append(half * (1.0 + float(n.get("edge_noise")) * 0.8))
		lines.append([pts, halves])
	var clearing: Node3D = scene.get_node("Clearing")
	var clearing_c := Vector2(clearing.position.x, clearing.position.z)
	var clearing_r: float = (clearing.get_node("Floor") as MeshInstance3D).mesh.get("top_radius")

	var size := Vector2i(ceili(FIELD_EXTENT.x / TEXEL), ceili(FIELD_EXTENT.y / TEXEL))
	var corner := FIELD_CENTRE - FIELD_EXTENT * 0.5
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 12.0
	var hnoise := FastNoiseLite.new()
	hnoise.seed = 19
	hnoise.frequency = 1.0 / 9.0

	var data := PackedByteArray()
	data.resize(size.x * size.y * 2)
	for y in size.y:
		for x in size.x:
			var p := corner + (Vector2(x, y) + Vector2(0.5, 0.5)) * TEXEL
			var d := INF  # distance beyond the nearest path edge
			for line: Array in lines:
				d = minf(d, _dist_beyond_edge(p, line[0], line[1]))
			var patch := lerpf(0.4, 1.0, clampf(noise.get_noise_2d(p.x, p.y) * 0.5 + 0.5, 0.0, 1.0))
			var density := patch * smoothstep(PATH_CLEAR, PATH_CLEAR + PATH_RAMP, d)
			if p.distance_to(clearing_c) <= clearing_r + 0.5:
				density = 0.0
			var h_t := clampf(maxf(d, 0.0) / HEIGHT_FAR_AT, 0.0, 1.0)
			var h := lerpf(HEIGHT_NEAR, HEIGHT_FAR, h_t) + hnoise.get_noise_2d(p.x, p.y) * 0.08
			# G is 0..1 across min_height..max_height (0.25..0.9); store the target metres.
			var g := clampf((h - 0.25) / (0.9 - 0.25), 0.0, 1.0)
			var i := (y * size.x + x) * 2
			data[i] = roundi(clampf(density, 0.0, 1.0) * 255.0)
			data[i + 1] = roundi(g * 255.0)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RG8, data)


## Distance from p to the path's edge (negative inside), by nearest centreline segment.
static func _dist_beyond_edge(p: Vector2, pts: PackedVector2Array, halves: PackedFloat32Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		var a := pts[i]
		var ab := pts[i + 1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t) - lerpf(halves[i], halves[i + 1], t))
	return best
