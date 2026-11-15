# Terrain replica tool — design

Date: 2026-11-11
First site: Sümber district, Govisümber, Mongolia — centre 46°15'09.23"N 108°46'45.96"E

## Intent and why

The Heavens Call test level played as "a dead world". The user wants to improve things one piece at a
time, starting with terrain. Not a fix to that level: a **general tool** that builds terrain and places
props (rocks, grass, scrub, and later trees) the way they sit in real life.

"Realistic" here means **true to life in position and size**, not photographic graphics. The first
use is a replica of a real place: everything at its actual size and in its actual spot — hills,
channels, outcrops, boulders. Scale is 1:1 (1 game unit = 1 m).

## The first site (from recon, 2026-11-10)

- Steppe–Gobi border. A sandy dry valley (gravel wash with thin braided channels) between granite
  hills. Two white gers sit in the valley at the centre point with vehicle tracks leading away.
- Hills are piles of grey rounded granite boulders and slabs (tor-like), not smooth slopes. Bare rock
  on top, large loose boulders down the slopes, smaller stones at the base, almost no rock on the sand.
- No trees. Sparse dry steppe grass and low scrub, denser at rock feet and along channels.
- Elevation over ~6 × 6 km: 1,380–1,650 m. Flats ~1,400 m; peaks rise 150–250 m; one right next to the
  centre point to the NW (~1,650 m).

## Goals

1. Build a **2 × 2 km** replica centred on the coordinates above, as detailed as public data allows.
2. Ground shape from real elevation data at true heights; hills where they really are.
3. A **surface map** traced from satellite imagery: rock / sand-gravel / grass / scrub / channel /
   track / man-made (gers). It drives ground colouring and placement.
4. Every rock or rock mass visible in the imagery (≈ 2 m across and larger) placed at its real
   position with matching footprint size and orientation; height estimated from its shadow.
5. Detail the data can't show is filled by **rules** that follow how this landscape works: scree and
   small stones below outcrops, grass/scrub clustered at rock feet and along channels, sparse on open sand.
6. The tool is **reusable**: pointing it at another coordinate + size produces a new site through the
   same steps. Trees are supported as a placeable class even though this site has none.
7. Walkable at eye level in Godot with the existing player/camera; also viewable from above.

## Non-goals

- Photographic visuals (scanned textures, photoreal rendering). Not the point.
- Fixing or reworking Heavens Call.
- Sound, weather, wildlife, NPCs, gameplay.
- Drone/photogrammetry capture (no drone available; may come later — keep inputs pluggable so a
  higher-resolution heightmap could replace the 30 m one without rework).

## Anti-goals (would be a failure even if it runs)

- Rocks or hills that are the wrong size — e.g. a 3 m boulder rendered as 10 m, or a 200 m hill as
  80 m. Sizes must come from the data, never from "looks good" scaling.
- Rocks sprinkled at random, or evenly, independent of the real layout.
- Rules overriding the imagery: where the photo shows sand, no invented outcrop; where it shows a
  boulder, it must exist.
- A one-off script hard-wired to this valley.

## Constraints

- Godot 4.6 (pure GDScript project), existing repo `D:/DevEnv/GDOT/environment-lab`.
- Hardware: RTX 3070; target ≥ 60 fps at 1080p walking the site (repo's existing budget practice:
  `docs/PERFORMANCE.md`, profile flags in README).
- Data must be free/public:
  - Elevation: 30 m DEM. Copernicus GLO-30 preferred (better than SRTM in most places); SRTM 30 m
    as fallback. 2 km ≈ 67 × 67 samples.
  - Imagery: Esri World Imagery, max zoom 17 here (~0.83 m/px at this latitude; zoom 18+ returns
    an empty placeholder). Used as a tracing reference, not shipped as a texture.
- Imagery is a top-down photo taken at one unknown time; sun direction/elevation must be derived
  from the image itself.
- Downloaded data goes in its own directory (untrusted input); raw downloads are not committed if
  large — record exact source URLs/tiles so they can be re-fetched.

## How — decided

- **Visual style:** this project's existing low-poly, flat-colour look (user: graphics aren't the
  point). Ground coloured per surface class, not textured with photos.
- **Rock shapes:** the kit has only 3 rocks (`rock_boulder_a/b`, `rock_shard`). Make a family of
  granite shapes in Blender (rounded boulders, flat slabs, split boulders, stacked piles, scree
  pieces) in the kit's style. Rocks are scaled to their measured size; each shape's base footprint
  must be known so scaling is exact.
- **Rock heights from shadows:** measure shadow length in the imagery; calibrate sun elevation and
  direction using the gers (Mongolian ger: ~6 m diameter, ~2.3–2.5 m to the roof crown) and
  cross-check against the DEM where large outcrops exist.
- **Ground shape:** DEM gives the large shape at true height. Fine detail is added by rules guided
  by the surface map: channel cuts where channels are traced, bumps/rises under rock masses, sand
  flats kept smooth. Added detail must not change the DEM's large-scale heights (e.g. the 30 m-scale
  average of the result stays within a small tolerance of the DEM).
- **Pipeline order:** fetch data → surface map + rock list (from imagery) → heightmap (DEM + rule
  detail) → place traced rocks → rule-fill (scree, small stones, grass, scrub) → load in Godot.

## Calls made by Claude (user can overrule)

- **DEM is a surface model.** Copernicus GLO-30 measures the top of the tors, not the ground under
  them. Reading: **terrain + rocks together** must match the DEM at the large scale. Under traced rock
  masses the ground is lowered so that placed rocks bring the surface back to DEM height — never
  stack full-size rocks on top of a DEM that already contains them. The DEM tolerance check and hill
  height spot checks compare the combined surface (terrain + rocks), not bare terrain.
- **Offline tools may use Python** (numpy, rasterio/GDAL, pyproj, Pillow) in a project-local venv,
  plus Blender's Python for rock shapes. Anything that runs in the game stays GDScript. Data handed to
  Godot is plain files (PNG/EXR heightmaps, PNG surface map, JSON rock list).
- **Beyond the 2 km edge:** a low-detail ring from the DEM only (no rocks, surface colour from a coarse
  classification), out to ~10 km, so the horizon and surrounding hills are real. A hard edge is not
  acceptable — it breaks the eye-level check.
- **Second site:** "without code changes" means a new coordinate + size runs end to end through the
  same steps. Same landscape family (steppe/granite) is enough for this project; other terrain types
  (forest, dunes) may need new rock/plant sets and rules, which is configuration, not engine work.
  Sun calibration must not require gers: fall back to a known-height outcrop matched against the DEM,
  or to manual entry of sun azimuth/elevation.
- **Rock masses:** a continuous pile with merged shadows may be one "rock mass" outline, filled with
  boulders by rule inside that outline to the measured height. Separately visible boulders get their
  own entry.

- **Rock tracing (user unsure → Claude's call):** automatic first, hand-corrected. A detector finds
  rocks/rock masses from shadow + brightness in the imagery and writes the rock list; a small
  correction tool shows the list over the imagery so wrong/missed rocks can be fixed. Claude does the
  correction pass; the user spot-checks one ~200 × 200 m patch around the gers. Accept some misses
  among the smallest (~2 m) boulders; rule-fill covers below that.
- **Imagery licence (user unsure → Claude's call):** treated as a personal/learning project. Esri
  tiles are used only as a local tracing reference: not committed, not shipped, not used as a game
  texture. Only derived data (surface map, rock list) is kept. If this ever ships commercially,
  revisit — buy imagery or re-trace from a licensed source.

## How — the builder's call

- Terrain rendering in Godot: Terrain3D add-on (free, built for large detailed terrain) is the
  suggested default; verify it supports Godot 4.6 first. Fall back to the repo's own mesh approach
  (`scripts/levels/mountain_terrain.gd`) if not. Whichever: 2 km at a resolution fine enough to show
  channel cuts (~0.5–1 m).
- How the imagery is turned into the surface map and rock list: automatic classification, manual
  tracing in a small tool, or a mix. Accuracy matters more than automation for this first site.
- Rule details (scree falloff, grass clustering densities), tuned against the imagery.
- Rendering budget tactics (LOD, instancing, distance culling).
- Ger and track representation (simple shapes are fine).
- Storage format for the site data (heightmap image, surface map image, rock list JSON, etc.).

## How we'll judge it

1. **From above:** a top-down orthographic capture overlays the satellite image — outcrops, large
   boulders, channels, tracks and gers line up (within a couple of metres).
2. **Sizes:** spot checks — ger at real size; measured boulders match their imagery footprint;
   hill heights match the DEM at sample points.
3. **At eye level:** walking from the gers, the hills and rocks feel the right size and distance.
   (User judgement.)
4. A second coordinate can be run through the tool without code changes (smoke test).
