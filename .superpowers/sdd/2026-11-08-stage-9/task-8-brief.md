### Task 8: Stage 8 leftovers — compare and captures (minors 1, 5, 6, 9)

**Files:**
- Modify: `scripts/compare.gd` (`capture_a`, `save_pair`), `scripts/debug/light_gizmos.gd`,
  `tests/test_compare_pair.gd`
- Test: `tests/test_stage8_leftovers.gd`

**Interfaces:**
- Produces: `static func Compare.save_sheet(image: Image, path: String) -> String`: returns `""`
  on success, otherwise `"Could not save <file> (error N)"`.
- Fixes:
  1. `capture_a` records `_last_cam` / `_last_fov` from the live camera **before**
     `render_state`, not after restore. A player move during the blink then triggers a recapture.
  5. `LightGizmos` joins `"overlay"`, so captures hide it. Lights are re-collected when the tree
     adds or removes a `Light3D` while visible (`node_added` / `node_removed`), instead of only on
     show.
  6. `save_pair` uses `save_sheet`; on failure it notifies the error, doesn't copy the log row,
     and returns `""`.
  9. `test_compare_pair.gd` saves the clipboard in `before_each` and restores it in `after_each`.

- [ ] **Step 1: Write the failing tests:**
  - `test_player_move_during_capture_recaptures`: enter split view, start `capture_a()`, move the
    player 2 m during it (after one frame), await its end, then wait `RECAPTURE_DELAY + 0.3` s.
    Expect the capture count (counted via `changed` as in
    `test_height_change_does_not_loop_recaptures`) to be ≥ 2.
  - `test_gizmos_hidden_in_captures`: set `light_gizmos` on, then `pg.hide_overlays()` →
    `not pg.light_gizmos.visible`, then `restore_overlays()` → visible.
  - `test_gizmos_pick_up_new_lights`: set gizmos on, then add an `OmniLight3D` to `pg`. Two frames
    later, the gizmo mesh vertex count has grown (count it with `Mesh.surface_get_arrays`, as in
    `test_light_gizmos.gd`). Free the light.
  - `test_save_sheet_reports_failure`: `Compare.save_sheet(Image.create(4, 4, false, Image.FORMAT_RGB8), "user://no/such/dir/x.png")`
    returns a non-empty string containing `"Could not save"`.
- [ ] **Step 2: Run** `--only=stage8_leftovers`. Expected: FAIL.
- [ ] **Step 3: Implement** the four fixes.
- [ ] **Step 4: Run** `--only=stage8_leftovers`, then `--only=compare`. Expected: PASS. Afterwards,
  the clipboard holds what it held before the run.
- [ ] **Step 5: Checkpoint.** Run the full suite windowed. Expect it to be all green.

