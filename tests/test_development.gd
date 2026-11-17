extends SceneTree
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
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
	if scene.has_method("show_development"):
		var key=InputEventKey.new()
		key.keycode=KEY_B
		key.pressed=true
		scene._input(key)
		check(scene.stage=="development" and scene.sim.paused,"development pauses game")
		await process_frame
		check(scene.hud.content.get_child_count()>10,"development shows growth organs and all synergy cards")
		var scroll=scene.hud.content.get_parent()
		check(scroll is ScrollContainer and scroll.size.y<=root.get_visible_rect().size.y,"development scroll fits screen")
		check(scene.hud.content.size.y>scroll.size.y,"long development content scrolls vertically")
		check(scene.hud.content.size.x<=scroll.size.x,"development cards fit without horizontal scroll")
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
		var offers=scene.sim.current_offers.duplicate()
		scene.show_development()
		check(scene.stage=="level" and scene.sim.current_offers==offers,"development cannot discard pending level context")
		scene.resume_game()
		scene.sim.pending_levels=0
		scene.resume_game()
		scene.sim.player=scene.sim.world.colonies[0].pos
		scene.show_shop()
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
