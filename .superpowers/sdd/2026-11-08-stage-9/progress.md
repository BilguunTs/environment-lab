# SDD ledger — plan: docs/superpowers/plans/2026-11-08-stage-9.md
Spec: docs/superpowers/specs/2026-11-08-stage-9-design.md
Setup: Ruling: no git repo (as Stage 8) — baseline snapshot of scripts/, scenes/, assets/ (minus meshes, blender), tests/, project.godot, README.md, main.md, docs/ in the session scratchpad `baseline/`; per-task snapshots `snap-<N>/` taken before each dispatch; review packages are `diff -ruN` against them; "commit" = full-suite checkpoint — cost if wrong: no per-task rollback beyond the snapshots.
Setup: baseline suite windowed = 56 passed, 0 failed, 0 skipped (plan said 47; Stage 8 review fixes added 9).

## Pre-flight scan
| Pair / task | Produces → consumes | Found |
|---|---|---|
| T1→T4 | wind.gdshaderinc: wind_gust(), wind_direction, wind_strength, wind_offset | match |
| T1→T5/T9 | pg.wind, params wind/wind_direction, default 53.13 | match |
| T2→T3 | ground = layer 2, Ground collision_layer 3 | match; T3 fixture at (0,0,-6) is on Ground plane |
| T3→T4 | INSTANCE_CUSTOM (tint, phase, fade_rand), fade_start/end exports | match |
| T3→T5 | sample(world_xz), ground_height_at, blade_count, mask | match |
| T3→T6 | paint()->Rect2i, rebuild(rect), set_mask_data, ground_layer | match |
| T5 ← path_ribbon | get_centerline_world(), width | present (scatter.gd:232) |
| T7 / T9 | both modify perf_hud.gd (measure vs placement) | disjoint parts; OK |
| T8 / T9 | both write tests/test_stage8_leftovers.gd | T9 appends; carry in dispatch |
| T1 self | tests vs code | consistent |
| T2 self | tests vs code | consistent (await frames(2) noted) |
| T3 self | test_heights_follow_mask paints with default falloff 0.5 → edge texels G<1, blades there fall below max_height*0.84 | DEFECT → ruling 1 |
| T4 self | image test field at fixed (0,0,-6) may be off-screen from Gameplay camera | RISK → ruling 2 |
| T5 self | consistent |
| T6 self | spacing 0.75 vs dab steps 2 m / 0.1 m | consistent |
| T7 self | consistent |
| T8 self | consistent |
| T9 self | consistent |
| T10 self | Stage 8 fps baseline 841 | consistent |

Preflight: Ruling 1: T3 test_heights_follow_mask paints DENSITY and HEIGHT with falloff 0.0 (full value across the disc) — the plan's call with falloff 0.5 would fail on correct code — cost if wrong: none (test-only).
Preflight: Ruling 2: T4 image tests place their 16×16 field centred 8 m in front of the active camera, projected to y=0, instead of fixed (0,0,-6) — guarantees the grass is in frame — cost if wrong: none (test-only).
Preflight: Ruling 3: plan's "Baseline before Task 1: 47 passed" is stale; checkpoints compare against 56 + new tests — cost if wrong: none.
Task 1: dispatched (implementer sonnet; snapshot = baseline/)
Task 1: implementer DONE_WITH_CONCERNS (62/62 windowed; global_shader_parameter_get is editor-only so test reads wind.vector(); rotated-direction capture not done; gust constants eyeballed). Review dispatched (sonnet).
Task 1: ⚠️ resolved by controller: PARAM_ORDER feeds get_state/apply_state/presets/compare generically (playground.gd get_state loops PARAM_ORDER) — OK; tree/cloth direction comes from the wind_direction global in flat_color (reviewer confirmed in diff) and mist/motes are pinned by tests; sway mean 0.55 matches old 0.55+0.45·sin — accepted without a rotated capture.
Task 1: minor (deferred): test_gust_offset_has_no_jump is weak (1-frame bound 1.0 would also pass a TIME-derived offset); assert per-frame advance = vector*strength*GUST_SPEED*delta instead
Task 1: minor (deferred): published globals untested (global_shader_parameter_get is editor-only)
Task 1: minor (deferred): Wind setters call _publish before entering the tree (redundant RenderingServer call)
Task 1: complete (snapshot baseline/ -> current, review clean)
Task 2: implementer DONE (65/65; mounds walkable max 40.7° < 45°; procedural trees land on mounds). Review dispatched.
Task 2: Ruling: reviewer said touched files are LF; controller measured CR bytes (playground.tscn 1406, project.godot 89, kit_asset.gd 57, mound scenes) — they ARE CRLF now (were LF; player.gd was CRLF before Stage 9). Godot reads both, so functionally harmless; normalize the Stage-9-touched files back to LF in Task 10 and tell every later implementer to preserve LF — cost if wrong: whole-file churn in the final diff until Task 10.
Task 2: ⚠️ resolved: Step 5 walk replaced by measured slopes (kit B max 40.7° vs floor_max_angle 45°) — accepted; listed for the user's manual walk at handoff.
Task 2: minor (deferred): kit_asset collision built in @tool _ready — live edits of a mound scene don't refresh collision until reload
Task 2: minor (deferred): test_ground_plane_is_ground rays at (0,0); would pass falsely if a ground kit piece ever sits at origin
Task 2: minor (deferred): add a comment on find_children(owned=false) in kit_asset.gd
Task 2: complete (review clean)
Task 3: implementer DONE_WITH_CONCERNS (72/72; height test paints HEIGHT r=6 because bilinear rim blends G; Ground is infinite WorldBoundary so missing-ground test uses ground_layer=20; full 74x104 field ≈184k blades, 0.62 s build, stroke 26 ms). Review dispatched.
Task 3: Ruling: accepted implementer's test deviations — test_heights_follow_mask paints HEIGHT with radius 6 (bilinear rim blends unpainted G), test_no_blades_where_ground_missing sets ground_layer=20 (scene Ground is an infinite WorldBoundaryShape3D, so nothing off the 400 m plane is a hole) — cost if wrong: none, test-only; the plan's "beyond the plane" premise was false.
Task 3: ⚠️ resolved: editor-side raycasts from a @tool node → confirm in Task 6 manual check; layer-2 selection → covered by Task 2's test_boulders_are_not_ground.
Task 3: minor (deferred): paint() byte quantisation stalls low-strength ticks just short of target (relevant to Task 6 brush strength)
Task 3: minor (deferred, carry to Task 5): rebuild() before the first physics frame can cache an all-NAN ground; only _ready→_physics_process path is protected
Task 3: minor (deferred, carry to Task 6): moving the GrassField node doesn't invalidate the ground cache or re-ground blades
Task 3: minor (deferred): stray blank line grass_field.gd:392; set_mask_data / ground_height_at values / INSTANCE_CUSTOM untested here
Task 3: minor (deferred): rim of a tall stroke is shorter (G bilinear with unpainted 0.5) — brush UX question for Task 6/final
Task 3: complete (review clean)
Task 4: implementer DONE_WITH_CONCERNS (75/75; grab rect moved to lower band y50-90% since middle third is mostly trees/sky; highlight×min(strength,1), fade remap, lean×blade height; Notan + GPU cost not checked). Review dispatched.
Task 4: Ruling: accepted deviations — grab rect lower band (y 50-90%), highlight × min(strength,1), whole-blade fade scale with FADE_BAND 0.12, lean × blade height — each meets the spec's intent (reviewer checked fade ends) — cost if wrong: look-tuning only.
Task 4: ⚠️ resolved: params reset between tests — run.gd calls pg.reset_scene() before every test. Notan/3-Value read, gust travel over time, GPU cost → carried to Task 5 visual check / Task 7 profile.
Task 4: minor (deferred): image tests don't isolate grass from tree sway/flutter in the grab rect (add a field-hidden baseline diff)
Task 4: minor (deferred): shader comments should note the highlight clamp and fade band differ from the plan formulas
Task 4: complete (review clean)
Task 5: implementer DONE (80/80; 112,982 blades; grass +0.34 ms GPU worst view (Gate Thirds/Camp 1.96 vs 1.64) at 1600x900; Notan/3-Value read OK). Review dispatched.
Task 5: Ruling: accepted path exclusion measured from PathRibbon's real edge profile (stricter than nominal width/2) and Image saved directly — cost if wrong: mask goes stale if the ribbon profile changes (rerun the tool).
Task 5: ⚠️ resolved: perf numbers are in this ledger (Task 5 report line); measured at 1600x900 not 1080p → Task 7 re-measures at 1920x1080.
Task 5: minor (deferred): make_starter_grass.gd calls PathRibbon._sample() and duplicates its width formula
Task 5: minor (deferred): make_starter_grass.gd repeats min/max height literals 0.25/0.9
Task 5: minor (deferred): fresh checkout without playground_grass.res prints a scene parse error on first generator run
Task 5: minor (deferred): clearing test samples 4 points only
Task 5: complete (review clean)
Task 6: implementer DONE (83/83; plugin load clean headless + windowed; create_action context = field so undo also re-saves mask; Ctrl+D duplicate shares mask (not handled); re-ground on move while selected; take_over_path for mask .res; Godot editor rewrites project.godot as LF).
Task 6: Ruling: create_action context = the field (so the mask re-save rides the scene history) — reviewer confirms EditorUndoRedoManager forces fixed history with a context — cost if wrong: "history mismatch" error on undo; user's manual check item.
Task 6: ⚠️ resolved: re-ground-on-move in plugin _process was requested by the controller in the dispatch (Task 3 deferred minor b) — not an Extra.
Task 6: minor (deferred): ensure_mask() resize happens before the undo snapshot (resize not undoable)
Task 6: minor (deferred): field leaving tree mid-stroke leaves dabs without an undo step
Task 6: minor (deferred): undo test only covers an empty "before" mask; spacing test never checks a far dab applies
Task 6: minor (deferred): [ / ] matched by keycode, not physical_keycode (non-US layouts)
Task 6: minor (deferred): main.md exception line lacks a blank line before it (renders into previous paragraph)
Task 6: minor (deferred): undo/redo re-saves don't call update_file
Task 6: minor (deferred): Ctrl+D duplicated GrassField shares the mask .res — painting one paints both
Task 6: complete (review clean)
Task 7: implementer DONE (85/85; 1920x1080: worst grass cost Gameplay 0.32-0.40 ms GPU, worst frame 1.77-1.82 ms GPU; no tuning; wireframes no measurable cost → stay on, --no-wireframes added; FPS column stale-ish (TIME_FPS 1 s update)). Review dispatched.
Task 7: ⚠️ resolved: profile numbers/startup times are runtime claims consistent with Task 5's independent 1600x900 measurement (+0.34 ms) — accepted; 1920x1080 relies on the documented --resolution flag.
Task 7: minor (deferred): FPS column averages lagging TIME_FPS (68/92 fps beside 1.77 ms GPU is misleading) — compute frames/elapsed in measure()
Task 7: minor (deferred): --profile-views silently skips the file write if FileAccess.open fails
Task 7: minor (deferred): PERFORMANCE.md "top 3 costs" names views, not cost sources
Task 7: minor (deferred): Overview row identical with grass on/off (grass out of range) — say so in the doc
Task 7: complete (review clean)
Tasks 8+9: Ruling: batched into ONE implementer dispatch and one review — same shape (small Stage 8 leftovers, each with a test), they share tests/test_stage8_leftovers.gd — cost if wrong: a larger single review surface.
Tasks 8+9: implementer DONE (94/94; probe sample 14-17 → 9.7-10.9 ms, measure() 2.2 ms; apply_state now returns skip notes; parse-error test uses expect_error). Review dispatched.
Tasks 8+9: ⚠️ resolved: pg._hud / view_names() exist (playground.gd) and the 94/94 windowed suite exercises the Node3D-in-overlay path.
Tasks 8+9: minor (deferred): skip note notified twice via apply_preset (harmless)
Tasks 8+9: minor (deferred): _same_type treats String vs StringName as different
Tasks 8+9: minor (deferred): probe luminance float64 LUT may differ in last bit from old float32 path
Tasks 8+9: minor (deferred): test_measure_is_fast 4 ms wall-clock threshold could flake (2.2 ms measured)
Tasks 8+9: minor (deferred): refresh_presets loads the cfg a third time via load_error
Tasks 8+9: minor (deferred): perf_hud reaches into private pg._hud
Task 8: complete (review clean, batched with 9)
Task 9: complete (review clean, batched with 8)
Task 10: implementer DONE_WITH_CONCERNS (windowed 94/0/0; headless 72/0/22; captures OK; fps ~654 vs Stage 8 841 grass-off; profile grass 0.33 / frame 1.81 ms; editor load clean; CRLF→LF normalised; test_compare_pair clipboard guarded for headless; main.md was CRLF→LF). Review dispatched.
Task 10: Ruling: main.md was CRLF in the baseline (318 CR) and is now LF — accepted, the project's text files are LF and Godot writes LF — cost if wrong: whole-file line-ending change in main.md.
Task 10: ⚠️ resolved: validation numbers are in this ledger (Task 10 implementer line).
Task 10: minor (deferred): REUSE.md step 5 implies a manual mask save — the plugin auto-saves the mask at stroke end; only the scene needs saving
Task 10: minor (deferred): REUSE.md step 1 doesn't name Wind.direction_degrees; README line 173 unwrapped
Task 10: complete (review clean)
Final review: dispatched (opus) on baseline -> current.
Final review (opus): 0 Critical, 4 Important (I1 gust pattern jumps on direction change with unbounded world offset; I2 duplicated GrassField shares mask .res; I3 REUSE.md gaps; I4 falloff missing from toolbar — spec §3, dropped by the plan), 4 Minor. Deferred-minor triage: fix Task1 weak gust test (→I1), Task6 Ctrl+D shared mask (→I2), Task10 REUSE wording (→I3); close Task6 main.md blank line (already fixed); all others stay deferred.
Final: Ruling: instant wind-direction change from preset/A-B/reset is a cut, no smoothing — smoothing would break A/B and capture determinism; slider drags are already incremental — cost if wrong: a one-frame lean flip on preset switch.
Final: Ruling: I4 is a plan defect (spec lists falloff; plan Task 6 dropped it) — spec wins, add the control — cost if wrong: one extra toolbar box.
Final: Ruling: M1 (extent/texel change stretches mask) stays deferred but is documented via I3; M2 editor raycasts stay on the user's manual checklist; M3 re-ground only while selected stays deferred.
Final: fix wave dispatched (one implementer, opus) with final-findings.md.
Final: fix wave DONE (96/0/0 windowed, 74/0/22 headless; editor load clean; wind_offset → float wind_phase wrapping at 2000 m with periodic noise; duplicate/pasted field forks its mask before first stroke; falloff SpinBox; REUSE/README updated). Scoped re-review dispatched.
Final: re-review — I1, I2, I3, I4, M4 all ADDRESSED, no new breakage. Stage 9 complete.
Final: Ruling: workspace kept (not deleted) — no git repo, so this ledger is the only record of rulings and deferred minors — cost if wrong: a few hundred KB of scratch in .superpowers/.
Final: Ruling: finishing-a-development-branch skipped — no git branch to merge or push — cost if wrong: none.
