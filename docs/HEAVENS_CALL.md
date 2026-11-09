# Heavens call

A 5-7 minute walking level: a tired cloaked girl climbs a foggy mountain trail (about 700 m at
2 m/s, no sprint, no lantern) to a summit reveal and the title. Mood follows her furthest trail
progress, never time.

## How to run

- Editor: open `scenes/levels/heavens_call.tscn` and press F6.
- Command line, from the project root:

```bash
GODOT=/d/softwares/Godot_v4.6-stable_mono_win64/Godot_v4.6-stable_mono_win64_console.exe
"$GODOT" --path . res://scenes/levels/heavens_call.tscn
```

WASD walks, the mouse orbits the camera. After the title, any key or mouse button quits.

## Capture and profile

Flags go after `--`. Lightning is switched off and the overlays (fade, title) are hidden while
capturing or profiling, so frames are repeatable.

```bash
# PNGs: screenshots/heavens_<view>_<datetime>.png
"$GODOT" --path . res://scenes/levels/heavens_call.tscn -- --capture-views --quit

# GPU profile (120 frames per view after 30 settle frames):
# screenshots/heavens_profile_<datetime>.md
"$GODOT" --path . --resolution 1920x1080 --disable-vsync res://scenes/levels/heavens_call.tscn \
    -- --no-wireframes --profile --quit
```

`--no-wireframes` skips the debug wireframe autoload (see `scripts/debug/debug_boot.gd`).
`HeavensCall.view_names()` and `show_view(name)` are the same views from code.

## Views

| View | Where |
|---|---|
| foot | trail progress 0.02 |
| debris | progress 0.42 |
| eerie | progress 0.72 |
| summit | progress 0.96 |
| wide | the summit sequence at the end of PULLBACK (vista fully open) |
| reveal_early | profile only: REVEAL with the vista's `reveal` at 0.15, when the far ridges and steppe draw as transparent while fading in |

## Profile (1920x1080, RTX 3070, vsync off, `--no-wireframes`)

Budget: 7.0 ms GPU in the worst view. The Grass column is always "on" (the level has no grass
toggle). The FPS column is a stale 1 s monitor; trust the milliseconds.

| View | Grass | FPS | CPU ms | GPU ms | Draws | Prims |
|---|---|---:|---:|---:|---:|---:|
| foot | on | 1 | 0.17 | 1.62 | 48 | 587k |
| debris | on | 90 | 0.21 | 1.51 | 184 | 601k |
| eerie | on | 261 | 0.21 | 1.45 | 162 | 602k |
| summit | on | 261 | 0.19 | 1.48 | 95 | 659k |
| wide | on | 261 | 0.20 | 1.70 | 62 | 606k |
| reveal_early | on | 429 | 0.20 | 1.98 | 67 | 680k |

Worst view: reveal_early at 1.98 ms, about 5 ms under budget. No cost reductions were needed.

## Audio

All 15 `.ogg` files are shipped in `assets/audio/` (wind, strong wind, eerie ambience, 4 gravel and
4 rock footsteps, 3 distant thunders, thunder clap). Sources and licences are in
`assets/audio/CREDITS.md`. A missing file is silent, never an error.

## Manual checks (for you)

1. Play the whole climb once and time it. Target 5-7 minutes (the trail length / 2.0 m/s).
2. Listen to the mix: wind, footsteps on gravel and rock, the eerie stretch, distant thunder
   after the flashes, the clap at the reveal.
3. Watch the summit reveal, the pull-back and the title `Heavens call`.
4. Repaint the grass if you want a different look.
