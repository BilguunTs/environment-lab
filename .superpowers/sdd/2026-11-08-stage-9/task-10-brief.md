### Task 10: Documentation and final validation

**Files:**
- Create: `docs/REUSE.md`
- Modify: `README.md`, `docs/EXPERIMENT_LOG.md`

- [ ] **Step 1: Write `docs/REUSE.md`**, about one page, in the README's voice. Cover:
  - **What to copy:** `scripts/environment/` (`wind.gd`, `grass_field.gd`, `grass_brush.gd`,
    `kit_asset.gd`), `assets/shaders/`, `assets/materials/`, the kit scenes, and
    `addons/grass_painter/`.
  - **Project settings:** the three `[shader_globals]`, the physics layer names, and enabling the
    plugin.
  - **The ground rule:** walkable ground needs collision on layers 1 + 2, and kit ground pieces
    set `collision = true`.
  - **A new level in five steps:** add `Wind`, add `GrassField`, set the extent, select it, paint.
  - **Playground-only parts not needed in a game level:** the dev panel, presets, Compare, the
    debug tools, and `tools/`.
- [ ] **Step 2: Update `README.md`.** Add grass, wind direction (and its compass convention), the
  painter's controls (LMB, Shift+LMB, `[` / `]`, Ctrl+Z), `--profile-views`, and links to
  `REUSE.md` and `PERFORMANCE.md`.
- [ ] **Step 3: Add a `## Stage 9 experiments to run` section** to `docs/EXPERIMENT_LOG.md`, above
  the Stage 8 section, in the same style: numbered, a fixed view, one change at a time. Include:
  - wind direction across vs along the path as a leading line
  - the gust strength where motion stops being atmosphere and becomes distraction (revisits the
    Stage 3 stillness test)
  - grass height as a framing device around the landmark
  - a painted clearing (erase) used to frame a shot
  - grass highlight vs the Notan read
- [ ] **Step 4: Final validation**, with the results recorded in the ledger:
  - the full suite, windowed and headless (no parse or runtime errors)
  - `--capture-views` (look at every PNG)
  - `--print-fps` against the Stage 8 figure (841 fps with grass off, as the comparable baseline)
  - `--profile-views` (budgets met)
  - the editor load check from Task 6 Step 5
- [ ] **Step 5: Handoff list** for the user's manual checks: painting in the editor (Task 6
  Step 6), walking over the mounds (Task 2 Step 5), RMB orbit in split view (carried over from
  Stage 8), and how the grass looks while the wind changes.
