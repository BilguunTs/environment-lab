# SDD ledger — plan: docs/superpowers/plans/2026-10-12-stage-8.md
Spec: docs/superpowers/specs/2026-10-12-stage-8-design.md
Setup: Ruling: no git repo — ledger kept by hand, baseline snapshot of scripts/, project.godot, README.md, docs/ copied to the session scratchpad for the final review diff; "commit" steps become full-suite checkpoints — cost if wrong: no per-task rollback (user offered git init, did not take it).
Pre-flight: T2→T3 Presets.all/save_user/USER_PATH signatures match. T4→T5 Compare leave()/show_a()/hud_tag() extended in T5 as planned. T5→T6 render_state/screenshot_path/busy match. T5→T8 overlay group + hide/restore_overlays match. T7→T8..10 Debug section anchor `_option("debug_draw"...)` present. T8→T9 get_param("probe") present before T9. No conflicts.
Task 1: Ruling: case.gd ternary needed an explicit bool type (Godot can't infer Variant ternaries); run.gd now counts an unparseable test file as FAIL (plan's runner reported 0/0 and exit 0) — cost if wrong: none, strictly safer
Task 1: complete (tests: run.gd headless → 2 pass 1 skip; windowed → 3/3 pass; broken-file check → FAIL + exit 1)
Task 2: complete (tests: run.gd windowed → 9 passed, 0 failed, 0 skipped, exit 0)
Task 3: Ruling: runner reported PASS for tests aborted by runtime script errors — added an OS Logger (ErrorCatcher) that fails any test raising an engine/script error, plus case.expect_error(fragment) for deliberate ones (used in test_broken_file_is_not_overwritten) — cost if wrong: a noisy-but-harmless engine warning could fail a test; fixable per test with expect_error
Task 3: complete (tests: run.gd windowed → 14 passed, 0 failed, 0 skipped, exit 0)
Task 4: Ruling: cam_fov is the active camera's lens, so after a view change A's cam_fov showed as a diff and holding X overwrote the new viewpoint's lens (spec: "compare from the same camera") — Compare remembers the pin view and drops cam_fov from A when the current view differs (_a_here) — cost if wrong: you can't compare "Gameplay at 60° vs Forest Gate at 50°", which the spec excludes anyway.
Task 4: Ruling: fmt(60.0) gave "60.0" (String.num keeps one decimal) — whole numbers now print as integers — cost if wrong: none.
Task 4: complete (tests: run.gd windowed → 24 passed, 0 failed, 0 skipped, exit 0)
Task 5: Ruling: capture_a renders _a_here() (Task 4 lens ruling) instead of raw a_state; hud_tag checks showing_a before split so holding X in split view reads SHOWING A (the overlay hides then) — cost if wrong: HUD wording only
Task 5: Ruling: plan's CompareView used set_anchors_preset (anchors only) so the overlay had size 0 and never drew; fixed with set_anchors_and_offsets_preset, pinned by a size check in test_split_captures_a_frozen_image (found by a visual look, not by the plan's tests) — cost if wrong: none
Task 5: complete (tests: run.gd windowed → 30 passed, 0 failed, 0 skipped, exit 0; split frame visually checked)
Task 6: Ruling: save_pair renders and diffs _a_here() (lens ruling) — cost if wrong: none
Task 6: complete (tests: run.gd windowed → 33 passed, 0 failed, 0 skipped, exit 0; saved pair visually checked)
Task 7: Ruling: render-mode test captures go to user://test_output/ (overwritten each run) instead of screenshots/ (would add 5 PNGs per test run to the user's captures) — cost if wrong: must look in the user data dir to inspect them
Task 7: complete (tests: run.gd windowed → 36 passed, 0 failed, 0 skipped, exit 0; 5 modes visually checked)
Task 8: complete (tests: run.gd windowed → 41 passed, 0 failed, 0 skipped, exit 0; probe sample 14.6 ms; overlay visually checked)
Task 9: Ruling: spec/plan computed CPU ms as render CPU + Performance.TIME_PROCESS, but TIME_PROCESS is the whole frame incl. vsync wait (read 16.5 ms at 120 fps); CPU now = viewport measured CPU render time + RenderingServer.get_frame_setup_time_cpu(), pinned by test_cpu_ms_is_work_not_frame_time — cost if wrong: script (_process) time isn't in the CPU figure; fps still shows the total
Task 9: complete (tests: run.gd windowed → 44 passed, 0 failed, 0 skipped, exit 0)
Task 10: Ruling: the plan's gizmo test used ImmediateMesh.surface_get_array_len, which ImmediateMesh does not expose; the test counts vertices via Mesh.surface_get_arrays instead (test-only) — cost if wrong: none
Task 10: complete (tests: run.gd windowed → 47 passed, 0 failed, 0 skipped, exit 0; gizmos visually checked)
Task 11: complete (tests: windowed 47/47, headless 35 pass 12 skip; no parse/run errors; fps 841 vs 842 baseline; capture-views OK; probe sample 14.5 ms)
Final review: opus reviewer — 0 Critical, 6 Important, 9 Minor. Re-graded: all 6 Important stand (each hit by ordinary use; #1 in the default view).
Final: fixed cam_height/smoothed camera → wrong A/B images + endless split recapture — test_flip_cuts_the_camera_instead_of_gliding, test_height_change_does_not_loop_recaptures RED→GREEN
Final: fixed nested hide/restore_overlays leaving HUD/split hidden + hotkeys acting mid-capture — test_overlay_hiding_is_reentrant, test_hotkeys_wait_for_a_capture RED→GREEN
Final: fixed X release lost during a capture or while typing — test_x_release_during_a_capture_is_kept, test_typing_releases_a RED→GREEN
Final: fixed re-pin in split leaving the old A image — test_repin_in_split_recaptures RED→GREEN
Final: fixed value-view slider drags blinking per tick in split view (now debounced) — test_value_view_changes_are_debounced RED→GREEN
Final: fixed Q/E/WASD moving follow/scout camera while typing a preset name — test_typing_does_not_orbit_or_fly RED→GREEN
Final: Ruling: value-view recapture is debounced (RECAPTURE_DELAY) instead of the spec's "immediately"; test_value_view_change_recaptures_a updated to wait for it; spec refinements updated — cost if wrong: A lags a value-view change by 0.5 s in split view
Final: Ruling: three of the new review tests passed before the fixes (they couldn't tell bug from fix); rewritten to measure capture count, view change via C, and busy — cost if wrong: none
Final: minor (deferred): A image camera pose recorded after restore, not at grab time (can miss a recapture if the player moves during the blink)
Final: minor (deferred): perf readout offset_top=64 may overlap a 3-4 line view HUD
Final: minor (deferred): unreadable user_presets.cfg fails silently on load (no status note)
Final: minor (deferred): wrong-typed values in hand-edited presets raise a runtime error in set_param
Final: minor (deferred): light gizmos show in A images / saved pairs; lights collected only when gizmos are enabled
Final: minor (deferred): Save pair ignores save_png's result and always reports success
Final: minor (deferred): probe measure() is ~14 ms (per-pixel get_pixel + per-pixel rect loop); probe test doesn't check the probe's own stats
Final: minor (deferred): wireframe generation always on (debug_boot), no measured cost
Final: minor (deferred): test_save_pair_writes_side_by_side_png overwrites the clipboard
Final: Ruling (declined-to-judge lines): ASCII-only preset names stand (clear refusal message; English UI). Probe hitch, debug mode in captures, cross-camera compare/A-B-C/delete UI: per spec. CompareView MOUSE_FILTER_PASS passthrough: RMB orbit untested in the suite — listed for the user's manual check. Volumetric-fog history on flip and single-frame draw/prim counts: accepted, visible only as a brief shimmer / stable counts — cost if wrong: minor visual noise
