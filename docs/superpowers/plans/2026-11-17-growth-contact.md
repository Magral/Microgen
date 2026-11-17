# Growth, contact capture and body damage

Goal: early giants become smaller relative to a growing player, contact always captures food quickly with organic animation, attraction unlocks later, bright healing tissue and visible HP damage.

Architecture: body radius grows from22 to96 with level/nutrient mass; camera zoom eases out using actual radius, keeping UI fixed and the same enemies/terrain in world space. Persistent regional giants (fixed radius, identity and position) exist from new-run start; nearby ones activate, distant ones render as silhouettes, resume with saved run. Size ratio determines threat/food, with devour permitting weakened peer targets; large enemies damage smaller player more, flee when outgrown. Soft body compresses through existing corridors without changing generation.

Contact: swept segment from previous to current player position tests real membrane outline (same genome/jelly contour from renderer, headless fallback); all touched remains/pickups latch immediately, including full-HP healing food retained on ground. Captured payloads follow organism and finish in0.45–0.75s; delayed reward exactly once. Magnet upgrade attracts uncaptured matter with growing range; base has no remote pull. Preserve legacy checkpoints.

- Red tests for growth/unchanged foe size, size-tier prey/giants, persistent silhouettes, swept contact capture of all fragments, healing and no full-HP waste, independent simultaneous digestion, attraction upgrades, capture persistence.
- Implement radius/growth and contact handling in simulation, zoom in world/fluid views, feed multiple captured pieces through existing absorption renderer; add actual HP deformation/scars to painter.
- Add bright restorative particles in world and corpse drops, effect feedback; HUD shows body growth and warns on low HP.
- Verify headless/native/render/movie, review, release0.5.0 with original package/signature. No new external dependencies.

User refinement: initial on-screen body doubled by starting camera zoom around3.09 (world radius22, screen radius68). Target screen radius rises toward86 as world body grows to96; same enemies/terrain keep fixed world dimensions. World/fluid transforms preserve HUD/joystick pixel coordinates. Normal fixed middle tier44–48 and regional72–78 giants bridge food-chain progression; boss140 remains apex.

Verification: full local suites pass: core26, simulation131, genome15064, jelly3929, harvest33, absorption8001, growth/contact20 and tissue damage36491 assertions; UI/input/fluid/FX/pigment/native zero failures; importer6 pass. Real12-second engine clip inspected as a contact sheet showing initial enlarged body, accelerated scale change against same giant, and near-death damage. Review fixes verified: actual damaged/breathing/feeding contact shape, returned unneeded healing, legacy internal digestion<=0.65. Legacy harvest tests now assert irreversible fast capture rather than slow contact interruption, per user's corrected requirements. Fixed-size test fixtures keep material conservation independent of generated tier.

Known limitation: soft body retains compact terrain collision to pass original narrow corridors; full physical wall compression not implemented. Physical Android performance and final feel need phone verification.
