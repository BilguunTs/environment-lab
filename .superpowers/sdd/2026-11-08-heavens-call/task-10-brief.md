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
