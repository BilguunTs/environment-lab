# Stage 8 design: comparison, preset saving, visual debugging

Date: 2026-10-12 · Status: draft for review

## Intent

Every experiment in `docs/EXPERIMENT_LOG.md` has the same shape: change one variable, compare
before and after, and measure values. Today that means two F12 presses, flipping between files,
and measuring luminance by hand from PNGs. Stage 8 shortens that loop inside the running scene.

**Success means:**
- Pin a state, change a variable, and see A against B from the same camera without leaving the game.
- Get a log-ready record (side-by-side PNG plus the list of changed parameters) with one button.
- Keep a good configuration as a named preset that survives a restart.
- Read values, cost and light coverage live instead of reconstructing them afterwards.

**Constraints** (from `main.md`): no database, no complex preset manager, no editor plugin. Every
control must actually work. Keep each piece small and testable.

**Decided with the user:**
- Comparison: both live A/B and saved pairs (option C).
- Split view: frozen A image, live B.
- Debug tools: all four (render modes, value probe, perf readout, light gizmos).

## 1. A/B compare: `scripts/compare.gd`

A `Node` child of the playground, created in code. It talks to the scene only through the
existing `get_state()` / `apply_state()` / `get_param()` interface.

### Compared state
- Compare state = `get_state()` minus the keys in `COMPARE_EXCLUDE`:
  - `view`
  - `guides_grid`, `guides_center`, `guides_aspect`
  - `value_mode`, `value_squint`, `value_split`
- The camera you're looking from, the framing guides and the value view stay fixed, so A and B
  are seen through the same eyes (for example, both in notan).
- Camera *lens* parameters (`cam_fov`, height, distance, pitch, shift) *are* compared, because a
  lens change is a legitimate experiment variable.

### Pin A
- Key **P**, or the *Pin A* button.
- Stores the compare state as A, then captures the A image (see Split).
- The panel status reads `A pinned`. Pinning again replaces A.

### Flip (hold)
- Key **X**, held.
- On press: remember the live state as B and apply A. On release: apply B.
- This is a fully live comparison, because both states are the real scene.
- The HUD shows `A` or `B` in the top right while comparing.
- **Key change from the chat design:** the design said *Tab*. Godot's GUI uses Tab for focus
  navigation and swallows it whenever a panel slider has focus, so the key is X.

### Split
- Key **Z** toggles split view.
- An overlay `TextureRect` shows the A image clipped to the left of a vertical divider; the live
  scene (B) shows on the right. Drag the divider with the left mouse button on a 12 px grab handle.
- The overlay sits on the UI layer *under* the dev panel and above the 3D view and the value view,
  so A is shown exactly as captured (the value view is baked into the capture).
- A thin label at the top of each half reads `A` and `B`.

### A image capture
Steps:
1. Hide the split overlay, the dev panel, the HUD and the debug overlays.
2. Apply A, then wait `SETTLE_FRAMES` (10) frames so volumetric fog and TAA history settle.
3. Grab `get_viewport().get_texture().get_image()`.
4. Apply B (the state at capture start) and restore the overlays.

When it runs:
- On *Pin A*.
- In split mode, automatically once the active camera's transform or FOV has been unchanged for
  0.5 s after a change.
- In split mode, immediately when `value_mode`, `value_squint` or `value_split` changes. Those are
  baked into the A image, so a stale A would compare two different value views.

**Known cost:** a 10-frame blink while A renders. That's invisible at high fps and about 170 ms at
60 Hz. This is accepted; it's the price of approach 1, chosen over two worlds or alternating frames.

### Diff
- `compare.diff() -> Array[String]` returns one line per parameter that differs between A and the
  live state, formatted as `key: a → b`:
  - floats rounded to 3 significant digits
  - colours as hex
  - booleans as on/off
- The panel's *Compare* section shows the diff live, up to 8 lines, then `+N more`.

### Save pair
- The *Save pair* button.
- Renders A and B *properly*: apply, settle 10 frames and grab for each, with overlays hidden.
  Then it restores B.
- It composes a full-resolution image, `2W × (H + strip)`, by rendering a temporary `SubViewport`:
  two `TextureRect`s, plus a `Label` strip with the diff, the view name and the date. Godot's `Image`
  can't draw text, so the SubViewport is how the text gets in.
- Saves the result as `screenshots/<stamp>_compare_<view>.png`.
- Copies a ready log row to the clipboard: `| <date> | | <diff joined by ", "> | | |`.
- The `--capture-views` CLI path is unchanged.

### Edge cases
- X, Z or Save pair with no A pinned: the status reads `Pin A first (P)`.
- Changing the forest seed or mode between A and B regenerates the forest on every flip. It's
  slow but correct.
- A forest-mode switch inside a capture is allowed.
- Flip, split and capture are disabled while the scout camera is active, to keep one camera.
  Pressing them shows `Leave Scout first (F)`.

## 2. Preset saving: extends `scripts/presets.gd`

- **File:** `res://presets/user_presets.cfg`, a `ConfigFile` with one section per preset and one key
  per overridden parameter. It's plain text that you can edit and diff, and it stores `Color`
  natively.
- **Save:** a `LineEdit` (placeholder *Preset name*) plus a *Save preset* button in the Presets
  section.
  - Stores **only the overrides**: keys whose value differs from the default state, like the
    built-in presets. The `view` key is always stored.
  - An empty name is refused with a status message.
  - A name equal to a built-in preset is refused (`Name taken by a built-in preset`).
  - Saving with an existing user preset's name overwrites it.
- **Load:** `presets.gd` gains `static func all() -> Dictionary`, which merges `ALL` with the file
  contents. The playground and panel use `all()` everywhere they used `ALL`. User presets appear
  in the grid after the built-in ones, and the grid rebuilds after a save.
- **Delete:** edit the file. There's no delete button.
- **Missing view:** if a saved `view` doesn't exist (a session bookmark), loading falls back to
  Gameplay. That's already the behaviour of `set_param("view")`, which uses `maxi(0, find())`.
- **Typing:** while the `LineEdit` has focus, the player ignores movement and the playground ignores
  hotkeys (`player.input_enabled = false` on focus, restored on focus exit or submit). Otherwise
  typing "wasd" would walk the player.
- **Caveat:** `res://` is read-only in exported builds. This is a dev playground and is never
  exported, which is documented in the README.

## 3. Visual debugging

There's a new **Debug** panel section. All four tools are reached through `get_param`/`set_param`
(keys `debug_draw`, `probe`, `perf_hud`, `light_gizmos`), so the panel stays uniform. They are
**not** in `PARAM_ORDER`, which keeps them out of presets, *Copy settings* and A/B.

### 3a. Render debug modes
- `debug_draw` is one of `Normal`, `Unshaded`, `Lighting`, `Overdraw`, `Wireframe`, mapped to
  `get_viewport().debug_draw`. It has a dropdown, and **F2** cycles through the modes.
- **Wireframe** requires `RenderingServer.set_debug_generate_wireframes(true)` before any mesh
  loads. So there's a new one-line autoload, `scripts/debug/debug_boot.gd`, registered in
  `project.godot` under `[autoload]`.
- The mode applies to the main viewport only. Screenshots taken in a debug mode capture it, which
  is intended.

### 3b. Value probe and histogram: `scripts/debug/value_probe.gd`
A `Control` in the bottom-right corner.

- **Sampling:** about 4 times per second (`SAMPLE_INTERVAL` 0.25 s), only while enabled. It grabs
  the viewport image, which includes the value view when it's on, since you measure what you see.
- **Measure:** luminance = Rec.709 (`0.2126 R + 0.7152 G + 0.0722 B`) on the final tonemapped
  colour, the same measure the experiment log uses.
- **Statistics:** from the image downsampled to 1/8 size, excluding the rects of visible UI (dev
  panel, probe, perf HUD, top-right HUD).
- **Shows:**
  - the value under the mouse cursor, read from the full-resolution image
  - p5, p50 and p95
  - a 32-bin histogram with tick marks at p5, p50 and p95
  - a vertical line at the current `value_split`, the notan threshold
- **Cost:** each readback stalls the GPU for a few ms. The probe is off by default, and while it's
  on the perf HUD shows `probe on` next to the fps.

### 3c. Perf readout: `scripts/debug/perf_hud.gd`
A `Label` in the top-right corner, directly under the existing view/intent HUD (the dev panel
owns the left side).

- **Updates:** 2 times per second, showing averages over the interval.
- **Metrics:**
  - fps: `Performance.TIME_FPS`
  - CPU ms: `viewport_get_measured_render_time_cpu` plus process time
  - GPU ms: `RenderingServer.viewport_get_measured_render_time_gpu`, with
    `viewport_set_measure_render_time(rid, true)` on while the HUD is enabled
  - draw calls: `RENDER_TOTAL_DRAW_CALLS_IN_FRAME`
  - primitives: `RENDER_TOTAL_PRIMITIVES_IN_FRAME`

### 3d. Light gizmos: `scripts/debug/light_gizmos.gd`
A `MeshInstance3D` with an `ImmediateMesh` and an unshaded material (`no_depth_test`, vertex
colours, `render_priority` high), so it draws on top of everything.

- **Lights:** on enable, collects every visible `OmniLight3D` and `SpotLight3D` in the playground,
  then rebuilds the lines every frame, because the lantern moves with the player.
  - **Omni:** three great circles at `omni_range`, in the light's colour.
  - **Spot:** a cone outline (8 edges from the apex plus a rim circle at `spot_range`, using
    `spot_angle`).
  - **Sun:** a 3 m direction arrow above the player, in the sun's colour.
- Hidden lights (the supernatural toggle off, props hidden) are skipped every frame.
- *Show exclusion zones* is unchanged and independent.

## Files

New:
- `scripts/compare.gd`
- `scripts/debug/debug_boot.gd`
- `scripts/debug/value_probe.gd`
- `scripts/debug/perf_hud.gd`
- `scripts/debug/light_gizmos.gd`
- `presets/user_presets.cfg` (created on first save)

Edited:
- `scripts/playground.gd`:
  - compare and debug node setup
  - debug parameters
  - keys P, X, Z, F2
  - HUD A/B tag
  - `all()` presets
  - scout guards
- `scripts/ui/dev_panel.gd`:
  - Compare section (Pin A, Split, Save pair, diff label)
  - preset name field and Save
  - Debug section
  - grid rebuild after a save
- `scripts/presets.gd`: `all()` and `save_user()`
- `project.godot`: autoload
- Docs:
  - `README.md` (controls, panel, layout)
  - `docs/EXPERIMENT_LOG.md` (Stage 8 experiments)

## Validation

1. **Headless parse:** `--headless --quit-after 120` runs with no errors or warnings.
2. **Scripted compare check:** a temporary `--selftest-compare` CLI flag, removed after validation.
   It runs this sequence:
   1. Pin A.
   2. Set `sun_glow` to 0.6.
   3. Assert `diff()` returns exactly one line.
   4. Save a pair.
   5. Assert the PNG exists and its size is `2W × (H + strip)`.
   6. Assert the live state equals B afterwards.
3. **Preset round trip:**
   1. Save a preset named `Test`.
   2. Restart.
   3. Confirm it's in the grid and that loading it reproduces the saved values.
   4. Delete it from the file.
4. **Probe accuracy:** in Forest Gate under Cold Dawn, the probe at the hole and sky should match
   the Stage 7 manual measurements (hole about 0.86, sky about 0.60) within ±0.03.
5. **Render modes:** capture each of the five modes and confirm each looks distinct and correct
   (wireframe shows edges).
6. **Perf:** fps with all debug tools off should be within noise of about 842. Report the probe's
   cost.
7. **Manual (user):** drag the split divider, check the blink on re-capture at your refresh rate,
   and check that typing in the preset name field doesn't move the player.

## Out of scope

- Deleting or renaming presets in the UI.
- More than one pinned state (A/B only, no A/B/C).
- History or undo of parameter changes.
- Comparing across different cameras.
- Gizmos for fog volumes or particles.

## Refinements made while planning and building

- A is rendered on entering split view and re-rendered while split is on. Pinning alone doesn't
  capture, so pins outside split mode don't blink.
- A permanent test suite (`tests/`, runner `tests/run.gd`) replaces the temporary
  `--selftest-compare` flag. The runner fails any test that raises an engine or script error.
- The probe test checks the sky against the Stage 7 value (0.60 ± 0.03) but checks the hole only
  as "> 0.75", because the hole breathes ±30 %.
- `cam_fov` is the *active* camera's lens, so A's lens is compared and applied only in the view
  where A was pinned. Otherwise, holding X after a view change would overwrite that viewpoint's
  lens.
- Perf readout CPU ms = viewport CPU render time + frame-setup time. `Performance.TIME_PROCESS`
  is the whole frame including the vsync wait, so it isn't used.
- One probe sample costs about 14 ms at 1600×900, not "a few ms". It's still sampled at 4 Hz; the
  README warns about the hitch.
- Value-view changes in split view re-render A once the change has rested for `RECAPTURE_DELAY`
  (like camera moves), not immediately. Otherwise every slider tick blinks and the hidden panel
  drops the drag.
- Applying A or B (flip, capture, restore) snaps the smoothed gameplay camera, so `cam_height`,
  distance and pitch cut instead of gliding, and split view settles.
- Hotkeys other than an X release are ignored while a capture is running. An X release that
  arrives mid-capture is honoured when the capture ends.
