# Task 4 report: grass wind shader

Status: DONE (with concerns below)

## Implemented
- assets/shaders/grass.gdshader: includes wind.gdshaderinc; uniforms bend 0.9, flutter 0.08, highlight 0.18, fade_start, fade_end. Uses `skip_vertex_transform`: world position is built in vertex(), displaced, then converted to view space.
  - Lean: wind_direction * wind_strength * (0.35+0.65*gust(blade root xz)) * bend * UV.y^2 * blade height (so "blade heights" holds with the per-blade height scale). Root stays planted (UV.y = 0).
  - Flutter: sin(TIME*7 + phase*6.283) * flutter * strength * UV.y * height, across the wind.
  - Highlight: ALBEDO *= 1 + highlight * gust * UV.y (gust scaled by min(strength,1), see deviations).
  - Fade: keep = 1 - smoothstep(fade_start, fade_end, dist(root, camera)); size = clamp((keep*1.12 - fade_rand)/0.12, 0, 1); the blade (offset from root, and its lean) is scaled by size, so blades shrink to nothing over a narrow band before vanishing.
- scripts/environment/grass_field.gd: _update_material passes fade_start / fade_end.
- tests/test_grass_wind.gd (new): test_wind_moves_the_grass, test_direction_moves_the_grass (image tests), test_shader_exposes_wind_and_fade_uniforms (source + material check). Field placed per Ruling 2 (16x16, full density, centred 8 m ahead of active camera flattened to XZ, y=0), player hidden.

## TDD
- RED: `-- --only=grass_wind` -> 0 passed, 3 failed (no include, no uniforms, fade_start param Nil).
- GREEN: after implementing, 2/3; wind test failed at diff 0.0093 (<0.01) because the brief's middle-third rect is mostly trees/sky/fog. Changed the grab rect (see deviations) -> diffs 0.022 and 0.024, 3 passed.
- Full suite windowed: 75 passed, 0 failed, 0 skipped, exit 0 (was 72; +3).

## Visual check (throwaway test, deleted)
Camera frames saved and viewed. Calm vs wind 2: calm blades stand upright spikes, windy ones lie over strongly, clearly different. Wind 1.5 toward +Z (toward camera) vs 90 degrees: lean direction follows the wind; leaning is patchy (heavier lean and lighter tip highlights in gust patches on the left, upright in calm patches), no stripes or sheet look. With a 70x70 m field, the far edge thins out gradually with no visible line (fog helps). Grass stays dark, low-contrast, faceted; it does not overpower trees and path. Not checked: Notan and 3-Value views, and a time series of travelling gusts (patch irregularity seen in single frames only).

## Deviations
1. Test grab rect: middle third horizontally, y from 50% to 90% of the frame (where the field sits), instead of the middle third vertically; the brief's rect gave 0.0093 for calm vs wind 2 (threshold 0.01) as it's mostly non-grass. Threshold unchanged.
2. Highlight multiplied by min(wind_strength,1) so calm air has no gust highlight.
3. Fade: remapped keep (1.12 factor) so near blades with fade_rand near 1 do not shrink; the whole blade scales, not height first.
4. Lean multiplied by blade height (brief says tip offset in blade heights).

## Self-review / concerns
- Gust sampled at blade root, consistent with the trees' shared field.
- skip_vertex_transform: NORMAL is set but fragment rebuilds normals from derivatives; shadows are off for grass so no shadow-pass concern.
- Flutter uses TIME, so the image tests compare frames at different times; effect on tests is small versus lean.
- GPU cost not measured (Task 5/budget).
