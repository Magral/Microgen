# Aquatic depth and living volume, 0.9.0

Pavel wants visibly richer water and environment, and amoebas with convincing volume, using Pathogenic and Spore's cell stage as visual references. Visual quality is first; each release must also contain measured optimization. Existing authorization delegates implementation choices and release preparation.

## Approach

Keep native Godot 2D gameplay and continuous jelly/contact geometry. Create pseudo-3D volume with directional tissue shading, recessed anatomy and wet rim highlights. Full 3D conversion would replace working deformation and increase Android cost; a pile of flat translucent circles would retain the reported flat look. Use bounded gradient geometry and cached environment detail instead.

Water gets a brighter teal/blue depth palette, broad caustic light filaments, deep parallax organic silhouettes, suspended plankton and near lens motes. Body edges and danger cues remain legible. Environment formations gain wet lighting, pores and tissue fibers, with distinct biome palettes. Decoration is noncolliding and seeded independently of gameplay.

## Constraints

Preserve size combat, pigment mixing, wounds, mouth/feeding, builds, save identity, offline Android and no videos. Avoid full-screen screen-texture refraction and per-enemy expensive shader passes. Cache static geometry and bounded textures; use per-layer motion rather than increasing particle count without limit. Measure 0/180/360/600-second scenes against 0.8, plus bounded adversarial stress, distinguish draw CPU from full software frame time and Android FPS.
