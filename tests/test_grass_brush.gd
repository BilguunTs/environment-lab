extends "res://tests/case.gd"
## GrassBrush: dab spacing within a stroke, the before/after pair a stroke hands to undo, and the
## brush ray against the ground layer. Each test builds its own 16 m field on the Ground plane in
## front of the start (the same fixture as test_grass_field.gd).

var f: GrassField


func before_each(pg) -> void:
	f = GrassField.new()
	f.extent = Vector2(16, 16)
	f.position = Vector3(0, 0, -6)
	pg.add_child(f)
	await frames(2)
	f.ensure_mask()


func after_each(_pg) -> void:
	if is_instance_valid(f):
		f.get_parent().remove_child(f)
		f.free()


func test_dabs_respect_spacing(pg) -> void:
	var b := GrassBrush.new()
	b.strength = 0.2
	b.begin(f)
	b.dab(f.global_position)
	var once := f.sample(Vector2(0, -6)).x
	b.dab(f.global_position + Vector3(0.1, 0, 0))  # closer than radius * 0.25
	check_near(f.sample(Vector2(0, -6)).x, once, 0.001, "a dab too close to the last is skipped")


func test_stroke_undo_restores_mask_and_blades(pg) -> void:
	var b := GrassBrush.new()
	b.strength = 1.0
	b.begin(f)
	for x in range(-4, 5, 2):
		b.dab(f.global_position + Vector3(x, 0, 0))
	var pair := b.end()
	check(pair[0].get_data() != pair[1].get_data(), "stroke changed the mask")
	check(f.blade_count() > 0, "stroke grew blades")
	f.set_mask_data(pair[0])
	check_eq(f.mask.get_data(), pair[0].get_data(), "undo restores the exact mask")
	check_eq(f.blade_count(), 0, "undo removes the blades")


func test_ray_to_ground(pg) -> void:
	var hit = GrassBrush.ray_to_ground(f, Vector3(0, 10, -6), Vector3.DOWN)
	check(hit is Vector3 and absf(hit.y) < 0.05, "brush ray lands on the Ground plane")
	check(GrassBrush.ray_to_ground(f, Vector3(0, 10, -6), Vector3.UP) == null, "ray into the sky misses")


func test_shared_mask_needs_fork(_pg) -> void:
	var scene := "res://scenes/level.tscn"
	var own := Image.create(4, 4, false, Image.FORMAT_RG8)
	check(not GrassBrush.mask_needs_fork(own, scene, []), "a fresh unsaved mask is saved, not forked")
	own.take_over_path("res://scenes/level_grass.res")
	check(not GrassBrush.mask_needs_fork(own, scene, []), "the scene's own mask file is painted in place")
	check(GrassBrush.mask_needs_fork(own, scene, [own]), "a duplicate (Ctrl+D) holding the same mask forks")
	var other := Image.create(4, 4, false, Image.FORMAT_RG8)
	check(not GrassBrush.mask_needs_fork(own, scene, [other]), "a sibling with its own mask doesn't force a fork")
	var pasted := Image.create(4, 4, false, Image.FORMAT_RG8)
	pasted.take_over_path("res://scenes/playground_grass_test_only.res")
	check(GrassBrush.mask_needs_fork(pasted, scene, []), "a mask pasted from another scene forks")
	check(not GrassBrush.mask_needs_fork(pasted, "res://somewhere/playground.tscn", []),
			"a <scene>_grass file in another folder still belongs to the scene")
	var embedded := Image.create(4, 4, false, Image.FORMAT_RG8)
	embedded.take_over_path("res://scenes/other.tscn::Image_abc")
	check(GrassBrush.mask_needs_fork(embedded, scene, []), "a mask embedded in another scene forks")
	check(not GrassBrush.mask_needs_fork(embedded, "res://scenes/other.tscn", []), "embedded in this scene: no fork")
	# The playground's starter meadow lives in assets/grass/, not next to the scene.
	var pg_mask: Image = load("res://assets/grass/playground_grass.res")
	check(not GrassBrush.mask_needs_fork(pg_mask, "res://scenes/playground.tscn", []), "playground Grass keeps playground_grass.res")
	check(not GrassBrush.mask_needs_fork(null, scene, []), "no mask, nothing to fork")
