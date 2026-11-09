class_name Player
extends CharacterBody3D
## Minimal third-person walker. Movement is relative to whichever camera is active,
## so it also works from fixed cinematic viewpoints.

@export var walk_speed := 3.5
@export var sprint_speed := 7.0
@export var acceleration := 10.0
@export var turn_speed := 10.0
## Off in levels where she only walks.
@export var can_sprint := true
## The lantern mesh and its light; off for a girl who walks in the dark.
@export var lantern := true:
	set(value):
		lantern = value
		_apply_lantern()
## Off while another system (e.g. the scout camera) owns the movement keys.
var input_enabled := true

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _model: Node3D = $Model


func _ready() -> void:
	_apply_lantern()


func _apply_lantern() -> void:
	if not is_node_ready():
		return
	_model.get_node("Lantern").visible = lantern
	_model.get_node("LanternLight").visible = lantern


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam and input != Vector2.ZERO:
		var forward := -cam.global_basis.z
		if absf(forward.y) > 0.98:  # looking straight down: use the camera's up as "forward"
			forward = cam.global_basis.y
		forward = Vector3(forward.x, 0.0, forward.z).normalized()
		var right := Vector3(-forward.z, 0.0, forward.x)
		dir = right * input.x - forward * input.y

	var speed := sprint_speed if can_sprint and Input.is_action_pressed("sprint") else walk_speed
	var blend := 1.0 - exp(-acceleration * delta)
	velocity.x = lerpf(velocity.x, dir.x * speed, blend)
	velocity.z = lerpf(velocity.z, dir.z * speed, blend)
	velocity.y -= _gravity * delta
	move_and_slide()

	if dir.length_squared() > 0.01:
		var target_yaw := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 1.0 - exp(-turn_speed * delta))
