extends SceneTree
var fails=0
func check(ok: bool,text: String):
	if not ok:fails+=1;push_error(text)
func _initialize():call_deferred("run")
func run():
	var app=load("res://main.tscn").instantiate();root.add_child(app);app.set_process(false);app.sound_enabled=false
	app.store.path="user://test-foundation-flow.json";app.store.profile=app.store.defaults();app.store.bank(100)
	for id in ["toxic","colony","elastic","sensory","folds","memory","receptive"]:check(app.store.research(id),"research bought once: "+id)
	app.store.select_form("toxic");app.store.toggle_trait("folds");app.store.toggle_trait("receptive");app.store.save_preset("Набор 3")
	app.show_start();await process_frame;await process_frame
	check(app.stage=="start","new generation preparation opens")
	app.start_run(600);check(app.sim.build.rank("acid")==1 and app.sim.build.rank("tentacle")==0,"start applies chosen organism instead of old universal tentacle")
	check(app.sim.inherited_traits==["folds","receptive"],"prepared traits become run mechanics")
	app.sim.elapsed=70;app.sim.build.organs.acid=3;app.sim.combat_stats.damage_dealt=20;app.sim.combat_stats.organs={"acid":{"damage":20,"hits":2,"kills":1}};app.sim.outcome="death"
	app.finish_run();var generation=app.store.profile.legacy.generation
	check(generation==1 and not app.store.profile.legacy.pending.is_empty(),"actual game result yields provenance-bearing inheritance")
	app.finish_run();check(app.store.profile.legacy.generation==1,"repeated results do not award another generation")
	app.show_imprints("results");app.close_modal();check(app.stage=="results" and not app.store.profile.legacy.pending.is_empty(),"X defers inherited reward safely")
	check(app.store.claim_imprint("acid"),"earned organ can be kept")
	app.store.select_imprint("acid");app.start_run(601)
	check(app.sim.build.rank("acid")==3 and app.sim.build.quality("acid")==0,"descendant keeps the family organ rank while old imprint metadata remains compatible")
	app.sim.elapsed=123;app.save_run();var checkpoint=JSON.stringify(app.store.profile.checkpoint)
	app.show_menu();app.show_updates();app.save_run()
	check(JSON.stringify(app.store.profile.checkpoint)==checkpoint,"update screen cannot replace active checkpoint with menu demo")
	app.show_imprints("menu");app.save_run()
	check(JSON.stringify(app.store.profile.checkpoint)==checkpoint,"inheritance screen cannot replace active checkpoint with menu demo")
	app.show_updates();check(app.stage=="updates" and app.update_feed.state.status=="idle","updates never make automatic requests")
	app.close_modal();check(app.stage=="menu","updates close returns to menu")
	app.start_run(602);app.sim.elapsed=70;app.sim.outcome="death";app.sim.build.organs={"acid":3}
	app.sim.combat_stats.damage_dealt=10;app.sim.combat_stats.organs={"acid":{"damage":10}}
	var sample={"id":"acid","name":"Кислота","branch":"adaptation","origin":{"generation":1,"biome":0,"elapsed":70},"recipe":app.sim.player_genome.duplicate(true),"rank":1,"quality":0}
	var queued=app.store.profile.duplicate(true);queued.legacy.pending=[sample];queued.legacy.pending_queue=[]
	for i in range(8):queued.legacy.pending_queue.append([sample.duplicate(true)])
	app.store.write_profile(queued);var old_generation=app.store.profile.legacy.generation
	app.finish_run();check(app.stage=="inherit" and app.store.profile.legacy.generation==old_generation,"full inheritance backlog defers result credit")
	check(app.store.profile.checkpoint.get("outcome","")=="death","waiting result survives application exit in checkpoint")
	app.store.claim_imprint("acid");app._close_imprints()
	check(app.stage=="results" and app.store.profile.legacy.generation==old_generation+1,"completion retries once after freeing inheritance slot")
	var old_id=app.sim.run_id;app.start_run(603)
	check(app.stage=="inherit" and app.sim.run_id==old_id,"new run cannot silently exceed inheritance memory cap")
	var recovery=app.store.profile.duplicate(true)
	var ended=app.sim.snapshot();ended.run_id="recovery-uncredited-life";ended.outcome="death";ended.elapsed=70
	recovery.checkpoint=ended;app.store.write_profile(recovery)
	var prior_generation=app.store.profile.legacy.generation
	app.show_menu();app.store.load_profile();app.store.claim_imprint("acid");app.start_run(604)
	check(app.stage=="results" and app.store.profile.legacy.generation==prior_generation+1,"restart then claim cannot discard uncredited completed life")
	check("recovery-uncredited-life:finished" in app.store.profile.credited and app.store.profile.checkpoint.is_empty(),"recovered result credits once before allowing a new life")
	app.store.clear_test_files();app.queue_free();await process_frame
	print("FOUNDATION FLOW: %d failures"%fails);quit(0 if fails==0 else 1)
