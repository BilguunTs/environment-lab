class_name ReplicaCapture
extends Node
## Validation runs on a built ReplicaSite (Task 11), started from the command line after `--`:
##   --capture-topdown  build/topdown.png: the core straight down, orthographic, at the class map's
##                      resolution (manifest core.size_m / classes_full 0.5 m -> 4000 x 4000 px),
##                      rendered in tiles of TILE_PX. Capture mode (below). For `replica check`.
##   --walk-perf        the scripted walk (spawn by the first ger -> site centre -> beside the
##                      largest tor -> rise to an aerial view), frame times per leg and overall:
##                      min, 1 %-low and average fps. Prints a table, writes
##                      screenshots/replica_perf_<site>_<datetime>.md. Run with --disable-vsync.
##   --capture-views    screenshots/replica_<site>_<view>.png at the walk's spawn, tor and aerial
##                      points.
##   --quit             quit when done.
##
## Capture mode draws the ground unlit in its class palette and every rock / fill-piece mesh in
## one unlit ROCK_COLOR, with grass, scrub, trees, scree, stones, gers, the player and the ring
## hidden, so the rendered rock mask is exact (tools/terrain/replica/check.py, CAPTURE_ROCK_RGB).
## Scree and stones are rule fill (not traced rocks) and are left out of the mask.
## exit_capture_mode() restores everything.

## The top-down camera sits this far above the highest ground (far above any rock).
const HEADROOM_M := 500.0
## Unlit colour of rocks in capture mode (check.py CAPTURE_ROCK_RGB).
const ROCK_COLOR := Color(1.0, 0.0, 1.0)
const TILE_PX := 2000
## Scatter types drawn in capture mode (the rest is hidden).
const CAPTURE_TYPES := ["fill_round", "fill_slab"]
## Walk speed (m/s): the player's sprint speed.
const WALK_SPEED := 7.0
const SETTLE_FRAMES := 60
## The aerial leg: rise to this height above the tor-side point, over this many seconds, then hold.
const AERIAL_RISE_M := 350.0
const AERIAL_RISE_S := 5.0
const AERIAL_HOLD_S := 5.0
## Distance (m) outside the tor's outline the walk ends at.
const TOR_STANDOFF_M := 4.0

var site: ReplicaSite
var _saved: Array = []  # [object, property, value] to restore after capture mode


## Runs the command-line jobs in `args` on `target` (already built).
func run(target: ReplicaSite, args: PackedStringArray) -> void:
	site = target
	if "--capture-topdown" in args:
		await capture_topdown()
	if "--capture-views" in args:
		await capture_views()
	if "--walk-perf" in args:
		await walk_perf()
	if "--quit" in args:
		get_tree().quit()


# --- capture mode --------------------------------------------------------------------------------

func enter_capture_mode() -> void:
	if not _saved.is_empty():
		return
	var unlit := StandardMaterial3D.new()
	unlit.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	unlit.albedo_color = ROCK_COLOR
	var terrain_shader := Shader.new()
	terrain_shader.code = (site.terrain.tiles()[0].material_override as ShaderMaterial).shader.code \
			.replace("render_mode cull_back;", "render_mode cull_back, unshaded;")
	var terrain_materials := {}
	for tile: MeshInstance3D in site.terrain.tiles():
		if tile.name.begins_with("Ring") or tile.name.ends_with("lod1"):
			_override(tile, "visible", false)
			continue
		_override(tile, "visibility_range_end", 0.0)
		var m := tile.material_override as ShaderMaterial
		if not terrain_materials.has(m):
			var c := m.duplicate() as ShaderMaterial
			c.shader = terrain_shader
			terrain_materials[m] = c
		_override(tile, "material_override", terrain_materials[m])
	if site.grass:
		_override(site.grass, "visible", false)
	for ger in site.ger_nodes():
		_override(ger, "visible", false)
	if site.player:
		_override(site.player, "visible", false)
	for rock in site.get_node("Rocks").get_children():
		if rock is MeshInstance3D:
			_override(rock, "material_override", unlit)
	for type: String in site.scatter_types():
		for node in site.scatter_nodes(type):
			if type in CAPTURE_TYPES:
				_override(node, "material_override", unlit)
			else:
				_override(node, "visible", false)


func exit_capture_mode() -> void:
	for i in range(_saved.size() - 1, -1, -1):
		var s: Array = _saved[i]
		if is_instance_valid(s[0]):
			s[0].set(s[1], s[2])
	_saved.clear()


func _override(object: Object, property: String, value: Variant) -> void:
	_saved.append([object, property, object.get(property)])
	object.set(property, value)


## The ground-and-rocks picture (capture mode must be on) of the size_m square centred on world
## (centre.x, centre.y) as px x px, north up, east right: pixel (r, c) covers
## x in [left + c * m, left + (c + 1) * m), z likewise with r (m = size_m / px).
func render_topdown(centre: Vector2, size_m: float, px: int) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(px, px)
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_taa = false
	vp.use_debanding = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = size_m
	var top := _highest() + HEADROOM_M
	cam.near = 0.05
	cam.far = top + 1000.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	cam.environment = env
	vp.add_child(cam)
	add_child(vp)
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)), Vector3(centre.x, top, centre.y))
	cam.current = true
	for _f in 4:
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	vp.queue_free()
	image.convert(Image.FORMAT_RGB8)
	return image


## Highest ground (core tile bounds); the camera sits HEADROOM_M above it.
func _highest() -> float:
	var top := -INF
	for tile in site.terrain.tiles():
		if tile.name.begins_with("Core"):
			top = maxf(top, tile.position.y + tile.custom_aabb.end.y)
	return top


## Writes build/topdown.png (manifest core square at the class map's 0.5 m/px), tiled.
func capture_topdown() -> String:
	var size_m := float(site.manifest.core.size_m)
	var classes_px := int(site.manifest.classes.n) * 2  # classes_full is twice classes.png (Ruling 4)
	var tiles := ceili(float(classes_px) / TILE_PX)
	var tile_px := classes_px / tiles
	var tile_m := size_m / tiles
	enter_capture_mode()
	var out := Image.create_empty(classes_px, classes_px, false, Image.FORMAT_RGB8)
	for ti in tiles:
		for tj in tiles:
			var c := Vector2(-size_m * 0.5 + (tj + 0.5) * tile_m, -size_m * 0.5 + (ti + 0.5) * tile_m)
			var image := await render_topdown(c, tile_m, tile_px)
			out.blit_rect(image, Rect2i(0, 0, tile_px, tile_px), Vector2i(tj * tile_px, ti * tile_px))
	exit_capture_mode()
	var path := site.build_dir().path_join("topdown.png")
	out.save_png(path)
	print("ReplicaCapture: wrote %s (%d px, %.2f m/px)" % [path, classes_px, size_m / classes_px])
	return path


# --- the walk ------------------------------------------------------------------------------------

## Walk waypoints (x, z): spawn, site centre, beside the largest tor (largest outline area).
func walk_points() -> PackedVector2Array:
	var spawn := site.spawn_point()
	var pts := PackedVector2Array([Vector2(spawn.x, spawn.z), Vector2.ZERO])
	var tor := largest_tor()
	if not tor.is_empty():
		var poly: PackedVector2Array = tor.poly
		var centre := Vector2(tor.x, tor.z)
		var near := poly[0]
		for p in poly:
			if p.distance_to(Vector2.ZERO) < near.distance_to(Vector2.ZERO):
				near = p
		pts.append(near + (near - centre).normalized() * TOR_STANDOFF_M)
	return pts


## The placed mass with the largest outline area: {id, x, z, poly}, or {} without masses.
func largest_tor() -> Dictionary:
	var best := {}
	var best_area := 0.0
	for r: Dictionary in site.placed_rocks():
		if r.kind != "mass" or not r.outline:
			continue
		var poly := PackedVector2Array()
		for p: Array in r.outline:
			poly.append(Vector2(p[0], p[1]))
		var area := 0.0
		for k in poly.size():
			area += poly[k].cross(poly[(k + 1) % poly.size()])
		area = absf(area) * 0.5
		if area > best_area:
			best_area = area
			best = {"id": r.id, "x": float(r.x), "z": float(r.z), "poly": poly, "area": area}
	return best


func _stand(p: Vector2, heading: Vector2) -> void:
	var player := site.player
	player.global_position = Vector3(p.x, site.ground_y(p.x, p.y) + 0.02, p.y)
	player.velocity = Vector3.ZERO
	var cam := site.follow_camera
	if cam and heading.length() > 0.0:
		cam.set("yaw_deg", rad_to_deg(atan2(-heading.x, -heading.y)))


func _hold_player(on: bool) -> void:
	site.player.set_physics_process(not on)
	site.player.set("input_enabled", not on)


## Frame times (s) per leg: {"leg name": PackedFloat64Array}.
func walk_perf() -> Dictionary:
	var legs := {}
	var pts := walk_points()
	var names := ["spawn -> centre", "centre -> tor"]
	_hold_player(true)
	_stand(pts[0], pts[1] - pts[0])
	if site.follow_camera.has_method("snap"):
		site.follow_camera.snap()
	site.grass.fill_now()
	for _f in SETTLE_FRAMES:
		await get_tree().process_frame
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var times := PackedFloat64Array()
		var walked := 0.0
		var length := a.distance_to(b)
		if length < 0.01:
			continue  # no gers: the spawn is the site centre
		var t := Time.get_ticks_usec()
		while walked < length:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - t) / 1e6
			t = now
			times.append(dt)
			walked = minf(length, walked + WALK_SPEED * dt)
			_stand(a.lerp(b, walked / length), b - a)
		legs[names[k] if k < names.size() else "leg %d" % k] = times
	legs["aerial"] = await _aerial(pts[pts.size() - 1])
	_hold_player(false)
	_report(legs)
	return legs


func _aerial(p: Vector2) -> PackedFloat64Array:
	var cam := site.follow_camera
	cam.set_process(false)
	var from := cam.global_transform
	var ground := site.ground_y(p.x, p.y)
	var to_pos := Vector3(p.x, ground + AERIAL_RISE_M, p.y)
	var to := Transform3D(Basis.looking_at(Vector3(0.0, site.ground_y(0.0, 0.0), 0.0) - to_pos), to_pos)
	var times := PackedFloat64Array()
	var elapsed := 0.0
	var t := Time.get_ticks_usec()
	while elapsed < AERIAL_RISE_S + AERIAL_HOLD_S:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - t) / 1e6
		t = now
		times.append(dt)
		elapsed += dt
		cam.global_transform = from.interpolate_with(to, smoothstep(0.0, 1.0, minf(elapsed / AERIAL_RISE_S, 1.0)))
	cam.set_process(true)
	return times


## {frames, seconds, min_fps, low1_fps, avg_fps, slow} of frame times (1 %-low: mean fps of the
## slowest 1 % of frames; slow: frames longer than 1/60 s).
static func fps_stats(times: PackedFloat64Array) -> Dictionary:
	var sorted := Array(times)
	sorted.sort()
	var total := 0.0
	for dt: float in sorted:
		total += dt
	var worst := maxi(1, ceili(sorted.size() * 0.01))
	var worst_total := 0.0
	var slow := 0
	for dt: float in sorted:
		if dt > 1.0 / 60.0:
			slow += 1
	for k in worst:
		worst_total += sorted[sorted.size() - 1 - k]
	return {
		"frames": sorted.size(), "seconds": total,
		"min_fps": 1.0 / sorted[sorted.size() - 1], "low1_fps": worst / worst_total,
		"avg_fps": sorted.size() / total, "slow": slow,
	}


func _report(legs: Dictionary) -> String:
	var all := PackedFloat64Array()
	var size := get_viewport().get_visible_rect().size
	var lines := ["Replica walk %s, %dx%d, %s" % [site.manifest.get("name", ""), size.x, size.y,
			RenderingServer.get_video_adapter_name()], "",
			"| Leg | Frames | Seconds | Min fps | 1 %-low fps | Avg fps | Frames < 60 fps |",
			"|---|---:|---:|---:|---:|---:|---:|"]
	for leg: String in legs:
		all.append_array(legs[leg])
		lines.append(_row(leg, legs[leg]))
	lines.append(_row("**whole walk**", all))
	var text := "\n".join(lines)
	print(text)
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open(dir.path_join("replica_perf_%s_%s.md" % [site.manifest.get("name", ""), stamp]), FileAccess.WRITE)
	if file:
		file.store_string(text + "\n")
	return text


static func _row(leg: String, times: PackedFloat64Array) -> String:
	var s := fps_stats(times)
	return "| %s | %d | %.1f | %.0f | %.0f | %.0f | %d |" % [leg, s.frames, s.seconds, s.min_fps, s.low1_fps, s.avg_fps, s.slow]


## Screenshots at the walk's spawn, tor-side point and the aerial view.
func capture_views() -> void:
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var pts := walk_points()
	var site_name: String = site.manifest.get("name", "site")
	_hold_player(true)
	var views := {"spawn": [pts[0], pts[1] - pts[0]], "tor": [pts[pts.size() - 1], pts[pts.size() - 1] - pts[pts.size() - 2]]}
	for v: String in views:
		_stand(views[v][0], views[v][1])
		site.follow_camera.snap()
		site.grass.fill_now()
		await _shot(dir.path_join("replica_%s_%s.png" % [site_name, v]))
	var p := pts[pts.size() - 1]
	var cam := site.follow_camera
	cam.set_process(false)
	var pos := Vector3(p.x, site.ground_y(p.x, p.y) + AERIAL_RISE_M, p.y)
	cam.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, site.ground_y(0.0, 0.0), 0.0) - pos), pos)
	await _shot(dir.path_join("replica_%s_aerial.png" % site_name))
	cam.set_process(true)
	_hold_player(false)
	site.reset_scene()


func _shot(path: String) -> void:
	for _f in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
