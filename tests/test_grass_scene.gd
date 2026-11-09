extends "res://tests/case.gd"
## The starter meadow in the playground: loaded from file, off the path and clearing, on the mounds.


func test_playground_has_grass(pg) -> void:
	await frames(2)
	check(pg.grass.mask != null and pg.grass.mask.resource_path.ends_with("playground_grass.res"), "mask loaded from file")
	check(pg.grass.blade_count() > 10000, "the starter field is populated")


func test_grass_visible_param(pg) -> void:
	check_eq(pg.PARAM_ORDER.find("grass_visible"), pg.PARAM_ORDER.find("props_visible") + 1, "param order")
	pg.set_param("grass_visible", false)
	check(not pg.grass.visible, "toggle hides the field")
	pg.reset_scene()
	check(pg.grass.visible, "default is on")


func test_path_is_clear_of_grass(pg) -> void:
	# The shipped mask is hand-painted; this checks the starter generator's own output.
	var gen: GDScript = load("res://tools/make_starter_grass.gd")
	var mask: Image = gen.call("build_mask", pg)
	var corner: Vector2 = gen.FIELD_CENTRE - gen.FIELD_EXTENT * 0.5
	for node_name in ["Path", "SideTrail"]:
		var pts: PackedVector2Array = pg.get_node(node_name).get_centerline_world()
		for p in pts:
			var t: Vector2 = (p - corner) / gen.TEXEL
			var x := clampi(floori(t.x), 0, mask.get_width() - 1)
			var y := clampi(floori(t.y), 0, mask.get_height() - 1)
			check_near(mask.get_pixel(x, y).r, 0.0, 0.01, "starter generator leaves the %s centreline clear" % node_name)


func test_clearing_is_clear_of_grass(pg) -> void:
	var c: Vector3 = pg.get_node("Clearing").global_position
	for off in [Vector2.ZERO, Vector2(6, 0), Vector2(0, -7), Vector2(-5, 5)]:
		check_near(pg.grass.sample(Vector2(c.x, c.z) + off).x, 0.0, 0.01, "no grass in the clearing")


func test_grass_on_mounds(pg) -> void:
	await frames(2)
	var m: Node3D = pg.get_node("Terrain/Mound1")
	check(pg.grass.ground_height_at(Vector2(m.global_position.x, m.global_position.z)) > 0.2, "cache sees the mound")
