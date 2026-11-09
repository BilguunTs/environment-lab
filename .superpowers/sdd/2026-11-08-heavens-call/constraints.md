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

