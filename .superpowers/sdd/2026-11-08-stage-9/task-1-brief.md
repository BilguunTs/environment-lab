### Task 1: Wind gets a direction (Wind node + shared gust field)

**Files:**
- Create: `scripts/environment/wind.gd`, `assets/shaders/wind.gdshaderinc`, `tests/test_wind.gd`
- Modify: `project.godot` (`[shader_globals]`), `assets/materials/flat_color.gdshader:8-39`,
  `scripts/playground.gd` (remove `WIND_DIR`; `_wind`, `_mist_offset`, the `"wind"` param, motes
  gravity), `scenes/playground.tscn` (add a `Wind` node), `scripts/ui/dev_panel.gd:72-75`

**Interfaces:**
- Produces: `class_name Wind extends Node` (`@tool`), with:
  - `const GUST_SPEED := 4.0` (m/s of gust travel at strength 1.0)
  - `@export_range(0, 2) var strength := 0.6` (setter publishes `wind_strength`)
  - `@export_range(0, 360) var direction_degrees := 53.13` (setter publishes `wind_direction`)
  - `var offset := Vector2.ZERO`; `_process` adds `vector() * strength * GUST_SPEED * delta` and
    publishes `wind_offset`. It runs in the editor too.
  - `static func vector_for(degrees: float) -> Vector2`
  - `func vector() -> Vector2`
- Produces, in `assets/shaders/wind.gdshaderinc`: declares the three global uniforms and
  `float wind_gust(vec2 world_xz)`, which returns 0..1. Gusts are irregular patches: two octaves of
  value noise sampled at `world_xz - wind_offset`, stretched so fronts run across the wind, at
  roughly 15–25 m wavelength.
- Produces: playground `@onready var wind: Wind = $Wind`; params `"wind"` (→ `wind.strength`) and
  `"wind_direction"` (→ `wind.direction_degrees`).

- [ ] **Step 1: Write the failing tests** in `tests/test_wind.gd`:

```gdscript
func test_compass_convention(_pg) -> void:
	check(Wind.vector_for(0.0).is_equal_approx(Vector2(0, -1)), "0° blows toward -Z")
	check(Wind.vector_for(90.0).is_equal_approx(Vector2(1, 0)), "90° blows toward +X")
	check(Wind.vector_for(53.13).distance_to(Vector2(0.8, -0.6)) < 0.001, "default = old WIND_DIR")

func test_direction_param_is_state(pg) -> void:
	var i: int = pg.PARAM_ORDER.find("wind_direction")
	check_eq(i, pg.PARAM_ORDER.find("wind") + 1, "wind_direction right after wind")
	check_near(pg.get_param("wind_direction"), 53.13, 0.01, "default direction")
	pg.set_param("wind_direction", 90.0)
	var g: Vector2 = RenderingServer.global_shader_parameter_get("wind_direction")
	check(g.is_equal_approx(Vector2(1, 0)), "global uniform follows the param")
	pg.reset_scene()
	check_near(pg.get_param("wind_direction"), 53.13, 0.01, "reset restores direction")

func test_old_preset_keeps_default_direction(pg) -> void:
	pg.set_param("wind_direction", 200.0)
	pg.apply_preset("Wide Reveal")  # has no wind_direction key
	check_near(pg.get_param("wind_direction"), 53.13, 0.01, "missing key falls back to default")

func test_motes_and_mist_follow_direction(pg) -> void:
	pg.set_param("wind", 1.0)
	pg.set_param("wind_direction", 90.0)
	var gravity: Vector3 = pg.motes.process_material.gravity
	check_near(gravity.x, pg.MOTE_DRIFT, 0.001, "motes pushed toward +X")
	check_near(gravity.z, 0.0, 0.001, "no Z push at 90°")
	var before: Vector3 = pg.mist.material.get_shader_parameter("offset")
	await frames(10)
	var after: Vector3 = pg.mist.material.get_shader_parameter("offset")
	check(after.x < before.x, "mist noise scrolls with the wind (offset decreases along +X)")
	check_near(after.z, before.z, 0.0001, "mist doesn't drift in Z at 90°")

func test_gust_offset_has_no_jump(pg) -> void:
	pg.set_param("wind", 0.5)
	await frames(2)
	var before: Vector2 = pg.wind.offset
	pg.set_param("wind", 2.0)
	pg.set_param("wind_direction", pg.get_param("wind_direction") + 180.0)
	await frames(1)
	check(pg.wind.offset.distance_to(before) < 1.0, "offset keeps integrating; no jump")

func test_no_hardcoded_wind_dir(pg) -> void:
	check(not pg.get_script().get_script_constant_map().has("WIND_DIR"), "WIND_DIR constant removed")
	var src := FileAccess.get_file_as_string("res://assets/materials/flat_color.gdshader")
	check(not src.contains("WIND_DIR"), "flat_color uses wind_direction")
	check(src.contains("wind.gdshaderinc"), "flat_color shares the gust include")
```

- [ ] **Step 2: Run** `--only=wind`. Expected: FAIL (`Wind` not declared, missing param).
- [ ] **Step 3: Implement `Wind`** and the include. Add `wind_direction` and `wind_offset` to
  `[shader_globals]` (the values from Global Constraints). Wrap
  `RenderingServer.global_shader_parameter_set` so it's a no-op when the global doesn't exist.
- [ ] **Step 4: Rewire the playground.** Add a `Wind` node (`strength = 0.6`) to
  `playground.tscn`. `"wind"` and `"wind_direction"` delegate to it. Mist drift and motes gravity
  use `wind.vector()`. Remove `WIND_DIR` and `_wind`, and stop reading
  `ProjectSettings shader_globals/wind_strength` in `_ready`. Keep the `MIST_DRIFT` and
  `MOTE_DRIFT` values.
- [ ] **Step 5: Rewire `flat_color.gdshader`.** `#include "res://assets/shaders/wind.gdshaderinc"`,
  delete its own `wind_strength` declaration and `WIND_DIR`, and replace the `gust` line with
  `wind_gust(world.xz)` (rescaled so the average sway stays close to today's). Bend along
  `wind_direction`. Keep the per-object `wave` term.
- [ ] **Step 6: Panel.** Add `_slider("wind_direction", "Wind direction", 0, 360, 1)` under Wind.
  Change the note to: `Wind drives grass, tree sway, cloth flutter, mist drift and motes.
  Direction is where it blows toward: 0 = into the screen from Gameplay's start, 90 = right. Fire
  and lantern always flicker.` Check that 0° really does point into the screen from Gameplay's
  start and fix the wording if not.
- [ ] **Step 7: Run** `--only=wind`. Expected: all PASS.
- [ ] **Step 8: Visual check.** Run `--capture-views --quit` and compare it with the newest Stage 8
  captures: the trees still sway similarly. Rotate the direction in the running game and confirm
  the trees, cloth, mist and motes all turn together.
- [ ] **Step 9: Checkpoint.** Run the full suite windowed. Expect it to be all green.

