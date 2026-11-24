# Microgen — Defold roadmap

## Current baseline

All active game development uses **Defold**. The accepted baseline is Android release **Defold 1.5.7**:

- Release/tag: `defold-1.5.7`
- Baseline commit: `95f1925571010b0b7ee552d387f5e41450c13e1b`
- Project: `prototypes/defold`
- Control device: **Poco X8 Pro**
- Platform: Android ARM64, landscape
- Package: `org.magral.microgen.defold`
- Minimum Android API: 26

Poco X8 Pro is a control device, not the sole target. The objective is a consistent experience across supported Android phones with different screen sizes, aspect ratios, pixel densities and safe areas.

## Released baseline · 1.5.7

- Expanded compact windows in landscape mode.
- Increased text and touch targets in the codex, organ lists, legacy screens and other menus.
- Moved organism summary tabs to the bottom.
- Enlarged the transition map while preserving its proportions.

This release contains targeted interface improvements; it is not a claim that all screens have been verified on all display classes.

## Priority 1 — universal Android interface adaptation

**Goal:** every important screen remains legible, reachable and visually coherent on supported Android phones in landscape orientation.

### Work plan

1. Audit every gameplay screen, menu, overlay and modal window in the Defold 1.5.7 baseline.
2. Document the existing coordinate system, base design area, panel-width adaptation, text fitting and scaling behavior.
3. Check multiple resolutions and aspect ratios, including wide and narrow landscape layouts.
4. Apply safe-area insets consistently so controls and important content avoid cutouts and inaccessible edges.
5. Review font sizes, cards, modal dimensions, buttons and touch targets together; prevent clipping, overlap and undersized controls.
6. Preserve the established Microgen visual language and landscape orientation.
7. Use Poco X8 Pro for hands-on validation and add coverage for other screen proportions through devices and/or emulators.
8. Make small, reviewable changes. Avoid unrelated changes to gameplay rules, balance, simulation or save formats.

### Known audit findings

- The interface already has a 2460×1080 design coordinate area and existing panel-width/text-fitting helpers; a full UI rewrite is not the starting assumption.
- The gameplay GUI has a safe-area calculation, but the current call path applies it to the in-run HUD. Modal windows still need a separate safe-area review.
- Existing smoke checks cover selected menu/modal layouts against the base design area. They do not replace validation across real Android resolutions and aspect ratios.

See [UI adaptation audit](docs/development/ui-adaptation.md).

### Completion criteria

- All major screens and modal windows have been checked at several resolutions and aspect ratios.
- Important controls remain visible and reachable, including near display edges and cutouts.
- Text and cards do not clip or overlap.
- Safe-area insets are handled consistently.
- Touch targets remain practical.
- The interface retains a coherent visual style and landscape orientation.
- Existing gameplay flows and saves continue to work.

## Priority 2 — preserve the released game

Interface work must not regress:
- run continuation and recovery;
- families, legacy and permanent progression;
- organs, adaptations, specializations, mutations and synergies;
- rewards, resources, bosses and stage transitions;
- application updates and save compatibility.

Changes to game logic or save data require a separate reason and targeted regression checks.

## Priority 3 — continue game development

After the universal UI pass, reconcile the next content scope against the current Defold implementation. Long-term directions include:
- more procedural biomes, regions, organisms and ecological interactions;
- additional organs, mutations, evolutions and ability combinations;
- more varied bosses, threats, rewards and stage conditions;
- richer organic body rendering, tissue damage and absorption;
- balance and long-run integrity of runs and meta-progression.

These are development directions, not a promise that every item is already implemented or assigned to a numbered release.

## Rules for every change

- Start from the accepted Defold 1.5.7 baseline unless a newer Defold baseline is explicitly selected.
- Keep the Android landscape experience universal rather than optimizing only for the control device.
- Preserve save compatibility.
- Do not change gameplay rules to solve a presentation-only issue.
- Validate affected screens and flows after each change.
- Do not present desktop profiling as Android frame-rate evidence.
- Organic visual coherence, legibility and touch usability are core quality requirements.
