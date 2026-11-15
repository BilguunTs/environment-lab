extends "res://tests/case.gd"
## Granite shape set for the terrain replica (assets/blender/build_granite.py). Every rock GLB is
## normalised to a 1 x 1 x 1 m box with its base at y = 0, centred on X/Z, so that
## `scale = (length, height, width)` reproduces each measured rock exactly. The ger is real size.

const DIR := "res://assets/meshes/rocks_granite/"
const SHAPES: Array[String] = [
	"granite_round_a", "granite_round_b", "granite_round_c",
	"granite_slab_a", "granite_slab_b", "granite_split_a",
	"granite_scree_a", "granite_scree_b", "granite_scree_c",
]
## Instanced up to ~200k times: triangle budgets per family.
const TRI_BUDGET := {"granite_round": 300, "granite_slab": 300, "granite_split": 300, "granite_scree": 60}
const TOLERANCE := 0.01


func test_shapes_are_unit_boxes_on_the_ground(_pg) -> void:
	for shape in SHAPES:
		var box := _aabb(shape)
		check_near(box.size.x, 1.0, TOLERANCE, "%s size x" % shape)
		check_near(box.size.y, 1.0, TOLERANCE, "%s size y" % shape)
		check_near(box.size.z, 1.0, TOLERANCE, "%s size z" % shape)
		check_near(box.position.y, 0.0, TOLERANCE, "%s min y" % shape)
		check_near(box.get_center().x, 0.0, TOLERANCE, "%s centre x" % shape)
		check_near(box.get_center().z, 0.0, TOLERANCE, "%s centre z" % shape)


func test_ger_is_real_size(_pg) -> void:
	var box := _aabb("ger")
	check_near(box.size.x, 6.0, 0.05, "ger diameter x")
	check_near(box.size.z, 6.0, 0.05, "ger diameter z")
	check_near(box.size.y, 2.4, 0.05, "ger crown height")
	check_near(box.position.y, 0.0, TOLERANCE, "ger min y")
	check_near(box.get_center().x, 0.0, TOLERANCE, "ger centre x")
	check_near(box.get_center().z, 0.0, TOLERANCE, "ger centre z")


func test_meshes_have_vertex_colours_and_palette_material(_pg) -> void:
	for shape: String in SHAPES + ["ger"]:
		var meshes := _meshes(shape)
		check(not meshes.is_empty(), "%s has a mesh" % shape)
		for mesh in meshes:
			for i in mesh.get_surface_count():
				check(mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR != 0,
						"%s surface %d has vertex colours" % [shape, i])
				var material := mesh.surface_get_material(i)
				var palette := "res://assets/materials/%s.tres" % (material.resource_name if material else "")
				check(ResourceLoader.exists(palette), "%s surface %d names a palette material (%s)" % [shape, i, palette])
	for name in ["granite", "felt"]:
		var material := load("res://assets/materials/%s.tres" % name) as ShaderMaterial
		check(material != null and material.shader.resource_path.ends_with("flat_color.gdshader"),
				"%s.tres is a flat_color material" % name)
		if material:
			check(material.get_shader_parameter("use_vertex_color") == true, "%s.tres shows vertex colours" % name)


func test_triangle_budgets(_pg) -> void:
	for shape in SHAPES:
		var tris := 0
		for mesh in _meshes(shape):
			for i in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(i)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				tris += (indices.size() if indices else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var budget: int = TRI_BUDGET[shape.left(shape.rfind("_"))]
		check(tris > 0 and tris <= budget, "%s triangles %d within %d" % [shape, tris, budget])


## Every MeshInstance3D mesh in the imported GLB scene.
func _meshes(shape: String) -> Array[Mesh]:
	var out: Array[Mesh] = []
	var scene := load(DIR + shape + ".glb") as PackedScene
	if scene == null:
		failures.append("%s.glb does not load" % shape)
		return out
	var root := scene.instantiate()
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh:
			out.append(mesh)
	root.free()
	return out


## Union of the GLB's mesh AABBs in the scene root's space.
func _aabb(shape: String) -> AABB:
	var scene := load(DIR + shape + ".glb") as PackedScene
	if scene == null:
		failures.append("%s.glb does not load" % shape)
		return AABB()
	var root := scene.instantiate() as Node3D
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var xform := Transform3D()
		var walk: Node = instance
		while walk != root:
			xform = (walk as Node3D).transform * xform
			walk = walk.get_parent()
		var part := xform * instance.mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	root.free()
	if first:
		failures.append("%s.glb has no mesh" % shape)
	return box
