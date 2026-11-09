extends "res://tests/case.gd"
## Regression tests for the minors deferred from the Stage 8 review.


func before_each(pg) -> void:
	pg.compare.clear()
	if pg.compare.split:
		await pg.compare.toggle_split()


func after_each(pg) -> void:
	if pg.compare.split:
		await pg.compare.toggle_split()
	pg.compare.clear()
	pg.set_param("light_gizmos", false)


func _vertex_count(mesh: Mesh) -> int:
	if mesh.get_surface_count() == 0:
		return 0
	var arrays := mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


# Minor 1: the camera is sampled before the blink, so a move during it is noticed afterwards.
func test_player_move_during_capture_recaptures(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	await pg.compare.toggle_split()
	await seconds(Compare.RECAPTURE_DELAY + 0.3)  # settle: nothing pending
	var start: Vector3 = pg.player.global_position
	var captures := [0]
	var counter := func() -> void: captures[0] += 1
	pg.compare.changed.connect(counter)
	pg.compare.capture_a()  # not awaited
	await frames(1)
	pg.player.global_position += Vector3(2, 0, 0)
	await frames(Compare.SETTLE_FRAMES + 5)
	await seconds(Compare.RECAPTURE_DELAY + 0.3)
	pg.compare.changed.disconnect(counter)
	pg.player.global_position = start
	check(captures[0] >= 2, "a move during the capture triggers another one (got %d)" % captures[0])


# Minor 5: gizmos are an overlay, and follow lights that come and go.
func test_gizmos_hidden_in_captures(pg) -> void:
	pg.set_param("light_gizmos", true)
	pg.hide_overlays()
	check(not pg.light_gizmos.visible, "hidden while capturing")
	pg.restore_overlays()
	check(pg.light_gizmos.visible, "back after the capture")


func test_gizmos_pick_up_new_lights(pg) -> void:
	if not needs_window():
		return
	pg.set_param("light_gizmos", true)
	await frames(2)
	var before := _vertex_count(pg.light_gizmos.mesh)
	var light := OmniLight3D.new()
	pg.add_child(light)
	await frames(2)
	var added := _vertex_count(pg.light_gizmos.mesh)
	light.free()
	await frames(2)
	var removed := _vertex_count(pg.light_gizmos.mesh)
	check(added > before, "new light drawn (%d -> %d)" % [before, added])
	check_eq(removed, before, "removed light no longer drawn")


# Minor 6: a failed save is reported, not swallowed.
func test_save_sheet_reports_failure(_pg) -> void:
	expect_error("Can't save")
	var result := Compare.save_sheet(Image.create(4, 4, false, Image.FORMAT_RGB8), "user://no/such/dir/x.png")
	check(result.contains("Could not save"), "failure message, got '%s'" % result)


# Minor 2: the perf readout sits under the view HUD, whatever its height.
func test_perf_readout_clears_view_hud(pg) -> void:
	var start: String = pg.get_param("view")
	pg.set_param("perf_hud", true)
	for view_name in pg.view_names():
		pg.set_param("view", view_name)
		await frames(2)
		var hud_bottom: float = pg._hud.get_global_rect().end.y
		var perf_top: float = pg.perf_hud.get_global_rect().position.y
		check(perf_top >= hud_bottom, "%s: readout at %.0f, HUD ends at %.0f" % [view_name, perf_top, hud_bottom])
	pg.set_param("perf_hud", false)
	pg.set_param("view", start)


# Minor 3: an unreadable user presets file is shown, not silently treated as empty.
const BAD_PATH := "user://bad_presets.cfg"
const TYPED_PATH := "user://test_typed_presets.cfg"


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_unreadable_presets_file_is_reported(pg) -> void:
	expect_error("ConfigFile parse")
	var f := FileAccess.open(BAD_PATH, FileAccess.WRITE)
	f.store_string("[broken")
	f.close()
	var original: String = pg.preset_path
	pg.preset_path = BAD_PATH
	pg.panel.refresh_presets()
	var text: String = pg.panel.status_text()
	pg.preset_path = original
	pg.panel.refresh_presets()
	_remove(BAD_PATH)
	check(text.contains("Can't read"), "status says the file can't be read, got '%s'" % text)


# Minor 4: a hand-edited, wrong-typed value is skipped with a note.
func test_wrong_typed_preset_value_is_skipped(pg) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("Bad", "wind_direction", "north")
	cfg.set_value("Bad", "wind", 1.2)
	cfg.save(TYPED_PATH)
	var original: String = pg.preset_path
	pg.preset_path = TYPED_PATH
	pg.reset_scene()
	pg.apply_preset("Bad")
	var direction: float = pg.get_param("wind_direction")
	var wind: float = pg.get_param("wind")
	var text: String = pg.panel.status_text()
	pg.preset_path = original
	pg.reset_scene()
	_remove(TYPED_PATH)
	check_near(direction, 53.13, 0.01, "direction unchanged")
	check_near(wind, 1.2, 0.001, "the valid value applied")
	check(text.contains("Skipped wind_direction"), "status notes the skip, got '%s'" % text)
