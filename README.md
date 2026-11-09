# Environment Forge

A small Godot 4 playground for practising stylized environment art and level design:
composition, silhouettes, depth, lighting and atmosphere. The brief and staged roadmap live in
[main.md](main.md). **Current stage: 9 (wind, painted grass, profiling, reuse).**

## Run

- Engine: **Godot 4.6** (the mono build works; the project is pure GDScript).
- Open `project.godot` in Godot and press **F5**, or run from a terminal:

```sh
Godot_v4.6-stable_mono_win64.exe --path D:/DevEnv/GDOT/environment-lab
```

Optional command-line flags (after `--`):

```sh
# apply a preset, render every viewpoint to screenshots/, then quit
Godot... --path . -- "--preset=Foggy Forest" --capture-views --quit

# measure every fixed view with grass on then off, write screenshots/profile_<datetime>.md
Godot... --path . --resolution 1920x1080 --disable-vsync -- --profile-views --quit
```

## Heavens call

`scenes/levels/heavens_call.tscn` is a 5-7 minute walking level built from this kit: a tired
cloaked girl climbs a foggy mountain trail to a summit reveal and the title. Open the scene and
press F6, or run:

```sh
Godot... --path . res://scenes/levels/heavens_call.tscn
```

Details, capture/profile flags and the view list: [docs/HEAVENS_CALL.md](docs/HEAVENS_CALL.md).

## Controls

| Input | Action |
| --- | --- |
| WASD / arrows | Move (relative to the active camera, cinematic views included) |
| Shift | Sprint |
| Right-mouse drag | Orbit the gameplay camera / look around in Scout |
| Q / E | Orbit left / right (gameplay), down / up (Scout) |
| Mouse wheel | Zoom (gameplay) / fly speed (Scout) |
| C | Cycle fixed views (Gameplay and the viewpoints) |
| F | Scout (free-fly) camera on/off. It starts from the current shot, and the player stops responding while you scout |
| B | Bookmark the current shot as a new viewpoint |
| G | Cycle grid: off / thirds / golden / diagonals |
| V | Cycle value view: colour / grayscale / 3-value / notan |
| P | Pin the current settings as A (compare) |
| X (hold) | Show A; release for the live scene (B) |
| Z | Split screen: frozen A image left, live B right; drag the divider |
| F2 | Cycle render mode: normal / unshaded / lighting / overdraw / wireframe |
| F1 | Show / hide the dev panel |
| F12 | Screenshot (panel and HUD hidden; guides and value view kept) to `screenshots/` |

The top-right HUD shows the active view, its FOV and full-frame lens equivalent in mm, and the
shot's *intent* (what it is meant to communicate).

## Dev panel

Each control below changes the scene.

- **Camera:** active view and FOV with its mm equivalent (applies to whichever camera is active). Gameplay-camera height, distance, pitch and **Shift X/Y** (lens shift: slides the frame without rotating it, so the player can sit on a third). Buttons for Scout and Bookmark.
- **Framing & Values:** grid (thirds, golden section, diagonals), aspect mask (2.39:1, 1.85:1, 4:3, 1:1), centre marker. Value view (grayscale, 3-value, notan) with *Value split*, the luminance where figure turns into sky, and *Squint*, a blur that removes detail.
- **Lighting:** sun energy, height (elevation), angle (azimuth) and colour. *Shadow fill* is ambient light, which takes the sky-top colour. Shadows on/off.
- **Atmosphere:** horizon/fog colour and sky-top colour (a gradient sky). *Sun glow* is a halo in the sky and scatter in the fog. Depth fog density, ground fog, *Light shafts* (volumetric fog on/off), shaft density, and *Drifting mist* (a volumetric ground mist that only shows while light shafts are on).
- **Motion:** *Wind* drives tree and cloth sway, grass, mist drift and mote drift; gusts roll across the forest. *Wind direction* is a compass angle in degrees: the way the wind blows *toward*, 0 = toward -Z, 90 = toward +X, clockwise seen from above. Floating motes around the player. The altar ember and the player's lantern always flicker.
- **Supernatural:** *Monolith awake* switches the whole effect on/off (off = the hole shows sky again). *Spirits* sets how many wisps flow from the hole down to the altar ember. *Hole glow* scales the glowing core, its halo and the cold spotlight from the hole together; they breathe on a slow 6 s cycle. The spotlight's shaft only shows while *Light shafts* is on.
- **Environment:** landmark, props and grass visibility (hidden props still collide). *Forest* switches between **Manual** (the hand-placed forest) and **Procedural** (scatter layers). *Seed* / *New seed*, *Tree density*, *Tree spacing*, *Clumping*, *Rock density*. *Show exclusion zones* draws the scatter masks in the world. The status line reports tree and rock counts after each regeneration.
- **Presets:** Flat Overcast (the Stage 2 look, kept for before/after comparison), Wide Reveal, Low Silhouette, Golden Backlight, Foggy Forest, Ritual Clearing, Moonlit, Awakened (dusk; the Stage 7 money shot), and Reset (default state plus player back at spawn). Each preset stores only its overrides on top of the default "Cold Dawn" mood; edit them in `scripts/presets.gd`. A preset that switches to a fixed view keeps that view's authored lens. Type a name and press *Save preset* to keep the current settings: only what differs from the default (plus the view) goes into `presets/user_presets.cfg`. Saving with the same name overwrites; to delete a preset, edit that file. It lives under `res://`, so saving works when running from the project folder, never in an exported build.
- **Capture:** Screenshot, *All views* (one PNG per viewpoint, same lighting), and *Copy settings*, which copies the current state as text so you can paste it in as a new preset.
- **Compare:** *Pin A* (P), *Split* (Z) and *Save pair*, plus a live list of what differs between A and the live scene (B). A and B share the camera, the guides and the value view; a lens is compared only in the view where A was pinned. In split view A is a frozen render that re-renders (a short blink) when the camera stops or the value view changes. *Save pair* writes `screenshots/<stamp>_compare_<view>.png`: A and B side by side with the diff underneath. It also copies an experiment-log row (Date and Changed filled in) to the clipboard.
- **Debug:** *Render* mode, the *Value probe* (luminance under the cursor, frame p5/p50/p95 and a histogram with the notan *Value split* marked), the *Perf readout* (fps, CPU/GPU ms, draw calls, primitives) and *Light gizmos* (omni ranges, spot cones, sun direction, drawn through everything). None of these are part of presets, *Copy settings* or A/B. The probe reads the frame back from the GPU four times a second (about 15 ms each), so expect small hitches while it's on.

Colour roles are fixed on purpose:
- **Horizon = fog colour.** Distant forms dissolve into the sky behind them, which is what produces atmospheric perspective.
- **Sky top = shadow fill.** Shadows are lit by the sky, so they take its cool colour while the sun stays warm. That temperature contrast is most of what makes the scene feel alive.

The **Overview** camera ignores all fog (depth and volumetric) because it is a layout view.

Panel sections collapse when you click their headers. The panel opens with the lighting sections expanded.

## Viewpoints

Fixed views are `Viewpoint` cameras (`scripts/camera/viewpoint.gd`) with an `intent` note. Several
are paired so you can compare them by pressing C:

| View | What it's for |
| --- | --- |
| Reveal | Establishing shot: goal, route and obstacle in one frame |
| Long Lens ↔ Landmark Foot | 20° telephoto compression vs 70° wide lens up close: how lens choice changes scale and threat |
| Path Low | Worm's-eye; trees become sky silhouettes |
| Forest Gate ↔ Gate Thirds | The same position with the landmark centred vs on the right third |
| Clearing | Warm focal point against a cold background |
| Camp | Secondary landmark and story beat at the end of the side trail |
| Overview | Fog-free layout plan |

**Bookmarks** (B) exist only for the current session. Each bookmark copies a `.tscn` node snippet to the clipboard
(it is also printed to the output log). To keep it, paste the snippet under the Viewpoints nodes in
`scenes/playground.tscn`. It works as a plain Camera3D; if you want an intent note, attach `viewpoint.gd`.

## Layout

```
project.godot
scenes/
  playground.tscn            main scene: lights, terrain, forest, clearing, landmark, cameras, UI
  environment/kit/           kit asset wrappers (place these, not the GLBs): 3 trees, 3 rocks,
                             2 mounds, cairn, log, stump, landmark; modular wall segment + end,
                             khadag post, spirit banner, fire ring, ger ruin
  environment/tree_dead.tscn the one remaining primitive prefab
  player/player.tscn
scripts/
  playground.gd              owns every tunable parameter (get_param/set_param), presets, screenshots
  presets.gd                 named presets (overrides only) + saved user presets
  compare.gd                 A/B compare: pin, hold-to-flip, split capture, saved pairs
  player/player.gd           CharacterBody3D walker
  camera/follow_camera.gd    gameplay orbit camera with lens shift
  camera/viewpoint.gd        fixed cinematic camera + intent note
  camera/scout_camera.gd     free-fly camera for finding shots
  effects/flicker_light.gd   noise flicker for fire / lantern lights
  effects/breathe.gd         slow pulse for the hole glow: core emission + halo + spotlight
  effects/spirit_stream.gd   @tool: feeds the spirit stream its source/target positions
  environment/path_ribbon.gd @tool: builds the path mesh from editable points
  environment/kit_asset.gd   @tool: swaps imported materials for palette materials by name
  environment/wind.gd        @tool: strength, compass direction and the shared gust field (shader globals)
  environment/grass_field.gd @tool: painted grass, chunked MultiMesh blades on layer-2 ground
  environment/grass_brush.gd brush logic shared by the editor painter
  procedural/scatter.gd      @tool: reproducible scatter layer (seeded, masked, ground-snapped)
  procedural/exclusion_zone.gd @tool: circle / capsule / box keep-out area with soft edge
  ui/dev_panel.gd            runtime panel, built in code
  ui/composition_guides.gd   grids, centre marker, aspect masks
  ui/compare_view.gd         split-screen overlay with a draggable divider
  debug/debug_boot.gd        autoload: enables wireframes before any mesh loads
  debug/value_probe.gd       cursor value, percentiles, histogram
  debug/perf_hud.gd          fps, CPU/GPU ms, draw calls
  debug/light_gizmos.gd      light ranges and cones drawn on top
addons/grass_painter/       the one editor plugin: paints the grass mask (see Grass below)
tools/make_starter_grass.gd  one-off script that wrote the starter meadow mask
presets/user_presets.cfg     saved presets (created on first save; plain text)
tests/                       run.gd (runner), case.gd (base), test_*.gd
assets/blender/              build_kit.py (procedural kit builder) + environment_kit.blend (git: source)
assets/meshes/               exported GLBs (generated by build_kit.py)
assets/materials/            flat_color.gdshader (faceted look, wind sway, tint variation) + palette
assets/shaders/              value_view (grayscale / 3-value / notan / squint),
                             gradient_sky (horizon/zenith + sun halo), ground_mist (FogVolume),
                             spirit_stream (particle path), spirit_wisp, light_halo
docs/                        art direction notes and experiment log
screenshots/                 captures (git-ignored; .gdignore keeps Godot from importing them)
```

## Editing the composition

- Every tree, rock, stone, prop and mound is a separate instance in `playground.tscn`, so you can move them directly in the editor. In Procedural mode the `Forest` node is swapped for the scatter layers (see below); everything else stays hand-placed.
- To change or add assets, see [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md).
- To change the path, select **Path** and edit its `points` (x, z) in the Inspector. The mesh rebuilds live.
- To frame a viewpoint, select a camera under **Viewpoints** and tick *Preview* in the 3D viewport. Then move the camera or change its FOV.
- Scale reference: 1 unit = 1 m. The player is about 1.8 m tall, spruces are 10–16 m, larches about 11 m, and the monolith tops out around 26 m.

## Wind sway on materials

`flat_color.gdshader` sways vertices by `sway × wind × height²`, using world height above the
ground. Every part of one object must use the same `sway` value: spruce trunk and foliage share
0.35, and dead trees use 0.2. Otherwise the crown slides off the trunk. Rocks and the ground use 0
(rigid). Wind comes from the `Wind` node, which publishes three global shader parameters
(`[shader_globals]` in `project.godot`): `wind_strength`, `wind_direction` and `wind_phase` (how
far the gusts have travelled downwind). The Wind and Wind direction sliders set the node.

Performance (RTX 3070, 1600×900): about 850 fps with everything on. Volumetrics cost about
0.13 ms per frame and wind sway about 0.07 ms.

## Grass and wind

`Grass` is a `GrassField`: a rectangle of blades driven by a painted mask (R = density, G = height),
drawn as chunked MultiMeshes with a wind-driven shader. Blades sit on ground found by a ray against
physics layer 2 (`ground`), so walkable ground needs collision on layers 1 + 2, and a spot with no
ground gets no blade. The wind comes from the `Wind` node: strength, a compass direction and a gust
field that travels with it, shared by the grass, trees and cloth. Direction is the angle the wind
blows **toward**: 0 = toward -Z, 90 = toward +X, clockwise from above (default 53.13: mostly +X
with a bit of -Z). Gusts show as waves rolling across the meadow.

To repaint, select `Grass` in the editor (the *Grass Painter* plugin must be enabled):

| Input | Action |
| --- | --- |
| Left-mouse drag | Paint with the toolbar's mode (Density / Height / Erase), radius, strength, target and falloff |
| Shift + left-mouse drag | Erase (a clearing) |
| `[` / `]` | Shrink / grow the brush radius |
| Ctrl+Z | Undo the last stroke (one stroke = one step) |

The mask is saved to its own `.res` at the end of every stroke (save the scene before the first
stroke). A duplicated field (Ctrl+D), or one pasted from another scene, gets its own copy of the
mask on its first stroke, so it never overwrites the other's file. The starter meadow is written by
`tools/make_starter_grass.gd`. Costs and budgets: [docs/PERFORMANCE.md](docs/PERFORMANCE.md). Moving
this into a game level: [docs/REUSE.md](docs/REUSE.md).

## Procedural scattering

`Scatter/Trees` and `Scatter/Rocks` are `Scatter` layers. Each throws seeded candidate points over
a rectangle and keeps a point with a probability shaped by:

| Mask | Purpose |
| --- | --- |
| Clumping noise (`clumping`, `clump_size`) | Groves and gaps instead of an even park |
| Path margin + falloff | The path stays walkable and readable |
| Far thinning (`far_distance`, `far_keep`) | Dense walls frame the corridor; the deep forest is thinner |
| `Scatter/Zones` (ExclusionZone nodes) | Clearing, landmark, the spawn → landmark sightline, the opening before the clearing |
| Obstacles (`Hero`, `Props`, `Clearing` children) | Hand-placed items are never overlapped |
| `min_spacing` | Trunks never intersect |

Then items snap down onto `Ground` / `Terrain` collision, so trees stand on the mounds.

**Guarantees:**
- **Reproducible:** the same seed and parameters give the same layout.
- **Stable:** every candidate draws its random numbers before any test, so changing a slider never reshuffles the forest. Lowering density keeps an exact subset of the trees.
- **Disposable:** generated nodes are not saved. Switching back to Manual, or Reset, removes them, and the scene file only stores the parameters.

**Never scattered**, because they're composition and not repetition: the gate trees and framing
boulders (`Hero`), props, the clearing stones, and the landmark.

**In the editor:**
- Zones always draw their outlines. Move them like any node; the inner line is the hard edge and the faint outer line is the falloff.
- To tune live, make `Scatter/Trees` visible (eye icon) and hide `Forest`. It regenerates as you edit its Inspector values.

## Paths and modular pieces

- **Two paths.**
  - `Path` is the main route. It's bright, wide, and has worn edges (`edge_noise`).
  - `SideTrail` branches east to the camp. It's narrower, darker (`path_faint.tres`), and starts thin where it leaves the main path.
  - The difference in brightness *is* the hierarchy: the eye follows the main path first.
  - Both are `path_ribbon.gd` nodes, so you can edit their `points` in the Inspector. Scatter layers keep clear of every path listed in their `paths`.
- **Modular walls.** `wall_segment` runs from x = 0 to x = 4 m along its local +X. Snap the next one at the previous end, rotate freely, and finish with `wall_end` (2 m, crumbling). The camp's north wall is an example: WallA → WallB snapped at +4 m, then a gap where it fell, then WallEnd.

## Spirit stream

`SpiritStream` is a `GPUParticles3D` whose process shader (`spirit_stream.gdshader`) moves every
wisp along one quadratic Bezier, from `source` (the hole, `Landmark/HoleGlow`) through a control point
`arc_height` above the midpoint, to `target` (`Clearing/Ember`). The path is authored rather than simulated,
so moving either end node reshapes the stream, in the editor too. Keep the node at the origin with no
rotation, because the shader works in world space. Wisps pinch to a point at both ends, travel at slightly
different paces, and are fogged like everything else. The halo around the hole is *not* fogged
(`light_halo.gdshader`): a halo is the air scattering the light, so depth fog must not erase it.

Stage 7 costs about 0.01 ms per frame (842 fps in the default gameplay view).

## Tests

```sh
Godot --headless --path . --import                 # after adding a class_name
Godot --path . -s res://tests/run.gd               # full suite (opens a window for image tests)
Godot --headless --path . -s res://tests/run.gd    # logic only; image tests are skipped
Godot --path . -s res://tests/run.gd -- --only=compare
```

Each `tests/test_*.gd` extends `tests/case.gd` and drives the real playground scene. Any engine or
script error raised during a test fails it, unless the test declares it with `expect_error()`.
Exit code 0 means everything passed.
