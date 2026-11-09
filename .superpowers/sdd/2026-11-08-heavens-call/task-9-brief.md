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

