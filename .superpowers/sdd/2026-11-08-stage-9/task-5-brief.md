### Task 5: Grass in the playground (starter field, `grass_visible`)

**Files:**
- Create: `tools/make_starter_grass.gd` (`extends SceneTree`, run once),
  `assets/grass/playground_grass.res` (its output), `tests/test_grass_scene.gd`
- Modify: `scenes/playground.tscn` (a `Grass` `GrassField` at `(0, 0, 6)`,
  `extent = Vector2(74, 104)`, `mask` = the `.res` file), `scripts/playground.gd`
  (`grass_visible` param, `@onready var grass: GrassField = $Grass`), `scripts/ui/dev_panel.gd`
  (an Environment check box "Grass")

**Interfaces:**
- Consumes: `GrassField.paint/ensure_mask`, and `Scatter`'s path data via the path nodes'
  `get_centerline_world()` and `width`.
- Starter mask rules:
  - Density 0 within `path half-width + 1.0 m` of every path centreline (Path and SideTrail).
    It ramps to full by +3 m. Patchy with `FastNoiseLite` (seed 9, ~12 m wavelength) between 0.4
    and 1.0.
  - Density 0 inside the Clearing floor radius.
  - Height 0.3 near the path, rising to 0.9 at 15 m away, with gentle noise.
  - Saved with `ResourceSaver.save(mask, "res://assets/grass/playground_grass.res")`.

- [ ] **Step 1: Write the failing tests:**

```gdscript
func test_playground_has_grass(pg) -> void:
	await frames(2)
	check(pg.grass.mask != null and pg.grass.mask.resource_path.ends_with("playground_grass.res"), "mask loaded from file")
	check(pg.grass.blade_count() > 10000, "the starter field is populated")

func test_grass_visible_param(pg) -> void:
	check_eq(pg.PARAM_ORDER.find("grass_visible"), pg.PARAM_ORDER.find("props_visible") + 1, "param order")
	pg.set_param("grass_visible", false)
	check(not pg.grass.visible, "toggle hides the field")
	pg.reset_scene()
	check(pg.grass.visible, "default is on")

func test_path_is_clear_of_grass(pg) -> void:
	var pts: PackedVector2Array = pg.get_node("Path").get_centerline_world()
	for p in pts:
		check_near(pg.grass.sample(p).x, 0.0, 0.01, "no grass on the path centreline")

func test_grass_on_mounds(pg) -> void:
	var m: Node3D = pg.get_node("Terrain/Mound1")
	check(pg.grass.ground_height_at(Vector2(m.global_position.x, m.global_position.z)) > 0.2, "cache sees the mound")
```

- [ ] **Step 2: Run** `--only=grass_scene`. Expected: FAIL.
- [ ] **Step 3: Implement.** Write and run the starter script, add the node, param and panel
  check box. Running it:
  `"$GODOT" --headless --path . -s res://tools/make_starter_grass.gd`.
- [ ] **Step 4: Run** `--only=grass_scene`. Expected: PASS.
- [ ] **Step 5: Visual check.** Run `--capture-views --quit` and look at every view. Grass frames
  the path, doesn't bury it, and sits on the mounds. Read the perf HUD in the busiest view with
  grass on and off, and write both numbers in the ledger. Task 7 tunes against the budget; only
  stop early if the frame is far over 7 ms.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed. Expect it to be all green.

