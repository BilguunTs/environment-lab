extends "res://tests/case.gd"
## GrassField: painting the RG mask, the ground height cache, reproducible blades per chunk and
## partial rebuilds. Each test builds its own 16 m field on the Ground plane in front of the start.

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


func test_paint_density_reaches_target_at_centre(pg) -> void:
	var r := f.paint(f.global_position, 2.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	check(r.has_area(), "a changed rect is returned")
	check_near(f.sample(Vector2(0, -6)).x, 1.0, 0.01, "full strength reaches the target at the centre")
	check_near(f.sample(Vector2(3, -6)).x, 0.0, 0.01, "nothing outside the radius")


func test_erase_and_height_modes(pg) -> void:
	f.paint(f.global_position, 2.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.paint(f.global_position, 2.0, GrassField.PaintMode.HEIGHT, 0.0, 1.0)
	check_near(f.sample(Vector2(0, -6)).y, 0.0, 0.01, "height mode moves G only")
	check_near(f.sample(Vector2(0, -6)).x, 1.0, 0.01, "density untouched by height mode")
	f.paint(f.global_position, 2.0, GrassField.PaintMode.ERASE, 1.0, 1.0)
	check_near(f.sample(Vector2(0, -6)).x, 0.0, 0.01, "erase zeroes density")


func test_paint_clips_at_field_edge(pg) -> void:
	var r := f.paint(f.global_position + Vector3(8, 0, 0), 30.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	check(Rect2i(Vector2i.ZERO, f.mask_size()).encloses(r), "rect clipped to the mask")
	var off := f.paint(f.global_position + Vector3(100, 0, 0), 2.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	check(not off.has_area(), "painting fully off the field changes nothing")


func test_blades_follow_density_and_are_reproducible(pg) -> void:
	check_eq(f.blade_count(), 0, "empty mask = no blades")
	f.paint(f.global_position, 4.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild()
	var n := f.blade_count()
	check(n > 0, "painted area grows blades")
	f.rebuild()
	check_eq(f.blade_count(), n, "same mask + seed = same blades")
	var mm := f.chunk_instance(Vector2i(0, 0)).multimesh
	var t0 := mm.get_instance_transform(0)
	f.rebuild()
	check(f.chunk_instance(Vector2i(0, 0)).multimesh.get_instance_transform(0).is_equal_approx(t0), "same first blade")


func test_heights_follow_mask(pg) -> void:
	# Falloff 0: the whole disc is at full value. Height is painted wider than density so the
	# bilinear sample at the density disc's rim doesn't blend in the unpainted mid height.
	f.paint(f.global_position, 4.0, GrassField.PaintMode.DENSITY, 1.0, 1.0, 0.0)
	f.paint(f.global_position, 6.0, GrassField.PaintMode.HEIGHT, 1.0, 1.0, 0.0)
	f.rebuild()
	var mm := f.chunk_instance(Vector2i(0, 0)).multimesh
	for i in mini(mm.instance_count, 50):
		var h := mm.get_instance_transform(i).basis.y.length()
		check(h >= f.max_height * 0.84 and h <= f.max_height * 1.16, "tall paint = max_height ± jitter")


func test_no_blades_where_ground_missing(pg) -> void:
	# The Ground collider is an infinite WorldBoundaryShape3D, so moving off the 400 m plane still
	# hits it; ray against an unused layer as well, so nothing is ground here.
	f.position = Vector3(500, 0, 500)  # beyond the 400 m Ground plane
	f.ground_layer = 20
	f.refresh_ground()
	f.paint(f.global_position, 4.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild()
	check_eq(f.blade_count(), 0, "no ground hit = no blades")
	check(is_nan(f.ground_height_at(Vector2(500, 500))), "missing ground reads NAN")


func test_partial_rebuild_touches_only_affected_chunks(pg) -> void:
	f.extent = Vector2(48, 16)  # three chunks in X
	f.ensure_mask()
	f.paint(f.global_position + Vector3(-16, 0, 0), 3.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild()
	var far := f.chunk_instance(Vector2i(0, 0))
	check(far != null, "the first stroke grew the -X chunk")
	var r := f.paint(f.global_position + Vector3(16, 0, 0), 3.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild(r)
	check(f.chunk_instance(Vector2i(0, 0)) == far, "untouched chunk keeps its node")
