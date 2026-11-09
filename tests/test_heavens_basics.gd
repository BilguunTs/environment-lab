extends "res://tests/case.gd"
## Heavens call level basics: the girl, her camera and the fade-in.

const SCENE := "res://scenes/levels/heavens_call.tscn"


func test_girl_has_no_lantern(lv) -> void:
	check(not lv.player.get_node("Model/Lantern").visible, "lantern mesh hidden")
	check(not lv.player.get_node("Model/LanternLight").visible, "lantern light off")


func test_no_sprint_in_level(lv) -> void:
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await seconds(1.5)
	var v := Vector2(lv.player.velocity.x, lv.player.velocity.z).length()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check(v <= 2.05, "speed capped at walk 2.0 with sprint held")
	check(v >= 1.8, "she does walk at about 2 m/s")


func test_camera_pitch_limited(lv) -> void:
	lv.follow_cam.pitch_deg = 80.0
	check_near(lv.follow_cam.pitch_deg, 45.0, 0.01, "pitch clamped to max_pitch")


func test_fades_in_from_black(lv) -> void:
	var fade: ColorRect = lv.get_node("UI/Fade")
	lv.reset_scene()
	check(fade.color.a > 0.9, "starts black")
	await seconds(3.3)
	check(fade.color.a < 0.05, "faded in after 3 s")


func test_views_exist(lv) -> void:
	check(lv.view_names() == PackedStringArray(["foot", "debris", "eerie", "summit", "wide"]), "the five named views")
	for v in lv.view_names():
		lv.show_view(v)
		await frames(2)
		check(lv.player.is_inside_tree(), "show_view(%s) leaves the level running" % v)
	lv.show_view("reveal_early")
	await frames(2)
	check(lv.vista.reveal > 0.1 and lv.vista.reveal < 0.2, "reveal_early is at reveal ~0.15")
	lv.reset_scene()
