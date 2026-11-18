# Release one implementation plan

> Implement inline with superpowers:executing-plans; use one independent review before integration.

**Goal:** Complete roadmap stages 1–2 as the first of four substantial releases.
**Architecture:** Separate family ownership/persistence from the active simulation; use a small pure model for body/stock transactions and compact paged UI views. Retain current save verification and simulation behavior until their replacements are tested.
**Tech stack:** Godot 4.6.3, GDScript, signed Android export.
**Spec:** docs/superpowers/specs/2026-11-18-release-one-design.md

## Global constraints

No release until both stages form a complete flow. No videos. Preserve existing data, signing identity, size/contact/digestion rules and raw-touch fixes. Families own resources; free equipment exchange cannot lose an organ. Three initial stock cells. Exact form capacities and organ cell costs are provisional balance values, not approved facts. Approved ownership rule: one living heir per family; different families can retain separate live saves. A family can be deleted only after an explicit confirmation covering its life and permanent progress.

## Review focus

Old ended-but-uncredited lives, failed writes during family switching, duplicate organ IDs, stock overflow during a multi-organ replacement, and view/demo state accidentally written as a live checkpoint.

## Task 1 — capacity transactions (independent of family lifetime decision)

Create `core/organism_slots.gd`; test `tests/test_organism_slots.gd`.

Interfaces: `validate(state: Dictionary) -> String`, `used_cells(state: Dictionary) -> int`, `move(state: Dictionary, id: String, destination: String, replacements: Array=[]) -> Dictionary`, `expand(state: Dictionary, target: String) -> Dictionary`. Result has `ok`, `error`, `state`; success returns a deep copy, failure leaves input untouched. State has body_capacity/stock_capacity, equipped/stock arrays of distinct IDs with positive integer cell costs. Body consumes cell cost; stock consumes one position per organ.

- [x] Write RED tests: large organ displaces several small organs, insufficient body cells, full stock rollback, duplicate IDs, unknown item, invalid destinations and expansion preserving contents.
- [x] Implement the pure model; run GREEN with no mutation/duplication/loss.
- [x] Include test in headless suite and record a reviewed working checkpoint.

## Task 2 — family repository and compatibility

After the concurrent-life question is settled, define the exact profile/repository schema before code. Keep inactive family state out of active simulation writes. Migrate the old profile once; retain a raw backup and prevent active-checkpoint duplication. RED→GREEN tests for every save invariant in the spec, including atomic switch failure and pending result recovery. Measure writes with several saved families.

## Task 3 — compact home and organism views

Create modular family-home, body and short picker views; root controller supplies state and callbacks. Native tests must exercise actual viewport resizing, paged live/ancestral families, form selection only in new organism, body-cell selection, stock exchange, back/close and save errors. Inspect native captures. Preserve old legacy data without putting the long generation page back on the main path.

## Task 4 — discoveries and run integration

Connect family capacity/stock state to starting/resumed builds and paused in-run swaps. Add discoverable body/stock extensions with permanent family ownership and a compact notice. Keep migrated over-capacity builds intact. Test capture/reward/save-resume/duplicate pickup and family switching. Infinite organ economy and new temporary mutation rules remain release-two work.

## Task 5 — verification and publication

Full suite, review, native visual/input checks, ten-minute paired profile and multi-family save measurement against stable 1.0.1. Only after both stages pass: update version/export/manifest, build signed APK and verify package/certificate/assets. Current main auto-publishes; preparation stays on `release/1.1.0` until the publication workflow is made safe for this release.

## Verified implementation checkpoint

Pavel confirmed one living heir per family, simultaneous lives in different families, and confirmed deletion. Stages 1–2 are implemented: isolated repository and old-save migration; compact paged home/body/stock/legacy views; individual organ identity and transactional swaps; persistent discoverable capacity extensions. Infinite organ economy, new whole-organism mutations, ladder worlds and rebuilt bosses remain releases two–four.

- [x] Family persistence and migration regression tests, including failed writes and active/inactive/last-family deletion.
- [x] Organ/capacity transactions, instance quality/evolution ownership and descendant inheritance tests.
- [x] Full local ci/run_tests.py: 72 commands, exit0, no Godot script/errors; six source-importer tests also pass.
- [x] Native 1280×640/720 layout captures inspected. Raw-touch family paging, deletion cancellation, heir resume and body/stock exchange checked separately.
- [x] Independent review of family/equipment implementation; the important evolution/quality identity finding reproduced and fixed.
- [x] Paired ten-minute simulation and native rendering, final repeated native logs clean; multi-family save/switch measurements recorded in docs/performance/1.1.0.md.
- [x] First signed Android candidate passed CI, package/certificate/version/manifest/hash checked. Final publication build repeats these checks after the late tendril rendering correction.

Publication is gated by the final main-branch workflow tests/export/signature/manifest checks. Android version1.1.0/code110. The preparation branch also builds signed artifacts but cannot publish stable releases. Preserve the existing package/certificate. No physical Android FPS or universal performance improvement is claimed; ten-family writes remain a measurable hitch risk. No videos.
