# Menu input correction — working branch, no release

Pavel reports that both content swiping and scrollbar dragging sometimes stop. Stable remains 1.0.1: small fixes accumulate until a substantial roadmap advance. The preceding working commit centers the home actions without adding a home scroll area.

## Reproduced issues

Native tests on the desktop renderer expose six failures in the old implementation: swiping from a button does not move the list; a second finger cannot drag the scrollbar while the first rests outside; canceled touches can activate a choice; finger reuse and release outside do not reliably start another scroll; rebuilding a menu during a gesture loses scrolling and can activate a choice.

Godot's stock scroll controls consume mouse/pan events. Screen touches depend on its single emulated mouse, while the list contains interactive buttons and decorative controls. The replacement handles ScreenTouch/ScreenDrag directly before that emulation, tracks one gesture owner and leaves physical mouse/wheel/pan input on the native path.

`ui/touch_scroll.gd` is used by the common HUD modal, so generation, genome, development, atlas and help share the correction. It distinguishes taps from drags, cancels choices during movement, restores pressed styles, accepts any touch index, and clears ownership on cancellation, hiding, focus loss and menu retirement. A fresh press of the same index also recovers from a lost release. Scrollbar movement follows its native thumb geometry, and a stationary thumb tap preserves position.

## Verification

`tests/test_scroll_touch.gd` is a displayed-viewport test included in `ci/run_tests.py`. It covers the original failures, pressed feedback/restoration, canceled and outside releases, menu replacement, focus interruption, lost release recovery, thumb taps, second-finger button taps, and physical mouse/wheel compatibility. Code review identified and helped fix thumb jumping and same-index recovery.

The physical Android freeze has not yet been reproduced on a device here. Passing these tests does not establish that every reported freeze has the same cause. Header close buttons are outside this list-specific touch controller; their existing second-finger limitation remains. Content swipes currently follow the finger directly without inertial continuation. No APK, version bump or stable release is part of this correction.

Verification record: complete `ci/run_tests.py` passed all model, simulation, UI, native touch, scroll, home, artwork/cache tests and captures. A final clipping-boundary regression was then reproduced RED and passed GREEN: a short release just outside the list cannot activate a clipped button. Final resource import is clean. Changes remain on `fix/menu-scroll-usability`; main and stable APK are unchanged.
