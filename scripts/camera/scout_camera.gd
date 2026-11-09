class_name ScoutCamera
extends Camera3D
## Free-fly camera for finding new compositions. Starts from whichever view was active.
## WASD move · right-mouse drag look · Q/E down/up · Shift fast · wheel changes speed.

@export var speed := 8.0
@export var fast_multiplier := 4.0
@export var look_sensitivity := 0.2

var _yaw := 0.0
var _pitch := 0.0


## Take over another camera's framing so scouting continues from the current shot.
## Off while a panel text field has focus, so typing doesn't fly the camera.
var input_enabled := true

func start_from(cam: Camera3D) -> void:
	global_transform = cam.global_transform
	fov = cam.fov
	var euler := global_basis.get_euler()
	_pitch = rad_to_deg(euler.x)
	_yaw = rad_to_deg(euler.y)


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= event.relative.x * look_sensitivity
		_pitch = clampf(_pitch - event.relative.y * look_sensitivity, -89.0, 89.0)
		rotation_degrees = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			speed = minf(speed * 1.25, 80.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			speed = maxf(speed / 1.25, 0.5)


func _process(delta: float) -> void:
	if not current or not input_enabled:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var vertical := float(Input.is_key_pressed(KEY_E)) - float(Input.is_key_pressed(KEY_Q))
	var move := global_basis * Vector3(input.x, 0.0, input.y) + Vector3.UP * vertical
	var s := speed * (fast_multiplier if Input.is_action_pressed("sprint") else 1.0)
	global_position += move * s * delta
