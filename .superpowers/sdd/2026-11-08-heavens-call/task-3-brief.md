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

