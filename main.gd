extends Node2D
const Legacy=preload("res://core/genome_legacy.gd")
const GenomeView=preload("res://ui/genome_view.gd")
const UpdateFeed=preload("res://core/update_feed.gd")
const UpdateView=preload("res://ui/update_view.gd")
var update_feed
var imprint_origin="menu"
const CystReveal=preload("res://ui/cyst_reveal.gd")
var reward_reveal
const Sim = preload("res://game/simulation.gd")
const View = preload("res://game/world_view.gd")
const HUD = preload("res://ui/hud.gd")
const Save = preload("res://core/save_store.gd")
const Catalog = preload("res://core/catalog.gd")
const Map = preload("res://ui/minimap.gd")
const Genome = preload("res://core/genome.gd")
const Specimen = preload("res://ui/specimen_view.gd")
const Rewards = preload("res://core/rewards.gd")
const Inspector = preload("res://core/build_inspector.gd")
const Development = preload("res://ui/development_view.gd")
const OrganArt = preload("res://ui/organ_art.gd")
const CombatAudio = preload("res://game/audio_bus.gd")
const Painter = preload("res://game/organism_painter.gd")
var store = Save.new()
var sim
var view
var hud
var development_origin = "game"
var stage = "menu"
var movement = Vector2.ZERO
var stick_id = -1
var button_touch_id = -1
var touched_button: Button
var stick_start = Vector2.ZERO
var stick_pos = Vector2.ZERO
var selected_branch = "predator"
var active_shop = -1
var replacement_id = ""
var replacement_origin = ""
var replacement_stock = -1
var deferred_choices = false
var reward_index = -1
var checkpoint_timer = 0.0
var ui_timer = 0.0
var message_timer = 0.0
var capture_path = ""
var capture_mode = ""
var motion_elapsed = 0.0
var organic_preview
var capture_elapsed = 0.0
var sound_enabled = true
var gallery_seed = 1729
var gallery_painter
var combat_audio
var sound_player: AudioStreamPlayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	store.load_profile()
	view = View.new()
	add_child(view)
	hud = HUD.new()
	add_child(hud)
	hud.on_pause = show_pause
	hud.on_map = show_map
	hud.on_shop = show_shop
	hud.on_build = show_development
	hud.on_close = close_modal
	hud.on_pending = open_pending
	sound_player = AudioStreamPlayer.new()
	sound_player.volume_db = -18
	add_child(sound_player)
	update_feed=UpdateFeed.new()
	add_child(update_feed)
	update_feed.state_changed.connect(_update_screen)
	combat_audio = CombatAudio.new()
	add_child(combat_audio)
	show_menu()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="): capture_path = argument.trim_prefix("--capture=")
		if argument.begins_with("--preview="): capture_mode = argument.trim_prefix("--preview=")
	if capture_mode != "":
		if capture_mode=="gallery":
			show_gallery()
			return
		start_run(448221)
		if capture_mode == "game":
			for id in ["acid","spikes","pulse","trail","devour"]: sim.build.apply(id)
			sim.build.biomass = 47
			sim.elapsed = 142
			for i in range(16): sim.spawn_enemy(sim.player+Vector2.from_angle(i*TAU/16)*randf_range(160,440),"hunter" if i%3 else "prey")
			for i in range(18): sim.step(0.016,Vector2.ZERO)
			sim.paused = true
		elif capture_mode == "habitat":
			sim.level=8
			sim.build.organs={"tentacle":3,"acid":3,"devour":3,"barrier":3,"electric":3}
			for y in range(8,30):
				var found=false
				for x in range(10,25):
					var p=Vector2(x+0.5,y+0.5)*110
					if sim.world.walkable(p,40) and not sim.world.walkable(p+Vector2(110,0),40):
						sim.player=p;sim.previous_player=p;found=true;break
				if found:break
			for i in range(6):
				var p=sim.player+Vector2.from_angle(i*TAU/6)*200
				if sim.world.walkable(p,25):sim.spawn_enemy(p,"hunter" if i%2 else "prey")
			sim.effects.clear();sim.paused=true
			hud.message.text="Свет, глубина и живая ткань"
		elif capture_mode == "organic":
			organic_preview=load("res://tests/organic_preview.gd").new()
			organic_preview.setup(sim)
			hud.message.text="Ускоренная демонстрация роста и повреждений"
		elif capture_mode == "motion":
			sim.build.apply("acid")
			sim.spawn_enemy(sim.player+Vector2(90,25),"hunter")
			sim._die(sim.enemies.size()-1,false)
		elif capture_mode=="jaw":
			sim.build.organs={"devour":3}
			sim.spawn_enemy(sim.player+Vector2.from_angle(sim.facing)*26,"prey")
			var prey=sim.enemies.back()
			prey.captured=true
			prey.engulf=0.5
			prey.entry_angle=sim.facing
			prey.entry_distance=36.0
			sim.bite_flash=1.0
			sim.paused=true
		elif capture_mode in ["development","journal"]:
			sim.build.organs={"tentacle":6,"acid":4,"pulse":3}
			sim.build.adaptations={"magnet":3,"armor":2,"regen":1}
			sim.build.qualities={"tentacle":2,"acid":1}
			sim.elapsed=142
			sim.spawn_enemy(sim.player+Vector2(100,0),"hunter")
			var target=sim.enemies.back();target.hp=200;target.max_hp=200;target.tissue_budget=100
			sim.hit_enemy(target,40,"tentacle")
			sim.hurt_player(8,{"kind":"projectile","name":"Плюющая амёба","pos":sim.player+Vector2(200,-80),"id":target.id})
			sim.heal_player(3)
			show_development(capture_mode=="journal")
		elif capture_mode == "rewards":
			sim.build.organs={"tentacle":6,"acid":4,"pulse":3}
			sim.build.adaptations={"magnet":3,"armor":2}
			sim.build.qualities={"tentacle":1}
			sim.reward_queue=[{"token":"preview-reward","tier":2}]
			show_reward()
			reward_reveal.skip()
		elif capture_mode in ["foundation-start","foundation-genome","inheritance"]:
			store.path="user://test-preview-1.0.json";store.profile=store.defaults();store.bank(80)
			for id in ["toxic","colony","sensory","elastic","folds","memory"]:store.research(id)
			store.select_form("toxic");store.toggle_trait("sensory");store.toggle_trait("folds");store.focus_research("receptive")
			sim.elapsed=125;sim.build.organs={"tentacle":4,"acid":3};sim.outcome="death"
			sim.combat_stats.damage_dealt=200;sim.combat_stats.organs={"tentacle":{"damage":150},"acid":{"damage":50}}
			var specimen_profile=store.profile.duplicate(true);Legacy.complete(specimen_profile,sim);store.write_profile(specimen_profile)
			if capture_mode=="inheritance":show_imprints("menu")
			elif capture_mode=="foundation-genome":show_genome()
			else:show_start()
		elif capture_mode == "cyst":
			sim.reward_queue=[{"token":"preview-cyst","tier":3}]
			show_reward()
			reward_reveal.set_process(false);reward_reveal.advance(1.65)
		elif capture_mode == "mutations":
			sim.level=7;sim.hp=76;sim.elapsed=85
			sim.build.organs={"tentacle":6,"infection":5,"electric":4,"devour":6,"acid":4,"division":3}
			sim.build.adaptations={"regen":3,"magnet":4,"metabolism":3,"catalysis":4}
			sim.build.qualities={"tentacle":3,"infection":2,"electric":1,"devour":2,"acid":1,"division":2,"regen":1,"magnet":3,"metabolism":2,"catalysis":3}
			sim.enemies.clear();sim.pickups.clear();sim.effects.clear();sim.cysts.clear()
			for i in range(3):
				sim.spawn_enemy(sim.player+Vector2.from_angle(2.2+i*1.2)*125,"hunter")
				var e=sim.enemies.back();e.infect=2.5;e.enzyme_time=3.0;e.max_hp=400;e.hp=280;e.tissue_budget=1000
			sim.cooldowns={};sim._attack();sim.heal_player(6.5)
			for effect in sim.effects:
				if effect.type=="lash":effect.life=0.25
			view.visual_time=1.2;sim.paused=true
			hud.message.text="Живые мутации · редкость ткани · заражение · лечение"
		elif capture_mode == "feedback":
			sim.level=5;sim.build.organs={"devour":3,"tentacle":3}
			sim.spawn_enemy(sim.player+Vector2(-60,18),"prey")
			sim.enemies.back().hp=sim.enemies.back().max_hp*0.10
			sim._spawn_cyst(sim.player+Vector2(100,60),3,"preview")
			sim.elapsed=85
			sim.hurt_player(9,{"kind":"projectile","name":"Плюющая амёба","pos":sim.player+Vector2(220,-90),"id":17})
			sim.paused=true
			hud.message.text="Направление урона · доступная добыча · ценный сгусток"
		elif capture_mode == "level":
			sim.build.apply("acid")
			sim.gain_xp(12)
			show_level()
		elif capture_mode == "map":
			for i in range(sim.world.cells.size()): sim.explored[i] = true
			show_map()

func _process(dt):
	if hud == null or sim == null: return
	if capture_path!="":
		capture_elapsed += dt
		if capture_elapsed>1.0:
			capture_elapsed = -1000
			_capture.call_deferred()
	if stage=="game" and capture_mode=="organic": organic_preview.step(sim,dt)
	if stage == "game" and capture_mode == "motion":
		motion_elapsed += dt
		var direction = Vector2.ZERO
		if motion_elapsed<1.6: direction = Vector2.RIGHT
		elif motion_elapsed<3.0: direction = Vector2.UP
		elif motion_elapsed<4.2: direction = Vector2.LEFT
		sim.step(dt,direction)
	if stage == "game" and capture_mode == "":
		var keyboard = Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		var dir = keyboard if keyboard.length_squared()>0 else movement
		sim.step(dt,dir)
		_handle_events()
		if sim.outcome!="":
			finish_run()
		elif not deferred_choices and not sim.reward_queue.is_empty():
			show_reward()
		elif not deferred_choices and sim.pending_levels>0:
			show_level()
		checkpoint_timer += dt
		if checkpoint_timer>=12:
			checkpoint_timer = 0
			save_run()
	if combat_audio!=null and sim.get("feedback")!=null:
		combat_audio.consume(sim,sound_enabled and stage=="game")
	ui_timer += dt
	if ui_timer>=0.12:
		ui_timer = 0
		hud.update_game(sim)
	if message_timer>0:
		message_timer -= dt
		if message_timer<=0: hud.message.text = ""
	view.joystick_visible = stick_id != -1 and stage=="game"
	view.joystick_origin = stick_start
	view.joystick_tip = stick_pos

func _input(event):
	# Godot emulates a GUI mouse only for the first finger. Capture a second
	# finger on the HUD buttons while the first keeps the joystick.
	if event is InputEventScreenTouch:
		if not event.pressed and event.index==button_touch_id:
			var button = touched_button
			button_touch_id = -1
			touched_button = null
			get_viewport().set_input_as_handled()
			if is_instance_valid(button) and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position): button.pressed.emit()
			return
		if event.pressed and stage=="game" and stick_id>=0 and event.index!=stick_id:
			for button in [hud.build_button,hud.pause_button,hud.map_button,hud.shop_button,hud.pending_button]:
				if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
					button_touch_id = event.index
					touched_button = button
					get_viewport().set_input_as_handled()
					return
	# Release is observed even if a finger ends over a button or a modal opens.
	if event is InputEventScreenTouch and not event.pressed and event.index == stick_id: clear_stick()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and stick_id == -2: clear_stick()
	if stage=="development" and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE,KEY_B]:
		close_development()
		get_viewport().set_input_as_handled()
		return
	if stage!="game": return
	if event is InputEventScreenDrag and event.index == stick_id: _move_stick(event.position)
	if event is InputEventMouseMotion and stick_id == -2: _move_stick(event.position)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE: show_pause()
		if event.keycode==KEY_M: show_map()
		if event.keycode==KEY_B: show_development()
		if event.keycode==KEY_E and sim.nearby_colony()>=0: show_shop()

func _unhandled_input(event):
	if stage!="game" or stick_id!=-1: return
	if event is InputEventScreenTouch and event.pressed and _stick_region(event.position):
		stick_id = event.index
		stick_start = event.position
		_move_stick(event.position)
	elif event is InputEventMouseButton and event.device != -1 and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and _stick_region(event.position):
		stick_id = -2
		stick_start = event.position
		_move_stick(event.position)

func _stick_region(p: Vector2) -> bool:
	# Buttons consume their GUI events before _unhandled_input. The rest is water.
	return get_viewport_rect().has_point(p)

func _move_stick(p: Vector2):
	var delta = (p-stick_start).limit_length(66)
	stick_pos = stick_start+delta
	movement = delta/66

func clear_stick():
	stick_id = -1
	movement = Vector2.ZERO
	if view!=null: view.joystick_visible = false

func set_stage(value: String):
	if stage=="updates" and value!="updates" and update_feed!=null:update_feed.cancel()
	if value!="reward":reward_reveal=null
	stage = value
	clear_stick()
	if sim!=null: sim.paused = stage!="game"
	view.menu = stage=="menu"

func show_menu():
	set_stage("menu")
	sim = Sim.new()
	sim.new_run(14481)
	sim.paused = true
	view.sim = sim
	hud.game_visible(false)
	var box = hud.open_home()
	box.add_child(hud.label("МИКРОГЕН",46,Color("e2f4ed")))
	box.add_child(hud.label("Маленькая жизнь. Непредсказуемая эволюция.",22,Color("9ce3cf"),true))
	if not store.profile.checkpoint.is_empty(): box.add_child(hud.button("Завершить итоги жизни" if str(store.profile.checkpoint.get("outcome",""))!="" else "Продолжить забег",continue_run,true))
	box.add_child(hud.button("Новый организм",show_start,true))
	var row = hud.row()
	box.add_child(row)
	for entry in [["Геном",show_genome],["Атлас",show_atlas],["Как играть",show_help]]:
		var b = hud.button(entry[0],entry[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	var services=hud.row()
	box.add_child(services)
	var updates=hud.button("Обновления",show_updates)
	updates.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	services.add_child(updates)
	if not store.profile.legacy.pending.is_empty():
		var inheritance=hud.button("Отпечатки · наследие",func():show_imprints("menu"),true)
		inheritance.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		services.add_child(inheritance)
	var footer_actions=hud.row()
	box.add_child(footer_actions)
	var gallery_button=hud.button("Коллекция форм",show_gallery)
	gallery_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer_actions.add_child(gallery_button)
	footer_actions.add_child(hud.button("Выход",exit_game))
	box.add_child(hud.label("Ядра: %d   ·   Забеги: %d   ·   Победы: %d" % [store.profile.cores,store.profile.runs,store.profile.wins],20,Color("ccb2e7"),true))
	box.add_child(hud.label("Версия %s · игра работает без интернета" % ProjectSettings.get_setting("application/config/version","1.0.1"),20,Color("94b5b8"),true))

func exit_game():
	save_run()
	get_tree().quit()

func show_gallery():
	set_stage("gallery")
	hud.game_visible(false)
	var box = hud.open("Жизнь не повторяется", "Тела, мембраны, ядра и органы смешиваются игровым генератором. Лист можно прокручивать.")
	var controls = hud.row()
	box.add_child(controls)
	controls.add_child(hud.button("Смешать ещё",func(): gallery_seed+=982451; show_gallery(),true))
	controls.add_child(hud.button("В меню",show_menu))
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	box.add_child(grid)
	if gallery_painter==null: gallery_painter = Painter.new()
	var rng = RandomNumberGenerator.new()
	rng.seed = gallery_seed
	for i in range(12):
		var specimen = Specimen.new()
		specimen.recipe = Genome.create(gallery_seed,i,"specimen",i%2)
		specimen.number = i+1
		specimen.painter = gallery_painter
		specimen.organs = {}
		var pool = Catalog.ORGANS.keys()
		for j in range(rng.randi_range(2,4)):
			var idx = rng.randi_range(0,pool.size()-1)
			specimen.organs[pool[idx]] = rng.randi_range(1,3)
			pool.remove_at(idx)
		if rng.randf()<0.45: specimen.organs.armor = 1
		if rng.randf()<0.4: specimen.organs.regen = 1
		specimen.custom_minimum_size = Vector2(280,185)
		specimen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(specimen)

func _legacy_preview():
	var specimen=Sim.new()
	specimen.new_run(14481,store.profile.unlocked,store.profile.upgrades,store.profile.legacy.selected_form,Legacy.loadout(store.profile))
	specimen.paused=true
	return specimen

func _legacy_edit(action: String,value="",screen: String="start"):
	var scroll=0 if hud.scroll_container==null else hud.scroll_container.scroll_vertical
	var ok=false
	match action:
		"form":ok=store.select_form(str(value))
		"trait":ok=store.toggle_trait(str(value))
		"imprint":ok=store.select_imprint(str(value))
		"reroll":ok=store.reroll_morphology()
		"research":ok=store.research(str(value))
		"focus":ok=store.focus_research(str(value))
		"upgrade":ok=store.buy_upgrade(str(value))
		"save_preset":ok=store.save_preset("Набор %d" % (int(value)+1))
		"load_preset":ok=store.load_preset(int(value))
	if not ok:message(store.last_error if store.last_error!="" else "Действие сейчас недоступно.",4)
	if screen=="genome":show_genome()
	else:show_start()
	hud.scroll_container.set_deferred("scroll_vertical",scroll)

func show_start():
	set_stage("start")
	var box=hud.open("Новое поколение", "Выбери основу, до двух признаков и один отпечаток. Остальные мутации возникнут в новой жизни.")
	if not store.profile.checkpoint.is_empty():box.add_child(hud.label("Начало новой жизни заменит незавершённый забег. Наследие сохранится.",22,Color("e9b99b"),true))
	GenomeView.populate_start(hud,box,store,_legacy_preview(),{
		"form":func(id):_legacy_edit("form",id),"trait":func(id):_legacy_edit("trait",id),
		"imprint":func(id):_legacy_edit("imprint",id),"reroll":func():_legacy_edit("reroll"),
		"save_preset":func(index):_legacy_edit("save_preset",index),"load_preset":func(index):_legacy_edit("load_preset",index),
		"start":func():start_run(),"imprints":func():show_imprints("start"),"back":show_menu})


func start_run(seed_value: int = -1):
	if str(store.profile.checkpoint.get("outcome",""))!="":
		continue_run()
		return
	if not Legacy.can_start(store.profile):
		show_imprints("start")
		message("Память заполнена. Сохраните один ожидающий отпечаток, чтобы начать новую жизнь.",6)
		return
	if seed_value<0: seed_value = int(Time.get_unix_time_from_system()*1000)%2147483647
	sim = Sim.new()
	sim.new_run(seed_value,store.profile.unlocked,store.profile.upgrades,store.profile.legacy.selected_form,Legacy.loadout(store.profile))
	view.sim = sim
	checkpoint_timer = 0
	deferred_choices = false
	hud.close()
	set_stage("game")
	hud.game_visible(true)
	hud.update_game(sim)
	save_run()
	message("Веди палец по свободному месту.\nКасайся пищи телом; бирюзовые кусочки лечат.",6)

func continue_run():
	var loaded = Sim.new()
	if not loaded.restore(store.profile.checkpoint):
		message("Сохранение забега повреждено. Геном сохранён.",5)
		return
	sim = loaded
	view.sim = sim
	hud.close()
	set_stage("game")
	hud.game_visible(true)
	hud.update_game(sim)
	if sim.outcome!="":
		_handle_events()
		finish_run()
		return
	if not deferred_choices and not sim.reward_queue.is_empty(): show_reward()
	elif not deferred_choices and sim.pending_levels>0: show_level()

func save_run():
	if sim==null or stage not in ["game","pause","development","map","shop","level","reward","replace","save_error"]: return
	var next = store.profile.duplicate(true)
	next.checkpoint = sim.snapshot()
	for id in sim.build.organs:
		if not id in next.discovered: next.discovered.append(id)
	for id in sim.build.adaptations:
		if not id in next.discovered: next.discovered.append(id)
	for id in sim.build.active_synergies():
		if not id in next.synergies: next.synergies.append(id)
	if not store.write_profile(next): message(store.last_error,6)

func _handle_events():
	if sim.events.is_empty(): return
	var next = store.profile.duplicate(true)
	var changed = false
	for event in sim.events:
		if event.type=="message": message(event.text,5)
		elif event.type=="core" and not event.token in next.credited:
			next.credited.append(event.token)
			next.cores += event.amount
			changed = true
			message("Ядра наследия +%d" % event.amount,3)
	if changed:
		next.checkpoint = sim.snapshot()
		if not store.write_profile(next):
			message(store.last_error,6)
			return
	sim.events.clear()

func finish_run():
	var next = store.profile.duplicate(true)
	for event in sim.events:
		if event.type=="core" and not event.token in next.credited:
			next.credited.append(event.token)
			next.cores += event.amount
	var token = sim.run_id+":finished"
	if token not in next.credited:
		if not Legacy.complete(next,sim):
			var deferred=store.profile.duplicate(true)
			deferred.checkpoint=sim.snapshot()
			if not store.write_profile(deferred):
				set_stage("save_error")
				var error_box=hud.open("Не удалось сохранить завершённую жизнь",store.last_error)
				error_box.add_child(hud.button("Повторить",finish_run,true))
				return
			show_imprints("results")
			message("Выберите ожидающий отпечаток. Итоги этой жизни сохранены и будут зачислены после выбора.",6)
			return
		next.credited.append(token)
		next.runs += 1
		if sim.outcome=="victory": next.wins += 1
		next.cores += 2 if sim.outcome=="victory" else (1 if sim.elapsed>=60 else 0)
	next.best = maxf(float(next.best),sim.elapsed)
	next.checkpoint = {}
	for id in sim.build.organs:
		if id not in next.discovered: next.discovered.append(id)
	for id in sim.build.active_synergies():
		if id not in next.synergies: next.synergies.append(id)
	if not store.write_profile(next):
		set_stage("save_error")
		var error_box = hud.open("Не удалось сохранить итоги",store.last_error+". Организм и награды остаются в памяти.",750)
		error_box.add_child(hud.button("Повторить сохранение",finish_run,true))
		return
	sim.events.clear()
	set_stage("results")
	var won = sim.outcome=="victory"
	var box = hud.open("Эволюция состоялась" if won else "Жизнь продолжается в геноме", "Открытия и полученные ядра наследия сохранены.",820)
	box.add_child(hud.label("%02d:%02d  ·  Уровень %d  ·  Поглощено и побеждено: %d" % [int(sim.elapsed)/60,int(sim.elapsed)%60,sim.level,sim.kills],24,Color("9ee0cc"),true))
	box.add_child(hud.label("Ядра наследия: %d\nИзученные синергии: %d/%d" % [store.profile.cores,store.profile.synergies.size(),Catalog.SYNERGIES.size()],22))
	box.add_child(hud.label(Development.combat_summary(sim),21,Color("b8dacf"),true))
	var progress=Legacy.focus_progress(store.profile)
	if str(progress.get("id",""))!="":box.add_child(hud.label("Цель: "+Legacy.RESEARCH[progress.id].name+" · не хватает %d ядер" % int(progress.remaining),22,Color("cbb4e7"),true))
	if not store.profile.legacy.pending.is_empty():box.add_child(hud.button("Сохранить отпечаток этой линии",func():show_imprints("results"),true))
	box.add_child(hud.button("Новое поколение",show_start,true))
	box.add_child(hud.button("Развить геном",show_genome))
	box.add_child(hud.button("В меню",show_menu))

func show_level():
	set_stage("level")
	if sim.current_offers.is_empty():
		sim.current_offers = sim.build.offers(sim.rng)
		sim.roll_offer_quality()
	deferred_choices = false
	var box = hud.open("Мутация · уровень %d" % sim.level,"Выбери одно улучшение. Новые органы можно заменить прямо здесь. Биомасса: %d" % sim.build.biomass)
	var row = hud.row()
	box.add_child(row)
	var usable=sim.current_offers.filter(func(id):return sim.build.rank(id)<Catalog.max_rank(id) or int(sim.offer_quality.get(id,0))>sim.build.quality(id))
	if usable.is_empty():
		box.add_child(hud.label("Все доступные мутации развиты. Получи 15 биомассы.",22))
		box.add_child(hud.button("Поглотить ДНК",func(): sim.build.biomass+=15; _complete_level(),true))
	else:
		for id in usable: row.add_child(_mutation_card(id,func(): choose_mutation(id),int(sim.offer_quality.get(id,0))))
	var controls = hud.row()
	box.add_child(controls)
	var price = 5+sim.rerolls*5
	var reroll = hud.button("Перебросить · %d" % price,func(): reroll_level(false))
	reroll.disabled = sim.rerolls>=3 or sim.build.biomass<price
	controls.add_child(reroll)
	var focus = hud.button("Моя ветка · %d" % (price+5),func(): reroll_level(true))
	focus.disabled = sim.rerolls>=3 or sim.build.biomass<price+5
	controls.add_child(focus)
	box.add_child(hud.label("Перебросы: %d/3. Текущие синергии: %d." % [sim.rerolls,sim.build.active_synergies().size()],16,Color("9cafb7")))
	save_run()

func _mutation_card(id: String,callback: Callable,quality: int=0) -> PanelContainer:
	var card = hud.card()
	card.custom_minimum_size.x = 250
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	card.add_child(column)
	var item = Catalog.item(id)
	var illustration = OrganArt.new()
	illustration.organ_id = id
	illustration.quality=maxi(quality,sim.build.quality(id))
	illustration.custom_minimum_size = Vector2(120,100)
	# Keep the action and explicit quality label visible before long details.
	illustration.custom_minimum_size.y = 70
	column.add_child(illustration)
	column.add_child(hud.label(item.name,23,Color(item.color),true))
	var result_grade=maxi(quality,sim.build.quality(id))
	if result_grade>0:card.add_theme_stylebox_override("panel",hud.box(Color("122e39").lerp(Rewards.quality_color(result_grade),0.07),Rewards.quality_color(result_grade),16))
	column.add_child(hud.label(Rewards.quality_name(result_grade)+(" (сохранится)" if result_grade>quality else "")+" · сила ×%.2f" % Rewards.quality_multiplier(result_grade),20,Rewards.quality_color(result_grade),true))
	var rank = sim.build.rank(id)
	var rank_text = ("Новый орган · 1/10" if id in Catalog.ORGANS else "Адаптация · 1/6") if rank==0 else ("Улучшение качества · ранг %d/%d" % [rank,Catalog.max_rank(id)] if rank>=Catalog.max_rank(id) else "Ранг %d → %d / %d" % [rank,rank+1,Catalog.max_rank(id)])
	column.add_child(hud.label(rank_text,20,Color("97b6ba"),true))
	var full = sim.build.rank(id)==0 and ((id in Catalog.ORGANS and sim.build.organs.size()>=6) or (id in Catalog.ADAPTATIONS and sim.build.adaptations.size()>=4))
	column.add_child(hud.button("Заменить орган" if full else "Выбрать",callback,true))
	var description = hud.label(item.desc,19,Color("c5d8d7"),true)
	description.custom_minimum_size.y = 66
	column.add_child(description)
	column.add_child(hud.label(Inspector.comparison(sim.build,id,quality,"",sim.ability_scale(),sim.cooldown_factor()),20,Color("9fe0ca"),true))
	column.add_child(hud.label(Catalog.milestone_text(id,rank),20,Color("d7c39f"),true))
	var hints = hud.label(Inspector.synergy_lines(sim.build,id),16,Color("d0b3e8"),true)
	hints.custom_minimum_size.y = 75
	column.add_child(hints)
	return card

func reroll_level(focused: bool):
	if stage!="level" or sim.rerolls>=3: return
	var price = 5+sim.rerolls*5+(5 if focused else 0)
	if sim.build.biomass<price: return
	var candidates = []
	var previous = sim.current_offers.duplicate()
	for attempt in range(12):
		candidates = sim.build.offers(sim.rng,sim.build.branch if focused else "")
		if candidates.is_empty():
			message("В этой ветке пока нет доступных мутаций.",4)
			return
		var old = previous.duplicate()
		var new = candidates.duplicate()
		old.sort()
		new.sort()
		if old!=new: break
	var sorted_old = previous.duplicate()
	var sorted_new = candidates.duplicate()
	sorted_old.sort()
	sorted_new.sort()
	if sorted_old==sorted_new:
		message("Других предложений сейчас нет — биомасса не потрачена.",4)
		return
	if not sim.build.spend(price): return
	sim.rerolls += 1
	sim.current_offers = candidates
	sim.roll_offer_quality()
	show_level()

func choose_mutation(id: String):
	if stage!="level" or id not in sim.current_offers or sim.pending_levels<=0: return
	if _needs_replacement(id):
		show_replacement(id,"level")
		return
	if sim.build.apply(id,"",int(sim.offer_quality.get(id,0))): _complete_level()

func _complete_level():
	sim.pending_levels = maxi(0,sim.pending_levels-1)
	sim.current_offers = []
	sim.offer_quality = {}
	deferred_choices = false
	sim.rerolls = 0
	_tone(640)
	if not deferred_choices and not sim.reward_queue.is_empty(): show_reward()
	elif not deferred_choices and sim.pending_levels>0: show_level()
	else: resume_game()
	save_run()

func _needs_replacement(id: String) -> bool:
	if sim.build.rank(id)>0: return false
	return sim.build.organs.size()>=6 if id in Catalog.ORGANS else sim.build.adaptations.size()>=4

func show_replacement(id: String,origin: String,stock: int=-1):
	replacement_id = id
	replacement_origin = origin
	replacement_stock = stock
	set_stage("replace")
	var box = hud.open("Перестройка организма", "Новый орган: "+Catalog.item(id).name+". Выбери, что заменить. Переносится половина дополнительных уровней, с округлением вниз.")
	var target = sim.build.organs if id in Catalog.ORGANS else sim.build.adaptations
	for old in target:
		var lost = []
		for synergy in sim.build.active_synergies():
			if old in Catalog.SYNERGIES[synergy].needs: lost.append(Catalog.SYNERGIES[synergy].name)
		var inherited = mini(1+int(floor((sim.build.rank(old)-1)/2.0)),Catalog.max_rank(id))
		var text = "%s %d → %s %d" % [Catalog.item(old).name,sim.build.rank(old),Catalog.item(id).name,inherited]
		if not lost.is_empty(): text += "\nПотеря: "+", ".join(lost)
		var grade = int(sim.offer_quality.get(id,0)) if origin=="level" else (int(sim.reward_options[reward_index].get("quality",0)) if origin=="reward" else int(sim.world.colonies[active_shop].stock[stock].get("quality",0)))
		box.add_child(hud.button(text,func(): confirm_replacement(old)))
		box.add_child(hud.label("Качество после замены: "+Rewards.quality_name(maxi(grade,sim.build.quality(old))),20,Rewards.quality_color(maxi(grade,sim.build.quality(old))),true))
		box.add_child(hud.label(Inspector.comparison(sim.build,id,grade,old,sim.ability_scale(),sim.cooldown_factor()),19,Color("b9d9cf"),true))
	box.add_child(hud.button("Отмена",func(): show_level() if origin=="level" else (show_reward() if origin=="reward" else show_shop())))

func confirm_replacement(old: String):
	if stage!="replace": return
	if replacement_origin=="reward":
		claim_reward(reward_index,old)
	elif replacement_origin=="shop":
		var item = sim.world.colonies[active_shop].stock[replacement_stock]
		if item.sold or sim.build.biomass<item.price: return
		if sim.build.apply(replacement_id,old,int(item.get("quality",0))):
			sim.build.spend(item.price)
			item.sold = true
			save_run()
			show_shop()
	else:
		if sim.build.apply(replacement_id,old,int(sim.offer_quality.get(replacement_id,0))): _complete_level()

func show_shop():
	var idx = sim.nearby_colony()
	if idx<0: return
	active_shop = idx
	set_stage("shop")
	var box = hud.open("Симбиотическая колония", "Здесь безопасно. Биомасса: %d. Покупки не обновляются при повторном входе." % sim.build.biomass)
	var row = hud.row()
	box.add_child(row)
	var stock = sim.world.colonies[idx].stock
	for i in range(stock.size()):
		var item = stock[i]
		var card = hud.card()
		card.custom_minimum_size.x = 250
		row.add_child(card)
		var col = VBoxContainer.new()
		card.add_child(col)
		col.add_child(hud.label("Восстановление" if item.id=="heal" else Catalog.item(item.id).name,23,Color("a5e4ca"),true))
		var b = hud.button("Получено" if item.sold else "Купить · %d" % item.price,func(): buy_shop(i),true)
		b.disabled = item.sold or sim.build.biomass<item.price or (item.id=="heal" and sim.hp>=sim.max_hp) or (item.id!="heal" and sim.build.rank(item.id)>=Catalog.max_rank(item.id) and int(item.get("quality",0))<=sim.build.quality(item.id))
		col.add_child(b)
		if item.id!="heal":
			col.add_child(hud.label(Rewards.quality_name(int(item.get("quality",0))),20,Rewards.quality_color(int(item.get("quality",0))),true))
			var illustration=OrganArt.new()
			illustration.organ_id=item.id
			illustration.custom_minimum_size=Vector2(120,90)
			col.add_child(illustration)
			col.add_child(hud.label(Inspector.comparison(sim.build,item.id,int(item.get("quality",0)),"",sim.ability_scale(),sim.cooldown_factor()),17,Color("9fe0ca"),true))
		col.add_child(hud.label("Восстановить 40 здоровья" if item.id=="heal" else Catalog.item(item.id).desc,19,Color("b3cfcb"),true))
		if item.id!="heal": col.add_child(hud.label(Catalog.synergy_hint(item.id,sim.build.organs.merged(sim.build.adaptations)),16,Color("ccb0e5"),true))

	box.add_child(hud.button("Вернуться в микромир",resume_game))

func buy_shop(index: int):
	if stage!="shop" or active_shop<0: return
	var stock = sim.world.colonies[active_shop].stock
	if index<0 or index>=stock.size(): return
	var item = stock[index]
	if item.sold or sim.build.biomass<item.price: return
	if item.id=="heal":
		if sim.hp>=sim.max_hp: return
		sim.heal_player(40)
	elif _needs_replacement(item.id):
		show_replacement(item.id,"shop",index)
		return
	elif not sim.build.apply(item.id,"",int(item.get("quality",0))): return
	sim.build.spend(item.price)
	item.sold = true
	save_run()
	_tone(480)
	show_shop()

func show_pause():
	if stage in ["menu","start","genome","atlas","help","results","gallery"]: return
	set_stage("pause")
	save_run()
	var box = hud.open("Пауза", "Организм ждёт. Бой и время остановлены.",700)
	box.add_child(hud.button("Продолжить",resume_game,true))
	box.add_child(hud.button("Развитие · сборка",show_development))
	box.add_child(hud.button("Карта микромира",show_map))
	box.add_child(hud.button("Звук: "+("вкл." if sound_enabled else "выкл."),func(): sound_enabled=not sound_enabled; show_pause()))
	box.add_child(hud.button("Сохранить и выйти в меню",func(): save_run(); show_menu()))
	box.add_child(hud.label("Seed: %d · %s" % [sim.world.seed_value,sim.run_id],15,Color("75949c"),true))

func show_development(journal: bool=false):
	# Only enter from contexts that can be restored without changing a choice.
	if stage not in ["game","pause","development"]: return
	if stage!="development":development_origin = stage
	set_stage("development")
	hud.game_visible(false)
	var box = hud.open("Развитие организма", "Бой и время остановлены. Органы, пассивные эффекты и сочетания текущей сборки.")
	var navigation=hud.row()
	box.add_child(navigation)
	navigation.add_child(hud.button("Сборка",func():show_development(false),not journal))
	navigation.add_child(hud.button("Журнал урона",func():show_development(true),journal))
	if journal:Development.damage_view(hud,box,sim)
	else:Development.populate(hud,box,sim)
	box.add_child(hud.button("Вернуться",close_development))

func close_development():
	if stage!="development": return
	if development_origin=="pause": show_pause()
	else: resume_game()

func resume_game():
	hud.close()
	set_stage("game")
	hud.game_visible(true)
	hud.update_game(sim)
	if not deferred_choices and not sim.reward_queue.is_empty(): show_reward()
	elif not deferred_choices and sim.pending_levels>0: show_level()

func show_map():
	set_stage("map")
	var box = hud.open("Карта микромира", "Неизведанное скрыто. Колонии и находки отмечаются после обнаружения.")
	var map = Map.new()
	map.sim = sim
	map.large = true
	map.custom_minimum_size = Vector2(800,390)
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(map)
	box.add_child(hud.button("Вернуться",resume_game))

func show_genome():
	set_stage("genome")
	var box=hud.open("Наследственный геном","Исследования и открытия сохраняются после гибели. Ядра: %d." % store.profile.cores)
	GenomeView.populate_genome(hud,box,store,_legacy_preview(),{
		"research":func(id):_legacy_edit("research",id,"genome"),"focus":func(id):_legacy_edit("focus",id,"genome"),
		"upgrade":func(id):_legacy_edit("upgrade",id,"genome"),"imprints":func():show_imprints("genome"),"back":show_menu})

func show_imprints(origin: String="menu"):
	imprint_origin=origin
	set_stage("inherit")
	var box=hud.open("Генетические отпечатки","Выбор можно отложить крестиком. Новые жизни не стирают ожидающее наследие.")
	GenomeView.populate_imprints(hud,box,store,{"claim":func(id):
		if not store.claim_imprint(id):message(store.last_error if store.last_error!="" else "Отпечаток недоступен",4)
		show_imprints(imprint_origin),"back":_close_imprints})

func _close_imprints():
	if imprint_origin=="start":show_start()
	elif imprint_origin=="genome":show_genome()
	elif imprint_origin=="results" and sim!=null and sim.outcome!="":finish_run()
	else:show_menu()

func show_updates():
	set_stage("updates")
	_update_screen()

func _update_screen():
	if stage!="updates":return
	var box=hud.open("Обновления Микрогена","Проверка выполняется только по кнопке. Игре интернет не нужен.")
	UpdateView.populate(hud,box,update_feed,{"check":update_feed.check_updates,"cancel":update_feed.cancel,
		"open_download":update_feed.open_download,"open_release":update_feed.open_release,"back":show_menu})


func show_atlas():
	set_stage("atlas")
	var box = hud.open("Атлас эволюции", "Изучи органы в забегах и открой все %d сочетаний." % Catalog.SYNERGIES.size())
	for id in Catalog.SYNERGIES:
		var item = Catalog.SYNERGIES[id]
		var known = id in store.profile.synergies
		box.add_child(hud.label(("✓ " if known else "◇ ")+item.name,23,Color("c8abe8")))
		var text = Catalog.item(item.needs[0]).name+" + "+Catalog.item(item.needs[1]).name
		box.add_child(hud.label(text+"\n"+(item.desc if known else "Собери оба органа, чтобы изучить взаимодействие."),18,Color("a8c5c5"),true))
	box.add_child(hud.label("Органы и адаптации",25))
	for id in Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys():
		var state = "Изучен" if id in store.profile.discovered else ("Доступен" if id in store.profile.unlocked else "Закрыт: геном")
		box.add_child(hud.label(state,18,Color("a9ceca"),true))
		box.add_child(Development.item_card(hud,id,1))
	box.add_child(hud.button("В меню",show_menu))

func show_help():
	set_stage("help")
	var box = hud.open("Как выжить в капле", "Движение — единственное действие во время боя.",850)
	box.add_child(hud.label("• Коснись любого свободного места экрана и веди палец: появится джойстик.\n• На ПК: WASD или стрелки; M — карта; E — колония; B — развитие; Esc — пауза.\n• Зелёные фрагменты ДНК повышают уровень. Янтарная биомасса нужна для покупок и перебросов. Фиолетовые ядра сохраняются между забегами.\n• Касание захватывает пищу: можно плыть дальше, пока она переваривается. Рецепторы открывают притягивание. Бирюзовые кусочки лечат. Рост меняет соотношение сил: бывшие хищники становятся пищей. Других врагов сначала ослабь; хищная пасть помогает поглощать их раньше.\n• Собирай пары органов: щупальца + кислота, шипы + импульс, деление + след, заражение + пасть.\n• На миникарте отмечаются изученные места. Светлые колонии безопасны; внутри доступен магазин.\n• Оформление, проходы, местные условия, находки и противники меняются с каждым seed.\n• На 10-й минуте появляется Архицит. Найди его по карте и победи. Таймер не завершает забег автоматически.\n• Игра сохраняет забег при паузе и уходе в фон; в меню есть «Продолжить».",20,Color("b8d0cd"),true))
	box.add_child(hud.button("Понятно",show_menu,true))

func message(text: String,seconds: float=3):
	if hud==null: return
	hud.message.text = text
	message_timer = seconds

func _tone(frequency: float):
	if not sound_enabled: return
	sound_player.stop()
	var data = PackedByteArray()
	for i in range(2400):
		var t = i/24000.0
		var sample = sin(t*frequency*TAU)*exp(-t*40)*0.35
		var value = int(sample*32767)
		data.append(value&255)
		data.append((value>>8)&255)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 24000
	stream.data = data
	sound_player.stream = stream
	sound_player.play()

func _exit_tree():
	if sound_player!=null:
		sound_player.stop()
		sound_player.stream = null

func _notification(what):
	if hud==null: return
	if what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		if stage in ["game","map","shop","level","replace","reward"]: show_pause()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if stage=="game": show_pause()
		elif stage=="development": close_development()
		elif stage in ["level","reward","replace"]: close_modal()
		elif stage in ["pause","map","shop"]: resume_game()
		elif stage=="inherit":_close_imprints()
		elif stage in ["genome","atlas","help","start","gallery","updates"]: show_menu()
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		save_run()
		get_tree().quit()

func _capture():
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var result = image.save_png(capture_path)
	print("CAPTURE: ",capture_path," status=",result)
	if capture_mode in ["foundation-start","foundation-genome","inheritance"]:store.clear_test_files()
	get_tree().quit()

func open_pending():
	deferred_choices = false
	if not sim.reward_queue.is_empty(): show_reward()
	elif sim.pending_levels>0: show_level()

func close_modal():
	match stage:
		"menu": get_tree().quit()
		"start","genome","atlas","help","gallery","results": show_menu()
		"development": close_development()
		"inherit": _close_imprints()
		"updates": show_menu()
		"level","reward","replace":
			deferred_choices = true
			save_run()
			resume_game()
		"save_error": resume_game()
		_: resume_game()

func show_reward():
	if sim.reward_queue.is_empty():
		resume_game()
		return
	deferred_choices = false
	sim.prepare_reward()
	set_stage("reward")
	var box = hud.open("Награда за опасную добычу", "Выбери одну награду. Качество и варианты сохраняются. Ожидают: %d." % sim.reward_queue.size())
	reward_reveal=CystReveal.new()
	reward_reveal.tier=int(sim.reward_queue[0].tier)
	reward_reveal.options=sim.reward_options.duplicate(true)
	box.add_child(reward_reveal)
	var reveal=reward_reveal
	var row = hud.row()
	box.add_child(row)
	row.hide()
	reveal.finished.connect(func():
		if stage!="reward" or reward_reveal!=reveal or not is_instance_valid(row):return
		reveal.hide();row.show()
		_tone(560+int(reveal.tier)*110)
		var tween=create_tween()
		row.modulate.a=0
		tween.tween_property(row,"modulate:a",1.0,0.3)
	)
	for i in range(sim.reward_options.size()):
		var option = sim.reward_options[i]
		if option.kind=="mutation":
			row.add_child(_mutation_card(option.id,func(): claim_reward(i),int(option.quality)))
		else:
			var card = hud.card()
			card.custom_minimum_size.x = 250
			row.add_child(card)
			var column = VBoxContainer.new()
			card.add_child(column)
			if option.kind=="evolution":
				column.add_child(hud.label(Catalog.EVOLUTIONS[option.id].name+" · "+Catalog.item(option.id).name,23,Color("e5c591"),true))
				column.add_child(hud.button("Эволюционировать",func(): claim_reward(i),true))
				column.add_child(hud.label("Урон органа ×1,30. Требования выполнены.\n"+Development.evolution_preview(sim.build,option.id,sim.ability_scale(),sim.cooldown_factor()),20,Color("bcdacf"),true))
			else:
				column.add_child(hud.label("Биомасса +%d" % int(option.amount),24,Color("eac88c"),true))
				column.add_child(hud.button("Поглотить",func(): claim_reward(i),true))
	save_run()

func claim_reward(index: int,replace_id: String=""):
	if stage=="reward" and is_instance_valid(reward_reveal) and not reward_reveal.complete:return
	if stage not in ["reward","replace"] or index<0 or index>=sim.reward_options.size(): return
	var option = sim.reward_options[index]
	if option.kind=="mutation" and replace_id=="" and _needs_replacement(option.id):
		reward_index = index
		show_replacement(option.id,"reward")
		return
	if not sim.claim_reward(index,replace_id): return
	_tone(720)
	save_run()
	if not sim.reward_queue.is_empty(): show_reward()
	elif sim.pending_levels>0: show_level()
	else: resume_game()
