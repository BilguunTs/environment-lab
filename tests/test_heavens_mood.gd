extends "res://tests/case.gd"
## Heavens call mood and storm: keys per stretch, blending by furthest progress, distant lightning,
## plus the level's camera terrain collision and the walk-back-down rule.

const SCENE := "res://scenes/levels/heavens_call.tscn"


func test_keys_ordered_and_shaped(_lv) -> void:
	var at := []
	for k in MoodDirector.KEYS: at.append(k.at)
	check_eq(at, [0.0, 0.28, 0.57, 0.86], "stretch boundaries")
	check_eq(MoodDirector.KEYS[0].lightning_per_min, 0.0, "no lightning in ascent")
	check_eq(MoodDirector.KEYS[1].lightning_per_min, 0.0, "no lightning in discovery")
	check(MoodDirector.KEYS[2].lightning_per_min > 0.0, "lightning in eerie")
	check(MoodDirector.KEYS[0].vol_eerie == 0.0 and MoodDirector.KEYS[1].vol_eerie == 0.0, "eerie ambience only from stretch 3")
	check(MoodDirector.KEYS[3].wind > MoodDirector.KEYS[0].wind, "wind builds")


func test_sample_blends_between_keys(_lv) -> void:
	var a: float = MoodDirector.sample(0.28).wind
	var b: float = MoodDirector.sample(0.57).wind
	var mid: float = MoodDirector.sample(0.425).wind
	check(mid > minf(a, b) - 0.001 and mid < maxf(a, b) + 0.001, "blend stays between keys")


func test_mood_ignores_backtracking(lv) -> void:
	lv.player.global_position = lv.trail.point_at(0.7)
	await physics_frames(3)
	var w: float = lv.mood.current.wind
	lv.player.global_position = lv.trail.point_at(0.1)
	await physics_frames(3)
	check_near(lv.mood.current.wind, w, 0.001, "walking back down keeps the mood")


func test_no_lightning_before_eerie(lv) -> void:
	lv.player.global_position = lv.trail.point_at(0.4)
	await physics_frames(2)
	check_eq(lv.storm.rate_per_min, 0.0, "storm silent in discovery")


func test_flash_schedules_distant_thunder(lv) -> void:
	var delays := []
	lv.storm.flashed.connect(func(d: float) -> void: delays.append(d))
	lv.storm.flash()
	await frames(1)
	check(delays.size() == 1 and delays[0] >= 2.5 and delays[0] <= 6.0, "thunder 2.5-6 s after flash")


## The mood follows the furthest point reached: at 0.7 it is the eerie blend, and the storm runs.
func test_mood_follows_furthest_progress(lv) -> void:
	lv.furthest_progress = 0.7
	await frames(2)
	var want: Dictionary = MoodDirector.sample(0.7)
	check_near(lv.mood.current.wind, want.wind, 0.001, "mood applied from furthest progress")
	check_near(lv.storm.rate_per_min, want.lightning_per_min, 0.001, "storm rate from the mood")
	check_near(lv.wind.strength, want.wind, 0.001, "Wind node driven by the mood")


func test_reset_clears_mood_and_storm(lv) -> void:
	lv.furthest_progress = 0.7
	await frames(2)
	lv.storm.flash()
	lv.reset_scene()
	check_eq(lv.storm.flash_count, 0, "flash count reset")
	check_near(lv.mood.current.wind, MoodDirector.KEYS[0].wind, 0.001, "mood back at the ascent key")
	check_eq(lv.storm.rate_per_min, 0.0, "storm silent after reset")


func test_walking_down_never_respawns(lv) -> void:
	lv.furthest_progress = 0.6
	var spot: Vector3 = lv.trail.point_at(0.3) + Vector3.UP
	lv.player.global_position = spot
	await physics_frames(4)
	check(lv.player.global_position.distance_to(spot) < 1.0, "she stays where she walked down to")
	check_near(lv.furthest_progress, 0.6, 0.001, "furthest progress kept")


## Ruling 3: with the camera goal behind the mountain, the camera pulls in to the near side.
func test_camera_stays_out_of_terrain(lv) -> void:
	var cam: FollowCamera = lv.follow_cam
	check_eq(cam.collision_mask, 2, "level camera collides with the ground layer")
	lv.player.global_position = lv.trail.point_at(0.3) + Vector3.UP
	cam.pitch_deg = 0.0
	cam.distance = 25.0
	cam.snap()
	await frames(2)
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var pivot: Vector3 = lv.player.global_position + Vector3.UP * cam.height
	# Find a yaw whose uncollided goal lies behind a terrain wall.
	var blocked_yaw := INF
	for i in 36:
		var yaw := i * 10.0
		var off := Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0)) * Vector3.BACK * cam.distance
		var q := PhysicsRayQueryParameters3D.create(pivot, pivot + off, 2)
		if not space.intersect_ray(q).is_empty():
			blocked_yaw = yaw
			break
	check(blocked_yaw != INF, "found a camera direction blocked by the mountain")
	if blocked_yaw == INF:
		return
	cam.yaw_deg = blocked_yaw
	await frames(20)
	pivot = lv.player.global_position + Vector3.UP * cam.height
	var q2 := PhysicsRayQueryParameters3D.create(pivot, cam.global_position, 2)
	check(space.intersect_ray(q2).is_empty(), "no ground between her and the camera")
	check(cam.global_position.distance_to(pivot) < cam.distance - 0.5, "camera pulled in")
	cam.distance = 7.0
	cam.pitch_deg = 14.0


## Ruling 5: lightning and eerie sound switch in only after EERIE starts and are gone at the summit.
func test_gated_values_respect_stretch_edges(_lv) -> void:
	check_eq(MoodDirector.sample(0.56).lightning_per_min, 0.0, "no lightning just before EERIE")
	check_eq(MoodDirector.sample(0.56).vol_eerie, 0.0, "no eerie ambience just before EERIE")
	check_eq(MoodDirector.sample(0.62).lightning_per_min, MoodDirector.KEYS[2].lightning_per_min, "full EERIE lightning once ramped in")
	check_eq(MoodDirector.sample(0.95).lightning_per_min, 0.0, "no lightning on the summit stretch")


## The wind wobble turns the gust field about the world origin: at the trail's 150 m radius the
## sideways slide must stay well under the gusts' own downwind travel, or grass gusts skate.
func test_wind_wobble_slide_is_slow(_lv) -> void:
	for k in MoodDirector.KEYS:
		var slide: float = 150.0 * deg_to_rad(k.wind_swing_deg) * TAU / MoodDirector.SWING_PERIOD
		var travel: float = Wind.GUST_SPEED * k.wind
		check(slide < 0.25 * travel, "at %.2f slide %.2f m/s < quarter of gust travel %.2f m/s" % [k.at, slide, travel])
