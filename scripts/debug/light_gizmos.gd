class_name LightGizmos
extends MeshInstance3D
## Draws every visible omni light's range, every spot light's cone and the sun's direction on
## top of everything (no depth test), so light coverage reads through the trees. Rebuilt each
## frame because the lantern moves with the player. Vertices are in world space: keep this node
## at the playground's origin.

const SEGMENTS := 32
const SUN_ARROW := 3.0  # m

var pg: Node
var _lights: Array[Light3D] = []
var _mesh := ImmediateMesh.new()


## Line-segment pairs for a circle of `radius` around `center` in the plane of axes a and b.
static func circle(center: Vector3, a: Vector3, b: Vector3, radius: float, segments := SEGMENTS) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in segments:
		var t0 := TAU * i / segments
		var t1 := TAU * (i + 1) / segments
		out.append(center + (a * cos(t0) + b * sin(t0)) * radius)
		out.append(center + (a * cos(t1) + b * sin(t1)) * radius)
	return out


## A spot light's reach: a rim whose points are all `reach` from the apex, plus edges to it,
## so the outline shows the true range at the cone's edge.
static func cone(xf: Transform3D, reach: float, angle_deg: float, edges := 8) -> PackedVector3Array:
	var angle := deg_to_rad(angle_deg)
	var forward := -xf.basis.z.normalized()
	var right := xf.basis.x.normalized()
	var up := xf.basis.y.normalized()
	var rim_center := xf.origin + forward * reach * cos(angle)
	var rim_radius := reach * sin(angle)
	var out := circle(rim_center, right, up, rim_radius)
	for i in edges:
		var t := TAU * i / edges
		out.append(xf.origin)
		out.append(rim_center + (right * cos(t) + up * sin(t)) * rim_radius)
	return out


static func arrow(from: Vector3, direction: Vector3, length: float) -> PackedVector3Array:
	var d := direction.normalized()
	var tip := from + d * length
	var side := d.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	return PackedVector3Array([from, tip, tip, tip - d * 0.6 + side * 0.3, tip, tip - d * 0.6 - side * 0.3])


func _ready() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # drawn after opaque geometry
	material.no_depth_test = true
	material_override = material
	visible = false
	add_to_group("overlay")  # captures hide it
	visibility_changed.connect(_on_visibility_changed)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)


func _on_visibility_changed() -> void:
	if visible:
		_lights.assign(pg.find_children("*", "Light3D", true, false))
	_rebuild()


func _on_node_added(node: Node) -> void:
	if visible and node is Light3D and pg.is_ancestor_of(node) and not _lights.has(node):
		_lights.append(node)


func _on_node_removed(node: Node) -> void:
	if node is Light3D:
		_lights.erase(node)


func _process(_delta: float) -> void:
	if visible:
		_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if not visible:
		return
	var points := PackedVector3Array()
	var colors := PackedColorArray()
	for light in _lights:
		if not is_instance_valid(light) or not light.is_visible_in_tree():
			continue
		var xf := light.global_transform
		var segment := PackedVector3Array()
		if light is OmniLight3D:
			var r: float = light.omni_range
			segment.append_array(circle(xf.origin, Vector3.RIGHT, Vector3.FORWARD, r))
			segment.append_array(circle(xf.origin, Vector3.RIGHT, Vector3.UP, r))
			segment.append_array(circle(xf.origin, Vector3.FORWARD, Vector3.UP, r))
		elif light is SpotLight3D:
			segment = cone(xf, light.spot_range, light.spot_angle)
		elif light is DirectionalLight3D:
			segment = arrow(pg.player.global_position + Vector3.UP * 2.5, -xf.basis.z, SUN_ARROW)
		points.append_array(segment)
		for i in segment.size():
			colors.append(light.light_color)
	if points.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in points.size():
		_mesh.surface_set_color(colors[i])
		_mesh.surface_add_vertex(points[i])
	_mesh.surface_end()
