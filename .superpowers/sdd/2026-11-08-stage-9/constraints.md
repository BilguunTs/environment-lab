## Global Constraints

- **Engine:** Godot **4.6**, pure GDScript. No third-party addons, no paid or cloud services. The
  only plugin is `addons/grass_painter/`, and it paints grass masks and nothing else.
- **Style:** tabs, `##` doc comments, typed variables, the existing naming style. Read the
  neighbouring code before writing.
- **No git:** the project is **not** a git repo. Before Task 1, copy `scripts/`, `scenes/`,
  `assets/materials/`, `project.godot`, `README.md`, `main.md` and `docs/` to the session
  scratchpad as a baseline for the final review diff. There are no commit steps; each task ends
  with a full-suite checkpoint.
- **Wind direction:** a compass angle in degrees, `0–360`. It names the direction the wind blows
  **toward**: 0° = toward −Z, 90° = toward +X, clockwise seen from above.
  `vector = Vector2(sin(rad), -cos(rad))`. The default is `53.13`, which equals the old
  `WIND_DIR (0.8, -0.6)`.
- **Global shader uniforms** (`project.godot [shader_globals]`): `wind_strength` (float, 0.6),
  `wind_direction` (vec2, (0.8, −0.6)), `wind_offset` (vec2, (0, 0)).
- **Physics layers:** layer 1 = `"world"`, layer 2 = `"ground"` (name both in `project.godot`).
  Walkable ground is on **both** (`collision_layer = 3`). Grass and the brush ray **only** against
  layer 2.
- **Budget** (dev machine RTX 3070, 1920×1080, measured with the perf HUD's method): grass costs
  ≤ **2.0 ms GPU**, and the whole frame is ≤ **7.0 ms GPU** in the worst named view.
- **Params:** `wind_direction` goes into `PARAM_ORDER` right after `"wind"`; `grass_visible` goes
  right after `"props_visible"`. Both are in presets, Copy settings and A/B.
- **Overlays:** anything drawn over the 3D view joins the group `"overlay"`.

**Test command.** Run it from the project root in Bash. The `--import` step registers new
`class_name`s and must run whenever a task adds one.

```bash
GODOT=/d/softwares/Godot_v4.6-stable_mono_win64/Godot_v4.6-stable_mono_win64_console.exe
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --path . -s res://tests/run.gd                    # full suite, windowed (image tests run)
"$GODOT" --path . -s res://tests/run.gd -- --only=grass    # files whose name contains "grass"
"$GODOT" --headless --path . -s res://tests/run.gd         # logic only, image tests SKIP
```

Exit code 0 means everything passed. **Baseline before Task 1:** 47 passed windowed. Record the
actual number in the ledger. Every later checkpoint must be all green.

## Review Focus

1. **A wind slider dragged fast, or the direction swung 180°.** The grass and trees turn smoothly,
   with no jump in the gust pattern, because the offset is integrated and never derived from
   `TIME × speed`. Test: `test_gust_offset_has_no_jump` (Task 1).
2. **Painting off the field's edge, or with a brush bigger than the field.** Only in-bounds texels
   change, with no error or out-of-range write. Test: `test_paint_clips_at_field_edge` (Task 3).
3. **A blade over a hole in the ground** (no hit on layer 2, such as off the Ground plane or over a
   boulder that isn't ground). It gets no blade; it doesn't sit at y = 0 or on top of the boulder.
   Tests: `test_boulders_are_not_ground` (Task 2) and `test_no_blades_where_ground_missing`
   (Task 3).
4. **Undo after a stroke that was painted and then rebuilt.** One Ctrl+Z restores the exact
   previous mask and blades. Test: `test_stroke_undo_restores_mask_and_blades` (Task 6).
5. **A hand-edited preset with `"wind_direction": "north"`, or an old preset without the key.**
   The bad value is skipped with a note; a missing key falls back to the default. Tests:
   `test_wrong_typed_preset_value_is_skipped` (Task 9) and `test_old_preset_keeps_default_direction`
   (Task 1).

