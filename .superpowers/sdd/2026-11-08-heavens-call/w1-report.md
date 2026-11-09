# W1 report: Heavens call far world (Khangai hills, Altai peaks, steppe, massif)

Status: done. The far world now reads as layered, rounded, grassy Khangai hills with valley mist, a sparse veiled band of snowy Altai peaks on the horizon, golden steppe in the valleys, and a massif whose flanks run out into the land. One suite failure remains, and it was already there before this work (see "Suite results").

## What changed, per file

- `scripts/levels/vista.gd`: rewritten far world. The `Vista` interface is unchanged: `reveal`, `far`, `far_fade()`, `fog_scale()`, `mist_scale()`, `horizon_tint()`, `zenith_tint()`, `horizon_distance()`, `steppe_height_at()`, `ring_radii`, `Ovoos` and the cloud deck.
  - The needle rings are gone. There is now one faceted polar ground heightfield (`Steppe`), made of the steppe floor, three hill layers and the massif's flanks.
  - New `Altai` mesh (short snowy ranges) using a new shader.
  - New optional export `terrain: MountainTerrain`, so the ground carries the massif's flanks on past the terrain square.
  - New trail-cone grid (`_build_cone`, `_cone_at`).
  - New ground colouring:
    - straw crests and olive hollows;
    - darker greener north (-Z) faces;
    - broad cloud shadows;
    - flank grass near the massif;
    - a blue-grey tint with distance.
  - `OPEN_FOG` went from 0.08 to 0.07, so you can see a little further at full reveal.
- `scripts/levels/mountain_terrain.gd`:
  - New `envelope_at()`, the old-mountain flank envelope.
  - New exterior raise with trail protection (`_trail_bound`, `_chamfer_min`).
  - Edge sink near the square's border.
  - Grass-to-rock colouring of the raised flanks.
  - The corridor, the cliffs and drops under the corridor, and the trail heights are computed exactly as before. The raise is applied afterwards, and it only ever adds ground.
- `assets/shaders/mist_sea.gdshader`: the soft fade now uses the slab's height above the ground behind it (ray length behind × vertical component), so the mist pools in valleys and thins over rises. The sky (depth 0) still counts as full mist, so the cloud deck is unchanged.
- `assets/shaders/far_peaks.gdshader` (new): faceted vertex-colour peaks with `fog_disabled` and their own haze.
  - The haze tints the peaks toward the horizon colour up to 0.7. Above that they fade out by alpha, so at haze 1 they vanish exactly into what is behind them.
  - A height veil fades their lower slopes, leaving only the snowy tops clear.
- `scenes/levels/heavens_call.tscn`, Vista node only:
  - `ring_radii` changed from 760/1400/2250 to 720/1250/1900;
  - `terrain = NodePath("../MountainTerrain")` added, plus its entry in `node_paths`.

## New layer and peak parameters

Hill layers (`HILLS`, one per `ring_radii` entry: 720 / 1250 / 1900 m):

| Layer | Crest above floor | Half-width (× radius) | Swells round ring | Wander | Valley toward -Z (start, closed, height left) |
|---|---|---|---|---|---|
| 1 (720 m) | 30–110 m | 0.50 | 6 | 0.14 | 0.30, 0.95 rad, 25 % |
| 2 (1250 m) | 55–160 m | 0.44 | 7 | 0.12 | 0.22, 0.75 rad, 40 % |
| 3 (1900 m) | 90–205 m (summit is ~217 m) | 0.40 | 8 | 0.10 | 0.12, 0.50 rad, 62 % |

- Profile: each layer is a raised cosine across the ring, slightly steeper on the near side. Layers combine by max, which leaves V-valleys between them.
- Saddles come from a two-octave crest noise sampled on a circle (k = swells × 0.25).
- `DOMES` (38 m): low rounded domes between 420 and 2800 m.
- `GULLY` (0.24): winding draws carved down the hillsides at noise zero-lines, up to 24 % of the local hill height. They give spurs and draws instead of a dune look.
- The valley toward -Z leads the eye from the summit out to the Altai.
- Colour: near layers golden-tan, blending to `FAR_TINT` (0.44, 0.48, 0.55) by up to 80 % between 500 and 2600 m, on top of the fog's own aerial perspective.

Altai (`ALTAI`):

- 16 slots round the horizon, kept at 85 % in the front view and 35 % behind.
- Radius 3000–3950 m.
- Main summit 260–440 m above the steppe (×0.75 behind).
- Ridge half-length 1.4–2.0 × height.
- Snow line at 0.55 of the height.
- Haze 0.5 at full reveal.
- Veil from 60 to 300 m above the steppe.
- Each range is a 14×7 faceted heightfield laid along the horizon: one main summit plus 2–3 lesser ones, kept clear of the buried border. Snow and rock are coloured per face.
- `ALTAI_FOG_DISTANCE` is 900 m: the haze follows the mood's fog as if the peaks stood 900 m away. They are gone in the climb fog and at reveal_early, and come out last.

## Steppe and mist

- Steppe: `steppe_color` (0.80, 0.64, 0.33) is warm straw-gold, with `STRAW`, `OLIVE` and `SHADE` variation and cloud shadows (`CLOUD_SHADOW` 0.3).
  - Floor roll is now 12 m (was 28), reached between 320 and 1000 m.
  - `steppe_radius` went from 3000 to 4200 m, so the land runs on under the Altai. The mist sea (4500 m) still buries the edge.
  - It is still flat under the massif and still dips under the trail's foot (FOOT_* unchanged).
- Mist layers:
  - heights changed from 30/75 m to 16/42 m above the steppe;
  - open thickness 0.3/0.1 (was 0.2/0.09); closed thickness unchanged;
  - new per-layer `soft` of 14/34 m (height above the ground over which each layer fades in).
  - Result: an opaque sea toward the horizon, a thin veil looking down, thick in the valleys, and the hills and flanks rise clear out of it.

## Massif change, and how the corridor is protected

Envelope (`envelope_at`):

- Formula: `summit_y − 90·(1−e^(−d/70)) − 150·(1−e^(−d/reach))`, where d is the distance from the summit plateau.
- `reach` = 260 m × (1 ± 0.45 spur noise). The spur noise is sampled round the summit and drifts with distance, so the spurs curve.
- Plus a 7 m broad roll.
- It is steep under the summit and reaches the steppe about 350–450 m out.

Raise: `y = lerp(y_orig, max(y_orig, bounded_envelope), w)`. Ground is never lowered except in the last 50 m of the square, where it sinks to 14 m under the envelope for the edge burial. The protection works in three layers:

1. `w = smoothstep(4, 20, distance from the corridor's edge)`, computed as a chamfer distance seeded inside the corridor. Within 4 m of the corridor's edge nothing changes.
2. Below a trail point (a drop beside the path), the raise stays under a cone 18 m below that point, rising 0.55 per metre away.
3. Above a trail point (a wall over the path), the raise stays under a cap 6 m above that point, rising 2.2 per metre.

Steps 2 and 3 are `_trail_bound`: exact per-vertex distances to trail samples every 3 m, blended by the unraised height relative to each trail point. It only runs where the envelope exceeds the chamfer drop cone.

- Raised flanks are coloured `FLANK_GRASS` low down, turning to rock toward the summit and on very steep pitches. The corridor and walls keep their colours.
- Vista continues the same envelope past the square: `ground = max(floor and hills, min(envelope, drop cone) − 4 m)`. It uses its own 4 m chamfer grid of the same drop cone.
- Verified visually: the debris and eerie corridor views are pixel-for-pixel the same composition before and after. The only difference is extra mountain body showing beyond the drop in debris.
- `test_terrain_matches_trail`, the camera-collision test and the trail tests all pass.
- Build cost: terrain rebuild about 1.2 s and vista rebuild about 0.4 s at load (headless timing).

## Test edits

None. All vista tests passed without changes:

- steppe 217 m below the summit;
- three rings at 720/1250/1900 m, inside 600–2500;
- steppe radius 4200 m, at least 3000;
- camera far reaches the 4500 m horizon;
- the terrain edge is buried, with a margin above 1 m;
- the trail stays above the steppe;
- fade-in and reveal behaviour.

## Suite results

- Windowed: 157 passed, 1 failed, 0 skipped.
- Headless: 134 passed, 1 failed, 23 skipped.

The only failure is `test_heavens_basics::test_no_sprint_in_level`. It is not caused by this work:

- `scenes/levels/heavens_call.tscn` sets `sprint_speed = 20.0` on the Player node.
- That line was already there when I started: it is in my start-of-task backup at `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\w1\bak\heavens_call.tscn`, line 126.
- It is absent from the earlier task backups (`scratchpad\heavens_call.tscn.bak`, `scratchpad\t7\heavens_call.tscn.bak`).
- It looks like a playtest edit. I did not revert it. Removing that line should restore 158 / 135+23.

## Profile

1920×1080, RTX 3070, `--profile`, final code (`screenshots/heavens_profile_*`, run 2026-11-08T20-17):

| View | Grass | FPS | CPU ms | GPU ms | Draws | Prims |
|---|---|---:|---:|---:|---:|---:|
| foot | on | 123 | 0.18 | 1.70 | 49 | 587k |
| debris | on | 206 | 0.23 | 1.55 | 184 | 601k |
| eerie | on | 206 | 0.22 | 1.49 | 162 | 602k |
| summit | on | 206 | 0.20 | 1.52 | 95 | 659k |
| wide | on | 409 | 0.21 | 1.74 | 60 | 677k |
| reveal_early | on | 611 | 0.23 | 1.98 | 62 | 751k |

The worst view is still 1.98 ms (reveal_early), against a 7.0 ms budget.

## Before and after captures

Before:

- `D:\DevEnv\GDOT\environment-lab\screenshots\heavens_wide_2026-11-08T18-45-08.png`
  - Zhangjiajie-like grey needles in three rings.
  - A flat white mist sheet with ochre-brown stains.
  - The massif a dark column standing in the sheet.
- `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\w1\before\` contains:
  - `wide`, `reveal_5s`, `summit_r1_y150` (spiky alpine ridges);
  - `aerial_se` (the massif as a lone cone in a white sheet);
  - `foot`.

After, official 1920×1080:

- `D:\DevEnv\GDOT\environment-lab\screenshots\heavens_wide_2026-11-08T20-17-19.png`
  - Golden valley floor with patchy mist pooled low.
  - Layered rounded hills either side, with gullies and cloud shadows, paler and bluer with distance.
  - Three or four short snowy ranges small on the horizon, bases melted into haze.
  - The rocky summit in front, golden flanks at the lower corners.
- `heavens_foot/debris/eerie/summit_2026-11-08T20-17-19.png`: the corridor is unchanged.
  - In foot, a fog-veiled hill flank now shows to the right at distance, instead of empty fog.

After, scratch windowed set in `C:\Users\user\AppData\Local\Temp\claude\d595467b469acd6b\50fe8da1-f185-4552-92de-73eb6f745a9c\scratchpad\w1\r8\`:

- `reveal_early.png`: still all fog; peaks and hills are not shown at reveal 0.15.
- `reveal_5s.png`: hills emerging, peaks faint.
- `summit_r1_y150.png` and `summit_r1_y220.png`: layered Khangai ridges to the horizon, Altai tops in haze.
- `aerial_n.png`: from the pull-back side, one big old mountain whose spurs flow into the hills.
- `aerial_sw.png`: the trail-side terrace is still visible as a ledge, because that is the protected corridor.
- `pull_mid.png`
- `foot_r1.png`: a state the game never reaches.

## Concerns

- From the SW, the protected trail spiral still reads as a terrace around a steeper rocky core. From the gameplay cameras (north and the summit) this barely shows.
- The near hills and flanks are visibly faceted (crumpled-paper triangles) up close. That is in keeping with the low-poly kit, but stronger than the old smooth disc.
- The hill layers' intersections and gully creases can show as sharp vertical facet edges at grazing angles.
