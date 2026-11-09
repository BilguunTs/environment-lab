# Task 7 report: Summit sequence, fade and title

**Status: DONE.** Windowed: 150 passed. Headless: 127 passed, 23 skipped. Both are fully green.

## What I implemented

The new `SummitSequence` node takes over once furthest progress reaches 0.97. It runs these phases in order: SLOWING, REVEAL, PULLBACK, FADE, TITLE. Each frame it computes everything from the current phase and the seconds spent in it, with every move eased in and out (sine). This makes `skip_to(p)` simple: it sets up the start state of the phase and the clock begins again.

- **SLOWING (2 s):**
  - Control is taken away from her. Her horizontal velocity eases from its value at the start down to 0.
  - Her `Model` turns to face −Z (yaw π).
  - The gameplay camera eases its yaw, pitch and distance round behind her to the look pose (yaw 0, pitch 16°, distance 9 m).
- **REVEAL (8 s):**
  - `vista.reveal` eases from 0 to 1.
  - `mood.wind_surge` eases from 0 to 1 over the first 5 s.
  - `soundscape.play_thunder(true)` plays once, 2.0 s in.
  - The camera pose is held each frame, so a stray right-mouse drag or wheel zoom cannot move it.
- **PULLBACK (12 s):** `SummitCamera` starts from the gameplay camera's exact transform and becomes current. It then cranes back and up along an eased arc, described below.
- **FADE (4 s):** `UI/Fade` alpha eases from 0 to 1 over the held end frame.
- **TITLE:**
  - `UI/Title` fades in over 2 s. It is centred, its text is `Heavens call`, and it sits under the `UI` CanvasLayer, which is in the "overlay" group.
  - After that, `input_armed` becomes true. The next pressed key (not an echo) or pressed mouse button emits `finished` and then quits, unless `quit_on_finish` is false.
  - This is handled in `_input`. It does not use input actions.

### Files

**New:**
- `scripts/levels/summit_sequence.gd`
- `tests/test_heavens_summit.gd`

**Modified:**
- `scripts/levels/heavens_call.gd`:
  - Adds `summit`. `_fade` is renamed to the public `fade`.
  - `_physics_process` calls `summit.start()` at ≥ START_PROGRESS while the sequence is idle.
  - `reset_scene()` calls `summit.reset()` before the trail placement and the fade restart.
  - Adds `place_on_trail(p)`, which is public and counts the progress as reached.
  - Adds `stop_fade()`, which kills the fade-in tween.
- `scenes/levels/heavens_call.tscn`:
  - `SummitCamera` (Camera3D, fov 60, far 5000).
  - `UI/Title` (Label with full-rect anchors, h/v centred, size 64, off-white, modulate alpha 0).
  - The `SummitSequence` node, wired to `level`, `summit_camera` and `title_label`.
- `scripts/levels/mood_director.gd`: adds `wind_surge` and `SURGE_STRENGTH`.
- `scripts/levels/vista.gd` and `assets/shaders/mist_sea.gdshader`: the far world now fades in. This was a fix for a popping reveal; details are under "Decisions and deviations".

All of these files have LF line endings (0 CRs). `player.gd` was not touched and is still CRLF (59 CRs).

## Timing constants (in `SummitSequence`)

| Constant | Value |
|---|---|
| `SLOWING_SECONDS` | 2.0 |
| `REVEAL_SECONDS` | 8.0 |
| `PULLBACK_SECONDS` | 12.0 |
| `FADE_SECONDS` | 4.0 |
| `TITLE_FADE_SECONDS` | 2.0 |
| `CLAP_AT` | 2.0 |
| `SURGE_SECONDS` | 5.0 |
| `START_PROGRESS` | 0.97 |

The camera and tuning constants are `LOOK_YAW_DEG` 0, `LOOK_PITCH_DEG` 16, `LOOK_DISTANCE` 9, `FACE_YAW` π, `PULL_END_OFFSET`, `PULL_END_LOOK`, `PULL_ARC_LIFT` and `SKIP_PROGRESS` 0.975. In Vista, `FAR_FADE` is 0.3.

## Camera path

- **Start:** the gameplay camera's transform (behind her, 9 m out, pitch 16°), looking at her pivot. The handover is seamless.
- **End:**
  - The camera is at `her_feet + (0, 48, 80)`: 48 m above her and 80 m behind her toward +Z.
  - It looks at `her_feet + (0, −36, −300)`, out across the mist sea toward the gap in the ridges.
  - She is about 93 m from the camera, which makes her about 1.8% of the viewport height (13 px at 720p, 20 px at 1080p).
- **Path:**
  - Position follows a quadratic Bezier from the start to the end. Its control point is the midpoint raised by 18 m, which gives a gentle rising arc.
  - The look target slides linearly from her head to the end look point.
  - Both use the same eased parameter, 0.5 − 0.5·cos(π·t/12).
- **Tuning:** I went through three end frames. (70, 120) left her an unreadable 8 px speck, and so did (60, 100). (48, 80) makes her a clear tiny orange figure among the three ovoos. All three end frames show the full mist ocean.

## How the wind surge composes with the mood

`MoodDirector.wind_surge` (0..1) is applied inside `apply()` on top of the mood sample every frame:
- `vol_wind_strong = lerp(mood.vol_wind_strong, 1.0, wind_surge)`
- `wind.strength = mood.wind + 0.35 · wind_surge`, so the summit's 1.45 becomes 1.8. This is a visible gust in the grass, mist and scarves, added beside the audio.

`current` still holds the mood's own values. The sequence only writes `wind_surge`, so nothing gets overwritten the next frame. `reset()` sets it back to 0.

## RED/GREEN evidence

1. **First RED:** the test file did not parse because `SummitSequence` did not exist yet.
   - The run also exposed a bug in the brief's verbatim test: `var cam := lv.get_viewport()...` with an untyped `lv` is a parse error ("Cannot infer the type"). I changed `cam`, `top` and `foot` to explicit types (`Camera3D`, `Vector2`) and left the logic unchanged.
2. **`test_input_ignored_until_title` RED:** I implemented everything except the input handler, with `_input` renamed to `_input_DISABLED_FOR_RED`. Result: 7 passed, 1 failed, with "a key after the title finishes". That shows the test really depends on the handler. With `_input` restored it passes windowed and headless, so `Input.parse_input_event` does reach `_input` in the runner.
3. **GREEN:** `--only=heavens_summit` gave 8 of 8 windowed and 7 + 1 skipped headless. Later, `--only=heavens` gave 52 of 52 windowed.

**Tests added beyond the brief:**
- `test_pullback_keeps_her_in_frame`: she is inside the frame with a 5% margin, and the camera is at least 40 m above her.
- `test_slowing_is_gentle`: 0.8–2.0 m/s at 0.5 s with move_forward held, under 0.05 m/s at the end, and she faces −Z.
- `test_reveal_opens_slowly_with_clap_and_surge`: reveal is under 0.1 after 1 s, the clap has played by 2.3 s, wind_strong is at 0 dB in PULLBACK, and the other loops still follow the mood.
- `test_reset_returns_to_gameplay`
- `test_far_world_fades_in`: written before the Vista fix.
- `test_skip_to_from_any_phase`: written after I found and fixed the bug where skipping back to SLOWING left reveal and fade untouched, so it was never seen RED.

`test_input_ignored_until_title` also sends a key release at the end, so no key stays held in `Input` for later tests.

## Suite results (final code)

- **Windowed:** 150 passed, 0 failed, 0 skipped. The earlier count was 140; this task adds 10.
- **Headless:** 127 passed, 0 failed, 23 skipped. The earlier count was 118 + 22; `test_pullback_makes_her_tiny` is the new skip. The flaky timing test did not fail.

## Captures

The capture script is `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t7\cap.gd`. It walks her in for real: she starts at 0.955 with the camera orbited 25° off-axis, holds move_forward, and the sequence takes over. Shots are 1280×720, windowed, in `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t7\shots\`:

- `a_slowing_start.png`: the climb camera as the sequence takes over.
- `b0_reveal_t0.png`, `b1_reveal_t3f.png`, `b_reveal_1s.png`: the first second of REVEAL looks almost the same as the closed fog. There is no pop; the far world is barely beginning.
- `c_reveal_mid.png` (reveal 0.52): the fog is thinning, the cloud deck is forming, and the left ridges and the sea are emerging softly.
- `d_pull_0_5s.png` (reveal 1, start of the crane): the ridges, the sea to the left of the summit and the ovoos on the rim.
- `e_pull_mid.png`: rising over the summit, with her as a small figure on the plateau.
- `f_pull_end.png`: **the last image.** The whole ocean of mist runs to the horizon between the two flanks of ridges, under a stormy slate sky. The summit plateau sits bottom-centre with the three ovoos, and she is a tiny orange figure on it. Vast world, tiny her.
- `g_fade_mid.png`: the same frame halfway to black.
- `h_title.png`: black, with "Heavens call" centred in off-white.

`pop_0.0.png`, `pop_0.0001.png`, `pop_0.05.png`, `pop_0.12.png` and `pop_0.25.png` (script `pop.gd`) are the controlled pop comparison described below.

## Decisions and deviations

1. **Reveal pop fix (Task 6 files touched).**
   - The problem: Vista's `far` node only draws while reveal > 0, but the mood's fog does not hide it. At reveal 0.0001 the ridges and the cloud deck appeared at once (`pop_0.0` compared with `pop_0.0001`). That breaks the "reveal that pops" anti-goal.
   - The fix: `Vista.far_fade()` = smoothstep(0, 0.3, reveal).
     - The steppe and ridge materials blend in with `TRANSPARENCY_ALPHA_DEPTH_PRE_PASS` and render_priority −1 while fading, then go back to opaque at fade 1.
     - The mist and cloud slabs get a new `opacity` uniform. Scaling thickness was not enough, because grazing rays still went fully opaque and left a hard grey horizon. I tried alpha-hash first, but its dithering was visibly noisy (`pop_0.12` from that attempt was overwritten).
   - The far world now emerges over roughly the first 3 s of the reveal.
2. **Camera look pose during SLOWING and REVEAL.** The camera swings behind her, looking −Z, at pitch 16° and 9 m. She stops on the ramp just below the plateau rim (progress about 0.973). This pose sees a little past the rim, so the reveal reads.
   - The player's own pitch and distance are saved and given back on reset.
   - The camera's yaw, pitch and distance are written every frame during these phases, so mouse orbit and zoom cannot disturb the move. `follow_cam.input_enabled` only gates Q/E; it is set false and then back to true.
3. **Slowing mechanism.** While SLOWING, `player.acceleration` is set to 0 so the player's own fast lerp to rest does not cut in. The sequence then writes her horizontal velocity at `process_physics_priority` −10, which is before `Player._physics_process`. Acceleration is restored at the end of SLOWING, on any `skip_to`, and on reset.
4. **`skip_to` from IDLE moves her.** If she is not yet at progress ≥ 0.97, `skip_to` puts her at `SKIP_PROGRESS` 0.975, where a walk-in stops. This makes the PULLBACK, FADE and TITLE states meaningful for tests and for Task 9's captures, because the camera path is relative to her. If she is already at the summit, she is not moved.
5. **Sound after the reveal.** The wind stays surged through the fade and the title, and nothing fades it out. The brief does not ask for an audio fade-out; one could be added later.
6. **`quit_on_finish` is not reset by `reset_scene()`.** It is configuration, not state.

## Self-review

- Every transition uses `ease_in_out`. At each phase end I write the final value (reveal 1, fade 1, title alpha 1, pull at e = 1), so frame timing cannot leave a value short.
- The fade-in tween is killed by `stop_fade()` whenever the sequence takes the Fade, and reset restarts it.
- The `start()` guard and HeavensCall's check against IDLE make sure it fires only once.
- `skip_to` covers IDLE (reset), SLOWING (resets reveal, surge, fade and title, then begins from current motion) and REVEAL through TITLE from any phase, backwards included, and it is tested. It always clears `input_armed` and `clap_played`.
- The pull-back start is seamless: at e = 0 the camera is exactly the gameplay camera's transform, and for e > 0 it uses look_at from her pivot, which is the same target the follow camera used.
- The Player script is untouched and still CRLF. Every new or modified file is LF.

## Concerns

- **GPU budget not re-profiled.** At steady state (fade 1) the render is the same as Task 6, apart from one uniform multiply in the mist shader. During the first ~3 s of the reveal, the ridges and steppe draw as depth-prepass transparents, which should cost little at the summit. Task 9's profile pass should still include a reveal view at about 0.15.
- **The REVEAL is seen from the ramp below the rim**, because 0.97 is reached before the plateau top. Ridges and sky open above the rim and the sea shows to the left. The full ocean only appears in the pull-back. If the user wants the reveal seen from the plateau itself, `START_PROGRESS` (a verbatim value) or the look pose would need to change.
- **The brief's verbatim test needed type annotations to parse**, as described above.

---

## Fix round 1

### Changes

1. **Mouse could still move the camera during the sequence (Important, Review Focus 4).**
   - `FollowCamera` has a new flag, `orbit_locked` (default false). While it is true, `_unhandled_input` ignores the right-drag orbit and the wheel zoom, and `_process` ignores Q/E. The playground never sets the flag, so its camera behaves exactly as before.
   - `SummitSequence._take_control()` sets the flag and `reset()` clears it.
   - The sequence now also runs with `process_priority = -10`, so its SLOWING orbit writes land before `FollowCamera._process` places the camera. The one-frame lag is gone.
   - From REVEAL onward the gameplay camera is no longer current, so it ignores mouse input anyway.
2. **The reveal is now watched while it happens (Ruling 12).**
   - At the end of SLOWING the gameplay camera is snapped to its look pose, and SummitCamera takes over from that exact transform at the start of REVEAL.
   - Over the 8 s of REVEAL, SummitCamera rises, eased in and out, to `her_feet + (0, 12, 14)`, looking at `her_feet + (0, −6, −40)`. The path is a quadratic Bezier lifted 2 m in the middle.
   - PULLBACK then continues from that pose to the unchanged end frame (48 / 80, looking at −36 / −300, arc lift 18).
   - Both moves ease to zero speed where they meet, so there is a soft settle at the REVEAL/PULLBACK boundary but no pop and no cut.
   - New constants: `REVEAL_CAM_OFFSET`, `REVEAL_CAM_LOOK`, `REVEAL_ARC_LIFT`.
   - `skip_to(REVEAL)` hands over at the look pose. `skip_to(PULLBACK)` puts the camera at the end pose of the rise.
   - This is a deliberate deviation from the brief's "PULLBACK takes over from the gameplay camera", ordered by the ruling.
3. **Cheap items:**
   - a. `skip_to(IDLE)` now calls `level.reset_scene()`, which is a full reset: the vista closes, the fade-in from black starts again, and she goes back to the foot, so the sequence does not restart.
   - b. In `tests/test_heavens_summit.gd`:
     - `before_each` sets `quit_on_finish = false` for every test.
     - `after_each` restores it, disconnects the `finished` handler (now kept as a member Callable), re-enables processing on the sequence, and restores the camera's collision mask.
   - c. `Soundscape.stop_one_shots()` stops the thunder and footstep players, and `reset_scene()` calls it. There is also a new `thunder_playing()` query.
   - d. The camera doc comments now match the constants (16°, 9 m).

**Files changed this round:**
- `scripts/camera/follow_camera.gd`
- `scripts/levels/summit_sequence.gd`
- `scripts/levels/heavens_call.gd`
- `scripts/levels/soundscape.gd`
- `tests/test_heavens_summit.gd`

All are LF with 0 CRs.

### New tests and RED evidence

- **`test_camera_ignores_mouse_during_sequence`**
  - The SLOWING half freezes the sequence, sets the camera's collision mask to 0 and waits for the camera to settle. The collision mask is turned off because the camera's slow ease-out after a collision hit moves it on its own by a few cm per second, which made the first version of the test fail even with the fix in place.
  - It then injects a right-button press, three right-drag motions and a wheel-up, and checks that the transform is unchanged. The REVEAL half does the same on SummitCamera and also checks that the gameplay orbit's yaw, pitch and distance are unchanged.
  - **RED** with the `orbit_locked` gate removed from `_unhandled_input`: "SLOWING: camera unmoved by drag and wheel (moved 5.8194 m, orbit −45.00/33.75/7.20)".
- **`test_skip_to_idle_is_a_reset`**
  - **RED** with the old `reset()` routing: "idle and staying idle: expected 0, got 1", "vista closed: expected 0.0, got 1.0" and "back at the foot".
- **`test_reset_stops_one_shots`** (uses an `AudioStreamGenerator` on the Thunder player)
  - **RED** without the `stop_one_shots()` call: "thunder stopped on reset".
- **`test_reveal_rises_over_the_rim`**: at the end of the rise, the camera is at least 10 m above her, she is more than 5% of the viewport height, and she is in frame.
  - I did not run it against the old code. By the numbers it would have failed: the old PULLBACK started at the follow camera, about 4 m above her.
- **Updated:** `test_skip_to_from_any_phase` now expects SummitCamera in REVEAL.

### Commands and output

All of these were run from the project root with `G=/d/softwares/Godot_v4.6-stable_mono_win64/Godot_v4.6-stable_mono_win64_console.exe`.

- **RED** (gates temporarily removed), `"$G" --path . -s res://tests/run.gd -- --only=heavens_summit`: 11 passed, 3 failed (the three listed above).
- **GREEN**, `"$G" --headless --path . -s res://tests/run.gd -- --only=heavens_summit`: 13 passed, 0 failed, 1 skipped.
- `"$G" --path . -s res://tests/run.gd -- --only=heavens`: **56 passed, 0 failed, 0 skipped**.
- **Full windowed**, `"$G" --path . -s res://tests/run.gd`: **154 passed, 0 failed, 0 skipped**.
- **Full headless**, `"$G" --headless --path . -s res://tests/run.gd`:
  - First run: 130 passed, 1 failed (`test_value_probe::test_measure_is_fast`, 4.12 ms against a 4 ms limit).
  - Rerun: the same test failed again at 4.40 ms.
  - Third run: **131 passed, 0 failed, 23 skipped** (measure 2.30 ms).
  - The test times an image histogram on the CPU and does not touch anything I changed. Run alone it passes three out of three times (2.28–2.46 ms). My guess is the machine was loaded right after the windowed suite. Note that it took two reruns, not one, to get green.

### New captures

Shots are in `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t7\shots_r1\`, taken with the walk-in script `cap_r1.gd` at 1280×720, windowed:

- `b_reveal_1s.png`: the camera has just started to lift behind her. The fog is still closed and the scene matches the end of SLOWING. No pop.
- `c_reveal_mid.png`: the camera has risen over the rim. The whole golden plateau with its three ovoos lies ahead of her, and the mist sea is visibly forming to the left beyond the cliff, with the ridges faint through the thinning fog. This frame differs clearly from b, so the opening reads as it happens.
- `c2_reveal_end.png` (reveal 1, the first frame of PULLBACK): the full scene is open. The ocean of mist runs to the horizon between the ridge flanks, the ovoos stand on the rim, and she is clear and fairly large in the lower centre (about 8% of frame height).
- `e_pull_mid.png` and `f_pull_end.png`: the crane carries on smoothly from c2. The end frame matches the previous round's: the vast mist ocean and ridges, the summit with its ovoos, and her as a tiny orange figure.
- `a`, `d`, `g` and `h` were also re-taken, and the fade and title are unchanged.

### Concerns

- At the end of the rise she sits low in the frame (about 83% down). It reads well, but `REVEAL_CAM_LOOK` can be lowered a little if the user wants her higher.
- The speed of the camera drops to zero at the REVEAL/PULLBACK boundary. This reads as a brief settle, not a stop-start, but it is there.
- `test_measure_is_fast` is flaky under full-suite load, as described above.

---

## Fix round 2 (Ruling 12: the reveal must be watched while it happens)

### Changes (`scripts/levels/summit_sequence.gd`)

- **The camera rise has its own clock.** New constant `RISE_SECONDS := 4.5`. REVEAL now places the camera with `_place_rise(ease_in_out(_t / RISE_SECONDS))`. The rise is finished 4.5 s into the 8 s REVEAL and then holds. The fog still opens on the full 8 s clock, so its second half is watched from the raised pose.
- **Flatter aim from a higher, further pose.**
  - `REVEAL_CAM_OFFSET` goes from (0, 12, 14) to **(0, 16, 24)**.
  - `REVEAL_CAM_LOOK` goes from (0, −6, −40) to **(0, −6, −120)**.
  - The aim is now about 9° down instead of 18°. The horizon sits about 38% from the top of the frame, and the mist sea fills the middle band with her low in it.
  - `REVEAL_ARC_LIFT` stays at 2.
- **The pull-back is unchanged.** It still starts from the raised pose and runs to the same end frame (48 / 80, looking at −36 / −300, arc lift 18) over 12 s, eased. The camera holds still from 4.5 s to 8 s of REVEAL, then PULLBACK eases out of that hold, so there is no pop.
- The doc comment for the rise constants now describes the shorter clock and the hold.

### Test change

`test_reveal_rises_over_the_rim` now requires her to be more than **4%** of the frame height, down from 5%.
- At the new pose she is about 29 m from the camera, which works out to about 5.5% of a 60° frame. The old 5% threshold would sit right at the edge of that.
- 4% still clearly separates "clear in frame" from the pull-back end's tiny 1.8%.
- The checks for at least 10 m of height and for her being in frame are unchanged.

### Commands and output

Run from the project root, with `G` set to the Godot console executable.

| Command | Result |
|---|---|
| `"$G" --path . -s res://tests/run.gd -- --only=heavens_summit` | 14 passed, 0 failed, 0 skipped |
| `"$G" --path . -s res://tests/run.gd -- --only=heavens` | **56 passed, 0 failed, 0 skipped** |
| `"$G" --path . -s res://tests/run.gd` (full, windowed) | **154 passed, 0 failed, 0 skipped** |
| `"$G" --headless --path . -s res://tests/run.gd` (full, headless) | **131 passed, 0 failed, 23 skipped** |

In the headless run the timing test measured 2.23 ms and passed first time. Both changed files are LF with 0 CRs.

### Captures

Shots are in `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t7\shots_r2\`, made with the walk-in script `cap_r2.gd` at 1280×720, windowed. The frames are taken by the sequence's own clock.

- `reveal_1s.png` (reveal 0.04): the camera has started lifting. The fog is still closed and she stands large on the ramp below the golden rim.
- `reveal_3s.png` (reveal 0.31): the camera is over the rim and the whole plateau and ovoos lie below. Thick fog surrounds the summit, the ridge silhouettes are faintly beginning, and the sky band shows the first cloud texture.
- `reveal_4s.png` (reveal 0.50, mid): the mist sea is visibly forming across the middle of the frame, either side of the summit and behind the ovoos. The ridges are emerging, and she is clear at the bottom centre.
- `reveal_5s.png` (reveal 0.69, rise done): the sea is plainly open across the middle band, with the left ridges and right flanks taking shape through the last haze.
- `reveal_end.png` (reveal 1.0): fully open. The ocean of mist runs to the horizon between the ridge flanks, the ovoos stand on the rim, and she is a clear small figure at the bottom centre.
- `pull_0_5s.png`: almost the same as `reveal_end`, as the crane eases out of the hold. No jump.
- `pull_mid.png`: rising and backing away. The summit is shrinking against the sea and she is a small figure on the plateau.
- `pull_end.png`: the same end frame as before. Vast mist ocean and ridges, the summit with its ovoos, and her as a tiny orange figure.

**Verdict:** across 3 s, 4 s, 5 s and the end, the sea of mist visibly opens in the middle of the frame while she stays in view. The opening now reads while it happens rather than only at the pull-back.

### Concerns

- At the raised pose she sits fairly low, about 88% down the frame, around 12% above the bottom edge. Lowering the look target's y slightly (for example to −8) would lift her a little if the user wants that.
- The camera holds still from 4.5 s to 8 s of REVEAL while the fog finishes opening, then PULLBACK eases out of that hold. This is intended, so the opening is watched from a steady view.
