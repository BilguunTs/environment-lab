class_name SummitSequence
extends Node
## The Heavens call ending. HeavensCall calls start() once, when her furthest progress reaches
## START_PROGRESS; from then on the sequence owns her, the cameras, the reveal and the overlays:
##
## - SLOWING: control is taken away and she eases to a stop, turning to face the vista (-Z),
##   while the gameplay camera swings round behind her to look the same way (its mouse orbit,
##   zoom and Q/E locked: FollowCamera.orbit_locked).
## - REVEAL: SummitCamera takes over from the gameplay camera's exact transform and rises gently
##   up and over the summit's rim, so the parting fog and the opening mist sea are watched as
##   they happen. Meanwhile the vista's `reveal` opens 0 -> 1, the wind surges on top of the mood
##   (MoodDirector.wind_surge) and the thunderclap sounds CLAP_AT seconds in.
## - PULLBACK: SummitCamera carries on from that pose, craning back and up along an arc until she
##   is a tiny silhouette above the ocean of mist.
## - FADE: UI/Fade goes to black over the held end frame.
## - TITLE: UI/Title fades in; once it is fully shown, any key or mouse button ends the level.
##
## Everything is driven per frame from the phase and the seconds spent in it, every move eased
## in and out, so skip_to() can put the scene at the start of any phase and nothing ever pops.

signal finished

enum Phase { IDLE, SLOWING, REVEAL, PULLBACK, FADE, TITLE }

const TITLE := "Heavens call"
## Furthest trail progress that starts the sequence.
const START_PROGRESS := 0.97

## Phase lengths, seconds.
const SLOWING_SECONDS := 2.0
const REVEAL_SECONDS := 8.0
const PULLBACK_SECONDS := 12.0
const FADE_SECONDS := 4.0
const TITLE_FADE_SECONDS := 2.0
## Seconds into REVEAL that the thunderclap sounds.
const CLAP_AT := 2.0
## Seconds into REVEAL over which the wind surge rises 0 -> 1 (it then holds to the end).
const SURGE_SECONDS := 5.0

## The gameplay camera's pose at the end of SLOWING (where SummitCamera takes over): looking
## along -Z (yaw 0), at pitch 16 degrees and 9 m out, a little higher and further back than the
## climb's 14 degrees and 7 m. The player's own pitch and distance come back on reset.
const LOOK_YAW_DEG := 0.0
const LOOK_PITCH_DEG := 16.0
const LOOK_DISTANCE := 9.0
## Where she faces at the end of SLOWING: the Model's yaw toward -Z (Player: atan2(dir.x, dir.z)).
const FACE_YAW := PI

## The REVEAL rise's end pose, relative to her feet: high enough behind her to see over the
## summit's rim and plateau, aimed nearly level (about 9 degrees down) so the mist sea fills the
## middle band of the frame with her low in it. REVEAL_ARC_LIFT bows the path upward (a quadratic
## Bezier). The rise has its own, shorter clock (RISE_SECONDS) and then holds, so the second half
## of the fog parting is watched from the raised pose.
const RISE_SECONDS := 4.5
const REVEAL_CAM_OFFSET := Vector3(0.0, 16.0, 24.0)
const REVEAL_CAM_LOOK := Vector3(0.0, -6.0, -120.0)
const REVEAL_ARC_LIFT := 2.0
## The pull-back's end frame, relative to her feet: the camera high behind her (+Z), looking
## down past her across the mist sea toward the gap in the ridges (-Z). PULL_ARC_LIFT raises the
## path's middle, so the crane rises a little ahead of travelling back.
const PULL_END_OFFSET := Vector3(0.0, 48.0, 80.0)
const PULL_END_LOOK := Vector3(0.0, -36.0, -300.0)
const PULL_ARC_LIFT := 18.0
## Where skip_to() puts her when she isn't at the summit yet (where a walk-in stops).
const SKIP_PROGRESS := 0.975

## The level root: player, cameras, vista, mood, soundscape, trail and fade come from it.
@export var level: HeavensCall
## The cinematic camera for REVEAL onward (separate from the gameplay camera).
@export var summit_camera: Camera3D
@export var title_label: Label
## Test hook: false makes the final key only emit `finished`, without quitting.
@export var quit_on_finish := true

var phase := Phase.IDLE
## True only once the title is fully shown: then any key or mouse button finishes.
var input_armed := false
## Whether this run's thunderclap has sounded.
var clap_played := false

var _t := 0.0  # seconds into the current phase
var _start_speed := Vector3.ZERO  # her horizontal velocity when SLOWING began
var _start_face := 0.0  # her Model's yaw when SLOWING began
var _cam_yaw0 := 0.0  # gameplay camera orbit when SLOWING began
var _cam_pitch0 := 0.0
var _cam_dist0 := 0.0
var _cam_saved := false  # whether pitch0/dist0 hold the player's own orbit (to give back)
var _accel := -1.0  # her acceleration, saved while SLOWING drives her velocity
var _rise_from := Transform3D.IDENTITY  # the gameplay camera's transform when REVEAL began
var _rise_look_from := Vector3.ZERO  # and the point it looked at (its pivot)
var _anchor := Vector3.ZERO  # her feet when REVEAL began


func _ready() -> void:
	process_physics_priority = -10  # set her velocity before Player._physics_process moves her
	process_priority = -10  # set the camera's orbit before FollowCamera._process places it
	if title_label:
		title_label.text = TITLE
		title_label.modulate.a = 0.0


## The in-out ease every transition uses (sine in-out: zero speed at both ends).
static func ease_in_out(t: float) -> float:
	return 0.5 - 0.5 * cos(PI * clampf(t, 0.0, 1.0))


## Begins the ending (once: ignored unless idle).
func start() -> void:
	if phase != Phase.IDLE:
		return
	_begin_slowing()


## Puts the scene at the start of phase `p`, from IDLE or any phase. From IDLE she is first put at
## the summit if she isn't there yet. skip_to(IDLE) is the level's full reset_scene().
func skip_to(p: Phase) -> void:
	if p == Phase.IDLE:
		level.reset_scene()
		return
	if phase == Phase.IDLE and level.trail.progress_at(level.player.global_position) < START_PROGRESS:
		level.place_on_trail(SKIP_PROGRESS)
	set_process(true)
	if phase == Phase.IDLE:
		_take_control()
	_restore_accel()
	clap_played = false
	input_armed = false
	var opened := p >= Phase.PULLBACK
	level.vista.reveal = 1.0 if opened else 0.0
	level.mood.wind_surge = 1.0 if opened else 0.0
	level.stop_fade()
	level.fade.color.a = 1.0 if p == Phase.TITLE else 0.0
	title_label.modulate.a = 0.0
	if p == Phase.SLOWING:
		_begin_slowing()  # from her current motion and orbit, gameplay camera current
		return
	_settle_her()
	level.follow_cam.yaw_deg = LOOK_YAW_DEG
	level.follow_cam.pitch_deg = LOOK_PITCH_DEG
	level.follow_cam.distance = LOOK_DISTANCE
	level.follow_cam.snap()
	_begin_summit_camera()
	if p == Phase.PULLBACK:
		_place_pull(0.0)
	elif p > Phase.PULLBACK:
		_place_pull(1.0)
	phase = p
	_t = 0.0


## Back to IDLE: gameplay camera, control and orbit given back, surge off, title hidden. (The
## level's reset_scene calls this and also closes the vista and restarts the fade-in.)
func reset() -> void:
	set_process(true)
	set_physics_process(true)
	phase = Phase.IDLE
	_t = 0.0
	input_armed = false
	clap_played = false
	_restore_accel()
	if level == null:
		return
	level.player.input_enabled = true
	level.follow_cam.input_enabled = true
	level.follow_cam.orbit_locked = false
	if _cam_saved:
		level.follow_cam.pitch_deg = _cam_pitch0
		level.follow_cam.distance = _cam_dist0
		_cam_saved = false
	level.follow_cam.make_current()
	level.mood.wind_surge = 0.0
	if title_label:
		title_label.modulate.a = 0.0


## Freezes the current phase `seconds` in (capture and profile views): the pose is placed and
## nothing advances until skip_to() or reset() runs again.
func scrub(seconds: float) -> void:
	_t = seconds
	_process(0.0)
	set_process(false)


func _input(event: InputEvent) -> void:
	if not input_armed:
		return
	var key: bool = event is InputEventKey and event.pressed and not event.echo
	var button: bool = event is InputEventMouseButton and event.pressed
	if key or button:
		get_viewport().set_input_as_handled()
		_finish()


func _finish() -> void:
	input_armed = false
	finished.emit()
	if quit_on_finish:
		get_tree().quit()


func _physics_process(_delta: float) -> void:
	if phase != Phase.SLOWING:
		return
	var v := _start_speed * (1.0 - ease_in_out(_t / SLOWING_SECONDS))
	level.player.velocity.x = v.x
	level.player.velocity.z = v.z


func _process(delta: float) -> void:
	if phase == Phase.IDLE:
		return
	_t += delta
	match phase:
		Phase.SLOWING:
			var e := ease_in_out(_t / SLOWING_SECONDS)
			var model: Node3D = level.player.get_node("Model")
			model.rotation.y = lerp_angle(_start_face, FACE_YAW, e)
			level.follow_cam.yaw_deg = rad_to_deg(lerp_angle(deg_to_rad(_cam_yaw0), deg_to_rad(LOOK_YAW_DEG), e))
			level.follow_cam.pitch_deg = lerpf(_cam_pitch0, LOOK_PITCH_DEG, e)
			level.follow_cam.distance = lerpf(_cam_dist0, LOOK_DISTANCE, e)
			if _t >= SLOWING_SECONDS:
				_settle_her()
				level.follow_cam.yaw_deg = LOOK_YAW_DEG
				level.follow_cam.pitch_deg = LOOK_PITCH_DEG
				level.follow_cam.distance = LOOK_DISTANCE
				level.follow_cam.snap()  # the exact look pose SummitCamera starts from
				_begin_summit_camera()
				_next(Phase.REVEAL)
		Phase.REVEAL:
			_place_rise(ease_in_out(_t / RISE_SECONDS))
			level.vista.reveal = ease_in_out(_t / REVEAL_SECONDS)
			level.mood.wind_surge = ease_in_out(_t / SURGE_SECONDS)
			if not clap_played and _t >= CLAP_AT:
				clap_played = true
				level.soundscape.play_thunder(true)
			if _t >= REVEAL_SECONDS:
				level.vista.reveal = 1.0
				level.mood.wind_surge = 1.0
				_place_pull(0.0)
				_next(Phase.PULLBACK)
		Phase.PULLBACK:
			_place_pull(ease_in_out(_t / PULLBACK_SECONDS))
			if _t >= PULLBACK_SECONDS:
				_place_pull(1.0)
				_next(Phase.FADE)
		Phase.FADE:
			level.fade.color.a = ease_in_out(_t / FADE_SECONDS)
			if _t >= FADE_SECONDS:
				level.fade.color.a = 1.0
				_next(Phase.TITLE)
		Phase.TITLE:
			title_label.modulate.a = ease_in_out(_t / TITLE_FADE_SECONDS)
			if _t >= TITLE_FADE_SECONDS and not input_armed:
				title_label.modulate.a = 1.0
				input_armed = true


func _next(p: Phase) -> void:
	phase = p
	_t = 0.0


func _take_control() -> void:
	level.player.input_enabled = false
	level.follow_cam.input_enabled = false
	level.follow_cam.orbit_locked = true
	if not _cam_saved:
		_cam_pitch0 = level.follow_cam.pitch_deg
		_cam_dist0 = level.follow_cam.distance
		_cam_saved = true
	_cam_yaw0 = level.follow_cam.yaw_deg


func _begin_slowing() -> void:
	_take_control()
	var v: Vector3 = level.player.velocity
	_start_speed = Vector3(v.x, 0.0, v.z)
	_start_face = level.player.get_node("Model").rotation.y
	if _accel < 0.0:
		_accel = level.player.acceleration
	level.player.acceleration = 0.0  # her own easing off; SLOWING sets her velocity instead
	level.follow_cam.make_current()
	clap_played = false
	input_armed = false
	_next(Phase.SLOWING)


## At rest, facing the vista: SLOWING's end state.
func _settle_her() -> void:
	_restore_accel()
	level.player.velocity.x = 0.0
	level.player.velocity.z = 0.0
	level.player.get_node("Model").rotation.y = FACE_YAW


func _restore_accel() -> void:
	if _accel >= 0.0 and level:
		level.player.acceleration = _accel
	_accel = -1.0


## SummitCamera takes over from the gameplay camera's transform, looking at its pivot.
func _begin_summit_camera() -> void:
	var cam: FollowCamera = level.follow_cam
	_anchor = level.player.global_position
	_rise_from = cam.global_transform
	_rise_look_from = _anchor + Vector3.UP * cam.height
	summit_camera.fov = cam.fov
	summit_camera.global_transform = _rise_from
	summit_camera.make_current()


## The REVEAL rise at eased fraction `e`: from the gameplay camera's pose up over the rim.
func _place_rise(e: float) -> void:
	if e <= 0.0:
		summit_camera.global_transform = _rise_from
		return
	_place_move(_rise_from.origin, _rise_look_from, _anchor + REVEAL_CAM_OFFSET,
			_anchor + REVEAL_CAM_LOOK, REVEAL_ARC_LIFT, e)


## The pull-back at eased fraction `e`: from the rise's end pose out to the end frame.
func _place_pull(e: float) -> void:
	_place_move(_anchor + REVEAL_CAM_OFFSET, _anchor + REVEAL_CAM_LOOK, _anchor + PULL_END_OFFSET,
			_anchor + PULL_END_LOOK, PULL_ARC_LIFT, e)


## SummitCamera at `e` along a quadratic Bezier from `p0` to `p2` (its middle raised by `lift`),
## aimed at a point sliding from `look0` to `look2`.
func _place_move(p0: Vector3, look0: Vector3, p2: Vector3, look2: Vector3, lift: float, e: float) -> void:
	var p1 := (p0 + p2) * 0.5 + Vector3.UP * lift
	summit_camera.global_position = p0.lerp(p1, e).lerp(p1.lerp(p2, e), e)
	summit_camera.look_at(look0.lerp(look2, e), Vector3.UP)
