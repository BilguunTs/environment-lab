# Task 6 report: summit vista, ovoos and grass

**Status:** DONE_WITH_CONCERNS (all green; the concerns are judgement calls listed at the end)

## What was implemented

**New files**
- `scripts/levels/vista.gd`: `@tool class_name Vista extends Node3D`. Everything far away is generated at runtime as internal children with no owner, under one internal `Far` node:
  - **Steppe:** a faceted polar disc, radius 3000 m, with 60 rings spaced on a 1.8 power and 160 segments. It sits at `steppe_y = 3.0`, which is 217 m below the summit. It is flat within 260 m of the centre, so it buries the square terrain's outer edge and its −200 m skirt. Beyond that, rolling noise grows to ±28 m by 1200 m. Golden vertex colours vary in two noise octaves (olive hollows, pale dry patches). `steppe_height_at(xz)` dips the steppe under the lowest stretch of trail: it stays 3 m under the trail, flat within 15 m of it and rising at 0.25 beyond, so the trail foot (y 0) is never under the plain.
  - **Ridges:** three rings of low-poly ridges with crests at 760, 1400 and 2250 m. Each ridge has a 7-row cross profile and noise peaks sampled on a circle, so the ring wraps without a seam.
    - The albedo gets darker and bluer per ring: (0.22,0.23,0.23), (0.17,0.20,0.26), (0.13,0.17,0.25). There is a touch of steppe gold low on the near foothills and old snow on the highest far crests.
    - The rings part toward −Z, the way she faces at the top. The gap crest stays below the mist, so the mist sea runs on to the horizon there, with the mountains rising either side. Crest ranges above the steppe are 40–210, 120–430 and 250–800 m.
  - **Mist sea:** two flat slab layers, 30 m and 75 m above the steppe, with radius 4500 m. They use the new shader `assets/shaders/mist_sea.gdshader`:
    - Opacity is the slab's optical depth along the view ray, `thickness / cos(view angle)`. Looking down it is a thin veil; toward the horizon it is a solid sea, which hides the steppe's edge.
    - Drifting noise banks move with the Wind node.
    - A soft depth fade where it meets the ground or ridges leaves no intersection line.
    - Its colour blends into the live fog colour with distance.
  - **Cloud deck:** one more slab of the same shader, dark slate, 1200 m above the steppe. It thickens toward the horizon and fades out before its rim (`rim_fade`), so it never cuts a line across the sky. This is a subtle stormy ceiling.
  - Every far mesh has `cast_shadow = OFF`, and nothing has collision.
  - `reveal` (export, 0..1) drives the mist-sea thickness (lower layer 1.2→0.2, upper 0.9→0.09) and `far.visible = reveal > 0`.
  - API: `fog_scale()`, `mist_scale()`, `horizon_tint(c)`, `zenith_tint(c)`, `steppe_height_at(xz)`, `horizon_distance()` (4500), plus `steppe_radius`, `steppe_y` and `ring_radii` exports.
- `tools/make_heavens_grass.gd`: the mask generator, following the `make_starter_grass.gd` pattern. `fields(lv)` and `build_mask(lv, cfg)` are static. It loads the level so the runtime terrain exists, writes the masks and prints the GrassField nodes as .tscn text.
- `assets/grass/heavens_{lower,middle,switchback,upper,summit}.res`: RG8 masks.
- `assets/shaders/mist_sea.gdshader`
- `tests/test_heavens_vista.gd`: 11 tests (below).

**Modified**
- `scenes/levels/heavens_call.tscn`:
  - New `Vista` node, wired to the trail, WorldEnvironment and Wind. It holds `Ovoos/Ovoo1..3`.
  - New `Grass` node with 5 GrassFields.
  - `GameplayCamera.far` goes from 600 to **5000**, so it reaches the mist-sea horizon at 4500 m.
  - `MoodDirector.vista` is wired.
  - New ext_resources: vista.gd, prop_khadag_post, grass_field.gd and the 5 masks.
- `scripts/levels/heavens_call.gd`: adds `@onready var vista: Vista`. `reset_scene()` now sets `vista.reveal = 0.0` before applying the mood.
- `scripts/levels/mood_director.gd`: adds an optional `@export var vista: Vista`. `apply()` composes the reveal on top of the mood (see the reveal mechanism below). `current` stays the mood's own values.
- `scripts/environment/grass_field.gd` (shared kit): the ground ray was hard-coded to world y 40 → −5, so no grass could grow on the mountain (y 0–220). It is now relative to the field's own height, through the new exports `ray_above` (default 40) and `ray_below` (default 5). The playground field is at y 0, so its behaviour is identical (the grass tests pass).
- `docs/REUSE.md`: the ground-rule section documents `ray_above` and `ray_below`.

## Ovoos

There are three, all on the summit plateau. Every kit instance has `height_from_origin = true`.

| Ovoo | position (x, y, z) | cairn scale | khadag posts |
|---|---|---|---|
| Ovoo1 | (−14, 219.9, −4.5) | 2.3 | 3 |
| Ovoo2 | (13, 219.9, −5.5) | 1.9 | 2 |
| Ovoo3 | (2.5, 219.9, −10) | 2.1 | 4 |

The posts are scaled 1.1–1.45, lean 5–11° and are set into the stones. Progress at each ovoo is 1.0. A scratch script produced the transforms and they were pasted into the scene.

## Grass fields

All trail fields use colours base (0.15,0.14,0.09) and tip (0.46,0.41,0.25), except Upper, whose tips are (0.58,0.52,0.33) so the edge tufts catch the dim light.

| Field | progress | centre | extent (m) | texel | blades/m² | heights (m) | rays ± (m) | mask peak / mean of non-zero | blades |
|---|---|---|---|---|---|---|---|---|---|
| Lower | 0–0.24 | (94, 24, −60) | 160×144 | 0.5 | 40 | 0.2–0.7 | 49 | 0.35 / 0.18 | 5538 |
| Middle | 0.24–0.50 | (−27, 81, −66) | 176×128 | 0.5 | 40 | 0.2–0.7 | 59 | 0.35 / 0.17 | 5638 |
| Switchback | 0.50–0.72 | (−46, 134, −39) | 144×96 | 0.5 | 40 | 0.2–0.7 | 46 | 0.34 / 0.15 | 4054 |
| Upper | 0.72–1.0 (outside the summit rect) | (−21, 187, 0) | 80×144 | 0.5 | 40 | 0.2–0.7 | 58 | 0.28 / 0.15 | 4679 |
| Summit | plateau | (0, 220, 0) | 48×32 | 0.5 | 26 | 0.3–0.85 | 8 | 0.85 / 0.69 | 15507 |

How the masks are built:
- **Trail masks:**
  - A texel belongs to the section its nearest trail point falls in (`Trail.progress_at` on the terrain height), so the fields never overlap.
  - Density is zero within 2.0 m of the centre (the gravel), ramps in over 1.2 m and fades out by 8.5 m. Ground steeper than 0.45–0.8 rise per metre gets none.
  - Tufts are metre-sized noise spots gathered by a broad noise, at most 0.35. They are a little thinner in the eerie stretch.
  - A thin band of tufts runs just off the gravel (0.2, rising to 0.32 from progress 0.82), so the path's edge reads in Task 3's dim stretch.
- **Summit mask:** density 0.6–0.9 over the flat plateau, clear around the ovoo cairns, with a worn line where the trail arrives.

## Reveal mechanism

`Vista.reveal` is set by the future SummitSequence. `MoodDirector.apply()` reads it every frame and composes it on top of the mood:
- `env.fog_density = mood.fog_density * vista.fog_scale()`, where `fog_scale() = pow(0.08, reveal)`. Opening geometrically makes the seen distance grow steadily rather than all at the end. At the summit key the fog goes 0.011 → 0.00088.
- The volumetric fog follows, as `env.fog_density * VOLUMETRIC_RATIO`.
- The ground `Mist` FogVolume density is `mood.mist * mist_scale()`, where `mist_scale() = lerp(1, 0.12, reveal)`.
- The fog, background, ambient and sky horizon colour is `horizon_tint(mood.sky_color)`, a 0.6·reveal lerp toward a blue-grey haze (0.56,0.60,0.67), so the ridges fade bluer. The sky zenith is `zenith_tint`, a lerp toward a stormy (0.19,0.22,0.29).
- At reveal 0 every factor is identity, so the mood is untouched and the test asserts it. Returning to 0 restores the mood's fog. The Storm's flash lighting still runs after this, on top.
- `Vista` itself thins the mist sea and shows the far world once reveal > 0. At very low reveal the fog is still nearly the full 0.011 (e^−7 at 700 m), so the far world can't pop in.

## RED / GREEN

- **RED:** `--only=heavens_vista` gave `FAIL test_heavens_vista.gd (does not parse ...)` with `Could not find type "Vista"`, so 0 passed and 1 failed. The scene had no Vista, Grass or class.
- **GREEN:** `--only=heavens_vista` passes 11 of 11, and `--only=heavens` passes 42 of 42.
- The tests:
  - The brief's four tests: `test_vista_hidden_until_reveal`, `test_ovoos_on_summit` and `test_summit_grass_is_golden_and_waving` as given, plus `test_trail_grass_is_sparse` as changed by **Ruling 2**. For each trail field it finds the trail centre point horizontally nearest the field's own centre (2001 samples), asserts that point lies inside the field's extent, asserts density < 0.05 there and asserts the field has blades. It also asserts there are 3–5 trail fields.
  - `test_grass_masks_fit_their_fields`: each mask's size equals `mask_size()` (no stretching), trail peaks are ≤ 0.45 and the summit peak is between 0.6 and 0.9.
  - `test_ovoo_kit_measures_from_origin`: each ovoo has one cairn scaled 1.5–2.5 and 2–4 posts, and every kit piece and mesh has `height_from_origin` on. This adds the Ovoos to Task 5's check.
  - `test_far_vista_only_while_revealing`
  - `test_reveal_opens_the_fog`: teleports to the summit and uses `physics_frames`.
    - Reveal 1 leaves the env fog and the volumetric fog under 10% of their closed values, and the ground mist under 30%.
    - Reveal 0 equals the mood's own fog, and closing the reveal restores it.
  - `test_steppe_buries_the_terrain_edge`: the steppe is more than 1 m above the terrain all around its one-cell-inset boundary ring, and more than 1 m below every trail point.
  - `test_vista_reaches_the_horizon`: steppe radius ≥ 3000 m, steppe 150–250 m below the summit, three rings within 600–2500 m, and camera far ≥ horizon distance.
  - `test_reset_closes_the_vista`

## Suite (checkpoint)

| Run | Before (expected) | After | Difference |
|---|---|---|---|
| Windowed | 129 | 140 passed, 0 failed | +11 new |
| Headless | 107 passed + 22 skipped | 118 passed, 0 failed, 22 skipped | +11 new |

The flaky `test_measure_is_fast` passed both times. There are no engine errors.

## Performance

The window was run at `--resolution 1920x1080 --disable-vsync` and actually measured 1920×1061 (the screen clips the title bar). The numbers are `PerfHud.measure(240)`, using `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\perf.gd`.

| View | GPU ms | draws | prims |
|---|---|---|---|
| summit, reveal 0 | 1.93 | 58 | 658k |
| summit, reveal 1, toward the vista | 2.18 | 65 | 684k |
| summit, reveal 1, pitch 20 (more ground and grass) | **2.48** | 91 | 686k |
| summit, reveal 1, yaw +50° | 2.12 | 42 | 665k |
| summit, reveal 1, looking back south | 1.85 | 78 | 659k |
| approach (0.95), reveal 1 | 1.64 | 92 | 689k |
| trail 0.30 | 1.63 | 174 | 599k |
| trail 0.90 | 1.44 | 25 | 583k |
| pull-back, reveal 1 | 1.69 | 94 | 610k |
| high pull-back, reveal 1 | 1.71 | 64 | 378k |

The worst view is 2.5 ms against the 7.0 ms budget, so there is plenty of headroom. The vista adds about 0.3 ms over reveal 0. The full profile comes in Task 9.

## Captures

The capture script is `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\capture.gd`. It runs windowed at 1280×720, except the last file below, which is 1920×1061.

What each final capture showed:
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\summit_r0.png`: golden waving grass and the three ovoos (blue khadags) in thick grey fog. Nothing of the vista shows, which is correct.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\summit_r05.png`: half open. Ridges are just emerging and the fog is lifting.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\summit_r1.png`: reveal 1 toward −Z. The ovoos stand against a stormy sky with a subtle cloud ceiling, the ridges recede pale blue-grey on both sides, and a band of mist sea sits at the horizon. The golden grass bends in the wind.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\summit_r1_left.png` and `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\summit_r1_back.png`: the side and back views. The back (south) view is the strongest: layered ridges rising out of the mist ocean in successively paler bands.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\pullback.png` and `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\pullback_far.png`: behind and above her, looking −Z. The summit rises out of an ocean of mist that runs unbroken to the horizon, with golden steppe glimpsed through gaps below. The ridges fade bluer with distance. **No square edge or skirt is visible anywhere**, and it reads as an endless world rather than a diorama.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\trail_030.png`: sparse windswept tufts on the uphill side and the shelf, with the gravel clear.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\shots\trail_090.png`: a dim stretch. Lines of tufts along both path edges help the path read.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\hd\summit_r1_left.png`: the 1920-wide check.

**Iteration log:**
1. **First pass:** the near ring was 110–330 m tall at 760 m, and fog at reveal 1 was only 4% of the mood's. The ridges read as close grey walls and formed a canyon, with curved "terrace" lines where the low gap crest poked through the mist.
2. **Fixes:**
   - The near ring was lowered to 40–210 m and the gaps widened, with the gap crest kept under the mist.
   - OPEN_FOG went from 0.04 to 0.08, which gives stronger layering.
   - The horizon and zenith tints were added.
   - The peaks were sharpened, and the mist banks made bigger and higher in contrast.
3. **Cloud deck:** added. At first its rim cut a hard line across the sky, which `rim_fade` fixed. At 1800 m it was invisible, so it settled at 1200 m.
4. **Trail grass:** it first read as lone blades. The fix was a 0.5 m texel, 40 blades/m², metre-sized clumps and a higher clump coverage.

## Decisions and deviations

- **The far world is not drawn at reveal 0** (`far.visible = reveal > 0`). The brief only requires that the mood fog hide it, so this goes further. The reasons: it is free performance on the whole climb, there can be no early glimpse of the plain from the foot, and in the editor the vista appears once you scrub `reveal`. Because the fog is still nearly full at small reveal, nothing pops.
- **The sky is tinted on reveal** (`horizon_tint` and `zenith_tint` in MoodDirector), beyond pure fog scaling. Without it the fog colour is grey, so the ridges faded grey rather than blue. It is identity at reveal 0.
- **Shared GrassField change:** the hard-coded ray became the `ray_above` and `ray_below` exports. Without it no grass at all is possible above y 40. REUSE.md is updated.
- **Camera far** went from 600 to 5000. Godot 4.3+ uses reverse-Z, so there is no depth-precision cost, and the measured cost is negligible.
- **"Darker and bluer with distance"** was applied to the ridge albedo. On screen the fog lightens the farther rings, which gives the classic receding blue layers.
- **The cloud deck** is a third transparent slab, added for the "stormy sky". It costs about 0 ms.
- **The steppe sits at y +3**, not lower. The terrain's outer ring reaches −0.8 m at most, so the steppe has to be above it to bury the edge. The trail foot (y 0) is protected by the dip, and the test asserts both.
- **Ruling 2** is applied as specified.

## Self-review

- **Mood direction:** the reveal never writes the mood. `current` holds the mood's own values, and closing the reveal restores the fog (tested).
- **Reset:** `reset_scene()` sets the vista closed before `mood.apply`, so a reset at the summit snaps the fog closed at once.
- **Kit:** every ovoo kit piece has `height_from_origin` on (tested).
- **Overlap and walkability:** no field overlaps another (assignment by progress plus the summit-rect exclusion). Grass never grows on gravel (tested per field), on cliffs (slope filter, and the summit's 8 m ray span) or on boulders (they aren't on layer 2).
- **Hygiene:** all new and edited files are LF, and player.gd was not touched. No subagents were used and git was not run.
- **Editor behaviour:** Vista is `@tool` and rebuilds when its exports change. Its generated nodes are internal, so the scene file stays small.

## Concerns

1. **The summit plateau view itself:** at the follow camera's height, the plateau's grassy horizon hides the mist sea directly ahead. What you see is ovoos against the sky and ridges, with only a band of mist. The full ocean of mist reads from the pull-back camera and when facing sideways or back. Task 7's pull-back should rise high enough, roughly ≥ 40 m above her, to show it.
2. **The massif from the air:** it reads as a steep mesa or pillar rising from the mist, because of Task 2's 60° cliffs. That is acceptable and its square edge is gone, but it is a strong vertical shape.
3. **The golden steppe through the mist** reads somewhat ochre-brown. Fog desaturates it, and it is only glimpsed in gaps.
4. **Trail tufts are deliberately sparse.** They read as scattered blades and small tufts rather than lush clumps. The 0.9 stretch is still dim (Task 3's lighting), and the edge tufts help only modestly.
5. **SummitSequence (Task 7)** should tween `vista.reveal` from 0 to 1 over several seconds. With `pow(0.08, reveal)` the opening is even over time.
