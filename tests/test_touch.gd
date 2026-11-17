extends SceneTree
var failures = 0
func _initialize(): call_deferred("run")
func tap(button):
	await process_frame
	await process_frame
	var touch = InputEventScreenTouch.new()
	touch.position = button.global_position+button.size/2
	touch.index = 0
	touch.pressed = true
	Input.parse_input_event(touch)
	await process_frame
	touch = touch.duplicate()
	touch.pressed = false
	Input.parse_input_event(touch)
	await process_frame
	await process_frame
func find_button(node,text: String):
	if node is Button and node.text.begins_with(text): return node
	for child in node.get_children():
		var found = find_button(child,text)
		if found!=null: return found
	return null
func check(ok: bool,text: String):
	if not ok:
		failures+=1
		push_error(text)
func run():
	if DisplayServer.get_name()=="headless":
		print("TOUCH: requires displayed viewport; run without --headless")
		quit(2)
		return
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.sound_enabled = false
	scene.store.path = "user://test-touch.json"
	scene.store.profile = scene.store.defaults()
	scene.store.profile.checkpoint = {}
	scene.show_menu()
	await tap(find_button(scene.hud.content,"Новый организм"))
	check(scene.stage=="start","native touch activates start menu")
	if scene.stage=="start":
		await tap(find_button(scene.hud.content,"Начать эволюцию"))
		check(scene.stage=="game","native touch starts game")
		scene.sim.gain_xp(12)
		scene.show_level()
		await tap(find_button(scene.hud.content,"Выбрать"))
		check(scene.sim.pending_levels==0,"native touch selects mutation")
		scene.sim.player = scene.sim.world.colonies[0].pos
		scene.sim.build.biomass = 100
		scene.show_shop()
		await tap(find_button(scene.hud.content,"Купить"))
		check(scene.sim.world.colonies[0].stock[0].sold,"native touch buys shop item")
		scene.resume_game()
		var p = Vector2(250,400)
		var touch = InputEventScreenTouch.new()
		touch.index=0
		touch.position=p
		touch.pressed=true
		Input.parse_input_event(touch)
		await process_frame
		var drag = InputEventScreenDrag.new()
		drag.index=0
		drag.position=p+Vector2(55,0)
		drag.relative=Vector2(55,0)
		Input.parse_input_event(drag)
		await process_frame
		check(scene.movement.x>0.5,"native touch joystick moves")
		touch=touch.duplicate()
		touch.pressed=false
		Input.parse_input_event(touch)
		await process_frame
		check(scene.stick_id==-1 and scene.movement==Vector2.ZERO,"native release clears joystick")
	scene.store.clear_test_files()
	print("TOUCH: %d failures" % failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
