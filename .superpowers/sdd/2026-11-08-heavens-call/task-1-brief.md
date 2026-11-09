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

