# Aquatic Volume Implementation Plan

> For agentic workers: execute the independent organism, environment and profiling domains, then integrate native verification and review.

**Goal:** Make the world read as water and each amoeba as rounded living tissue while optimizing rendering every release.

**Architecture:** Retain Godot native 2D simulation; use cached static formations, layered particle depth and efficient directional volume geometry. Reuse existing painter/fluid/world interfaces.

**Tech stack:** Godot 4.6 GL compatibility, GDScript, canvas shader.

**Spec:** ../specs/2026-11-17-aquatic-volume-design.md

## Global constraints
- Android offline identity/signature retained; no videos.
- No gameplay collision/attraction/pigment changes.
- Deterministic visual RNG independent of combat; bounded caches and wakes.

## Review focus
- Damaged/strongly deformed geometry remains triangulatable and feeding attached.
- Camera movement changes parallax while pause freezes water time.
- New seed replaces all environment caches, growth zoom does not leave gaps.
- Bright water and highlights retain danger/loot and player readability.
- Richer shaders are measured separately from CPU drawing on software Mesa.

## Tasks
- [x] Organism: implement volume helper and integrate painter; validate all-health geometry and cache bounds, native static renders.
- [x] Environment: enrich cached terrain chunks; test deterministic decoration and unchanged collision/culling.
- [x] Water: replace faint background with visible caustics/haze; layered bounded particles and soft parallax silhouettes, optimize per-frame flow calculation. Test pause, pan/zoom, reset and boundedness.
- [x] Integration: static gameplay/development/jaw/gallery QA, full suite and review.
- [x] Performance: immutable 0.8 baseline and identical-scene 0.9 comparisons; document cost/limits and fix avoidable regressions.
- [ ] Release: 0.9.0/code9, signed APK verification and published download without video.
