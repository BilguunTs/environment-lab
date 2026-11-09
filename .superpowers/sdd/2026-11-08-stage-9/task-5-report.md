# Task 5 report: starter grass in the playground

Status: DONE.

## Implemented
- `tools/make_starter_grass.gd`: writes RG8 mask bytes directly (148x208 texels, 0.5 m, field centre (0,0,6), 74x104).
  Density = FastNoiseLite (seed 9, 12 m wavelength, simplex smooth) mapped to 0.4..1.0, times smoothstep(1, 3, distance beyond the
  path EDGE) over Path and SideTrail; 0 inside Clearing floor radius (9.5, +0.5 m margin). Height 0.3 at the path rising to 0.9
  at 15 m, plus +-0.08 noise, stored as G across min_height..max_height (0.25..0.9).
- `assets/grass/playground_grass.res` (Image), loaded as an ext_resource in `scenes/playground.tscn` (`Grass` node, (0,0,6), extent 74x104; CRLF kept).
- `scripts/playground.gd`: `grass_visible` in PARAM_ORDER right after `props_visible`, `@onready var grass: GrassField = $Grass`, get/set cases.
- `scripts/ui/dev_panel.gd`: "Grass" check box in Environment.
- `tests/test_grass_scene.gd`: the 4 brief tests plus a clearing test; the path test covers Path and SideTrail.

## TDD
RED: `--only=grass_scene` headless: 0 passed, 5 failed (no `grass` property). GREEN: 5 passed. Full windowed suite: **80 passed, 0 failed** (75 + 5).

## Visual (all 11 views read)
Grass hugs both sides of the path in Gameplay, Forest Gate, Gate Thirds, Path Low and Camp; the path and clearing stay bare.
It sits on the mounds (no floating or buried tufts seen). Overview/Reveal/Long Lens are mostly past the fade, so grass barely shows there,
which is correct. Landmark and clearing still read first. 3-Value and Notan (Gameplay): the picture is almost identical to grass off, and
the only difference is a mid-grey tuft patch right of the path; the path strip and landmark read as before. Note that the scratch-run
Notan frame was very dark in both on/off cases (baseline lighting in my scratch script), so it is not a grass effect.
Blade count at start: 112,982 (blade_count > 10000 true right after 2 frames; the pre-physics NAN issue did not bite: the node builds in _physics_process).

## Perf (RTX 3070, window 1600x900 not 1080p, mean over 90 frames, GPU ms, grass on / off)
Busiest: Gate Thirds 1.96 / 1.64 (grass +0.32); Camp 1.96 / 1.68 (+0.28); Scout 1.72 / 1.39 (+0.34).
Others 1.5-1.9 on, grass delta -0.05..+0.22. Well inside 2.0 ms grass / 7.0 ms frame. I measured with the same
RenderingServer measure calls as PerfHud (viewport_get_measured_render_time_gpu), not by reading the HUD label.

## Deviations
- Exclusion margin uses the path edge (per-sample half width from the same width profile as PathRibbon, x(1 + edge_noise*0.8) for bulges)
  rather than the nominal `width`/2, so the 1 m clear + 2 m ramp holds at the widened end too.
- Generator can't load the scene when the mask file doesn't exist yet (first run printed a parse error but still wrote the file); re-running is clean.

## Self-review / concerns
- Mask is static; Task 6 brush will repaint. Re-running the generator overwrites any hand painting.
- Path half-width in the generator is hard-wired to PathRibbon's profile; if that profile changes the generator needs a rerun.
- Left scratch scripts in the session scratchpad only; screenshots dir has new PNGs.
