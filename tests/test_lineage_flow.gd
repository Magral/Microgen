extends SceneTree
const Equipment=preload("res://core/organism_equipment.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func find_button(node,text: String):
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var result=find_button(child,text)
		if result!=null:return result
	return null
func _initialize():call_deferred("run")
func run():
	var app=load("res://main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.sound_enabled=false
	app.store.path="user://test-lineage-flow.json";app.store.clear_test_files();app.store.profile=app.store.defaults()
	app.show_menu();var flow=app._lineage()
	flow.create_family("predator")
	var first=app.store.family_id()
	check(app.stage=="start" and first!="","new family opens compact preparation")
	app.start_run(411)
	check(app.sim.family_id==first and app.sim.build.organ_capacity==6,"live run is bound to selected family capacity")
	var run_id=app.sim.run_id
	app.sim.player=app.sim.world.start+Vector2(15,0);app.save_run()
	var position=app.sim.player
	app.start_run(999)
	check(app.sim.run_id==run_id,"starting again cannot overwrite a living heir")
	app.sim.events.append({"type":"expansion","target":"body","amount":1,"token":"test-body"})
	check(app._handle_events() and app.store.profile.organism.body_capacity==7,"found body chamber is durably owned by family")
	app.sim.events.append({"type":"expansion","target":"body","amount":1,"token":"test-body"})
	app._handle_events()
	check(app.store.profile.organism.body_capacity==7,"same expansion cannot credit twice")
	app.sim.events.append({"type":"expansion","target":"stock","amount":1,"token":"test-stock"});app._handle_events()
	check(app.store.profile.organism.stock_capacity==4,"stock expansion persists independently")
	app.store.credit_once("shared-token",7)
	app.show_development()
	for kind in ["tentacle","acid","division"]:check(flow.award(kind,0),"organ earned without deleting another instance: "+kind)
	app.save_run()
	var value=flow.state()
	var incoming=value.stock.filter(func(part):return part.kind=="division")[0]
	var outgoing=value.equipped.filter(func(part):return part.kind=="devour")[0]
	flow.move(incoming.id,"body",[outgoing.id])
	check(app.sim.build.rank("division")==1 and app.sim.build.rank("devour")==0,"paused exchange updates actual combat build")
	check(app.store.profile.organism.stock.any(func(part):return part.id==outgoing.id),"replaced instance remains in stock")
	check(app.store.profile.checkpoint.build.organs.has("division"),"exchange and live checkpoint commit together")
	app.show_menu();flow.create_family("toxic")
	var second=app.store.family_id()
	check(second!=first and app.store.profile.cores==0,"new family does not inherit another family's currency")
	app.start_run(412)
	check(app.sim.build.rank("acid")>=1 and app.sim.family_id==second,"glandular family starts with its own actual organ")
	app.store.credit_once("shared-token",2)
	check(app.store.profile.cores==2,"reward token ownership is per family")
	app.store.select_family(first)
	var checkpoint=JSON.stringify(app.store.profile.checkpoint)
	check(not app.save_run() and JSON.stringify(app.store.profile.checkpoint)==checkpoint,"stale simulation cannot overwrite selected family's life")
	flow.select_family(first,true)
	check(app.sim.family_id==first and app.sim.player.is_equal_approx(position),"family resumes its own position")
	check(app.sim.build.rank("division")==1 and app.sim.stock_capacity==4,"family resumes swapped organs and expanded stock")
	app.sim.elapsed=125;app.sim.outcome="defeat";app.finish_run()
	check(app.store.profile.checkpoint.is_empty() and app.store.profile.runs==1,"death finishes one life without deleting family")
	check(app.store.profile.organism.body_capacity==7 and app.store.profile.organism.stock_capacity==4,"descendant inherits found chambers")
	flow.show_preparation();app.start_run(413)
	check(app.sim.run_id!=run_id and app.sim.build.rank("division")==1,"new heir starts with preserved equipped organs")
	flow.confirm_delete(second)
	check(app.store.family_summaries().size()==2,"deletion waits for explicit confirmation")
	find_button(app.hud.content,"Удалить семейство").pressed.emit()
	check(app.store.family_summaries().size()==1 and app.store.family_id()==first,"deleting another family preserves current heir")
	flow.confirm_delete(first);find_button(app.hud.content,"Удалить семейство").pressed.emit()
	check(app.store.family_summaries().is_empty() and app.store.profile.checkpoint.is_empty(),"deleting final family returns to new-family state")
	app.store.clear_test_files();app.queue_free();await process_frame
	print("LINEAGE FLOW: %d failures"%failures)
	quit(0 if failures==0 else 1)
