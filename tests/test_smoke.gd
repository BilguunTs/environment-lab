extends "res://tests/case.gd"


func test_scene_starts_in_gameplay_view(pg) -> void:
	check_eq(pg.get_param("view"), "Gameplay", "starting view")
	check_eq(pg.get_state().size(), pg.PARAM_ORDER.size(), "get_state covers PARAM_ORDER")


func test_reset_restores_a_changed_param(pg) -> void:
	pg.set_param("sun_glow", 0.9)
	pg.reset_scene()
	check_near(pg.get_param("sun_glow"), 0.15, 0.001, "sun_glow after reset")


func test_window_check_skips_when_headless(_pg) -> void:
	if not needs_window():
		return
	check(true, "running with a window")


func test_playground_player_unchanged(pg) -> void:
	check(pg.player.can_sprint, "playground player sprints")
	check(pg.player.lantern, "playground player keeps her lantern")
	check_eq(pg.player.walk_speed, 3.5, "playground walk speed")
