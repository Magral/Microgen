# Render cost reduction implementation plan

**Goal:** Reduce repeated CPU work in the current living visuals before expanding the ecosystem.
**Architecture:** Preserve simulation and authored visual budgets. Build volume positions with native packed-array transforms; cache exact quantized-normal shading in a bounded cache. If profiling supports it, replace repeated effect trigonometry with equivalent reusable bases.
**Tech stack:** Godot 4.6.3, GDScript, GL compatibility.
**Spec:** ROADMAP.md unchanged visual/optimization requirements and docs/performance/1.0.0.md measured regression.

## Constraints and review focus

- No balance, save format, controls or population-cap changes; no videos.
- Preserve torn/irregular triangulation, pigment, health shading, animated deformation and functional organ counts.
- Cache must distinguish changed palette, phase, light normals and detail, remain bounded, and survive caller mutation via explicit packed-array copies.
- Compare with immutable 1.0 `526922c` using the same replay checkpoints. Desktop results are not Android FPS.
- Work on `perf/volume-fx`; no automatic 1.0 republishing from main.

## Tasks

- [x] Add a regression for repeated lighting reuse plus changing contour, pigment, health, phase/detail and bounded cache; retain an independent reference for original mesh math. Run RED.
- [x] Implement volume packed transforms and exact shading reuse; run GREEN plus volume, tissue, feeding and native art checks.
- [x] Inspect paired timings; retain effect-basis optimization only if needed and verified against original formulas.
- [x] Run full suite and ten-minute/native profile comparison, inspect native snapshots, review the diff, record limits and measured results.
- [ ] Commit and push the isolated improvement branch for a reviewable checkpoint. User steering adds the fullscreen non-scrolling home fix; prepare and verify 1.0.1/code101 before stable publication.

Progress: Baseline profile started from immutable 1.0. Prior 1.0 complete CI was green; this branch begins clean. Current scope is renderer optimization, not a claim that the next ecosystem stage is finished.

User steering: main screen must never scroll and its background must cover the viewport. Add dedicated HUD home layout, keep all actions (including pending/continue/exit), verify fit at 1280×720, 1600×720 and 1280×640, and native touch. No new dependency or image asset is required.

Review: independent read-only review found two issues and both were fixed: use complete cache keys rather than 32-bit hash identity (concrete collision RED→GREEN), and resize logical viewport in layout tests. No remaining reported blockers or minors. Native home screenshot inspected at 1280×640 with both optional actions visible. Repeated lighting tests, original mesh/color reference, 354162 volume assertions and native touch are green. Optional effect-basis work is deferred: this correction remains scoped to menu layout and volume computation; mixed timing results are documented without claiming overall speedup.

Verification: complete ci/run_tests.py exit0, zero SCRIPT ERROR/ERROR; six importer tests pass; native home/touch/art/cache and 13 captures pass. Baseline and final native profile logs have no script errors; the 10-minute replay has matching checkpoint kills and bounded counters. Final publication gate remains signed Android CI.
