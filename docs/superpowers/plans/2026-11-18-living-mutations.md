# Living mutations implementation plan

**Goal:** Make all 18 skills visible as living anatomy; show healing and infection clearly; celebrate cyst rewards and rare tissue.
**Architecture:** Extend immediate-mode painter with optional appearance state (quality/evolution/lash tips/activity). Shared Catalog limb count drives combat and anatomy. Reward reveal is a pausable UI Control driven only by saved options, with no gameplay RNG or early grants.
**Tech stack:** Existing Godot 4.6, GDScript, GL Compatibility; no new dependencies.
**Spec:** Pavel's 18 November request in this conversation and AGENTS.md.

## Constraints
Preserve slow size-first combat, smooth attraction, integrated tissue, offline saves, all modal X buttons, no videos. No new particle nodes per tick. Benchmark immutable 0.10.0 against candidate over ten simulated minutes; desktop measurements are not Android FPS.

## Decisions
Native execution within existing isolated branch. Prior authorization delegates implementation and release choices. Tentacles increase one per rank (1–10), each can hit a target; divide existing total volley damage among limbs to preserve combat timing. Quality colors blue/purple/gold tint each corresponding organ, evolution adds a double living vein. All passive effects have anatomy. Reveal ~2.6 seconds; skip reveals immediately; X defers safely; closing never rerolls or grants a reward.

## Review focus
- Single foe gets full existing volley damage; multiple foes share total, no teleport.
- Healing displays actual restored HP including small continuous regeneration, not overheal.
- Reveals cannot claim early, duplicate grants, consume RNG or block X/replacement.
- All 18 organs and three qualities draw safely at low/high ranks and during attacks.
- Long sessions bound effects/caches and maintain damage-label visibility.

## Tasks
- [x] Test healing aggregation, multi-limb target selection/damage, and reveal outcome stability; observe failures.
- [x] Implement Catalog count, simulation shared volley, healing numbers; update numerical text.
- [x] Implement living anatomy/rarity/attack anchoring, explicit hostile infections and enzyme indicators, rare fragments.
- [x] Implement cyst reveal and acquisition highlight; animated body preview and quality card frames.
- [x] Run full native suite/screenshots, immutable long-run comparison, review fixes.
- [ ] Update 0.11.0 docs/version, publish signed APK after green CI.

## Verification ledger

RED→GREEN: missing heal popup/multi-limb targeting (8 failures → 0), cyst early claim/reveal (2 → 0), shell half geometry across all tiers/ages (12 → 0), same-volley total damage popup (2 → 0). Native full suite and all-18-skill animated-pose render passed; native screenshots inspected. Six source-importer tests passed.

Fresh reviewer found the shell triangulation bug and delayed multi-hit popup totals. Both received regression tests and fixes. Reveal/X/replacement stability reviewed. Final reward layout keeps rays out of the subtitle. Ten-minute immutable baseline/candidate plus same-checkpoint native and frozen saturated measurements are recorded in docs/performance/0.11.0.md; no overall performance win claimed.

Ruling: Shared volley damage is aggregated by target before applying hit_enemy, preserving actual damage and immediate popup totals while retaining one visual strike per limb. Cosmetic reveal does not consume gameplay RNG. Final device-level performance remains a user check.
