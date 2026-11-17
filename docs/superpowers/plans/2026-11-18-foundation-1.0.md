# Foundation 1.0 implementation and release plan

**Goal:** Ship the agreed first playable foundation with living morphologies, build/evolution choices, three starter forms, meaningful persistent genome research/traits/imprints and readable preparation/results. Existing procedural biomes, growth, minimap and minibosses remain; expanded food-chain ecosystem and new scale tiers are future roadmap stages.
**Architecture:** Pure Legacy model + atomic Save operations, immutable per-run loadout snapshot, modular genome UI, existing simulation and organic painter extended with trait feedback. Update checker reads a stable GitHub release manifest; download/install is a clearly labelled browser + Android installer handoff. No silent installation.
**Release gate:** No1.0 publication until all foundation paths, legacy migration/failed-save behavior, native UI/touch/render checks, ten-minute replay and paired profiling, code review, signed Android export pass. Preserve package org.magral.microgen and signing key. No videos.

- [x] Legacy model/research/presets/focus/history/pending imprint and migration tests.
- [x] Run-loadout simulation and visible trait anatomy; honest numerical tradeoffs.
- [x] New generation/genome/results/imprint UI with live preview and fixedX/44pxscroll.
- [x] Explicit update check, stable feed validation and transparent browser install handoff.
- [x] Full headless/native tests, save-resume/atomicity, research progression, ordinary/evolved combat, native snapshots and longrun/performance comparison.
- [x] Review fixes, 1.0 docs/checklist and release workflow stable manifest/signature.
- [ ] Only after all checks publish v1.0.0 APK and verify assets/commit/version/signature.

Runtime trait decisions: elastic response0.13s instead0.20s with +8%collision damage; sensory +160 sensing with −5%speed; folds −20%detached tissue digestion time with −10%received healing; receptive preferred-branch weight1.75 instead1.35 with −5%XP. Two slots, ordinary rank1 imprint, no inherited quality/evolution. Costs finite, initial predator available, migration preserves prior purchases. Agents own disjoint model/UI/updater modules; root integrates simulation/main/workflow and verifies everything.
