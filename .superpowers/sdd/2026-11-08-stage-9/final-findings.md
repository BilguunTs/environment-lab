# Stage 9 final review — findings to fix (one fix wave)

I1. Gust pattern jumps on direction change; jump grows with runtime (Review Focus 1 not met).
  assets/shaders/wind.gdshaderinc:22-25, scripts/environment/wind.gd:33. wind_gust uses p = world_xz - wind_offset then projects p on along/across built from the CURRENT direction; wind_offset grows without bound along old directions (~2.4 m/s default → ~1.4 km after 10 min), so a 1° step shifts the pattern by |offset|·sin(1°) ≈ 25 m (0.6 noise cells) after 10 min. Trees share it.
  Fix: keep the scroll in pattern space — publish a scalar phase integrated from strength*GUST_SPEED*dt (replace or repurpose wind_offset; keep project.godot [shader_globals], docs, README, REUSE consistent with whatever you name it) and compute q = vec2(dot(world_xz, along)/20 - phase/20, dot(world_xz, across)/40) (keep the existing scales). Wrap/rebase the phase so float32 precision never stalls (e.g. periodic noise along q.x and wrap phase by the period).
  Check consumers of wind_offset / Wind.offset (playground mist? tests) and update them.
  Test: replace the weak test_gust_offset_has_no_jump with one that evaluates the gust pattern math in GDScript (mirror the shader function, or a static Wind helper the test can call) at a sample point before and after a 1° direction step with a large accumulated phase, asserting the change is small (< 0.1 noise cell equivalent); plus assert the per-frame phase advance = strength*GUST_SPEED*delta.
  Controller ruling: an instant direction change from a preset/A-B/reset is a cut — do NOT add smoothing (it would break A/B and capture determinism).

I2. Duplicated GrassField (Ctrl+D / copy-paste into another scene) shares its mask .res; painting one silently overwrites the other's file.
  addons/grass_painter/plugin.gd:159-163 (_save_mask). Fix: at stroke begin, if the mask's resource_path doesn't belong to the edited scene (doesn't start with the edited scene's dir + basename + "_grass") OR another GrassField in the edited scene holds the same mask object, fork it first (field.mask = field.mask.duplicate(), clear path) so _save_mask writes a new <scene>_grass[_N].res. Must keep the playground's existing Grass → playground_grass.res working without forking (the starter file is named playground_grass.res next to... check its path vs scene path and make the rule accept it, or rename consistently). Undo still correct. Test what can be tested outside the editor (e.g. a static helper deciding "needs fork" given scene path + mask path + sibling fields).

I3. REUSE.md doesn't fully work if followed literally.
  - docs/REUSE.md:8-11 omit assets/meshes/ (.glb files the kit scenes reference).
  - Name the project.godot entries to copy: [shader_globals] (the wind globals), [layer_names] 3d_physics/layer_1/2, [editor_plugins].
  - REUSE.md:37-39: the plugin only writes the mask .res once the scene has been saved to a file; say "save the scene before the first stroke; the plugin saves the mask to <scene>_grass.res after every stroke" (also fixes the Task 10 deferred minor about manual mask save).
  - Step 3: warn that changing extent or texel_size after painting stretches the painted mask.
  - Step 1: name Wind.direction_degrees (Task 10 deferred minor).

I4. Falloff control missing from the painter toolbar (spec §3 lists radius, strength, target value and falloff).
  addons/grass_painter/plugin.gd:259-264 — add a Falloff SpinBox (0–1, default 0.5) wired to GrassBrush.falloff. Update README painter controls.

M4. README.md:156-157 still says wind is shader_globals/wind_strength "set by the Wind slider" — describe the Wind node and the wind globals. Also wrap README line 173 to match neighbours.
