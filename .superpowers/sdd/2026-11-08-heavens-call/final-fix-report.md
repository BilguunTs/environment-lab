# Final fix wave report

Status: all 7 fixes done. Heavens tests 60 passed. Full suite: 158 passed windowed (was 155), 135 passed / 23 skipped headless (was 132/23). No CR line endings introduced.

1. test_natural_path_to_title (tests/test_heavens_summit.gd): freezes the sequence (_freeze), start(), then _process(0.25) in a loop. Calls summit._input(event) directly for the key presses (FADE, title fade-in) and the mouse click. Asserts phase order, clap_played after REVEAL, fade alpha > 0.99, not armed early, armed only after the fade-in (8 ticks), title alpha 1.0, 0 finished emissions before arming, 1 after the click.
   RED proof: temporarily added `input_armed = true` after `_next(Phase.TITLE)`. Result: FAIL natural_path ("armed only after the title fade-in (1 ticks)", "title fully shown when armed: expected 1.0, got 0.0"), 59 passed 1 failed. Reverted (diff confirms), 60 passed.
2. test_missing_file_paths_stay_silent plus test_clap_survives_a_roll (tests/test_heavens_sound.gd). Seam: optional `file` arg on play_thunder(clap, file) and step(on_trail, file). _make_loop is called directly with a missing name. Asserts null stream, nothing playing, no engine error.
3. docs/REUSE.md: tonemap_mode = 4 now labelled AgX.
4. docs/HEAVENS_CALL.md: table copied from heavens_profile_2026-11-08T18-45-15.md (adds Grass column); worst view text now 1.98 ms.
5. show_view: unknown name push_warning and return before reset_scene. Only test callers use the five valid names plus reveal_early. No test for the warning (a warning could trip the runner's error check).
6. soundscape.gd: separate "Clap" AudioStreamPlayer; play_thunder(clap := false, file := ""); stop_one_shots stops both; thunder_playing covers both. The roll player is still named "Thunder", so the existing test is unchanged.
7. SummitSequence.reset() now calls set_physics_process(true) too.

Commands (GODOT = console exe, from project root): `--path . -s res://tests/run.gd -- --only=heavens` -> 60 passed; full windowed -> 158 passed, 0 failed; `--headless` -> 135 passed, 0 failed, 23 skipped.

Concerns: the new tests call `_input` directly, so they don't cover Input.parse_input_event routing (test_input_ignored_until_title still does). Fix 5 has no dedicated test.
