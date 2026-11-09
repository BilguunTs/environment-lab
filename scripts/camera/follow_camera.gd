class_name FollowCamera
extends Camera3D
## Gameplay camera: orbits a pivot placed `height` metres above the target.
## Cinematic viewpoints are separate Camera3D nodes and never move.
##
## Right-mouse drag orbits, Q/E rotates, mouse wheel zooms.

signal user_adjusted  # emitted when the player orbits/zooms, so UI can resync

@export var target: Node3D
@export_range(0.0, 10.0, 0.1) var height := 1.4
@export_range(1.0, 40.0, 0.5) var distance := 7.0
## Angle above the horizon. Negative values look up at the subject from below.
@export_range(-10.0, 80.0, 1.0) var pitch_deg := 14.0:
	set(value):
		pitch_deg = clampf(value, min_pitch, max_pitch)
## Orbit limits for pitch_deg, in degrees above the horizon.
@export var min_pitch := -10.0
@export var max_pitch := 80.0
@export var yaw_deg := 0.0
@export var follow_smoothing := 6.0
@export var mouse_orbit_sensitivity := 0.25
@export var key_orbit_speed := 90.0
## Physics layers the camera can't pass through (0 = off). When set, a ray from the look target
## to the camera stops it short of the first hit, so walls never come between her and the view.
@export_flags_3d_physics var collision_mask := 0
## Off while a panel text field has focus, so typing Q or E doesn't orbit.
var input_enabled := true
## On while a cutscene owns the camera (the Heavens call summit sequence): mouse orbit, wheel
## zoom and Q/E are all ignored, so nothing but the cutscene moves it.
var orbit_locked := false

## How far in front of a hit the camera stops, in metres.
const COLLISION_MARGIN := 0.3
## The camera never pulls in closer than this to the look target.
const MIN_DISTANCE := 0.6
## How fast the camera eases back out once a wall stops blocking it (per second).
const RETURN_SPEED := 3.0

var _pivot := Vector3.ZERO
var _clear_distance := INF  # how far out the camera may be (smoothed); collision only


func _ready() -> void:
	if target:
		_pivot = _goal()
	_place()


func _unhandled_input(event: InputEvent) -> void:
	if not current or orbit_locked:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw_deg -= event.relative.x * mouse_orbit_sensitivity
		pitch_deg += event.relative.y * mouse_orbit_sensitivity
		user_adjusted.emit()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1.0, distance * 0.9)
			user_adjusted.emit()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(40.0, distance * 1.1)
			user_adjusted.emit()


func _process(delta: float) -> void:
	if current and input_enabled and not orbit_locked:
		var orbit := float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
		yaw_deg += orbit * key_orbit_speed * delta
	if target:
		_pivot = _pivot.lerp(_goal(), 1.0 - exp(-follow_smoothing * delta))
	_place(delta)


## Jump straight to the target, skipping smoothing (used after teleports/resets).
func snap() -> void:
	if target:
		_pivot = _goal()
	_place()


func _goal() -> Vector3:
	return target.global_position + Vector3.UP * height


## Puts the camera on its orbit. `delta` 0 (a snap) skips the ease-out after a collision.
func _place(delta := 0.0) -> void:
	var offset := Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), deg_to_rad(yaw_deg), 0.0)) * Vector3.BACK
	var pos := _pivot + offset * _collided_distance(offset, delta)
	pos.y = maxf(pos.y, 0.15)  # never dip below the ground plane
	global_position = pos
	if not pos.is_equal_approx(_pivot):
		look_at(_pivot, Vector3.UP)


## `distance`, shortened to stay in front of anything on `collision_mask` between the look target
## and the camera. It pulls in at once (a wall is never seen from inside) and eases back out.
func _collided_distance(offset: Vector3, delta: float) -> float:
	if collision_mask == 0 or not is_inside_tree():
		return distance
	var q := PhysicsRayQueryParameters3D.create(_pivot, _pivot + offset * distance, collision_mask)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var limit := distance
	if not hit.is_empty():
		limit = maxf(_pivot.distance_to(hit.position) - COLLISION_MARGIN, MIN_DISTANCE)
	if delta <= 0.0 or limit < _clear_distance:
		_clear_distance = limit
	else:
		_clear_distance = lerpf(_clear_distance, limit, 1.0 - exp(-RETURN_SPEED * delta))
	return minf(distance, _clear_distance)
