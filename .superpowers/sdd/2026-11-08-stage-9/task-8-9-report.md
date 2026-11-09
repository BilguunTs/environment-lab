# Tasks 8 + 9: Stage 8 leftovers

Status: DONE. Full windowed suite: 94 passed, 0 failed, 0 skipped (was 85; 9 new tests). Exit 0. No CR line endings.

## Task 8
- Minor 1 (`compare.gd capture_a`): `_last_cam`/`_last_fov` now sampled before `render_state`. Test `test_player_move_during_capture_recaptures`. RED: count 1. GREEN: >= 2.
- Minor 5 (`light_gizmos.gd`): joins group "overlay"; connects `node_added`/`node_removed` (adds a Light3D under pg while visible, erases on removal). Tests `test_gizmos_hidden_in_captures` (RED: still visible), `test_gizmos_pick_up_new_lights` (RED: 470 -> 470; also asserts removal returns to the old count). GREEN.
- Minor 6 (`compare.gd`): new `static save_sheet(image, path) -> String`; `save_pair` notifies the error, skips the clipboard copy, returns "". Test `test_save_sheet_reports_failure` (RED: parse error, function missing; GREEN). The engine's "Can't save PNG" error is declared with `expect_error`.
- Minor 9: `test_compare_pair.gd` saves the clipboard in before_each, restores it in after_each (new after_each). Checks unchanged. 19 compare tests pass.

## Task 9
- Minor 2: `PerfHud._process` sets `offset_top` to the view HUD's top + max(size, min size) height + 8 each update (reads `pg._hud`). `measure`/`table` untouched. Test `test_perf_readout_clears_view_hud` (all views). RED fail, GREEN pass.
- Minor 3: `Presets.load_error(path)`; `DevPanel.status_text()`; `refresh_presets()` notifies a non-empty error. Test `test_unreadable_presets_file_is_reported` (RED: no status_text; GREEN). `expect_error("ConfigFile parse")` because the broken file makes the engine log parse errors (all() and load_error both load it).
- Minor 4: `apply_state` skips values whose type differs from `_default_state`'s (int/float equal), notifies "Skipped <key>: expected <type>", and now returns the skip notes (Array[String]). `apply_preset` appends the notes to its own "Preset: X" message, otherwise that message would have overwritten the skip note. Test `test_wrong_typed_preset_value_is_skipped` (RED/GREEN as above): direction 53.13, wind 1.2, status contains "Skipped wind_direction".
- Minor 7: `ValueProbe.measure` reads `get_data()` (RGB8/RGBA8; other formats converted on a copy), uses per-channel luminance LUTs, builds per-row x-spans from the rects (pixel-centre rule identical to `Rect2.has_point`), walks runs between spans. Tests `test_measure_known_gradient` (passed already, as a guard for identical results; old tests half/white and exclusion still pass) and `test_measure_is_fast` (RED failed with the old code; GREEN 2.2 ms for 200x113 with 3 rects).
- Probe `sample()` cost: ~14-17 ms before, 9.7-10.9 ms after.

## Deviations / concerns
- `apply_state` return type changed from void to Array[String] (callers ignoring it are unaffected); apply_preset note format is "Preset: Bad (Skipped wind_direction: expected float)".
- Perf readout positioning only runs while visible; relies on the HUD layout being current (verified for every view with a 2-frame wait).
- The remaining probe cost is mostly the GPU readback and resize, not `measure`.
- Self-review: spans clamp/sentinel logic checked against the exclusion test (exact count of non-excluded pixels asserted in `test_measure_is_fast`).
