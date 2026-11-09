### Task 9: Stage 8 leftovers — panel, presets, probe, perf (minors 2, 3, 4, 7)

**Files:**
- Modify: `scripts/debug/perf_hud.gd`, `scripts/presets.gd`, `scripts/playground.gd`
  (`apply_state`, `_build_hud` access), `scripts/ui/dev_panel.gd`, `scripts/debug/value_probe.gd`
- Test: `tests/test_stage8_leftovers.gd`, `tests/test_value_probe.gd`

**Interfaces:**
- Produces:
  - `static func Presets.load_error(path := USER_PATH) -> String`: `""` when the file is fine or
    missing, otherwise `"Can't read <path> (error N): fix or delete it"`.
  - `func DevPanel.status_text() -> String`
  - `playground.apply_state` skips a value whose type doesn't match the default state's type (int
    and float count as the same), and notifies `"Skipped <key>: expected <type>"`.
- Fixes:
  2. `PerfHud` places itself 8 px under the view HUD's bottom edge each update, instead of the
     fixed `offset_top = 64`.
  3. `refresh_presets()` shows `Presets.load_error()` in the status line when it's non-empty.
  4. Wrong-typed values in presets are skipped, as above.
  7. `ValueProbe.measure` reads `image.get_data()` directly (RGB8/RGBA8 bytes) and turns the
     exclude rects into per-row x-spans once, instead of testing every pixel against every rect.
     Results must be identical.

- [ ] **Step 1: Write the failing tests:**
  - `test_perf_readout_clears_view_hud`: for every view name, set it, wait a frame, and check
    `pg.perf_hud.get_global_rect().position.y >= pg._hud.get_global_rect().end.y`.
  - `test_unreadable_presets_file_is_reported`: write `"[broken"` to `user://bad_presets.cfg`,
    point `pg.preset_path` at it, and call `pg.panel.refresh_presets()`. Expect
    `pg.panel.status_text()` to contain `"Can't read"`. Restore `preset_path` afterwards.
  - `test_wrong_typed_preset_value_is_skipped`: save a cfg with
    `[Bad] wind_direction="north" wind=1.2` to the test path, then `apply_preset("Bad")`.
    Direction stays 53.13 (±0.01), wind = 1.2, and the status contains
    `"Skipped wind_direction"`. No engine error.
  - In `test_value_probe.gd`:
    - `test_measure_known_gradient`: a 100 × 1 RGB8 image with pixel x = grey x/99. Expect p5,
      p50 and p95 equal to the grey of pixel 5, 50 and 95 (± 0.005), and the histogram total = 100.
    - `test_measure_is_fast`: a 200 × 113 image with 3 exclude rects; `measure()` takes < 4 ms
      (`Time.get_ticks_usec`).
- [ ] **Step 2: Run** `--only=stage8_leftovers` and `--only=value_probe`. Expected: the new tests
  FAIL.
- [ ] **Step 3: Implement** the four fixes.
- [ ] **Step 4: Run** the same filters. Expected: PASS.
- [ ] **Step 5: Checkpoint.** Run the full suite windowed. Expect it to be all green.

