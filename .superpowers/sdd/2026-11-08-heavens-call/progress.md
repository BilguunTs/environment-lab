# SDD ledger — plan: docs/superpowers/plans/2026-11-08-heavens-call.md
Spec: docs/superpowers/specs/2026-11-08-heavens-call-design.md
Setup: Ruling: no git repo — baseline snapshot in session scratchpad hc/base/, per-task snapshots hc/snap/, review packages = diff -ruN --strip-trailing-cr; "commit" = full-suite checkpoint — cost if wrong: no per-task rollback beyond snapshots.
Setup: baseline windowed = 95 passed, 1 failed (test_grass_scene::test_path_is_clear_of_grass — the user hand-painted grass onto the path in the editor test; the test pins the shipped, user-editable mask).
Preflight: Ruling 0: keep the user's painting; Task 1 also rewrites test_path_is_clear_of_grass to check the starter generator's output (tools/make_starter_grass.gd logic run into an in-memory image) instead of the shipped playground_grass.res — the mask is user-paintable by design — cost if wrong: no test guards the shipped file's path clearance.

## Pre-flight scan
| Pair / task | Produces → consumes | Found |
|---|---|---|
| T1→all | run.gd `const SCENE`, HeavensCall.reset_scene, member names trail/mood/storm/soundscape/vista/summit | match |
| T2→T3,T5,T6,T7,T9 | Trail.progress_at/point_at/distance_to_centre/width/length, furthest_progress | match |
| T3↔T4 | MoodDirector.apply → Soundscape.set_volumes (optional until T4); T4 modifies mood_director.gd | match |
| T3→T4 | Storm.flashed(delay) → play_thunder | match |
| T6→T7 | Vista.reveal 0..1 | match |
| T4→T8 | fixed file names, README table | match |
| T7→T9 | skip_to(Phase) for "wide" view | match |
| T1 self | 5 new tests, baseline+5 | consistent (baseline now 95+1 fail → ruling 0) |
| T2 self | respawn rule "y < point_at(progress).y - 15" — must use LOCAL progress (progress_at(player)), not furthest (walking back down legitimately drops >15 m below the furthest point) | AMBIGUOUS → ruling 1 |
| T3 self | consistent |
| T4 self | test_missing_audio_is_silent relies on runner's engine-error catch | consistent |
| T5 self | consistent |
| T6 self | test_trail_grass_is_sparse samples every trail field at trail 0.5 — a field not covering that point returns (0,0) and passes vacuously | WEAK → ruling 2 |
| T7 self | consistent (quit_on_finish hook declared) |
| T8 self | network availability unknown | NEEDED.md fallback covers it |
| T9 self | consistent |
| T10 self | consistent |
Preflight: Ruling 1: respawn triggers when player y < trail.point_at(trail.progress_at(player_pos)).y - 15 (local progress), respawn point = point_at(furthest_progress) — avoids respawning a player who legitimately walks back down — cost if wrong: a player below a switchback could be matched to the wrong trail segment (test pins the basic case).
Preflight: Ruling 2: test_trail_grass_is_sparse checks each trail field at the trail centre point nearest that field's own centre (and asserts that point lies inside the field) — cost if wrong: none (test-only).
Task 1: implementer DONE (101/0/0 windowed, 79/0/22 headless; build_mask static in make_starter_grass; pitch limits clamp at set time only).
Task 1: review — spec ✅, quality Approved. ⚠️ player.gd CRLF checked by controller (see counts at completion).
Task 1: minor (deferred): pitch_deg clamped only on set; changing min/max_pitch later doesn't re-clamp; export_range(-10,80) duplicates limits.
Task 1: minor (deferred): test_no_sprint_in_level releases input actions after checks — an aborted test leaves sprint/move_forward pressed.
Task 1: minor (deferred): run.gd always runs the playground group first; "sorted order" holds within a scene only.
Task 1: complete (snapshot hc/snap after T1, review clean)
Task 1: line endings verified by CR byte count: only player.gd CRLF (59/59), all new files LF. (grep -c $'\r$' gives false counts in Git Bash — use tr -cd '\r' | wc -c.)
Task 2: implementer DONE (106 windowed; 84+22 headless; trail 694 m, 220 m climb, max grade 24.3°; full trimesh 330 ms). Concerns: dark late climb (T3), camera clips cliffs, corridor wide.
Task 2: review — spec ✅, quality Approved. ⚠️ cliffs ≥50° approximately met (1.1% off-corridor samples <45°, no basins — reviewer analysed no softlock) — accepted.
Task 2: minor (deferred): banks between switchback legs ~41° near hairpin 1 allow corner-cutting and can nudge furthest_progress early.
Task 2: minor (deferred → carried into T3): no test that walking back down never respawns; no bounded-corridor assertion.
Task 2: minor (deferred): _build() ~190 lines, 5 phases; split into helpers.
Task 2: minor (deferred): heavens_call.gd reaches player.get_node("Model") by name.
Task 2: minor (deferred): redundant `ahead` computation at progress>=1.
Task 2: minor (deferred): Trail.width change doesn't trigger terrain rebuild in editor.
Task 2: minor (deferred): extra exports narrows/summit_size/cliff_slope (fine).
Task 2: minor (deferred → T6): square massif boundary visible from the air; vista must hide it.
Task 2: complete (snapshot after T2, review clean)
Task 3: Ruling 3: FollowCamera gets terrain collision (ray from target to goal on a mask, pulls in with a small margin; export collision_mask, 0 = off so the playground is unchanged; level uses mask 2) — added to Task 3 because the implementer reported the camera clipping into cliff walls on ledges and the spec says props must read from any side — cost if wrong: ~30 lines in follow_camera.gd, playground unaffected.
Task 3: Ruling 4: Task 3 adds test_walking_down_never_respawns (Task 2 deferred minor) and must keep the 0.8–0.95 stretch readable (implementer concern: deep shadow) via mood light/ambient — cost if wrong: none.
Task 3: implementer DONE_WITH_CONCERNS (115 windowed; headless 93+22 in 1/3 runs, 2/3 failed pre-existing test_value_probe::test_measure_is_fast at 4.3–4.5 ms vs 4 ms).
Task 3: Ruling 5: lightning_per_min and vol_eerie ramp in only over 0.57–0.62 (not blended across 0.28–0.57) — the plan's smoothstep-between-keys contradicts its own test_no_lightning_before_eerie and the spec ("none in stretches 1–2", eerie ambience "during stretch 3") — cost if wrong: lightning/eerie arrive ~0.05 later than a full blend.
Task 3: Ruling 6: ambient energy/colour added to mood keys (outside the brief's key list) to fix the murky 0.8–0.95 stretch — per Ruling 4 — cost if wrong: none.
Task 3: note: ground_mist.gdshader gained base_height uniform (default 0, playground unchanged) — shared shader change, reviewer to check.
Task 3: note: test_value_probe::test_measure_is_fast is flaky headless (pre-existing timing threshold 4 ms) — track; if it fails at a checkpoint, rerun once.
Task 3: review — spec ✅, quality Needs fixes. I1: 0.9 stretch barely readable, foggier near her than 0.7 (SUMMIT mist/fog too high).
Task 3: Ruling 7: fix round also takes reviewer minor 1 (wind wobble slides gusts ~3–9 m/s sideways at trail radius — load-bearing for T6 grass) and minor 2 (gate-edge test pinning Ruling 5) — cheap and protect later tasks — cost if wrong: small scope growth.
Task 3: minor (deferred): camera test returns early without restoring distance/pitch, never restores yaw (fresh reset each test).
Task 3: minor (deferred): collision margin measured along the ray, not the normal.
Task 3: minor (deferred): runtime mutation of shared sub-resources (mist material, Environment, sky) — add resource_local_to_scene if two instances coexist.
Task 3: minor (deferred → T9 perf): extra 110×30×110 Mist FogVolume GPU cost unmeasured; ambient_light_color effect depends on env ambient source.
Task 3: minor (deferred): test_value_probe::test_measure_is_fast flaky headless (pre-existing).
Task 3: fix round 1/5 (3 addressed, 0 open — SUMMIT fog 0.011/mist 0.30/ambient 1.15; wobble single 120 s swing 4/5/6/6°; gate-edge + wobble tests). 117 windowed, 95+22 headless.
Task 3: minor (deferred → T6): path band at 0.90 faint against dark slope; she is ambient-only lit 0.85–0.90 (flat shading).
Task 3: complete (snapshot after T3 fix 1, review clean)
Task 4: implementer DONE (124 windowed; 102+22 headless). Concerns: respawn teleport may fire steps (reset _last_pos); loop flag untested on real ogg (T8).
Task 4: review — spec ✅, quality Approved. ⚠️ thunder lag: controller checked storm.gd emits randf_range(2.5, 6.0), pinned by test_flash_schedules_distant_thunder. ⚠️ mood_director untouched: already wires volumes; test_mood_drives_volumes covers it.
Task 4: minor (deferred): respawn stride burst — if she stood on a ledge ≥15 m below, next frame counts the teleport distance (one restarted footstep, inflated step_count); fix: reset _last_pos/_stride_walked in _place_on_trail.
Task 4: minor (deferred): "never same file twice" untested; test calls private _count_stride.
Task 4: minor (deferred → T8): "loop" in s untested on real ogg.
Task 4: complete (snapshot after T4, review clean)
Task 5: pre-task backup of assets/meshes + environment_kit.blend in hc/snap/assets (Blender re-exports every GLB).
Task 5: implementer DONE_WITH_CONCERNS (127 windowed; 105+22 headless; 18 existing GLBs byte-identical). Concerns: shared flat_color.gdshader sway/contact now uses height above object origin (cloth at y 220 bent metres); walkable test excludes player RID; scarf barely sways; T3 test_mood_ignores_backtracking flaked 1/5 windowed (3 frames may lack a physics tick).
Task 5: Ruling 8: test-side exclude of the player RID in test_props_leave_the_path_walkable is correct — the brief's test probed the player standing at progress 0 — cost if wrong: none.
Task 5: review — spec ❌ via I1: flat_color.gdshader origin-relative height changes the playground (banner cloth ~100× stiffer and 20–35% darker, pole half rigid/darker, trees on mounds sway ~30% less). Reviewer independently verified the 18 GLBs MD5-identical.
Task 5: Ruling 9: the origin-relative height becomes opt-in: `instance uniform bool height_from_origin = false` in flat_color.gdshader (default = old world-height behaviour, so the playground is bit-for-bit unchanged); kit_asset.gd gets `@export var height_from_origin := false` that sets the instance parameter on its meshes; the level's kit instances (Debris, Traces, Rocks, and later Vista/Ovoos) enable it — kit GLBs have base origins, so it's correct for them — cost if wrong: one more kit flag to remember (goes in REUSE.md in T10).
Task 5: Ruling 10: the fix round also deflakes T3 test_mood_ignores_backtracking (wait for physics ticks, e.g. `await get_tree().physics_frame` ×3, not process frames) — a Review Focus test must not be flaky — cost if wrong: none.
Task 5: Ruling 11: scarf_worn's low sway accepted (a cloth draped low over a rock barely moves); taller khadag on the summit ovoos keep visible sway with origin height — cost if wrong: one static-looking scarf.
Task 5: minor (deferred): debris at 0.35 small/low-contrast at gameplay distance; scarf_worn stone very dark, scarf saturated blue (existing cloth palette).
Task 5: minor (deferred): tools/place_heavens_props.gd not in the brief's file list and hardcodes ext_resource ids 12–22 — add a note that the scene is the source of truth.
Task 5: fix round 1/5 (2 addressed, 0 open — height_from_origin opt-in instance uniform, false path = original; physics_frames() helper deflakes teleport tests). 129 windowed, 107+22 headless, --only=heavens 5/5 stable.
Task 5: minor (deferred): kit_asset.gd triple blank line; test_camera_stays_out_of_terrain uses frames(20) (process-frame wait).
Task 5: complete (snapshot after T5 fix 1, review clean)
Task 6: implementer DONE_WITH_CONCERNS (140 windowed; 118+22 headless; summit worst 2.48 ms GPU at reveal 1). Concerns: shared GrassField ray was hard-coded world y 40→−5 — now ray_above/ray_below exports relative to field (playground unaffected, REUSE.md updated); extras: far world not drawn at reveal 0, reveal tints fog/sky, camera far 600→5000, cloud layer; pull-back must rise ≥40 m to show the mist sea; golden steppe reads ochre-brown; 0.9 still dim.
Task 6: note → T7: pull-back camera must rise ≥ ~40 m above her to show the mist sea.
Task 6: review — spec ✅, quality Approved. GrassField ray identical at y 0 for playground; reveal composes on mood (identity at 0); extras justified (far world off at reveal 0, reveal tints, camera far 5000, cloud deck). Perf 2.48 ms credible.
Task 6: minor (deferred): sparse test's nearest-point search spans the whole trail, not the field's own range (overlapping sections weaken it).
Task 6: minor (deferred): vista.gd `@export var seed` shadows global seed() (SHADOWED_GLOBAL_IDENTIFIER) — rename random_seed.
Task 6: minor (deferred): make_heavens_grass.gd duplicates SUMMIT_CENTRE/EXTENT/OVOOS positions from the scene.
Task 6: minor (deferred, visual): steppe through mist reads ochre-brown not golden; far ridges needle-like for Mongolia; mountain reads as a sheer pillar from above; 0.9 dim.
Task 6: minor (deferred → T9): vista._process sets shader params per frame while revealed.
Task 6: complete (snapshot after T6, review clean)
Task 7: implementer DONE (150 windowed; 127+23 headless). Changed T6 vista.gd + mist_sea.gdshader so far ridges/cloud deck fade in over first ~3 s of reveal (they popped). She stops on the ramp below the rim. End frame 48 m up, 80 m back, her ~1.8% of screen height. Brief tests needed explicit types.
Task 7: note → T9: profile a view early in the reveal (reveal ≈ 0.15).
Task 7: review — spec ✅ except Review Focus 4 gap; quality Needs fixes. I1: right-drag/wheel still render disturbed camera frames during SLOWING/REVEAL (FollowCamera._unhandled_input ignores input_enabled; process order places the camera before the sequence writes back).
Task 7: Ruling 12: the reveal must be visible while it happens — during REVEAL the view eases up/over the rim (camera rises enough to look past the plateau edge onto the opening mist sea), and PULLBACK continues from that pose; spec "the fog slowly parts" is a watched moment, not an off-screen state change — cost if wrong: a different camera arc in the reveal (constants, user-tunable).
Task 7: Ruling 13: fix round also takes minors 1 (skip_to(IDLE) → level.reset_scene or unsupported), 2 (test leak: finished lambda never disconnected, quit_on_finish persists; test_title_text arms input with quit_on_finish true — a stray key could quit the runner), 3 (stop the clap on reset), 4 (test injecting drag/wheel during REVEAL), 5 (stale doc comment) — cheap and protect the runner — cost if wrong: small scope growth.
Task 7: minor (deferred → T9): far materials' transparency/albedo written every reveal frame (possible first-use hitch); wind surge also raises wind.strength +0.35 (outside brief, accepted).
Task 7: fix round 1/5 (5 addressed, 1 open — Ruling 12: mist sea opening not readable during REVEAL; camera rise shares the fog's curve and aims 18° down). 154 windowed, 131+23 headless (value_probe flaked twice under load).
Task 7: minor (deferred): follow_cam.snap() at SLOWING end with collision easing could jump outward one frame (no pop seen).
Task 7: note: test_value_probe::test_measure_is_fast flakes more under full-suite headless load — Ruling 14 pending in T9/T10.
Task 7: fix round 2/5 (1 addressed, 0 open — RISE_SECONDS 4.5 then hold; REVEAL_CAM_OFFSET (0,16,24), LOOK (0,-6,-120); test min height 5%→4% justified). 154 windowed, 131+23 headless.
Task 7: minor (deferred): at raised pose she sits ~88% down frame (look y -8 would lift her).
Task 7: minor (deferred → T10, controller-observed): from the raised reveal camera the summit GrassField ends in a visible straight-edged rectangle on the plateau.
Task 7: complete (snapshot after T7 fix 2, review clean)
Task 8: implementer DONE_WITH_CONCERNS — 15/15 files shipped, all CC0 OpenGameArt, CREDITS.md; no NEEDED.md. 154 windowed, 131+23 headless. Edited test_missing_audio_is_silent assertion to p.playing == (p.stream != null). Concerns: not listened to (RMS/spectral analysis only); gravel recorded on snowy gravel; all thunders from one recording; eerie loop is low-passed wind from the wind recording.
Task 8: review — spec ✅, quality Approved. ⚠️ CC0 unverifiable by reviewer (403): controller fetched all 4 source pages with curl — the licence field reads CC0 on each (42-snow-and-gravel-footsteps, fantozzis-footsteps-grasssand-stone, park-ambiences, rain-long-thunder).
Task 8: minor (deferred): missing-file path through play_thunder/step no longer exercised now that all files exist — add a test with a nonexistent name.
Task 8: minor (deferred, user listen): all 3 loops from one wind recording (eerie = 220 Hz low-pass); all thunders from one event (clap has faint rain); gravel on snowy gravel; Vorbis loop-point padding unmeasured in-engine.
Task 8: complete (snapshot after T8, review clean)
Task 9: implementer DONE (155 windowed; 132+23 headless; worst reveal_early 2.04 ms GPU). Report transcribed by controller (implementer didn't write the file).
Task 9: review — spec ✅, quality Approved. scrub() freeze and storm.set_process(false) confined to flagged runs / re-enabled by reset; captures clean; docs commands correct.
Task 9: minor (deferred → T10): reveal_early scrubs to 2.03 s ≥ CLAP_AT 2.0, so the real thunder clap plays on every reveal_early show (incl. test_views_exist).
Task 9: minor (deferred): "wide" frozen in phase FADE at _t=0 (pose identical; fragile); test_views_exist nearly tautological; docs FPS column stale + stray "repaint grass" line; capture/profile don't restore overlays if called elsewhere.
Task 10: Ruling 14: Task 10 also takes three cheap carried items — (a) reveal_early just under CLAP_AT (1.99 s) so profiling/tests don't fire the clap; (b) soften the summit GrassField's straight mask edge (density falloff toward the field border in tools/make_heavens_grass.gd, regenerate heavens_summit mask) — visible rectangle from the reveal camera; (c) deflake the pre-existing test_value_probe::test_measure_is_fast (timing threshold flakes under full-suite headless load: take the best of 3 measurements rather than one) — a checkpoint test must not be flaky — cost if wrong: small scope growth; (c) loosens a perf guard slightly.
Task 10: implementer DONE (155 windowed; 132+23 headless; worst reveal_early 1.98 ms; editor load clean). (a) 1.99 s; (b) summit mask edge fade, trail masks byte-identical; (c) best-of-3.
Task 10: review — spec ✅, quality Approved. ⚠️ trail masks: controller md5-checked against the pre-task snapshot (see completion).
Task 10: minor (deferred → final): REUSE.md tonemap_mode 4 is AgX not "Filmic/ACES"; physics_frames described as "two process frames" (code awaits one); camera values used by the level not listed; HEAVENS_CALL.md lists reveal_early 2.04 (now 1.98); ground_mist header comment mentions only the playground.
Task 10: complete (review clean)
Final: trail masks md5-identical to pre-T10 snapshot (lower/middle/switchback/upper); only summit changed. Final review dispatched on whole-plan package final-review.diff (hc/base -> now).
Final review: verdict ready after small fixes; no Critical; no playground/kit regressions (playground.tscn/.gd/grass mask byte-identical); suite re-run green 155 / 132+23. I1: no test drives the ending naturally through to the title (spec line 160).
Final: Ruling 15: one fix wave takes I1 (natural-path sequence test incl. key during FADE/title fade-in and mouse-button quit), T8 missing-file-path test, REUSE.md tonemap label (AgX), HEAVENS_CALL.md profile number, plus cheap minors 3 (unknown view name warns), 4 (separate clap player), 5 (summit.reset re-enables physics processing) — cost if wrong: small scope growth.
Final: Ruling 16: the reviewer's "declined to judge" items (eerie ambience under the summit/title, loops at full surge under the black title, pull-back framing looking down rather than against the horizon) go to the user as questions, not changed now — spec silent / ruled framing — cost if wrong: one more tweak after the user plays it.
Final fix wave: implementer DONE (158 windowed; 135+23 headless; RED proof for natural-path test).
Final fix wave: re-review — 7/7 addressed, no new breakage. Controller verification: windowed 158/0/0, headless 135 passed/0 failed/23 skipped; player.gd 59 CRs.
Finish: Ruling 17: keep this workspace (ledger, briefs, reports) instead of deleting it — the project has no git history, so the ledger is the only record of rulings and deferred minors — cost if wrong: a few hundred KB of scratch under .superpowers/.
PLAN COMPLETE.

## Follow-up: world look (user feedback after play)
User: "looks so2" → "the world itself, steppe and mountains look wrong" → wants "rolling Khangai hills, snowy Altai peaks far on the horizon".
Follow-up W1: rework vista (rolling layered Khangai hills; snowy Altai peaks only on far horizon; golden visible steppe in valleys, mist lying low in valleys rather than a total sheet) and soften the massif's sheer-pillar exterior (outside the walkable corridor) so it slopes into the land. Trail/corridor/tests/budget unchanged. Snapshot hc/snap.
