extends "res://tests/case.gd"

## Render-mode captures land here (not in screenshots/), overwritten each run.
const OUTPUT := "user://test_output"


func after_each(pg) -> void:
	pg.set_param("debug_draw", "Normal")


func test_render_mode_sets_viewport_debug_draw(pg) -> void:
	pg.set_param("debug_draw", "Wireframe")
	check_eq(pg.get_viewport().debug_draw, Viewport.DEBUG_DRAW_WIREFRAME, "wireframe")
	pg.set_param("debug_draw", "Normal")
	check_eq(pg.get_viewport().debug_draw, Viewport.DEBUG_DRAW_DISABLED, "back to normal")


func test_render_mode_is_not_scene_state(pg) -> void:
	pg.set_param("debug_draw", "Unshaded")
	check(not pg.get_state().has("debug_draw"), "debug views stay out of presets and A/B")
	pg.reset_scene()
	check_eq(pg.get_param("debug_draw"), "Unshaded", "Reset leaves the debug view alone")


func test_each_render_mode_looks_different(pg) -> void:
	if not needs_window():
		return
	pg.set_param("view", "Forest Gate")
	var means := {}
	for mode in pg.DEBUG_DRAWS:
		pg.set_param("debug_draw", mode)
		await frames(5)
		await RenderingServer.frame_post_draw
		var frame: Image = pg.get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(OUTPUT)
		frame.save_png(OUTPUT.path_join("debug_%s.png" % mode.to_lower()))  # for a human look
		frame.resize(64, 36)
		var total := 0.0
		for y in 36:
			for x in 64:
				var c := frame.get_pixel(x, y)
				total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		means[mode] = total / (64 * 36)
	var modes: Array = means.keys()
	for i in modes.size():
		for j in range(i + 1, modes.size()):
			check(absf(means[modes[i]] - means[modes[j]]) > 0.004, "%s and %s look different (%.3f vs %.3f)" % [modes[i], modes[j], means[modes[i]], means[modes[j]]])
