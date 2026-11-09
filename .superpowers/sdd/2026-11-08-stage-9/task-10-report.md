# Task 10 report

## Docs
- Created docs/REUSE.md (47 lines): what to copy, project settings (3 shader globals, layer names, plugin), ground rule (layers 1+2), five-step new level, playground-only parts.
- README.md: stage line -> 9; --profile-views flag; Motion panel text (wind direction, compass convention); grass visibility; layout entries (wind.gd, grass_field.gd, grass_brush.gd, addons/grass_painter, tools/make_starter_grass.gd); new "Grass and wind" section with painter controls table (LMB, Shift+LMB, [ / ], Ctrl+Z; verified against plugin.gd) and links to REUSE.md / PERFORMANCE.md.
- docs/EXPERIMENT_LOG.md: "Stage 9 experiments to run" (5 numbered items) above Stage 8.
- main.md: blank line added before the Stage 9 plugin-exception line.

## Line endings
CRLF found and converted to LF: scripts/environment/kit_asset.gd (57 lines), scenes/environment/kit/ground_mound_a.tscn (10), ground_mound_b.tscn (10), scenes/playground.tscn (1414), project.godot (93), main.md (319). Verified: line counts identical before/after and `diff --strip-trailing-cr` of backup vs result = 0 lines each; zero CR left. scripts/player/player.gd left CRLF (intended). assets/blender/environment_kit.blend is binary, skipped. No other CRLF under scripts/scenes/tests/tools/addons/docs.

## Validation
- Full suite windowed: 94 passed, 0 failed, 0 skipped, exit 0. (Console ERROR lines are the expect_error tests: bad ConfigFile, PNG save to missing dir.)
- Full suite headless: first run 70 passed, 2 FAILED (test_compare_pair::test_log_row_format, test_save_pair_without_a_does_nothing): before_each calls DisplayServer.clipboard_get(), unsupported on the headless display server (the clipboard save/restore was added in Stage 9 work). Fixed in tests/test_compare_pair.gd by guarding before_each/after_each with DisplayServer.has_feature(FEATURE_CLIPBOARD). Re-run: headless 72 passed, 0 failed, 22 skipped, exit 0; windowed re-run 94/0/0 exit 0.
- --capture-views: exit 0, no errors, 10 PNGs (gameplay, reveal, camp, clearing, forest_gate, gate_thirds, landmark_foot, long_lens, overview, path_low) all viewed. Grass visible and sensible in gameplay, forest gate, gate thirds, path low, camp, clearing (bare clearing floor with grass edge); none visible in reveal (fog), long lens, landmark foot, overview (dark plan view; the empty eastern area is the known open moor). No artifacts.
- --print-fps --disable-vsync (default scene, grass on, default window): ~652-656 fps (1.52-1.55 mspf). Stage 8 baseline 841 fps (grass off). Delta ~0.35 ms/frame, consistent with grass cost in --profile-views (0.1-0.33 ms GPU per view). No grass-off fps run (no flag/preset for it); the profile table gives the on/off comparison.
- --profile-views --resolution 1920x1080 --disable-vsync (screenshots/profile_2026-11-08T12-11-13.md): worst grass cost Gameplay 1.81 - 1.48 = 0.33 ms (budget 2.0); next Camp 0.25, Gate Thirds 0.23. Worst whole frame: Gameplay with grass 1.81 ms GPU (budget 7.0). Budgets met; consistent with docs/PERFORMANCE.md. (FPS column lags, as documented.)
- Editor load check `--headless --editor --path . --quit-after 300 | grep -i -E "error|grass_painter"`: no output (clean).

## Handoff: manual checks for the user
1. Paint in the editor: select Grass, LMB paint, Shift+LMB erase, [ / ] radius, Ctrl+Z undo one stroke (Task 6 Step 6).
2. Walk the player over the ground mounds; confirm no snagging or falling through (Task 2 Step 5).
3. RMB orbit while in split view (carried over from Stage 8).
4. Watch the grass while dragging Wind and Wind direction: waves should turn smoothly, no jumps in the gust pattern.

## Concerns
- Headless clipboard test fix touched a test file (small, guarded).
- main.md was CRLF and is now LF (assumed intended per ruling).
- A stray background shell (accidental python REPL call) was started during the work; harmless.
- README "default 53.13: mostly +X with a bit of -Z" is derived from the formula, not scene-checked.
