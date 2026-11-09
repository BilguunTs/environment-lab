# Task 7 report: Profiling pass and budget

Status: DONE. Full windowed suite: 85 passed, 0 failed (was 83).

## Implemented
- PerfHud.measure(frames) (awaitable; same sources as HUD; measuring forced on, restored to `visible`; 2 warmup frames).
- PerfHud.table(rows) Markdown table.
- playground.gd: --profile-views (settle 30, measure 120, grass on/off per fixed view, overlays hidden, state restored; prints and writes screenshots/profile_<datetime>.md).
- debug_boot.gd: --no-wireframes.
- docs/PERFORMANCE.md, tests/test_profile.gd.

## TDD
RED: `--only=profile` -> "Static function table() not found in PerfHud", 0 passed 1 failed. GREEN: 2 passed.

## Profile (1920x1080, --disable-vsync): see docs/PERFORMANCE.md for full table
- Worst grass cost: Gameplay ~0.32-0.40 ms GPU (budget 2.0). Worst frame: Gameplay grass on 1.77-1.82 ms (budget 7.0).
- Wireframes on vs off: identical within noise. Startup (wall, --quit, 3 runs): on 2.26/2.28/2.50 s, off 2.23/2.25/2.39 s. Kept on.

## Tuning: none (within budget). No grass defaults changed.

## Deviations / concerns
- FPS column is Performance TIME_FPS, which lags (updates ~1/s), so first rows after a view change show stale values; ms columns are reliable. Noted in PERFORMANCE.md.
- Needed `--resolution 1920x1080` to pin the size.
- Run on a 3070 only; the mid-range claim is by ratio, not measured.

## Self-review
LF files, typed, tabs. Test passes with measure leaving perf_hud.visible unchanged.
