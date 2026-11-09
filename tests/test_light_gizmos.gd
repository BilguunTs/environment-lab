extends "res://tests/case.gd"


func after_each(pg) -> void:
	pg.set_param("light_gizmos", false)


func test_circle_is_segment_pairs_on_the_radius(_pg) -> void:
	var pts := LightGizmos.circle(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, 2.0, 16)
	check_eq(pts.size(), 32, "two points per segment")
	for p in pts:
		check_near(p.length(), 2.0, 0.0001, "on the radius")


func test_cone_rim_is_at_range(_pg) -> void:
	var xf := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
	var pts := LightGizmos.cone(xf, 10.0, 30.0)
	for i in LightGizmos.SEGMENTS * 2:  # the rim circle comes first
		check_near(pts[i].distance_to(xf.origin), 10.0, 0.001, "rim point %d at the light's range" % i)
	check_eq(pts.size(), LightGizmos.SEGMENTS * 2 + 16, "rim plus 8 edges")


func test_gizmos_draw_and_skip_hidden_lights(pg) -> void:
	if not needs_window():
		return
	pg.set_param("light_gizmos", true)
	await frames(2)
	var mesh: ImmediateMesh = pg.light_gizmos.mesh
	check_eq(mesh.get_surface_count(), 1, "one line surface")
	var with_hole := _vertex_count(mesh)
	pg.set_param("supernatural", false)  # hides the hole spotlight
	await frames(2)
	check_eq(_vertex_count(mesh), with_hole - (LightGizmos.SEGMENTS * 2 + 16), "hidden spot light not drawn")
	pg.set_param("light_gizmos", false)
	await frames(1)
	check_eq(mesh.get_surface_count(), 0, "cleared when off")


func _vertex_count(mesh: Mesh) -> int:
	var arrays := mesh.surface_get_arrays(0)
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
