# Long-run performance replay

Requires Python 3.12+, Godot 4.6, and (for automatic native rendering) Xorg with the dummy video driver, OpenGL/Mesa, and an available TCP X 11 display. No video is recorded.

Run from repository root:

```sh
python tools/performance/run_profile.py --commit 64a50cb --output /tmp/microgen-baseline --native
python tools/performance/run_profile.py --output /tmp/microgen-current --snapshots /tmp/microgen-baseline --native
```

The runner instruments a disposable project copy. Source files in the supplied checkout are never modified. `--commit` extracts the specified git revision. Omitting it uses the current working tree. Output includes simulation stage JSON, snapshots, native stage JSON, capped-scene JSON, and Xorg logs. Use `--source`, `--godot`, or `--display` for another checkout, binary, or existing display. `--render-only --native --snapshots /tmp/microgen-baseline` skips the long replay when only renderer code changed. Native comparisons use the **same baseline snapshots** via `--snapshots`; each current version's independent long replay is also measured.

The real simulation advances 36,000 steps at 1/60 second: ten simulated minutes, not ten wall-clock minutes. Reports occur at 0, 180, 360, 540, and 600 seconds. Seed 44; six rank 3 organs (tentacle/acid/infection/trail/division/pulse); four rank 3 adaptations (speed/regen/armor/magnet); 10 million HP; boss spawn disabled for profiling only; movement direction changes every 6 simulated seconds. Level pauses are bypassed, and UI/audio event queues are consumed each frame.

Native tests run at 1280×720 with compatibility rendering, uncapped engine frame rate, and requested VSync off. Each 0/180/360/600 baseline snapshot receives 60 warmup frames plus 180 measured draw callbacks while simulation continues at 1/60. Existing baseline checkpoint `impulse` arrays are repaired by the harness to permit continuation. Effects are not serialized by the game's snapshot format and therefore rebuild during warmup. Minimap, HUD, and audio mixing are excluded from this world-renderer benchmark; full gameplay effects remain enabled.

The frozen capped scene uses 28 infected enemies,80 fields,96 remains,600 pickups,200 shots,160 effects (80 damage labels plus 80 toxic colony effects), all near the player, with 20 warmup+60 draw measurements. It is deliberately adversarial and is not representative gameplay. It skips simulation stepping to retain exact counts.

JSON microsecond counters measure GDScript CPU construction, with named simulation and draw stages. New terrain `update_world` CPU is measured separately. Cached terrain nodes retain native draw commands and therefore do not rebuild geometry every frame. One-time scene setup and first-time patch draws are outside warmed measurements. On llvmpipe, rasterization/shader time and driver behavior make absolute frame time unsuitable for a desktop or mobile FPS promise. Compare same-machine CPU measurements; inspect logs for errors before accepting results.

Water-only fixture: `python tools/performance/profile_water.py SOURCE OUTPUT` copies SOURCE into a disposable directory, instruments fluid timings and draws a fixed paused water scene. For a baseline SOURCE use an extracted git archive; the supplied source directory is never modified. Requires Xorg/Godot, no videos.
