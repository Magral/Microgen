# Defold UI adaptation — audit and work plan

## Baseline

Audit target: Defold 1.5.7, tag `defold-1.5.7`, commit `95f1925571010b0b7ee552d387f5e41450c13e1b`. Project directory: `prototypes/defold`.

Android configuration confirmed in `game.project`:
- Design area: 2460×1080.
- Window area: 1230×540.
- Dynamic orientation disabled; the game is landscape.
- Android immersive mode enabled.
- Package: `org.magral.microgen.defold`.
- Minimum Android API: 26.
- Version code: 157.

## Existing adaptation mechanisms

- `main/run/interface.lua` defines the 2460×1080 interface coordinate space.
- Panel width is adapted through the existing `Interface:widen(width)` helper.
- Text fitting uses the existing horizontal and font scaling logic.
- `main/gameplay.gui_script` has a `safe_edges()` helper based on the current window size and safe area.

The current implementation is therefore a starting point for targeted improvements, not a reason to rebuild the interface from scratch.

## Gaps identified

- The safe-area helper is currently used when constructing the in-run HUD.
- Modal windows require a separate review; the HUD safe-area handling does not automatically establish that every modal is safe on every display.
- Existing smoke checks exercise selected menus and modals against the base coordinate area. They are not a substitute for a resolution/aspect-ratio test matrix or hands-on Android checks.

## Work sequence

1. Inventory every screen, modal and overlay, recording its layout and important touch controls.
2. Define a small set of representative landscape test profiles: standard, wide and relatively narrow aspect ratios, plus differing resolutions/densities.
3. Verify coordinate transforms and panel/text scaling at each profile.
4. Extend safe-area handling consistently to HUD, menus, overlays and modal windows.
5. Check clipping, overlap, scroll behavior, button size, touch target and text readability.
6. Validate the main flows on Poco X8 Pro and use emulators or additional devices for other display profiles.
7. Run relevant functional and save-compatibility checks after each change.

## Non-goals for this pass

- No gameplay balance or combat-rule changes.
- No save-format migration unless separately justified.
- No wholesale visual redesign.
- No FPS benchmarking as part of this task; performance checks are separate and should only be added if specifically required.

## Acceptance criteria

- Every major screen and modal has been reviewed on the agreed landscape profiles.
- No critical text or control is clipped, hidden or placed in an unsafe edge region.
- Touch targets are practical and consistent.
- The same screen hierarchy and Microgen visual identity are preserved.
- Core gameplay and save continuation still work.
