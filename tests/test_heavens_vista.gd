extends "res://tests/case.gd"
## Heavens call summit vista (Task 6): the far world hidden until `reveal` opens it, the ovoos on
## the summit, golden grass at the top and sparse tufts along the trail.

const SCENE := "res://scenes/levels/heavens_call.tscn"


func test_vista_hidden_until_reveal(lv) -> void:
	check_eq(lv.vista.reveal, 0.0, "vista hidden on start")


func test_ovoos_on_summit(lv) -> void:
	var ovoos: Array = lv.vista.get_node("Ovoos").get_children()
	check_eq(ovoos.size(), 3, "three ovoos")
	for o: Node3D in ovoos:
		check(lv.trail.progress_at(o.global_position) >= 0.9, "ovoo near the summit")


func test_summit_grass_is_golden_and_waving(lv) -> void:
	var g: GrassField = lv.get_node("Grass/Summit")
	check(g.blade_count() > 2000, "summit field populated")
	check(g.tip_color.r > g.tip_color.b + 0.15, "golden tips")


## Ruling 2: each trail field is sampled at the trail centre point nearest its own centre, and
## that point must lie inside the field, so the check can't pass on an empty sample.
func test_trail_grass_is_sparse(lv) -> void:
	var trail_fields := 0
	for g: GrassField in lv.get_node("Grass").get_children():
		if g.name == "Summit":
			continue
		trail_fields += 1
		var c := Vector2(g.global_position.x, g.global_position.z)
		var best := Vector3.ZERO
		var best_d := INF
		for i in 2001:
			var p: Vector3 = lv.trail.point_at(i / 2000.0)
			var d := Vector2(p.x, p.z).distance_to(c)
			if d < best_d:
				best_d = d
				best = p
		var corner := c - g.extent * 0.5
		var inside := Rect2(corner, g.extent).has_point(Vector2(best.x, best.z))
		check(inside, "%s: the nearest trail point lies inside the field" % g.name)
		var on_path: float = g.sample(Vector2(best.x, best.z)).x
		check(on_path < 0.05, "%s keeps the gravel centre clear" % g.name)
		check(g.blade_count() > 0, "%s has tufts" % g.name)
	check(trail_fields >= 3 and trail_fields <= 5, "3-5 trail sections, got %d" % trail_fields)


## Trail masks stay sparse (mostly 0.1-0.35, never a meadow); the summit is dense (0.6-0.9).
## Every mask was generated at its field's size, so nothing gets stretched.
func test_grass_masks_fit_their_fields(lv) -> void:
	for g: GrassField in lv.get_node("Grass").get_children():
		check(g.mask != null, "%s has a mask" % g.name)
		if g.mask == null:
			continue
		check_eq(g.mask.get_size(), g.mask_size(), "%s mask size" % g.name)
		var data: PackedByteArray = g.mask.get_data()
		var top := 0
		for i in range(0, data.size(), 2):
			top = maxi(top, data[i])
		if g.name == "Summit":
			check(top >= roundi(0.6 * 255) and top <= roundi(0.9 * 255) + 1, "summit density peaks at %.2f" % (top / 255.0))
		else:
			check(top <= roundi(0.45 * 255), "%s density peaks at %.2f" % [g.name, top / 255.0])


## Every kit piece of the ovoos sways and shades from its own origin (Task 5's rule).
func test_ovoo_kit_measures_from_origin(lv) -> void:
	var n := 0
	for ovoo: Node3D in lv.vista.get_node("Ovoos").get_children():
		var posts := 0
		var cairns := 0
		for kit: Node3D in ovoo.get_children():
			check(kit.height_from_origin, "%s/%s opts in" % [ovoo.name, kit.name])
			if kit.scene_file_path.ends_with("prop_khadag_post.tscn"):
				posts += 1
			elif kit.scene_file_path.ends_with("prop_cairn.tscn"):
				cairns += 1
				check(kit.scale.y >= 1.5 and kit.scale.y <= 2.5, "%s cairn scaled 1.5-2.5x" % ovoo.name)
			for g in kit.find_children("*", "GeometryInstance3D", true, false):
				check((g as GeometryInstance3D).get_instance_shader_parameter("height_from_origin") == true,
						"%s/%s mesh %s has the parameter on" % [ovoo.name, kit.name, g.name])
				n += 1
		check_eq(cairns, 1, "%s has one cairn" % ovoo.name)
		check(posts >= 2 and posts <= 4, "%s has 2-4 khadag posts" % ovoo.name)
	check(n >= 9, "meshes checked: %d" % n)


## The far world (steppe, ridges, mist sea) only exists once the reveal has started, so it can't
## show through the fog on the climb.
func test_far_vista_only_while_revealing(lv) -> void:
	check(not lv.vista.far.visible, "far vista hidden at reveal 0")
	lv.vista.reveal = 0.3
	check(lv.vista.far.visible, "far vista shown once revealing")


## At the summit, reveal opens the mood's fog and the mist without fighting the mood: back at 0
## the mood's own values return.
func test_reveal_opens_the_fog(lv) -> void:
	lv.player.global_position = lv.trail.point_at(1.0) + Vector3.UP
	await physics_frames(2)
	var env: Environment = lv.get_node("WorldEnvironment").environment
	var closed_fog := env.fog_density
	var closed_mist: float = lv.mist.material.get_shader_parameter("density")
	check_near(closed_fog, lv.mood.current.fog_density, 0.0001, "reveal 0 leaves the mood's fog alone")
	lv.vista.reveal = 1.0
	await physics_frames(1)
	check(env.fog_density < closed_fog * 0.1, "reveal 1 opens the summit fog (%.5f)" % env.fog_density)
	check(env.volumetric_fog_density < closed_fog * 0.1, "and the volumetric fog")
	check(lv.mist.material.get_shader_parameter("density") < closed_mist * 0.3, "and the ground mist")
	lv.vista.reveal = 0.0
	await physics_frames(1)
	check_near(env.fog_density, closed_fog, 0.0001, "closing the reveal restores the mood's fog")


## The square massif's outer edge (and its -200 m skirt) sits under the steppe everywhere, while
## the whole trail stays above it.
func test_steppe_buries_the_terrain_edge(lv) -> void:
	var t: MountainTerrain = lv.terrain
	var half: Vector2 = t.extent * 0.5 - Vector2.ONE * t.cell
	var lowest_margin := INF
	for i in 241:
		var s := -1.0 + i / 120.0
		for xz: Vector2 in [Vector2(s * half.x, -half.y), Vector2(s * half.x, half.y), Vector2(-half.x, s * half.y), Vector2(half.x, s * half.y)]:
			var w := xz + Vector2(t.global_position.x, t.global_position.z)
			lowest_margin = minf(lowest_margin, lv.vista.steppe_height_at(w) - t.height_at(w))
	check(lowest_margin > 1.0, "steppe above the terrain edge everywhere (min margin %.2f m)" % lowest_margin)
	for i in 401:
		var p: Vector3 = lv.trail.point_at(i / 400.0)
		var below: float = p.y - lv.vista.steppe_height_at(Vector2(p.x, p.z))
		if below < 1.0:
			check(false, "trail at %.3f is %.2f m above the steppe" % [i / 400.0, below])
			break


## The steppe is huge and well below the summit, the ridges stand in three rings between 600 and
## 2500 m, and the gameplay camera sees out to the horizon.
func test_vista_reaches_the_horizon(lv) -> void:
	var v: Vista = lv.vista
	check(v.steppe_radius >= 3000.0, "steppe radius %.0f" % v.steppe_radius)
	var drop: float = lv.trail.point_at(1.0).y - v.steppe_y
	check(drop >= 150.0 and drop <= 250.0, "steppe %.0f m below the summit" % drop)
	check_eq(v.ring_radii.size(), 3, "three ridge rings")
	for r: float in v.ring_radii:
		check(r >= 600.0 and r <= 2500.0, "ring at %.0f m" % r)
	check(lv.follow_cam.far >= v.horizon_distance(), "camera far %.0f reaches the horizon" % lv.follow_cam.far)


func test_reset_closes_the_vista(lv) -> void:
	lv.vista.reveal = 1.0
	lv.reset_scene()
	check_eq(lv.vista.reveal, 0.0, "reset closes the vista")
