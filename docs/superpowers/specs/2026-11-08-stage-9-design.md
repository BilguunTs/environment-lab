# Stage 9 design: wind-driven grass, profiling, cleanup, reuse

Date: 2026-11-08 · Status: draft for review

## Intent

Stage 9 in `main.md` is "performance profiling, cleanup, documentation, and reuse in future game
levels". The user made a painted, wind-driven grass system the main new feature of the stage.
Profiling, cleanup and docs are done around it.

The reference is Ghost of Tsushima's fields. The blades lean in the wind direction, and gusts roll
across the field as visible waves, so you can read the wind's direction and strength from the
grass alone. The effect is **atmosphere only**. The wind does not guide the player.

Grass is placed by **painting it with a brush in the Godot editor**, not by automatic placement. The
brush paints **where grass grows, its density and its height**. Because the painter works in any
scene, it is also the main thing that makes Environment Forge reusable in future levels.

**Success means:**
- Standing in a painted field, turning the wind slider up or rotating its direction makes the
  whole field visibly lean that way and carry travelling gust waves, with no jumps or pops.
- Painting grass into a new scene takes minutes: add one node, select it, paint.
- The game still holds 60 fps on a mid-range PC with the grass on (see Performance).
- The Stage 8 leftovers are cleared, and a short guide explains how to reuse the kit in a new level.

**Anti-goals:** the result fails, even if it technically works, if:
- the field moves as one rigid sheet, or as a regular sine pattern you can see repeating;
- the grass looks photoreal or noisy instead of matching the flat, faceted style;
- the painter grows into a general level editor.

## Decided with the user

- Grass bends with the wind, and waves ripple across it in the wind's direction (Ghost of Tsushima).
- Atmosphere only. No guiding-wind gameplay for now.
- Placement is a paint tool in the Godot editor. The brush paints presence, density and height.
- The grass is part of Stage 9, which still includes profiling, cleanup and docs.
- Performance target: 60 fps on a mid-range PC.
- Cleanup means the 9 deferred Stage 8 minor issues, plus tidying any code the grass touches.
- Docs means a short guide for bringing Environment Forge and the grass painter into a new level.

## Constraints

- Godot 4.6, Forward+, GDScript (the existing code style). The binary and CLI checks are in the
  project memory: `--capture-views`, `--print-fps`, and the windowed test runner `tests/run.gd`.
- `main.md`: no paid services or third-party plugins, smallest working implementation, exported
  parameters with clear names, no general-purpose level editor.
- **Plugin override (user decision):** `main.md:149` and `:308` say to avoid a custom editor plugin.
  The user approved overriding that for one single-purpose `EditorPlugin`, the grass painter. Add a
  note at `main.md:149` recording the exception, so later stages don't treat it as licence for
  more plugins.
- **Ground (user decision):** ground in future levels is mesh pieces with colliders, like the
  mounds. Grass and the brush find the ground by physics raycast.
- The project is not a git repository. Follow the Stage 8 ledger approach: a baseline snapshot, plus
  full-suite checkpoints in place of commits.

## 1. Wind gets a direction

Today the direction is a constant, `WIND_DIR = (0.8, -0.6)`, duplicated in `flat_color.gdshader:25`
and `playground.gd:26`. Only the strength is tunable.

- Add a global shader uniform `wind_direction` (vec2, normalised) next to `wind_strength` in
  `project.godot` `[shader_globals]`. Its default is the current (0.8, -0.6), so existing looks don't
  change.
- Add a playground param `wind_direction`, stored as a compass angle in degrees (0–360), in
  `PARAM_ORDER` right after `"wind"`. It has a dev panel slider under Wind and goes through
  presets, Copy settings and A/B like every other param. Presets that omit it fall back to the
  default.
- Remove both `WIND_DIR` constants. Everything that used them reads the new direction instead: tree
  and cloth sway in `flat_color.gdshader`, mist drift and mote push in `playground.gd`.
- **Gusts are one shared field.** Put the gust function in a shader include (for example
  `assets/shaders/wind.gdshaderinc`) used by both `flat_color.gdshader` and the grass shader, so a
  gust that crosses the meadow then reaches the trees. Gusts must be irregular travelling patches
  (scrolling noise along the wind direction), not the current single sine front.
- **No jumps when sliders move.** The mist already integrates its offset in `_process` instead of
  using `TIME * speed` (`playground.gd:137`). Do the same for the gust scroll: the playground
  integrates a global `wind_offset` from direction × strength each frame. In the editor, where the
  playground script doesn't run, the grass may fall back to a gentle `TIME`-based motion. Exact
  form: builder's call.
- Update the dev panel note (`dev_panel.gd:75`) to mention grass and direction.

## 2. Grass field: `GrassField` node

A `@tool` `Node3D` (`class_name GrassField`) that covers a rectangle centred on itself, the same
pattern as `Scatter` (`scripts/procedural/scatter.gd`).

**Painted data.** One mask texture per field: R = density (0 = none, 1 = full), G = height (0 =
shortest, 1 = tallest). It is saved as its own resource file next to the scene, not embedded in the
`.tscn`, so the scene file stays readable and the mask can be reused. Resolution is about 0.5 m per
texel; the exact value is an exported parameter.

**Exported parameters** (names indicative): `extent`, `texel_size`, `mask`, `blades_per_m2` at full
density, `min_height` / `max_height` in metres, `random_seed`, colours (base, tip), and
`fade_start` / `fade_end` distances.

**Blades.** Low-poly tapered blades, a few triangles each, in the faceted look of `flat_color`. Some
per-blade variation in lean, height and tint, seeded so the same mask and seed always give the same
field (the reproducibility rule from Stage 5).

**Rendering.** The builder's call, within these requirements:
- Instanced (for example `MultiMesh` chunks of roughly 10–20 m) with visibility culling per chunk.
- Distance thinning: blades fade out or drop away between `fade_start` and `fade_end`, with no
  visible line where it happens.
- Blades sit on the visible ground, including the mounds (`Terrain/Mound*`), found by a downward
  physics raycast at build time (user decision: ground is meshes with colliders). The mound kit
  scenes (`scenes/environment/kit/ground_mound_*.tscn`) currently have no colliders, so add
  collision to them. Check that the player still walks over them correctly once it's added.
  Points with no ground hit get no blades. Which collision layer or mask to ray against is the
  builder's call; document it in `REUSE.md`.
- Rebuilding after a brush stroke only touches the affected chunks, so painting stays interactive.

**Grass shader** (`assets/shaders/grass.gdshader`):
- Bend grows with height along the blade, so the base stays planted. The blade leans in
  `wind_direction`, scaled by `wind_strength` and the shared gust field. A small per-blade flutter
  sits on top.
- **Wave highlight (my call, from the Ghost of Tsushima reference):** blades brighten slightly while
  a gust bends them, so waves read from a distance. Keep it subtle enough that Notan and 3-Value
  views still read the path and landmark first.
- Colour runs from a darker base to a lighter tip, close to the existing ground palette. Uses the
  same per-face normal trick and base darkening as `flat_color` so it sits in the scene.

**Playground integration:**
- Add a `GrassField` to `playground.tscn` covering the play area, not the whole 400 m ground.
- **Starter field (my call):** the builder paints or generates an initial mask (meadow along the
  path edges and around the clearing, kept off the path itself) so the scene and screenshots have
  grass from day one. The user will repaint it.
- New param `grass_visible` (bool, like `props_visible`) in `PARAM_ORDER`, with a dev panel toggle,
  so grass cost can be A/B'd and profiled.

## 3. Grass painter: `addons/grass_painter/`

A minimal `EditorPlugin`. It is active only while a `GrassField` is selected.

- **Brush:** left mouse paints in the 3D viewport, with a circle drawn on the ground under the
  cursor showing the brush size.
- **Modes:** Density (paint towards a target density), Height (paint towards a target height), and
  Erase (density to 0). Shift or Ctrl modifiers to invert or soften are the builder's call.
- **Settings** in a small toolbar or dock: radius, strength (how fast it reaches the target), target
  value, and falloff.
- **Undo:** each stroke (mouse down → up) is one undo step through the editor's `UndoRedo`.
- Painting writes the mask and rebuilds affected chunks live. The mask file is saved with the scene.
- **Not included:** layers, multiple grass types, texture import/export UI, or painting anything
  other than grass. The plugin does not touch scenes without a `GrassField`.

## 4. Performance and profiling

- **Target:** 60 fps on a mid-range PC. The dev machine has an RTX 3070 and an i7-12700F at
  1920×1080, which is well above mid-range.
- **Proxy budget (my call):** with grass on, the busiest playground view stays at or below **7 ms
  GPU frame time** on the dev machine, and grass itself costs at most **2 ms GPU**. Measure grass by
  comparing the perf HUD's GPU ms with `grass_visible` on and off. 7 ms on the 3070 is roughly
  16 ms on a GTX 1660 / RTX 3050-class card.
- **Profiling pass (the rest of Stage 9's profiling):** measure every named viewpoint with grass on.
  Record fps, CPU ms, GPU ms, draws and primitives in a table. Name the top costs. If anything is
  over budget, fix the largest cost first and re-measure. Results go in `docs/PERFORMANCE.md`.
- Keep the Stage 8 check that the headless/windowed suite and `--capture-views` still run.

## 5. Cleanup: Stage 8 deferred minors

From `.superpowers/sdd/2026-10-12-stage-8/progress.md:35-43`. Each one gets a regression test where
practical.

1. The A image's camera pose is recorded after restore, not at grab time.
2. The perf readout (`offset_top = 64`) can overlap a 3–4 line view HUD.
3. An unreadable `user_presets.cfg` fails silently on load. Show a status note.
4. Wrong-typed values in hand-edited presets raise a runtime error in `set_param`. Skip them with a
   note instead.
5. Light gizmos show in A images and saved pairs. Lights are only collected when gizmos are enabled.
6. Save pair ignores `save_png`'s result and always reports success.
7. The probe's `measure()` takes about 14 ms (per-pixel `get_pixel` plus a per-pixel rect loop). Its
   test doesn't check the probe's own stats.
8. Wireframe generation is always on (`debug_boot`), with no measured cost. Measure it, and gate it
   if it costs anything.
9. `test_save_pair_writes_side_by_side_png` overwrites the clipboard.

Also tidy any code the grass and wind changes touch, such as the removed `WIND_DIR` duplicates.

## 6. Documentation

- `docs/REUSE.md`: how to bring Environment Forge pieces into a new level. Covers which scripts,
  shaders and kit scenes to copy, the shader globals to add, enabling the grass painter, adding a
  `GrassField`, painting, the rule that ground must have collision, and what the
  playground-specific parts are (dev panel, presets, compare)
  that a game level won't need.
- `README.md`: add grass, wind direction and the painter to the controls and features lists.
- `docs/EXPERIMENT_LOG.md`: a "Stage 9 experiments to run" section, written in the style of the
  existing ones. For example: wind direction against the path as a leading line, and gust strength
  where motion turns from atmosphere into distraction.
- `docs/PERFORMANCE.md`: the profiling table and findings from section 4.

## Non-goals

- Guiding-wind gameplay.
- The player or other objects pushing grass aside (possible later).
- Several grass species, flowers or other painted foliage.
- Painting terrain height or ground textures.
- Grass collisions, or grass hiding the player.

## Left to the builder

- Chunk size, blade mesh, instancing method and LOD details, within the requirements above.
- The gust noise shape and how the editor fallback motion works.
- Brush modifier keys and the toolbar layout.
- The collision layer the grass raycasts against.
- The compass-angle convention for `wind_direction` (state it in the panel and in `README.md`).
- Mask file format, and whether new shaders go in `assets/shaders/` or `assets/materials/`.
- Test breakdown, using the existing `tests/run.gd` runner. Visual checks via `--capture-views`
  stay part of each task that changes the look.
