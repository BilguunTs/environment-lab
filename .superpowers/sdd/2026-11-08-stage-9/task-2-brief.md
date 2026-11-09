### Task 2: Ground layer and mound collision

**Files:**
- Modify: `scripts/environment/kit_asset.gd`, `scenes/environment/kit/ground_mound_a.tscn`,
  `ground_mound_b.tscn`, `scenes/playground.tscn` (`Ground` `collision_layer = 3`),
  `project.godot` (`[layer_names] 3d_physics/layer_1="world"`, `3d_physics/layer_2="ground"`)
- Test: `tests/test_ground.gd`

**Interfaces:**
- Produces: `kit_asset.gd` `@export var collision := false`. When true, `_ready` adds a
  `StaticBody3D` named `"Collision"` with one trimesh `CollisionShape3D` per `MeshInstance3D`
  (`mesh.create_trimesh_shape()`, the mesh's global transform), and `collision_layer = 3`. It also
  works in the editor. The body has no owner, so it isn't saved into scenes.
- Produces: the convention that walkable ground = layer 1 + layer 2. Scatter's existing
  `ground_layer = 2` already matches.

- [ ] **Step 1: Write the failing tests:**

```gdscript
func _ray(pg, xz: Vector2, mask := 2) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 40, xz.y), Vector3(xz.x, -5, xz.y), mask)
	return pg.get_world_3d().direct_space_state.intersect_ray(q)

func test_mounds_are_ground(pg) -> void:
	var mound: Node3D = pg.get_node("Terrain/Mound1")
	var hit := _ray(pg, Vector2(mound.global_position.x, mound.global_position.z))
	check(not hit.is_empty(), "ray on layer 2 hits Mound1")
	check(hit.get("position", Vector3.ZERO).y > 0.2, "hit is on top of the mound, not the plane")

func test_ground_plane_is_ground(pg) -> void:
	check(not _ray(pg, Vector2(0, 0)).is_empty(), "the Ground plane is on layer 2")

func test_boulders_are_not_ground(pg) -> void:
	var boulder: Node3D = pg.get_node("Hero/Boulder1")
	var hit := _ray(pg, Vector2(boulder.global_position.x, boulder.global_position.z))
	check(hit.get("position", Vector3.ONE).y < 0.2, "a layer-2 ray passes through boulders to the ground")
```

  Physics needs a frame before the bodies are queryable. Start each test with `await frames(2)`.
- [ ] **Step 2: Run** `--only=ground`. Expected: FAIL on the mound test.
- [ ] **Step 3: Implement** the `collision` flag, set it in both mound kit scenes, set `Ground`
  `collision_layer = 3`, and name the layers.
- [ ] **Step 4: Run** `--only=ground`. Expected: PASS.
- [ ] **Step 5: Manual check.** Walk the player over Mound1 and Mound3. If a mound is too steep
  to walk up, write the outcome in the ledger (steepness is a level design call, not a bug to
  fix here).
- [ ] **Step 6: Checkpoint.** Run the full suite windowed. Expect it to be all green. Then run the
  procedural forest (`forest_mode = "Procedural"`) and confirm trees now sit on the mounds too.

