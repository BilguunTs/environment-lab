# Terrain replica

A tool that builds a 1:1 walkable Godot replica of a real place from public data: Copernicus
GLO-30 elevation and Esri World Imagery. Every size and position comes from the data or from a rule
written in a rules file. Nothing is sized by eye.

- **Python pipeline:** `tools/terrain/replica`. It downloads the data, classifies the surface,
  traces rocks, builds the heightmaps and does the rule fill. Everything it writes goes to
  `data/sites/<site>/build/`.
- **Godot loader:** `scripts/replica/`. `ReplicaSite` builds the ground, rocks, scatter, gers,
  grass and sun from `build/`. Scenes are in `scenes/replica/`.
- **First site:** `data/sites/sumber`, a 2 × 2 km granite valley in Sümber, Govisümber, Mongolia
  (46.252564 N, 108.779433 E). The scene is `scenes/replica/sumber.tscn`.

The plan, spec and rulings are in `docs/superpowers/plans/2026-11-11-terrain-replica.md` and
`docs/superpowers/specs/2026-11-11-terrain-replica-design.md`.

## Frame and outputs

The local frame has 1 Godot unit = 1 m, +x east and +z south (north is −z). The origin is the
site's lat/lon. In Godot, y = elevation − `base_elevation`.

The core is a 2 × 2 km square at a 1 m step. Grid sample (i, j) sits at x = −1000 + j,
z = −1000 + i, with row 0 at north. The ring is a 20 × 20 km square of DEM only, at a 30 m step.

`build/manifest.json` is the contract between Python and Godot. It documents every file below.

| File | What it is | Committed |
|---|---|---|
| `manifest.json` | Grid layout, base elevation, sun, structures, drift-guard stats | no (rebuilt) |
| `core.r32`, `ring.r32`, `mass_tops.r32` | Raw float32 heightmaps | no (rebuilt) |
| `classes_full.png` | Surface class ids at 0.5 m (Python's map) | yes |
| `classes.png` | Surface class ids at 1 m (Godot's map) | yes |
| `rocks_detected.json` | Traced rocks | yes |
| `rocks.json` | `merge(rocks_detected, edits)` | yes |
| `rocks_placed.json` | What Godot places | yes |
| `grass_density.png` | Grass density, one pixel per core sample | yes |
| `scatter.json` | Rule-fill instances, columnar | no (> 5 MB, deterministic) |
| `ortho.png`, `*_debug.png` | Imagery and overlays on it | **never** (licence) |
| `topdown.png`, `check.json` | Validation outputs | no (rebuilt) |

The class ids are 0 unknown, 1 rock, 2 sand, 3 grass, 4 scrub, 5 channel, 6 track and
7 structure.

## The licence rule

Esri World Imagery tiles, and anything that contains their pixels, are **local only**. They are
never committed, never shipped and never used as a game texture. That covers `cache/`,
`build/ortho.png`, every `build/*_debug.png` and any screenshot of the ortho.

Only data derived from the imagery is kept: the class map, the rock list, the edits and the grass
density. `.gitignore` enforces this for the standard names. Before you commit a new kind of
picture, ask whether it has imagery pixels in it. If it does, give it a `*_debug.png` name.

The Godot ground is flat-coloured per class (`ReplicaTerrain.PALETTE`). Rocks and fill pieces use
`assets/materials/granite.tres`. No photo texture reaches the game.

## Adding a site

1. Create `data/sites/<site>/site.json`:

   ```json
   {
     "name": "<site>",
     "lat": 46.252564, "lon": 108.779433,
     "core_m": 2000, "core_step_m": 1.0,
     "ring_m": 20000, "ring_step_m": 30.0,
     "ortho_m_per_px": 0.5, "imagery_zoom": 17,
     "rules": "steppe_granite",
     "sun": {"azimuth_deg": 159.0, "elevation_deg": 28.5},
     "sun_source": "where the sun numbers come from",
     "calibration": [],
     "structures": []
   }
   ```

   The fields:

   - `lat`, `lon`: the centre of the core, in WGS84 decimal degrees. It becomes the origin.
   - `core_m`, `core_step_m`: the core square (2000 m) and its heightmap step (1 m).
   - `ring_m`, `ring_step_m`: the DEM-only ring square (20 km) and its step (30 m). The fetch
     downloads every 1° DEM tile the ring touches, so a ring may cross tile edges.
   - `ortho_m_per_px`, `imagery_zoom`: the ortho resampling (0.5 m/px) and the Esri zoom. Zoom 17
     is about 0.83 m/px at 46° N; z18 and above return a placeholder in rural Mongolia.
   - `rules`: a file in `tools/terrain/rules/` holding the rule-fill parameters for the landscape
     family, such as `steppe_granite`.
   - `sun`: azimuth (clockwise from north, the direction the sun is *in*) and elevation, in
     degrees, at the time the imagery was taken. Rock heights are read from shadow lengths, so this
     matters. Use `null` to measure the sun from `calibration`. A manual `sun` always wins.
   - `sun_source`: free text recording where the sun came from, such as imagery metadata (sensor,
     date, local solar time) or "placeholder".
   - `calibration`: a list of objects of known height with a measured shadow tip, in local
     metres: `{"x", "z", "height_m", "shadow_tip_x", "shadow_tip_z"}`. Use it when there is no
     metadata. It may be `[]` when `sun` is set. It is kept for the record even when `sun` wins.
     A ger's far shadow tip comes from the wall top, not the crown, so ger calibration
     under-reads the elevation (see `replica/sun.py`).
   - `structures`: measured man-made objects. Today that means
     `{"type": "ger", "x", "z", "diameter_m"}`, measured on the ortho. Godot places `ger.glb`
     scaled to the diameter, and the player spawns 15 m south of the first one. With
     `structures: []` the player spawns at the origin.

2. Fetch and build. The build stops with exit code 1 if the drift guard fails, after writing its
   outputs for inspection.
3. Optional: fix rocks with the correction tool, fix classes in `edits/classes_override.png`,
   then build again.
4. Make a scene. Copy `scenes/replica/sumber.tscn` and set the root's `site_dir`, or inherit it
   the way `scenes/replica/smoke.tscn` does. No code changes are needed.
5. Validate with the top-down capture and `check` (below).

## Commands

Run these from the repo root. `PY` is the venv Python. The `-I` flag is required: the cache is
untrusted input.

```sh
PY=tools/terrain/.venv/Scripts/python.exe
GODOT=/d/softwares/Godot_v4.6-stable_mono_win64/Godot_v4.6-stable_mono_win64_console.exe

$PY -I -m replica fetch data/sites/<site>     # DEM tiles + z17 imagery into cache/ (resumable)
$PY -I -m replica build data/sites/<site>     # cache -> build/ (no downloads; ~1 min)
$PY -m pytest tools/terrain/tests -q          # pipeline tests (@site tests need the sumber cache)

# Godot (windowed for anything that renders)
"$GODOT" --path . res://scenes/replica/sumber.tscn                       # walk it
"$GODOT" --path . res://scenes/replica/sumber.tscn -- --capture-topdown --quit
$PY -I -m replica check data/sites/<site>     # topdown vs class map: IoU + rock offsets
"$GODOT" --path . --resolution 1920x1080 --disable-vsync res://scenes/replica/sumber.tscn -- --walk-perf --quit
"$GODOT" --path . res://scenes/replica/sumber.tscn -- --capture-views --quit
"$GODOT" --path . -s res://tests/run.gd -- --only=replica                # Godot replica tests
```

- `build` runs these steps in order: ortho, classes (with overrides), rock detection and the
  merge with the edits, the class map brought in line with the edits (below), the core and ring
  heightmaps, the agreement and drift checks, rule fill and mass packing, then export.
- **The class map follows the rock edits** (Ruling 27). After the merge, `classes_full.png` (and
  so `classes.png`) is rewritten so that it agrees with the corrected rock list:
  - the ROCK pixels of a deleted rock (its footprint grown by 1 m, minus every kept rock) take
    the most common non-rock class in a 4 m ring around them, region by region;
  - the old place of a rock whose geometry an edit changed is freed the same way;
  - an added rock is painted ROCK (a boulder's ellipse, a mass's outline), and so is a changed
    boulder's new place.

  The numbers are `reclass_margin_m` and `reclass_ring_m` in `rocks.PARAMS`. Without this the
  ground under deleted rocks was still coloured and scattered as rock ground in Godot. The
  hand override (`edits/classes_override.png`) is applied again afterwards, so its pixels win
  here too.
- **Drift guard.** The build compares the replica ground with the native DEM. It also compares
  rock-free ground with the DEM. The numbers go in `manifest.stats`, and the build fails over the
  plan's thresholds.
- `--capture-topdown` writes `build/topdown.png`: the core straight down, orthographic, at
  0.5 m/px (4000²), rendered in 2000 px tiles.
  - It uses a capture-only mode. The ground is drawn unlit by class colour, and every rock and
    fill-piece mesh is drawn in one unlit magenta (255, 0, 255), so the rock mask is exact.
  - Grass, scrub, trees, scree, stones, the gers, the player and the ring are hidden.
- `check` compares two masks: the magenta mask of `topdown.png` and ROCK in
  `classes_full.png`.
  - It reports the IoU two ways (Ruling 29): against every ROCK pixel, and against the ROCK
    pixels of rock-list-size components (footprint ≥ the 2 m detection minimum; smaller specks
    are rule-fill territory). The threshold applies to the second.
  - It reports the share of the mass outlines (`rocks_placed.json`) that the render covers
    (Ruling 28 target: ≥ 85 %).
  - For every traced rock at least 3 m across, it finds the shift (within 8 m) that best lays the
    rock on the rendered mask. It reports the median of those shifts and the mean signed dx/dz, so
    a frame or axis bug shows as a consistent direction.
  - It passes at rock-list-size IoU ≥ 0.7 and a median offset ≤ 2 m.
  - With the local `ortho.png` present, it also writes `check_side_debug.png` (ortho | topdown)
    and `check_overlay_debug.png`. Both are local only.
- `--walk-perf` walks a scripted path at sprint speed (7 m/s): from the spawn to the site centre,
  then to just outside the largest tor's outline, then rising to an aerial view. It prints the
  min, 1 %-low and average fps per leg and for the whole walk, and writes
  `screenshots/replica_perf_<site>_<datetime>.md`.
- `--capture-views` saves `screenshots/replica_<site>_{spawn,tor,aerial}.png`.

## The correction tool

`scenes/replica/rock_editor.tscn` is a 2D editor for the traced rocks, drawn over the local
ortho:

```sh
"$GODOT" --path . res://scenes/replica/rock_editor.tscn -- --site=data/sites/<site>
```

- **Inputs and outputs.** It reads `build/rocks_detected.json` and `edits/rocks_edits.json`, and
  shows their merge. It writes **only** `edits/rocks_edits.json` (added, deleted and changed
  rocks). That file is committed. The next `build` turns it into `rocks.json`.
- **Navigation.** Mouse wheel zooms. Right or middle drag, WASD or the arrow keys pan. **F** fits
  the site in view.
- **Select and delete.** Click to select. **Del** or **X** deletes the selection. **Esc** cancels
  or deselects.
- **Add a rock.** Drag along the long axis, move the mouse for the width, then click. **Esc**
  cancels.
- **Height.**
  - **1**–**9** give *n* m and **Shift+1**–**9** give *n*+0.5 m. **0** gives 10 m.
  - These apply to the selected rock. With nothing selected, they set the height of the next new
    rock.
  - **M**, then drag from the rock's foot to its shadow tip, sets the selected rock's height from
    its shadow.
- **Display and save.** **O** toggles the ortho and **L** the rock outlines. **Ctrl+S** saves, and
  closing the window also saves.

Class fixes go in `edits/classes_override.png`. It is the size of `classes_full.png`, palette or
8-bit grey, with value = class id and 0 = keep. Any non-zero pixel wins over the classifier
and over the class changes that follow the rock edits.

## Validation results

### Sumber (Task 11, after Rulings 27–30)

**`check`: PASS.**

| Measure | First pass | After Rulings 27–28 | Threshold |
|---|---:|---:|---:|
| IoU vs rock-list-size ROCK (Ruling 29, gated) | (0.331) | **0.789** | ≥ 0.7 |
| IoU vs all ROCK | 0.331 | 0.789 | reported |
| Mass outlines covered by the render | 53 % | **91.2 %** | ≥ 85 % (Ruling 28) |
| Median offset, traced rocks ≥ 3 m | 0.00 m | 0.00 m | ≤ 2 m |
| Matched / traced rocks | 2684 / 3593 | 2515 / 2515 | |
| p90 offset | 8.7 m | 7.8 m | |
| Mean dx / dz | +0.04 / +0.06 m | +0.08 / +0.08 m | |
| Best shift at the 8 m search edge | 321 | 151 of 2515 | reported |

- **The p90 sits at the search edge.** 151 of the 2515 traced rocks (6 %) have their best
  shift at the 8 m limit of the search, so their real offset is not measured: it is 8 m or more,
  or the best overlay is a neighbouring rendered rock. That is what puts the p90 at 7.83 m while
  the median is 0. The numbers are `at_search_edge`, `rocks` and `p90_offset_m` in
  `build/check.json`.
- **What changed.**
  - **Ruling 27.** The class map now follows the rock edits. 458,752 ROCK px (11.5 ha) under the
    1228 deleted rocks and the reshaped mass were reclassified. 96,041 px were painted ROCK:
    9 added rocks, of which 3 are hand-drawn masses of 70–150 m. The NW and S deletion areas now
    show scrub and grass ground in Godot instead of grey rock ground. Class ROCK went from
    1.24 M to 0.88 M px.
  - **Ruling 28.** A gap pass packs every mass outline a second time. It uses 0.75–2 m pieces on
    a 0.5 m candidate grid, at overlap 0.5. A gap piece is a single block on the ground. Slabs
    now reach at least 0.1 m above the highest ground under them, so a slope no longer buries
    them.
- **Almost all ROCK lies in rock-list-size components.** Only 922 ROCK px are in specks under
  2 m. That is why the two IoUs agree to three decimals.
- **Cost.**
  - Fill pieces went from 46,282 (fill_round 39,350, fill_slab 6,932) to 310,495
    (fill_round 186,317, fill_slab 124,178), 6.7×.
  - The rule-fill step takes 61 s, and the whole build 109 s.
  - In Godot the site builds in 7.6 s, up from 6.8 s.

**Performance (Ruling 30: judged on the 1 %-low).** Over three runs the walk ran at 1 %-low
74–77 fps, min 36–75 fps and average 107–111 fps. That is a pass, but the average was 252–270
before the gap pass. See `docs/PERFORMANCE.md`.

### Second site: smoke run (Task 11)

- **Location.** `data/sites/smoke`, 46.2266 N 106.0386 E, near Baga Gazriin Chuluu
  (Dundgovi). It is about 3 km east of the 106° E line, so its 20 km ring needs two 1° DEM tiles,
  E105 and E106.
- **Config.** The sun is a manual placeholder (az 160°, el 30°, not measured), and there are no
  gers. The scene is `scenes/replica/smoke.tscn`, an inherited scene with only `site_dir`
  changed. No code was changed for it.
- **Fetch.** 2 DEM tiles and 121 imagery tiles, in 1 min 41 s.
- **Build.** 39 s after the Ruling 28 gap pass.
  - 767 rocks traced, of which 767 placed. There are no edits, so Ruling 27 changes nothing.
  - Scatter: scree 5396, stone 20507, scrub 69154. fill_round went from 1544 to 8386.
  - Drift guard passed: native-DEM rms 0.186 m / max 1.198 m; rock-free rms 0.179 m /
    max 0.959 m.
- **`check`: PASS.**
  - Rock-list-size IoU 0.763 (all ROCK 0.762). It was 0.668 before the gap pass.
  - Mass outlines are 85.2 % covered.
  - Median offset 0.00 m, p90 0.50 m, mean dx/dz +0.14 / −0.09 m.
  - All 769 rocks matched.
  - With 1–2 m gap pieces the coverage was 82.3 %, which is why the gap pieces go down to
    0.75 m.
- **Perf.** 1 %-low 108 fps, min 59 fps (a single frame below 60), average 415 fps.
- **Caveat.** The classes do not transfer to this imagery. See the classifier limit under
  Known limits.

## Known limits

- **The classifier is tuned on one season.** Its thresholds were set on Sumber's autumn
  imagery (WorldView-2, late October: dry, tan ground). The smoke site's Esri imagery is summer
  (green). There the classifier finds only 0.36 % ROCK on terrain that looks like dissected rocky
  hills, while Sumber has 7.75 %. A passing `check` at such a site only shows that the replica
  matches its own class map. It does not show that the class map is right. Check a new season or
  landscape against the imagery, and fix it with thresholds or `classes_override.png`.
- **Mass fill is dense.** To cover its outlines (Ruling 28), Sumber has about 310 k fill
  pieces, 6.7× the first pass. Small gap blocks (0.75–2 m) fill the joints between the stacks.
  This halved the average fps of the walk (1 %-low is still ≥ 74). Only fill pieces over
  1.5 m on some axis collide (plan Task 10, Ruling 34): at Sumber 168,404 of the 310,495. The
  smaller gap blocks sit among collided pieces; where one is not covered by a larger piece,
  the player walks through it.
- **Rock heights are mostly estimated.** Only about 16 % of rock heights are measured from
  shadows. The rest come from the footprint rule (height ≈ width × the median shadow-measured
  ratio). That is about ±0.9 m for boulders and ±2.2 m for masses.
  - Masses at least 60 m long take their top from the DEM, which is a DSM and sees large tor
    fields.
  - Smaller masses use a capped fallback height (9.48 m at Sumber), so tall mid-size tors can read
    low.
- **Rock ids are a hash of the centroid at 0.5 m.** If a re-detected rock's centroid crosses a
  0.5 m boundary, its id changes, and edits keyed to the old id no longer apply. The merge warns
  about this. Re-check edits after changing the classifier or the imagery.
- **Cast shadows are read as scrub.** The dark shadow of a tor on sand or grass is classed SCRUB,
  so rule fill puts shrubs there. Fix it in `classes_override.png`.
- **Tors read as cobble piles.** Masses are packed with rounded and slab pieces stacked to the
  mass top. Up close, a big tor looks like a pile of cobbles rather than jointed sheet granite,
  and narrow masses look like stacked walls.
- **Imagery registration.** Esri imagery and the coordinate you give can disagree by tens of
  metres. At Sumber the gers sit about 160 m NW of the given point, and that offset is in the
  imagery itself. The replica is consistent with the imagery, so re-centre by changing lat/lon.
- **Frame drift in the ring.** The local frame is equirectangular, so it drifts about 0.16 %
  east–west at ±10 km north–south. That is about 16 m at the ring corners and about 0.16 m at
  the core corners. DEM and imagery go through the same frame, so the replica is internally
  consistent, but ring hills can be up to about 16 m off their real map spot.
- **The 20 m apron is filler, not DEM.** The core is extended to ±1020 m, the first ring grid
  line, by blending from the core edge to the ring. That band is derived ground with no DEM sample
  of its own. Where core and ring disagree, its slope can reach about 0.5.
- **1 m class edges stair-step up close.** Classes are 1 m pixels in Godot.
- **Grass blade height and colour are reference values,** not measurements: a photo at 0.8 m/px
  cannot see blades.
