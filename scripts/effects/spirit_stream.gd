@tool
class_name SpiritStream
extends GPUParticles3D
## Feeds spirit_stream.gdshader with the world positions of its two ends, so the stream
## follows when either end moves (in the editor too). Keep this node at the origin with no
## rotation: the shader works in world space and the visibility box is computed from the path.

@export var source: Node3D
@export var target: Node3D
## Height of the arc's control point above the midpoint of source and target.
@export var arc_height := 4.0

var _last := PackedVector3Array()


func _process(_delta: float) -> void:
	if source == null or target == null or not (process_material is ShaderMaterial):
		return
	var a := source.global_position
	var b := target.global_position
	var apex := (a + b) * 0.5 + Vector3.UP * arc_height
	var key := PackedVector3Array([a, b, apex])
	if key == _last:
		return
	_last = key
	var mat: ShaderMaterial = process_material
	mat.set_shader_parameter("source", a)
	mat.set_shader_parameter("apex", apex)
	mat.set_shader_parameter("target", b)
	var margin: float = mat.get_shader_parameter("spread") + mat.get_shader_parameter("wobble") + 1.0
	var box := AABB(a, Vector3.ZERO).expand(b).expand(apex).grow(margin)
	visibility_aabb = AABB(box.position - global_position, box.size)
