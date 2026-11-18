extends SceneTree
const Store=preload("res://core/save_store.gd")
class FailingStore extends "res://core/save_store.gd":
	func _write_tmp(_path: String,_data: String) -> bool:return false
var failures=0
func check(ok: bool,text: String):
	if not ok:failures+=1;push_error(text)
func _initialize():call_deferred("run")
func run():
	var app=load("res://main.tscn").instantiate();root.add_child(app);app.set_process(false);app.sound_enabled=false
	app.store.path="user://test-family-write-failure.json";app.store.clear_test_files();app.store.profile=app.store.defaults()
	var flow=app._lineage();flow.create_family("predator");app.start_run(653)
	app.show_development()
	var good=app.store
	var faulty=FailingStore.new(good.path);faulty.profile=good.profile.duplicate(true);app.store=faulty
	var before=faulty.profile.duplicate(true)
	var organs=app.sim.build.to_dict()
	var value=flow.state();value.body_capacity+=1
	check(not flow.commit_state(value),"failed equipment write is reported")
	check(faulty.profile==before and app.sim.build.to_dict()==organs,"failed equipment write leaves memory and combat unchanged")
	app.sim.events.append({"type":"expansion","target":"body","amount":1,"token":"retry-expansion"})
	check(not app._handle_events(),"failed expansion write is reported")
	check(app.sim.events.size()==1 and faulty.profile==before and app.sim.build.to_dict()==organs,"failed expansion remains pending without partial credit")
	app.store=good
	check(app._handle_events(),"pending expansion can retry after storage recovers")
	check(good.profile.organism.body_capacity==int(before.organism.body_capacity)+1 and app.sim.events.is_empty(),"retry credits expansion exactly once")
	check(good.profile.credited.count("retry-expansion")==1,"expansion has one durable receipt")
	app.sim.reward_queue = [{"token":"cyst-write-retry", "tier":1}]
	app.sim.reward_options = [{"kind":"biomass", "id":"biomass", "quality":1, "amount":40}]
	app.show_reward(false)
	var biomass_before = app.sim.build.biomass
	faulty.profile = good.profile.duplicate(true)
	app.store = faulty
	app.claim_reward(0)
	check(app.stage == "reward" and app.stage_action_error.visible and app.sim.reward_queue.size() == 1 and app.sim.build.biomass == biomass_before, "failed cyst claim keeps the reward visible and restores biomass")
	app.store = good
	app.claim_reward(0)
	check(app.sim.reward_queue.is_empty() and app.sim.build.biomass == biomass_before + 40, "cyst retry pays exactly once")
	flow.show_body(true);app.show_genome();app.close_modal()
	check(app.stage=="development" and app.sim.paused,"closing legacy returns to paused body")
	flow.confirm_delete(good.family_id());app.close_modal()
	check(app.stage=="menu" and good.family_summaries().size()==1,"closing delete dialog cancels deletion")
	app.continue_run()
	app.sim.spawn_enemy(app.sim.player + Vector2(85, 0), "boss")
	app.sim._die(app.sim.enemies.size() - 1, false)
	check(app._handle_events(), "boss clear awards legacy cores before the reward choice")
	app.show_stage_briefing()
	check(app.stage == "boss_reward", "unclaimed reward is shown before the next stage")
	var original_organ = app.sim.boss_reward.organ
	var earned_organium = int(good.profile.organium)
	check(earned_organium >= app.stage_reroll_cost(), "stage clear pays area reroll currency immediately")
	faulty.profile = good.profile.duplicate(true)
	app.store = faulty
	app._reroll_boss_reward()
	check(app.sim.boss_reward.organ == original_organ and not app.sim.boss_reward.get("rerolled", false) and faulty.profile == good.profile, "failed boss reroll keeps both the trophy and currency")
	app._claim_boss_reward(false)
	check(not app.sim.boss_reward.claimed and faulty.profile == good.profile and app.stage_action_error.visible, "failed reward write preserves the choice and shows a visible error")
	app.store = good
	app._reroll_boss_reward()
	app._reroll_boss_reward()
	check(app.sim.boss_reward.organ != original_organ and good.profile.checkpoint.boss_reward.rerolled and int(good.profile.organium) == earned_organium - app.BOSS_REROLL_COST, "boss reroll persists a different trophy and pays once")
	var materials_before = int(good.profile.organ_materials.get("organelle", 0))
	app._claim_boss_reward(false)
	app._claim_boss_reward(false)
	check(good.profile.checkpoint.boss_reward.claimed and int(good.profile.organ_materials.organelle) == materials_before + int(app.sim.boss_reward_materials().organelle), "boss materials and the receipt are written together once")
	app.show_stage_briefing()
	var previous_stage = app.sim.stage_index
	var prepared_seed = app.sim.pending_stage_seed
	faulty.profile = good.profile.duplicate(true)
	app.store = faulty
	app.enter_next_stage()
	check(app.sim.stage_transition and app.sim.stage_index == previous_stage and app.sim.pending_stage_seed == prepared_seed and app.stage_action_error.visible, "failed stage entry preserves the prepared area and shows a visible error")
	app.store = good
	app.enter_next_stage()
	check(app.sim.stage_index == previous_stage + 1 and app.sim.world.seed_value == prepared_seed and int(good.profile.checkpoint.stage_index) == previous_stage + 1, "retry saves and enters the same prepared area")
	app.sim.spawn_enemy(app.sim.player + Vector2(85, 0), "boss")
	app.sim._die(app.sim.enemies.size() - 1, false)
	app.show_stage_briefing()
	var trophy_kind = app.sim.boss_reward.organ
	app._claim_boss_reward(true)
	var saved_body = good.profile.organism
	var trophy_saved = (saved_body.equipped + saved_body.stock + saved_body.reserve).any(func(part): return part.kind == trophy_kind and int(part.quality) == 3)
	check(trophy_saved and good.profile.checkpoint.boss_reward.claimed, "legendary organ and receipt survive as family equipment")
	app.continue_run()
	check(app.stage == "stage_briefing" and app.sim.boss_reward.claimed, "reloading after an organ claim does not offer it again")
	good.clear_test_files();app.queue_free();await process_frame
	print("FAMILY WRITE FAILURE: %d failures"%failures);quit(0 if failures==0 else 1)
