### Task 4: Grass shader — lean, gust waves, highlight, distance fade

**Files:**
- Modify: `assets/shaders/grass.gdshader`, `scripts/environment/grass_field.gd` (pass the fade
  uniforms)
- Test: `tests/test_grass_wind.gd`

**Interfaces:**
- Consumes: `wind.gdshaderinc` (`wind_gust`, `wind_direction`, `wind_strength`), and
  `INSTANCE_CUSTOM` from Task 3.
- Produces: grass shader uniforms `bend := 0.9` (tip offset in blade heights at strength 1, full
  gust), `flutter := 0.08`, `highlight := 0.18` (tip brightening at full gust), `fade_start`,
  `fade_end`, `base_color`, `tip_color`.
- Shader behaviour:
  - **Lean:** offset = `wind_direction * wind_strength * (0.35 + 0.65 * wind_gust(instance_xz)) * bend * UV.y²` in world space,
    applied to the vertex's world position. The base stays planted.
  - **Flutter:** per-blade `sin(TIME * 7 + phase * 6.283) * flutter * wind_strength * UV.y`,
    sideways to the wind.
  - **Highlight:** `ALBEDO *= 1 + highlight * gust * UV.y`.
  - **Fade:** `keep = 1 - smoothstep(fade_start, fade_end, camera distance)`. A blade with
    `fade_rand > keep` collapses to zero size. Blades near the threshold shrink in height first,
    so there is no popping line.

- [ ] **Step 1: Write the failing image test** (`needs_window()`). It builds a 16 × 16 m
  full-density field at `(0, 0, -6)` in Gameplay, hides the player, and grabs the frame centre
  rect (the middle third) with `pg.compare.render_state(pg.get_state())`.

```gdscript
func test_wind_moves_the_grass(pg) -> void:
	pg.set_param("wind", 0.0)
	var calm := await _grab(pg)
	pg.set_param("wind", 2.0)
	var windy := await _grab(pg)
	check(_mean_abs_diff(calm, windy) > 0.01, "strong wind visibly changes the field")

func test_direction_moves_the_grass(pg) -> void:
	pg.set_param("wind", 1.5)
	pg.set_param("wind_direction", 0.0)
	var a := await _grab(pg)
	pg.set_param("wind_direction", 180.0)
	var b := await _grab(pg)
	check(_mean_abs_diff(a, b) > 0.01, "opposite directions lean the field differently")
```

  `_mean_abs_diff` averages per-pixel luminance difference
  (`ValueProbe.luminance`) over the two images.
- [ ] **Step 2: Run** `--only=grass_wind`. Expected: FAIL (the colour-only shader doesn't move).
- [ ] **Step 3: Implement** the lean, flutter, highlight and fade.
- [ ] **Step 4: Run** `--only=grass_wind`. Expected: PASS.
- [ ] **Step 5: Visual check.** Spawn a temporary big field around the player in a scratch scene,
  or wait for Task 5 and do this there. Check that the waves travel along the direction and look
  irregular rather than like stripes. Check the far edge fades out with no visible line. In Notan
  and 3-Value, the path and landmark should still read first. Write what you saw in the ledger.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed. Expect it to be all green.

