extends "res://tests/case.gd"
## Heavens call soundscape: missing audio is silent, footstep kinds, the volume floor, the mood's
## volumes, thunder after a flash, and footsteps by distance walked.

const SCENE := "res://scenes/levels/heavens_call.tscn"


func test_missing_audio_is_silent(lv) -> void:
	check(Soundscape.load_stream("definitely_missing") == null, "missing file -> null, no error")
	lv.soundscape.play_thunder()
	lv.soundscape.play_thunder(true)
	lv.soundscape.step(true)
	lv.soundscape.set_volumes(1.0, 1.0, 1.0)
	check(true, "no engine errors with missing audio")  # the runner fails the test on any engine error
	for p in lv.soundscape.loop_players():
		check(p.playing == (p.stream != null), "a player plays exactly when it has a stream (missing file = silent)")


## The null-stream branches, driven with a name that has no file: nothing plays, nothing errors.
func test_missing_file_paths_stay_silent(lv) -> void:
	var sc: Soundscape = lv.soundscape
	sc.stop_one_shots()
	sc.play_thunder(false, "definitely_missing")
	sc.play_thunder(true, "definitely_missing")
	sc.step(true, "definitely_missing")
	sc.step(false, "definitely_missing")
	var loop := sc._make_loop("definitely_missing")
	check(loop.stream == null, "the loop has a null stream")
	check(not loop.playing, "the loop is not playing")
	loop.free()
	check(not sc.thunder_playing(), "no thunder sounding")
	check(sc.get_node("Thunder").stream == null or not sc.get_node("Thunder").playing, "roll player idle")
	check(not sc.get_node("Clap").playing, "clap player idle")
	var steps: AudioStreamPlayer3D = sc.get_node_or_null("Footsteps")
	if steps == null:
		steps = lv.player.get_node_or_null("Footsteps")
	check(steps != null and not steps.playing, "footstep voice idle")


## The clap has its own player: a distant roll after it doesn't cut it off.
func test_clap_survives_a_roll(lv) -> void:
	var clap: AudioStreamPlayer = lv.soundscape.get_node("Clap")
	clap.stream = AudioStreamGenerator.new()
	clap.play()
	lv.soundscape.play_thunder(false)
	check(clap.playing, "the clap keeps sounding when a roll starts")
	lv.soundscape.stop_one_shots()
	check(not clap.playing, "stop_one_shots stops the clap too")
	clap.stream = null


func test_footstep_kind_follows_ground(lv) -> void:
	lv.soundscape.step(true)
	check_eq(lv.soundscape.last_step_kind, "gravel", "on the trail = gravel")
	lv.soundscape.step(false)
	check_eq(lv.soundscape.last_step_kind, "rock", "off the trail = rock")


func test_volume_floor(lv) -> void:
	lv.soundscape.set_volumes(0.0, 0.0, 0.0)
	for p in lv.soundscape.loop_players():
		check(p.volume_db <= -60.0, "silent at 0")
	lv.soundscape.set_volumes(1.0, 1.0, 1.0)
	for p in lv.soundscape.loop_players():
		check_near(p.volume_db, 0.0, 0.001, "full at 1")


func test_mood_drives_volumes(lv) -> void:
	lv.furthest_progress = 0.0
	await frames(2)
	var wind_db: float = lv.soundscape.wind_loop.volume_db
	var eerie_db: float = lv.soundscape.ambience_eerie_loop.volume_db
	check_near(wind_db, linear_to_db(0.7), 0.1, "wind follows the first key")
	check(eerie_db <= -60.0, "no eerie ambience at the start")
	lv.furthest_progress = 0.6
	await frames(2)
	check(lv.soundscape.ambience_eerie_loop.volume_db > -30.0, "eerie ambience in the eerie stretch")


func test_four_distinct_steps_names(_lv) -> void:
	check_eq(Soundscape.step_names("gravel"), ["footstep_gravel_1", "footstep_gravel_2", "footstep_gravel_3", "footstep_gravel_4"], "gravel names")
	check_eq(Soundscape.step_names("rock").size(), 4, "rock names")


func test_thunder_follows_flash_and_resets(lv) -> void:
	lv.storm.flash()
	check_eq(lv.pending_thunder(), 1, "one thunder pending after a flash")
	lv.reset_scene()
	check_eq(lv.pending_thunder(), 0, "reset cancels pending thunder")
	lv.storm.flashed.emit(0.05)
	await frames(1)
	check_eq(lv.pending_thunder(), 1, "pending again")
	await seconds(0.3)
	check_eq(lv.pending_thunder(), 0, "thunder played")


func test_steps_by_distance_on_floor(lv) -> void:
	await seconds(1.0)  # settle on the ground
	check(lv.player.is_on_floor(), "grounded")
	var before: int = lv.step_count
	lv._count_stride(Vector3(0.9, 0.0, 0.0), true)
	check_eq(lv.step_count, before + 1, "0.9 m on the floor = one step")
	lv._count_stride(Vector3(0.4, 5.0, 0.0), true)
	check_eq(lv.step_count, before + 1, "vertical motion is ignored")
	lv._count_stride(Vector3(5.0, 0.0, 0.0), false)
	check_eq(lv.step_count, before + 1, "no steps in the air")
