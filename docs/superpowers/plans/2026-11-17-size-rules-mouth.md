# Size-based interaction and organic anatomy

Goal: size ratio governs capture HP, pull speed, impact damage and enemy speed; all attraction remains smooth; less geometric tissue, effective directed mouth. User also requires builds without videos.

Core rules: tiny food can be consumed healthy, smaller competitors at high HP, peers at lower HP; slightly larger peers inflict small collision damage, big foes inflict more and swim slower. Ordinary large foes resist all pull; only severely damaged borderline larger targets yield to developed pull. Mouth has a front cone matching facing, adds damage and raises capture threshold, faster frontal digestion. Side membrane absorption remains possible under stricter baseline rules.

- Test pure ratio profiles, monotonic thresholds/speed/impact, no ordinary giant pull, no-position-change in acid-grasp attack, smooth continuous movement, directed mouth advantage; verify save facing.
- Implement core/size_rules.gd; simulation continuous drag/pull rather than position shifts, directional bite, size-driven capture and collision, facing persistence. Keep corpse/loot guaranteed contact capture.
- Simplify permanent anatomy to soft tissue/one subdued nucleus and faint granules; remove hard circles/plates/vesicles inside; organic detailed opening/folds/radula mouth and transient dissolving chunks.
- Remove movie generation, ffmpeg dependency and mp4 release assets; retain native and static rendering verification. Version0.6.0; review/build signed APK with source and change notes.

User refinement: organs must merge into one mutating organism; optimization required because phone lags. Renderer now uses rooted appendages and body-pigment folds, one subdued nucleus, transient chunks. Profiled identical600-frame dense scenes before/after; renderingCPU32.329→18.790ms, nativecalls5464.7→1899.5. These are desktop softwareGL measurements, not AndroidFPS. Fixed rare fragment polygon errors via precomputed valid hulls.

Review fixed size-threshold monotonicity at ratio0.95 and aligned physical/visible mouth heading with resolved movement at walls. SIZE_RULES120assertions pass; mouth23; fragment540valid procedural polygons. Full native/headless/static suite rerun before release. No movie/ffmpeg/mp4 generation or release assets remain.
