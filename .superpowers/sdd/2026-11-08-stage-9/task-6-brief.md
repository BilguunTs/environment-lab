### Task 6: Grass painter (GrassBrush + editor plugin)

**Files:**
- Create: `scripts/environment/grass_brush.gd`, `addons/grass_painter/plugin.cfg`,
  `addons/grass_painter/plugin.gd`, `tests/test_grass_brush.gd`
- Modify: `project.godot` (`[editor_plugins] enabled=PackedStringArray("res://addons/grass_painter/plugin.cfg")`),
  `main.md:149` (add one line after it: `Exception (Stage 9, approved): addons/grass_painter, a
  single-purpose grass mask painter. No other editor plugins.`)

**Interfaces:**
- Produces: `class_name GrassBrush extends RefCounted`, with:
  - `var mode := GrassField.PaintMode.DENSITY`, `radius := 3.0`, `strength := 0.3`,
    `target := 1.0`, `falloff := 0.5`
  - `func begin(field: GrassField) -> void`: snapshots `field.mask.duplicate()`
  - `func dab(world_pos: Vector3) -> void`: skipped if within `radius * 0.25` of the previous dab
    in the stroke. Otherwise calls `paint` and then `rebuild(rect)`.
  - `func end() -> Array[Image]`: returns `[before, after]` and clears the stroke
  - `static func ray_to_ground(field: GrassField, from: Vector3, dir: Vector3) -> Variant`:
    returns the hit `Vector3` on `field.ground_layer`, or null
- Plugin (`@tool extends EditorPlugin`), glue only:
  - `_handles(o)` returns `o is GrassField`.
  - The toolbar goes in `CONTAINER_SPATIAL_EDITOR_MENU`: a mode `OptionButton`
    (Density/Height/Erase) and `SpinBox`es for radius (0.5–20), strength (0.05–1) and target
    (0–1).
  - `_forward_3d_gui_input`:
    - Mouse motion moves a brush circle: an `ImmediateMesh` line loop of 48 points following
      `ground_height_at`, editor-only, freed on deselect.
    - LMB press → `begin`, drag → `dab`, release → `end`. **Shift + LMB erases** for that stroke.
    - `[` and `]` scale the radius by 0.8 / 1.25.
    - Consumed LMB events return `AFTER_GUI_INPUT_STOP`.
  - At stroke end:
    - `EditorUndoRedoManager.create_action("Paint grass")` with
      `add_do_method(field, "set_mask_data", after)` and
      `add_undo_method(field, "set_mask_data", before)`, then `commit_action(false)` (already
      applied).
    - If the mask has no `resource_path`, save it next to the edited scene as
      `<scene_name>_grass.res` and assign it. Otherwise `ResourceSaver.save(field.mask)`.

- [ ] **Step 1: Write the failing tests** (same field fixture as Task 3):

```gdscript
func test_dabs_respect_spacing(pg) -> void:
	var b := GrassBrush.new()
	b.strength = 0.2
	b.begin(f)
	b.dab(f.global_position)
	var once := f.sample(Vector2(0, -6)).x
	b.dab(f.global_position + Vector3(0.1, 0, 0))  # closer than radius * 0.25
	check_near(f.sample(Vector2(0, -6)).x, once, 0.001, "a dab too close to the last is skipped")

func test_stroke_undo_restores_mask_and_blades(pg) -> void:
	var b := GrassBrush.new()
	b.strength = 1.0
	b.begin(f)
	for x in range(-4, 5, 2):
		b.dab(f.global_position + Vector3(x, 0, 0))
	var pair := b.end()
	check(pair[0].get_data() != pair[1].get_data(), "stroke changed the mask")
	check(f.blade_count() > 0, "stroke grew blades")
	f.set_mask_data(pair[0])
	check_eq(f.mask.get_data(), pair[0].get_data(), "undo restores the exact mask")
	check_eq(f.blade_count(), 0, "undo removes the blades")

func test_ray_to_ground(pg) -> void:
	var hit = GrassBrush.ray_to_ground(f, Vector3(0, 10, -6), Vector3.DOWN)
	check(hit is Vector3 and absf(hit.y) < 0.05, "brush ray lands on the Ground plane")
	check(GrassBrush.ray_to_ground(f, Vector3(0, 10, -6), Vector3.UP) == null, "ray into the sky misses")
```

- [ ] **Step 2: Run** `--only=grass_brush`. Expected: FAIL.
- [ ] **Step 3: Implement `GrassBrush`**, then the plugin, `plugin.cfg` and its enablement.
- [ ] **Step 4: Run** `--only=grass_brush`. Expected: PASS.
- [ ] **Step 5: Plugin load check.**
  `"$GODOT" --headless --editor --path . --quit-after 300 2>&1 | grep -i -E "error|grass_painter"`.
  Expected: no output mentioning `grass_painter` or `GrassField`.
- [ ] **Step 6: Manual check for the user** (list it in the final handoff): open
  `playground.tscn`, select `Grass`, paint, change height, erase with Shift, Ctrl+Z / Ctrl+Y,
  save, reopen.
- [ ] **Step 7: Checkpoint.** Run the full suite windowed. Expect it to be all green.

