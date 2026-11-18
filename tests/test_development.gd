extends SceneTree
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func inspect_readability(node):
	if node is Label and node.text!="": check(node.get_theme_font_size("font_size")>=20,"body text is readable: "+node.text.left(30))
	if node is Button: check(node.get_theme_font_size("font_size")>=(20 if node.get_meta("compact_action",false) else 24),"button text is readable")
	for child in node.get_children(): inspect_readability(child)
func find_text(node,needle):
	if node is Label and needle in node.text: return true
	for child in node.get_children():
		if find_text(child,needle): return true
	return false
func check_action_bounds(content,prefix):
	var scroll=content.get_parent().get_parent()
	for child in content.find_children("*","Button",true,false):
		if child.text.begins_with(prefix):
			check(scroll.get_global_rect().encloses(child.get_global_rect()),prefix+" action stays above fold")
func _initialize(): call_deferred("run")
func run():
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.sound_enabled = false
	scene.store.path = "user://test-development.json"
	scene.store.profile = scene.store.defaults()
	scene.start_run(732)
	check(scene.hud.get("build_button") is Button,"game HUD has development button")
	check(scene.hud.get("slots")==null and scene.hud.get("synergy_label")==null,"bottom build text removed permanently")
	check(scene.has_method("show_development"),"development window exists")
	await process_frame
	check(not scene.hud.map_button.get_global_rect().intersects(scene.hud.build_button.get_global_rect()),"larger HUD action buttons do not overlap")
	check(not scene.hud.stats.get_global_rect().intersects(scene.hud.message.get_global_rect()),"larger HUD stats do not overlap transient message")
	if scene.has_method("show_development"):
		var key=InputEventKey.new()
		key.keycode=KEY_B
		key.pressed=true
		scene._input(key)
		check(scene.stage=="development" and scene.sim.paused,"development pauses game")
		await process_frame
		inspect_readability(scene.hud.content)
		check(find_text(scene.hud.content,"Тело"),"body shows actual cell budget")
		check(scene.hud.stats.get_theme_font_size("font_size")>=22,"HUD stats enlarged")
		check(scene.hud.scroll_container==null,"organism management has no long scroll")
		for button in scene.hud.content.find_children("*","Button",true,false):
			check(scene.get_viewport_rect().encloses(button.get_global_rect()),"organism actions fit without scrolling")
		var old = scene.sim.elapsed
		scene._process(1)
		check(scene.sim.elapsed==old,"development freezes elapsed time")
		scene._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		check(scene.stage=="game" and not scene.sim.paused,"Android back closes development")
		await process_frame
		scene.stick_id=0
		scene.movement=Vector2.RIGHT
		var touch=InputEventScreenTouch.new()
		touch.index=1
		touch.position=scene.hud.build_button.get_global_rect().get_center()
		touch.pressed=true
		scene._input(touch)
		check(scene.button_touch_id==1 and scene.stick_id==0,"second finger reserves development HUD button")
		touch.pressed=false
		scene._input(touch)
		check(scene.stage=="development" and scene.stick_id==-1,"second finger opens build and clears joystick")
		scene.close_development()
		scene.show_pause()
		scene.show_development()
		scene.close_development()
		check(scene.stage=="pause" and scene.sim.paused,"development returns to pause origin")
		scene.resume_game()
		scene.sim.gain_xp(12)
		scene.show_level()
		await process_frame
		await process_frame
		inspect_readability(scene.hud.content)
		check_action_bounds(scene.hud.content,"Выбрать")
		var offers=scene.sim.current_offers.duplicate()
		scene.show_development()
		check(scene.stage=="level" and scene.sim.current_offers==offers,"development cannot discard pending level context")
		scene.resume_game()
		scene.sim.pending_levels=0
		scene.resume_game()
		scene.sim.player=scene.sim.world.colonies[0].pos
		scene.show_shop()
		await process_frame
		await process_frame
		inspect_readability(scene.hud.content)
		check_action_bounds(scene.hud.content,"Купить")
		scene.show_development()
		check(scene.stage=="shop","development preserves shop context")
		scene.show_replacement("acid","shop",1)
		scene.show_development()
		check(scene.stage=="replace" and scene.replacement_id=="acid" and scene.replacement_stock==1,"development preserves replacement context")
		scene.resume_game()
		scene.hud.game_visible(false)
		scene.hud.game_visible(true)
		check(scene.hud.get("slots")==null and scene.hud.get("synergy_label")==null,"game visibility cannot revive bottom text")
	scene.store.clear_test_files()
	scene.queue_free()
	await process_frame
	print("DEVELOPMENT: %d failures" % failures)
	quit(0 if failures==0 else 1)
