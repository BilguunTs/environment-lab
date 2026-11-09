extends "res://tests/case.gd"


var _clipboard := ""


func before_each(pg) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):  # the headless display server has none
		_clipboard = DisplayServer.clipboard_get()
	pg.compare.clear()


func after_each(_pg) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(_clipboard)


func test_log_row_format(_pg) -> void:
	var lines: Array[String] = ["a: 1 → 2", "b: on → off"]
	var row := Compare.log_row(lines)
	check(row.begins_with("| 20"), "starts with the date")
	check(row.ends_with("| | a: 1 → 2, b: on → off | | |"), "only the Changed column is filled")


func test_save_pair_without_a_does_nothing(pg) -> void:
	var path: String = await pg.compare.save_pair()
	check_eq(path, "", "no file without A")


func test_save_pair_writes_side_by_side_png(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	pg.set_param("sun_glow", 0.6)
	var path: String = await pg.compare.save_pair()
	check(FileAccess.file_exists(path), "PNG written")
	var image := Image.load_from_file(path)
	var frame: Vector2 = pg.get_viewport().get_visible_rect().size
	check_eq(image.get_width(), int(frame.x) * 2, "two frames wide")
	check_eq(image.get_height(), int(frame.y) + Compare.STRIP_LINE * 3, "frame plus text strip (header, 1 diff line, padding)")
	check_near(pg.get_param("sun_glow"), 0.6, 0.001, "live state is B afterwards")
	check(DisplayServer.clipboard_get().contains("sun_glow: 0.15 → 0.6"), "log row copied")
	check(pg.panel.visible, "panel restored")
	DirAccess.remove_absolute(path)
