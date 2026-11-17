# Liquid Life 0.3.0 implementation plan

Goal: movement from any free screen point, directional jelly anatomy in visibly flowing liquid, and a slower harvest-based combat loop.
User requirements: no left-only control, living membranes respond to movement, microscopic space feels liquid, dead enemies leave parts consumed gradually, fewer and tougher foes.

## Modules and interfaces
- main.gd / ui/hud.gd: unhandled touches anywhere in viewport start joystick; actual buttons keep GUI priority. Passive HUD must not consume touches. Update instructions.
- game/jelly_motion.gd: RefCounted visual spring; init(rest_angle), step(dt, actual_velocity), deform_point(p,phase), deform_points(points,phase), angle_delta(). Substeps and bounded strain; no gameplay RNG/collision changes.
- game/organism_painter.gd: optional JellyMotion argument; common deformation for membrane, tissues and organ attachment anchors. No per-frame recipe regeneration.
- game/fluid_view.gd + assets/liquid.gdshader: liquid background, coherent suspended particles and bounded wake history. update(dt,sim,viewport_size), emit_wake(world_pos,velocity,radius). Pause freezes effects; no gameplay forces from shader.
- game/world_view.gd: track actual world displacement for player/enemies/clones; prune motion states; draw soft body fragments and absorption progress.
- game/simulation.gd: player_velocity, remains:Array, digesting_id:int; fragment dictionaries with id,pos,vel,r,genome,part,dna,bio,progress (0..1),duration,infected. Enemy.engulf normalized progress. Slow movement with drag, reduced/tougher waves, progressive living absorption, corpse harvest before rewards. Save/restore all progress with safe old-save defaults. Named ENEMY_CAP=28, REMAINS_CAP=96; preserve material value when compacting at cap.

## Tasks and checks
1. Test input at right/top/bottom/passive HUD, outside bounds, release/multitouch, button priority. Observe red; remove restriction and fix passive blockers.
2. Test jelly directional elongation, heading turn, idle local wave, stop overshoot/settling, dt invariance, bounded triangulatable outlines. Observe red, implement spring/deformer, integrate all anatomy.
3. Test fluid vector finiteness/coherence, bounded particles/wakes and pause; render real animation frames for inspection.
4. Test delayed rewards, lingering fragments, interrupted/resumed digestion, progressive prey absorption, material conservation at cap, fewer tougher enemies and player inertia. Update old instant-consumption assumptions rather than weaken assertions. Core/simulation/genome suites stay green.
5. Update 0.3.0/code3 with same package/key; native touch and graphics tests; inspect moving frames/clip, review, push tested source and verify GitHub Actions signed APK/release.

## Execution notes
Fresh clone of Magral/Microgen at d3f24e2, branch fix/free-touch-jelly. Baseline core/simulation/genome/UI pass. Native run locally needs Xorg dummy because xvfb-run is absent; CI provides Xvfb. Independent simulation/tests work may proceed separately from input/rendering with the interfaces above; only the coordinator edits shared render/UI/CI files or commits.

## Verification outcome
Implemented all five tasks. Native displayed tests cover free points on each side, passive health HUD, second-finger ownership/release, and pause with finger 1 while finger 0 holds the joystick. Ignore synthesized mouse presses in joystick handling; GUI retains engine emulation.
Final local checks: core26, simulation131, genome15064, jelly3929, harvest30 assertions; UI/input/fluid/native suites zero failures; six importer tests pass. Real game/gallery frames and 180-frame motion recording render without engine errors. Inspected six motion frames showing local membrane deformation, changing heading, tissue attachment and wake trails. Review found and fixed a regenerating-enemy residual-engulf immunity regression using shared eligibility.
Local graphics use Xorg dummy/llvmpipe; performance on physical Android remains unverified. GitHub Actions builds with original development signing key and publishes APK/source/previews.
