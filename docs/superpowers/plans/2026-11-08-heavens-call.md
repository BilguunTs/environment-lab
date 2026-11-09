# Heavens Call Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build *Heavens call*, a 5–7 minute walking level. A tired cloaked girl climbs a foggy
mountain trail, past war debris and then traveller traces, to a summit where the fog parts on a
vast Mongolian steppe. The camera pulls back, the screen fades, and the title appears.

**Architecture:** The level is one scene with a thin root script that wires small single-purpose
nodes:
- `Trail`: a `Path3D`, the source of truth for distance and progress.
- `MountainTerrain`: a `@tool` mesh and collision generated around the trail.
- `MoodDirector`: blends four mood keys by furthest progress.
- `Storm`: distant lightning and thunder.
- `Soundscape`: fixed audio file names; a missing file is silent.
- `SummitSequence`: the slow-down, reveal, pull-back, fade and title.

Props come from the Blender kit script. Grass, wind, fog and kit collision are reused per
`docs/REUSE.md`.

**Tech Stack:** Godot 4.6 (mono build, pure GDScript), Forward+, and Blender 5.1 for props
(`C:/Program Files/Blender Foundation/Blender 5.1/blender.exe -b -P assets/blender/build_kit.py`).

**Spec:** `docs/superpowers/specs/2026-11-08-heavens-call-design.md`. Read it first. The mood, the
anti-goals and the user's own words decide every look and sound call this plan leaves open.

This plan makes these calls inside the spec's "left to the builder" space:
- **Terrain.** It is generated in Godot from the trail curve (`MountainTerrain`), not sculpted in
  Blender, so walkable slope can be tested and the trail can be re-routed cheaply.
- **Trail surface.** It is part of the terrain (vertex colour), not a draped ribbon. Footsteps pick
  gravel vs rock by distance to the trail centreline.
- **Falling.** A player who leaves the playable area is put back on the trail.

## Global Constraints

- **Engine:** Godot **4.6**, pure GDScript, Forward+. No third-party plugins or paid services.
  Code style: tabs, `##` doc comments, typed vars, LF line endings (`scripts/player/player.gd` is
  CRLF; keep it so).
- **No git:** the project is **not** a git repo. Each task ends with a full-suite checkpoint, not
  a commit.
- **Paths:**
  - scene `scenes/levels/heavens_call.tscn`, root script `scripts/levels/heavens_call.gd`
  - level scripts in `scripts/levels/`
  - audio in `assets/audio/`, credits in `assets/audio/CREDITS.md`
  - new kit props: `scenes/environment/kit/prop_*.tscn` and `assets/meshes/prop_*.glb`
- **Title:** exact text `Heavens call`, centred.
- **Girl:**
  - the existing `scenes/player/player.tscn`, with the lantern **off** (no Lantern mesh, no
    LanternLight)
  - `walk_speed = 2.0`, **no sprint**
  - the playground's player keeps its lantern, its sprint and a walk speed of 3.5
- **Climb:** trail length **650–750 m**; walking time `length / 2.0` must be **300–420 s**.
  Walkable slope along the trail is **≤ 30°** (the player's floor limit is 45°).
- **Ground rule:** walkable collision is on layers 1 + 2 (`collision_layer = 3`). Grass and
  footsteps ray against layer 2 only.
- **Mood:** driven by **furthest** trail progress (0..1), never by time. Stretch boundaries in
  progress: `ASCENT 0.0`, `DISCOVERY 0.28`, `EERIE 0.57`, `SUMMIT 0.86`. The summit sequence
  starts at progress **≥ 0.97**.
- **Sound:**
  - Never music, dialogue or jump scares. A missing audio file is silent, never an error.
  - No procedural sound synthesis.
  - Fixed file names, all `.ogg`:
    - `wind_loop`, `wind_strong_loop`, `ambience_eerie_loop`
    - `footstep_gravel_1..4`, `footstep_rock_1..4`
    - `thunder_distant_1..3`, `thunder_clap`
- **Lightning:** none before `EERIE`. It is always distant and never startling. Thunder lags its
  flash by **2.5–6.0 s**.
- **Not used:** the playground's dev panel, presets, Compare, debug tools, monolith glow and spirit
  particles.
- **Budget:** ≤ **7.0 ms GPU** at 1920×1080 on the RTX 3070, in the worst capture view.
- **Overlays:** the fade and title `CanvasLayer` join the group `"overlay"`.

**Test command.** Run from the project root in Bash. Run `--import` whenever a task adds a
`class_name` or new assets.

```bash
GODOT=/d/softwares/Godot_v4.6-stable_mono_win64/Godot_v4.6-stable_mono_win64_console.exe
"$GODOT" --headless --path . --import >/dev/null 2>&1
"$GODOT" --path . -s res://tests/run.gd                       # full suite, windowed
"$GODOT" --path . -s res://tests/run.gd -- --only=heavens     # level tests only
"$GODOT" --headless --path . -s res://tests/run.gd            # logic only, image tests SKIP
```

**Baseline:** 96 passed windowed, 74 passed and 22 skipped headless. Every checkpoint must be all
green.

## Review Focus

1. **The player walks off the trail, falls off a cliff edge, or slips through the terrain.** She
   is put back on the trail at her furthest reached point, the mood doesn't reset, and nothing
   errors. Test: `test_fall_respawns_on_trail` (Task 2).
2. **The player walks back down the trail.** The mood stays at the furthest stretch reached, with
   no lightning switching off and no fog thickening back. Test: `test_mood_ignores_backtracking`
   (Task 3).
3. **`assets/audio/` is empty, or only some files exist.** The level runs silently with no engine
   errors, and present files play. Test: `test_missing_audio_is_silent` (Task 4).
4. **The player keeps pressing movement keys during the summit sequence, or presses keys before
   the title.** She stops gently, the camera move isn't disturbed, and only a key press after the
   title has shown quits. Test: `test_input_ignored_until_title` (Task 7).
5. **The sprint key (Shift) held at any time.** Speed never exceeds 2.0 m/s in this level, while
   the playground still sprints. Test: `test_no_sprint_in_level` (Task 1).

---

### Task 1: Player and camera options, scene-aware test runner, level skeleton

**Files:**
- Modify: `scripts/player/player.gd` (keep CRLF), `scripts/camera/follow_camera.gd`, `tests/run.gd`
- Create: `scenes/levels/heavens_call.tscn`, `scripts/levels/heavens_call.gd`,
  `tests/test_heavens_basics.gd`

**Interfaces:**
- Produces:
  - `Player`:
    - `@export var can_sprint := true`
    - `@export var lantern := true` (a setter hides `Model/Lantern` and `Model/LanternLight`)
  - `FollowCamera`: `@export var min_pitch := -10.0`, `@export var max_pitch := 80.0`. They
    replace the hard-coded clamp at `follow_camera.gd:36` and also clamp `pitch_deg` on set.
  - **`tests/run.gd`:**
    - A test file may declare `const SCENE := "res://..."`. Files without it run against
      `res://scenes/playground.tscn`, as today.
    - The runner instantiates each distinct scene once and runs its files in sorted order.
    - It calls `reset_scene()` before each test **if the scene root has it**.
  - **`HeavensCall` (`scripts/levels/heavens_call.gd`, `class_name HeavensCall extends Node3D`):**
    - `@onready var player: Player`, `follow_cam: FollowCamera`, `wind: Wind`
    - `func reset_scene() -> void`: puts the player back at the trail start, restarts the 3 s
      fade-in from black, and resets the mood and the sequence (later tasks extend it)
    - Later tasks add `@onready` members with these exact names: `trail` (Task 2), `mood` and
      `storm` (Task 3), `soundscape` (Task 4), `vista` (Task 6), `summit` (Task 7). Tests reach
      them as `lv.<name>`.
  - **Scene skeleton:**
    - a `WorldEnvironment` and `Sun` copied from `playground.tscn` (sky shader, fog, volumetric
      fog), and a `Wind`
    - a `Player` instance with `walk_speed = 2.0`, `can_sprint = false`, `lantern = false`
    - a `GameplayCamera` (`FollowCamera`, `min_pitch = -5`, `max_pitch = 45`)
    - a flat `Ground` placeholder (`collision_layer = 3`), which Task 2 replaces
    - a `UI/Fade` `ColorRect`, black, fading in from alpha 1 to 0 over 3.0 s on start, in group
      `"overlay"`

- [ ] **Step 1: Write the failing tests** in `tests/test_heavens_basics.gd`
  (`const SCENE := "res://scenes/levels/heavens_call.tscn"`):

```gdscript
func test_girl_has_no_lantern(lv) -> void:
	check(not lv.player.get_node("Model/Lantern").visible, "lantern mesh hidden")
	check(not lv.player.get_node("Model/LanternLight").visible, "lantern light off")

func test_no_sprint_in_level(lv) -> void:
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await seconds(1.5)
	var v := Vector2(lv.player.velocity.x, lv.player.velocity.z).length()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check(v <= 2.05, "speed capped at walk 2.0 with sprint held")
	check(v >= 1.8, "she does walk at about 2 m/s")

func test_camera_pitch_limited(lv) -> void:
	lv.follow_cam.pitch_deg = 80.0
	check_near(lv.follow_cam.pitch_deg, 45.0, 0.01, "pitch clamped to max_pitch")

func test_fades_in_from_black(lv) -> void:
	var fade: ColorRect = lv.get_node("UI/Fade")
	lv.reset_scene()
	check(fade.color.a > 0.9, "starts black")
	await seconds(3.3)
	check(fade.color.a < 0.05, "faded in after 3 s")
```

  Add `test_playground_player_unchanged` to `tests/test_smoke.gd` (the playground scene): expect
  `pg.player.can_sprint`, `pg.player.lantern` and `walk_speed == 3.5`.
- [ ] **Step 2: Run** `--only=heavens`. Expected: FAIL (the scene doesn't exist).
- [ ] **Step 3: Implement** the player and camera exports, the runner change and the skeleton
  scene. The level root needs no dev panel, presets or Compare.
- [ ] **Step 4: Run** `--only=heavens`, then the full suite. Expected: all PASS (96 + 5).
- [ ] **Step 5: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 2: Trail and mountain terrain

**Files:**
- Create: `scripts/levels/trail.gd`, `scripts/levels/mountain_terrain.gd`,
  `tests/test_heavens_trail.gd`
- Modify: `scenes/levels/heavens_call.tscn` (replace the placeholder ground), `heavens_call.gd`
  (respawn)

**Interfaces:**
- Produces:
  - **`class_name Trail extends Path3D` (`@tool`):**
    - The `curve` (Curve3D) is the authored trail centreline, from the foot (offset 0) to the
      summit.
    - `@export var width := 3.0`
    - `func length() -> float`
    - `func progress_at(world_pos: Vector3) -> float`: closest point's offset / length, 0..1
    - `func point_at(progress: float) -> Vector3`
    - `func distance_to_centre(world_pos: Vector3) -> float`: horizontal distance
  - **`class_name MountainTerrain extends Node3D` (`@tool`):**
    - `@export var trail: Trail` and `@export var extent := Vector2(360, 360)` (centred on the
      node)
    - `@export var cell := 1.5`, `@export var seed := 7`
    - `@export var corridor := 9.0` (walkable half-width): within it, height follows the trail's
      height across the corridor with a gentle cross-slope. Beyond it, it rises or falls into
      steep rock (cliffs ≥ 50°) so the corridor is bounded, plus noise.
    - `@export var trail_color`, `rock_color`: the vertex colour lerps from trail to rock between
      `trail.width * 0.5` and `width * 0.5 + 1.5` m from the centre.
    - It builds one `ArrayMesh` (faceted, using the `flat_color`-style per-face normals) and a
      `StaticBody3D` with a trimesh, `collision_layer = 3`, as internal children with no owner.
    - `func rebuild() -> void`, `func height_at(xz: Vector2) -> float`
  - **`HeavensCall`:**
    - `var furthest_progress := 0.0`, updated each physics frame from
      `trail.progress_at(player.global_position)`, and only ever increasing
    - `func respawn() -> void`: puts the player at `trail.point_at(furthest_progress) + Vector3.UP`
      and zeroes her velocity. It's called when the player's y is below
      `trail.point_at(progress).y - 15.0`.
- **Authoring:**
  - The curve is about 700 m long, climbing about 220 m with switchbacks, ledges and a few narrow
    chokepoints.
  - The summit is a broad flat-topped ridge at the curve's end, about 40 × 25 m, open on the
    vista side.
  - Steepest grade along the trail ≤ 30°.

- [ ] **Step 1: Write the failing tests:**

```gdscript
const SCENE := "res://scenes/levels/heavens_call.tscn"

func test_trail_length_and_walk_time(lv) -> void:
	var l: float = lv.trail.length()
	check(l >= 650.0 and l <= 750.0, "trail 650-750 m, got %.0f" % l)
	var t := l / lv.player.walk_speed
	check(t >= 300.0 and t <= 420.0, "walk time 5-7 min, got %.0f s" % t)

func test_trail_grade_walkable(lv) -> void:
	var worst := 0.0
	for i in 400:
		var a: Vector3 = lv.trail.point_at(i / 400.0)
		var b: Vector3 = lv.trail.point_at((i + 1) / 400.0)
		var run := Vector2(b.x - a.x, b.z - a.z).length()
		worst = maxf(worst, rad_to_deg(atan2(absf(b.y - a.y), run)))
	check(worst <= 30.0, "steepest trail grade <= 30 deg, got %.1f" % worst)

func test_terrain_matches_trail(lv) -> void:
	await frames(2)
	for i in 50:
		var p: Vector3 = lv.trail.point_at(i / 50.0)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20, p + Vector3.DOWN * 20, 2)
		var hit: Dictionary = lv.get_world_3d().direct_space_state.intersect_ray(q)
		check(not hit.is_empty() and absf(hit.position.y - p.y) < 0.6, "ground on layer 2 under the trail at %d" % i)

func test_progress_is_monotonic_along_trail(lv) -> void:
	check_near(lv.trail.progress_at(lv.trail.point_at(0.0)), 0.0, 0.01, "foot = 0")
	check_near(lv.trail.progress_at(lv.trail.point_at(0.5)), 0.5, 0.01, "middle = 0.5")
	check_near(lv.trail.progress_at(lv.trail.point_at(1.0)), 1.0, 0.01, "summit = 1")

func test_fall_respawns_on_trail(lv) -> void:
	lv.furthest_progress = 0.4
	lv.player.global_position = lv.trail.point_at(0.4) + Vector3(0, -40, 0)
	await frames(3)
	check(lv.player.global_position.distance_to(lv.trail.point_at(0.4)) < 2.5, "put back at furthest point")
	check_near(lv.furthest_progress, 0.4, 0.001, "progress not reset by the fall")
```

- [ ] **Step 2: Run** `--only=heavens_trail`. Expected: FAIL.
- [ ] **Step 3: Implement** `Trail` and `MountainTerrain`, author the curve, wire progress and
  respawn, and place the player at `point_at(0)`.
- [ ] **Step 4: Run** `--only=heavens`. Expected: all PASS.
- [ ] **Step 5: Visual check.** Fly or walk the trail (temporary capture script, deleted after).
  Check that it reads as a narrow mountain trail with cliffs and a ridge summit. Write the result
  in the ledger.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 3: Mood director and storm

**Files:**
- Create: `scripts/levels/mood_director.gd`, `scripts/levels/storm.gd`,
  `tests/test_heavens_mood.gd`
- Modify: `heavens_call.gd`, `heavens_call.tscn` (add the nodes and a `Mist` FogVolume copied from
  the playground)

**Interfaces:**
- Produces:
  - **`class_name MoodDirector extends Node`:**
    - `const KEYS := [ { "at": 0.0, ... }, { "at": 0.28, ... }, { "at": 0.57, ... }, { "at": 0.86, ... } ]`.
      Each key has: `wind`, `wind_swing_deg` (direction wobble amplitude), `fog_density`,
      `mist`, `lightning_per_min`, `sun_energy`, `sky_color`, `zenith_color`, plus the volumes
      `vol_wind`, `vol_wind_strong` and `vol_eerie` (0..1).
    - Values are tuned by eye. Required shape:
      - `lightning_per_min` is 0 for the first two keys, 1–3 at EERIE, and 0 at SUMMIT (the
        sequence owns the summit clap).
      - wind rises across the keys.
      - `vol_eerie` is above 0 only from EERIE on.
      - fog is thickest at EERIE.
    - `static func sample(progress: float) -> Dictionary`: smoothstep blend between neighbouring
      keys; colours lerp.
    - `func apply(mood: Dictionary) -> void`: drives `Wind.strength`, a slow
      `Wind.direction_degrees` wobble, environment fog, mist density, sun energy, sky colours,
      `Storm.rate_per_min` and the `Soundscape` volumes (soundscape optional until Task 4).
    - `var current: Dictionary`: the last applied mood.
  - **`class_name Storm extends Node`:**
    - `var rate_per_min := 0.0`
    - `signal flashed(delay_s: float)`: the delay until the thunder
    - `func flash() -> void`: a 0.15–0.35 s flicker of sun and ambient energy plus a sky
      brightening, then emits `flashed` with `randf_range(2.5, 6.0)`.
    - It schedules flashes with Poisson timing from `rate_per_min`.
    - `var flash_count := 0`
  - `HeavensCall` calls `mood.apply(MoodDirector.sample(furthest_progress))` each frame.

- [ ] **Step 1: Write the failing tests:**

```gdscript
const SCENE := "res://scenes/levels/heavens_call.tscn"

func test_keys_ordered_and_shaped(_lv) -> void:
	var at := []
	for k in MoodDirector.KEYS: at.append(k.at)
	check_eq(at, [0.0, 0.28, 0.57, 0.86], "stretch boundaries")
	check_eq(MoodDirector.KEYS[0].lightning_per_min, 0.0, "no lightning in ascent")
	check_eq(MoodDirector.KEYS[1].lightning_per_min, 0.0, "no lightning in discovery")
	check(MoodDirector.KEYS[2].lightning_per_min > 0.0, "lightning in eerie")
	check(MoodDirector.KEYS[0].vol_eerie == 0.0 and MoodDirector.KEYS[1].vol_eerie == 0.0, "eerie ambience only from stretch 3")
	check(MoodDirector.KEYS[3].wind > MoodDirector.KEYS[0].wind, "wind builds")

func test_sample_blends_between_keys(_lv) -> void:
	var a: float = MoodDirector.sample(0.28).wind
	var b: float = MoodDirector.sample(0.57).wind
	var mid: float = MoodDirector.sample(0.425).wind
	check(mid > minf(a, b) - 0.001 and mid < maxf(a, b) + 0.001, "blend stays between keys")

func test_mood_ignores_backtracking(lv) -> void:
	lv.player.global_position = lv.trail.point_at(0.7)
	await frames(3)
	var w: float = lv.mood.current.wind
	lv.player.global_position = lv.trail.point_at(0.1)
	await frames(3)
	check_near(lv.mood.current.wind, w, 0.001, "walking back down keeps the mood")

func test_no_lightning_before_eerie(lv) -> void:
	lv.player.global_position = lv.trail.point_at(0.4)
	await frames(2)
	check_eq(lv.storm.rate_per_min, 0.0, "storm silent in discovery")

func test_flash_schedules_distant_thunder(lv) -> void:
	var delays := []
	lv.storm.flashed.connect(func(d: float) -> void: delays.append(d))
	lv.storm.flash()
	await frames(1)
	check(delays.size() == 1 and delays[0] >= 2.5 and delays[0] <= 6.0, "thunder 2.5-6 s after flash")
```

- [ ] **Step 2: Run** `--only=heavens_mood`. Expected: FAIL.
- [ ] **Step 3: Implement** them and tune the keys by eye. Place the player at 0.1, 0.4, 0.7 and
  0.9 and capture a frame at each. Each stretch should read differently, with the fog thickest and
  eeriest at 0.7.
- [ ] **Step 4: Run** `--only=heavens`. Expected: all PASS.
- [ ] **Step 5: Checkpoint.** Run the full suite windowed and headless. Both green. Put the four
  captures' paths in the ledger.

### Task 4: Soundscape

**Files:**
- Create: `scripts/levels/soundscape.gd`, `tests/test_heavens_sound.gd`,
  `assets/audio/README.md` (the file-name table from Global Constraints: each sound's purpose,
  loop or one-shot, and rough length)
- Modify: `heavens_call.gd`, `heavens_call.tscn`, `mood_director.gd` (volumes)

**Interfaces:**
- Produces:
  - **`class_name Soundscape extends Node`:**
    - `const DIR := "res://assets/audio/"`
    - `static func load_stream(name: String) -> AudioStream`: returns null when
      `DIR + name + ".ogg"` doesn't exist (checked with `ResourceLoader.exists`), so it never errors
    - `func set_volumes(vol_wind: float, vol_wind_strong: float, vol_eerie: float) -> void`: 0..1
      linear, mapped to dB with a −60 dB floor. It's called by `MoodDirector.apply`.
    - `func play_thunder(clap := false) -> void`: a random `thunder_distant_*`, or `thunder_clap`
    - `func step(on_trail: bool) -> void`: a random gravel or rock step, never the same file twice
      in a row
    - `var last_step_kind := ""`: `"gravel"` or `"rock"`, for tests
  - **Loops:** three `AudioStreamPlayer`s (`wind_loop`, `wind_strong_loop`, `ambience_eerie_loop`)
    that loop and start at the mood's volumes.
  - **Footsteps:** one `AudioStreamPlayer3D` on the player. `HeavensCall` calls
    `soundscape.step(trail.distance_to_centre(p) <= trail.width * 0.5 + 0.5)` every **0.85 m**
    walked on the floor. That stride suits 2 m/s.
  - **Thunder:** `Storm.flashed(delay)` → after `delay` s, `play_thunder()`.

- [ ] **Step 1: Write the failing tests:**

```gdscript
const SCENE := "res://scenes/levels/heavens_call.tscn"

func test_missing_audio_is_silent(lv) -> void:
	check(Soundscape.load_stream("definitely_missing") == null, "missing file -> null, no error")
	lv.soundscape.play_thunder()
	lv.soundscape.step(true)
	lv.soundscape.set_volumes(1.0, 1.0, 1.0)
	check(true, "no engine errors with missing audio")  # the runner fails the test on any engine error

func test_footstep_kind_follows_ground(lv) -> void:
	lv.soundscape.step(true)
	check_eq(lv.soundscape.last_step_kind, "gravel", "on the trail = gravel")
	lv.soundscape.step(false)
	check_eq(lv.soundscape.last_step_kind, "rock", "off the trail = rock")

func test_volume_floor(lv) -> void:
	lv.soundscape.set_volumes(0.0, 0.0, 0.0)
	for p in lv.soundscape.loop_players():
		check(p.volume_db <= -60.0, "silent at 0")
```

  `loop_players() -> Array[AudioStreamPlayer]` is part of the interface.
- [ ] **Step 2: Run** `--only=heavens_sound`. Expected: FAIL.
- [ ] **Step 3: Implement** them. `assets/audio/` holds only `README.md` for now; real files arrive
  in Task 8.
- [ ] **Step 4: Run** `--only=heavens`. Expected: all PASS, with no engine errors.
- [ ] **Step 5: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 5: War debris and traveller props, staged along the trail

**Files:**
- Modify: `assets/blender/build_kit.py` (new builders and `ASSETS` entries), run through Blender
- Create:
  - `assets/meshes/prop_{shield_broken,sword_planted,helmet,breastplate,spear_broken,scarf_worn}.glb`
  - matching `scenes/environment/kit/*.tscn` (with `kit_asset.gd`)
  - `assets/materials/rusted_metal.tres`, `weathered_wood.tres` (`flat_color` shader)
  - `tests/test_heavens_props.gd`
- Modify: `heavens_call.tscn` (adds `Debris`, `Traces` and `Rocks` groups)

**Interfaces:**
- Consumes: `Trail.point_at`, the kit conventions in `build_kit.py`'s header (1 unit = 1 m, origin
  at base centre, material names = palette names).
- **Props**, low-poly and faceted:
  - `shield_broken`: a round shield with a missing wedge, lying tilted.
  - `sword_planted`: a blade stuck in the ground at an angle, with a bent crossguard.
  - `helmet`: a dented helmet on its side.
  - `breastplate`: a cracked breastplate face down.
  - `spear_broken`: a snapped shaft with its head.
  - `scarf_worn`: a faded blue cloth draped over a rock, using the existing `cloth` material so it
    sways with the wind.
  - None of them include bodies or bones (anti-goal).
- **Staging:**
  - **`Debris`:** 20–30 pieces placed only between progress **0.28 and 0.60**, in small, uneven
    clusters at path edges, ledges and chokepoints. Some sit half-buried. None block the
    walkable corridor.
  - **`Traces`:** 6–10 pieces between **0.60 and 0.95**: kit `prop_cairn` stacks, `scarf_worn`
    and one `prop_fire_ring` at a sheltered ledge.
  - **`Rocks`:** kit boulders and shards along the whole trail.
  - Placement is hand-authored in the scene (node transforms), not scattered.

- [ ] **Step 1: Write the failing tests:**

```gdscript
const SCENE := "res://scenes/levels/heavens_call.tscn"

func test_debris_in_discovery_stretch(lv) -> void:
	var n := 0
	for d: Node3D in lv.get_node("Debris").get_children():
		var p: float = lv.trail.progress_at(d.global_position)
		check(p >= 0.27 and p <= 0.61, "%s at progress %.2f" % [d.name, p])
		n += 1
	check(n >= 20 and n <= 30, "20-30 debris pieces, got %d" % n)

func test_traces_near_the_top(lv) -> void:
	for t: Node3D in lv.get_node("Traces").get_children():
		var p: float = lv.trail.progress_at(t.global_position)
		check(p >= 0.59 and p <= 0.96, "%s at progress %.2f" % [t.name, p])

func test_props_leave_the_path_walkable(lv) -> void:
	await frames(2)
	var space: PhysicsDirectSpaceState3D = lv.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1
	for i in 140:
		var p: Vector3 = lv.trail.point_at(i / 140.0)
		q.transform = Transform3D(Basis(), p + Vector3.UP * 0.9)
		check(space.intersect_shape(q, 1).is_empty(), "centreline clear at %.3f" % (i / 140.0))
```

- [ ] **Step 2: Run** `--only=heavens_props`. Expected: FAIL.
- [ ] **Step 3: Build the props.** Add the builders and run
  `"/c/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b -P assets/blender/build_kit.py`.
  Confirm that the existing GLBs re-export unchanged in look (spot-check one capture), then add
  the kit scenes and materials.
- [ ] **Step 4: Stage** the debris, traces and rocks, then run `--only=heavens`. Expected: all
  PASS.
- [ ] **Step 5: Visual check.** Capture frames at 0.35, 0.5 and 0.8. The debris should read as
  remnants of a battle (no bodies), and the traces as signs of passing people. Ledger it.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 6: Summit vista, ovoos and grass

**Files:**
- Create: `scripts/levels/vista.gd` (`@tool`), `tools/make_heavens_grass.gd`,
  `assets/grass/heavens_*.res`, `tests/test_heavens_vista.gd`
- Modify: `heavens_call.tscn`

**Interfaces:**
- **`class_name Vista extends Node3D` (`@tool`):**
  - a **steppe**: a huge golden ground disc of radius 3000 m, 150–250 m below the summit, faceted,
    with gentle rolling noise
  - **mountain silhouettes** at 600–2500 m: 3 depth rings of low-poly ridges, darker and bluer with
    distance
  - a **mist sea**: 2–3 large translucent layered planes, or a `FogVolume` slab, between the steppe
    and the summit, hiding the steppe's edge and the valleys
  - **ovoos**: 3 on or near the summit ridge, each a kit `prop_cairn` scaled up 1.5–2.5× with 2–4
    `prop_khadag_post` scarves around it
  - `@export var reveal := 0.0` (0..1): drives how far the mist sea and the near summit fog have
    opened. It's used by `SummitSequence`. Mood fog up to the summit keeps the vista hidden at
    `reveal = 0`.
  - No collision except the summit ridge terrain. It casts no shadows beyond the near ring.
- **Grass:**
  - `GrassField`s cover the trail in about 3–5 sections (sparse windswept tufts between rocks,
    density mostly 0.1–0.35, kept off the gravel centre).
  - One summit field (golden: base and tip colours shifted to gold, density 0.6–0.9).
  - Masks are generated by `tools/make_heavens_grass.gd` (the `make_starter_grass.gd` pattern);
    the user can repaint them.

- [ ] **Step 1: Write the failing tests:**

```gdscript
const SCENE := "res://scenes/levels/heavens_call.tscn"

func test_vista_hidden_until_reveal(lv) -> void:
	check_eq(lv.vista.reveal, 0.0, "vista hidden on start")

func test_ovoos_on_summit(lv) -> void:
	var ovoos: Array = lv.vista.get_node("Ovoos").get_children()
	check_eq(ovoos.size(), 3, "three ovoos")
	for o: Node3D in ovoos:
		check(lv.trail.progress_at(o.global_position) >= 0.9, "ovoo near the summit")

func test_summit_grass_is_golden_and_waving(lv) -> void:
	var g: GrassField = lv.get_node("Grass/Summit")
	check(g.blade_count() > 2000, "summit field populated")
	check(g.tip_color.r > g.tip_color.b + 0.15, "golden tips")

func test_trail_grass_is_sparse(lv) -> void:
	for g: GrassField in lv.get_node("Grass").get_children():
		if g.name == "Summit":
			continue
		var on_path: float = g.sample(Vector2(lv.trail.point_at(0.5).x, lv.trail.point_at(0.5).z)).x
		check(on_path < 0.05, "%s keeps the gravel centre clear" % g.name)
```

- [ ] **Step 2: Run** `--only=heavens_vista`. Expected: FAIL.
- [ ] **Step 3: Implement** the vista, ovoos and grass, and generate the masks.
- [ ] **Step 4: Visual check.** Set `reveal = 1`, stand on the summit and capture towards the vista.
  It must read as an endless world: steppe into mist, ridges fading blue. It must not look like a
  diorama (anti-goal), and the ovoos must stand against the sky. Ledger it.
- [ ] **Step 5: Run** `--only=heavens`. Expected: all PASS.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 7: Summit sequence, fade and title

**Files:**
- Create: `scripts/levels/summit_sequence.gd`, `tests/test_heavens_summit.gd`
- Modify: `heavens_call.gd`, `heavens_call.tscn` (`UI/Title` Label, `SummitCamera` Camera3D)

**Interfaces:**
- Consumes: `Vista.reveal`, `Soundscape.play_thunder(true)`, `Soundscape.set_volumes`,
  `MoodDirector`, `UI/Fade`, `Player.input_enabled`.
- Produces **`class_name SummitSequence extends Node`:**
  - `enum Phase { IDLE, SLOWING, REVEAL, PULLBACK, FADE, TITLE }`
  - `var phase := Phase.IDLE`
  - `const TITLE := "Heavens call"`
  - `const START_PROGRESS := 0.97`
  - `signal finished`
  - `func start() -> void`: called by `HeavensCall` once, when `furthest_progress ≥ START_PROGRESS`
  - **Timings:**
    - SLOWING 2.0 s: input off, the velocity eases to 0, and her model turns to face the vista.
    - REVEAL 8.0 s: `reveal` goes 0 → 1 with ease-in-out. The thunderclap sounds 2.0 s in.
      `wind_strong` volume rises to 1.
    - PULLBACK 12.0 s: `SummitCamera` takes over from the gameplay camera's transform and moves
      back and up along a gentle arc (ease-in-out) until she is a tiny silhouette against the
      horizon. That means the player's on-screen height is under 3% of the viewport.
    - FADE 4.0 s: `UI/Fade` alpha goes 0 → 1.
    - TITLE: `UI/Title` (centred, `text == TITLE`) fades in over 2.0 s. After that, any key press
      or mouse button quits (`get_tree().quit()`) and emits `finished` first.
  - `func skip_to(p: Phase) -> void`: for tests and captures
  - `var input_armed := false`: true only once the title is fully shown

- [ ] **Step 1: Write the failing tests:**

```gdscript
const SCENE := "res://scenes/levels/heavens_call.tscn"

func test_reaching_summit_starts_sequence(lv) -> void:
	lv.player.global_position = lv.trail.point_at(0.985)
	await frames(3)
	check(lv.summit.phase != SummitSequence.Phase.IDLE, "sequence started at the summit")
	check(not lv.player.input_enabled, "player control taken away")

func test_title_text(lv) -> void:
	lv.summit.skip_to(SummitSequence.Phase.TITLE)
	await seconds(2.2)
	var title: Label = lv.get_node("UI/Title")
	check_eq(title.text, "Heavens call", "exact title")
	check(title.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "centred")
	check(lv.get_node("UI/Fade").color.a > 0.99, "behind the title is black")

func test_input_ignored_until_title(lv) -> void:
	var quit := [false]
	lv.summit.finished.connect(func() -> void: quit[0] = true)
	lv.summit.quit_on_finish = false  # test hook: don't actually quit the runner
	lv.summit.skip_to(SummitSequence.Phase.REVEAL)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	await frames(2)
	check(not quit[0], "keys during the reveal do nothing")
	lv.summit.skip_to(SummitSequence.Phase.TITLE)
	await seconds(2.2)
	Input.parse_input_event(key)
	await frames(2)
	check(quit[0], "a key after the title finishes")

func test_pullback_makes_her_tiny(lv) -> void:
	if not needs_window(): return
	lv.summit.skip_to(SummitSequence.Phase.PULLBACK)
	await seconds(12.5)
	var cam := lv.get_viewport().get_camera_3d()
	var top := cam.unproject_position(lv.player.global_position + Vector3.UP * 1.7)
	var foot := cam.unproject_position(lv.player.global_position)
	check(absf(foot.y - top.y) < lv.get_viewport().get_visible_rect().size.y * 0.03, "tiny silhouette")
```

  `quit_on_finish := true` is an exported test hook.
- [ ] **Step 2: Run** `--only=heavens_summit`. Expected: FAIL.
- [ ] **Step 3: Implement** it. `reset_scene()` must return the sequence to IDLE, the camera to
  gameplay, `reveal` to 0 and input to on.
- [ ] **Step 4: Run** `--only=heavens`. Expected: all PASS.
- [ ] **Step 5: Visual check.** Capture the start of the reveal, the end of the pull-back, and the
  title. The reveal must open slowly rather than pop (anti-goal). Ledger it.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 8: Audio files

**Files:**
- Create: `assets/audio/*.ogg` (whatever can be fetched), `assets/audio/CREDITS.md`, and
  `assets/audio/NEEDED.md` (only if some files are missing)

**Interfaces:**
- Consumes: the file names in Global Constraints and `assets/audio/README.md` (Task 4).
- **Rules:**
  - **CC0 only.** Verify the licence on each file's own page (a site-wide claim isn't enough).
  - Natural field recordings: real wind, real gravel and rock steps, distant thunder with long
    tails. No music, no designed "horror" stingers, no synthesis.
  - Convert to Ogg Vorbis with Godot-compatible import. Loops loop cleanly: no click at the seam.
    Trim or crossfade if needed.
  - Footsteps are 4 variations each, sounding like a light person walking slowly.

- [ ] **Step 1: Find and download.** Try direct-download CC0 sources (for example OpenGameArt
  entries marked CC0, or other sites with plain download links and a per-file CC0 statement). Use
  `curl` with the file's direct URL. Don't use anything behind a login.
- [ ] **Step 2: Credits.** For each file you keep, write a row in `CREDITS.md`: file name, source
  page URL, author, licence (`CC0 1.0`), and any edits made.
- [ ] **Step 3: The rest.** For each file name you couldn't get, write a row in `NEEDED.md`: what it
  should sound like, loop or one-shot, rough length, and search terms. Missing files stay silent
  in the level (Task 4).
- [ ] **Step 4: Run** `--import`, then `--only=heavens`. Expected: all PASS, with no import errors.
- [ ] **Step 5: Listen-through by capture.** Play the level headless for 20 s at progress 0.1 and
  0.7, and confirm in the log that each present file loaded. Ledger which files exist and which
  are needed.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 9: Captures, profile and budget

**Files:**
- Modify: `heavens_call.gd` (command line), `tests/test_heavens_basics.gd`
- Create: `docs/HEAVENS_CALL.md` (how to run the level, its views, and the profile result)

**Interfaces:**
- **Command line**, after `--`, run with
  `"$GODOT" --path . res://scenes/levels/heavens_call.tscn -- <flags>`:
  - `--capture-views`: for each named view, place the player and camera, settle 30 frames, and
    save to `screenshots/heavens_<view>_<datetime>.png`. The views are `foot` (0.02),
    `debris` (0.42), `eerie` (0.72), `summit` (0.96) and `wide` (the sequence skipped to the end
    of PULLBACK).
  - `--profile`: for each view, measure 120 frames with `PerfHud.measure`, print the table
    (`PerfHud.table`), and write `screenshots/heavens_profile_<datetime>.md`.
  - `--quit`.
- `func view_names() -> PackedStringArray` and `func show_view(name: String) -> void`.

- [ ] **Step 1: Write the failing test:** `test_views_exist`. `view_names()` equals
  `["foot", "debris", "eerie", "summit", "wide"]`, and `show_view` on each raises no error.
- [ ] **Step 2: Run** it and see it fail. Implement it, then see it pass.
- [ ] **Step 3: Capture and profile** at `--resolution 1920x1080 --disable-vsync`. Check every PNG.
  The worst view must be ≤ 7.0 ms GPU. If it's over, cut the vista cost first (silhouette rings,
  mist layers, shadow ranges), re-profile, and record what changed.
- [ ] **Step 4: Write `docs/HEAVENS_CALL.md`:** how to run (editor F6, and the command line), the
  views, the profile table, the audio status (CREDITS / NEEDED), and the user's manual checks.
- [ ] **Step 5: Checkpoint.** Run the full suite windowed and headless. Both green.

### Task 10: REUSE.md gaps, README, final validation

**Files:**
- Modify: `docs/REUSE.md`, `README.md`

- [ ] **Step 1: `REUSE.md`.** Add a "Fog, mist and sky" section covering what was copied from the
  playground in Tasks 1 and 3:
  - the `WorldEnvironment` settings
  - the sky shader
  - the `Mist` FogVolume and how its offset follows the wind
  - the player `lantern` / `can_sprint` options
  - the camera pitch limits
  - the scene-aware test runner (`const SCENE`)

  Fix any other gap found while building the level, and list those gaps in the ledger.
- [ ] **Step 2: `README.md`.** Add a short "Heavens call" section: what it is, how to run it, and a
  link to `docs/HEAVENS_CALL.md`.
- [ ] **Step 3: Final validation**, recorded in the ledger:
  - the full suite windowed and headless
  - the playground's `--capture-views` (unchanged look) and the level's `--capture-views` (look at
    every PNG)
  - the level's `--profile` at 1920×1080 (≤ 7.0 ms GPU)
  - the editor load check:
    `"$GODOT" --headless --editor --path . --quit-after 300 2>&1 | grep -i -E "error|grass_painter"`
- [ ] **Step 4: Handoff list** for the user:
  - play the whole climb once and time it (5–7 min)
  - listen for the sound mix (sparse, silence breathes)
  - the summit reveal and the title
  - drop in any files listed in `NEEDED.md`
  - repaint the grass if wanted
