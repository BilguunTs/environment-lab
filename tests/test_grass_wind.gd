extends "res://tests/case.gd"
## Grass reacts to the shared wind: strength and direction change the rendered field.

var f: GrassField


func before_each(pg) -> void:
	pg.player.visible = false
	var cam: Camera3D = pg.get_viewport().get_camera_3d()
	var forward := -cam.global_basis.z
	var flat := Vector2(forward.x, forward.z)
	flat = flat.normalized() if flat.length() > 0.001 else Vector2(0, -1)
	var centre := Vector2(cam.global_position.x, cam.global_position.z) + flat * 8.0
	f = GrassField.new()
	f.extent = Vector2(16, 16)
	f.position = Vector3(centre.x, 0.0, centre.y)
	pg.add_child(f)
	await frames(2)
	f.ensure_mask()
	f.paint(f.global_position, 20.0, GrassField.PaintMode.DENSITY, 1.0, 1.0, 0.0)
	f.rebuild()


func after_each(pg) -> void:
	pg.player.visible = true
	if is_instance_valid(f):
		f.get_parent().remove_child(f)
		f.free()


func test_wind_moves_the_grass(pg) -> void:
	if not needs_window():
		return
	pg.set_param("wind", 0.0)
	var calm := await _grab(pg)
	pg.set_param("wind", 2.0)
	var windy := await _grab(pg)
	check(_mean_abs_diff(calm, windy) > 0.01, "strong wind visibly changes the field")


func test_direction_moves_the_grass(pg) -> void:
	if not needs_window():
		return
	pg.set_param("wind", 1.5)
	pg.set_param("wind_direction", 0.0)
	var a := await _grab(pg)
	pg.set_param("wind_direction", 180.0)
	var b := await _grab(pg)
	check(_mean_abs_diff(a, b) > 0.01, "opposite directions lean the field differently")


func test_shader_exposes_wind_and_fade_uniforms(_pg) -> void:
	var src := FileAccess.get_file_as_string("res://assets/shaders/grass.gdshader")
	check(src.contains("wind.gdshaderinc"), "grass shares the gust include")
	for name in ["bend", "flutter", "highlight", "fade_start", "fade_end"]:
		check(src.contains("uniform float " + name), "uniform " + name)
	var mat: ShaderMaterial = f.chunk_instance(Vector2i(0, 0)).material_override
	check_near(mat.get_shader_parameter("fade_start"), f.fade_start, 0.001, "fade_start passed through")
	check_near(mat.get_shader_parameter("fade_end"), f.fade_end, 0.001, "fade_end passed through")


## The middle third of the frame horizontally, over the lower part where the field sits (the
## sky and trees above it do not move).
func _grab(pg) -> Image:
	var image: Image = await pg.compare.render_state(pg.get_state())
	var s := image.get_size()
	return image.get_region(Rect2i(s.x / 3, s.y / 2, s.x / 3, s.y * 2 / 5))


func _mean_abs_diff(a: Image, b: Image) -> float:
	var total := 0.0
	var n := a.get_width() * a.get_height()
	for y in a.get_height():
		for x in a.get_width():
			total += absf(ValueProbe.luminance(a.get_pixel(x, y)) - ValueProbe.luminance(b.get_pixel(x, y)))
	return total / maxf(n, 1.0)
