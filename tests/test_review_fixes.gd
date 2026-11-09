extends "res://tests/case.gd"
## Regression tests for the Stage 8 final-review findings.


func before_each(pg) -> void:
	pg.compare.clear()
	if pg.compare.split:
		await pg.compare.toggle_split()


func after_each(pg) -> void:
	if pg.compare.split:
		await pg.compare.toggle_split()
	pg.compare.clear()
	pg.set_typing(false)


func _key(pg, keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	pg._unhandled_input(event)


# Finding 1: camera height is smoothed, so A/B states must snap the camera.
func test_flip_cuts_the_camera_instead_of_gliding(pg) -> void:
	pg.compare.pin()
	pg.set_param("cam_height", 4.0)
	pg.follow_cam.snap()
	var b_position: Vector3 = pg.follow_cam.global_position
	pg.compare.show_a(true)
	check_near(b_position.y - pg.follow_cam.global_position.y, 2.6, 0.05, "A's camera height applies at once")
	pg.compare.show_a(false)
	check(pg.follow_cam.global_position.is_equal_approx(b_position), "B's camera is back at once")


func test_height_change_does_not_loop_recaptures(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	pg.set_param("cam_height", 4.0)
	pg.follow_cam.snap()
	await pg.compare.toggle_split()
	var captures := [0]
	pg.compare.changed.connect(func() -> void: captures[0] += 1)
	await seconds(2.5)
	check_eq(captures[0], 0, "split view settles instead of re-capturing every second")


# Finding 2: nested captures must not leave overlays hidden; hotkeys wait for a capture.
func test_overlay_hiding_is_reentrant(pg) -> void:
	pg.hide_overlays()
	pg.hide_overlays()
	pg.restore_overlays()
	check(not pg.panel.visible, "still hidden while the outer capture runs")
	pg.restore_overlays()
	check(pg.panel.visible, "panel back after the outer restore")
	check(pg._hud.visible, "HUD back after the outer restore")


func test_hotkeys_wait_for_a_capture(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	pg.set_param("sun_glow", 0.9)
	pg.compare.toggle_split()  # capture in flight: A is applied right now
	_key(pg, KEY_C, true)  # cycle view
	await frames(Compare.SETTLE_FRAMES + 5)
	check_eq(pg.get_param("view"), "Gameplay", "hotkeys are ignored during the blink")
	check_near(pg.get_param("sun_glow"), 0.9, 0.001, "scene ends on B")


# Finding 3: a release of X must never be lost.
func test_x_release_during_a_capture_is_kept(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	pg.set_param("sun_glow", 0.9)
	pg.compare.show_a(true)
	pg.compare.capture_a()  # not awaited: busy
	pg.compare.show_a(false)
	await frames(Compare.SETTLE_FRAMES + 5)
	check(not pg.compare.showing_a, "release honoured after the capture")
	check_near(pg.get_param("sun_glow"), 0.9, 0.001, "scene is B")


func test_typing_releases_a(pg) -> void:
	pg.compare.pin()
	pg.set_param("sun_glow", 0.9)
	pg.compare.show_a(true)
	pg.set_typing(true)
	check(not pg.compare.showing_a, "clicking into the name field drops A")
	check_near(pg.get_param("sun_glow"), 0.9, 0.001, "a preset saved now stores B")


# Finding 4: re-pinning in split view must refresh the A image.
func test_repin_in_split_recaptures(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	await pg.compare.toggle_split()
	var first: Image = pg.compare.a_image
	pg.set_param("sun_glow", 0.9)
	pg.compare.pin()
	await frames(Compare.SETTLE_FRAMES + 10)
	check(pg.compare.a_image != first, "new A rendered")


# Finding 5: value-view slider drags in split view are debounced, not one blink per tick.
func test_value_view_changes_are_debounced(pg) -> void:
	if not needs_window():
		return
	pg.compare.pin()
	await pg.compare.toggle_split()
	var first: Image = pg.compare.a_image
	pg.set_param("value_split", 0.5)
	await frames(3)
	check(not pg.compare.busy, "no capture starts in the middle of a drag")
	await seconds(Compare.RECAPTURE_DELAY + 0.5)
	check(pg.compare.a_image != first, "captured once the slider rests")


# Finding 6: typing a name must not move any camera.
func test_typing_does_not_orbit_or_fly(pg) -> void:
	var press := InputEventKey.new()
	press.keycode = KEY_Q
	press.physical_keycode = KEY_Q
	press.pressed = true
	var release: InputEventKey = press.duplicate()
	release.pressed = false
	var yaw: float = pg.follow_cam.yaw_deg
	Input.parse_input_event(press)
	await frames(5)
	check(not is_equal_approx(pg.follow_cam.yaw_deg, yaw), "sanity: Q orbits when not typing")
	pg.set_typing(true)
	yaw = pg.follow_cam.yaw_deg
	await frames(5)
	check(is_equal_approx(pg.follow_cam.yaw_deg, yaw), "Q doesn't orbit while typing")
	pg.set_param("view", "Scout")
	var scout_position: Vector3 = pg.scout_cam.global_position
	await frames(5)
	check(pg.scout_cam.global_position.is_equal_approx(scout_position), "Q doesn't fly the scout camera while typing")
	Input.parse_input_event(release)
	pg.set_param("view", "Gameplay")
	pg.follow_cam.yaw_deg = 0.0
