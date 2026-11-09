# Task 5 report: War debris and traveller props, staged along the trail

Status: DONE_WITH_CONCERNS. The concerns are minor; see the end.

## Implemented and files changed

**Blender kit** (`assets/blender/build_kit.py`):
- Two palette entries: `rusted_metal` (0.33, 0.19, 0.11) and `weathered_wood` (0.32, 0.29, 0.25).
- Four geometry helpers: `sector` (a pie-slice prism), `dome` (a capped half UV-sphere), `plate` (a curved grid with thickness) and `ribbon` (a double-sided cloth strip).
- Six builders, appended to the end of `ASSETS` with new seeds (71–97). Existing entries are untouched.
- Ran headless with `blender.exe -b -P assets/blender/build_kit.py`. It works; the only tracebacks come from the user's unrelated add-ons (rokoko/boto3, DivineCut unregister).

**New files:**
- `assets/meshes/prop_{shield_broken,sword_planted,helmet,breastplate,spear_broken,scarf_worn}.glb` (+ `.import`)
- `scenes/environment/kit/prop_*.tscn` (6 files): `kit_asset.gd` wrappers, copied from the `prop_cairn` pattern
- `assets/materials/rusted_metal.tres` (tint_variation 0.18) and `weathered_wood.tres` (0.12). Both use the `flat_color` shader with sway 0.
- `tests/test_heavens_props.gd` (3 tests)
- `tools/place_heavens_props.gd` (+ `.uid`): the hand-authored placement table, with a helper that resolves ground height and slope. It is kept under tools/ as the brief allows. Its header says the scene is the source of truth.

**Modified:**
- `scenes/levels/heavens_call.tscn`: 11 ext_resources (ids 12–22) and the `Debris`, `Traces` and `Rocks` Node3D groups, with plain baked transforms. The original content is unchanged; only additions were made.
- `assets/materials/flat_color.gdshader`: see the deviations section.
- `docs/ASSET_PIPELINE.md`: the palette-name list now includes `rusted_metal` and `weathered_wood`.
- `assets/blender/environment_kit.blend`: re-saved by the script.

## Props (triangles from Blender `loop_triangles`, visible mesh)

| Prop | Tris | Materials | Collision | Notes |
|---|---|---|---|---|
| prop_shield_broken | 200 | weathered_wood, rusted_metal | none | Round board with a 58° wedge missing, ragged edges by the break, rusted rim (broken at the gap), boss and strap iron. Lies tilted and half sunk; the broken wedge lies 0.75 m away. |
| prop_sword_planted | 132 | rusted_metal, weathered_wood, rock | none | Diamond-section blade with a notched edge, 0.2 m in the ground and tilted about 21°. One guard arm is bent down. Grip, pommel, and stones kicked up at the base. |
| prop_helmet | 154 | rusted_metal, monolith | none | Dented open-faced dome on its side, with brow band, nasal, a hanging cheek plate, and the dark inside showing. |
| prop_breastplate | 300 | rusted_metal | none | Face down on its keel, cracked into two halves; waist taper, arm holes, neck notch, rolled neck and waist rims (the right waist rim is gone). |
| prop_spear_broken | 86 | weathered_wood, rusted_metal | none | Snapped in two: the head end (socket and leaf blade) and the butt end (ferrule), both with splintered break ends. |
| prop_scarf_worn | 64 (+20 collider) | rock, cloth | `-convcolonly` stone | A 0.92 m standing stone with the `cloth` scarf draped over it. One end reaches the ground and the other lifts in the wind. |

No bodies, bones or gore anywhere.

## Staging

All transforms are baked into the .tscn. Each prop sits on `MountainTerrain.height_at`. Lying debris is aligned to the ground normal; planted swords lean 30% with the slope; cairns and scarf stones stand upright; rocks lean 50% with the slope and are sunk by 0.15 × scale.

**Debris: 28 pieces, progress 0.287–0.578.** 9 swords, 6 helmets, 6 shields, 4 spears, 3 breastplates, in eight uneven clusters:
- 0.287–0.292: the first sign, one planted sword with a helmet behind it, at the left edge.
- 0.318–0.327: shield, spear, and a half-sunk helmet at the right edge.
- 0.352–0.361: under the uphill wall.
- 0.386–0.412: **the narrows chokepoint** ("where they held the pass"). The densest cluster, 9 pieces on both sides, with 4 swords planted against the walls.
- 0.438–0.447: a ledge above the drop on the right; a sword stands at the lip.
- 0.484–0.494: two strays.
- 0.514–0.525: the flat switchback landing, 4 pieces.
- 0.561–0.578: thinning out.

Debris sits 2.3–7.6 m from the centreline (the worn path is ±1.5 m). It has no collision, so nothing blocks the corridor. Several pieces are sunk 0.05–0.10 m (half-buried helmets and shields).

**Traces: 9 pieces, progress 0.615–0.934.** 6 `prop_cairn` stacks (scale 0.55–0.9), 2 `prop_scarf_worn` (0.662, and 0.832 at the 0.82 narrows), and 1 `prop_fire_ring` at 0.752. The fire ring sits on the sheltered ledge under the uphill wall, with a small cairn beside it and a shard at 0.745 as a windbreak.

**Rocks: 40 pieces** (16 boulder_a, 13 boulder_b, 11 shard), progress 0.02–0.955. They sit in groups of 1–2 against the walls, on ledge lips and beside the debris clusters, 4.4–8.4 m from the centreline. Their convex collision stays clear of the path. None are on the summit plateau, which is left free for Task 6.

The helper confirmed `progress_at` for every placed node equals its authored progress (one shard reads 0.401 against 0.400), so no prop is matched to a neighbouring switchback leg.

## RED / GREEN

- **RED** (`--only=heavens_props`): 0 passed, 3 failed.
  - debris and traces: `Node not found: "Debris"` / `"Traces"`.
  - walkable: `centreline clear at 0.000` failed **before any props existed**. The probe was hitting the player herself: her CharacterBody3D is on layer 1 and `reset_scene` stands her at progress 0. I added `q.exclude = [lv.player.get_rid()]`, which is the only change to the brief's test code. After that the test passed with no props, as it should, and the other two still failed.
- **GREEN** (`--only=heavens`): 30 passed, 0 failed (three back-to-back runs at the end were also 30/30).

## Suite

- **Windowed:** 127 passed, 0 failed, 0 skipped (124 + 3).
  - The first full run gave 126 + 1 fail: `test_heavens_mood::test_mood_ignores_backtracking` (wind 0.700 read where 1.277 was expected).
  - That test is from Task 3. It waits only 3 process frames after teleporting and assumes a physics tick happens in them, which isn't guaranteed at high refresh rates.
  - It passed in 3/3 `--only=heavens` runs and in the full-suite rerun (127/127). I did not change it; see concerns.
- **Headless:** 105 passed, 0 failed, 22 skipped (102 + 3). `test_measure_is_fast` did not flake.
- No "no palette material" warnings. All new and edited files have 0 CRs (`tr -cd '\r' | wc -c`); `player.gd` is untouched.

## Captures

Location: `C:/Users/user/AppData/Local/Temp/claude/d595467b469acd6b/50fe8da1-f185-4552-92de-73eb6f745a9c/scratchpad/t5/cap/`. Windowed, 1280×720, lightning suppressed. The capture scripts are `t5/capture.gd` and `t5/lineup.gd` in the same scratchpad; temporary copies in tools/ were deleted.

**Gameplay views** (taken before the last two narrows swords were added):
- `view_350.png`: a planted sword, breastplate and shield in the dirt under the uphill wall, with a boulder. It reads as abandoned arms by the path.
- `view_385.png`: the approach to the narrows. A shield and planted swords are visible at both wall feet ahead.
- `view_500.png`: near the landing, a planted sword silhouetted on the skyline and a helmet. Sparse, by design.
- `view_740.png` (extra): the fire ring and a small cairn in the shelter of the wall. It clearly reads as a place where someone stopped.
- `view_800.png`: the camera is high and the next trace (scarf, 0.832) is a small dot up the ridge. Little is visible at this exact spot, which fits a thinning-out stretch. `view_740` covers the traces.

**Close-ups:**
- `lineup.png` and `lineup_top.png`: **the props close-up**, all six on flat ground in neutral light. Shield, planted sword, helmet, cracked breastplate, snapped spear and scarf stone each read clearly, rusted and weathered.
- `eye_narrows.png`: eye height through the pass.
- `eye_landing.png`
- `close_ledge.png`: the best shot. A sword stands at the ledge lip against the fog, with a snapped spear and a helmet in the dirt; desolate, no bodies.
- `close_sword_shield.png`: a planted sword silhouetted in the fog.
- `close_breastplate.png`: the old breastplate model, before the rebuild (see below).
- `close_scarf.png`
- `close_fire.png`

**What I saw and changed:**
- The first breastplate (3-column grid, wide crack) looked like a pair of trousers. I rebuilt it with a keel, waist taper, arm holes, neck notch, rims and a tight crack (`lineup_top.png` shows the fix).
- I pushed the rust a little more orange so it separates from the brown path.
- I lowered the scarf drape onto the stone (there was a gap at the top).
- I added 2 planted swords to the narrows, because from eye height the pass cluster read too faint.

## GLB regression check

I recorded size and MD5 of all 18 existing GLBs before running Blender, and compared after each of the two runs. **All 18 are byte-identical**, so existing assets cannot have changed in look. The existing kit `prop_cairn` and `prop_fire_ring` also appear in `view_740.png` and `close_fire.png`, looking as before.

## Decisions and deviations

1. **`flat_color.gdshader`: sway and contact shade are now relative to the node's origin** (`world.y - NODE_POSITION_WORLD.y`) instead of absolute world height.
   - Sway bent by `world.y²`, so on this mountain (y up to 220) any swaying material would move by metres. That breaks the brief's own swaying `scarf_worn`, and Task 6's khadag ovoos at the summit would hit the same problem.
   - The contact darkening (`base_height` 1.5) likewise never applied above y = 1.5.
   - Playground kit instances sit at y ≈ 0 (221 of 233 at exactly 0, the rest within −0.33…2), so the playground is unchanged.
   - Verified: playground frames with the old and new shader differ by a mean luminance of 0.00057 / 0.00017. Two runs with the same shader differ by 0.00042 / 0.00014. The image tests pass.
2. **The walkable test excludes the player's RID** (see RED above). Without it, the test fails at progress 0 regardless of props.
3. **Debris has no collision.** These are ankle-high pieces, and convex hulls on swords and shields would snag a CharacterBody. That also guarantees "none block the corridor". Rocks and cairns keep their kit collision; the scarf stone has an invisible stone-only collider.
4. **28 debris pieces** (20–30 allowed), 9 traces (6–10), 40 rocks.
5. **Placement tool kept** at `tools/place_heavens_props.gd` (the brief allows it). The table in it is the authored layout. Rock yaw comes from a golden-angle sequence; positions are authored.
6. **ASSET_PIPELINE.md**: added the two palette names to the conventions row.
7. A docstring-only edit to `sector()` was made after the last Blender run; it does not change any output.

## Self-review

- **Anti-goals:**
  - Weapons and armour only; no bodies or bones.
  - No fantasy clutter: the materials are the existing flat palette plus two muted additions.
  - Traces use the kit's cairns and fire ring, plus a plain scarf on a stone.
- **Kit conventions:** 1 unit = 1 m, origin at the base centre, one root Empty per asset, material names equal palette names, `_mesh` / `-convcolonly` suffixes.
- **Hand-authored placement:** clustered at edges, the narrows, a ledge and the landing; deliberately uneven, with nothing in the first 0.28 or on the summit.
- **Progress ranges** are verified by test and by the helper's printout; the walkable check covers 140 centreline samples.
- **Not done:**
  - No per-asset Notan/Squint check in the playground; the level captures stood in for it.
  - I did not open Blender's UI.

## Concerns

1. **The scarf barely sways.** The `cloth` material is used as the brief asks, but sway scales with the square of height above the origin. At the scarf's 0.5–0.9 m height the bend is only millimetres to about 1 cm at strong wind, so it reads as static. Making it visibly flutter would need its own material or a sway tweak. I left it as the brief asked.
2. **`test_mood_ignores_backtracking` is a timing flake** (1 failure in 5 windowed runs this session). It waits 3 process frames and assumes a physics tick happens in them. Suggested fix: `await tree.physics_frame` twice before reading. I left it alone because it is outside this task's scope.
3. **Shared shader change** (deviation 1) touches every kit asset. The reviewer should confirm that is acceptable; the playground evidence is above.
4. The gameplay `view_*` captures predate the two extra narrows swords; the close-ups and lineup reflect the final models.

## Fix round 1

Status: DONE.

### 1. Origin-relative height is now opt-in (Important finding)

**`assets/materials/flat_color.gdshader`:**
- Rebuilt from the snapshot copy, with additions only.
- New: `instance uniform bool height_from_origin = false;`.
- When it is true, `world_y -= NODE_POSITION_WORLD.y` runs after the old `world_y = world.y;`, and `bend` is recomputed from `h = max(world.y - NODE_POSITION_WORLD.y, 0.0)` after the old `bend` line.
- When it is false, the old expressions run untouched.
- Header comment updated.

**Diff against the snapshot.** Command:
`diff scratchpad/hc/snap/assets/materials/flat_color.gdshader assets/materials/flat_color.gdshader`

```
5a6,8      + header comment (3 lines)
22a26,27   + comment + `instance uniform bool height_from_origin = false;`
28a34,36   + if (height_from_origin) { world_y -= NODE_POSITION_WORLD.y; }
34a43,46   + if (height_from_origin) { float h = ...; bend = ... h * h ...; }
removed lines: 0
```

The false path is textually the old code: every original line is present and unchanged.

**`scripts/environment/kit_asset.gd`** (`@tool`):
- New `@export var height_from_origin := false`. Its setter re-applies the value when inside the tree (editor), and `_ready()` applies it in the game and the editor.
- `_apply_height_from_origin()` calls `set_instance_shader_parameter("height_from_origin", ...)` on every GeometryInstance3D under the kit instance.
- It writes only when the flag is on, or to clear a previously set value, so playground meshes never get the parameter.
- The parameter lives on the unowned GLB children, so nothing extra is saved into scenes.

**Level and tool:**
- `tools/place_heavens_props.gd` now writes `height_from_origin = true` for every node.
- The scene was re-baked and re-spliced: `heavens_call.tscn` has 77 `height_from_origin = true` lines (28 Debris + 9 Traces + 40 Rocks).
- The transforms are byte-identical to before: the diff contains only the new lines.

**Tests (RED, then GREEN):**
- `tests/test_heavens_props.gd::test_level_kit_measures_from_origin`: every kit node in Debris, Traces and Rocks has `height_from_origin` set, and each of its meshes has the instance parameter set to true (at least 77 meshes).
  - RED before re-staging: `Debris/Sword1 opts in`, `... mesh prop_sword_planted_mesh has the parameter on`, and so on.
  - GREEN after.
- New `tests/test_kit_height_origin.gd` (playground): more than 10 kit_asset nodes found, none with the flag, and no mesh carrying the parameter as true. It passes; it is a guard.

**Docs:** `docs/ASSET_PIPELINE.md` has a short paragraph on `height_from_origin`.

### 2. Ruling 10: deflaking the tests that teleport then read physics state

**Root cause, measured with temporary frame counters in the test (since removed).** In the failing pattern, `physics_frames(3)` finished after only **2 process frames**: one slow frame ran several physics ticks back to back. `SceneTree.process_frame` is emitted *before* nodes' `_process`, so the test read `mood.current` before `HeavensCall._process` had applied the new furthest progress. It therefore saw the ascent wind 0.700. Three process frames hit the same window whenever a long frame occurred, for example on first sight of a newly staged area. That is why the new props made the existing race more frequent.

**Fix.** New helper `physics_frames(count)` in `tests/case.gd`: it awaits `count` physics ticks, then two process frames, which guarantees one whole `_process` pass after the ticks. It is used in:
- `test_heavens_mood`: `test_mood_ignores_backtracking` (both waits), `test_no_lightning_before_eerie`, `test_walking_down_never_respawns`
- `test_heavens_trail::test_fall_respawns_on_trail`
- `test_heavens_props::test_props_leave_the_path_walkable`

Tests that set `furthest_progress` directly and wait `frames(2)` already get a full `_process` pass, so they were left alone. The camera test reads `_process`-driven state, so it was left alone too.

**Stability.** A version of the helper that waited only one process frame still failed once in 3 `--only=heavens` runs. With the final helper:

```
--only=heavens x5 (windowed): 31 passed, 0 failed, 0 skipped  (all five runs)
```

### Suite after fix round 1

| Command | Result |
|---|---|
| `--only=height_origin` (windowed) | 1 passed, 0 failed |
| `--only=heavens` ×5 (windowed) | 31 passed, 0 failed each time |
| `Godot --path . -s res://tests/run.gd` | **129 passed, 0 failed, 0 skipped** (127 + 2 new) |
| `Godot --headless --path . -s res://tests/run.gd` | **107 passed, 0 failed, 22 skipped** (105 + 2) |

- No palette or instance-parameter warnings in either log.
- All touched files have 0 CRs.
- A level recapture after the fix (`scratchpad/t5/cap_fix1/*.png`, e.g. `close_ledge.png`) renders as before, with no errors.

### Files touched in fix round 1

- `assets/materials/flat_color.gdshader`
- `scripts/environment/kit_asset.gd`
- `scenes/levels/heavens_call.tscn`
- `tools/place_heavens_props.gd`
- `tests/case.gd`
- `tests/test_heavens_mood.gd`
- `tests/test_heavens_trail.gd`
- `tests/test_heavens_props.gd`
- `tests/test_kit_height_origin.gd` (new)
- `docs/ASSET_PIPELINE.md`

### Remaining notes

- The scarf's low sway is left as it is, per the ruling.
- Task 6 must set `height_from_origin = true` on any kit pieces it places on the mountain, such as the khadag ovoos. Otherwise their cloth will sway by world height (metres at y ≈ 220). This is documented in ASSET_PIPELINE.md.
