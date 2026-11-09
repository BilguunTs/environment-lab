# Task 1 report

Status: DONE

## Implemented
- Player: `can_sprint` (gates sprint speed) and `lantern` (setter, also applied in `_ready`) hide/show `Model/Lantern` and `Model/LanternLight`. player.gd stays CRLF.
- FollowCamera: `min_pitch`/`max_pitch` exports (-10/80 defaults); `pitch_deg` setter clamps; mouse-orbit uses the setter (hard-coded clamp removed).
- tests/run.gd: files may declare `const SCENE`; files grouped per scene (playground group first), each scene instantiated once, freed after its group; `reset_scene()` called only if the root has it.
- Level: `scenes/levels/heavens_call.tscn` + `scripts/levels/heavens_call.gd` (class HeavensCall: player, follow_cam, wind, reset_scene, 3 s tween fade-in). Scene has WorldEnvironment/Sun copied from the playground, Wind, Player (walk 2.0, no sprint, no lantern), GameplayCamera (pitch -5..45), flat Ground (layer 3, plane + 400x1x400 box), UI CanvasLayer (group overlay) with black Fade ColorRect.
- Grass ruling: `tools/make_starter_grass.gd` now has `static func build_mask(scene) -> Image`; `_init` just calls it and saves. `test_path_is_clear_of_grass` (name kept) builds the mask in memory from the live playground and checks the path/side-trail centrelines are 0 density. The shipped `assets/grass/playground_grass.res` was not touched.
- Added `test_playground_player_unchanged` to tests/test_smoke.gd; created tests/test_heavens_basics.gd (4 tests).

## TDD
- RED: `--only=heavens` crashed on the missing scene (null instantiate); grass test failed with "Nonexistent function 'build_mask'".
- GREEN: `--only=heavens` 4 passed.

## Full suite
- Windowed: 101 passed, 0 failed, 0 skipped (96 + 5).
- Headless: 79 passed, 0 failed, 22 skipped.
- The ERROR lines printed in the run are the pre-existing expected ones from preset/PNG tests.

## Deviations
- None of substance. Ground uses a 400 m plane plus a box collider (top at y=0) instead of a WorldBoundary, because Task 2 replaces it anyway.

## Self-review / concerns
- Camera pitch is clamped on set using the min/max at that moment; scene load applies `pitch_deg` before `min_pitch/max_pitch`, fine for the default 14 but changing limits later does not re-clamp.
- Each scene group is torn down and freed before the next, so the playground and level never coexist (avoids two current cameras and Wind globals clashing).
- Tween fade uses real process time; the test waits 3.3 s.
