# Microgen First Playable Implementation Plan

> Execute inline with executing-plans. Track checks below.

**Goal:** Installable offline Android Godot prototype with two biomes, eight organs, four synergies, shops, a boss and persistent progression.
**Architecture:** Data-driven build model and versioned save store independent of a deterministic world simulation. A Node2D renderer and Control UI consume the simulation; touch and desktop input share a movement vector.
**Tech Stack:** Godot 4.6.3, GDScript, compatibility renderer, prebuilt Android export template.
**Spec:** ../specs/2026-11-17-microworld-design.md

## Global Constraints
- Six combat slots, four adaptations; eight organs/four adaptations in prototype.
- Free three-choice level-up, biomass rerolls and replacements; no internet.
- Short ten-minute test run, two connected biomes, one boss and legacy rewards.
- Preserve discovery and progress across death and app restart; no copied reference art.

## Review Focus
- Full slots and replacement lose dependent synergies and never create rank/currency.
- Insufficient currency and exhausted offers do not charge the player.
- Corrupt/interrupted saves recover previous profile; rewards are idempotent.
- Foreground/background and menus freeze combat without losing touch release.
- Procedural placement leaves mandatory routes usable and caps combat effect counts.

### Task 1: Build rules and persistence
Files: core/catalog.gd, core/build_model.gd, core/save_store.gd; tests/test_core.gd.
Interfaces: Catalog.organs/adaptations/synergies; BuildModel.apply(id,replace_id), offers(rng), active_synergies(); SaveStore.load_profile(), write_profile(profile), bank(amount), unlock(id).
- [x] Write tests for six-slot replacement, ranks, synergy activation/removal, insufficient funds and corruption fallback.
- [x] Run headless tests; observe missing implementation failure.
- [x] Implement data catalogue, model and atomic save/backup.
- [x] Run tests green and commit.

### Task 2: World and combat
Files: game/simulation.gd, game/world_view.gd; tests/test_simulation.gd.
Interfaces: Simulation.new_run(seed), step(delta,direction), snapshot(), restore(data); state for player/enemies/pickups/colonies and events for UI.
- [x] Write seeded-world, movement, pause, combat, boss-reward and snapshot tests; run red.
- [x] Implement bounded world, connected open biomes, absorption, automatic abilities and four concrete synergy effects.
- [x] Verify tests and late-wave soak; commit.

### Task 3: Playable interface
Files: main.gd, main.tscn, ui/hud.gd, assets/icon.svg, project.godot.
Interfaces: UI callbacks to simulation/model transactions; modal state gates simulation.
- [x] Implement Russian start menu, joystick, HUD/minimap, mutation/replacement, shop, map, pause, genome, atlas and results screens.
- [x] Add lifecycle checkpoint/resume and touch-release handling.
- [x] Run Godot import and integration smoke; inspect real rendered frames at mobile aspect ratios.
- [x] Fix blocking issues and commit.

### Task 4: Android delivery
Files: export_presets.cfg, README.md, CHANGELOG.md, build artifacts.
- [x] Obtain matching Android template/SDK, export APK using Godot CLI.
- [x] Verify signature, package, ABI, permissions and archive contents.
- [x] Run full tests and independent final review; address material findings.
- [x] Package source and signed test APK; persist deliverables.

## Execution ledger
Native inline execution: user approved development; no extra approval gate for routine plan details. Fresh standalone project, no existing repository to isolate.
Pre-flight: model/catalogue interfaces feed simulation; snapshot contains model and simulation but profile rewards are banked independently. Runtime must not credit a pickup twice after restoring checkpoint.


## Verification ledger — 17 November 2026
- Task 1 complete: core suite 26 assertions, zero failures. Missing implementation observed first; locking of division made explicit in test fixture.
- Task 2 complete: simulation suite 131 assertions, zero failures; seeded terrain, reachable landmarks across 20 seeds, late-wave caps and all four synergy mechanics.
- Task 3 complete: UI integration suite zero failures; actual displayed input suite covers start menu, start, mutation, shop and joystick motion/release. Headless input dispatch cannot validate Input.parse_input_event, so the touch suite runs on a graphical display.
- Task 4 complete: APK exported, v2/v3 signature verified, org.magral.microgen 0.1.0, min API24, target36, arm64-v8a, no requested permissions. Delivery packaging and persistence performed after verification.
- Independent code review found five issues: native touch support, terminal checkpoint outcome, failed-write rewards, rare pickups at cap, and moving boss marker. Each has a reproduced failure and a passing regression after correction. Audio warnings were eliminated from the headless UI suite by disabling audio in that fixture.
- Ruling: this is a first test build with temporary code-rendered graphics; generated concept sheet remains a visual discussion artifact until the user selects a direction.
- Ruling: 20–30 minute full game remains the subsequent milestone; this approved prototype introduces its boss at ten active minutes.
- Ruling: no existing repository/base branch exists; keep the standalone feature branch and deliver source without remote publication.
- Physical Android device testing is outstanding and is stated in the README and delivery.
