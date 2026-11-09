# Task 3 report: mood director and storm

**Status:** DONE_WITH_CONCERNS (minor: one interpretation of the blend rule, see Decisions 1; a flaky pre-existing timing test)

## Implemented
- **`MoodDirector`** (`scripts/levels/mood_director.gd`, `class_name MoodDirector extends Node`)
  - `const KEYS` (4 keys at 0.0 / 0.28 / 0.57 / 0.86) with every field in the brief, plus two extras:
    `ambient` (ambient energy) and `sun_color`. The value table is a comment table at the top of the file.
  - `static func sample(progress)`: a smoothstep blend between the neighbouring keys, with colours lerped. The
    GATED fields (`lightning_per_min`, `vol_eerie`) are handled differently; see Decisions 1.
  - `func apply(mood)` drives these, then remembers the mood as `current`:
    - `Wind.strength`
    - a slow `Wind.direction_degrees` wobble: base ± `wind_swing_deg`, a 41 s swing plus a 13 s ripple
    - `fog_density`, with the volumetric fog set to 0.45× of it
    - fog, background and ambient colour (= `sky_color`) and ambient energy
    - sky `horizon_color` and `zenith_color`
    - sun energy and colour
    - mist density and `Storm.rate_per_min`
    - the storm flash overlay (`storm.light(...)`)
    - `soundscape.set_volumes(...)` if a soundscape is set and has the method. `@export var soundscape: Node`
      is optional and null until Task 4.
  - `_process`:
    - keeps the `Mist` FogVolume centred on the girl and sets its `base_height` to 4 m below her feet
    - drifts the mist noise with the wind. This is the playground's integrated-offset code without the panel
      plumbing.
  - Exports: `wind`, `sun`, `world_environment`, `mist`, `storm`, `follow` and `soundscape`.
- **`Storm`** (`scripts/levels/storm.gd`, `class_name Storm extends Node`)
  - Members: `rate_per_min`, `flash_count`, `glow`, `signal flashed(delay_s)`.
  - `flash()`:
    - starts a 0.15–0.35 s decaying flicker with 2–3 pulses and a peak of 0.7–1.0
    - emits `flashed(randf_range(2.5, 6.0))` at once
  - Poisson scheduling: each frame there is a `rate/60·delta` chance of a flash, but never while a flash is running.
  - `light(sun, env, sky)` adds the flicker on top of the mood's lights:
    - sun +0.45·glow
    - ambient +0.5·glow
    - fog colour and sky horizon lerped up to 35% toward a pale blue-white
    - no light near her, no bolt
  - `reset()` restores a silent sky.
- **`HeavensCall`**
  - New members: `@onready mood`, `storm` and `mist`.
  - `_process` calls `mood.apply(MoodDirector.sample(furthest_progress))` each frame.
  - `reset_scene()` now also calls `storm.reset()` and applies `sample(0.0)`.
- **Scene** (`heavens_call.tscn`)
  - `Mist`: a FogVolume, 110×30×110, using the playground's mist material (same noise; `mist_height` 7)
  - `Storm`
  - `MoodDirector` (wired to Wind, Sun, WorldEnvironment, Mist, Storm and Player)
  - `GameplayCamera.collision_mask = 2`
- **`ground_mist.gdshader`**: a new `uniform float base_height = 0.0`. The height fade is now
  `smoothstep(base_height, base_height + mist_height, y)`. The playground is unchanged, since its default of 0
  gives the same formula.
- **Ruling 3, `FollowCamera`**
  - New `@export_flags_3d_physics var collision_mask := 0`; 0 = off, the playground's camera is unchanged.
  - When the mask is set, a ray from the pivot (look target) to the orbit goal shortens the distance to
    hit − 0.3 m (minimum 0.6 m).
  - It pulls in at once, so a wall is never seen from inside, and eases back out at 3/s, so it does not jitter.
    `snap()` skips the ease.
- **Ruling 4:** `test_walking_down_never_respawns` is added. Readability of 0.8–0.95 was checked and tuned; see
  the captures below.

## Final key table
| key              | ASCENT 0.00      | DISCOVERY 0.28   | EERIE 0.57       | SUMMIT 0.86      |
|------------------|------------------|------------------|------------------|------------------|
| wind             | 0.70             | 0.85             | 1.15             | 1.45             |
| wind_swing_deg   | 6                | 8                | 14               | 10               |
| fog_density      | 0.014            | 0.017            | 0.028            | 0.022            |
| mist             | 0.35             | 0.45             | 0.80             | 0.55             |
| lightning_per_min| 0                | 0                | 2.0              | 0                |
| sun_energy       | 1.30             | 1.10             | 0.80             | 1.00             |
| sun_color        | (1.00,0.88,0.74) | (0.95,0.86,0.76) | (0.80,0.82,0.88) | (0.95,0.84,0.70) |
| ambient          | 0.45             | 0.50             | 0.75             | 0.95             |
| sky_color        | (0.56,0.58,0.60) | (0.52,0.54,0.56) | (0.42,0.45,0.49) | (0.50,0.50,0.52) |
| zenith_color     | (0.34,0.39,0.46) | (0.31,0.35,0.41) | (0.23,0.26,0.32) | (0.28,0.30,0.36) |
| vol_wind         | 0.70             | 0.75             | 0.60             | 0.50             |
| vol_wind_strong  | 0.10             | 0.25             | 0.60             | 0.90             |
| vol_eerie        | 0                | 0                | 0.70             | 0.30             |

Every shape rule in the brief holds:
- lightning is 0 / 0 / 2.0 / 0
- wind rises across the keys
- `vol_eerie` is above 0 only from EERIE on
- fog is thickest at EERIE

## Files changed
- New: `scripts/levels/mood_director.gd`, `scripts/levels/storm.gd`, `tests/test_heavens_mood.gd`, plus the
  `.uid` files from `--import`.
- Modified: `scripts/levels/heavens_call.gd`, `scenes/levels/heavens_call.tscn`,
  `scripts/camera/follow_camera.gd`, `assets/shaders/ground_mist.gdshader`.
- Line endings: the CR count is 0 in every new or changed file. `player.gd` was not touched and is still CRLF
  (59 CRs).

## RED/GREEN evidence
- **RED:** `--only=heavens_mood` gave `FAIL test_heavens_mood.gd (does not parse)`, because `MoodDirector` is not
  declared. That gave 0 passed, 1 failed.
- **GREEN:** `--only=heavens` gave 18 passed, 0 failed, both windowed and headless.
- **Camera test checked against the real behaviour:** with `_collided_distance` temporarily forced to return
  `distance`, `test_camera_stays_out_of_terrain` failed. It reported "no ground between her and the camera" and
  "camera pulled in". I then restored the code.
- **The 9 tests in `test_heavens_mood.gd`:**
  - the brief's 5, kept verbatim
  - `test_mood_follows_furthest_progress`
  - `test_reset_clears_mood_and_storm`
  - `test_walking_down_never_respawns` (Ruling 4)
  - `test_camera_stays_out_of_terrain` (Ruling 3). It searches the yaws for one whose uncollided goal is behind
    terrain on layer 2. It then checks that the ray from the pivot to the camera is clear and that the camera
    pulled in.

## Suite results (checkpoint)
- **Windowed:** `115 passed, 0 failed, 0 skipped`. That is 106 + 9.
- **Headless:** `93 passed, 0 failed, 22 skipped`. That is 84 + 9.
  - Two of the three headless runs failed `test_value_probe::test_measure_is_fast` (4.30 and 4.48 ms against a
    4 ms limit). That test is a playground-only CPU timing test of `ValueProbe.measure` on an in-memory image,
    and it does not touch any code I changed. The third run was fully green.

## Captures (windowed, 1280×720)
The capture script is `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\capture.gd`.
It is outside the project. All PNGs are in the same `t3` folder:
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\mood_010.png`
  - Mean luminance 0.37.
  - Ascent: warm low sun, a long shadow, a clear brown path band up the slope, grey haze softening the distant
    wall and the sky.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\mood_040.png`
  - Mean luminance 0.29.
  - Discovery: a narrow gorge, greyer and cooler, with the path and her figure clearly readable and the far end
    fading into fog.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\mood_070.png`
  - Mean luminance 0.29.
  - Eerie: the thickest fog. The crags dissolve, the light is cold and blue-grey, and mist pools below the path.
    The winding path and her silhouette still read clearly. It is the most distinct of the four.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\mood_090.png`
  - Mean luminance 0.30, centre 0.25.
  - Late climb in the mountain's shadow: dark and moody. Her silhouette is clearly separated from the slope,
    and the path reads faintly as a warmer band.
  - **This is the Ruling 4 check.** It started out murky, with her almost invisible (centre luminance 0.18).
    A diagnostic pass found the cause: with fog off she was near-black (the ambient colour was the dark zenith
    at 0.6 energy), and the fog veil then flattened her. Fixes:
    - the ambient colour is now the pale horizon colour
    - ambient energy is 0.75 (EERIE) and 0.95 (SUMMIT)
    - the mist pools 4 m below her feet
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\flash_070.png`
  - The frame right after `storm.flash()` at 0.7. Mean luminance 0.33, against 0.29 without the flash.
  - The whole sky and fog lift slightly and cool toward blue-white. There is no hard light, no new shadows and
    nothing localised near her. It reads as a distant flicker behind the fog, not a strike.
- Diagnostic shots (fog/mist toggled at 0.9) are in the same folder: `d_base.png`, `d_nomist.png`,
  `d_novol.png`, `d_nofog.png`.

## Decisions and deviations
1. **Gated blend for lightning and eerie sound (interpretation).**
   - The problem: a plain smoothstep from DISCOVERY (0.28) to EERIE (0.57) would put lightning, about
     0.7/min, and eerie sound at 0.4. That breaks the brief's own `test_no_lightning_before_eerie` and the spec
     rule "none before EERIE".
   - The rule I used:
     - Every continuous value (wind, fog, mist, light, colours, wind volumes) blends across the whole interval
       between keys, as the brief says.
     - `lightning_per_min` and `vol_eerie` are GATED: inside stretch *i* they blend from key *i−1* to key *i*
       over `GATE_RAMP = 0.05` (about 35 m) after the stretch starts.
   - The result: no lightning or eerie sound before 0.57. They fade in over 0.57–0.62 and fade out over
     0.86–0.91 (lightning goes to 0 at the summit).
   - `test_sample_blends_between_keys` passes: wind is not gated.
2. **Storm flash and the mood.** `apply` writes the mood's base values every frame, so the flash cannot write
   the lights directly; the next `apply` would erase it.
   - Instead, `Storm.glow` holds the flicker envelope, and `Storm.light()` adds the boosts after the mood.
     MoodDirector calls it at the end of `apply`.
   - The flicker itself, its boost constants and the timing all live in Storm.
   - `flashed` is emitted at the moment of the flash, synchronously; the brief's test needs that within 1 frame.
     The delay is measured from the flash.
3. **Extra key fields.** `ambient` and `sun_color` were added, beyond the brief's list, to meet Ruling 4. Also:
   - `sky_color` sets the horizon, fog, background and ambient colour.
   - `zenith_color` sets the sky top.
4. **The mist follows her.** The playground's mist uses world y = 0 as the ground. On a 220 m mountain the volume
   follows the player instead, and the new `base_height` uniform anchors the height fade 4 m below her feet.
   Noise is sampled in world space, so moving the volume does not move the pattern.
5. **Camera.** I used `@export_flags_3d_physics` rather than a plain `@export var`. It is the same int type with
   a nicer inspector. The existing `y ≥ 0.15` clamp is kept.
6. **Apply timing.** `apply` is called in `_process`, every rendered frame. `furthest_progress` is still updated in
   `_physics_process` (Task 2).

## Self-review
- **Interfaces match the brief:** `KEYS`, `sample`, `apply`, `current`, `rate_per_min`, `flashed(delay_s)`,
  `flash()`, `flash_count`, and the per-frame `mood.apply(MoodDirector.sample(furthest_progress))`.
  `reset_scene` resets the mood and the storm.
- **Anti-goals:** the lightning is ambient-only and soft (+0.45 sun, +0.5 ambient at peak, 0.15–0.35 s), with no
  bolt and no local light. Nothing supernatural was added.
- **Playground is unaffected:**
  - camera mask 0 makes `_collided_distance` return early
  - the shader's `base_height` defaults to 0
  - the full windowed suite is green
- **Soundscape** is optional: it is null-checked, and `has_method` is checked.
- **Unused member:** `HeavensCall.mist` is unused for now. It is there for the Task 6/7 reveal.

## Concerns
1. **Wind direction wobble vs grass (Task 6).** `Wind` rotates the gust pattern about the world origin. The trail
   is 50–150 m from the origin, so even a slow ±14° wobble slides the gust pattern sideways by a few m/s there.
   The level has no grass yet. If it looks wrong once grass lands, reduce `wind_swing_deg` or lengthen
   `SWING_PERIOD`.
2. **GPU cost not measured.** The extra FogVolume (110×30×110) sits inside the volumetric fog that was already on.
   The 7 ms budget check belongs to the later perf task.
3. **Flaky playground timing test.** `test_value_probe::test_measure_is_fast` (4 ms limit) failed in 2 of 3
   headless runs on this machine. It is pre-existing and unrelated to this task, but the controller may want to
   relax it.
4. **0.9 still dark.** It is readable now, but it is the darkest stretch, and the path there is a faint band.
   Task 6's grass and props, or a summit-side sun adjustment, could lift it further if the user wants.

## Fix round 1

**Status:** DONE

### Changes
1. **0.86–0.95 readability.** The SUMMIT key is now:
   - `fog_density` 0.022 → **0.011**
   - `mist` 0.55 → **0.30**
   - `ambient` 0.95 → **1.15**
   - **Diagnosis** (toggle crops at 0.9, files `d2_*`/`d3_*` in the capture folder): the veil was mainly
     the depth fog's flat grey over a figure lit only by ambient light in the mountain's shadow. The mist and
     the volumetric fog each added little.
   - **Edges:** a zoomed crop (`d3_base.png`) shows her silhouette edges are sharp. What reads as softness is
     low contrast, from flat ambient-only shading.
   - **Fog ordering:** EERIE (0.028) is now clearly the foggiest. SUMMIT (0.011) is thinner than every other
     stretch, because the fog is about to part.
2. **Wind wobble.**
   - The fast 13 s ripple is gone. The swing is now a single sine over `SWING_PERIOD` **120 s** (was 41 s).
   - `wind_swing_deg` is now **4 / 5 / 6 / 6** (was 6 / 8 / 14 / 10).
   - Worst sideways slide at a 150 m radius is `150·rad(A)·2π/120` = 0.55–0.82 m/s. Downwind gust travel
     is 2.8–5.8 m/s, so the slide is under 20% of it at every key.
   - The `SWING_PERIOD` comment documents the formula.
3. **New tests** in `tests/test_heavens_mood.gd`:
   - **`test_gated_values_respect_stretch_edges`** (pins Ruling 5): `sample(0.56)` has lightning 0 and
     `vol_eerie` 0; `sample(0.62)` lightning == KEYS[2]; `sample(0.95)` lightning 0.
     - It passed on first run, because it pins behaviour that already existed.
   - **`test_wind_wobble_slide_is_slow`**: at every key, slide < 25% of `Wind.GUST_SPEED·wind`.
     - The old values would have failed it: EERIE gave about 5.6 m/s of slide against a limit of 1.15 m/s.

### New key values (full table in mood_director.gd)
| key            | ASCENT | DISCOVERY | EERIE | SUMMIT |
|----------------|--------|-----------|-------|--------|
| wind_swing_deg | 4      | 5         | 6     | 6      |
| fog_density    | 0.014  | 0.017     | 0.028 | 0.011  |
| mist           | 0.35   | 0.45      | 0.80  | 0.30   |
| ambient        | 0.45   | 0.50      | 0.75  | 1.15   |

All other values are unchanged.

### Commands and output
- `"$GODOT" --path . -s res://tests/run.gd -- --only=heavens` → `20 passed, 0 failed, 0 skipped`
- `"$GODOT" --path . -s res://tests/run.gd` → `117 passed, 0 failed, 0 skipped`
- `"$GODOT" --headless --path . -s res://tests/run.gd` → `95 passed, 0 failed, 22 skipped` (84 + 11)
  - This was the first run; the value-probe timing test did not flake this time.
- CR count is 0 in `mood_director.gd` and `test_heavens_mood.gd`.

### New captures (windowed, 1280×720)
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\fix1_mood_070.png`
  - Eerie, unchanged. The thickest fog: crags dissolve, the light is cold, and she is crisp in sunlight.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\fix1_mood_085.png`
  - In the mountain's shadow, and visibly thinner than 0.7: the far wall and skyline read through the fog.
  - The path is a clear warm band winding up, and her silhouette is clear.
  - It is dark and heavy, but not murky.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\fix1_mood_090.png`
  - A dark slope under a grey storm sky. The path band reads up to the skyline, and her silhouette is clear
    with sharp edges.
  - Before the fix she was veiled and the path was barely visible.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\fix1_mood_095.png`
  - The summit plateau in low sun, with a long shadow and a crisp figure.
  - The haze still closes off the horizon, so the vista stays hidden.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\t3\fix1_flash_070.png`
  - The flash at 0.7 is still a soft, whole-sky lift (mean luminance 0.33 against 0.29), with no local light.

### Remaining concern
- At 0.85–0.9 she is lit only by ambient light, so she reads as a flat silhouette with little shading. That is
  readable and moody. Task 6's props and grass will add more cues there.
