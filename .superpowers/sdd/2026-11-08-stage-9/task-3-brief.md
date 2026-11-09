### Task 3: GrassField — mask, painting, ground cache, chunks

**Files:**
- Create: `scripts/environment/grass_field.gd`, `assets/shaders/grass.gdshader` (colour only in
  this task; wind comes in Task 4), `tests/test_grass_field.gd`

**Interfaces:**
- Produces: `class_name GrassField extends Node3D` (`@tool`), with:
  - `const CHUNK_SIZE := 16.0`
  - `enum PaintMode { DENSITY, HEIGHT, ERASE }`
  - `signal rebuilt(blade_count: int)`
  - Exports (rebuild on change, as `Scatter` does with `mark_dirty`):
    - `extent := Vector2(74, 104)`
    - `texel_size := 0.5`
    - `mask: Image`
    - `blades_per_m2 := 24.0`
    - `min_height := 0.25`
    - `max_height := 0.9`
    - `random_seed := 1`
    - `ground_layer := 2`
    - `base_color`, `tip_color` (pick near `ground.tres` `(0.16, 0.17, 0.15)`; tip lighter and
      slightly warm)
    - `fade_start := 25.0`, `fade_end := 45.0`
  - `func mask_size() -> Vector2i`: `ceil(extent / texel_size)`
  - `func ensure_mask() -> void`: creates an `Image.FORMAT_RG8` of `mask_size()`, filled with
    `(0, 0.5)`, if `mask` is null. If the size is wrong, resizes it (bilinear) instead.
  - `func sample(world_xz: Vector2) -> Vector2`: bilinear `(density, height)`, `(0, 0)` outside
  - `func paint(world_pos: Vector3, radius: float, mode: PaintMode, target: float, strength: float, falloff := 0.5) -> Rect2i`
    - For each texel centre within `radius`: `w = strength * (1 - smoothstep(radius * (1 - falloff), radius, d))`.
    - DENSITY moves R toward `target`, HEIGHT moves G toward `target`, ERASE moves R toward 0, each
      by `lerp(v, target, w)`.
    - Returns the changed texel rect, clipped to the mask, or an empty `Rect2i()` if nothing
      changed.
  - `func set_mask_data(image: Image) -> void`: copies into `mask` and rebuilds everything (used
    by undo)
  - `func rebuild(texel_rect := Rect2i()) -> void`: an empty rect rebuilds every chunk; otherwise
    only chunks touching the rect grown by 1 texel
  - `func refresh_ground() -> void`: re-raycasts the height cache, then rebuilds
  - `func ground_height_at(world_xz: Vector2) -> float`: bilinear from the cache, `NAN` if any
    surrounding sample missed
  - `func blade_count() -> int`
  - `func chunk_instance(chunk: Vector2i) -> MultiMeshInstance3D`: null for an empty chunk
  - `static func blade_mesh() -> ArrayMesh`: a tapered blade of 3 segments (7 vertices), 1 unit
    tall, with `UV.y` = 0 at the base and 1 at the tip
- **Placement algorithm** (fixed, because tests depend on it being stable):
  - Each chunk gets an RNG seeded with `hash([random_seed, chunk.x, chunk.y])`, and
    `int(blades_per_m2 * CHUNK_SIZE²)` candidates.
  - Each candidate draws all of its randoms up front, in this order: x, z, keep, height jitter
    (±15%), yaw, lean (±10°), custom (tint, phase, fade).
  - A candidate is kept if `keep < sample().x` and `ground_height_at` isn't `NAN`.
  - Height = `lerp(min_height, max_height, sample().y) * jitter`.
  - `INSTANCE_CUSTOM` = `Color(tint, phase, fade_rand, 0)`.
  - Chunk nodes are internal children with no owner (not saved), named `"Chunk_%d_%d"`.
    `cast_shadow = OFF`, `visibility_range_end = fade_end + CHUNK_SIZE`.
- The ground cache is one height per texel centre, raycast from y = 40 down to y = −5 against
  `ground_layer`. It's computed lazily, on the first rebuild after `_ready`, waiting for the
  physics frame.

- [ ] **Step 1: Write the failing tests.** Each test builds its own field: `GrassField.new()`,
  `extent = Vector2(16, 16)`, added at `Vector3(0, 0, -6)` on the Ground plane in front of the
  gameplay start. `await frames(2)`, then `ensure_mask()`. Free it in `after_each`.

```gdscript
func test_paint_density_reaches_target_at_centre(pg) -> void:
	var r := f.paint(f.global_position, 2.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	check(r.has_area(), "a changed rect is returned")
	check_near(f.sample(Vector2(0, -6)).x, 1.0, 0.01, "full strength reaches the target at the centre")
	check_near(f.sample(Vector2(3, -6)).x, 0.0, 0.01, "nothing outside the radius")

func test_erase_and_height_modes(pg) -> void:
	f.paint(f.global_position, 2.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.paint(f.global_position, 2.0, GrassField.PaintMode.HEIGHT, 0.0, 1.0)
	check_near(f.sample(Vector2(0, -6)).y, 0.0, 0.01, "height mode moves G only")
	check_near(f.sample(Vector2(0, -6)).x, 1.0, 0.01, "density untouched by height mode")
	f.paint(f.global_position, 2.0, GrassField.PaintMode.ERASE, 1.0, 1.0)
	check_near(f.sample(Vector2(0, -6)).x, 0.0, 0.01, "erase zeroes density")

func test_paint_clips_at_field_edge(pg) -> void:
	var r := f.paint(f.global_position + Vector3(8, 0, 0), 30.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	check(Rect2i(Vector2i.ZERO, f.mask_size()).encloses(r), "rect clipped to the mask")
	var off := f.paint(f.global_position + Vector3(100, 0, 0), 2.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	check(not off.has_area(), "painting fully off the field changes nothing")

func test_blades_follow_density_and_are_reproducible(pg) -> void:
	check_eq(f.blade_count(), 0, "empty mask = no blades")
	f.paint(f.global_position, 4.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild()
	var n := f.blade_count()
	check(n > 0, "painted area grows blades")
	f.rebuild()
	check_eq(f.blade_count(), n, "same mask + seed = same blades")
	var mm := f.chunk_instance(Vector2i(0, 0)).multimesh
	var t0 := mm.get_instance_transform(0)
	f.rebuild()
	check(f.chunk_instance(Vector2i(0, 0)).multimesh.get_instance_transform(0).is_equal_approx(t0), "same first blade")

func test_heights_follow_mask(pg) -> void:
	f.paint(f.global_position, 4.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.paint(f.global_position, 4.0, GrassField.PaintMode.HEIGHT, 1.0, 1.0)
	f.rebuild()
	var mm := f.chunk_instance(Vector2i(0, 0)).multimesh
	for i in mini(mm.instance_count, 50):
		var h := mm.get_instance_transform(i).basis.y.length()
		check(h >= f.max_height * 0.84 and h <= f.max_height * 1.16, "tall paint = max_height ± jitter")

func test_no_blades_where_ground_missing(pg) -> void:
	f.position = Vector3(500, 0, 500)  # beyond the 400 m Ground plane
	f.refresh_ground()
	f.paint(f.global_position, 4.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild()
	check_eq(f.blade_count(), 0, "no ground hit = no blades")
	check(is_nan(f.ground_height_at(Vector2(500, 500))), "missing ground reads NAN")

func test_partial_rebuild_touches_only_affected_chunks(pg) -> void:
	f.extent = Vector2(48, 16)  # three chunks in X
	f.ensure_mask()
	f.paint(f.global_position + Vector3(-16, 0, 0), 3.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild()
	var far := f.chunk_instance(Vector2i(0, 0))
	var r := f.paint(f.global_position + Vector3(16, 0, 0), 3.0, GrassField.PaintMode.DENSITY, 1.0, 1.0)
	f.rebuild(r)
	check(f.chunk_instance(Vector2i(0, 0)) == far, "untouched chunk keeps its node")
```

  Chunk coordinates start at the field's −X/−Z corner. Adjust the `Vector2i` indices in the tests
  if that convention differs, but keep it the same in every test.
- [ ] **Step 2: Run** `--only=grass_field`. Expected: FAIL (`GrassField` not declared).
- [ ] **Step 3: Implement `GrassField`** and a colour-only `grass.gdshader`: base → tip colour by
  `UV.y`, the per-face normal and base darkening copied from `flat_color`, `cull_disabled`, and
  `INSTANCE_CUSTOM.r` tint jitter.
- [ ] **Step 4: Run** `--only=grass_field`. Expected: PASS. Also run once headless: the logic tests
  must pass there too.
- [ ] **Step 5: Checkpoint.** Run the full suite windowed. Expect it to be all green.

