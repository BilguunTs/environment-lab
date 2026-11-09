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

