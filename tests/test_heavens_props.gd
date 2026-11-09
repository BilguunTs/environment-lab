extends "res://tests/case.gd"
## Heavens call staging: war debris in the discovery stretch, traveller traces near the top,
## and none of it blocking the trail.

const SCENE := "res://scenes/levels/heavens_call.tscn"


func test_debris_in_discovery_stretch(lv) -> void:
	var n := 0
	for d: Node3D in lv.get_node("Debris").get_children():
		var p: float = lv.trail.progress_at(d.global_position)
		check(p >= 0.27 and p <= 0.61, "%s at progress %.2f" % [d.name, p])
		n += 1
	check(n >= 20 and n <= 30, "20-30 debris pieces, got %d" % n)


func test_traces_near_the_top(lv) -> void:
	for t: Node3D in lv.get_node("Traces").get_children():
		var p: float = lv.trail.progress_at(t.global_position)
		check(p >= 0.59 and p <= 0.96, "%s at progress %.2f" % [t.name, p])


func test_props_leave_the_path_walkable(lv) -> void:
	await physics_frames(2)
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	q.exclude = [lv.player.get_rid()]  # she stands on the trail at progress 0; only props count
	for i in 140:
		var p: Vector3 = lv.trail.point_at(i / 140.0)
		q.transform = Transform3D(Basis(), p + Vector3.UP * 0.9)
		check(space.intersect_shape(q, 1).is_empty(), "centreline clear at %.3f" % (i / 140.0))


## Every kit piece on the mountain sways and shades from its own origin (flat_color's
## height_from_origin), not from world y = 0 hundreds of metres below.
func test_level_kit_measures_from_origin(lv) -> void:
	var n := 0
	for group in ["Debris", "Traces", "Rocks"]:
		for kit: Node3D in lv.get_node(group).get_children():
			check(kit.height_from_origin, "%s/%s opts in" % [group, kit.name])
			for g in kit.find_children("*", "GeometryInstance3D", true, false):
				check((g as GeometryInstance3D).get_instance_shader_parameter("height_from_origin") == true,
						"%s/%s mesh %s has the parameter on" % [group, kit.name, g.name])
				n += 1
	check(n >= 77, "meshes checked: %d" % n)
