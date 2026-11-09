### Task 2: Trail and mountain terrain

**Files:**
- Create: `scripts/levels/trail.gd`, `scripts/levels/mountain_terrain.gd`,
  `tests/test_heavens_trail.gd`
- Modify: `scenes/levels/heavens_call.tscn` (replace the placeholder ground), `heavens_call.gd`
  (respawn)

**Interfaces:**
- Produces:
  - **`class_name Trail extends Path3D` (`@tool`):**
    - The `curve` (Curve3D) is the authored trail centreline, from the foot (offset 0) to the
      summit.
    - `@export var width := 3.0`
    - `func length() -> float`
    - `func progress_at(world_pos: Vector3) -> float`: closest point's offset / length, 0..1
    - `func point_at(progress: float) -> Vector3`
    - `func distance_to_centre(world_pos: Vector3) -> float`: horizontal distance
  - **`class_name MountainTerrain extends Node3D` (`@tool`):**
    - `@export var trail: Trail` and `@export var extent := Vector2(360, 360)` (centred on the
      node)
    - `@export var cell := 1.5`, `@export var seed := 7`
    - `@export var corridor := 9.0` (walkable half-width): within it, height follows the trail's
      height across the corridor with a gentle cross-slope. Beyond it, it rises or falls into
      steep rock (cliffs ≥ 50°) so the corridor is bounded, plus noise.
    - `@export var trail_color`, `rock_color`: the vertex colour lerps from trail to rock between
      `trail.width * 0.5` and `width * 0.5 + 1.5` m from the centre.
    - It builds one `ArrayMesh` (faceted, using the `flat_color`-style per-face normals) and a
      `StaticBody3D` with a trimesh, `collision_layer = 3`, as internal children with no owner.
    - `func rebuild() -> void`, `func height_at(xz: Vector2) -> float`
  - **`HeavensCall`:**
    - `var furthest_progress := 0.0`, updated each physics frame from
      `trail.progress_at(player.global_position)`, and only ever increasing
    - `func respawn() -> void`: puts the player at `trail.point_at(furthest_progress) + Vector3.UP`
      and zeroes her velocity. It's called when the player's y is below
      `trail.point_at(progress).y - 15.0`.
- **Authoring:**
  - The curve is about 700 m long, climbing about 220 m with switchbacks, ledges and a few narrow
    chokepoints.
  - The summit is a broad flat-topped ridge at the curve's end, about 40 × 25 m, open on the
    vista side.
  - Steepest grade along the trail ≤ 30°.

- [ ] **Step 1: Write the failing tests:**

```gdscript
const SCENE := "res://scenes/levels/heavens_call.tscn"

func test_trail_length_and_walk_time(lv) -> void:
	var l: float = lv.trail.length()
	check(l >= 650.0 and l <= 750.0, "trail 650-750 m, got %.0f" % l)
	var t := l / lv.player.walk_speed
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
	await frames(3)
	check(lv.player.global_position.distance_to(lv.trail.point_at(0.4)) < 2.5, "put back at furthest point")
	check_near(lv.furthest_progress, 0.4, 0.001, "progress not reset by the fall")
```

- [ ] **Step 2: Run** `--only=heavens_trail`. Expected: FAIL.
- [ ] **Step 3: Implement** `Trail` and `MountainTerrain`, author the curve, wire progress and
  respawn, and place the player at `point_at(0)`.
- [ ] **Step 4: Run** `--only=heavens`. Expected: all PASS.
- [ ] **Step 5: Visual check.** Fly or walk the trail (temporary capture script, deleted after).
  Check that it reads as a narrow mountain trail with cliffs and a ridge summit. Write the result
  in the ledger.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

