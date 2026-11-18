extends SceneTree
var failures = 0
func _initialize(): call_deferred("run")
func tap(button,index: int=0):
	if button==null:
		check(false,"requested touch button exists")
		return
	await process_frame
	await process_frame
	var touch = InputEventScreenTouch.new()
	touch.position = button.global_position+button.size/2
	touch.index = index
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
	check(scene.stage=="new_family","native touch activates form choice")
	if scene.stage=="new_family":
		await tap(find_button(scene.hud.content,"Выбрать"))
		check(scene.stage=="start","chosen family opens body preparation")
	if scene.stage=="start":
		await tap(find_button(scene.hud.content,"Начать жизнь"))
		check(scene.stage=="game","native touch starts game")
		# Seed 72 places another colony near colony 0 + (500,0). Keep this
		# overlap deterministic: a fixed offset is not guaranteed to be water.
		scene.store.profile.checkpoint={}
		scene.start_run(72)
		scene.sim.gain_xp(12)
		scene.show_level()
		await tap(find_button(scene.hud.content,"Выбрать"))
		check(scene.sim.pending_levels==0,"native touch selects mutation")
		scene.sim.player = scene.sim.world.colonies[0].pos
		scene.sim.build.biomass = 100
		scene.show_shop()
		await tap(find_button(scene.hud.content,"Купить"))
		check(scene.sim.world.colonies[0].stock[0].sold,"native touch buys shop item")
		scene.sim.player = scene.sim.world.colonies[1].pos
		scene.resume_game()
		await tap(scene.hud.shop_button)
		check(scene.stage=="shop","native colony button consumes its touch")
		for nutrient in scene.sim.world.nutrients:
			scene.sim.player = nutrient.pos
			if scene.sim.nearby_colony()<0: break
		scene.resume_game()
		check(scene.sim.nearby_colony()<0 and not scene.hud.shop_button.visible,"joystick fixture is outside every colony button")
		var size = root.get_visible_rect().size
		for p in [Vector2(250,400),size*Vector2(0.8,0.55),size*Vector2(0.5,0.12),size*Vector2(0.5,0.92),scene.hud.hp_bar.global_position+scene.hud.hp_bar.size/2]:
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
			check(scene.movement.x>0.5,"native joystick moves from %s" % p)
			var second = InputEventScreenTouch.new()
			second.index=1
			second.position=size*Vector2(0.7,0.7)
			second.pressed=true
			Input.parse_input_event(second)
			await process_frame
			check(scene.stick_id==0,"second finger cannot steal joystick")
			second.pressed=false
			Input.parse_input_event(second)
			await process_frame
			check(scene.movement.x>0.5,"second release does not stop first finger")
			touch=touch.duplicate()
			touch.pressed=false
			Input.parse_input_event(touch)
			await process_frame
			check(scene.stick_id==-1 and scene.movement==Vector2.ZERO,"native release clears joystick")
		var held = InputEventScreenTouch.new()
		held.index=0
		held.position=Vector2(400,400)
		held.pressed=true
		Input.parse_input_event(held)
		await process_frame
		check(scene.stick_id==0,"first finger holds joystick before HUD action")
		await tap(scene.hud.pause_button,1)
		held.pressed=false
		Input.parse_input_event(held)
		await process_frame
		check(scene.stage=="pause" and scene.stick_id==-1,"HUD pause takes priority over joystick")
		scene.resume_game()
		held.pressed=true
		Input.parse_input_event(held)
		await process_frame
		await tap(scene.hud.build_button,1)
		held.pressed=false
		Input.parse_input_event(held)
		await process_frame
		check(scene.stage=="development" and scene.sim.paused and scene.stick_id==-1,"second finger opens development while joystick held")
		check(scene.hud.scroll_container==null,"organism management fits without scrolling")
		await tap(find_button(scene.hud.modal,"×"))
		check(scene.stage=="game","native touch closes development")

		scene.sim.reward_queue.append({"token":"native-pending","tier":1})
		scene.hud.update_game(scene.sim)
		held.pressed=true
		Input.parse_input_event(held)
		await process_frame
		await tap(scene.hud.pending_button,1)
		held.pressed=false
		Input.parse_input_event(held)
		await process_frame
		check(scene.stage=="reward" and scene.sim.paused,"second finger opens pending reward while moving")
		await tap(find_button(scene.hud.modal,"×"))
		check(scene.stage=="game" and scene.sim.reward_queue.size()==1,"native close defers pending reward without losing it")

	scene.store.clear_test_files()
	print("TOUCH: %d failures" % failures)
	scene.queue_free()
	await process_frame
	quit(0 if failures==0 else 1)
