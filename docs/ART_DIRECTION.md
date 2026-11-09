# Art direction: Stage 1 blockout

Mood: a cold, quiet northern taiga at the edge of something old. The main references are the
restraint of INSIDE and Little Nightmares. The setting is northern Mongolia: larch/spruce forest,
rocky valleys and ovoo cairns.

## Composition of the level

1. **Spawn (foreground).** Large dark trunks and boulders sit at the frame edges. They give the
   viewer scale and push the eye inward.
2. **Path (leading line).** The path is the lightest value on the ground and bends in an S toward
   the clearing. Rocks mark the bends.
3. **View corridor.** No trees stand on the sightline from spawn to the landmark, so the landmark
   is visible from the first frame and pulls the player forward.
4. **Forest gate.** Two big spruces near the end of the path frame the monolith like a doorway.
   This is the threshold beat.
5. **Clearing (destination).** The forest opens out and the ground gets lighter. A ring of
   standing stones surrounds an ember altar. The ember is the only warm colour in the scene, so it
   is the focal point.
6. **Landmark (background).** A dark leaning monolith on a rock outcrop, with an ovoo cairn and a
   blue cloth at its foot. Its tilt is the one strong diagonal in a scene of verticals.
7. **Ridges (far background).** These are huge, simple, faceted forms. Fog pushes them back into
   the sky colour.

## Rules in use

- **Value hierarchy:** the foreground is darkest and each layer gets lighter toward the sky. Fog
  colour always matches the sky.
- **Palette:** desaturated greens and greys. There are two accents: the player's ochre cloak and
  the ember. Don't add more without removing one.
- **Shapes:** big readable shapes come first. Spruce = stacked cones; dead trees = pale verticals
  with a few angled branches.
- **No surface detail yet.** Flat faceted colour only. Detail is priority 6 of 6.

## Light and atmosphere (Stage 3)

Default mood: **Cold Dawn**.
- A low (20°), warm, slightly desaturated sun comes from the north-east, side-back of the main views.
- Cool sky-top fill lights the shadows at a low level (0.35).
- Neutral-cool horizon and fog colour.

Why each choice:
- **Warm light vs cool shadow.** The palette stays restrained, but every lit surface is slightly
  warm and every shadow slightly cool. Remove either and the scene flattens back into grey.
- **Low fill.** Darks have to actually be dark (forest floor, near trunks). Otherwise light pools
  on the path have nothing to read against.
- **Sun off the main view axis.** Pointing straight into the sun turns volumetric fog into a
  white-out. Put the sun to the side-back so the glow sits at the frame edge and shafts cross
  the path diagonally.
- **Volumetric fog is a cool, thin accent.** Its albedo is cool so the haze isn't sepia, and its
  density stays very low (0.004). Shafts should be noticed, not looked through.
- **Mist is patchy and below 2 m.** It reads as weather. A uniform band reads as a dust storm.
- **Motion is quiet.** Sway at the treetops is around 20–30 cm, gusts travel as fronts across the
  forest, the fire flickers, and motes drift with the wind. Movement should be felt rather than
  watched.

## Asset kit (Stage 4)

- **Three tree silhouettes, three jobs.**
  - *Spruce A* (broad cone, 61%) is the mass of the forest.
  - *Spruce B* (tall narrow column with a crooked top, 27%) adds vertical rhythm along the skyline.
  - *Larch* (sparse cone of tufts with sky showing through, 12%, ochre) breaks the dark mass.
    It's the only warm-ish note in the forest, so keep it rare.
- **The landmark gained a hole.** A 1.5 m hole near the top of the monolith. It's tiny at
  distance, but it is the one thing in the scene that is *wrong*, which is the hook for Stage 7
  (light through the hole).
- **Props tell a story without words.**
  - Travellers' cairns at two path bends say "people walked here and paid respect".
  - Cut stumps by the clearing say "people worked here".
  - The fallen log and the dead trees say "nobody has worked here for a long time".
- **Mounds are felt more than seen.** They sit under the forest walls, so the floor stops being a
  table top when you walk. They are not landmarks, so don't light them as such.

## Procedural rules (Stage 5)

Scatter handles *repetition*. The things that carry the composition stay hand-placed: the gate
trees, the foreground framing boulders, the props, the clearing ring and the landmark. The
generator follows the same level-design rules the hand-placed forest did:
- Keep the spawn → landmark sightline open.
- Let the forest open up before the clearing.
- Build dense walls along the path and thin the forest out beyond them.
- Group trees into groves rather than spreading them evenly.

If a seed produces a bad frame, fix the rule (a zone, a hero item), not the seed.

## Paths, landmarks and story (Stage 6)

**The level as a sentence.** You follow a path past travellers' cairns and through a gate of
trees. A line of blue khadag posts leads you to a clearing where an ember is still burning, under
a broken monolith with a hole in it. Off to the side, a fainter trail leads to a camp: a collapsed
ger, a cold hearth, a spirit banner. Nobody lives there any more.

**Hierarchy.**
- *Landmarks:* monolith (26 m) > spirit banner (18 m) > canopy (≤ 16 m).
- *Paths:* the main path is bright and wide; the side trail is darker and narrower.
- *Heat:* the altar ember is warm and the camp hearth is cold. That contrast is the question the
  level asks.

**Story rules.**
- Props carry history, not decoration. Each one should answer *who was here and what did they do*:
  - cairns: travellers paid respect
  - cut stumps: people worked
  - fallen log and dead trees: nobody has worked here for a long time
  - cold hearth and collapsed ger: they left
- One deliberate colour echo: the ger's door frame is the faded ochre of the player's cloak. Keep it the only one.
- Modular walls are always broken somewhere. An intact wall says *maintained*; a gap says *abandoned*.

## The monolith is awake (Stage 7)

**One supernatural idea, one line.** The hole in the monolith glows, and spirits drift from it down
to the altar ember. That answers the level's question, *why is the ember still burning when everyone
left?*: something old feeds it. There are no other spirit sources. One readable line is a story;
spirits everywhere would just be weather.

**Colour: khadag blue, not a new accent.** The spirit light is the pale blue of the khadag cloths
(the sky colour of Tengri), brightened. It reuses an existing colour, so the two-accent rule still holds.
It also sets up a temperature pair: *cold spirit feeds warm ember*, the same contrast as sun against shadow.

**Rules in use.**
- *Spirits breathe, fire flickers.* The hole pulses on a slow, even 6 s cycle. Irregular noise is
  reserved for fire, so the two kinds of light never read as the same thing.
- *Quiet by default.* In Cold Dawn the hole is a small point of light and the stream is faint: you notice it
  rather than watch it. Only the Awakened preset (dusk) lets it carry the frame.
- *A point reads as light only with a halo.* The bare glowing disc looked like paint at telephoto
  distance. A soft halo that ignores depth fog fixed it, because that is what fog does to a real light.
- *Particles are still part of the atmosphere.* Wisps are fogged like any object, so the far half of
  the stream fades into the haze.
- *The hole is now the landmark's focal point.* It is the brightest value in Reveal, Forest Gate and
  Long Lens (0.76–0.86 against sky 0.55–0.61). That gives the monolith the separation that the Stage 2
  notan test said it lacked.
