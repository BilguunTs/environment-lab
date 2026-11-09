extends "res://tests/case.gd"
## The playground's kit pieces keep flat_color's world-height sway and contact shade:
## height_from_origin is a per-instance opt-in for the Heavens call mountain.


func test_playground_kit_keeps_world_height(pg) -> void:
	var kits: Array = pg.find_children("*", "Node3D", true, false).filter(
			func(n: Node) -> bool: return n.get_script() != null and n.get_script().resource_path.ends_with("kit_asset.gd"))
	check(kits.size() > 10, "playground has kit pieces: %d" % kits.size())
	for kit: Node3D in kits:
		check(not kit.height_from_origin, "%s stays on world height" % kit.name)
		for g in kit.find_children("*", "GeometryInstance3D", true, false):
			check((g as GeometryInstance3D).get_instance_shader_parameter("height_from_origin") != true,
					"%s mesh %s has no origin-height parameter" % [kit.name, g.name])
