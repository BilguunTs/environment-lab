# Performance

Target: the game holds 60 fps on a mid-range PC.

## Method

`PerfHud.measure(frames)` averages CPU ms, GPU ms, draw calls and primitives over N frames, using the
same sources as the on-screen perf HUD (CPU = viewport CPU render time + `get_frame_setup_time_cpu()`;
GPU = viewport measured GPU render time). `--profile-views` visits every fixed view (Scout skipped),
with grass on then off: settle 30 frames, measure 120, overlays hidden. Grass cost = GPU ms (on) minus
GPU ms (off).

Dev machine: RTX 3070, i7-12700F, **1920x1080**, vsync off. The FPS column is Godot's `TIME_FPS`
monitor, which updates about once a second and lags view changes; trust the ms columns.

## Budgets

- Grass: at most 2.0 ms GPU.
- Whole frame: at most 7.0 ms GPU in the worst named view.

Rationale for "mid-range": 7 ms of GPU on an RTX 3070 is roughly 60 fps (16.7 ms) on a GTX 1660 or an
RTX 3050, which are about 2.3x slower, leaving headroom for CPU and driver costs.

## Result (wireframes on, 1920x1080)

| View | Grass | FPS | CPU ms | GPU ms | Draws | Prims |
|---|---|---:|---:|---:|---:|---:|
| Gameplay | on | 68 | 0.38 | 1.77 | 469 | 366k |
| Gameplay | off | 92 | 0.36 | 1.45 | 453 | 83k |
| Reveal | on | 92 | 0.35 | 1.44 | 394 | 309k |
| Reveal | off | 92 | 0.34 | 1.32 | 381 | 76k |
| Long Lens | on | 258 | 0.25 | 1.30 | 203 | 96k |
| Long Lens | off | 662 | 0.24 | 1.28 | 198 | 19k |
| Path Low | on | 662 | 0.32 | 1.41 | 352 | 291k |
| Path Low | off | 662 | 0.31 | 1.26 | 337 | 40k |
| Forest Gate | on | 662 | 0.29 | 1.43 | 304 | 221k |
| Forest Gate | off | 695 | 0.27 | 1.26 | 292 | 29k |
| Gate Thirds | on | 708 | 0.25 | 1.49 | 260 | 204k |
| Gate Thirds | off | 708 | 0.28 | 1.26 | 249 | 22k |
| Clearing | on | 708 | 0.23 | 1.28 | 141 | 117k |
| Clearing | off | 708 | 0.23 | 1.19 | 134 | 9k |
| Landmark Foot | on | 732 | 0.21 | 1.07 | 73 | 64k |
| Landmark Foot | off | 733 | 0.19 | 1.02 | 70 | 6k |
| Camp | on | 733 | 0.20 | 1.33 | 92 | 73k |
| Camp | off | 733 | 0.19 | 1.12 | 88 | 10k |
| Overview | on | 733 | 0.33 | 1.22 | 269 | 66k |
| Overview | off | 774 | 0.32 | 1.22 | 269 | 66k |

- Worst grass cost: Gameplay, 0.32-0.40 ms GPU (budget 2.0). Next: Camp 0.21, Gate Thirds 0.23.
- Worst whole frame: Gameplay with grass, 1.77-1.82 ms GPU (budget 7.0).
- Both budgets are met with a wide margin, so **nothing was tuned**; grass defaults are unchanged
  (24 blades/m2, fade 25/45).

## Top 3 costs

1. Gameplay (the follow camera sees the most grass and trees): 1.8 ms GPU, 469 draws, 366k prims.
2. Reveal: 1.44 ms GPU, 394 draws, 309k prims.
3. Path Low / Forest Gate: about 1.4 ms GPU, 300-350 draws. Grass is only 0.15-0.2 ms of that; the
   rest is the shared scene (trees, shadows, fog).

Grass is the largest primitive contributor (about 280k of Gameplay's 366k) but cheap per primitive.

## Wireframe finding

`RenderingServer.set_debug_generate_wireframes(true)` (needed for the F2 Wireframe view) was compared
with `--no-wireframes`: the profile tables are the same within noise (Gameplay 1.77 vs 1.82 ms GPU,
Gate Thirds grass cost 0.23 vs 0.24 ms), and startup is 2.26-2.50 s vs 2.23-2.39 s (3 runs each, wall
clock, `--quit`), no measurable difference. It stays on by default; `--no-wireframes` skips it, and F2
Wireframe then draws nothing useful.

## Re-running

```bash
GODOT=/d/softwares/Godot_v4.6-stable_mono_win64/Godot_v4.6-stable_mono_win64_console.exe
"$GODOT" --path . --disable-vsync --resolution 1920x1080 -- --profile-views --quit
# add --no-wireframes after -- to compare
```

It prints the table and writes `screenshots/profile_<datetime>.md`.
