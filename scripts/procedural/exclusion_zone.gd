@tool
class_name ExclusionZone
extends Node3D
## Keeps scattered objects out of an area on the ground plane: a circle, a capsule (along
## local Z) or a box. `falloff` softens the edge so a scatter thins out over that many metres
## instead of stopping at a hard line. Move/rotate the node in the editor; don't scale it.
## The outline is drawn in the editor, and at runtime when debug drawing is switched on.

enum Shape { CIRCLE, CAPSULE, BOX }

@export var shape: Shape = Shape.CIRCLE:
	set(v):
		shape = v
		_redraw()
@export var radius := 5.0:
	set(v):
		radius = v
		_redraw()
## Capsule only: length of the straight middle section.
@export var length := 10.0:
	set(v):
		length = v
		_redraw()
## Box only: width (x) and depth (z).
@export var size := Vector2(10, 10):
	set(v):
		size = v
		_redraw()
@export var falloff := 3.0:
	set(v):
		falloff = v
		_redraw()
@export var debug_color := Color(1.0, 0.45, 0.2)

var _outline: MeshInstance3D


func _ready() -> void:
	_redraw()
	set_debug_visible(Engine.is_editor_hint())


## 0 inside the shape, ramping to 1 at `falloff` metres outside it.
func weight(world: Vector3) -> float:
	var p := global_transform.affine_inverse() * world
	var d := signed_distance(Vector2(p.x, p.z))
	if falloff <= 0.0:
		return 0.0 if d < 0.0 else 1.0
	return clampf(d / falloff, 0.0, 1.0)


## Distance from the shape's edge in local x/z (negative inside).
func signed_distance(p: Vector2) -> float:
	match shape:
		Shape.CIRCLE:
			return p.length() - radius
		Shape.CAPSULE:
			var z := clampf(p.y, -length * 0.5, length * 0.5)
			return Vector2(p.x, p.y - z).length() - radius
		_:
			var q := Vector2(absf(p.x), absf(p.y)) - size * 0.5
			return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


func set_debug_visible(on: bool) -> void:
	if _outline:
		_outline.visible = on


func _redraw() -> void:
	if not is_inside_tree():
		return
	if _outline == null:
		_outline = MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_outline.material_override = mat
		_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_outline, false, INTERNAL_MODE_FRONT)
	var mesh := ImmediateMesh.new()
	_add_loop(mesh, 0.0, debug_color)
	if falloff > 0.0:
		_add_loop(mesh, falloff, Color(debug_color, 0.35))
	_outline.mesh = mesh


func _add_loop(mesh: ImmediateMesh, grow: float, color: Color) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	mesh.surface_set_color(color)
	for p in _outline_points(grow):
		mesh.surface_add_vertex(Vector3(p.x, 0.15, p.y))
	mesh.surface_end()


func _outline_points(grow: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match shape:
		Shape.CIRCLE:
			for i in 49:
				pts.append(Vector2.from_angle(TAU * i / 48.0) * (radius + grow))
		Shape.CAPSULE:
			var r := radius + grow
			var h := length * 0.5
			for i in 25:
				pts.append(Vector2(0, h) + Vector2.from_angle(PI * i / 24.0) * r)
			for i in 25:
				pts.append(Vector2(0, -h) + Vector2.from_angle(PI + PI * i / 24.0) * r)
			pts.append(pts[0])
		_:
			var e := size * 0.5 + Vector2(grow, grow)
			pts.append_array([Vector2(-e.x, -e.y), Vector2(e.x, -e.y), Vector2(e.x, e.y), Vector2(-e.x, e.y), Vector2(-e.x, -e.y)])
	return pts
