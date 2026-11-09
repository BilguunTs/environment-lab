# Task 1 report: Wind gets a direction

## Implemented
- `scripts/environment/wind.gd`: `@tool class_name Wind extends Node` with GUST_SPEED, `strength`, `direction_degrees`, integrated `offset`, `vector_for()`, `vector()`. Setters and `_process` publish globals; `_publish` is a no-op unless `ProjectSettings.has_setting("shader_globals/<name>")`.
- `assets/shaders/wind.gdshaderinc`: declares the 3 globals + `wind_gust(vec2)` (two value-noise octaves at `world_xz - wind_offset`, ~20 m along x ~40 m across the wind, remapped to 0..1).
- `project.godot`: `wind_direction` (vec2 0.8,-0.6) and `wind_offset` (vec2 0,0) globals.
- `flat_color.gdshader`: includes the gust file, removed its own wind_strength decl and WIND_DIR, `gust = 0.1 + 0.9 * wind_gust(world.xz)` (average ~0.55 like before), bends along `wind_direction`; per-object `wave` kept.
- `playground.gd`: WIND_DIR, `_wind` and the ProjectSettings read removed; `@onready var wind: Wind = $Wind`; `wind_direction` in PARAM_ORDER right after `wind`; get/set delegate to Wind; mist drift and motes gravity (new `_update_mote_gravity()`, also called in `_ready`) use `wind.vector()`.
- `scenes/playground.tscn`: `Wind` node (strength 0.6).
- `dev_panel.gd`: "Wind direction" slider 0..360 + new note text. Verified 0 deg points into the screen at Gameplay start (follow camera sits at +Z, yaw 0, looks toward -Z), so wording stands.
- `tests/test_wind.gd`: the 6 tests from the brief.

## TDD
- RED: `--only=wind` -> `Identifier "Wind" not declared` ... `FAIL test_wind.gd (does not parse)`, 0 passed, 1 failed.
- GREEN: `--only=wind` -> 6 passed, 0 failed, 0 skipped.
- Full windowed suite: **62 passed, 0 failed, 0 skipped** (baseline 56 + 6).

## Deviation from the brief (test)
`RenderingServer.global_shader_parameter_get` is editor-only and raises an engine error in a running game (the runner fails tests on that). So in `test_direction_param_is_state` I replaced the global readback with `pg.wind.vector().is_equal_approx(Vector2(1, 0))`. Same reason `_publish` uses `ProjectSettings.has_setting` rather than `global_shader_parameter_get_list` (also editor-only). Consequence: no test directly verifies the published global values.

## Visual check
`--capture-views --quit` ran clean (no shader/script errors); forest_gate capture (screenshots/2026-11-08T11-26-45_forest_gate.png) renders trees, cloth, mist, motes normally. Statically sway amplitude is expected similar (avg gust ~0.55). I could not capture a rotated-direction pair: a scratch SceneTree script with `-s` hung (killed), so I did not verify the turn visually; direction rotation is covered by the logic tests (mist offset sign, motes gravity, vector).

## Self-review / concerns
- Gust noise remap constants (0.2/0.6) are eyeballed; the tree sway average is approximate, not measured.
- `wind_hash` etc. are namespaced in the include to avoid clashing with flat_color's own `hash`.
- Wind `_process` runs in the editor too (as specified) but only publishes if the global exists.
- Existing presets set `wind` but not `wind_direction`; missing key falls back to default via default-state layering (tested).
