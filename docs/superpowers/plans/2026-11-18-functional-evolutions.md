# Functional living evolutions implementation plan

**Goal:** Implement the three approved living evolutions, starting with the hunting crown, without releasing or changing the app version.
**Architecture:** Keep existing saved evolution IDs/recipes and the 30% organ bonus. Add bounded state to existing enemy dictionaries and simulation checkpoint; anatomy consumes that state. Share eligibility and geometry rules in a small helper.
**Spec:** Approved concepts from this conversation: hunting crown (tentacle+magnet), dissolving mantle (acid+armor), spore womb (infection+metabolism); ROADMAP.md.
**Constraints:** Continuous attraction, size-first combat, boss protection, contact digestion, unified tissue, no videos, no APK/release/main push. Preserve existing recipes and save migrations.

- [x] Add RED tests for crown eligibility, continuous mouth-directed steering, expiry/healing/giant protection; mantle trigger/cooldown; spore charge/one-time burst and JSON persistence.
- [x] Implement helper rules and three bounded simulation behaviors; preserve damage attribution and tissue budget.
- [x] Implement crown collar/roots/sensory combs, mantle folds/contraction, spore chambers/charge, hybrid tint/functional contact effects; exact on-body attack anchors and native screenshots.
- [x] Update recipe/inspector/reward descriptions; baseline legacy evolutions retain their previous numerical effect.
- [x] Full headless/native/touch checks, adversarial geometry/long-run bounds, fresh code review.
- [ ] Save verified changes on a feature branch; no release.

Decisions: mantle activates only on actual close enemy collision, at most every 2s. It creates a local acid patch using existing tissue-limited damage. Spore womb fills only from fully digested infected material, three meals per burst, with no charge from hits or repeated contact. A single enemy meal counts once. Charge is 0–2 between bursts and serialized. Crown selects at most two eligible targets; lashing all other foes remains ordinary damage. Current recipes at organ 6 + passive 3 stay unchanged.

Verification: full native/headless suite passed, including touch and 30 evolving art poses; 10-minute evolved replay and JSON restores passed (max2 holds,42 effects). Fresh reviewer cleared corrected allocation, anchors and cache invalidation. No release.
