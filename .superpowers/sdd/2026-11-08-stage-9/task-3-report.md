# Task 3 report: GrassField (mask, painting, ground cache, chunks)

**Status:** DONE_WITH_CONCERNS (two test deviations, explained below; the code follows the brief's contract)

## Implemented
- `GrassField` (`@tool`, `class_name GrassField extends Node3D`) with everything in the brief's interface:
  `CHUNK_SIZE`, `PaintMode`, `rebuilt(blade_count)`, the exports with the brief's defaults (they mark the
  field dirty, and it rebuilds in `_physics_process`, the same pattern as Scatter), `mask_size`, `ensure_mask` (RG8, filled with
  (0, 0.5); converts a wrong format and resizes bilinear), `sample`, `paint`, `set_mask_data`,
  `rebuild(rect)`, `refresh_ground`, `ground_height_at`, `blade_count`, `chunk_instance`, `static blade_mesh`.
- Conventions: the field is centred on the node. Texel (0, 0) and chunk (0, 0) are both at the field's −X/−Z corner (the
  tests use the brief's indices unchanged). Texel centres are at `corner + (i + 0.5) * texel_size`.
- `paint`: works on the raw RG8 bytes. It only visits the disc's bounding box, clamped to the mask, so a brush
  that is off the field or bigger than the field never writes out of range. The returned rect covers the texels whose stored byte actually
  changed (empty if none did). Falloff 0 is handled without calling `smoothstep(r, r, d)`.
- Placement follows the brief's algorithm exactly: per-chunk RNG `hash([random_seed, cx, cy])`,
  `int(blades_per_m2 * 16²)` candidates. Each candidate draws its randoms in the order x, z, keep, jitter ±15%, yaw,
  lean ±10°, then tint, phase and fade. A candidate is kept if `keep < density` and the ground isn't NAN.
  `INSTANCE_CUSTOM = (tint, phase, fade, 0)`, with all three in 0..1. Basis = yaw · lean · scale(1, h, 1), so
  `basis.y.length() == h`.
- Optimisation: a chunk is skipped (no node) when every texel a bilinear sample in it can reach has
  R = 0. This gives the same result as running the candidates, because `keep < 0` is never true.
- Chunks: `MultiMeshInstance3D` named `Chunk_x_y`, with no owner, `cast_shadow = OFF`,
  `visibility_range_end = fade_end + CHUNK_SIZE`. All chunks share one material and one blade mesh.
- Ground cache: one ray per texel centre from y = 40 to y = −5 against `1 << (ground_layer - 1)`, with NAN on a miss.
  It's computed lazily on the first rebuild, which `_ready` defers to the physics step. It's recomputed when the size,
  texel size, layer or node position changes, or when `refresh_ground()` is called. `ground_height_at` is bilinear, and returns NAN if any of its 4
  samples missed or the point is outside the field.
- `grass.gdshader` (colour only): `cull_disabled`, colour from base to tip by `UV.y`, the per-face derivative normal
  from flat_color, base darkening, and a tint jitter from `INSTANCE_CUSTOM.r`. The base darkening is measured along the blade (`UV.y`) rather than by world height, so
  it still works on mounds. Base `(0.12, 0.14, 0.10)`, tip `(0.30, 0.31, 0.19)`. The fade uniforms are not wired
  yet (Task 4). `fade_end` already sets the chunk visibility range.

## Files
- Created: `scripts/environment/grass_field.gd`, `assets/shaders/grass.gdshader`, `tests/test_grass_field.gd` (all LF).

## TDD evidence
GODOT=/d/softwares/Godot_v4.6-stable_mono_win64/Godot_v4.6-stable_mono_win64_console.exe
- RED: `"$GODOT" --path . -s res://tests/run.gd -- --only=grass_field`
  `Parse Error: Identifier "GrassField" not declared` → `FAIL test_grass_field.gd (does not parse)`, `0 passed, 1 failed`.
- After the first implementation, 5 passed and 2 failed:
  - `test_heights_follow_mask`: 5 of 50 blades were below the 0.84 × max limit (see Deviation 1).
  - `test_no_blades_where_ground_missing`: 702 blades at (500, 500) (see Deviation 2).
- GREEN (windowed, after the test fixes): `7 passed, 0 failed, 0 skipped`, exit 0.
- Headless: `"$GODOT" --headless --path . -s res://tests/run.gd -- --only=grass_field` gives `7 passed, 0 failed, 0 skipped`.
- Full suite windowed: `"$GODOT" --path . -s res://tests/run.gd` gives **`72 passed, 0 failed, 0 skipped`**, exit 0 (65 + 7).
  The output includes 2 `ConfigFile parse error at user://test_presets.cfg` lines. These come from the existing presets tests, are expected, and are not new.

## Deviations from the brief (tests only)
1. **test_heights_follow_mask:** ruling 1 (falloff 0) is not enough. Even with hard-edged discs,
   `sample()` is bilinear. Where a point at the rim of the density disc has R > 0, its four neighbours include
   unpainted texels with G ≈ 0.5, so blades there get a blended height of about 0.6–0.8 × max. Fix: the test paints HEIGHT with
   radius 6 (density keeps radius 4), both with falloff 0. Every texel that affects a kept blade then has G = 1.
   The code still follows the brief (`lerp(min, max, sample().y)`).
   *Option for the controller:* weighting height by density (G = Σ wRG / Σ wR) would keep tall patches tall right up to their rim
   in real painting too. Today, a tall stroke whose height disc matches its density disc gets slightly shorter blades along its rim.
   This is a contract change, so I didn't make it.
2. **test_no_blades_where_ground_missing:** the Ground's collider is an infinite `WorldBoundaryShape3D`
   (playground.tscn, `Ground/Shape`). Only the visible mesh is 400 m, so rays at (500, 500) still hit y = 0. The test now
   also sets `f.ground_layer = 20` (an unused layer) before `refresh_ground()`. That exercises the same no-hit code path
   (no blade, NAN). The alternative was to change the Ground collider to a 400 m box, but that is a scene and physics change outside this task.
   Note for Task 5 and review focus 3: off-plane areas are *not* holes in this scene.
3. Added one guard check to the partial-rebuild test (`far != null`), so that it can't pass vacuously.

## Self-review
- Interface names, signatures and defaults match the brief, including the `falloff := 0.5` 6th argument and `rebuild(texel_rect := Rect2i())`.
- Edge clipping: the bbox is clamped to `[0, size)` before any write. If it's fully off the field, the function returns early with an empty rect.
- Partial rebuild: rect grown by 1, then mapped to chunks from texel centres, then clamped to the chunk grid. Only those chunks are freed and rebuilt.
  A full rebuild clears `_dirty`. A partial rebuild leaves it as it was.
- Reproducibility: the RNG is seeded per chunk and every random is drawn before any rejection, so a stroke in one chunk never
  moves blades in another.
- If `rebuild()` is called before the node is in the tree, it only marks the field dirty, which avoids a null space state.

## Concerns
- Speed (windowed, playground): a 74×104 field filled to full density took 621 ms to build fully, with **184,523 blades**.
  Ground cache plus an empty rebuild took 71 ms. A 2 m stroke plus its partial rebuild took 26 ms, so painting stays interactive. At 24 blades/m², a fully
  painted play area is a lot of blades for the 2.0 ms GPU budget. Task 5's starter mask should be partial, or
  `blades_per_m2` tuned there.
- The chunk AABB comes from the MultiMesh instances. Task 4's wind bend may need a custom AABB margin to avoid culling at the screen edges.
- Assumes the field node is not rotated or scaled (stated in the class doc).
