extends "res://tests/case.gd"
## Walkable ground (the Ground plane and the terrain mounds) is on physics layers 1 + 2.
## Grass and the brush ray against layer 2 only; boulders and props are not ground.


func _ray(pg, xz: Vector2, mask := 2) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 40, xz.y), Vector3(xz.x, -5, xz.y), mask)
	return pg.get_world_3d().direct_space_state.intersect_ray(q)


func test_mounds_are_ground(pg) -> void:
	await frames(2)
	var mound: Node3D = pg.get_node("Terrain/Mound1")
	var hit := _ray(pg, Vector2(mound.global_position.x, mound.global_position.z))
	check(not hit.is_empty(), "ray on layer 2 hits Mound1")
	check(hit.get("position", Vector3.ZERO).y > 0.2, "hit is on top of the mound, not the plane")


func test_ground_plane_is_ground(pg) -> void:
	await frames(2)
	check(not _ray(pg, Vector2(0, 0)).is_empty(), "the Ground plane is on layer 2")


func test_boulders_are_not_ground(pg) -> void:
	await frames(2)
	var boulder: Node3D = pg.get_node("Hero/Boulder1")
	var hit := _ray(pg, Vector2(boulder.global_position.x, boulder.global_position.z))
	check(hit.get("position", Vector3.ONE).y < 0.2, "a layer-2 ray passes through boulders to the ground")
