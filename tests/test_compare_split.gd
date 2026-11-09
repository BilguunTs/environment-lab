extends "res://tests/case.gd"


func before_each(pg) -> void:
	pg.compare.clear()
	if pg.compare.split:
		await pg.compare.toggle_split()


func after_each(pg) -> void:
	if pg.compare.split:
		await pg.compare.toggle_split()
	pg.compare.clear()


func test_split_needs_a_pin(pg) -> void:
	await pg.compare.toggle_split()
	check(not pg.compare.split, "split refused without A")


func test_split_captures_a_frozen_image(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	pg.set_param("sun_glow", 0.9)
	await pg.compare.toggle_split()
	var image: Image = pg.compare.a_image
	check(image != null and image.get_width() == int(pg.get_viewport().get_visible_rect().size.x), "A image is a full frame")
	check_near(pg.get_param("sun_glow"), 0.9, 0.001, "live state is B again after capturing A")
	check(pg.panel.visible, "panel restored after the capture")
	check(pg.compare.view.active(), "split overlay is drawing")
	check_eq(pg.compare.view.size, pg.get_viewport().get_visible_rect().size, "split overlay covers the whole frame")


func test_value_view_change_recaptures_a(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	await pg.compare.toggle_split()
	var first: Image = pg.compare.a_image
	pg.set_param("value_mode", "Notan")
	await seconds(Compare.RECAPTURE_DELAY + 0.5)  # debounced: renders once the change rests
	check(pg.compare.a_image != first, "A re-rendered after the value view changed")


func test_flip_ignored_while_capturing(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	pg.set_param("sun_glow", 0.9)
	pg.compare.toggle_split()  # not awaited: the capture is in flight
	pg.compare.show_a(true)
	check(not pg.compare.showing_a, "flip waits for the capture")
	await frames(Compare.SETTLE_FRAMES + 5)
	check_near(pg.get_param("sun_glow"), 0.9, 0.001, "scene ends on B")


func test_scout_leaves_split(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	await pg.compare.toggle_split()
	pg.set_param("view", "Scout")
	check(not pg.compare.split, "Scout turns split off")
	pg.set_param("view", "Gameplay")


func test_screenshot_still_hides_overlays(pg) -> void:
	if not needs_window():
		return
	var path: String = await pg.take_screenshot("overlay_check")
	check(FileAccess.file_exists(path), "screenshot written")
	check(pg.panel.visible, "panel back after the screenshot")
	DirAccess.remove_absolute(path)
