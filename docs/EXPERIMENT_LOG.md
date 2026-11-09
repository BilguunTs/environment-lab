# Experiment log

Record one variable change per entry, and capture before/after screenshots with **All views**
or F12. Value views and guides are included in screenshots, so a notan comparison is just two
F12 presses.

| Date | Question | Changed | Fixed | Result / takeaway |
| --- | --- | --- | --- | --- |
| 2026-10-10 | Does fog density alone hide the landmark? | fog 0.022 → 0.012 | geometry, camera | At 0.022 the overview was a grey wall and the monolith barely read from Reveal. 0.012 keeps depth layers without losing the landmark. |
| 2026-10-10 | Does the foreground frame or clutter? | Boulder2 scale 2.4 → 1.8, moved 2.5 m outward | everything else | At 2.4 the boulder filled the right third of the gameplay frame and competed with the player. |
| 2026-10-10 | Where does the landmark sit in the value hierarchy? | nothing (measured Forest Gate) | default preset | Luminance: sky 0.74, **monolith 0.54**, far trees 0.52, path 0.51, near trees/ground ~0.30. The landmark is in the *same value band as the mid-ground forest*, so it separates from the sky but not from its surroundings. In notan it merges into one silhouette with the outcrop and trees. **Open problem, see experiment 1 below.** |
| 2026-10-10 | Gate centred vs on a third | camera yaw 15.4° (Forest Gate → Gate Thirds) | position, light | Moving the landmark to the right third put the right-hand gate tree dead centre. A frame is a system: moving one element changes every other element's position too. |
| 2026-10-10 | Why does the scene feel lifeless? | nothing (measured 4 views, Stage 2 look) | — | Value range only p5 0.25 → p95 0.76 (no true darks or highlights), mean saturation ≈ 0.10 in every view, nothing moving. Diagnosis: flat light, no temperature contrast, total stillness. *Not* a lack of props. |
| 2026-10-10 | First volumetric pass | sun 2.2 at 160° (straight behind the landmark), vol fog 0.012, anisotropy 0.6 | geometry, cameras | White-out in every northward view and sepia everywhere. Forward-scattering fog multiplies the sun's brightness when you look toward it. |
| 2026-10-10 | Volumetric pass, tuned | sun 1.6 at 135°, vol fog 0.004 with cool albedo, AgX tonemapper, patchier and lower mist | geometry, cameras | Real darks return, warm light pools and shadow stripes appear on the path, cool haze in the distance. Takeaway: atmosphere is subtractive. Each layer (depth fog, volumetric, mist) has to be weaker when the others are on. |
| 2026-10-10 | First larch design | wide flat pads stacked up the trunk, 24% of trees | everything else | Read as signposts or stacked plates, especially near camera, and dominated the forest. Rebuilt as a sparse narrow cone of small tufts at 12%. A distinctive silhouette has to stay *plausible* at the closest distance it will be seen. |
| 2026-10-10 | Kit vs blockout primitives | 3 tree species + tint variation replace one cone tree | lighting, cameras, positions | The forest stops reading as copies: skyline rhythm from Spruce B, holes in the mass from the larch. Same positions, so the gain is purely silhouette and value variety. |
| 2026-10-10 | Overview after the kit | (observation) | — | The plan view shows a large empty flat area east of the clearing. It isn't visible from any gameplay view yet, but it's a hole in the layout, worth deciding in Stage 6: fill it, or make it a deliberate open moor. |
| 2026-10-10 | First procedural pass vs manual forest | scatter: density 4.5, spacing 3.4, clumping 0.55 | lights, cameras, hero items | 105 trees, evenly spread: it read as a *park*. The manual forest has dense walls along the path that turn it into a corridor. Random placement doesn't know that rule. |
| 2026-10-10 | Teach the generator the corridor rule | far thinning (full density at the path, 50 % by 22 m), density 9, spacing 3.1, clumping 0.45 | everything else | 137 trees. It now frames the path like the manual forest from Reveal and Overview. The remaining difference is the gameplay view: the manual forest has deliberate foreground trees framing the shot, and the scatter doesn't. **Scatter fills space; it doesn't compose frames.** That's why foreground framing stays in `Hero`. |
| 2026-10-10 | Where does new content go? | (ASCII occupancy map of the manual forest) | — | The emptiest region (x 20–38, z −12…−36) was the hole flagged in Stage 4. It became the abandoned camp, reached by a side trail. New content should fix a layout problem, not just fill space. |
| 2026-10-10 | Does the spirit banner work as a secondary landmark? | banner 14 m → 18 m | trees ≤ 16 m, monolith 26 m | At 14 m it hid below the canopy and wasn't visible from anywhere on the main path. At 18 m it clears the treeline at the fork, above the gate tree. From Reveal it's still lost in the dawn haze, which is acceptable for a *discovered* landmark. Height hierarchy: monolith > banner > trees. |
| 2026-10-10 | Do the processional posts read? | khadag cloth 0.2 × 1.1 m dark blue → 0.32 × 1.4 m lighter blue | positions | Small and dark, they read as dead sticks. Larger and lighter, they read as a line of blue markers leading to the clearing. A leading line only works if its elements read at the distance you see them. |
| 2026-10-10 | Does the camp story read on arrival? | (observation, Camp view) | Cold Dawn | You arrive from the west looking into the low dawn sun, so the ger, hearth and walls are glare and silhouettes. The banner reads; the details don't. **Open: a Stage 7 lighting decision.** |
| 2026-10-12 | Does the spirit stream read as spirits? | first pass: 60 wisps, one Bezier path | lights, cameras | Every wisp rode the same lane at the same pace: a rigid dotted line, like a power cable. Per-wisp lanes, paces and drift turned it into a loose drift. **Regularity reads as machinery; irregularity reads as life.** |
| 2026-10-12 | Does the hole read as light from far away? | hole emission 6 → 14 | Awakened, Long Lens | No visible change. The tonemapper flattens the core to a pale flat hexagon, so it reads as paint. Adding a soft halo that ignores depth fog made it read as a light source. Brightness alone doesn't say "light"; light spilling into the air around it does. |
| 2026-10-12 | Does the awake monolith fix the Stage 2 notan problem? | (measured, Cold Dawn) | default preset | Hole luminance 0.86 (Forest Gate) / 0.81 (Reveal) vs sky 0.60 and monolith body 0.51–0.58. The landmark now owns the brightest point in the frame, so it separates from the outcrop without changing the fog or sun. |

## Stage 9 experiments to run

Use one fixed view per experiment, change one thing, and pair it with Pin A / Z so the diff is explicit.

1. **Across or along?** In Path Low, set *Wind direction* to 90 (across the path), then 0 or 180 (along it). Which
   makes the waves read as a leading line toward the landmark, and which makes them read as a barrier?
2. **When does motion become distraction?** In Forest Gate, raise *Wind* from 0.2 in steps of 0.2. Find the strength where
   you stop noticing the grass and start noticing the *gusts*. Revisit the Stage 3 stillness test: how much motion is
   atmosphere, and where does it start pulling the eye from the landmark?
3. **Height as a frame.** Select `Grass`, paint the ring around the landmark with the *Height* brush, tall at the edge and
   short near the foot. Does the tall grass frame it, or does it just hide the base? Compare against the starter meadow.
4. **A clearing as a frame.** In Gate Thirds, Shift+LMB a clearing in the foreground meadow. Does the bare ground make
   a stage for the gate, or a hole in the frame? Move the clearing and see which shot it helps.
5. **Highlight vs notan.** Change the grass `tip_color` from dark to bright, then press V to switch to notan. At what
   brightness does the grass stop reading as one dark mass and start competing with the path? Does it still
   separate from the landmark?

## Stage 8 experiments to run

1. **Redo Stage 7 #1 as a pair.** In Forest Gate, pin A with *Monolith awake* on, switch it off, then *Save pair*. Paste
   the copied row into the table above and write the Question and Result. Did seeing them side by side change your answer?
2. **Palette or light?** Pick the view you like least. Look at it in *Unshaded*, then *Lighting*. Which one is the problem?
   Fix only that one, then compare against the original with X.
3. **Read the histogram.** Turn on the value probe in Reveal. Where is the big hump, and how much of the frame sits on
   each side of the *Value split* line? Move the split until the landmark is on the light side alone.
4. **What does the fog cost?** With the perf readout on, toggle *Light shafts* and *Drifting mist*. Write down the GPU ms
   each one costs. Is either one worth what it costs in the views where you can barely see it?
5. **Light as level design, measured.** Turn on light gizmos and walk the path. Does every bend have a light (sun pool,
   ember or lantern) reaching it? Note the bend that has none.

## Stage 7 experiments to run

1. **With and without.** In Reveal, Forest Gate and Clearing, F12 with *Monolith awake* on, then off. Write one sentence
   about what the place *is* in each state. If the sentences match, the effect is decoration, not story.
2. **How quiet is quiet?** In Cold Dawn and the Gameplay view, walk the whole path with *Spirits* at 0.5, then at 0.2 and 1.0.
   Find the lowest value at which you still notice the stream without being told it's there. That's the default.
3. **Breathing vs flicker.** In `Landmark/HoleGlow`, set `period` to 0.4 (a flicker), then 15 (barely moving). Which one says
   *alive*, which says *broken machine*, and which says *fire*?
4. **Shaft vs no shaft.** In Awakened, toggle *Light shafts*. The cold shaft lights the clearing from above. Does it make the
   ember feel threatened, protected, or fed?
5. **Move the target.** In the editor, point `SpiritStream.target` at the camp's cold hearth instead of the ember. What
   does the level say now, and is it better or worse than *the monolith feeds the ember*?

## Stage 6 experiments to run

1. **The camp against the light.** In the Camp view, try *Sun angle* around −45 (sun behind you), then Golden Backlight, then Moonlit.
   Which one tells the story *"people lived here and left"*: detail you can read, or silhouette and mood? Save the winner as a preset.
2. **Story with and without props.** Toggle *Story props* in the Camp and Forest Gate views. Write one sentence for each
   state. If the sentences are the same, the props aren't doing their job.
3. **Path hierarchy.** Set `SideTrail`'s material to the main `path.tres`. Walk to the fork. Does the trail now compete with the
   main route? Revert it, then try `edge_noise` = 0 on the main path: what does a perfectly clean ribbon say about the place?
4. **Build a wall.** Snap four `wall_segment`s and a `wall_end` along the first bend of the main path as an old field boundary.
   Does a human-made line make the forest feel older, or does it fight the path for attention?
5. **The ochre link.** The ger's door frame is the same colour as the player's cloak. Stand the player in the doorway (Camp view)
   and squint. Is the link noticeable, too subtle, or too obvious?

## Stage 5 experiments to run

1. **Manual vs procedural.** For each fixed view, F12 in Manual, then in Procedural (seed 1). Which views get
   worse? Look for missing foreground framing or a broken sightline. Fix it by adding a hero item or a zone,
   not by re-rolling seeds.
2. **Seed sweep.** Press *New seed* ten times from the Reveal view. Bookmark the best seed with Copy settings.
   Is "best" about the forest, or about what happens to land near the camera?
3. **Clumping 0 vs 1.** Same seed. Watch the Overview, then walk the path. Groves create pockets of shade and
   light; even coverage creates noise. Find the value where the forest feels *grown*.
4. **Draw a new zone.** Duplicate `Scatter/Zones/Clearing` as a circle near a path bend (radius ~6). In Procedural
   mode it becomes a small glade. Use it with a light pool (Stage 3) as a breather moment on the walk.
5. **Rock density vs props.** Raise *Rock density* until the path edge looks cluttered, then back off. Where's
   the line between "rocky ground" and "noise that competes with the cairns"?

## Stage 4 experiments to run

1. **Species mix.** Make one view all Spruce A: in `scenes/playground.tscn`, temporarily replace
   `kit_tree_spruce_b` / `kit_tree_larch` with `kit_tree_spruce_a` in the Tree nodes' `instance=`.
   Squint at that view, then at the mixed forest. What does the mix change at distance vs up close?
2. **The hole.** In Forest Gate and Long Lens, does the hole in the monolith read at all? Try the
   Golden Backlight preset. If it only reads backlit, that's a lighting cue for Stage 7.
3. **Story by props.** Hide Props (panel → Environment) and walk the path, then show them and walk it again.
   Write one sentence about what the place *is* in each case.
4. **Rebuild a tree.** Open `assets/blender/build_kit.py`, change `tree_spruce_b`'s `squash` or `tiers`, run it, and
   watch the whole forest update in Godot. This is the iteration loop for Stage 5.

## Stage 3 experiments to run

1. **Before/after.** Apply *Flat Overcast*, F12, then Reset, F12, from the same view. Then switch on the
   Stage 3 features one at a time (warm sun, low shadow fill, light shafts, mist, wind) and note which
   single change brings the most life back.
2. **Temperature contrast only.** Start from Reset and set *Sun colour* and *Sky top* to the same neutral
   grey. Then pull them apart (sun warmer, sky cooler) in small steps. Where does the scene stop looking grey?
3. **Light as level design.** In Gameplay, rotate *Sun angle* slowly and watch the light pools on the
   path. Find an angle where a lit patch sits at each bend, so light pulls you forward. Copy settings and
   save it as a preset.
4. **Landmark separation, revisited.** Golden Backlight puts the dark monolith against the glow. In Notan,
   compare it with the default mood: which separates the landmark better, and what does each cost the
   rest of the frame?
5. **Stillness test.** Set Wind to 0 and turn motes off, watch for 10 s, then restore them. Then try Wind 2.
   Find the point where motion stops being atmosphere and becomes a distraction.

## Stage 2 experiments to run

Do each in a fixed view with one change at a time, and take an F12 before and after.

1. **Make the landmark the darkest thing against the sky.** In Forest Gate, switch to Notan (V)
   and set Value split to about 0.6. Try one fix at a time:
   - lower fog density
   - move the sun angle so the monolith is back-lit (`Sun angle` about 150–200)
   - darken the sky (`Sky / fog`)

   Goal: the monolith reads as its own shape, not merged with the outcrop. Note which fix also
   keeps the near/mid/far layers distinct in 3-Value.
2. **Lens and scale.** Switch between Long Lens and Landmark Foot. Then, in Scout (F), stand at
   Landmark Foot's position and drag the FOV slider from 70° down to 30°, re-framing as you go.
   At what focal length does the monolith stop feeling threatening and start feeling like a
   postcard?
3. **Subject placement in gameplay.** With the Thirds grid on, set Shift X to about ±1.6 so the
   player sits on a third. Walk the path in both directions. Does leading space (empty frame in
   front of the player) make the walk feel more purposeful? Which side works better as the path
   bends left and then right?
4. **Squint test on every view.** Set Squint to about 3 and press C through all views. Write down
   any view where you can't find the focal point within one second. Fix those first in Stage 3
   (lighting), *not* by adding props.
5. **Find a shot the level designer didn't plan.** Scout for 5 minutes and bookmark (B) the 3 best
   frames. For each one, write its intent in one sentence. If you can't, it's a pretty
   picture, not a shot.
