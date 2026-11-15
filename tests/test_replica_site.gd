extends "res://tests/case.gd"
## The Sumber replica site (scenes/replica/sumber.tscn): every size and position comes from
## data/sites/sumber/build/ (Python pipeline). The tests read the build files themselves, so the
## scene is checked against the data, not against its own copy of it.

const SCENE := "res://scenes/replica/sumber.tscn"
const SITE := "res://data/sites/sumber"
const SEED := 20261111
const SAMPLES := 20

var _manifest: Dictionary
var _core := PackedFloat32Array()


## The build outputs (.r32, manifest.json, scatter.json) are gitignored: a fresh clone has none
## until `fetch` + `build` run (docs/TERRAIN_REPLICA.md), and the tests that read them skip.
func before_each(_site) -> void:
	var build := ProjectSettings.globalize_path(SITE).path_join("build")
	if not FileAccess.file_exists(build.path_join("manifest.json")):
		return
	_manifest = JSON.parse_string(FileAccess.get_file_as_string(build.path_join("manifest.json")))
	if _core.is_empty():
		_core = FileAccess.get_file_as_bytes(build.path_join("core.r32")).to_float32_array()


## Usage: `if not needs_build(): return` (like needs_window()).
func needs_build() -> bool:
	if _manifest.is_empty():
		skipped = "no %s/build/manifest.json: run `python -I -m replica fetch` + `build` (docs/TERRAIN_REPLICA.md)" % SITE.trim_prefix("res://")
		return false
	return true


func test_heights_match_manifest(site) -> void:
	if not needs_build():
		return
	var n: int = _manifest.core.n
	var base: float = _manifest.base_elevation
	check_eq(_core.size(), n * n, "core.r32 has n x n samples")
	var rng := _rng()
	var space: PhysicsDirectSpaceState3D = site.get_world_3d().direct_space_state
	for k in SAMPLES:
		var i := rng.randi_range(0, n - 1)
		var j := rng.randi_range(0, n - 1)
		var x: float = _manifest.core.origin_x + j * _manifest.core.step_m
		var z: float = _manifest.core.origin_z + i * _manifest.core.step_m
		var want := _core[i * n + j] - base
		_near(site.ground_y(x, z), want, 0.05, "ground_y at sample (%d, %d)" % [i, j])
		# The walkable collision is the same surface, also between samples.
		var px := x + rng.randf_range(0.0, 0.99)
		var pz := z + rng.randf_range(0.0, 0.99)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(px, 2000.0, pz), Vector3(px, -2000.0, pz), 2))
		check(not hit.is_empty(), "ground collision under (%.1f, %.1f)" % [px, pz])
		if not hit.is_empty():
			_near(hit.position.y, site.ground_y(px, pz), 0.05, "collision = ground_y at (%.2f, %.2f)" % [px, pz])


func test_nw_peak_position(site) -> void:
	if not needs_build():
		return
	var n: int = _manifest.core.n
	var best := 0
	for k in _core.size():
		if _core[k] > _core[best]:
			best = k
	var x: float = _manifest.core.origin_x + (best % n) * _manifest.core.step_m
	var z: float = _manifest.core.origin_z + (best / n) * _manifest.core.step_m
	check(x < 0.0 and z < 0.0, "highest core sample at x < 0, z < 0 (NW); got (%.0f, %.0f)" % [x, z])
	_near(site.ground_y(x, z), _core[best] - float(_manifest.base_elevation), 0.05, "the replica's peak is there")


func test_rock_sizes_exact(site) -> void:
	if not needs_build():
		return
	var rocks := _rocks().filter(func(r: Dictionary) -> bool: return r.kind == "boulder")
	check_eq(site.rock_count(), _rocks().size(), "one rock per rocks_placed.json entry")
	var rng := _rng()
	for k in SAMPLES:
		var r: Dictionary = rocks[rng.randi_range(0, rocks.size() - 1)]
		var node := site.rock_node(r.id) as MeshInstance3D
		check(node != null, "rock %s has a node" % r.id)
		if node == null:
			continue
		var box: AABB = node.global_transform * node.mesh.get_aabb()
		# From the data (rocks_placed.json + core.r32), not from the loader: the top is the ground
		# under the centre + height (rock_top_y), the base the lowest sample under the footprint
		# grown by one diagonal step (rock_base_y).
		var top := _bilinear(r.x, r.z) + float(r.height)
		var base := _footprint_min(r.x, r.z, r.length, r.width, r.yaw_deg)
		var yaw := deg_to_rad(r.yaw_deg)
		var c := absf(sin(yaw))
		var s := absf(cos(yaw))
		var want := Vector2(c * r.length + s * r.width, s * r.length + c * r.width)
		_near(box.size.x, want.x, 0.02 * want.x + 0.005, "rock %s AABB x" % r.id)
		_near(box.size.z, want.y, 0.02 * want.y + 0.005, "rock %s AABB z" % r.id)
		_near(box.end.y, top, 0.05, "rock %s top = ground at centre + height" % r.id)
		_near(box.position.y, base, 0.05, "rock %s base = lowest ground under its footprint" % r.id)
		_near(box.get_center().x, r.x, 0.05, "rock %s x" % r.id)
		_near(box.get_center().z, r.z, 0.05, "rock %s z" % r.id)
		# The long axis runs along the yaw (clockwise from north = -Z), at its measured length.
		var long_axis: Vector3 = node.global_basis.x
		_near(long_axis.length(), r.length, 0.02 * r.length, "rock %s length along its long axis" % r.id)
		var along := absf(long_axis.normalized().dot(Vector3(sin(yaw), 0.0, -cos(yaw))))
		check(along > 0.999, "rock %s long axis follows yaw %.1f (dot %.4f)" % [r.id, r.yaw_deg, along])


func test_rock_base_not_floating(site) -> void:
	if not needs_build():
		return
	var boulders := _rocks().filter(func(r: Dictionary) -> bool: return r.kind == "boulder")
	var rng := _rng()
	for k in SAMPLES:
		var r: Dictionary = boulders[rng.randi_range(0, boulders.size() - 1)]
		var box: AABB = site.rock_aabb(r.id)
		for corner in _corners(r.x, r.z, r.length, r.width, r.yaw_deg):
			var g: float = site.ground_y(corner.x, corner.y)
			check(box.position.y <= g + 0.05, "rock %s base %.2f under its corner ground %.2f" % [r.id, box.position.y, g])
	# Masses are packed fill pieces (scatter fill_*): a piece standing on the ground (y = 0)
	# reaches below its own footprint corners; a stacked one (y > 0) rests on the top of a piece
	# beneath it whose footprint holds its centre (Ruling 22).
	var doc := _scatter()
	var rows: Array = doc.rows
	var fill := [doc.types.find("fill_round"), doc.types.find("fill_slab")]
	var fill_rows: Array[int] = []
	for k in rows.size():
		if int(rows[k][0]) in fill:
			fill_rows.append(k)
	var standing := 0
	var stacked := 0
	while standing < SAMPLES or stacked < SAMPLES:
		var row_index := fill_rows[rng.randi_range(0, fill_rows.size() - 1)]
		var row: Array = rows[row_index]
		var box := _unit_box(site.scatter_transform(row_index))
		if float(row[3]) <= 0.0:
			if standing >= SAMPLES:
				continue
			standing += 1
			for corner in _corners(row[1], row[2], row[5], row[7], row[4]):
				var g: float = site.ground_y(corner.x, corner.y)
				check(box.position.y <= g + 0.05, "fill row %d base %.2f under corner ground %.2f" % [row_index, box.position.y, g])
			continue
		if stacked >= SAMPLES:
			continue
		stacked += 1
		var rests := false
		for other in fill_rows:
			if other == row_index:
				continue
			var o: Array = rows[other]
			if absf(float(o[1]) - float(row[1])) > 5.0 or absf(float(o[2]) - float(row[2])) > 5.0:
				continue
			var below: Transform3D = site.scatter_transform(other)
			var top := below.origin.y + float(o[6])
			if absf(top - box.position.y) > 0.05:
				continue
			var local := below.affine_inverse() * Vector3(row[1], below.origin.y, row[2])
			if absf(local.x) <= 0.5 and absf(local.z) <= 0.5:
				rests = true
				break
		check(rests, "stacked fill row %d (base %.2f) rests on a piece below" % [row_index, box.position.y])


func test_scatter_sizes_and_counts(site) -> void:
	if not needs_build():
		return
	var doc := _scatter()
	var counts: Dictionary = _manifest.scatter.counts
	for type: String in counts:
		check_eq(site.scatter_count(type), int(counts[type]), "%s instances drawn" % type)
	var rows: Array = doc.rows
	var rng := _rng()
	for k in SAMPLES * 5:
		var row_index := rng.randi_range(0, rows.size() - 1)
		var row: Array = rows[row_index]
		var xf: Transform3D = site.scatter_transform(row_index)
		var yaw := deg_to_rad(row[4])
		_near(xf.basis.x.length(), row[5], 0.01, "row %d length" % row_index)
		_near(xf.basis.y.length(), row[6], 0.01, "row %d height" % row_index)
		_near(xf.basis.z.length(), row[7], 0.01, "row %d width" % row_index)
		check(absf(xf.basis.x.normalized().dot(Vector3(sin(yaw), 0.0, -cos(yaw)))) > 0.999, "row %d yaw" % row_index)
		_near(xf.origin.x, row[1], 0.01, "row %d x" % row_index)
		_near(xf.origin.z, row[2], 0.01, "row %d z" % row_index)
		var drawn: Transform3D = site.scatter_drawn_transform(row_index)
		var types: Array = doc.types
		# The headless renderer keeps no MultiMesh data (instances read back as identity), and the
		# kit tree is fitted into the unit box by its bounds.
		if DisplayServer.get_name() != "headless" and types[int(row[0])] != "tree":
			var off := drawn.origin.distance_to(xf.origin)
			for axis in 3:
				off = maxf(off, (drawn.basis[axis] - xf.basis[axis]).length())
			check(off < 0.01, "row %d drawn where it is placed (off by %.4f)" % [row_index, off])


func test_gers_at_measured_positions(site) -> void:
	if not needs_build():
		return
	var gers: Array = site.ger_nodes()
	var structures: Array = _manifest.structures.filter(func(s: Dictionary) -> bool: return s.type == "ger")
	check_eq(gers.size(), structures.size(), "one ger per measured structure")
	for k in mini(gers.size(), structures.size()):
		var s: Dictionary = structures[k]
		var node: Node3D = gers[k]
		check(Vector2(node.global_position.x, node.global_position.z).distance_to(Vector2(s.x, s.z)) <= 0.5,
				"ger %d at its measured (%.2f, %.2f), got (%.2f, %.2f)" % [k, s.x, s.z, node.global_position.x, node.global_position.z])
		var box := _world_aabb(node)
		_near(box.size.x, s.diameter_m, 0.1, "ger %d footprint x" % k)
		_near(box.size.z, s.diameter_m, 0.1, "ger %d footprint z" % k)
		# Height: the crown reference the shadow calibration uses (site.json calibration
		# height_m 2.4, plan Task 9 ger.glb), whatever the diameter.
		_near(box.size.y, _ger_height(), 0.05, "ger %d height (diameter %.2f)" % [k, s.diameter_m])
		check(box.position.y <= site.ground_y(s.x, s.z) + 0.05, "ger %d stands on the ground" % k)


func test_ring_present(site) -> void:
	if not needs_build():
		return
	var ring: Dictionary = _manifest.ring
	var data := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(SITE).path_join("build/ring.r32")).to_float32_array()
	var n: int = ring.n
	var j := 600
	var i := (n - 1) / 2
	var x: float = ring.origin_x + j * ring.step_m
	var z: float = ring.origin_z + i * ring.step_m
	var y: float = site.ground_y(8000.0, 0.0)
	check(is_finite(y), "ground_y(8000, 0) has a value")
	_near(site.ground_y(x, z), data[i * n + j] - float(_manifest.base_elevation), 0.05, "ring sample at (%.0f, %.0f)" % [x, z])
	var space: PhysicsDirectSpaceState3D = site.get_world_3d().direct_space_state
	# Off the sample lines: Godot Physics' HeightMapShape3D ray test misses rays that run exactly
	# along a cell edge (the player's capsule is a shape cast and is not affected).
	var off := Vector2(x + 7.3, z + 11.9)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(off.x, 3000.0, off.y), Vector3(off.x, -3000.0, off.y), 2))
	check(not hit.is_empty(), "ring has walkable ground at %s" % off)
	if not hit.is_empty():
		_near(hit.position.y, site.ground_y(off.x, off.y), 0.05, "ring collision height")
	# The ring's drawn surface stays under the core (its shader also discards the core square;
	# the outermost ring cell straddling the core edge is left to that), so the core is what shows.
	var rng := _rng()
	for k in 200:
		var p := Vector2(rng.randf_range(-989.0, 989.0), rng.randf_range(-989.0, 989.0))
		var under: float = site.terrain.ring_surface_at(p.x, p.y)
		if under >= site.ground_y(p.x, p.y):
			check(false, "ring surface %.2f under the core %.2f at %s" % [under, site.ground_y(p.x, p.y), p])
			break


func test_core_ring_seam(site) -> void:
	if not needs_build():
		return
	# All four sides of the core edge and the corners, out to the first ring line and beyond:
	# the walkable collision is ground_y, and ground_y has no step across the core edge.
	var half: float = -float(_manifest.core.origin_x)
	var space: PhysicsDirectSpaceState3D = site.get_world_3d().direct_space_state
	var rng := _rng()
	var points: Array[Vector2] = []
	for k in 60:
		var along := rng.randf_range(-half - 30.0, half + 30.0)
		var out := rng.randf_range(half, half + 30.0)
		var side := k % 4
		points.append([Vector2(out, along), Vector2(-out, along), Vector2(along, out), Vector2(along, -out)][side])
	for k in 20:
		points.append(Vector2(rng.randf_range(half, half + 30.0) * (1 if k % 2 else -1),
				rng.randf_range(half, half + 30.0) * (1 if k % 4 < 2 else -1)))
	var misses := 0
	for p in points:
		var g: float = site.ground_y(p.x, p.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 3000.0, p.y), Vector3(p.x, -3000.0, p.y), 2))
		if hit.is_empty():
			misses += 1
			continue
		_near(hit.position.y, g, 0.05, "seam collision = ground_y at %s" % p)
	check(misses == 0, "seam collision under every point (%d misses)" % misses)
	# No step across the core edge: just inside vs just outside, on every side.
	for k in 80:
		var along := rng.randf_range(-half, half)
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var edge := d * half + Vector2(d.y, d.x).abs() * along
			var inside := edge - d * 0.01
			var outside := edge + d * 0.01
			var jump := absf(site.ground_y(outside.x, outside.y) - site.ground_y(inside.x, inside.y))
			if jump > 0.05:
				check(false, "step of %.2f m across the core edge at %s" % [jump, edge])
				return


func test_player_spawns_on_ground(site) -> void:
	if not needs_build():
		return
	await physics_frames(30)
	var player: CharacterBody3D = site.player
	var ger: Dictionary = _manifest.structures[0]
	var p := player.global_position
	check(Vector2(p.x, p.z).distance_to(Vector2(ger.x, ger.z + 15.0)) < 0.5, "spawn 15 m south of the first ger, got %s" % p)
	check(player.is_on_floor(), "player stands on the floor")
	_near(p.y, site.ground_y(p.x, p.z), 0.1, "player feet on the ground")


func test_fill_collision_only_over_1_5_m(site) -> void:
	if not needs_build():
		return
	# Plan Task 10 / Ruling 34: fill pieces > 1.5 m on some axis collide; smaller ones (gap
	# blocks among collided pieces) do not.
	var doc := _scatter()
	var rows: Array = doc.rows
	var fill := [doc.types.find("fill_round"), doc.types.find("fill_slab")]
	var small := -1
	var large := -1
	var solid := 0
	for k in rows.size():
		var row: Array = rows[k]
		if not int(row[0]) in fill:
			continue
		var big := maxf(float(row[5]), maxf(float(row[6]), float(row[7]))) > 1.5
		if big:
			solid += 1
		if big and large < 0:
			large = k
		elif not big and small < 0:
			small = k
	check(small >= 0 and large >= 0, "the site has fill pieces on both sides of 1.5 m")
	if small < 0 or large < 0:
		return
	check(not site.scatter_has_collision(small), "fill row %d (max side %.2f m) has no collision" % [small, _max_side(rows[small])])
	check(site.scatter_has_collision(large), "fill row %d (max side %.2f m) has collision" % [large, _max_side(rows[large])])
	var xf: Transform3D = site.scatter_collision_transform(large)
	var placed: Transform3D = site.scatter_transform(large)
	check(xf.origin.distance_to(placed.origin) < 0.01, "its hull sits where the piece is placed")
	var boulders := _rocks().filter(func(r: Dictionary) -> bool: return r.kind == "boulder" or not r.outline)
	check_eq(site.rock_shape_count(), solid + boulders.size(), "rock shapes = boulders + fill pieces over 1.5 m")
	# A ray onto the large piece's top hits it.
	var top := placed.origin + Vector3(0.0, float(rows[large][6]) * 0.5, 0.0)
	var hit: Dictionary = site.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(top.x, top.y + 50.0, top.z), Vector3(top.x, top.y - 50.0, top.z), 1))
	check(not hit.is_empty(), "a ray onto fill row %d hits rock collision" % large)


func test_manifest_without_optional_entry_names_it(_site) -> void:
	# export_site writes grass_density / rocks_placed only when given them; the builder says so
	# by name instead of crashing on the missing key.
	var dir := "user://replica_manifest_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir).path_join("build"))
	var f := FileAccess.open(ProjectSettings.globalize_path(dir).path_join("build/manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"core": {"n": 3, "step_m": 1.0, "origin_x": -1.0, "origin_z": -1.0, "file": "core.r32"},
			"base_elevation": 0.0, "rocks_placed": {"file": "rocks_placed.json"}}))
	f.close()
	expect_error("has no \"grass_density\" entry")
	var other := ReplicaSite.new()
	other.site_dir = dir
	other.build()
	check(other.terrain == null, "nothing is built from an incomplete manifest")
	other.free()


func test_missing_build_names_file_and_command(_site) -> void:
	expect_error("-I -m replica build data/sites/no_such_site")
	var other := ReplicaSite.new()
	other.site_dir = "res://data/sites/no_such_site"
	other.build()
	check(other.terrain == null, "nothing is built without the build files")
	other.free()


func test_capture_topdown_marks_rocks(site) -> void:
	if not needs_build() or not needs_window():
		return
	var boulders := _rocks().filter(func(r: Dictionary) -> bool: return r.kind == "boulder" and r.width >= 5.0)
	var r: Dictionary = boulders[0]
	var capture := ReplicaCapture.new()
	capture.site = site
	site.add_child(capture)
	capture.enter_capture_mode()
	var image: Image = await capture.render_topdown(Vector2(r.x, r.z), 40.0, 80)
	capture.exit_capture_mode()
	# North up, east right, 0.5 m/px: the boulder's centre is the centre pixel.
	var c := image.get_pixel(40, 40)
	check(c.is_equal_approx(ReplicaCapture.ROCK_COLOR), "boulder %s drawn in the capture colour at its centre, got %s" % [r.id, c])
	# The ground is unlit: every non-rock pixel is a palette colour or a blend of two.
	var magenta := 0
	for y in 80:
		for x in 80:
			if image.get_pixel(x, y).is_equal_approx(ReplicaCapture.ROCK_COLOR):
				magenta += 1
	check(magenta < 80 * 80, "ground is visible around the boulder")
	var node := site.rock_node(r.id) as MeshInstance3D
	check(node.material_override == null, "capture mode restored the rock material")
	check(site.grass.visible, "capture mode restored the grass")
	capture.queue_free()


func test_fps_stats(_site) -> void:
	var times := PackedFloat64Array()
	for k in 99:
		times.append(0.004)
	times.append(0.02)
	var st := ReplicaCapture.fps_stats(times)
	check_eq(st.frames, 100, "frames")
	_near(st.min_fps, 50.0, 0.01, "min fps = slowest frame")
	_near(st.low1_fps, 50.0, 0.01, "1 %-low = mean of the slowest 1 % (one frame here)")
	_near(st.avg_fps, 100.0 / (99 * 0.004 + 0.02), 0.01, "average fps = frames / seconds")
	check_eq(st.slow, 1, "one frame under 60 fps")


# --- helpers ------------------------------------------------------------------------------------

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _rocks() -> Array:
	var path := ProjectSettings.globalize_path(SITE).path_join("build/rocks_placed.json")
	return JSON.parse_string(FileAccess.get_file_as_string(path)).rocks


static var _scatter_doc: Dictionary


func _scatter() -> Dictionary:
	if _scatter_doc.is_empty():
		var path := ProjectSettings.globalize_path(SITE).path_join("build/scatter.json")
		_scatter_doc = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _scatter_doc


func _max_side(row: Array) -> float:
	return maxf(float(row[5]), maxf(float(row[6]), float(row[7])))


## The ger crown height the site's shadow calibration measures against (site.json).
func _ger_height() -> float:
	var site_json: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			ProjectSettings.globalize_path(SITE).path_join("site.json")))
	return float(site_json.calibration[0].height_m)


## Ground at (x, z) the way the pipeline's rock_top_y reads it: bilinear between core samples.
func _bilinear(x: float, z: float) -> float:
	var n: int = _manifest.core.n
	var u := clampf((x - _manifest.core.origin_x) / _manifest.core.step_m, 0.0, n - 1.0001)
	var v := clampf((z - _manifest.core.origin_z) / _manifest.core.step_m, 0.0, n - 1.0001)
	var j := int(u)
	var i := int(v)
	var a := lerpf(_core[i * n + j], _core[i * n + j + 1], u - j)
	var b := lerpf(_core[(i + 1) * n + j], _core[(i + 1) * n + j + 1], u - j)
	return lerpf(a, b, v - i) - float(_manifest.base_elevation)


## Lowest core sample (ground y) in the l x w footprint grown by one diagonal step, long axis yaw
## degrees clockwise from north: the pipeline's heightmap.rock_base_y for a boulder, from core.r32.
func _footprint_min(x: float, z: float, l: float, w: float, yaw_deg: float) -> float:
	var n: int = _manifest.core.n
	var step: float = _manifest.core.step_m
	var x0: float = _manifest.core.origin_x
	var z0: float = _manifest.core.origin_z
	var yaw := deg_to_rad(yaw_deg)
	var a := Vector2(sin(yaw), -cos(yaw))
	var b := Vector2(cos(yaw), sin(yaw))
	var hl := l * 0.5 + step * sqrt(2.0)
	var hw := w * 0.5 + step * sqrt(2.0)
	var reach := hl + hw
	var lo := INF
	for i in range(maxi(0, floori((z - reach - z0) / step)), mini(n - 1, ceili((z + reach - z0) / step)) + 1):
		for j in range(maxi(0, floori((x - reach - x0) / step)), mini(n - 1, ceili((x + reach - x0) / step)) + 1):
			var d := Vector2(x0 + j * step - x, z0 + i * step - z)
			if absf(d.dot(a)) <= hl and absf(d.dot(b)) <= hw:
				lo = minf(lo, _core[i * n + j])
	return lo - float(_manifest.base_elevation)


## Four corners (x, z) of an l x w footprint whose long axis points yaw degrees clockwise from north.
func _corners(x: float, z: float, l: float, w: float, yaw_deg: float) -> Array[Vector2]:
	var yaw := deg_to_rad(yaw_deg)
	var a := Vector2(sin(yaw), -cos(yaw)) * l * 0.5
	var b := Vector2(cos(yaw), sin(yaw)) * w * 0.5
	var c := Vector2(x, z)
	return [c + a + b, c + a - b, c - a + b, c - a - b]


func _unit_box(xf: Transform3D) -> AABB:
	return xf * AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)


func _world_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## check_near that also fails on NAN / INF (check_near alone lets NAN through).
func _near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if not is_finite(actual):
		failures.append("%s: expected %.3f, got %s" % [message, expected, actual])
		return
	check_near(actual, expected, tolerance, message)
