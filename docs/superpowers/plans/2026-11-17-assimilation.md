# Organic assimilation implementation plan

Goal: fragments visibly cross the living membrane and dissolve inside; unique readable infection/four synergy effects; menu exit.
Architecture: keep deterministic gameplay, procedural Godot rendering and original Android identity. Pure absorption geometry maps saved progress through contact/crossing/dissolution and local membrane bulge. After crossing, fragment is internal and follows player until digestion completes. Transient capped combat effects report real triggers; no RNG consumption for decorations.

- [ ] Red tests: physical internal capture follows movement and saves/restores; delayed conserved rewards. Pure pose crosses actual contour, late inclusion inside, bounded triangulatable body. Real synergy/infection trigger events, capped effects and pause expiry. Menu exit present.
- [ ] Implement game/absorption.gd geometry, simulation internal state/effect triggers, organism_painter.gd layered inclusions and deforming membrane. World uses common pose for corpses/live engulf and renders no generic progress ring.
- [ ] game/organic_fx.gd draws organic threads/spore mycelium/chromatic layered waves and motes; infected enemy tissue; mutation and digestion tissue pulse. Integrate events with world, preserve pause and budgets.
- [ ] Add menu exit using existing save/quit behavior. Version0.4.0/code4. Add deterministic engine preview of absorption and combat effects; test headless/native/display, inspect extracted frames, review, build/release and verify APK.

Design choices: translucent microscopic body horror from the user's “Нечто” reference, readable colored living tissues. No image assets or dependencies needed for procedural shape animation. Whole-body membrane absorption; no mouth-only pickup. Visible mutation response is feedback, not a new random upgrade rule.

Scope update from user: cumulative pigment mixing after absorbing colored tissue. core/pigment.gd stores weighted optical density and finite body pigment turnover, with JSON defaults for old saves. Merged corpse payload conserves incoming pigment mass and density. Color is applied to body and clone cytoplasm; incoming tissue shows its own pigment before dissolution. This is an artistic approximation of translucent pigments.

Verification: all local suites pass (core26, simulation131, genome15064, jelly3929, harvest34, absorption8001 assertions; UI/input/fluid/FX/pigment/native zero failures); importer6 pass. Displayed 360-frame real digestion/combat capture inspected as contact sheets. Reviewer findings fixed: omitted engulfed prey stay visible; central fragments do not jump outward at capture; capped remains conserve full pigment density/mass. Menu layout adjusted after screenshot showed exit initially below fold; exit now shares visible row with gallery. UI/native rechecked after layout change. Physical Android performance remains unverified.
