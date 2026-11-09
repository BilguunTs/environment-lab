extends SceneTree
## Run once to (re)write the Heavens call grass masks (the make_starter_grass.gd pattern):
##   godot --headless --path . -s res://tools/make_heavens_grass.gd
## Writes assets/grass/heavens_<name>.res for every field in SECTIONS plus the summit, and prints
## the matching `Grass` GrassField nodes as .tscn text (position, extent, ray span), which were
## pasted into scenes/levels/heavens_call.tscn. The masks are only a start: repaint them with the
## Grass Painter. Re-running overwrites the paint, and changing a section's progress range moves
## its field, so paste the printed nodes again after that. The look (blades_per_m2, heights,
## colours) is set on the nodes in the scene and isn't printed.
##
## Trail sections: sparse windswept tufts between bare rock (density 0.1-0.35 in clumps), zero on
## the gravel centre, a thin line of tufts along the path's edges (stronger near the top, where
## the light is low and the edges help the path read), none on steep ground. Each texel belongs
## to the section its nearest trail point (Trail.progress_at) falls in, so fields never overlap.
## Summit: golden grass over the whole plateau (0.6-0.9), clear around the ovoo cairns, with a
## worn line where the trail arrives, and an irregular fade toward the field border.

const OUT := "res://assets/grass/heavens_%s.res"
## name, progress from, progress to. The last section stops where the summit field takes over.
const SECTIONS := [
	["Lower", 0.0, 0.24],
	["Middle", 0.24, 0.5],
	["Switchback", 0.5, 0.72],
	["Upper", 0.72, 1.0],
]
const TRAIL_TEXEL := 0.5
## Metres beyond the corridor's reach a field's rectangle extends.
const MARGIN := 10.0
## Gravel kept clear: no grass within PATH_CLEAR of the centreline, full by PATH_CLEAR + RAMP.
const PATH_CLEAR := 2.0
const PATH_RAMP := 1.2
## Tufts thin out toward the corridor's edge (the walls and drops beyond get none).
const REACH := 8.5
## Ground steeper than this (rise per metre) gets no grass, fading in over the band below it.
const STEEP := Vector2(0.45, 0.8)
const TUFT_MAX := 0.35
const EDGE_BAND := 0.2
const EDGE_BAND_TOP := 0.32  ## near the summit, progress 0.82+
const SUMMIT_CENTRE := Vector3(0, 220, 0)
const SUMMIT_EXTENT := Vector2(48, 32)
const SUMMIT_TEXEL := 0.5
## Width of the summit field's irregular edge fade.
const SUMMIT_FADE := 6.0
## The ovoo cairns' ground positions (Vista/Ovoos in the scene): grass keeps clear of their stones.
const OVOOS := [Vector2(-14.0, -4.5), Vector2(13.0, -5.5), Vector2(2.5, -10.0)]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var lv: Node = load("res://scenes/levels/heavens_call.tscn").instantiate()
	root.add_child(lv)
	await physics_frame
	var ok := true
	var text := PackedStringArray()
	for cfg: Dictionary in fields(lv):
		var image := build_mask(lv, cfg)
		var path: String = OUT % cfg.name.to_lower()
		var err := ResourceSaver.save(image, path)
		ok = ok and err == OK
		var top := 0
		var data := image.get_data()
		for i in range(0, data.size(), 2):
			top = maxi(top, data[i])
		print("%s %s -> %s: %s (peak density %.2f)" % [cfg.name, image.get_size(), path,
			"saved" if err == OK else "error %d" % err, top / 255.0])
		text.append(node_text(cfg))
	print("\n".join(text))
	quit(0 if ok else 1)


## Field settings: the trail sections sized to their stretch of trail, then the summit.
static func fields(lv: Node) -> Array[Dictionary]:
	var trail: Trail = lv.get_node("Trail")
	var out: Array[Dictionary] = []
	for s: Array in SECTIONS:
		var lo := Vector3.INF
		var hi := -Vector3.INF
		var n := 200
		for i in n + 1:
			var p := trail.point_at(lerpf(s[1], s[2], float(i) / n))
			lo = lo.min(p)
			hi = hi.max(p)
		var reach := REACH + MARGIN
		var size := Vector2(hi.x - lo.x, hi.z - lo.z) + Vector2.ONE * reach * 2.0
		size = (size / GrassField.CHUNK_SIZE).ceil() * GrassField.CHUNK_SIZE
		var centre := Vector3((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, (lo.z + hi.z) * 0.5)
		centre = centre.round()
		var span := (hi.y - lo.y) * 0.5 + 25.0
		out.append({"name": s[0], "from": s[1], "to": s[2], "centre": centre, "extent": size,
			"texel": TRAIL_TEXEL, "span": ceilf(span)})
	out.append({"name": "Summit", "centre": SUMMIT_CENTRE, "extent": SUMMIT_EXTENT,
		"texel": SUMMIT_TEXEL, "span": 8.0})
	return out


## The mask for one field config (from fields()), built in memory; nothing is written.
static func build_mask(lv: Node, cfg: Dictionary) -> Image:
	var trail: Trail = lv.get_node("Trail")
	var terrain: MountainTerrain = lv.get_node("MountainTerrain")
	var texel: float = cfg.texel
	var extent: Vector2 = cfg.extent
	var centre: Vector3 = cfg.centre
	var size := Vector2i(ceili(extent.x / texel), ceili(extent.y / texel))
	var corner := Vector2(centre.x, centre.z) - extent * 0.5
	var summit: bool = cfg.name == "Summit"
	var summit_rect := Rect2(Vector2(SUMMIT_CENTRE.x, SUMMIT_CENTRE.z) - SUMMIT_EXTENT * 0.5, SUMMIT_EXTENT)
	# The section's own centreline, for a cheap "near this section at all" test.
	var line := PackedVector2Array()
	if not summit:
		var count := int((cfg.to - cfg.from) * trail.length() / 2.0) + 1
		for i in count + 1:
			var p := trail.point_at(lerpf(cfg.from, cfg.to, float(i) / count))
			line.append(Vector2(p.x, p.z))
	var tufts := FastNoiseLite.new()
	tufts.seed = 31
	tufts.frequency = 1.0 / 2.2
	tufts.fractal_octaves = 2
	var broad := FastNoiseLite.new()
	broad.seed = 37
	broad.frequency = 1.0 / 30.0
	var hnoise := FastNoiseLite.new()
	hnoise.seed = 41
	hnoise.frequency = 1.0 / 6.0

	var data := PackedByteArray()
	data.resize(size.x * size.y * 2)
	for y in size.y:
		for x in size.x:
			var p := corner + (Vector2(x, y) + Vector2(0.5, 0.5)) * texel
			var density := 0.0
			var height := 0.5 + 0.35 * hnoise.get_noise_2d(p.x, p.y)
			if summit:
				density = _summit_density(p, trail, terrain, broad, tufts)
				density *= _summit_edge_fade(p, summit_rect, tufts, broad)
				height = 0.55 + 0.4 * hnoise.get_noise_2d(p.x, p.y)
			elif not summit_rect.has_point(p) and _near_line(p, line, REACH + 1.0):
				density = _trail_density(p, cfg, trail, terrain, tufts, broad)
			var i := (y * size.x + x) * 2
			data[i] = roundi(clampf(density, 0.0, 1.0) * 255.0)
			data[i + 1] = roundi(clampf(height, 0.0, 1.0) * 255.0)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RG8, data)


static func _trail_density(p: Vector2, cfg: Dictionary, trail: Trail, terrain: MountainTerrain,
		tufts: FastNoiseLite, broad: FastNoiseLite) -> float:
	var ground := Vector3(p.x, terrain.height_at(p), p.y)
	var progress := trail.progress_at(ground)
	if progress < cfg.from or (progress >= cfg.to and cfg.to < 1.0):
		return 0.0
	var dc := trail.distance_to_centre(ground)
	var off_path := smoothstep(PATH_CLEAR, PATH_CLEAR + PATH_RAMP, dc)
	if off_path <= 0.0:
		return 0.0
	var steep := 1.0 - smoothstep(STEEP.x, STEEP.y, _slope(terrain, p))
	var reach := 1.0 - smoothstep(REACH - 2.5, REACH, dc)
	# Clumps: metre-sized noise spots thresholded into tufts, gathered where the broad noise is
	# high; a little lusher low down, thinner in the eerie stretch.
	var n := tufts.get_noise_2d(p.x, p.y)
	var clump := smoothstep(-0.05, 0.3, n) * smoothstep(-0.45, 0.15, broad.get_noise_2d(p.x, p.y))
	var lush := lerpf(1.0, 0.7, smoothstep(0.5, 0.75, progress))
	var density := TUFT_MAX * clump * lush
	# A thin line of tufts just off the gravel, so the path's edge reads in low light.
	var band_strength := lerpf(EDGE_BAND, EDGE_BAND_TOP, smoothstep(0.78, 0.84, progress))
	var band := band_strength * (1.0 - smoothstep(PATH_CLEAR + 0.8, PATH_CLEAR + 2.2, dc))
	band *= 0.55 + 0.45 * smoothstep(-0.4, 0.3, tufts.get_noise_2d(p.x * 2.0, p.y * 2.0))
	density = maxf(density, band)
	density *= off_path * steep * reach
	return 0.0 if density < 0.06 else minf(density, 0.4)


static func _summit_density(p: Vector2, trail: Trail, terrain: MountainTerrain,
		broad: FastNoiseLite, tufts: FastNoiseLite) -> float:
	var h := terrain.height_at(p)
	if h < SUMMIT_CENTRE.y - 0.8:
		return 0.0  # over the edge
	var steep := 1.0 - smoothstep(0.3, 0.6, _slope(terrain, p))
	var n := broad.get_noise_2d(p.x, p.y) * 0.6 + tufts.get_noise_2d(p.x, p.y) * 0.4
	var density := 0.6 + 0.3 * clampf(n * 0.5 + 0.5, 0.0, 1.0)
	for o: Vector2 in OVOOS:
		density *= smoothstep(1.6, 2.6, p.distance_to(o))
	# A worn line where the trail arrives, ending in the meadow.
	var ground := Vector3(p.x, h, p.y)
	if trail.progress_at(ground) < 0.995:
		density *= lerpf(0.15, 1.0, smoothstep(0.9, 2.2, trail.distance_to_centre(ground)))
	return density * steep


## Soft, irregular falloff over the outer SUMMIT_FADE metres of the summit field, so its border
## doesn't read as a straight-edged rectangle: the fade's reach is modulated by noise, and the
## surviving density is broken into tufts near the edge.
static func _summit_edge_fade(p: Vector2, rect: Rect2, tufts: FastNoiseLite, broad: FastNoiseLite) -> float:
	var d := minf(minf(p.x - rect.position.x, rect.end.x - p.x), minf(p.y - rect.position.y, rect.end.y - p.y))
	var reach := SUMMIT_FADE * (0.55 + 0.45 * (broad.get_noise_2d(p.x * 3.1 + 50.0, p.y * 3.1) * 0.5 + 0.5) * 1.6)
	var t := smoothstep(0.0, reach, d)
	var patchy := smoothstep(-0.2, 0.35, tufts.get_noise_2d(p.x * 1.3 + 9.0, p.y * 1.3))
	return t * lerpf(patchy, 1.0, t)


static func _slope(terrain: MountainTerrain, p: Vector2) -> float:
	const D := 0.75
	var gx := terrain.height_at(p + Vector2(D, 0)) - terrain.height_at(p - Vector2(D, 0))
	var gz := terrain.height_at(p + Vector2(0, D)) - terrain.height_at(p - Vector2(0, D))
	return Vector2(gx, gz).length() / (2.0 * D)


static func _near_line(p: Vector2, line: PackedVector2Array, reach: float) -> bool:
	var r2 := reach * reach
	for q in line:
		if p.distance_squared_to(q) <= r2:
			return true
	return false


## The GrassField node for `cfg` as .tscn text (its mask is ExtResource "mask_<name>").
static func node_text(cfg: Dictionary) -> String:
	var c: Vector3 = cfg.centre
	var e: Vector2 = cfg.extent
	return "[node name=\"%s\" type=\"Node3D\" parent=\"Grass\"]\ntransform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\nscript = ExtResource(\"grass_script\")\nextent = Vector2(%s, %s)\ntexel_size = %s\nmask = ExtResource(\"mask_%s\")\nray_above = %s\nray_below = %s\n" % [
		cfg.name, c.x, c.y, c.z, e.x, e.y, cfg.texel, cfg.name.to_lower(), cfg.span, cfg.span]
