extends SceneTree
var fails = 0
func check(ok: bool,text: String):
	if not ok:
		fails += 1
		push_error(text)
func find_exit(node):
	if node is Button and node.text=="Выход": return node
	for child in node.get_children():
		var found=find_exit(child)
		if found!=null:return found
	return null
func _initialize():
	call_deferred("run")
func run():
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.sound_enabled = false
	await process_frame
	check(scene.stage=="menu", "start menu")
	check(find_exit(scene.hud.content)!=null,"main menu has exit button")
	scene.store.path = "user://test-ui.json"
	scene.store.clear_test_files()
	scene.store.profile = scene.store.defaults()
	scene.start_run(77)
	check(scene.stage=="game", "game starts")
	scene.sim.gain_xp(12)
	scene._process(0.01)
	check(scene.stage=="level", "level-up pauses")
	check(scene.sim.current_offers.size()==3, "level offers")
	var id = scene.sim.current_offers[0]
	scene.choose_mutation(id)
	check(scene.sim.pending_levels==0 and scene.sim.build.rank(id)>0, "choice consumes level")
	check(scene.stage=="game", "game resumes")
	scene.show_pause()
	var elapsed = scene.sim.elapsed
	scene._process(1)
	check(scene.sim.elapsed==elapsed,"modal freezes timer")
	scene.resume_game()
	scene.sim.player = scene.sim.world.colonies[0].pos
	scene.sim.build.biomass = 0
	scene.show_shop()
	scene.buy_shop(0)
	check(not scene.sim.world.colonies[0].stock[0].sold,"no money no purchase")
	scene.sim.build.biomass = 100
	var stock_id = scene.sim.world.colonies[0].stock[0].id
	scene.buy_shop(0)
	check(scene.sim.world.colonies[0].stock[0].sold and scene.sim.build.rank(stock_id)>0,"purchase works")
	var after = scene.sim.build.biomass
	scene.buy_shop(0)
	check(scene.sim.build.biomass==after,"sold item cannot charge twice")
	scene.save_run()
	var cp = scene.store.profile.checkpoint.duplicate(true)
	check(cp.get("seed",0)==77,"checkpoint saved")
	scene.resume_game()
	scene.show_map()
	check(scene.stage=="map","map opens")
	scene._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(scene.stage=="pause","background pauses")
	var proper_path = scene.store.path
	scene.store.path = "user://missing-dir-test/profile.json"
	scene.sim.events.append({"type":"core","token":"retry-reward","amount":3})
	scene._handle_events()
	check(not scene.sim.events.is_empty(),"failed write retains reward event")
	scene.store.path = proper_path
	scene.save_run()
	var retry_cp = scene.store.profile.checkpoint.duplicate(true)
	check(not retry_cp.get("events",[]).is_empty(),"pending reward included in checkpoint")
	scene._handle_events()
	check("retry-reward" in scene.store.profile.credited,"reward recovered after write retry")
	scene.sim.outcome = "victory"
	scene.save_run()
	scene.show_menu()
	scene.continue_run()
	check(scene.stage=="results" and scene.store.profile.checkpoint.is_empty(),"terminal checkpoint settles victory")
	check(scene.store.profile.wins==1,"resumed victory counted once")
	var terminal_cores = scene.store.profile.cores
	var corrupt = FileAccess.open(scene.store.path,FileAccess.WRITE)
	corrupt.store_string("broken")
	corrupt.close()
	scene.store.load_profile()
	scene.show_menu()
	scene.continue_run()
	check(scene.stage=="results" and scene.store.profile.wins==1,"backup of completed run settles once")
	check(scene.store.profile.cores==terminal_cores,"backup completion preserves reward total")
	scene.show_menu()
	var before_gallery = scene.store.profile.duplicate(true)
	scene.show_gallery()
	check(scene.stage=="gallery","gallery opens")
	var gallery_grid = scene.hud.content.get_child(scene.hud.content.get_child_count()-1)
	check(gallery_grid.get_child_count()==12,"twelve procedural specimens")
	scene.save_run()
	check(scene.store.profile==before_gallery,"gallery preserves saved run")
	scene.store.clear_test_files()
	scene.queue_free()
	await process_frame
	print("UI: %d failures" % fails)
	quit(0 if fails==0 else 1)
