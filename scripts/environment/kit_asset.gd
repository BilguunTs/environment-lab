@tool
extends Node3D
## Root of a kit asset scene (scenes/environment/kit/). Replaces every imported material
## with the palette material of the same name (res://assets/materials/<name>.tres), so
## Blender only has to name materials correctly; colour and shading live in Godot.

const PALETTE_DIR := "res://assets/materials/"
## Walkable ground is on layer 1 (world) + layer 2 (ground); grass rays against layer 2 only.
const GROUND_LAYERS := 3

## Adds trimesh collision on the ground layers (for terrain pieces such as mounds).
@export var collision := false
## Sway and contact shade measured from this instance's origin rather than world height (the
## flat_color instance uniform of the same name). Set it on kit pieces placed high above y = 0.
@export var height_from_origin := false:
	set(value):
		height_from_origin = value
		if is_inside_tree():
			_apply_height_from_origin()


func _ready() -> void:
	_apply_palette(self)
	_apply_height_from_origin()
	if collision:
		_build_collision()


func _apply_palette(node: Node) -> void:
	var instance := node as MeshInstance3D
	if instance and instance.mesh:
		for i in instance.mesh.get_surface_count():
			var source: Material = instance.mesh.surface_get_material(i)
			if source == null:
				continue
			var path := PALETTE_DIR + source.resource_name + ".tres"
			if ResourceLoader.exists(path):
				instance.set_surface_override_material(i, load(path))
			else:
				push_warning("%s: no palette material '%s'" % [owner_name(), source.resource_name])
	for child in node.get_children():
		_apply_palette(child)



## Pushes height_from_origin into every geometry instance under this asset. Only set when on, so
## instances that never use it carry no per-instance parameter at all.
func _apply_height_from_origin() -> void:
	for node in find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if height_from_origin or geometry.get_instance_shader_parameter("height_from_origin") != null:
			geometry.set_instance_shader_parameter("height_from_origin", height_from_origin)


## One static body ("Collision", no owner so it is never saved) with a trimesh per mesh.
func _build_collision() -> void:
	if has_node("Collision"):
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = GROUND_LAYERS
	add_child(body)
	var to_local := global_transform.affine_inverse()
	for instance in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := instance as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = mesh_instance.mesh.create_trimesh_shape()
		body.add_child(shape)
		shape.transform = to_local * mesh_instance.global_transform


func owner_name() -> String:
	return scene_file_path.get_file() if scene_file_path else String(name)
