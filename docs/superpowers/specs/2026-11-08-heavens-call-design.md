# Heavens Call: level design

Date: 2026-11-08 · Status: draft for review

## Intent

This is the first real level built with the Environment Forge kit. A lone, exhausted girl climbs a
desolate mountain trail through drifting fog and the remnants of a forgotten past. At the summit
the fog parts on a vast Mongolian wilderness. The camera pulls back to her tiny silhouette, the
screen fades out, and the title **Heavens call** appears.

The user's words: the player should feel *"like they've wandered into a forgotten world, not simply
completed a mountain climb."* She is not discovering a kingdom; she is discovering *"a world that
feels older than memory."* The mood is lonely, haunting and dreamlike, with beauty and dread
together, and *"nothing is ever fully explained."* Elden Ring is a mood reference only. This is
the user's own world, and Mongolian rather than European fantasy.

**The user's guiding rule:** *make the landscape itself the mythology.* Don't overpopulate it with
fantasy objects or obvious supernatural elements. Let the wilderness feel mysterious without
explaining why.

The level is also the real test of `docs/REUSE.md`: can a level be built from the kit without the
playground's tools?

## The experience, beat by beat (decided with the user)

A slow climb of about **5–7 minutes**. The atmosphere builds gradually rather than rushing.

| Stretch | Approx. time | What the player meets |
|---|---|---|
| 1. Ascent | 0–2 min | Quiet, lonely. Heavy wind, footsteps, distant thunder, thick fog. |
| 2. Discovery | 2–4 min | Scattered war debris along the path: broken shields, rusted swords, broken armour. **No bodies.** |
| 3. Eerie | 4–6 min | Stronger wind, distant lightning, shifting fog, subtle eerie ambience. Traces of **travellers** replace the war debris near the top. |
| 4. Summit | 6–7 min | The fog slowly opens on the horizon. The wind surges and a powerful distant thunderclap sounds. The camera pulls back, the screen fades out, and the title appears. |

**The trail's quiet story (user decision):** war debris on the lower trail, then traveller traces
near the top. Whoever came this way, the war came first and the wanderers came later. Nothing
explains either.

**The summit vista (user's description):** the trail opens into a vast Mongolian wilderness.
Endless grasslands, towering mountains and distant valleys disappear beneath an ocean of mist. A
few ancient **ovoos** stand silently against a stormy sky. Thunder rolls across the open steppe,
and the wind moves through **golden grass**.

**The ending (user decision):**
1. At the summit the fog slowly parts.
2. The camera pulls back slowly until she is a tiny silhouette against the horizon.
3. The screen fades out.
4. The title **`Heavens call`** appears centred, exactly that text and capitalisation.

## The girl (user decisions)

- She is the existing cloaked, hooded player figure (`scenes/player/player.tscn`) **without the
  lantern**: no lantern mesh and no lantern light. Fog and storm light are her only light.
- She moves at a **slow, tired pace, about 2 m/s, with no sprint**. The current walk speed is
  3.5 m/s and sprint is 7. The user accepted that some players may find this slow.
- Remove the lantern and sprint per instance in this level (exported settings or overrides). The
  playground's player must keep its lantern, sprint and speeds.

## Sound (user decisions)

The sound should be natural and atmospheric, never cinematic or artificial:
- mountain wind and gusts
- footsteps on gravel and rocky ground
- distant, deep thunder with long echoes
- subtle eerie environmental ambience during stretch 3
- stronger wind and a powerful distant thunderclap at the summit reveal

The soundscape is **sparse, immersive and slightly unsettling**. **No music, no dialogue and no
jump scares.** Let moments of silence breathe.

**My calls:**
- **Source.** Use free **CC0** recordings, so there are no licence obligations and no paid
  services. Record each file's source URL and licence in `assets/audio/CREDITS.md`. Audio files go
  under `assets/audio/`, which the project doesn't have yet.
- **When a download fails (user decision).** Try direct-download CC0 sources first. Any sound that
  can't be fetched goes on a short list for the user: what it should be, its rough length, and
  whether it loops or plays once. The user drops those files into `assets/audio/`. The level is
  wired to fixed file names either way, and a missing file is simply silent, never an error. Don't
  synthesise sounds procedurally (it clashes with "natural, never artificial").
- **Footsteps.** Switch between gravel and rock by the ground under her. How the ground type is
  known is the builder's call, for example a per-collider tag or a path-versus-off-path check.
- **Thunder delay.** Thunder lags its lightning flash by a delay that suggests distance (a few
  seconds), with long echoes.

## How the mood builds (my call)

Mood follows **how far she has climbed along the trail, not a clock**, so a slow or wandering
player still gets the whole build-up. Use her furthest progress along the trail, so backtracking
doesn't undo the mood.

Each stretch is a mood key. Between keys, the mood blends smoothly over:
- wind strength, and wind direction (gusts can swing)
- fog density and how the fog moves
- the lightning rate (none in stretches 1–2, rare and distant in 3)
- the volume of each sound layer
- sky and light colour

The `Wind` node from Stage 9 drives grass, scarves and mist as before. The exact key values are
the builder's call, tuned by eye and recorded in a small table in the level's script or
documentation.

**Lightning (my call):** a brief, distant flash of sky and light, never a strike near her, and
never a jump scare. Thunder follows it after a delay.

## Places and pieces

**Built new:**
- **The mountain.** A climbing trail of about **700 m**, sized so a 2 m/s walk with some pausing
  takes 5–7 minutes. It rises to a summit with real elevation gain and is bounded so she can't
  wander off it (cliffs, steep rock, or invisible bounds disguised by fog). Build it from ground
  pieces with collision on layers 1 + 2, per the Stage 9 ground rule, so grass and footsteps work.
  How the terrain is made (Blender kit script, sculpted meshes or modular pieces) is the builder's
  call. The existing `path_ribbon.gd` is flat (2D points), so the trail surface must be made to
  follow the terrain, by draping the ribbon or baking the path into the terrain. Builder's call.
- **War debris props**, made in the existing Blender kit style (`assets/blender/build_kit.py`,
  low-poly, palette materials by name): shattered shields, rusted swords (some planted in the
  ground), broken armour pieces (helmet, breastplate) and a broken spear or pole. Add rusted-metal
  and weathered-wood palette materials if none fit.
- **The summit vista:**
  - a far golden steppe, distant mountain silhouettes and valleys under an ocean of mist
  - a stormy sky
  - **real, painted golden grass** around the summit, a `GrassField` waving in the wind
  - the far steppe reads as endless grass through golden ground colour and distance, not millions
    of blades (my call: painted grass fades out after about 45 m)
- **The summit sequence:**
  - It is triggered when she reaches the summit.
  - Her input is taken away gently: she slows to a stop, with no snap.
  - The fog parts over several seconds, the wind surges, and the thunderclap sounds.
  - The camera pulls back slowly, separate from the gameplay camera.
  - Then the fade and the centred title. After the title shows, any key quits the level.
- **The start:** fade in from black at the foot of the trail, with her already in control.

**Reused from the kit** (my calls):
- `Wind` node, `GrassField` (sparse windswept tufts between rocks on the trail, golden grass at the
  summit), `kit_asset.gd` collision, fog and mist, and the gameplay follow camera.
- **Ovoos** built from the kit's `prop_cairn` and `prop_khadag_post`: stone cairns with weathered
  blue scarves snapping in the wind.
- **Traveller traces near the top:** small stone stacks (cairns), a worn scarf, and the kit's
  `prop_fire_ring`.
- Rocks and boulders from the kit.
- **Not used:** the playground's monolith glow, spirit particles and other supernatural effects.

## Where it lives (user decision and my calls)

- A new scene in this project. My call on the path: `scenes/levels/heavens_call.tscn`, plus a
  level script under `scripts/levels/`.
- **Built per `docs/REUSE.md`.** It doesn't use the playground's dev panel, presets, Compare or
  debug tools. Any gap or error found in `REUSE.md` while building is fixed in the doc.
- `project.godot`'s main scene stays the playground (my call). The level runs with F6 in the editor
  or from the command line with the scene path. Document both in the README.
- **Validation hooks (my call):** a few named viewpoints for `--capture-views`-style captures
  (trail foot, debris stretch, eerie stretch, summit, and the final wide shot). This needs a small,
  level-local capture command rather than the playground's. Also add automated tests in the
  existing runner style for:
  - player speed: no sprint, about 2 m/s
  - no lantern
  - trail length and walking time within 5–7 minutes at walk speed
  - mood driven by progress
  - the summit trigger reaching the title
  - the title text

## Builder-check answers (my calls)

- **Fog, mist and sky.** `REUSE.md` doesn't cover the playground's `WorldEnvironment`, volumetric
  fog, `Mist` FogVolume, mist drift and sky shader. The builder may copy that setup out of
  `scenes/playground.tscn` and `scripts/playground.gd` into the level, without the dev-panel
  plumbing, and adds a short "fog, mist and sky" section to `REUSE.md` describing it.
- **Camera.** Keep the follow camera's orbit (mouse and keys) but limit its pitch range. Props on
  the trail must read from any side.
- **Slopes.** Every walkable slope stays under the player's 45° floor angle.
- **Grass.** Use several `GrassField`s sized to the trail sections and the summit, not one
  700 m field. Start masks may be generated by a one-off script, as `tools/make_starter_grass.gd`
  does; the user can repaint them.
- **Quit after the title.** "Any key" means any key press or mouse button after the title has
  shown. Add no new input actions beyond what this needs.

## Constraints

- Godot 4.6, Forward+, GDScript, in the existing code style. No paid services or third-party
  plugins (`main.md`).
- **Performance:** the Stage 9 budget holds. 60 fps on a mid-range PC, proxied as ≤ 7 ms GPU on
  the RTX 3070 at 1920×1080 in the worst spot. The summit vista is the risk: keep it cheap
  (impostors, silhouettes, fog) and measure it.
- The project is not a git repo. Use the same snapshot and ledger practice as Stages 8 and 9.

## Anti-goals (fail even if it technically works)

- Fantasy clutter, or obvious supernatural elements or explanations (the user's guiding rule).
- Music, dialogue or jump scares, or thunder and lightning that startle rather than unsettle.
- A rushed pace, or a reveal that pops instead of slowly opening.
- Bodies or gore among the war debris.
- A vista that looks like a small diorama rather than an endless world.

## Non-goals

- Combat, enemies, NPCs, collectibles, objectives or a HUD.
- A menu, save system, checkpoints or restart flow beyond "any key quits after the title".
- Guiding wind (still atmosphere only, from Stage 9).
- Grass bending around the player, flowers or more grass types.
- Explaining the war, the travellers or the world.

## Left to the builder

- Trail layout (switchbacks, ledges, chokepoints) and how the debris and traces are staged along
  it, within the beats and lengths above.
- How the terrain, the vista and the mist sea are made, within the performance budget.
- Mood key values, blend curves and lightning timing, tuned by eye.
- Which CC0 recordings to use, and how ground type selects the footstep set.
- Summit sequence timings (fog opening, pull-back length, fade and title holds), within "slow".
- Test breakdown and the capture viewpoints' exact framing.
