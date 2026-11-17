extends SceneTree
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var art=preload("res://game/reward_art.gd")
	for tier in [1,2,3]:
		for side in [-1,1]:
			for age in [0.0,0.7,1.65,2.5]:
				var shell=art.shell(tier,17,age,side)
				check(not Geometry2D.triangulate_polygon(shell).is_empty(),"both cyst lobes must triangulate at every tier/age")
	var app=load("res://main.tscn").instantiate();root.add_child(app);app.set_process(false);app.sound_enabled=false
	app.store.path="user://test-cyst-reveal.json";app.store.profile=app.store.defaults();app.start_run(144)
	app.sim.reward_queue=[{"token":"reveal","tier":3}];app.show_reward()
	var options=app.sim.reward_options.duplicate(true);var rng=app.sim.rng.state
	app.claim_reward(0)
	check(app.sim.reward_queue.size()==1,"reward cannot be claimed during unopened cyst animation")
	var reveal=app.get("reward_reveal")
	check(reveal!=null,"cyst has an animated reveal control")
	if reveal!=null:
		reveal.advance(0.8)
		check(not reveal.complete,"early reveal remains sealed")
		app.close_modal();check(app.sim.reward_queue.size()==1,"X during reveal defers without granting")
		app.open_pending();reveal=app.reward_reveal
		check(app.sim.reward_options==options and app.sim.rng.state==rng,"reveal/reopen never consumes gameplay RNG or rerolls reward")
		reveal.skip();reveal.skip()
		check(reveal.complete,"skip reaches final reveal once")
		app.claim_reward(0);check(app.sim.reward_queue.is_empty(),"revealed reward can be selected exactly once")
	app.store.clear_test_files();app.queue_free();await process_frame
	print("CYST REVEAL: %d failures"%failures);quit(0 if failures==0 else 1)
