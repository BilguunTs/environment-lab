extends "res://tests/case.gd"
## Heavens call summit sequence (Task 7): she slows to a stop at the summit, the fog parts, the
## wind surges and the clap sounds, a separate camera pulls back until she is tiny, the screen
## fades to black and the title shows; only then does a key quit.

const SCENE := "res://scenes/levels/heavens_call.tscn"

var _on_finished := Callable()
var _saved_mask := -1


## Every test here runs with the quit hook off, so a stray real key on the title can't quit the
## runner; it is restored, and the finished handler disconnected, afterwards.
func before_each(lv) -> void:
	lv.summit.quit_on_finish = false


func after_each(lv) -> void:
	lv.summit.quit_on_finish = true
	if _on_finished.is_valid() and lv.summit.finished.is_connected(_on_finished):
		lv.summit.finished.disconnect(_on_finished)
	lv.summit.set_process(true)
	lv.summit.set_physics_process(true)
	if _saved_mask >= 0:
		lv.follow_cam.collision_mask = _saved_mask
		_saved_mask = -1


func test_reaching_summit_starts_sequence(lv) -> void:
	lv.player.global_position = lv.trail.point_at(0.985)
	await frames(3)
	check(lv.summit.phase != SummitSequence.Phase.IDLE, "sequence started at the summit")
	check(not lv.player.input_enabled, "player control taken away")


func test_title_text(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.TITLE)
	await seconds(2.2)
	var title: Label = lv.get_node("UI/Title")
	check_eq(title.text, "Heavens call", "exact title")
	check(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "centred")
	check(lv.get_node("UI/Fade").color.a > 0.99, "behind the title is black")


func test_input_ignored_until_title(lv) -> void:
	var quit := [false]
	_on_finished = func() -> void: quit[0] = true
	lv.summit.finished.connect(_on_finished)
	lv.summit.quit_on_finish = false  # test hook (also set in before_each)
	lv.summit.skip_to(SummitSequence.Phase.REVEAL)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	check(not quit[0], "keys during the reveal do nothing")
	lv.summit.skip_to(SummitSequence.Phase.TITLE)
	await seconds(2.2)
	Input.parse_input_event(key)
	await frames(2)
	check(quit[0], "a key after the title finishes")
	var release := InputEventKey.new()
	release.keycode = KEY_SPACE
	release.pressed = false
	Input.parse_input_event(release)  # leave no key held for later tests
	await frames(1)


## The ending on its natural path, stepped by hand (the sequence's own processing is frozen so
## real frames don't double-step): the phases come in order, the clap sounds in REVEAL, the fade
## reaches black, and input stays unarmed through FADE and the title's fade-in. Only then does a
## mouse button finish.
func test_natural_path_to_title(lv) -> void:
	var finished := [0]
	_on_finished = func() -> void: finished[0] += 1
	lv.summit.finished.connect(_on_finished)
	_freeze(lv)
	lv.summit.start()
	var seen: Array = [lv.summit.phase]
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	var sent_in_fade := false
	var sent_in_title := false
	var clap_after_reveal := false
	var armed_early := false
	var title_ticks := 0
	for i in 400:  # 100 s of sequence time at most
		var before: int = lv.summit.phase
		lv.summit._process(0.25)
		var ph: int = lv.summit.phase
		if ph != seen[-1]:
			seen.append(ph)
			if before == SummitSequence.Phase.REVEAL:
				clap_after_reveal = lv.summit.clap_played
		if ph == SummitSequence.Phase.FADE and not sent_in_fade:
			sent_in_fade = true
			lv.summit._input(key)
		if ph == SummitSequence.Phase.TITLE:
			title_ticks += 1
			if lv.summit.input_armed:
				break
			armed_early = armed_early or lv.summit.input_armed
			if title_ticks == 3:  # 0.75 s in: the title is still fading in
				sent_in_title = true
				lv.summit._input(key)
	check_eq(seen, [SummitSequence.Phase.SLOWING, SummitSequence.Phase.REVEAL, SummitSequence.Phase.PULLBACK, SummitSequence.Phase.FADE, SummitSequence.Phase.TITLE], "phases in order")
	check(clap_after_reveal, "the clap sounded during REVEAL")
	check(sent_in_fade and sent_in_title, "keys were sent in FADE and in the title fade-in")
	check(lv.get_node("UI/Fade").color.a > 0.99, "black once at the title")
	check(not armed_early, "not armed at the start of TITLE")
	check(title_ticks >= int(SummitSequence.TITLE_FADE_SECONDS / 0.25), "armed only after the title fade-in (%d ticks)" % title_ticks)
	check(lv.summit.input_armed, "armed once the title is fully shown")
	check_eq(lv.get_node("UI/Title").modulate.a, 1.0, "title fully shown when armed")
	check_eq(finished[0], 0, "keys during FADE and the title fade-in did not finish")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	lv.summit._input(click)
	check_eq(finished[0], 1, "a mouse button after arming finishes")
	check(not lv.summit.input_armed, "disarmed after finishing")


func test_pullback_makes_her_tiny(lv) -> void:
	if not needs_window(): return
	lv.summit.skip_to(SummitSequence.Phase.PULLBACK)
	await seconds(12.5)
	var cam: Camera3D = lv.get_viewport().get_camera_3d()
	var top: Vector2 = cam.unproject_position(lv.player.global_position + Vector3.UP * 1.7)
	var foot: Vector2 = cam.unproject_position(lv.player.global_position)
	check(absf(foot.y - top.y) < lv.get_viewport().get_visible_rect().size.y * 0.03, "tiny silhouette")


## She stays in the frame at the end of the pull-back (a tiny figure, not lost off-screen).
func test_pullback_keeps_her_in_frame(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.FADE)
	await frames(2)
	var cam: Camera3D = lv.get_viewport().get_camera_3d()
	check(cam == lv.summit.summit_camera, "the summit camera holds the end frame")
	var her: Vector3 = lv.player.global_position + Vector3.UP * 0.85
	check(not cam.is_position_behind(her), "she is in front of the camera")
	var p := cam.unproject_position(her)
	var size: Vector2 = lv.get_viewport().get_visible_rect().size
	check(Rect2(Vector2.ZERO, size).grow(-size.y * 0.05).has_point(p), "she is inside the frame")
	check(cam.global_position.y - lv.player.global_position.y >= 40.0, "high above her")


## Her movement eases out over SLOWING: not snapped to a stop, but stopped by its end. Keys held
## during the sequence don't move her.
func test_slowing_is_gentle(lv) -> void:
	lv.player.global_position = lv.trail.point_at(0.9) + Vector3.UP
	await physics_frames(2)
	lv.player.velocity = Vector3(0.0, 0.0, -2.0)
	lv.summit.start()
	Input.action_press("move_forward")
	await seconds(0.5)
	var mid := Vector2(lv.player.velocity.x, lv.player.velocity.z).length()
	check(mid > 0.8 and mid < 2.0, "still easing to a stop after 0.5 s, got %.2f" % mid)
	await seconds(SummitSequence.SLOWING_SECONDS)
	Input.action_release("move_forward")
	var end := Vector2(lv.player.velocity.x, lv.player.velocity.z).length()
	check(end < 0.05, "stopped by the end of SLOWING, got %.2f" % end)
	var yaw: float = lv.player.get_node("Model").rotation.y
	check(absf(angle_difference(yaw, PI)) < 0.05, "she faces the vista (-Z)")


## The reveal opens slowly from 0, with the clap 2 s in and the wind surging on top of the mood.
func test_reveal_opens_slowly_with_clap_and_surge(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.REVEAL)
	await frames(2)
	check(lv.vista.reveal < 0.02, "reveal starts closed")
	check(not lv.summit.clap_played, "no clap at the start")
	await seconds(1.0)
	check(lv.vista.reveal > 0.0 and lv.vista.reveal < 0.1, "opening slowly after 1 s, got %.3f" % lv.vista.reveal)
	await seconds(1.3)
	check(lv.summit.clap_played, "the clap sounds 2 s in")
	lv.summit.skip_to(SummitSequence.Phase.PULLBACK)
	await frames(2)
	check_eq(lv.vista.reveal, 1.0, "fully open at the pull-back")
	check_near(lv.soundscape.wind_strong_loop.volume_db, 0.0, 0.05, "wind_strong surged to 1")
	check(lv.soundscape.wind_loop.volume_db < -1.0, "the mood still drives the other loops")


func test_reset_returns_to_gameplay(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.TITLE)
	await seconds(0.5)
	lv.reset_scene()
	await frames(2)
	check_eq(lv.summit.phase, SummitSequence.Phase.IDLE, "sequence idle")
	check(not lv.summit.input_armed, "input disarmed")
	check(lv.get_viewport().get_camera_3d() == lv.follow_cam, "gameplay camera current")
	check_eq(lv.vista.reveal, 0.0, "vista closed")
	check(lv.player.input_enabled, "control given back")
	check(lv.follow_cam.input_enabled, "camera orbit given back")
	check_eq(lv.mood.wind_surge, 0.0, "no surge")
	check_eq(lv.get_node("UI/Title").modulate.a, 0.0, "title hidden")
	check(lv.get_node("UI/Fade").color.a > 0.5, "fading in from black again")


## Anti-goal "a reveal that pops": the far world (ridges, steppe, mist sea, cloud deck) fades in
## with the reveal's first quarter instead of appearing the moment it starts drawing.
func test_far_world_fades_in(lv) -> void:
	lv.vista.reveal = 0.01
	check(lv.vista.far.visible, "drawn once revealing")
	check(lv.vista.far_fade() < 0.02, "but barely there at reveal 0.01 (%.3f)" % lv.vista.far_fade())
	lv.vista.reveal = 0.5
	check_eq(lv.vista.far_fade(), 1.0, "fully in by half the reveal")
	lv.vista.reveal = 0.0


## skip_to() lands on a phase's start state from any other phase, backwards included.
func test_skip_to_from_any_phase(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.TITLE)
	await frames(2)
	lv.summit.skip_to(SummitSequence.Phase.REVEAL)
	await frames(2)
	check(lv.get_viewport().get_camera_3d() == lv.summit.summit_camera, "REVEAL: summit camera")
	check(lv.get_node("UI/Fade").color.a < 0.01, "REVEAL: no black")
	check(lv.vista.reveal < 0.02, "REVEAL: closed")
	lv.summit.skip_to(SummitSequence.Phase.FADE)
	await frames(2)
	check(lv.get_viewport().get_camera_3d() == lv.summit.summit_camera, "FADE: summit camera")
	lv.summit.skip_to(SummitSequence.Phase.SLOWING)
	await frames(2)
	check_eq(lv.summit.phase, SummitSequence.Phase.SLOWING, "back to SLOWING")
	check(lv.get_viewport().get_camera_3d() == lv.follow_cam, "SLOWING: gameplay camera")
	check_eq(lv.vista.reveal, 0.0, "SLOWING: closed")
	check(not lv.player.input_enabled, "SLOWING: no control")


## skip_to(IDLE) is a full reset: the vista closed, fading in from black, and the sequence not
## restarted by her still standing at the summit.
func test_skip_to_idle_is_a_reset(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.TITLE)
	await frames(2)
	lv.summit.skip_to(SummitSequence.Phase.IDLE)
	await physics_frames(3)
	check_eq(lv.summit.phase, SummitSequence.Phase.IDLE, "idle and staying idle")
	check_eq(lv.vista.reveal, 0.0, "vista closed")
	check(lv.furthest_progress < 0.1, "back at the foot")
	check(lv.get_node("UI/Fade").color.a > 0.5, "fading in from black")


## Review Focus 4: a right-drag orbit or a wheel zoom during the sequence never moves the camera
## off the sequence's own pose (the sequence is frozen so its pose holds still to compare).
func test_camera_ignores_mouse_during_sequence(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.SLOWING)
	await seconds(1.0)
	_freeze(lv)
	# Collision off for the comparison: its slow ease-out after a hit would move the camera on its
	# own. Mouse orbit and zoom are what is under test.
	_saved_mask = lv.follow_cam.collision_mask
	lv.follow_cam.collision_mask = 0
	await _settle_camera(lv)
	await frames(10)
	check(lv.get_viewport().get_camera_3d() == lv.follow_cam, "SLOWING: gameplay camera")
	var before: Transform3D = lv.get_viewport().get_camera_3d().global_transform
	await _drag_and_wheel()
	var after: Transform3D = lv.get_viewport().get_camera_3d().global_transform
	check(before.is_equal_approx(after), "SLOWING: camera unmoved by drag and wheel (moved %.4f m, orbit %.2f/%.2f/%.2f)" % [before.origin.distance_to(after.origin), lv.follow_cam.yaw_deg, lv.follow_cam.pitch_deg, lv.follow_cam.distance])
	lv.summit.set_process(true)
	lv.summit.set_physics_process(true)
	lv.summit.skip_to(SummitSequence.Phase.REVEAL)
	await seconds(0.5)
	_freeze(lv)
	await frames(2)
	before = lv.get_viewport().get_camera_3d().global_transform
	var orbit := Vector3(lv.follow_cam.yaw_deg, lv.follow_cam.pitch_deg, lv.follow_cam.distance)
	await _drag_and_wheel()
	after = lv.get_viewport().get_camera_3d().global_transform
	check(before.is_equal_approx(after), "REVEAL: camera unmoved by drag and wheel")
	var orbit_after := Vector3(lv.follow_cam.yaw_deg, lv.follow_cam.pitch_deg, lv.follow_cam.distance)
	check(orbit.is_equal_approx(orbit_after), "REVEAL: the gameplay orbit untouched too")


## Ruling 12: the reveal is watched as it happens. The cinematic camera rises over the rim
## (it looks nearly level across the plateau to the mist sea) with her still clear: over 4% of
## the frame height (about 5.5% at the 16 / 24 m pose), well above the pull-back end's 1.8%.
func test_reveal_rises_over_the_rim(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.PULLBACK)  # PULLBACK starts at the rise's end pose
	lv.summit.set_process(false)
	await frames(2)
	var cam: Camera3D = lv.get_viewport().get_camera_3d()
	var feet: Vector3 = lv.player.global_position
	check(cam.global_position.y - feet.y >= 10.0, "risen at least 10 m above her")
	var top: Vector2 = cam.unproject_position(feet + Vector3.UP * 1.7)
	var foot: Vector2 = cam.unproject_position(feet)
	var size: Vector2 = lv.get_viewport().get_visible_rect().size
	check(absf(foot.y - top.y) > size.y * 0.04, "she is still clear, not yet tiny (%.1f%%)" % (100.0 * absf(foot.y - top.y) / size.y))
	check(Rect2(Vector2.ZERO, size).grow(-size.y * 0.05).has_point(foot), "she is in frame")


## reset_scene() cuts off a clap or footstep still sounding.
func test_reset_stops_one_shots(lv) -> void:
	var thunder: AudioStreamPlayer = lv.soundscape.get_node("Thunder")
	thunder.stream = AudioStreamGenerator.new()
	thunder.play()
	await frames(1)
	lv.reset_scene()
	check(not lv.soundscape.thunder_playing(), "thunder stopped on reset")
	thunder.stream = null


func _freeze(lv) -> void:
	lv.summit.set_process(false)
	lv.summit.set_physics_process(false)


func _drag_and_wheel() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await frames(1)
	for i in 3:
		var drag := InputEventMouseMotion.new()
		drag.button_mask = MOUSE_BUTTON_MASK_RIGHT
		drag.relative = Vector2(60.0, 25.0)
		Input.parse_input_event(drag)
		await frames(1)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await frames(1)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	Input.parse_input_event(release)
	await frames(3)


## Waits (up to 3 s) until the current camera has held still for 5 frames in a row.
func _settle_camera(lv) -> void:
	var last: Vector3 = lv.get_viewport().get_camera_3d().global_position
	var still := 0
	for i in 180:
		await frames(1)
		var now: Vector3 = lv.get_viewport().get_camera_3d().global_position
		still = still + 1 if now.distance_to(last) < 0.00001 else 0
		if still >= 5:
			return
		last = now
