# Microgen · Defold

**Microgen** — Android roguelike auto-battler about the evolution of an amoeba in a procedural micro-world. The player steers the organism with one finger from anywhere on the screen; attacks are automatic. Growth, organs, mutations, pigments, tissue damage and absorption shape both the organism and its build.

## Project baseline

- **Engine:** Defold
- **Current development baseline:** [Defold 1.5.7 release](https://github.com/Magral/Microgen/releases/tag/defold-1.5.7)
- **Baseline commit:** `95f1925571010b0b7ee552d387f5e41450c13e1b`
- **Project directory:** `prototypes/defold`
- **Platform:** Android, ARM64 (`arm64-v8a`)
- **Package:** `org.magral.microgen.defold`
- **Android minimum API:** 26
- **Orientation:** landscape
- **Build/version code:** 157
- **Control device:** Poco X8 Pro

The Poco X8 Pro is the reference device for hands-on checks, not the only target device. The goal is broad compatibility with supported Android phones across different resolutions, aspect ratios, pixel densities and display safe areas.

## Current release · 1.5.7

The Defold 1.5.7 release includes:
- Wider compact windows in landscape mode.
- Larger text and touch targets in the codex, organ lists, legacy screens and other menus.
- Organism summary tabs moved to the bottom to make room for the title and cards.
- A larger transition map that preserves its proportions.

These improvements do not yet mean that every screen has been validated across all Android display classes. Universal interface adaptation is the next development priority.

Release notes: [Defold 1.5.7](prototypes/defold/RELEASE_NOTES.md) · [All releases](https://github.com/Magral/Microgen/releases)

## Gameplay and visual direction

- Procedural biomes, organisms, threats, resources and bosses.
- Organs, mutations and synergies that change combat and anatomy.
- DNA, biomass, legacy nuclei and organium as progression resources.
- Smaller organisms can be pulled in and absorbed; comparable organisms resist, while larger ones must be weakened.
- Absorbed tissue contributes to the organism and its pigment palette.
- A living, wet, translucent membrane with a visible core, fibers, pores, vessels, deformation, wounds and organic recovery.
- On death, tissue fragments retain their original colors and material character; rejoining restores the organism's silhouette.

The visual identity is part of the game design: organic tissue should remain cohesive and readable. Generic white geometric debris is not an acceptable substitute for tissue fragments.

## Build and open the project

1. Install Defold Editor.
2. Open `prototypes/defold/game.project`.
3. Use the project's Android export settings and build workflows.

The Android package settings are maintained in `prototypes/defold/game.project`. Current values include a 2460×1080 design area, immersive mode, landscape orientation, package `org.magral.microgen.defold`, version code 157 and minimum Android API 26.

## Documentation

- [ROADMAP.md](ROADMAP.md) — active priorities and completion criteria.
- [RELEASE_NOTES.md](RELEASE_NOTES.md) — current release summary.
- [CHANGELOG.md](CHANGELOG.md) — project change history.
- [prototypes/defold/RELEASE_NOTES.md](prototypes/defold/RELEASE_NOTES.md) — release-specific Defold notes.
- [docs/development/ui-adaptation.md](docs/development/ui-adaptation.md) — interface audit and adaptation work.

