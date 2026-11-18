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
	flow.show_body(true);app.show_genome();app.close_modal()
	check(app.stage=="development" and app.sim.paused,"closing legacy returns to paused body")
	flow.confirm_delete(good.family_id());app.close_modal()
	check(app.stage=="menu" and good.family_summaries().size()==1,"closing delete dialog cancels deletion")
	good.clear_test_files();app.queue_free();await process_frame
	print("FAMILY WRITE FAILURE: %d failures"%failures);quit(0 if failures==0 else 1)
