# Task 9 report (transcribed by controller from the implementer's handback)
Status: DONE. Worst view reveal_early 2.04 ms GPU (budget 7.0). No cost reductions.
Implemented: heavens_call.gd — VIEWS, REVEAL_EARLY, REVEAL_EARLY_SECONDS=2.03, SETTLE_FRAMES=30, PROFILE_FRAMES=120; view_names(); show_view(name) (reset_scene, stop_fade, fade alpha 0; progress views via place_on_trail(p); "wide" = summit.skip_to(PULLBACK)+scrub(PULLBACK_SECONDS); "reveal_early" = skip_to(REVEAL)+scrub(2.03)+vista.reveal=0.15; follow_cam.snap()); _run_command_line() deferred from _ready (--capture-views, --profile, --quit); capture_views(); profile_views() (temporary PerfHud, measure(120), table, writes screenshots/heavens_profile_<datetime>.md); storm.reset()+storm.set_process(false) and "overlay" hidden during capture/profile.
summit_sequence.gd — new scrub(seconds): sets _t, runs _process(0) once, set_process(false); skip_to()/reset() set_process(true).
tests/test_heavens_basics.gd — test_views_exist (five names, show_view each, reveal_early leaves vista.reveal in 0.1..0.2).
docs/HEAVENS_CALL.md — new.
RED: --only=heavens_basics 4 passed 1 failed ("Nonexistent function 'view_names'"). GREEN: --only=heavens 57/0.
Command: "$GODOT" --path . --resolution 1920x1080 --disable-vsync res://scenes/levels/heavens_call.tscn -- --no-wireframes --capture-views --profile --quit
| View | GPU ms | CPU ms | Draws | Prims |
|---|---:|---:|---:|---:|
| foot | 1.60 | 0.17 | 49 | 587k |
| debris | 1.51 | 0.22 | 184 | 601k |
| eerie | 1.44 | 0.21 | 162 | 602k |
| summit | 1.48 | 0.19 | 95 | 663k |
| wide | 1.72 | 0.20 | 62 | 606k |
| reveal_early | 2.04 | 0.20 | 67 | 685k |
(Grass column always "on" — vestigial; FPS column stale.)
Captures: screenshots/heavens_<view>_2026-11-08T18-38-19.png — foot (warm gravel, light haze, cliff left, drop right), debris (blue-grey, trail between slopes), eerie (greyest/flattest), summit (rim, golden grass, 3 ovoos, warm light), wide (mist sea, ridges, girl a speck). No fade/title/flash visible.
Suites: windowed 155/0/0; headless 132 passed, 23 skipped (value_probe did not flake).
Deviations: added scrub() to SummitSequence; show_view synchronous (callers wait settle frames); storm disabled for the whole capture/profile run.
