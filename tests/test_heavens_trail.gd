extends "res://tests/case.gd"
## Heavens call trail and mountain: length, grade, ground under the trail, progress and fall respawn.

const SCENE := "res://scenes/levels/heavens_call.tscn"


func test_trail_length_and_walk_time(lv) -> void:
	var l: float = lv.trail.length()
	check(l >= 650.0 and l <= 750.0, "trail 650-750 m, got %.0f" % l)
	var t: float = l / lv.player.walk_speed
	check(t >= 300.0 and t <= 420.0, "walk time 5-7 min, got %.0f s" % t)


func test_trail_grade_walkable(lv) -> void:
	var worst := 0.0
	for i in 400:
		var a: Vector3 = lv.trail.point_at(i / 400.0)
		var b: Vector3 = lv.trail.point_at((i + 1) / 400.0)
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		worst = maxf(worst, rad_to_deg(atan2(absf(b.y - a.y), run)))
	check(worst <= 30.0, "steepest trail grade <= 30 deg, got %.1f" % worst)


func test_terrain_matches_trail(lv) -> void:
	await frames(2)
	for i in 50:
		var p: Vector3 = lv.trail.point_at(i / 50.0)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20, p + Vector3.DOWN * 20, 2)
		var hit: Dictionary = lv.get_world_3d().direct_space_state.intersect_ray(q)
		check(not hit.is_empty() and absf(hit.position.y - p.y) < 0.6, "ground on layer 2 under the trail at %d" % i)


func test_progress_is_monotonic_along_trail(lv) -> void:
	check_near(lv.trail.progress_at(lv.trail.point_at(0.0)), 0.0, 0.01, "foot = 0")
	check_near(lv.trail.progress_at(lv.trail.point_at(0.5)), 0.5, 0.01, "middle = 0.5")
	check_near(lv.trail.progress_at(lv.trail.point_at(1.0)), 1.0, 0.01, "summit = 1")


func test_fall_respawns_on_trail(lv) -> void:
	lv.furthest_progress = 0.4
	lv.player.global_position = lv.trail.point_at(0.4) + Vector3(0, -40, 0)
	await physics_frames(3)
	check(lv.player.global_position.distance_to(lv.trail.point_at(0.4)) < 2.5, "put back at furthest point")
	check_near(lv.furthest_progress, 0.4, 0.001, "progress not reset by the fall")
