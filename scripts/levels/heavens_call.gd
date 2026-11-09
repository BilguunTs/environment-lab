class_name HeavensCall
extends Node3D
## "Heavens call": a tired girl climbs a foggy mountain trail to a summit reveal. This root owns
## the level's state and its reset; the trail, mood, sound, vista and summit systems hook in here.

## Seconds the screen takes to fade in from black at the start.
const FADE_IN_SECONDS := 3.0
## She is put back on the trail when she falls this far below the stretch she is over.
const FALL_DEPTH := 15.0
## The named capture views: trail progress, or -1 for the end of PULLBACK.
const VIEWS := {"foot": 0.02, "debris": 0.42, "eerie": 0.72, "summit": 0.96, "wide": -1.0}
## Profile-only: REVEAL when the vista's `reveal` is about 0.15 (the far ridges fading in).
const REVEAL_EARLY := "reveal_early"
## Seconds into REVEAL at which the vista's reveal is 0.15 (ease_in_out(t / 8) = 0.15).
const REVEAL_EARLY_SECONDS := 1.99
const SETTLE_FRAMES := 30
const PROFILE_FRAMES := 120
## Metres walked on the floor per footstep (suits 2 m/s).
const STRIDE := 0.85

@onready var player: Player = $Player
@onready var follow_cam: FollowCamera = $GameplayCamera
@onready var wind: Wind = $Wind
@onready var trail: Trail = $Trail
@onready var terrain: MountainTerrain = $MountainTerrain
@onready var mood: MoodDirector = $MoodDirector
@onready var storm: Storm = $Storm
@onready var mist: FogVolume = $Mist
@onready var soundscape: Soundscape = $Soundscape
@onready var vista: Vista = $Vista
@onready var summit: SummitSequence = $SummitSequence
@onready var fade: ColorRect = $UI/Fade

## Furthest progress (0 = foot, 1 = summit) she has reached along the trail. It only ever
## increases, so walking back down or falling never undoes the mood.
var furthest_progress := 0.0

## Footsteps made since the last reset.
var step_count := 0

var _fade_tween: Tween
var _stride_walked := 0.0
var _last_pos := Vector3.ZERO
var _thunder_gen := 0
var _thunder_pending := 0


func _ready() -> void:
	soundscape.attach_footsteps(player)
	storm.flashed.connect(_on_flashed)
	reset_scene()
	_run_command_line.call_deferred()


func _process(_delta: float) -> void:
	mood.apply(MoodDirector.sample(furthest_progress))


func _physics_process(_delta: float) -> void:
	var pos := player.global_position
	_count_stride(pos - _last_pos, player.is_on_floor())
	_last_pos = pos
	var progress := trail.progress_at(pos)
	furthest_progress = maxf(furthest_progress, progress)
	if pos.y < trail.point_at(progress).y - FALL_DEPTH:
		respawn()
	if summit.phase == SummitSequence.Phase.IDLE and furthest_progress >= SummitSequence.START_PROGRESS:
		summit.start()


## Puts the girl back at the trail start facing up the trail, restarts the fade-in from black,
## and resets the progress, the mood, the storm, the vista (closed: reveal 0) and the summit
## sequence (idle, gameplay camera current, control given back, title hidden).
func reset_scene() -> void:
	furthest_progress = 0.0
	_thunder_gen += 1
	_thunder_pending = 0
	_stride_walked = 0.0
	step_count = 0
	summit.reset()
	soundscape.stop_one_shots()
	storm.reset()
	vista.reveal = 0.0
	mood.apply(MoodDirector.sample(0.0))
	_place_on_trail(0.0)
	_last_pos = player.global_position
	_restart_fade()


## Puts her on the trail at `progress`, at rest facing up it, counting it as reached.
func place_on_trail(progress: float) -> void:
	_place_on_trail(progress)
	_last_pos = player.global_position
	furthest_progress = maxf(furthest_progress, progress)


## Stops the start's fade-in where it is, so the summit sequence can own UI/Fade.
func stop_fade() -> void:
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = null


## Thunder rolls still waiting for their flash's delay.
func pending_thunder() -> int:
	return _thunder_pending


## Adds `motion`'s horizontal length to the walked distance while on the floor, and makes a
## footstep every STRIDE metres.
func _count_stride(motion: Vector3, on_floor: bool) -> void:
	if not on_floor:
		return
	_stride_walked += Vector2(motion.x, motion.z).length()
	while _stride_walked >= STRIDE:
		_stride_walked -= STRIDE
		step_count += 1
		var on_trail := trail.distance_to_centre(player.global_position) <= trail.width * 0.5 + 0.5
		soundscape.step(on_trail)


func _on_flashed(delay_s: float) -> void:
	var gen := _thunder_gen
	_thunder_pending += 1
	await get_tree().create_timer(delay_s).timeout
	if gen != _thunder_gen:
		return
	_thunder_pending -= 1
	soundscape.play_thunder()


## Puts her back on the trail at the furthest point she reached, at rest.
func respawn() -> void:
	_place_on_trail(furthest_progress)


func _place_on_trail(progress: float) -> void:
	player.global_position = trail.point_at(progress) + Vector3.UP
	player.velocity = Vector3.ZERO
	var ahead := trail.point_at(minf(progress + 2.0 / trail.length(), 1.0)) - trail.point_at(progress)
	if progress >= 1.0:
		ahead = trail.point_at(1.0) - trail.point_at(1.0 - 2.0 / trail.length())
	var dir := Vector2(ahead.x, ahead.z).normalized()
	player.get_node("Model").rotation.y = atan2(dir.x, dir.y)
	follow_cam.yaw_deg = rad_to_deg(atan2(-dir.x, -dir.y))
	follow_cam.snap()


func _restart_fade() -> void:
	if _fade_tween:
		_fade_tween.kill()
	fade.color.a = 1.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade, "color:a", 0.0, FADE_IN_SECONDS)


## The named capture views, in order.
func view_names() -> PackedStringArray:
	return PackedStringArray(VIEWS.keys())


## Puts the level in the named view (see VIEWS, plus REVEAL_EARLY), clear of the fade and title,
## with the summit sequence frozen where it stands. An unknown name warns and changes nothing. Callers wait SETTLE_FRAMES to let it settle.
func show_view(view_name: String) -> void:
	if view_name != REVEAL_EARLY and not VIEWS.has(view_name):
		push_warning("show_view: unknown view '%s'" % view_name)
		return
	reset_scene()
	stop_fade()
	fade.color.a = 0.0
	if view_name == REVEAL_EARLY:
		summit.skip_to(SummitSequence.Phase.REVEAL)
		summit.scrub(REVEAL_EARLY_SECONDS)
		vista.reveal = 0.15
	elif VIEWS.get(view_name, -1.0) < 0.0:
		summit.skip_to(SummitSequence.Phase.PULLBACK)
		summit.scrub(SummitSequence.PULLBACK_SECONDS)
	else:
		place_on_trail(VIEWS[view_name])
	follow_cam.snap()


## Command line (after `--`): --capture-views, --profile, --quit.
func _run_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	if "--capture-views" in args or "--profile" in args:
		storm.reset()
		storm.set_process(false)  # no lightning: the frames stay deterministic
		for node in get_tree().get_nodes_in_group("overlay"):
			node.visible = false
	if "--capture-views" in args:
		await capture_views()
	if "--profile" in args:
		await profile_views()
	if "--quit" in args:
		get_tree().quit()


func _settle() -> void:
	for _f in SETTLE_FRAMES:
		await get_tree().process_frame


## Saves screenshots/heavens_<view>_<datetime>.png for each named view.
func capture_views() -> void:
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	for v in view_names():
		show_view(v)
		await _settle()
		await RenderingServer.frame_post_draw
		var path := dir.path_join("heavens_%s_%s.png" % [v, stamp])
		get_viewport().get_texture().get_image().save_png(path)
		print("Saved ", path)


## Measures each named view and REVEAL_EARLY (settle 30 frames, measure 120), prints the table and
## writes screenshots/heavens_profile_<datetime>.md. Run with --disable-vsync.
func profile_views() -> String:
	var hud := PerfHud.new()
	$UI.add_child(hud)
	var rows: Array[Dictionary] = []
	var names := view_names()
	names.append(REVEAL_EARLY)
	for v in names:
		show_view(v)
		await _settle()
		var m: Dictionary = await hud.measure(PROFILE_FRAMES)
		m["view"] = v
		m["grass"] = true
		rows.append(m)
	hud.queue_free()
	var text := PerfHud.table(rows)
	print(text)
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open(dir.path_join("heavens_profile_%s.md" % stamp), FileAccess.WRITE)
	if file:
		file.store_string(text)
	return text
