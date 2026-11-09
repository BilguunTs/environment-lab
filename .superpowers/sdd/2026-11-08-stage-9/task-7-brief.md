### Task 7: Profiling pass and budget

**Files:**
- Modify: `scripts/debug/perf_hud.gd` (a reusable measurement), `scripts/playground.gd`
  (`--profile-views` command line), `scripts/debug/debug_boot.gd` (`--no-wireframes`)
- Create: `docs/PERFORMANCE.md`, `tests/test_profile.gd`

**Interfaces:**
- Produces:
  - `PerfHud.measure(frame_count: int) -> Dictionary`: awaitable. Returns `{fps, cpu_ms, gpu_ms,
    draws, prims}` averaged, using the same sources as the HUD (Stage 8 ruling: CPU = viewport
    CPU render time + `get_frame_setup_time_cpu()`).
  - `static func PerfHud.table(rows: Array[Dictionary]) -> String`: a Markdown table, one row per
    `{view, grass, fps, cpu_ms, gpu_ms, draws, prims}`, with ms to 2 decimals.
  - `--profile-views`: for every fixed view, grass on then off, it settles 30 frames, measures 120,
    prints the table and writes it to `screenshots/profile_<datetime>.md`. Run it with
    `--disable-vsync`.
  - `debug_boot.gd` skips `set_debug_generate_wireframes` when `--no-wireframes` is in the user
    args.

- [ ] **Step 1: Write the failing tests:** `test_table_format` checks that `PerfHud.table()` of two
  rows gives a header, a separator and 2 rows, with `gpu_ms` printed as `"1.23"`.
  `test_measure_reads_gpu` (needs a window) checks that `await pg.perf_hud.measure(10)` returns
  `gpu_ms > 0` and `draws > 0`, and leaves `perf_hud.visible` as it was.
- [ ] **Step 2: Run** `--only=profile`. Expected: FAIL.
- [ ] **Step 3: Implement** them.
- [ ] **Step 4: Run** `--only=profile`. Expected: PASS.
- [ ] **Step 5: Profile.** Run `"$GODOT" --path . --disable-vsync -- --profile-views --quit`. Then
  run it again with `--no-wireframes` as well, and also record the startup time of each run
  (wall clock).
- [ ] **Step 6: Meet the budget.** Grass cost = GPU ms (grass on) − GPU ms (grass off), per view.
  If the worst view breaks either budget (grass ≤ 2.0 ms GPU, whole frame ≤ 7.0 ms GPU), change
  one thing at a time and re-profile after each:
  - `blades_per_m2`
  - `fade_end`
  - blade segment count
  - chunk `visibility_range_end`

  Stop when both budgets are met. Visually re-check that the field still reads as dense near the
  player.
- [ ] **Step 7: Write `docs/PERFORMANCE.md`:**
  - the method, and the dev machine (RTX 3070, i7-12700F, 1920×1080)
  - the budgets, and the mid-range rationale (7 ms on a 3070 ≈ 60 fps on a GTX 1660 / RTX 3050)
  - the final table
  - the top 3 costs named, plus what was tuned and why
  - the wireframe finding: if it costs nothing measurable, keep it on and say so; otherwise gate
    it off by default with `--wireframes` to opt in, and update `debug_boot.gd` and the F2 note
  - how to re-run the profile
- [ ] **Step 8: Checkpoint.** Run the full suite windowed. Expect it to be all green.

