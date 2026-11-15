# Terrain Replica Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reusable tool that turns a coordinate + size into a walkable Godot replica of a real
place — ground shape, surface types, rocks and plants at their true positions and sizes — first
used on a 2 × 2 km valley in Sümber, Govisümber.

**Architecture:** An offline Python pipeline (`tools/terrain/replica/`) fetches public elevation
and imagery, builds a local metric frame, classifies the surface, detects rocks from shadows,
builds a heightmap that respects the elevation data, and rule-fills small detail. It writes plain
files into `data/sites/<site>/build/`. A Godot node (`ReplicaSite`) reads those files and builds
terrain, rocks, plants and gers. A Godot 2D tool corrects the detected rock list by hand.

**Tech Stack:** Python 3.14 + numpy, scipy, tifffile, Pillow, pytest (project-local venv);
Godot 4.6 (pure GDScript); Terrain3D add-on if it supports 4.6, else own chunked mesh; Blender 5.1
for rock shapes (`C:/Program Files/Blender Foundation/Blender 5.1/blender.exe -b -P ...`).

**Spec:** `docs/superpowers/specs/2026-11-11-terrain-replica-design.md`. Read it first; the
anti-goals (wrong sizes, random scatter, rules overriding imagery, one-off code) decide open calls.

This plan makes these calls inside the spec's "builder's call" space:
- **Frame:** local tangent plane at the site centre. Godot `+X` = east, `-Z` = north, `+Y` = up,
  metres. `y = elevation − base_elevation`; `base_elevation` = floor of the core's minimum DEM
  height, stored in the manifest.
- **Projection:** own WGS84 local-plane maths (meridian / prime-vertical radii at the centre), no
  pyproj/GDAL — error is far below 1 m within 10 km and avoids native wheels on Python 3.14.
- **Heightmaps to Godot:** raw little-endian float32 `.r32` + `manifest.json` (Godot's PNG loader
  drops 16-bit precision).
- **Surface map / rock list:** automatic classification + shadow-based detection, then a hand
  correction pass in a Godot 2D tool. Hand edits live in their own file and survive re-runs.
- **Rock shapes:** every granite GLB is normalised to a 1 × 1 m footprint and 1 m height with its
  base at the origin, so `scale = (length, height, width)` gives the measured size exactly.

## Global Constraints

- Scale 1:1: 1 Godot unit = 1 m. No size is ever chosen by eye; every size comes from DEM,
  imagery measurement, or a rule written in a rules file.
- Core: **2000 × 2000 m** centred on 46°15'09.23"N 108°46'45.96"E (46.252564, 108.779433).
- Core heightmap step **1.0 m** (2001 × 2001 samples). Ring: DEM-only, **20 × 20 km** square
  (out to ~10 km) at **30 m** step, no rocks, coarse surface colour.
- Elevation: Copernicus GLO-30 COG from
  `https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N{lat:02d}_00_E{lon:03d}_00_DEM/Copernicus_DSM_COG_10_N{lat:02d}_00_E{lon:03d}_00_DEM.tif`
  (verified 200 OK for N46 E108); SRTM via opentopodata only as fallback.
- Imagery: Esri World Imagery `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}`,
  **zoom 17** (~0.83 m/px here; z18+ returns a ~2.5 KB placeholder). Ortho resampled to **0.5 m/px**.
- **Licence rule:** imagery tiles and the ortho image are local-only — never committed, never
  shipped, never used as a game texture. Only derived data (surface map, rock list, edits) is kept.
- Downloads go to `data/sites/<site>/cache/` (gitignored, untrusted input). Python that reads it
  runs as `python -I -m replica ...` from the venv.
- Visual style: the project's existing low-poly flat-colour look (`assets/materials/flat_color.gdshader`,
  `scripts/environment/kit_asset.gd`). No photo textures.
- Performance: ≥ 60 fps at 1920 × 1080 on the RTX 3070 walking the core (measure with the repo's
  `--disable-vsync --print-fps` per `docs/PERFORMANCE.md`).
- DEM agreement: for every 30 × 30 m block in the core, |mean(terrain + rock tops) − DEM| — RMS
  ≤ **2.0 m**, max ≤ **6.0 m**.
- Godot code style: tabs, `##` doc comments, typed vars. Existing tests must stay green
  (`-s res://tests/run.gd`, windowed and `--headless`).
- Git: work on branch `terrain-replica` (not `master`). Commit at the end of each task.

## Review Focus

1. **Axis flips** — north/south or east/west mirrored anywhere between lat/lon, imagery pixels and
   Godot. Expected: the NW peak (~1,650 m) is at −X, −Z; gers at the origin. Test in Task 1 and Task 10.
2. **Placeholder / no-data input** — Esri placeholder tiles and DEM no-data (−32767 / NaN) must
   fail loudly with the tile named, never silently become black ground or a 0 m pit. Test in Task 2.
3. **Re-running the build** — re-detecting rocks must not wipe hand edits; deleted rocks stay
   deleted, added rocks stay. Test in Task 5.
4. **Rocks on slopes** — a rock's base must sit at or below the lowest ground under its footprint
   (no floating edge), and its top at measured height above the ground at its centre. Test in Task 7.
5. **A site that crosses a DEM 1° tile edge or has no gers** — mosaic multiple DEM tiles; sun comes
   from manual `sun` in `site.json`. Tests in Task 2 and Task 4; smoke run in Task 11.

---

## File structure

```
tools/terrain/
  requirements.txt          numpy, scipy, tifffile, Pillow, pytest (pinned versions that install)
  replica/
    __init__.py
    __main__.py             CLI: fetch | build | check
    site.py                 SiteConfig (reads data/sites/<s>/site.json)
    geo.py                  LocalFrame, web-mercator tile maths
    fetch.py                DEM + imagery download & cache
    rasters.py              DEM resampling, ortho mosaic in local frame
    sun.py                  sun direction from calibration objects or manual
    classify.py             surface class map
    rocks.py                rock detection, rock list I/O, edits merge
    heightmap.py            core + ring heightmaps, DEM agreement check
    scatter.py              rule fill (scree, stones, grass, scrub, trees)
    export.py               manifest + .r32 + PNG/JSON writers
  rules/steppe_granite.json rule-fill parameters for this landscape family
  tests/                    pytest, one file per module
data/sites/sumber/
  site.json                 committed
  edits/rocks_edits.json    committed (hand corrections)
  edits/classes_override.png committed (hand-painted class fixes; may be empty)
  build/                    classes.png, rocks.json, scatter.json committed; *.r32, manifest.json gitignored
  cache/                    gitignored
assets/meshes/rocks_granite/ granite GLBs (Task 6) + assets/blender/build_granite.py
scripts/replica/
  replica_site.gd           ReplicaSite: loads build/, builds everything
  replica_terrain.gd        terrain (Terrain3D or chunked mesh) behind one interface
  rock_editor.gd            2D correction tool
scenes/replica/sumber.tscn, scenes/replica/rock_editor.tscn
tests/test_replica_*.gd
```

---

### Task 1: Python scaffold, site config, local frame

**Files:**
- Create: `tools/terrain/requirements.txt`, `tools/terrain/replica/{__init__,__main__,site,geo}.py`,
  `tools/terrain/tests/test_geo.py`, `tools/terrain/tests/test_site.py`, `data/sites/sumber/site.json`
- Modify: `.gitignore` (add `tools/terrain/.venv/`, `data/sites/*/cache/`, `data/sites/*/build/*.r32`,
  `data/sites/*/build/manifest.json`, `data/sites/*/build/ortho*.png`)

**Interfaces:**
- Produces:
  - `SiteConfig.load(site_dir: Path) -> SiteConfig` with fields `name: str, lat: float, lon: float,
    core_m: float, core_step_m: float, ring_m: float, ring_step_m: float, ortho_m_per_px: float,
    imagery_zoom: int, rules: str, sun: dict | None, calibration: list[dict]`, and
    `site_dir, cache_dir, build_dir, edits_dir: Path`.
  - `LocalFrame(lat0: float, lon0: float)`: `to_local(lat, lon) -> (x_east, z_south)` (numpy-broadcast),
    `to_latlon(x, z) -> (lat, lon)`.
  - `tile_xy(lat, lon, zoom) -> (float, float)`, `tile_bounds(tx, ty, zoom) -> (lat_n, lon_w, lat_s, lon_e)`.

- [ ] **Step 1:** Create branch `terrain-replica`. Create venv `tools/terrain/.venv`, install
  requirements; pin the versions that install on Python 3.14. Expected: `pytest --version` works.
- [ ] **Step 2: Write failing tests** (`test_geo.py`):

```python
F = LocalFrame(46.252564, 108.779433)
def test_origin(): assert np.allclose(F.to_local(46.252564, 108.779433), (0, 0), atol=1e-6)
def test_north_is_negative_z():
    x, z = F.to_local(46.252564 + 0.01, 108.779433); assert abs(x) < 0.01 and -1113 < z < -1110
def test_east_is_positive_x():
    x, z = F.to_local(46.252564, 108.779433 + 0.01); assert 769 < x < 772 and abs(z) < 0.5
def test_roundtrip_10km():
    lat, lon = F.to_latlon(7000.0, -7000.0); x, z = F.to_local(lat, lon)
    assert abs(x - 7000) < 0.05 and abs(z + 7000) < 0.05
def test_tile_xy_matches_recon():  # recon: z17 tile x=105141, y=46497
    tx, ty = tile_xy(46.252564, 108.779433, 17)
    assert int(tx) == 105141 and int(ty) == 46497
```
  `test_site.py`: loading `data/sites/sumber/site.json` yields `core_m == 2000`, `core_step_m == 1.0`,
  `ring_m == 20000`, `imagery_zoom == 17`, `ortho_m_per_px == 0.5`; a missing required key raises
  `ValueError` naming the key.
- [ ] **Step 3:** Run `pytest tools/terrain/tests -q` → FAIL (import errors).
- [ ] **Step 4:** Implement. `site.json` for sumber: the values above, `rules: "steppe_granite"`,
  `sun: null`, `calibration: []` (filled in Task 4).
- [ ] **Step 5:** `pytest tools/terrain/tests -q` → all pass. Commit.

### Task 2: Fetch DEM and imagery

**Files:** Create `replica/fetch.py`, `tests/test_fetch.py`. Modify `__main__.py` (`fetch <site_dir>`).

**Interfaces:**
- Consumes: `SiteConfig`, `LocalFrame`, `tile_xy`, `tile_bounds`.
- Produces:
  - `dem_tile_names(lat_min, lat_max, lon_min, lon_max) -> list[str]` (every 1° tile touched).
  - `fetch_dem(cfg) -> list[Path]` (cached GeoTIFFs covering the ring).
  - `fetch_imagery(cfg) -> list[tuple[int, int, Path]]` (z17 tiles covering the core + 50 m margin).
  - `is_placeholder(jpeg_bytes: bytes) -> bool`; `FetchError(Exception)`.

- [ ] **Step 1: Failing tests:**
  - `test_dem_tiles_single`: Sümber ring extent → `["Copernicus_DSM_COG_10_N46_00_E108_00_DEM"]`.
  - `test_dem_tiles_crossing`: lat 45.95–46.05, lon 108.95–109.05 → 4 names (N45/N46 × E108/E109).
  - `test_placeholder_detected`: a 2521-byte fixture saved from the z18 placeholder (fetch once in the
    step, commit it under `tests/fixtures/`) → `True`; a real z17 tile fixture → `False`.
  - `test_imagery_placeholder_raises`: with a fake downloader returning the placeholder, `fetch_imagery`
    raises `FetchError` whose message names the tile `z/y/x`.
  - Downloads go through an injectable `downloader(url) -> bytes` so tests never hit the network.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement. Skip downloads already in cache. Detect placeholders by size < 4 KB
  **and** near-uniform pixels (check both). Send a generic User-Agent (`terrain-replica`), nothing
  identifying the user.
- [ ] **Step 4:** Run tests → pass. Run `python -I -m replica fetch data/sites/sumber` → DEM tile(s)
  and ~ 9 × 9 z17 tiles in cache, no errors. Commit (cache is gitignored).

### Task 3: Rasters in the local frame (DEM grid + ortho)

**Files:** Create `replica/rasters.py`, `tests/test_rasters.py`.

**Interfaces:**
- Produces:
  - `read_dem(paths: list[Path]) -> DemMosaic` with `.sample(lat, lon) -> ndarray` (bilinear; raises
    `ValueError` if any sample hits no-data −32767/NaN, naming lat/lon).
  - `dem_grid(cfg, frame, half_extent_m: float, step_m: float) -> ndarray[float32]` shape (n, n),
    row 0 = north (−Z), col 0 = west (−X).
  - `build_ortho(cfg, frame, tiles) -> ndarray[uint8]` (H, W, 3) at `cfg.ortho_m_per_px` over the core,
    same row/col orientation. Written to `build/ortho.png` (gitignored).

- [ ] **Step 1: Failing tests:**
  - `test_dem_grid_matches_recon`: on the real cached DEM, `dem_grid(..., 3000, 30)` has min in
    1370–1395 and max in 1630–1670 (recon: 1,379–1,654 m, SRTM); the max lies in the NW quadrant
    (row < n/2, col < n/2).
  - `test_nodata_raises`: a synthetic DEM with a −32767 cell raises `ValueError`.
  - `test_ortho_orientation`: synthetic 2 × 2 tiles coloured R/G/B/W by position → ortho NW corner red,
    SE corner white.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (tifffile for COG; GeoTIFF tags give origin/step).
- [ ] **Step 4:** Tests pass. Build the real ortho; open `build/ortho.png` and confirm the two gers
  are at the image centre. Commit.

### Task 4: Sun direction and surface classification

**Files:** Create `replica/sun.py`, `replica/classify.py`, tests for both;
`data/sites/sumber/edits/classes_override.png`. Modify `site.json` (calibration entries).

**Interfaces:**
- Produces:
  - `sun_from_site(cfg) -> Sun` with `azimuth_deg` (clockwise from north, direction the sun is *in*)
    and `elevation_deg`. Manual `cfg.sun` wins; else from `cfg.calibration` items
    `{"x":..,"z":..,"height_m":..,"shadow_tip_x":..,"shadow_tip_z":..}` (averaged); else `ValueError`
    "no sun: add calibration objects or a manual sun".
  - Class ids (module constants, also written to the manifest): `UNKNOWN=0, ROCK=1, SAND=2, GRASS=3,
    SCRUB=4, CHANNEL=5, TRACK=6, STRUCTURE=7`.
  - `classify(ortho, cfg) -> ndarray[uint8]` at ortho resolution; `apply_overrides(classes, png_path)`
    where any non-zero override pixel (palette index = class id) replaces the class.

- [ ] **Step 1: Failing tests:**
  - `test_sun_manual_wins`, `test_sun_from_calibration` (object height 2.4 m, shadow 4.0 m due north
    of it → elevation ≈ 30.96°, azimuth 180°), `test_no_sun_raises`.
  - `test_classify_synthetic`: a synthetic image with a grey textured blob, flat tan area, darker
    green-brown patches → ROCK / SAND / SCRUB in the right regions (≥ 90 % per region).
  - `test_override_replaces`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. Classification uses colour + local texture
  (std-dev in a 5 px window) + shadow adjacency (shadows sit on the anti-sun side of rock); thin
  dark linear features in sand → CHANNEL; long thin light lines → TRACK. Gers: mark manually as
  STRUCTURE in the override PNG.
- [ ] **Step 4:** Measure the gers in `ortho.png`: centre, and shadow tip of each crown; add both
  as calibration items with `height_m: 2.4`, and add each ger to `site.json` as
  `structures: [{"type": "ger", "x": .., "z": .., "diameter_m": ..}]` (measured). Ger footprint diameter measured from ortho should be
  5.5–7 m (sanity check on scale; if not, stop and report).
- [ ] **Step 5:** Run classification on the real ortho; write `build/classes.png` and a debug overlay
  `build/classes_debug.png` (gitignored, contains imagery). Inspect: hilltops ROCK, valley SAND,
  channels visible. Paint obvious misses into the override PNG. Commit.

### Task 5: Rock detection, rock list, edits merge

**Files:** Create `replica/rocks.py`, `tests/test_rocks.py`.

**Interfaces:**
- Consumes: `Sun`, class map, ortho, `frame`.
- Produces:
  - `Rock` dataclass: `id: str` (stable hash of rounded x, z), `x, z: float` (centre, m),
    `length, width: float` (m, length ≥ width), `yaw_deg: float` (long axis, clockwise from north),
    `height: float` (m), `kind: "boulder" | "mass"`, `outline: list[[x, z]] | None` (masses only),
    `source: "detected" | "edit"`.
  - `detect_rocks(ortho, classes, sun, cfg) -> list[Rock]` (min footprint 2.0 m).
  - `load_edits(path) -> Edits` with `added: list[Rock]`, `deleted: set[str]`, `changed: dict[str, dict]`.
  - `merge(detected, edits) -> list[Rock]`; `write_rocks(path, rocks)` / `read_rocks(path)` (JSON).
- [ ] **Step 1: Failing tests:**
  - `test_height_from_shadow`: synthetic bright 4 × 3 m blob with a 2.0 m shadow on the anti-sun side,
    sun elevation 45° → one Rock, length 4 ± 0.6, width 3 ± 0.6, height 2.0 ± 0.5.
  - `test_small_blob_ignored`: 1 × 1 m blob → no rock.
  - `test_merged_shadows_make_mass`: three touching blobs → one `mass` with an outline.
  - `test_edits_survive_redetect` (Review Focus 3): detect → delete one id, add one rock, change one
    height → merge → detect again → merge → same three edits applied, deleted id absent.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement with `scipy.ndimage.label` on ROCK pixels;
  oriented footprint from second moments; height = shadow length along the sun azimuth × tan(elevation),
  clamped to [0.3, 40] m; touching components whose shadows merge → `mass`.
- [ ] **Step 4:** Tests pass. Run on the real site → `build/rocks.json`. Report count by kind and
  size histogram. Commit.

### Task 6: Rock correction tool (Godot 2D) + correction pass

**Files:** Create `scripts/replica/rock_editor.gd`, `scenes/replica/rock_editor.tscn`,
`tests/test_replica_rock_editor.gd`.

**Interfaces:**
- Consumes: `build/ortho.png`, `build/rocks.json`, `edits/rocks_edits.json` (format = `Edits` JSON).
- Produces: the tool writes `edits/rocks_edits.json` only (never `rocks.json`).

- [ ] **Step 1: Failing test** (`const SCENE := "res://scenes/replica/rock_editor.tscn"`, with a
  fixture site under `tests/fixtures/replica_site/`): `test_delete_writes_edit` — call
  `editor.select_at(Vector2(x, z))`, `editor.delete_selected()`, `editor.save()` → edits file has
  that id in `deleted`; `test_add_writes_edit` — `editor.add_rock(Vector2, length, width, yaw, height)`
  → in `added` with `source == "edit"`; `test_never_touches_rocks_json` (mtime unchanged).
- [ ] **Step 2:** Run `--only=replica_rock_editor` → FAIL. **Step 3:** Implement: ortho as background,
  rock outlines coloured by kind, pan/zoom, click select, Del delete, drag to add (length/width/yaw
  from drag), number keys set height. Site path from `-- --site=data/sites/sumber`.
- [ ] **Step 4:** Tests pass. **Correction pass:** go over the whole core in the tool; fix missed and
  false rocks ≥ 2 m. Then ask the user to spot-check the 200 × 200 m patch around the gers (the
  task stops here until they reply). Rebuild `rocks.json` with edits merged. Commit.

### Task 7: Heightmaps (core + ring) and DEM agreement

**Files:** Create `replica/heightmap.py`, `replica/export.py`, `tests/test_heightmap.py`.
Modify `__main__.py` (`build <site_dir>` runs Tasks 3–5, 7, 8 steps in order).

**Interfaces:**
- Consumes: `dem_grid`, class map, `list[Rock]`.
- Produces:
  - `core_heightmap(dem30, classes, rocks, cfg) -> ndarray[float32]` (2001 × 2001, metres, absolute).
  - `rock_base_y(rock, hm, cfg) -> float` = min ground under the footprint; `rock_top_y` = ground at
    centre + height.
  - `dem_agreement(hm, rocks, dem30, cfg) -> (rms: float, max_abs: float)` over 30 m blocks of
    `max(ground, rock top inside footprint)` vs DEM.
  - `ring_heightmap(cfg, frame) -> ndarray[float32]` (20 km at 30 m).
  - `export_site(cfg, core, ring, classes, rocks, scatter) -> None` writing `build/core.r32`,
    `build/ring.r32`, `build/classes.png` (class map downsampled to 1 m), `build/rocks.json`,
    `build/scatter.json`, `build/manifest.json` = `{base_elevation, core: {size_m, step_m, n},
    ring: {size_m, step_m, n}, classes: {...ids}, sun: {...}, structures: [...from site.json], lat, lon}`.
- [ ] **Step 1: Failing tests:**
  - `test_flat_dem_flat_sand`: flat DEM, all SAND → heightmap flat at DEM height ± 0.05.
  - `test_mass_lowers_ground`: flat DEM 1400 with a 20 m mass → ground under the mass lowered so that
    ground + rock top ≈ 1400 at block scale; `dem_agreement` rms ≤ 2.0.
  - `test_channel_cut`: CHANNEL strip in SAND → ground there 0.3–1.5 m below neighbours.
  - `test_rock_on_slope` (Review Focus 4): 30° slope, 3 m rock → `rock_base_y` ≤ min ground in footprint.
  - `test_real_site_agreement`: on the real build, rms ≤ 2.0 and max ≤ 6.0.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement: bicubic upsample of the 30 m DEM; DSM correction
  under masses (subtract rock-top contribution, then re-check agreement); channel cut depth from width
  (≈ 0.3 × width, clamp 0.3–1.5 m); smooth SAND by a 5 m blur; small rise (≤ 1 m) at ROCK edges. Never
  shift the 30 m-block mean beyond tolerance — re-level per block at the end.
- [ ] **Step 4:** Tests pass; `python -I -m replica build data/sites/sumber` prints rms/max. Commit.

### Task 8: Rule fill (scree, stones, grass, scrub, trees)

**Files:** Create `replica/scatter.py`, `tools/terrain/rules/steppe_granite.json`, `tests/test_scatter.py`.

**Interfaces:**
- Produces: `rule_fill(classes, hm, rocks, rules: dict, seed: int) -> list[Instance]` with
  `Instance{type: str, x, z: float, yaw_deg: float, size: [l, h, w]}`; types `scree`, `stone`,
  `grass`, `scrub`, `tree` (rules may give zero density). Also `fill_mass(rock, hm, rules) -> list[Instance]`
  that packs boulders inside a mass outline up to its measured height.
- Rules JSON keys: per type `density_per_100m2` by class, `size_m` [min, max] per axis, plus
  `scree_band_m` (distance below rock edges), `downslope_bias`, `cluster_radius_m`, `near_rock_boost`,
  `channel_boost`. Starting values tuned against the imagery in Step 4.
- [ ] **Step 1: Failing tests:** `test_no_scatter_rock_on_sand_far_from_rock` (open sand > 30 m
  from rock: no `scree`/`stone`); `test_scree_downslope` (scree centroid lies downhill of its rock);
  `test_grass_denser_at_rock_feet_and_channels` (density ratio ≥ 2 vs open sand);
  `test_deterministic` (same seed → same list); `test_mass_fill_height` (packed boulders' top within
  10 % of the mass height, all inside the outline); `test_no_instance_overlaps_traced_rock`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Tests pass; tune densities by
  comparing a 200 m patch of `build/scatter.json` plotted over the ortho (debug PNG, gitignored).
  Commit.

### Task 9: Granite rock shape set (Blender)

**Files:** Create `assets/blender/build_granite.py`, `assets/meshes/rocks_granite/*.glb`,
`tests/test_replica_rock_shapes.gd`.

**Interfaces:**
- Produces GLBs: `granite_round_a/b/c`, `granite_slab_a/b`, `granite_split_a`, `granite_scree_a/b/c`,
  each with footprint exactly 1 × 1 m (X × Z) and height 1 m, base at y = 0, centred on X/Z, flat
  vertex colour in the kit's palette, `flat_color.gdshader` compatible. Plus `ger.glb`: 6.0 m diameter,
  1.6 m wall, 2.4 m crown, white felt.
- [ ] **Step 1: Failing test:** load each GLB, compute its AABB → size (1, 1, 1) ± 0.01, min y = 0 ± 0.01;
  `ger.glb` AABB ≈ (6.0, 2.4, 6.0).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Write the Blender script (rounded granite = displaced
  subdivided cube with exfoliation slabs; slab = flattened; split = boolean cut; scree = small
  angular). Run it headless with Blender 5.1. **Step 4:** Test passes; capture a look at them in the
  playground next to `rock_boulder_a`. Commit.

### Task 10: Godot site builder (terrain, rocks, plants, gers, ring)

**Files:** Create `scripts/replica/replica_site.gd`, `scripts/replica/replica_terrain.gd`,
`scenes/replica/sumber.tscn`, `tests/test_replica_site.gd`. Possibly `addons/terrain_3d/`.

**Interfaces:**
- Consumes: `build/manifest.json`, `core.r32`, `ring.r32`, `classes.png`, `rocks.json`, `scatter.json`;
  GLBs from Task 9.
- Produces:
  - `ReplicaSite` (`class_name`, `extends Node3D`): `@export var site_dir: String`; `build() -> void`;
    `ground_y(x: float, z: float) -> float`; `rock_count() -> int`; `rock_node(id: String) -> Node3D`;
    signals none. Builds on `_ready` if not built.
  - `ReplicaTerrain`: `setup(core: PackedFloat32Array, n: int, step: float, ring: ..., classes: Image,
    base: float) -> void`; `height_at(x, z) -> float`. Colours per class from a palette constant.
- [ ] **Step 1:** Check Terrain3D's latest release supports Godot 4.6 (release notes). If yes, install
  it into `addons/terrain_3d/` and `ReplicaTerrain` wraps it; if no, `ReplicaTerrain` builds 64 m
  chunked `ArrayMesh` tiles with 2 LODs + `HeightMapShape3D` collision. Record which in the task report.
- [ ] **Step 2: Failing tests** (`const SCENE := "res://scenes/replica/sumber.tscn"`):
  - `test_heights_match_manifest`: `ground_y` at 20 random core samples equals the `core.r32` value
    − base ± 0.05.
  - `test_nw_peak_position` (Review Focus 1): the highest core sample lies at x < 0, z < 0.
  - `test_rock_sizes_exact`: for 20 random rocks, the node's world AABB size ≈ (length, height, width)
    rotated by yaw, ± 2 %.
  - `test_rock_base_not_floating` (Review Focus 4): each sampled rock's lowest point ≤ `ground_y` at
    its four footprint corners + 0.05.
  - `test_gers_at_measured_positions`: one ger node per manifest `structures` entry, within 0.5 m of
    its measured x/z, footprint = its measured `diameter_m` ± 0.1. (Ruling 10: the gers are ~160 m NW
    of the site centre; the centre stays the user's coordinate.)
  - `test_ring_present`: `ground_y(8000, 0)` returns a value (no hard edge).
  - `test_player_spawns_on_ground` near the gers.
- [ ] **Step 3:** Run → FAIL. **Step 4:** Implement. Large rocks (> 1.5 m any axis) get individual
  nodes with convex collision; scree/stones/grass/scrub use `MultiMeshInstance3D` per type in 128 m
  cells with visibility ranges. Grass reuses the existing grass shader/wind from `docs/REUSE.md`.
  Player + follow camera from the playground setup; spawn 15 m south of the first ger (not the origin).
- [ ] **Step 5:** Tests pass (windowed + headless). Existing suite still green. Commit.

### Task 11: Validation — top-down overlay, sizes, performance, second site

**Files:** Create `replica/check.py` (`check <site_dir>`), `tests/test_check.py`;
modify `replica_site.gd` (`--capture-topdown` flag); create `data/sites/smoke/site.json`.

**Interfaces:**
- Produces: `--capture-topdown` renders an orthographic top-down of the core at 0.5 m/px (4000²,
  tiled if needed) to `data/sites/<s>/build/topdown.png`; `check` computes rock-mask IoU between
  topdown (rock pixels by palette) and `classes.png` ROCK, and the centroid offset of each traced
  rock ≥ 3 m.
- [ ] **Step 1: Failing test:** `test_check_identical_masks` (IoU 1.0, offset 0) and
  `test_check_shifted` (5 m shift → reported offset 5 ± 0.5).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Real run: IoU ≥ 0.7 and median rock
  centroid offset ≤ 2 m. Write a side-by-side PNG (ortho | topdown) for the user (local only).
- [ ] **Step 5:** Performance: walk-path FPS at 1920 × 1080 with `--disable-vsync --print-fps`;
  ≥ 60 fps worst-case. Record in `docs/PERFORMANCE.md`.
- [ ] **Step 6:** Second-site smoke run (Review Focus 5): pick a steppe/granite coordinate whose ring
  crosses a 1° DEM tile edge, with manual `sun` and no gers; `fetch` + `build` + open the scene run
  without code changes. Record the coordinate in `site.json`.
- [ ] **Step 7:** Write `docs/TERRAIN_REPLICA.md` (how to add a site, the commands, the licence
  rule, the correction tool). Commit. Then the user walks the site (eye-level judgement).
