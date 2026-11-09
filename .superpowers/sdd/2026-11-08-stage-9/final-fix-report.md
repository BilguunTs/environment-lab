## Final fix wave

### I1 — gust pattern jump on direction change
- `scripts/environment/wind.gd`: `offset: Vector2` replaced by `phase: float` (l.32), integrated as
  `phase = fposmod(phase + strength * GUST_SPEED * delta, PHASE_PERIOD)` (l.42) and published as
  `wind_phase`. New consts `GUST_CELL_ALONG/ACROSS` (20/40 m) and `PHASE_PERIOD := 2000.0` (l.19).
  New `static func pattern_coord(world_xz, direction, gust_phase)` (l.54) mirrors the shader's `q`.
- `assets/shaders/wind.gdshaderinc`: global `float wind_phase` (l.5); `wind_value_noise(p, period)`
  hashes `mod(i.x, period)` so the noise is periodic along the wind (l.12-19); `wind_gust` computes
  `q = ((dot(world, along) - wind_phase)/20, dot(world, across)/40)` (l.30), octave periods 100 and
  230 cells = 2000 m in each octave's cells, so the phase wrap is invisible. Same scales as before.
- `project.godot [shader_globals]`: `wind_offset` (vec2) -> `wind_phase` (float, 0.0).
- Consumers: grass.gdshader and flat_color.gdshader only call `wind_gust` (unchanged). Playground
  mist/motes integrate their own drift from `wind.vector()` (3D noise offset, not projected on the
  current direction, so no jump) — unchanged. No other `wind_offset`/`Wind.offset` users.
- Tests (`tests/test_wind.gd`): `test_gust_offset_has_no_jump` (l.41, name kept for the Review Focus
  reference) now runs 600 s of default wind via `_process(1.0)`, then a 1° step, and asserts the
  sample point's pattern coord moves < 0.1 cell. `test_gust_phase_advance` (l.54) asserts
  advance = strength*GUST_SPEED*delta, the wrap rebases into [0, PERIOD), and PERIOD is a whole number
  of cells. Written first; failed (parse: `phase`, `pattern_coord`, `PHASE_PERIOD` missing), then
  passed. With the old math the same scenario moves q by |offset|·sin1°/40 = 1440·0.01745/40 ≈ 0.63
  cell (> 0.1); couldn't run that literally since the old API had no pattern helper.
- No smoothing added (controller ruling).

### I2 — duplicated GrassField shares its mask file
- `scripts/environment/grass_brush.gd:79` `static func mask_needs_fork(mask, scene_path, other_masks)`:
  true if another field in the scene holds the same Image object, or the mask's file isn't the
  scene's: file name must start with `<scene basename>_grass` (any folder, so
  `res://assets/grass/playground_grass.res` still belongs to `scenes/playground.tscn`), or an embedded
  `scene.tscn::id` path must name this scene. Unsaved mask / unknown scene -> no fork.
- `addons/grass_painter/plugin.gd:116` calls `_fork_shared_mask(_field)` before `_brush.begin`;
  `_fork_shared_mask` (l.163) walks the edited scene for other GrassFields and, if needed, sets
  `field.mask = field.mask.duplicate()` (no path) so `_save_mask` writes a new `<scene>_grass[_N].res`.
  Undo: the stroke's undo/redo act on the forked mask (set_mask_data copies into it) and re-save its
  file; the original file is never written. The fork itself is not undone (field keeps its copy).
- Test `tests/test_grass_brush.gd:54 test_shared_mask_needs_fork` (10 checks incl. the real
  playground mask). Written first; failed (parse: function missing), then passed.

### I3 — REUSE.md
- `docs/REUSE.md`: adds `assets/meshes/` (.glb for kit scenes); names the three `project.godot`
  sections with their exact entries (`[shader_globals]` incl. `wind_phase` float, `[layer_names]`
  `3d_physics/layer_1/2`, `[editor_plugins]`); step 1 names `strength` and `direction_degrees`;
  step 3 warns that changing `extent`/`texel_size` after painting stretches the mask; steps 4-5 say
  save the scene before the first stroke, the plugin saves `<scene>_grass.res` after every stroke,
  duplicates get `_grass_2.res`, and list the toolbar controls incl. falloff.

### I4 — Falloff control
- `addons/grass_painter/plugin.gd:286` Falloff SpinBox (0-1, step 0.05, default `_brush.falloff`
  = 0.5), `_on_falloff_changed` (l.310) sets `GrassBrush.falloff`; `_falloff_box` member added.
- README painter table: "radius, strength, target and falloff".

### M4 — README
- README "Wind sway on materials": describes the `Wind` node publishing `wind_strength`,
  `wind_direction`, `wind_phase` (`[shader_globals]`), set by the Wind / Wind direction sliders.
- The 114-char direction line (it was l.169 in the current file) wrapped to <=100 like its
  neighbours. Mask paragraph also says: save scene first; duplicates get their own mask copy.

### Verification
- `--import`, then windowed suite: **96 passed, 0 failed, 0 skipped** (exit 0; was 94 + 2 new).
- Headless suite: **74 passed, 0 failed, 22 skipped** (exit 0; was 72 + 2 new).
  Only error lines in the log are the presets/PNG tests' deliberate, expected errors.
- `--capture-views --quit`: looked at `screenshots/2026-11-08T12-26-18_clearing.png` and
  `..._forest_gate.png` — trees, banners and grass render and lean normally; the windowed
  `test_wind_moves_the_grass` / `test_direction_moves_the_grass` image tests pass.
- Editor load check `--headless --editor --quit-after 300 | grep -i -E "error|grass_painter"`: no output.

### Deviations
- I1 test name kept as `test_gust_offset_has_no_jump` (constraints Review Focus 1 references it),
  though it now checks the phase-based pattern.
- Historical docs `docs/superpowers/plans|specs/2026-11-08-stage-9*.md` and `constraints.md` still
  say `wind_offset`; left as the record of the original plan. Live docs (README, REUSE,
  project.godot, code comments) all say `wind_phase`.
- The fork in I2 is not part of the undo action (deliberate: avoids reordering risk in UndoRedo;
  the original file stays intact either way).

### Concerns
- The plugin fork path itself (`_fork_shared_mask` + save) is only verified by the static helper
  test and the editor load check; an in-editor Ctrl+D -> paint check by hand is still worthwhile.
- The gust pattern now repeats every 2000 m along the wind (invisible at playground scale), and it
  rotates about the world origin on a direction change, so far from the origin a 1° step moves it
  by distance·sin1° (e.g. 0.04 cell at 50 m, 0.4 cell at 500 m).
