extends "res://tests/case.gd"


func before_each(pg) -> void:
	pg.compare.clear()


func test_fmt(_pg) -> void:
	check_eq(Compare.fmt(0.15), "0.15", "float")
	check_eq(Compare.fmt(842.0), "842", "large float")
	check_eq(Compare.fmt(60.0), "60", "whole number, no trailing .0")
	check_eq(Compare.fmt(0.004), "0.004", "small float")
	check_eq(Compare.fmt(0.0), "0", "zero")
	check_eq(Compare.fmt(true), "on", "bool")
	check_eq(Compare.fmt(Color(1, 0, 0)), "#ff0000", "colour")
	check_eq(Compare.fmt("Manual"), "Manual", "string")


func test_pin_then_change_gives_one_diff_line(pg) -> void:
	pg.compare.pin()
	check_eq(pg.compare.diff().size(), 0, "no diff right after pinning")
	pg.set_param("sun_glow", 0.6)
	check_eq(PackedStringArray(pg.compare.diff()), PackedStringArray(["sun_glow: 0.15 → 0.6"]), "one changed param")


func test_hold_x_shows_a_and_release_restores_b(pg) -> void:
	pg.compare.pin()
	pg.set_param("sun_glow", 0.6)
	pg.compare.show_a(true)
	check_near(pg.get_param("sun_glow"), 0.15, 0.001, "A is shown")
	check_eq(pg.compare.diff().size(), 1, "diff is still A vs B while A is shown")
	pg.compare.show_a(false)
	check_near(pg.get_param("sun_glow"), 0.6, 0.001, "B is back")


func test_view_and_value_view_are_not_compared(pg) -> void:
	pg.compare.pin()
	pg.set_param("value_mode", "Notan")
	pg.set_param("view", "Forest Gate")
	check_eq(pg.compare.diff().size(), 0, "camera and value view are shared")
	pg.compare.show_a(true)
	check_eq(pg.get_param("value_mode"), "Notan", "showing A keeps the value view")
	check_eq(pg.get_param("view"), "Forest Gate", "showing A keeps the camera")
	check_near(pg.get_param("cam_fov"), 50.0, 0.01, "showing A keeps this view's own lens")
	pg.compare.show_a(false)


func test_lens_is_compared_in_the_pinned_view(pg) -> void:
	pg.compare.pin()
	pg.set_param("cam_fov", 35.0)
	check_eq(PackedStringArray(pg.compare.diff()), PackedStringArray(["cam_fov: 60 → 35"]), "a lens change is an experiment variable")


func test_flip_needs_a_pin(pg) -> void:
	pg.compare.show_a(true)
	check(not pg.compare.showing_a, "nothing to show without A")


func test_pin_refused_in_scout(pg) -> void:
	pg.set_param("view", "Scout")
	pg.compare.pin()
	check(not pg.compare.has_a(), "pin refused in Scout")
	pg.set_param("view", "Gameplay")


func test_entering_scout_releases_a(pg) -> void:
	pg.compare.pin()
	pg.set_param("sun_glow", 0.6)
	pg.compare.show_a(true)
	pg.set_param("view", "Scout")
	check(not pg.compare.showing_a, "Scout leaves A")
	check_near(pg.get_param("sun_glow"), 0.6, 0.001, "scene is B")
	pg.set_param("view", "Gameplay")


func test_focus_loss_releases_a(pg) -> void:
	pg.compare.pin()
	pg.set_param("sun_glow", 0.6)
	pg.compare.show_a(true)
	pg.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not pg.compare.showing_a, "A released when the window loses focus")
	check_near(pg.get_param("sun_glow"), 0.6, 0.001, "scene is B")


func test_hud_tag(pg) -> void:
	check_eq(pg.compare.hud_tag(), "", "no tag without A")
	pg.compare.pin()
	check_eq(pg.compare.hud_tag(), "B · A pinned", "live = B")
	pg.compare.show_a(true)
	check_eq(pg.compare.hud_tag(), "SHOWING A", "holding X")
	pg.compare.show_a(false)
