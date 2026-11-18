# Release 1.2.0 implementation plan

**Goal:** Implement roadmap stages 3–4: enduring organ development, specializations, recovery by dismantling and run-only mutations.
**Architecture:** Keep organ instances in the family equipment model; add family-owned organium and materials to the active profile; apply mathematically bounded growth to the existing combat build. Keep temporary mutations in the live checkpoint and clear them only when the life ends.
**Tech Stack:** Godot 4.6.3, GDScript, current Android export pipeline.
**Spec:** docs/superpowers/specs/2026-11-18-release-two-design.md

## Implementation and release checkpoint

- Added family-owned organium and tissue counters with zero-value migration defaults.
- Added endless saved organ ranks with a bounded soft-cap for combat math, rising upgrade prices, and visible specialization anatomy.
- Added atomic upgrade/specialize/dismantle transactions in the organism window; organelles from digested remains are saved in batches to reduce profile writes.
- Each organ now has two named specializations with its own effect description, synergy bonus and anatomy motif.
- Reduced organ, mutation and shop cards to core numbers; added a paged Codex for full organ, adaptation, synergy, specialization and evolution descriptions.
- Complete: temporary mutation choices and anatomy markers, overflow review/install/dismantle/archive, old-checkpoint migration, concise cards with a paged Codex, full visual/native input suite, and ten-minute comparative profiling.
- Complete locally: full CI test runner and Godot resource import pass. Android export and signature verification are delegated to the repository's pinned GitHub Actions toolchain because Android SDK/build-tools are absent from this environment.
- Release branch metadata is now 1.2.0/code120. The workflow publishes only tag `v1.2.0`; pushing the branch does not create or replace a stable release.

## Global constraints

- Existing 1.1.0 family saves and live checkpoints migrate without losing organs or resources.
- One living heir remains active per family; family resources never cross families.
- Organ rank has no design maximum; the four rarity grades remain bounded, while all combat values and prices stay finite.
- Organ exchange remains free; specialization and upgrades have a clear family-resource price.
- Dismantling requires explicit confirmation and commits with its material refund atomically.
- Temporary mutations affect the current life only and reset on death.
- Compact menus, touch sizing, persistent family progression, procedural discoveries, no videos.

## Review focus

- Maximum JSON-safe rank/quality, cost overflow and diminishing-return precision.
- Failed saves during upgrade, specialization, dismantle and reward credit.
- Old live checkpoints resumed after migration and then ended in death/victory.
- Same-kind organ instances with different specializations, ranks and qualities.
- Temporary effects removed on every death path while family currency survives.

## Task 1: Unbounded organ math and family materials

**Files:** `core/catalog.gd`, `core/organism_equipment.gd`, `core/build_model.gd`, `core/save_store.gd`.

- Define JSON-safe cap `9007199254740991` for stored organ ranks; rarity stays at four clear grades.
- Define a bounded diminishing-return curve for organ rank and clamp combat multipliers before float overflow.
- Add family-owned `organium` and per-organ materials to defaults/normalization with zero migration defaults.
- Keep existing instance identities and aggregate all equipped instances without silently dropping ranks.

## Task 2: Upgrade, specialization and dismantle transactions

**Files:** `core/organism_equipment.gd`, `ui/organism_flow.gd`, `main.gd`, `ui/organism_view.gd`.

- Add pure transaction APIs `upgrade(state,id,materials)`, `specialize(state,id,specialization,materials)`, and `dismantle(state,id,materials)` returning `{ok,error,state,materials}`.
- Use a monotonic price curve and bounded salvage fraction; preview exact prices/refunds.
- Persist organ changes and live checkpoint together; apply runtime only after successful write.
- Add compact organ tabs/actions and confirmation for dismantling.

## Task 3: Run rewards and persistent salvage

**Files:** `game/simulation.gd`, `main.gd`, `ui/organism_flow.gd`, `core/save_store.gd`.

- Add per-run mutation records and typed family-material discovery events with stable run tokens.
- Present new organs, materials and temporary mutations through concise level/cyst choices.
- Preserve found organs/materials through death and prevent duplicate reward credit on restore.
- Clear temporary mutations on every ended-life path; restore them with an unfinished live checkpoint.

## Task 4: Visual distinction and compact screens

**Files:** `ui/organism_view.gd`, `ui/organism_flow.gd`, `game/organism_painter.gd`, `game/world_view.gd`, `core/build_inspector.gd`.

- Show diminishing-return value, next price, specialization, dismantle refund and active synergy changes.
- Render specialization and temporary mutation as bounded anatomy/effect details.
- Keep page contents bounded regardless of inventory size.

## Task 5: Release integration

**Files:** `README.md`, `RELEASE_NOTES.md`, `ROADMAP.md`, `.github/workflows/android.yml`, `project.godot`, `export_presets.cfg`, performance documentation.

- [x] Update 1.2.0/code120 and workflow release metadata.
- [x] Run the established local verification, native screen review, and profile against immutable 1.1.0 baseline.
- [ ] Push the release branch, wait for GitHub Android export/signature checks, then publish tag v1.2.0 only after they pass.
