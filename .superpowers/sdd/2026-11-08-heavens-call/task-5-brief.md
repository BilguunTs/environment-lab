### Task 5: War debris and traveller props, staged along the trail

**Files:**
- Modify: `assets/blender/build_kit.py` (new builders and `ASSETS` entries), run through Blender
- Create:
  - `assets/meshes/prop_{shield_broken,sword_planted,helmet,breastplate,spear_broken,scarf_worn}.glb`
  - matching `scenes/environment/kit/*.tscn` (with `kit_asset.gd`)
  - `assets/materials/rusted_metal.tres`, `weathered_wood.tres` (`flat_color` shader)
  - `tests/test_heavens_props.gd`
- Modify: `heavens_call.tscn` (adds `Debris`, `Traces` and `Rocks` groups)

**Interfaces:**
- Consumes: `Trail.point_at`, the kit conventions in `build_kit.py`'s header (1 unit = 1 m, origin
  at base centre, material names = palette names).
- **Props**, low-poly and faceted:
  - `shield_broken`: a round shield with a missing wedge, lying tilted.
  - `sword_planted`: a blade stuck in the ground at an angle, with a bent crossguard.
  - `helmet`: a dented helmet on its side.
  - `breastplate`: a cracked breastplate face down.
  - `spear_broken`: a snapped shaft with its head.
  - `scarf_worn`: a faded blue cloth draped over a rock, using the existing `cloth` material so it
    sways with the wind.
  - None of them include bodies or bones (anti-goal).
- **Staging:**
  - **`Debris`:** 20–30 pieces placed only between progress **0.28 and 0.60**, in small, uneven
    clusters at path edges, ledges and chokepoints. Some sit half-buried. None block the
    walkable corridor.
  - **`Traces`:** 6–10 pieces between **0.60 and 0.95**: kit `prop_cairn` stacks, `scarf_worn`
    and one `prop_fire_ring` at a sheltered ledge.
  - **`Rocks`:** kit boulders and shards along the whole trail.
  - Placement is hand-authored in the scene (node transforms), not scattered.

- [ ] **Step 1: Write the failing tests:**

```gdscript
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
	await frames(2)
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	for i in 140:
		var p: Vector3 = lv.trail.point_at(i / 140.0)
		q.transform = Transform3D(Basis(), p + Vector3.UP * 0.9)
		check(space.intersect_shape(q, 1).is_empty(), "centreline clear at %.3f" % (i / 140.0))
```

- [ ] **Step 2: Run** `--only=heavens_props`. Expected: FAIL.
- [ ] **Step 3: Build the props.** Add the builders and run
  `"/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P assets/blender/build_kit.py`.
  Confirm that the existing GLBs re-export unchanged in look (spot-check one capture), then add
  the kit scenes and materials.
- [ ] **Step 4: Stage** the debris, traces and rocks, then run `--only=heavens`. Expected: all
  PASS.
- [ ] **Step 5: Visual check.** Capture frames at 0.35, 0.5 and 0.8. The debris should read as
  remnants of a battle (no bodies), and the traces as signs of passing people. Ledger it.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

