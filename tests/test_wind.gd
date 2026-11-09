extends "res://tests/case.gd"
## Wind has a direction (a compass angle) and a shared gust field that scrolls with it.


func test_compass_convention(_pg) -> void:
	check(Wind.vector_for(0.0).is_equal_approx(Vector2(0, -1)), "0° blows toward -Z")
	check(Wind.vector_for(90.0).is_equal_approx(Vector2(1, 0)), "90° blows toward +X")
	check(Wind.vector_for(53.13).distance_to(Vector2(0.8, -0.6)) < 0.001, "default = old WIND_DIR")


func test_direction_param_is_state(pg) -> void:
	var i: int = pg.PARAM_ORDER.find("wind_direction")
	check_eq(i, pg.PARAM_ORDER.find("wind") + 1, "wind_direction right after wind")
	check_near(pg.get_param("wind_direction"), 53.13, 0.01, "default direction")
	pg.set_param("wind_direction", 90.0)
	# (RenderingServer.global_shader_parameter_get is editor-only and errors in a running game.)
	check(pg.wind.vector().is_equal_approx(Vector2(1, 0)), "Wind node follows the param")
	pg.reset_scene()
	check_near(pg.get_param("wind_direction"), 53.13, 0.01, "reset restores direction")


func test_old_preset_keeps_default_direction(pg) -> void:
	pg.set_param("wind_direction", 200.0)
	pg.apply_preset("Wide Reveal")  # has no wind_direction key
	check_near(pg.get_param("wind_direction"), 53.13, 0.01, "missing key falls back to default")


func test_motes_and_mist_follow_direction(pg) -> void:
	pg.set_param("wind", 1.0)
	pg.set_param("wind_direction", 90.0)
	var gravity: Vector3 = pg.motes.process_material.gravity
	check_near(gravity.x, pg.MOTE_DRIFT, 0.001, "motes pushed toward +X")
	check_near(gravity.z, 0.0, 0.001, "no Z push at 90°")
	var before: Vector3 = pg.mist.material.get_shader_parameter("offset")
	await frames(10)
	var after: Vector3 = pg.mist.material.get_shader_parameter("offset")
	check(after.x < before.x, "mist noise scrolls with the wind (offset decreases along +X)")
	check_near(after.z, before.z, 0.0001, "mist doesn't drift in Z at 90°")


func test_gust_offset_has_no_jump(pg) -> void:
	# Ten minutes of default wind, then a 1° turn: the gust pattern at a sample point must move by
	# a hair, not by whole noise cells (the old offset grew along past directions without bound).
	pg.set_param("wind", 0.6)
	for i in 600:
		pg.wind._process(1.0)
	var sample := Vector2(30.0, -25.0)
	var q0: Vector2 = Wind.pattern_coord(sample, pg.wind.vector(), pg.wind.phase)
	pg.set_param("wind_direction", pg.get_param("wind_direction") + 1.0)
	var q1: Vector2 = Wind.pattern_coord(sample, pg.wind.vector(), pg.wind.phase)
	check(q0.distance_to(q1) < 0.1, "1° turn moves the gust pattern < 0.1 noise cell (moved %.3f)" % q0.distance_to(q1))


func test_gust_phase_advance(pg) -> void:
	pg.wind.strength = 0.5
	pg.wind.phase = 10.0
	pg.wind._process(0.1)
	check_near(pg.wind.phase, 10.0 + 0.5 * Wind.GUST_SPEED * 0.1, 0.00001, "phase advances strength * GUST_SPEED * delta")
	# Near the wrap the phase rebases by PHASE_PERIOD; the pattern doesn't notice (the noise is
	# periodic along the wind with exactly that period).
	pg.wind.phase = Wind.PHASE_PERIOD - 0.1
	pg.wind._process(0.1)
	check(pg.wind.phase >= 0.0 and pg.wind.phase < Wind.PHASE_PERIOD, "phase wraps into [0, PHASE_PERIOD)")
	check_near(pg.wind.phase, 0.1, 0.0001, "phase rebased by the period")
	var cells_per_period := Wind.PHASE_PERIOD / Wind.GUST_CELL_ALONG
	check_near(cells_per_period, roundf(cells_per_period), 0.0001, "period is a whole number of cells")


func test_no_hardcoded_wind_dir(pg) -> void:
	check(not pg.get_script().get_script_constant_map().has("WIND_DIR"), "WIND_DIR constant removed")
	var src := FileAccess.get_file_as_string("res://assets/materials/flat_color.gdshader")
	check(not src.contains("WIND_DIR"), "flat_color uses wind_direction")
	check(src.contains("wind.gdshaderinc"), "flat_color shares the gust include")
