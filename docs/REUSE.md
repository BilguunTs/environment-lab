# Reusing the grass and wind in a game level

Everything the playground adds on top of a plain level is optional. This is the short list of what a
game project needs from here.

## What to copy

- `scripts/environment/`: `wind.gd`, `grass_field.gd`, `grass_brush.gd`, `kit_asset.gd`
- `assets/shaders/` (the wind include and grass shader live here) and `assets/materials/`
- The kit scenes in `scenes/environment/kit/` you actually place, and `assets/meshes/` (the `.glb`
  files those kit scenes reference)
- `assets/shaders/gradient_sky.gdshader` and `assets/shaders/ground_mist.gdshader` if you want the
  playground's sky and ground mist (see "Fog, mist and sky" below)
- `scripts/player/player.gd` + `scenes/player/player.tscn` and `scripts/camera/follow_camera.gd` if
  you want the walker and orbit camera (see "Player and camera options")
- `addons/grass_painter/` (the editor brush; the only plugin, and it paints grass masks and nothing else)

After copying, run `Godot --headless --path . --import` once so the new `class_name`s register.

## Project settings

Copy these three sections of `project.godot` (or set the same values in Project Settings):

- **`[shader_globals]`** (Project Settings > Shader Globals): all three wind globals are required,
  because the materials read them:
  - `wind_strength`, float, `0.6`
  - `wind_direction`, vec2, `(0.8, -0.6)`
  - `wind_phase`, float, `0.0`
- **`[layer_names]`**: `3d_physics/layer_1="world"` and `3d_physics/layer_2="ground"`.
- **`[editor_plugins]`**: `enabled=PackedStringArray("res://addons/grass_painter/plugin.cfg")`
  (Project Settings > Plugins > enable *Grass Painter*).

## The ground rule

Grass finds the ground with a ray against **layer 2 only**. Walkable ground therefore needs collision
on layers **1 + 2** (`collision_layer = 3`). Kit ground pieces (mounds) set `collision = true` so
they carry it. Anything not on layer 2 (boulders, props) gets no grass on top of it, and a spot with
no ground below gets no blade.

The ray runs from `ray_above` (default 40 m) over the field's own height (its node y) down to
`ray_below` (default 5 m) under it. A field on high or steep ground, such as a section of a mountain
trail, sits at the section's middle height with both widened to cover its climb (Heavens call
uses half the section's height range plus 25 m). The first ground-layer hit from the top wins.

## A new level in five steps

1. Add a `Wind` node. Set `strength` and `direction_degrees` (a compass angle the wind blows
   toward: 0 = toward -Z, 90 = toward +X, clockwise from above).
2. Add a `GrassField` node.
3. Set its `extent` (metres, centred on the node) to cover the area you want to paint. Settle
   `extent` and `texel_size` before painting: changing either afterwards stretches the painted mask.
4. Save the scene, then select the `GrassField`. The Grass Painter toolbar appears in the 3D editor.
5. Paint: LMB paints, Shift+LMB erases, `[` / `]` change the radius, Ctrl+Z undoes a stroke. The
   toolbar sets mode, radius, strength, target and falloff. The mask is only written once the
   scene has a file, so save the scene before the first stroke; after that the plugin saves the
   mask to `<scene>_grass.res` next to the scene after every stroke. A duplicated field gets its
   own copy (`<scene>_grass_2.res`, ...) on its first stroke.

## Fog, mist and sky

Heavens call copied these from `scenes/playground.tscn` into `scenes/levels/heavens_call.tscn`.
Open either scene and copy the nodes and sub-resources; nothing here needs code.

- **`WorldEnvironment`**: `background_mode = Sky` with a `Sky` whose material is a `ShaderMaterial`
  on `gradient_sky.gdshader` (`horizon_color`, `zenith_color`, `glow_size`, `glow_energy`). Keep
  the roles: horizon colour = fog colour (`fog_light_color`, `background_color`), zenith colour =
  `ambient_light_color` (ambient from colour, `ambient_light_source = 2`). Other settings:
  AgX tonemap (`tonemap_mode = 4`), SSAO and glow on, depth fog (`fog_density`,
  `fog_aerial_perspective`, `fog_sky_affect`, a thin `fog_height` layer), and volumetric fog
  (`volumetric_fog_enabled`, `density`, `albedo`, `anisotropy`, `length`, `ambient_inject`,
  `sky_affect = 0`). Without volumetric fog enabled the mist below draws nothing.
- **`Mist`**: a `FogVolume` (the level uses 110 x 30 x 110 m) whose material is a `ShaderMaterial` on
  `ground_mist.gdshader` with a seamless `NoiseTexture3D` as `noise_tex`. Uniforms: `density`,
  `mist_height` (how far above the base it thins out), `base_height` (world y it is thickest at and
  below; 0 = the playground's flat ground), `noise_scale`, `offset` and `albedo`.
- **Following the player up a slope.** The volume is finite, so a script keeps it centred on the
  player and sets `base_height` to a little below her feet every frame, which lets the mist climb a
  mountain with her. `scripts/levels/mood_director.gd` does this for the level.
- **Mist drift follows the wind.** `offset` is advanced each frame from the wind, as an integrated
  sum (`_mist_offset -= wind direction x strength x speed x delta`), never `TIME * speed`: a change
  of wind strength then never makes the mist jump. The playground does the same in `playground.gd`.

## Player and camera options

- **`Player`** (`scripts/player/player.gd`): `walk_speed` (default 3.5), `can_sprint` (default true;
  off = Shift does nothing) and `lantern` (default true; off removes the lantern mesh and its light).
  Heavens call sets 2.0 / false / false.
- **`FollowCamera`** (`scripts/camera/follow_camera.gd`):
  - `min_pitch` / `max_pitch` (degrees, default -10 / 80) limit mouse and key pitch.
  - `collision_mask` (default 0 = off). Any non-zero mask pulls the camera in front of the first
    hit between the look target and the camera, so terrain never covers the view.
  - `orbit_locked` (a variable, not an export): when true, mouse orbit, wheel zoom and Q/E are
    ignored. Cutscenes set it so nothing but the cutscene moves the camera.

## Kit pieces placed high up: `height_from_origin`

`flat_color.gdshader` sways cloth by world height above y 0. A kit piece placed far above y 0, such
as a banner on a mountain at y 60, would sway by that whole height. Tick **Height From Origin** on
the placed kit instance (`kit_asset.gd` export `height_from_origin`): it sets the
`height_from_origin` instance uniform on every mesh of the piece, and sway and contact shade then
use height above the piece's own origin. Hand-made materials on `flat_color.gdshader` can set the
instance uniform themselves. Pieces near y 0 do not need it.

## Testing a level scene

`tests/run.gd` runs every test file against the playground by default. A level's tests declare their
scene instead:

```gdscript
extends "res://tests/case.gd"
const SCENE := "res://scenes/levels/my_level.tscn"
```

The runner groups files by `SCENE`, instances each scene once, and, if the scene's root has a
`reset_scene()` method, calls it before every test. `tests/case.gd` has `await physics_frames(n)`
(n physics ticks, then two process frames) for teleport-then-read tests, where one process frame
does not guarantee a physics tick.

## Playground-only parts

Not needed in a game level: the dev panel, presets, Compare, the debug tools (value probe, perf HUD,
light gizmos), the composition guides, and `tools/` (such as `make_starter_grass.gd`, which only
writes this playground's starter meadow).

Performance numbers for the grass are in [PERFORMANCE.md](PERFORMANCE.md).
