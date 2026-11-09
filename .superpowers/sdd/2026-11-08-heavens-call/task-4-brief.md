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

