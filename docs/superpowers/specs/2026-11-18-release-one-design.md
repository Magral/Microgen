# Release one design — families and organism management

Status: preparation, not implemented. User approved stages 1–2 as the first of four releases. Working version label 1.1.0; stable remains 1.0.1. This specification records the approved direction and separates remaining decisions from implementation assumptions.

## Intent and boundaries

Players retain distinct lineages like characters, continue living organisms exactly, and prepare heirs using a compact body-centered interface. A new family cannot overwrite a previous live checkpoint. Basic forms belong only in the new-organism flow. All accumulated permanent data belongs to its family.

First release delivers family isolation, migration/recovery, alive/dead menu navigation, body/stock capacities, basic equipment exchange, capacity discoveries, compact selectors and inherited expansion. The complete infinite organ economy, dismantling, specialization changes and temporary mutation redesign belong to stages 3–4 in release two. Endless stages and boss redesign belong to later releases. Do not label existing finite ranks or current boss victory as those future systems.

## Existing implementation

`core/save_store.gd` owns one flat version-1 profile, verified atomic temporary writes and backup recovery. `main.gd` assumes one `store.profile` and one `checkpoint`; changing the menu currently creates a paused demo simulation. `core/genome_legacy.gd` stores research, traits, imprints, pending rewards and history. Those fields must not disappear during family migration.

`ui/hud.gd` owns one modal; the current home is centered and fullscreen. `ui/touch_scroll.gd` fixes raw touch gestures but new primary screens should not depend on long scrolling. `Build` stores organ kinds/ranks/quality in dictionaries, with a six-organ limit. Equipment cells must become an explicit independent capacity; old checkpoint load must not silently remove an organ when it exceeds a new form's base.

## Approaches

1. Extend the single flat profile with a family registry and active-family projection. Keeps old systems compatible but needs strict ownership boundaries to avoid saving a demo or another family's state.
2. Separate manifest plus a save file per family. Saves only the active lineage; requires atomic multi-file selection/migration and broader test-path changes.
3. Rewrite all simulation/UI code around a new global profile schema. Largest migration risk and unnecessary scope.

Builder recommendation: use a family registry with the existing active profile as an explicit projection, and keep inactive state separate. Avoid storing a second duplicate active checkpoint in the registry. Exact storage implementation must be reviewed against failure-recovery and measured save costs before choosing it; no approach has been represented as a user-selected technical choice.

## User-visible structure

Home: centered title, two compact paged blocks (living organisms and ancestral families), New organism, auxiliary actions and Exit. No unbounded list of families. A selected living organism resumes; a selected ancestral family prepares a descendant; New organism creates a distinct family and then shows base forms.

Organism: large procedural body with capacity cells, a compact family/status summary and three starting stock cells. Select a body/stock cell to open one short choice window with organ image, occupied cells, actual effects and soft form preference. The old long generation list is removed from the main path. Collection/choice windows use short pages and preserve selection on return. Existing legacy discoveries/research remain available without loss and are identified as compatibility data until release-two migration replaces their UI.

Any equipment exchange pauses the simulation and resumes the same run on close. Capacity and occupied cells are shown before confirmation. Free swapping never discards the replaced organ. Save errors leave the current organism, family selection and pending choices recoverable.

Capacity discoveries occur in a run, persist in the owning family and show a short animation/notice of the new tissue chamber. They are not a shop-only upgrade. Exact base capacities, cell costs and discovery rates are provisional builder parameters, to be displayed honestly and tested rather than presented as approved balance.

## Minimal organ records required in release one

Stage-two equipment cannot use the old destructive kind replacement. The first release needs stable per-family organ identity, kind, rank, quality, cell cost and equipped/stock location. It preserves existing values rather than implementing limitless upgrades or new specialization recipes early. Release two expands this foundation into the complete permanent organ economy.

A run must carry its family ID. Saving an old simulation after selecting a different family is rejected; an active-profile projection alone is insufficient. Body view has an explicit live-run versus preparation-preview context; previews are never saved as checkpoints. Inactive registry records and IDs are validated; corruption must not silently turn an inherited family into a blank one.

## Save invariants and migration

- The old profile becomes the first family exactly once; its cores, purchases, discoveries, archived imprints, pending rewards and history remain.
- An unfinished checkpoint remains resumable with position, HP, build, RNG, captured food, pigment and pending rewards.
- An ended-but-uncredited checkpoint must finish its original result flow before a descendant starts.
- Switching family is atomic; failure cannot charge, duplicate, overwrite another family or change in-memory selection.
- Credits and reward tokens remain local to a family; menu previews never become gameplay checkpoints.
- A new family starts independently, while former families stay available.
- No destructive family deletion is part of this release.
- New capacity defaults cannot strand existing equipped organs; migration preserves enough capacity to hold them.

## Decisions requiring Pavel

One live organism per family versus several concurrent lives in the same family is not yet explicit. Several living FAMILIES must be supported either way. If concurrent lives share the same item collection, ownership/reservation rules are required; that cannot be guessed after coding equipment transactions.

## Verification and release gate

Model tests for migration, cross-family isolation, interrupted writes, live/dead selection and duplicate results. Controller tests for save/reopen/switch/resume/create without loss. Native touch tests for both paged family blocks and body/stock pickers, and no-scroll layout checks at actual logical viewport dimensions. Inspect actual screenshots, not only structural tests.

Run the complete existing suite. Profile a ten-minute run and paired native scenes against stable 1.0.1; add a several-family save/switch measurement so new persistence is represented. Preserve package/signing identity and verify the signed APK/version/manifest in CI.

Do not move preparation commits to main while its current workflow publishes automatically. No release until stages 1 and 2 work as a complete player flow and the release gates pass. A plan or new menu alone is not this release.
