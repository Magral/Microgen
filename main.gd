extends Node2D
const OrganismFlow=preload("res://ui/organism_flow.gd")
const CodexView=preload("res://ui/codex_view.gd")
const Equipment=preload("res://core/organism_equipment.gd")
var lineage_flow
var codex_view
var capacity_notice=false
func _lineage():
	if lineage_flow==null:lineage_flow=OrganismFlow.new(self)
	return lineage_flow

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
const Build = preload("res://core/build_model.gd")
const Map = preload("res://ui/minimap.gd")
const World = preload("res://game/world.gd")
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
var synergy_continue: Callable
var stage_reveal_tween: Tween
var stage_preview_world
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
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preview="):
			store.path="user://test-preview-release-one.json";store.clear_test_files()
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
		elif capture_mode == "codex":
			sim.build.organs={"tentacle":4,"acid":3,"pulse":2}
			show_codex_entry("tentacle")
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
		if not _handle_events():return
		if sim.stage_transition:
			show_stage_briefing()
		elif sim.outcome!="":
			finish_run()
		elif capacity_notice:
			show_capacity_notice()
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
	if stage=="stage_briefing" and value!="stage_briefing" and stage_reveal_tween!=null and stage_reveal_tween.is_running():stage_reveal_tween.kill()
	if value!="reward":reward_reveal=null
	stage = value
	clear_stick()
	if sim!=null: sim.paused = stage!="game"
	view.menu = stage=="menu"

func show_menu():
	if stage in ["game","pause","development"] and sim!=null and not sim.family_id.is_empty():
		if not save_run():return
	_lineage().show_home()

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
	if hud.scroll_container!=null:hud.scroll_container.set_deferred("scroll_vertical",scroll)

func show_start():
	_lineage().show_preparation()


func start_run(seed_value: int = -1):
	if not _lineage().ensure_family():message(store.last_error,5);return
	if not store.profile.checkpoint.is_empty() and str(store.profile.checkpoint.get("outcome",""))=="":
		continue_run();return
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
	sim.best_stage=maxi(0,int(store.profile.get("best_stage",0)))
	sim.family_id=store.family_id()
	var equipment=Equipment.from_profile(store.profile)
	if equipment.is_empty():message("Не удалось прочитать органы семейства",5);return
	_lineage().bind_run(equipment)
	OrganismFlow.apply_to_build(equipment,sim.build)
	sim.stock_capacity=int(equipment.stock_capacity)
	capacity_notice=false
	view.sim = sim
	checkpoint_timer = 0
	deferred_choices = false
	hud.close()
	set_stage("game")
	hud.game_visible(true)
	hud.update_game(sim)
	save_run()
	message("Веди палец по свободному месту.\nКасайся пищи телом; бирюзовые кусочки лечат.",6)
	var starter_synergies=sim.build.active_synergies()
	if not starter_synergies.is_empty():show_synergy_reveal(starter_synergies,Callable(self,"resume_game"))

func continue_run():
	if not _lineage().ensure_family():message(store.last_error,5);return
	var loaded = Sim.new()
	if not loaded.restore(store.profile.checkpoint):
		message("Сохранение забега повреждено. Геном сохранён.",5)
		return
	if not loaded.family_id.is_empty() and loaded.family_id!=store.family_id():
		message("Сохранённая жизнь принадлежит другому семейству",5);return
	loaded.family_id=store.family_id()
	loaded.best_stage=maxi(loaded.best_stage,int(store.profile.get("best_stage",0)))
	var equipment=Equipment.from_profile(store.profile)
	if equipment.is_empty():message("Не удалось прочитать органы семейства",5);return
	_lineage().bind_run(equipment)
	OrganismFlow.apply_to_build(equipment,loaded.build)
	loaded.stock_capacity=int(equipment.stock_capacity)
	capacity_notice=false
	sim = loaded
	view.sim = sim
	hud.close()
	set_stage("game")
	hud.game_visible(true)
	hud.update_game(sim)
	if sim.stage_transition:
		show_stage_briefing()
		return
	if sim.outcome!="":
		_handle_events()
		finish_run()
		return
	if not deferred_choices and not sim.reward_queue.is_empty(): show_reward()
	elif not deferred_choices and sim.pending_levels>0: show_level()

func _run_matches_family() -> bool:
	return sim!=null and not sim.family_id.is_empty() and sim.family_id==store.family_id()

func save_run() -> bool:
	if sim==null or stage not in ["game","pause","development","map","shop","level","reward","replace","synergy_reveal","stage_briefing","save_error","capacity_notice"]:return false
	if stage=="development" and not _lineage().live_mode:return false
	if not _run_matches_family():message("Другая жизнь не может перезаписать семейство",5);return false
	var next=store.profile.duplicate(true)
	var equipment=_lineage().capture(sim.build.to_dict())
	if equipment.is_empty():message("Не удалось сохранить органы",5);return false
	next.organism=equipment
	next.checkpoint=sim.snapshot()
	for id in sim.build.organs.keys()+sim.build.adaptations.keys():
		if id not in next.discovered:next.discovered.append(id)
	for id in sim.build.active_synergies():
		if id not in next.synergies:next.synergies.append(id)
	if not store.write_profile(next):message(store.last_error,6);return false
	return true

func _handle_events() -> bool:
	if not _run_matches_family():return false
	if sim.events.is_empty():return true
	var next=store.profile.duplicate(true)
	var equipment=_lineage().capture(sim.build.to_dict())
	if equipment.is_empty():return false
	var changed=false
	var expanded=false
	for event in sim.events:
		if event.type=="message":message(event.text,5)
		elif event.type=="core" and not event.token in next.credited:
			next.credited.append(event.token);next.cores+=event.amount;changed=true
			message("Ядра наследия +%d"%event.amount,3)
		elif event.type=="stage_clear":
			var cleared=maxi(1,int(event.get("stage",1)))
			if not event.token in next.credited:
				next.credited.append(event.token);changed=true
				next.best_stage=maxi(int(next.get("best_stage",0)),cleared)
				sim.best_stage=maxi(sim.best_stage,cleared)
		elif event.type=="family_material" and not event.token in next.credited:
			var found=event.get("materials",{})
			if not found is Dictionary or found.is_empty():return false
			for material in found:
				var amount=int(found[material])
				if material not in ["organelle","membrane","plasma"] or amount<=0:return false
				next.organ_materials[material]=mini(9007199254740991,int(next.organ_materials.get(material,0))+amount)
			next.credited.append(event.token)
			changed=true
			message("Поглощённые части тела сохранены как семейные материалы",3)
		elif event.type=="expansion" and not event.token in next.credited:
			var target=str(event.get("target",""))
			var amount=event.get("amount",0)
			if target not in ["body","stock"] or not (amount is int or amount is float) or not is_finite(float(amount)) or amount<=0 or float(amount)!=floorf(float(amount)):return false
			var key=target+"_capacity"
			if amount>9007199254740991-int(equipment[key]):return false
			equipment[key]=int(equipment[key])+int(amount)
			if Equipment.validate(equipment)!="":return false
			next.credited.append(event.token);changed=true;expanded=true
	if changed:
		next.organism=equipment
		next.checkpoint=sim.snapshot()
		next.checkpoint.build.organ_capacity=int(equipment.body_capacity)
		next.checkpoint.stock_capacity=int(equipment.stock_capacity)
		if not store.write_profile(next):message(store.last_error,6);return false
		_lineage().bind_run(equipment)
		OrganismFlow.apply_to_build(equipment,sim.build)
		sim.stock_capacity=int(equipment.stock_capacity)
	if expanded:
		capacity_notice=true
		sim._effect({"type":"mutation","pos":sim.player,"r":sim.body_radius()*1.6,"color":Color("9ce3cf"),"life":1.8,"max":1.8})
	sim.events.clear()
	return true

func show_capacity_notice():
	capacity_notice=false
	set_stage("capacity_notice")
	var equipment=_lineage().state()
	var box=hud.open_fixed("Новая камера организма","Найденное расширение сохраняется у этого семейства после любой гибели.",900)
	var art=OrganArt.new();art.sim=sim;art.custom_minimum_size=Vector2(600,260);box.add_child(art)
	box.add_child(hud.label("Тело: %d ячеек · запас: %d мест"%[int(equipment.body_capacity),int(equipment.stock_capacity)],26,Color("9ce3cf"),true))
	var row=hud.row();box.add_child(row)
	row.add_child(hud.button("К организму",func():development_origin="game";_lineage().show_body(true)))
	row.add_child(hud.button("Продолжить",resume_game,true))

func stage_reroll_cost()->int:
	return 8+mini(40,sim.stage_index*4)

func show_stage_briefing():
	if sim==null or not sim.stage_transition:return
	set_stage("stage_briefing")
	var stage_number=sim.stage_index+1
	var seed_value=maxi(1,sim.pending_stage_seed)
	var preview_world=World.new();preview_world.generate(seed_value)
	stage_preview_world=preview_world
	var preview_sim=Sim.new();preview_sim.world=preview_world;preview_sim.player=preview_world.start
	preview_sim.stage_index=stage_number;preview_sim.run_id=sim.run_id;preview_sim._create_cysts()
	preview_sim.boss_spawned=true;preview_sim.boss_marker=preview_world.boss_pos
	for index in range(preview_world.cells.size()):preview_sim.explored[index]=true
	var screen_size=hud.root.get_viewport_rect().size
	var wide=screen_size.x>=900
	var box=hud.open_fixed("Переход на ступень %d"%stage_number,"Карта, условия и награды следующей области.",1120)
	var map=Map.new();map.sim=preview_sim;map.large=wide;map.custom_minimum_size=Vector2(430,290) if wide else Vector2(230,clampf(screen_size.y*0.18,100,140))
	if wide:
		var row=hud.row();box.add_child(row);row.add_child(map)
	else:
		map.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;box.add_child(map)
	var details=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;box.add_child(details)
	var final_stage_name=sim.stage_name(stage_number,seed_value)
	var title=hud.label("Сканирование среды…",30 if wide else 25,Color("9ce3cf"),true);details.add_child(title)
	var danger=[]
	var cyst_counts=[0,0,0]
	for cyst in preview_sim.cysts:cyst_counts[clampi(int(cyst.tier)-1,0,2)]+=1
	details.add_child(hud.label("ЦИСТЫ · редк. %d · эпич. %d · легенд. %d"%[cyst_counts[0],cyst_counts[1],cyst_counts[2]],21 if wide else 20,Color("e7ca8b"),true))
	for biome in range(2):
		var condition=int(preview_world.conditions[biome])
		var effect=["свободный ход","движение медленнее","перезарядка быстрее"][condition]
		danger.append(("Питательная" if biome==0 else "Токсичная")+" · "+effect)
	details.add_child(hud.label("СРЕДА · "+"  /  ".join(danger),21 if wide else 20,Color("c7ded8"),true))
	var boss=sim.boss_title(stage_number,seed_value)
	var boss_hp=roundi(1600.0*(1.0+0.14*float(stage_number-1)))
	details.add_child(hud.label("БОСС · %s · база ~%d HP\nАтака: веер из 10 сгустков / 1,5 с"%[boss,boss_hp],23 if wide else 20,Color("efa3a9"),true))
	var miniboss_target=sim.stage_miniboss_target(stage_number)
	var nest_target=mini(4,miniboss_target*2)
	details.add_child(hud.label("ЦЕЛЬ · гнёзда %d · минибоссы %d · затем босс"%[nest_target,miniboss_target],21 if wide else 20,Color("d3dfd8"),true))
	var recommendation="Сочетай органы для синергий."
	var active=sim.build.active_synergies()
	if not active.is_empty():recommendation="СИНЕРГИЯ · "+str(Catalog.SYNERGIES[str(active[0])].name)
	else:
		for synergy_id in Catalog.SYNERGIES:
			var synergy=Catalog.SYNERGIES[synergy_id]
			var have=[]
			for needed in synergy.needs:
				if sim.build.rank(str(needed))>0:have.append(str(needed))
			if not have.is_empty():
				var missing=str(synergy.needs[0] if synergy.needs[1] in have else synergy.needs[1])
				recommendation="ПАРА · %s + %s"%[Catalog.item(str(have[0])).name,Catalog.item(missing).name]
				break
	var tip=hud.label(recommendation,21 if wide else 20,Color("d3b9eb"),true);details.add_child(tip)
	var actions=hud.row() if wide else VBoxContainer.new();box.add_child(actions)
	var cost=stage_reroll_cost()
	var organism_button=hud.button("ОРГАНИЗМ",func():development_origin="stage_briefing";_lineage().show_body(true))
	var reroll=hud.button("Новая область · %d органиума"%cost,reroll_stage_area)
	var enter=hud.button("ВОЙТИ В ОБЛАСТЬ",enter_next_stage,true)
	if not wide:
		for action in [organism_button,reroll,enter]:action.custom_minimum_size.y=46
	actions.add_child(organism_button)
	reroll.disabled=int(store.profile.get("organium",0))<cost
	actions.add_child(reroll)
	actions.add_child(enter)
	for info_index in range(1,details.get_child_count()):details.get_child(info_index).hide()
	actions.hide()
	var skip_button:Button
	skip_button=hud.button("ПРОПУСТИТЬ",func():_skip_stage_generation(title,final_stage_name,details,actions,skip_button))
	if not wide:skip_button.custom_minimum_size.y=46
	box.add_child(skip_button)
	var roll_rng=RandomNumberGenerator.new();roll_rng.seed=seed_value+stage_number*991
	var roll_names=[]
	for i in range(6):roll_names.append(sim.stage_name(stage_number,roll_rng.randi()))
	roll_names.append(final_stage_name)
	if stage_reveal_tween!=null and stage_reveal_tween.is_running():stage_reveal_tween.kill()
	stage_reveal_tween=create_tween();title.scale=Vector2(0.92,0.92);map.modulate.a=0.0
	stage_reveal_tween.tween_method(Callable(self,"_set_stage_roll_title").bind(title,roll_names),0.0,float(roll_names.size()-1),0.72).set_trans(Tween.TRANS_SINE)
	stage_reveal_tween.parallel().tween_property(map,"modulate:a",1.0,0.66)
	stage_reveal_tween.parallel().tween_property(title,"scale",Vector2.ONE,0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	stage_reveal_tween.tween_callback(Callable(self,"_reveal_stage_details").bind(details,actions,skip_button))
	save_run()

func _set_stage_roll_title(value: float,title: Label,names: Array):
	if is_instance_valid(title) and stage=="stage_briefing":title.text=str(names[clampi(roundi(value),0,names.size()-1)])

func _skip_stage_generation(title: Label,final_name: String,details: VBoxContainer,actions: Control,skip_button: Button):
	if stage_reveal_tween!=null and stage_reveal_tween.is_running():stage_reveal_tween.kill()
	if is_instance_valid(title):title.text=final_name
	_reveal_stage_details(details,actions,skip_button)

func _reveal_stage_details(details: VBoxContainer,actions: Control,skip_button: Button):
	if stage!="stage_briefing" or not is_instance_valid(details) or not is_instance_valid(actions):return
	for info_index in range(1,details.get_child_count()):details.get_child(info_index).show()
	actions.show()
	if is_instance_valid(skip_button):skip_button.hide()

func reroll_stage_area():
	if stage!="stage_briefing" or not sim.stage_transition:return
	var cost=stage_reroll_cost()
	if int(store.profile.get("organium",0))<cost:return
	var previous_seed=sim.pending_stage_seed
	var reroll_rng=RandomNumberGenerator.new()
	reroll_rng.seed=posmod(previous_seed+int(Time.get_ticks_usec())+sim.stage_index*7919,2147483647)
	var replacement_seed=reroll_rng.randi_range(1,2147483646)
	if replacement_seed==previous_seed:replacement_seed=1 if replacement_seed>=2147483646 else replacement_seed+1
	sim.pending_stage_seed=replacement_seed
	var next=store.profile.duplicate(true)
	next.organium=int(next.get("organium",0))-cost
	next.checkpoint=sim.snapshot()
	if not store.write_profile(next):
		sim.pending_stage_seed=previous_seed
		message(store.last_error,6)
		return
	show_stage_briefing()

func enter_next_stage():
	if sim==null or not sim.enter_next_stage(stage_preview_world):return
	stage_preview_world=null
	view.sim=sim;view.motions.clear();view.detailed_enemies.clear()
	checkpoint_timer=0
	hud.close()
	set_stage("game")
	hud.game_visible(true)
	hud.update_game(sim)
	save_run()

func finish_run():
	sim.flush_family_materials()
	if not sim.events.is_empty() and not _handle_events():return
	if not _run_matches_family():message("Итоги принадлежат другому семейству",5);return
	var next = store.profile.duplicate(true)
	var equipment=_lineage().capture(sim.build.to_dict())
	if not equipment.is_empty():next.organism=equipment
	for event in sim.events:
		if event.type=="core" and not event.token in next.credited:
			next.credited.append(event.token)
			next.cores += event.amount
	var token = sim.run_id+":finished"
	if token not in next.credited:
		if not Legacy.complete(next,sim):
			var deferred=store.profile.duplicate(true)
			deferred.checkpoint=sim.snapshot()
			if not equipment.is_empty():deferred.organism=equipment
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
		var organium_token=sim.run_id+":organium"
		if organium_token not in next.credited:
			next.credited.append(organium_token)
			next.organium=mini(9007199254740991,int(next.get("organium",0))+maxi(1,int(sim.kills/4))+int(sim.minibosses_spawned)*2+(5 if sim.outcome=="victory" else 0))
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
	box.add_child(hud.label("Ядра наследия: %d · Органиум: %d\nИзученные синергии: %d/%d" % [store.profile.cores,int(store.profile.get("organium",0)),store.profile.synergies.size(),Catalog.SYNERGIES.size()],22))
	box.add_child(hud.label(Development.combat_summary(sim),21,Color("b8dacf"),true))
	var progress=Legacy.focus_progress(store.profile)
	if str(progress.get("id",""))!="":box.add_child(hud.label("Цель: "+Legacy.RESEARCH[progress.id].name+" · не хватает %d ядер" % int(progress.remaining),22,Color("cbb4e7"),true))
	if not store.profile.legacy.pending.is_empty():box.add_child(hud.button("Сохранить отпечаток этой линии",func():show_imprints("results"),true))
	box.add_child(hud.button("Новое поколение",show_start,true))
	box.add_child(hud.button("Развить геном",show_genome))
	box.add_child(hud.button("В меню",show_menu))

func show_level(page: int=0):
	set_stage("level")
	if sim.current_offers.is_empty():
		sim.current_offers = sim.build.offers(sim.rng)
		sim.roll_offer_quality()
	deferred_choices = false
	var box = hud.open("Мутация · уровень %d" % sim.level,"Выбери одно улучшение. Новые органы можно заменить прямо здесь. Биомасса: %d" % sim.build.biomass)
	var viewport_width=hud.root.get_viewport_rect().size.x
	var columns=1 if viewport_width<640 else (2 if viewport_width<1020 else 3)
	var choices=GridContainer.new()
	choices.columns=columns
	choices.add_theme_constant_override("h_separation",12)
	choices.add_theme_constant_override("v_separation",12)
	box.add_child(choices)
	var usable=sim.current_offers.filter(func(id):return sim.build.stored_rank(id)<Catalog.max_rank(id) or int(sim.offer_quality.get(id,0))>sim.build.quality(id))
	if usable.is_empty():
		box.add_child(hud.label("Все доступные мутации развиты. Получи 15 биомассы.",22))
		box.add_child(hud.button("Поглотить ДНК",func(): sim.build.biomass+=15; _complete_level(),true))
	elif columns==1:
		var selected_page=posmod(page,usable.size())
		var pager=hud.row();choices.add_child(pager)
		var previous=hud.button("‹",func():show_level(posmod(selected_page-1,usable.size())))
		previous.disabled=usable.size()<=1
		pager.add_child(previous)
		var page_label=hud.label("Вариант %d / %d"%[selected_page+1,usable.size()],21,Color("a5c4c4"),true)
		page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		page_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		pager.add_child(page_label)
		var next=hud.button("›",func():show_level(posmod(selected_page+1,usable.size())))
		next.disabled=usable.size()<=1
		pager.add_child(next)
		var id=str(usable[selected_page])
		var card=_mutation_card(id,func():choose_mutation(id),int(sim.offer_quality.get(id,0)))
		card.custom_minimum_size.x=maxf(180.0,minf(380.0,viewport_width-160.0))
		choices.add_child(card)
	else:
		for id in usable:
			var card=_mutation_card(id,func(): choose_mutation(id),int(sim.offer_quality.get(id,0)))
			card.custom_minimum_size.x=maxf(180.0,minf(380.0,(viewport_width-160.0-12.0*float(columns-1))/float(columns)))
			choices.add_child(card)
	var controls = hud.row() if viewport_width>=640 else VBoxContainer.new()
	controls.add_theme_constant_override("separation",8)
	box.add_child(controls)
	var price = 5+sim.rerolls*5
	var reroll = hud.button("Перебросить · %d" % price,func(): reroll_level(false))
	reroll.disabled = sim.rerolls>=3 or sim.build.biomass<price
	controls.add_child(reroll)
	var focus = hud.button("Моя ветка · %d" % (price+5),func(): reroll_level(true))
	focus.disabled = sim.rerolls>=3 or sim.build.biomass<price+5
	controls.add_child(focus)
	box.add_child(hud.label("Перебросы: %d / 3" % sim.rerolls,19,Color("9cafb7")))
	save_run()

func _mutation_card(id: String,callback: Callable,quality: int=0) -> PanelContainer:
	var card = hud.card()
	card.custom_minimum_size.x = 288
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	card.add_child(column)
	var item = Catalog.item(id)
	var illustration = OrganArt.new()
	illustration.organ_id = id
	var drop_grade=clampi(quality,0,3)
	illustration.quality=maxi(drop_grade,sim.build.quality(id))
	illustration.custom_minimum_size = Vector2(112,78)
	column.add_child(illustration)
	var result_grade=maxi(drop_grade,sim.build.quality(id))
	var preview=Build.new();preview.from_dict(sim.build.to_dict())
	var before_synergies=sim.build.active_synergies()
	var before_rank=sim.build.stored_rank(id)
	var full=before_rank==0 and not sim.build.can_fit(id)
	if not full:preview.apply(id,"",result_grade)
	var after_rank=preview.stored_rank(id)
	var title=hud.label(item.name,27,Color("e8f3ef"),true)
	column.add_child(title)
	var grade_label=Rewards.quality_name(drop_grade).to_upper()
	if id in Catalog.ORGANS and before_rank>0:
		grade_label+="  ·  +%d РАНГА"%[Catalog.duplicate_rank_gain(drop_grade)]
	var quality_label=hud.label(grade_label,20,Rewards.quality_color(drop_grade),true)
	column.add_child(quality_label)
	var rank_text=("НОВЫЙ ОРГАН" if before_rank==0 and id in Catalog.ORGANS else ("НОВАЯ ПАССИВКА" if before_rank==0 else "РАНГ %d  →  %d"%[before_rank,after_rank]))
	var change=hud.label(rank_text,27,Color("b7f1dc"),true)
	column.add_child(change)
	var stat_change="Параметры покажу после выбора замены" if full else (_passive_change(id,sim.build,preview) if id in Catalog.ADAPTATIONS else Development.short_effect(id,preview,sim.ability_scale(),sim.cooldown_factor()))
	column.add_child(hud.label(stat_change,21,Color("c6ded8"),true))
	if drop_grade>0:
		card.add_theme_stylebox_override("panel",hud.box(Color("122e39").lerp(Rewards.quality_color(drop_grade),0.09),Rewards.quality_color(drop_grade),16))
	var activated=[]
	var related=[]
	for synergy_id in Catalog.SYNERGIES:
		var synergy=Catalog.SYNERGIES[synergy_id]
		if id not in synergy.needs:continue
		if synergy_id in preview.active_synergies() and synergy_id not in before_synergies:activated.append(synergy)
		elif synergy_id not in preview.active_synergies():related.append(synergy)
	for synergy in activated:
		var badge=hud.label("✦ СИНЕРГИЯ АКТИВИРОВАНА",21,Color("f2d487"),true)
		column.add_child(badge)
		column.add_child(hud.label(str(synergy.name)+" · "+str(synergy.desc),19,Color("e5c8ff"),true))
	for synergy in related:
		var partner=str(synergy.needs[1] if synergy.needs[0]==id else synergy.needs[0])
		var progress=1 if preview.rank(partner)>0 else 0
		column.add_child(hud.label("До синергии %d/2 · %s"%[progress+1,Catalog.item(partner).name],18,Color("c1a8dd"),true))
	var candidates=preview.evolution_candidates()
	for evolution_id in candidates:
		if evolution_id in sim.build.evolution_candidates():continue
		column.add_child(hud.label("✦ ДОСТУПЕН РЕЦЕПТ ЭВОЛЮЦИИ",20,Color("f1c36e"),true))
		column.add_child(hud.label(str(Catalog.EVOLUTIONS[evolution_id].name)+" · подробности в Кодексе",18,Color("e5c8ff"),true))
	column.add_child(hud.button("Заменить" if full else "ВЫБРАТЬ",callback,true))
	return card

func _passive_change(id: String,before,after)->String:
	var a=before.passive(id);var b=after.passive(id)
	match id:
		"regen":return "Лечение %.2f → %.2f HP/с"%[a,b]
		"armor":return "Снижение урона %.0f%% → %.0f%%"%[a*100.0,b*100.0]
		"speed":return "Скорость +%.0f%% → +%.0f%%"%[a*100.0,b*100.0]
		"magnet":return "Притяжение +%.0f → +%.0f"%[a,b]
		"metabolism":return "ДНК +%.0f%% → +%.0f%%"%[a*100.0,b*100.0]
		"catalysis":return "Урон органов +%.0f%% → +%.0f%%"%[a*100.0,b*100.0]
	return Development.short_effect(id,after,sim.ability_scale(),sim.cooldown_factor())

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
	var previous_synergies=sim.build.active_synergies().duplicate()
	var previous_evolutions=sim.build.evolution_candidates().duplicate()
	if (_lineage().award(id,int(sim.offer_quality.get(id,0))) if id in Catalog.ORGANS else sim.build.apply(id,"",int(sim.offer_quality.get(id,0)))):
		var new_synergies=[]
		for synergy_id in sim.build.active_synergies():
			if synergy_id not in previous_synergies:new_synergies.append(synergy_id)
		if not new_synergies.is_empty():
			_commit_level_pick()
			show_synergy_reveal(new_synergies,Callable(self,"_continue_after_level_pick"))
			return
		else:
			for evolution_id in sim.build.evolution_candidates():
				if evolution_id not in previous_evolutions:
					message("✦ ДОСТУПНА ЭВОЛЮЦИЯ\n%s · открой развитие, чтобы увидеть награду"%Catalog.EVOLUTIONS[evolution_id].name,5.5)
					break
		_complete_level()

func show_synergy_reveal(ids: Array,after: Callable=Callable()):
	set_stage("synergy_reveal")
	synergy_continue=after if after.is_valid() else Callable(self,"_complete_level")
	var first=str(ids[0])
	var synergy=Catalog.SYNERGIES[first]
	var box=hud.open_fixed("СИНЕРГИЯ ПРОБУДИЛАСЬ",str(synergy.name).to_upper()+" · ОРГАНИЗМ ИЗМЕНИЛСЯ",900)
	var art=OrganArt.new();art.sim=sim;art.custom_minimum_size=Vector2(350,300);art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	box.add_child(art)
	box.add_child(hud.label(str(synergy.desc),26,Color("e8d7f4"),true))
	for synergy_id in ids.slice(1):
		var extra=Catalog.SYNERGIES[str(synergy_id)]
		box.add_child(hud.label(str(extra.name)+" · "+str(extra.desc),22,Color("d5c2ea"),true))
	box.add_child(hud.button("ПРОДОЛЖИТЬ",finish_synergy_reveal,true))

func finish_synergy_reveal():
	var next=synergy_continue
	synergy_continue=Callable()
	if next.is_valid():next.call()

func _complete_level():
	_commit_level_pick()
	_continue_after_level_pick()

func _commit_level_pick():
	sim.pending_levels = maxi(0,sim.pending_levels-1)
	sim.current_offers = []
	sim.offer_quality = {}
	deferred_choices = false
	sim.rerolls = 0
	_tone(640)
	save_run()

func _continue_after_level_pick():
	if not sim.pending_inventory.is_empty(): _lineage().show_inventory_review()
	elif not deferred_choices and not sim.reward_queue.is_empty(): show_reward()
	elif not deferred_choices and sim.pending_levels>0: show_level()
	else: resume_game()

func _needs_replacement(id: String) -> bool:
	if id in Catalog.ORGANS:return sim.build.rank(id)==0 and not sim.build.can_fit(id)
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
		var inherited = mini(1+int(floor((sim.build.stored_rank(old)-1)/2.0)),Catalog.max_rank(id))
		var grade = int(sim.offer_quality.get(id,0)) if origin=="level" else (int(sim.reward_options[reward_index].get("quality",0)) if origin=="reward" else int(sim.world.colonies[active_shop].stock[stock].get("quality",0)))
		box.add_child(hud.button("Заменить %s · ранг %d → %d" % [Catalog.item(old).name,sim.build.stored_rank(old),inherited],func(): confirm_replacement(old)))
		box.add_child(hud.label(Rewards.quality_name(maxi(grade,sim.build.quality(old)))+((" · потеряется: "+", ".join(lost)) if not lost.is_empty() else ""),18,Rewards.quality_color(maxi(grade,sim.build.quality(old))),true))
		var projected=Build.new();projected.from_dict(sim.build.to_dict());projected.apply(id,old,grade)
		box.add_child(hud.label(Development.short_effect(id,projected,sim.ability_scale(),sim.cooldown_factor()),18,Color("b9d9cf"),true))
	box.add_child(hud.button("Отмена",func(): show_level() if origin=="level" else (show_reward() if origin=="reward" else show_shop())))

func confirm_replacement(old: String):
	if stage!="replace": return
	if replacement_origin=="reward":
		claim_reward(reward_index,old)
	elif replacement_origin=="shop":
		var item = sim.world.colonies[active_shop].stock[replacement_stock]
		if item.sold or sim.build.biomass<item.price: return
		var previous_synergies=sim.build.active_synergies().duplicate()
		if sim.build.apply(replacement_id,old,int(item.get("quality",0))):
			sim.build.spend(item.price)
			item.sold = true
			save_run()
			var activated=[]
			for synergy_id in sim.build.active_synergies():
				if synergy_id not in previous_synergies:activated.append(synergy_id)
			if not activated.is_empty():
				show_synergy_reveal(activated,Callable(self,"show_shop"))
				return
			show_shop()
	else:
		var previous_synergies=sim.build.active_synergies().duplicate()
		if sim.build.apply(replacement_id,old,int(sim.offer_quality.get(replacement_id,0))):
			var activated=[]
			for synergy_id in sim.build.active_synergies():
				if synergy_id not in previous_synergies:activated.append(synergy_id)
			if not activated.is_empty():
				_commit_level_pick()
				show_synergy_reveal(activated,Callable(self,"_continue_after_level_pick"))
			else:_complete_level()

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
		b.disabled = item.sold or sim.build.biomass<item.price or (item.id=="heal" and sim.hp>=sim.max_hp) or (item.id!="heal" and sim.build.stored_rank(item.id)>=Catalog.max_rank(item.id) and int(item.get("quality",0))<=sim.build.quality(item.id))
		col.add_child(b)
		if item.id!="heal":
			col.add_child(hud.label(Rewards.quality_name(int(item.get("quality",0))),18,Rewards.quality_color(int(item.get("quality",0))),true))
			var illustration=OrganArt.new()
			illustration.organ_id=item.id
			illustration.custom_minimum_size=Vector2(90,68)
			col.add_child(illustration)
			var projected=Build.new();projected.from_dict(sim.build.to_dict())
			projected.apply(str(item.id),"",int(item.get("quality",0)))
			col.add_child(hud.label(Development.short_effect(item.id,projected,sim.ability_scale(),sim.cooldown_factor()),17,Color("9fe0ca"),true))
		else:col.add_child(hud.label("+40 здоровья",18,Color("b3cfcb"),true))

	box.add_child(hud.button("Вернуться в микромир",resume_game))

func buy_shop(index: int):
	if stage!="shop" or active_shop<0: return
	var stock = sim.world.colonies[active_shop].stock
	if index<0 or index>=stock.size(): return
	var item = stock[index]
	if item.sold or sim.build.biomass<item.price: return
	var previous_synergies=sim.build.active_synergies().duplicate()
	if item.id=="heal":
		if sim.hp>=sim.max_hp: return
		sim.heal_player(40)
	elif _needs_replacement(item.id):
		show_replacement(item.id,"shop",index)
		return
	elif not (_lineage().award(item.id,int(item.get("quality",0))) if item.id in Catalog.ORGANS else sim.build.apply(item.id,"",int(item.get("quality",0)))): return
	sim.build.spend(item.price)
	item.sold = true
	save_run()
	_tone(480)
	var activated=[]
	for synergy_id in sim.build.active_synergies():
		if synergy_id not in previous_synergies:activated.append(synergy_id)
	if not activated.is_empty():
		show_synergy_reveal(activated,Callable(self,"show_shop"))
		return
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
	if stage not in ["game","pause","development","organ_mutations"]:return
	if stage in ["game","pause"]:
		development_origin=stage
		if not save_run():return
	_lineage().show_body(true)
	if journal:_lineage().show_statistics()

func close_development():
	_lineage().close_body()

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
	_lineage().show_legacy()

func show_imprints(origin: String="menu"):
	_lineage().show_pending(origin)

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
	if codex_view==null:codex_view=CodexView.new(self)
	codex_view.home()

func show_codex_entry(kind: String):
	if codex_view==null:codex_view=CodexView.new(self)
	codex_view.open_entry_for_kind(kind)

func show_help():
	set_stage("help")
	var box = hud.open("Как выжить в капле", "Движение — единственное действие во время боя.",850)
	box.add_child(hud.label("• Коснись любого свободного места экрана и веди палец: появится джойстик.\n• На ПК: WASD или стрелки; M — карта; E — колония; B — развитие; Esc — пауза.\n• Зелёные фрагменты ДНК повышают уровень. Янтарная биомасса нужна для покупок и перебросов. Фиолетовые ядра сохраняются между забегами.\n• Касание захватывает пищу: можно плыть дальше, пока она переваривается. Рецепторы открывают притягивание. Бирюзовые кусочки лечат. Рост меняет соотношение сил: бывшие хищники становятся пищей. Других врагов сначала ослабь; хищная пасть помогает поглощать их раньше.\n• Собирай пары органов: щупальца + кислота, шипы + импульс, деление + след, заражение + пасть.\n• На миникарте отмечаются гнёзда и угрозы. Посети гнёзда, победи местных минибоссов — это откроет маршрут к боссу ступени.\n• После победы выбирай сборку и особенности следующей процедурной области. Чем выше семейный рекорд, тем быстрее проходятся знакомые ступени.\n• Игра сохраняет забег при паузе и уходе в фон; в меню есть «Продолжить».",20,Color("b8d0cd"),true))
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
		if stage=="synergy_reveal":finish_synergy_reveal()
		if stage in ["game","map","shop","level","replace","reward"]: show_pause()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if stage=="game": show_pause()
		elif stage=="development": close_development()
		elif stage in ["level","reward","replace"]: close_modal()
		elif stage=="synergy_reveal":finish_synergy_reveal()
		elif stage=="stage_briefing":enter_next_stage()
		elif stage in ["pause","map","shop"]: resume_game()
		elif stage=="inherit":_close_imprints()
		elif stage in ["organ_detail","organ_picker","organ_exchange","organ_mutations"]:_lineage().show_body(_lineage().live_mode)
		elif stage=="capacity_notice":resume_game()
		elif stage in ["new_family","family_delete","family_error"]:show_menu()
		elif stage=="genome":_lineage().close_legacy()
		elif stage in ["atlas","codex_category","codex_entry","help","start","gallery","updates"]: show_menu()
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		save_run()
		get_tree().quit()

func _capture():
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var result = image.save_png(capture_path)
	print("CAPTURE: ",capture_path," status=",result)
	if capture_mode!="":store.clear_test_files()
	get_tree().quit()

func open_pending():
	deferred_choices = false
	if not sim.pending_inventory.is_empty(): _lineage().show_inventory_review()
	elif not sim.reward_queue.is_empty(): show_reward()
	elif sim.pending_levels>0: show_level()

func close_modal():
	match stage:
		"organ_detail","organ_picker","organ_exchange","organ_mutations","inventory_review":_lineage().show_body(_lineage().live_mode)
		"new_family","family_delete","family_error":show_menu()
		"menu": get_tree().quit()
		"genome":_lineage().close_legacy()
		"start","atlas","codex_category","codex_entry","help","gallery","results": show_menu()
		"development": close_development()
		"inherit": _close_imprints()
		"synergy_reveal":finish_synergy_reveal()
		"stage_briefing":enter_next_stage()
		"updates": show_menu()
		"level","reward","replace":
			deferred_choices = true
			save_run()
			resume_game()
		"capacity_notice":resume_game()
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
		elif option.kind=="temporary":
			var card=hud.card();card.custom_minimum_size.x=250;row.add_child(card)
			var column=VBoxContainer.new();card.add_child(column)
			var data=Catalog.temporary_mutation(str(option.id))
			var art_row=hud.row();column.add_child(art_row)
			var art=OrganArt.new();art.organ_id=str(data.get("organ","devour"));art.quality=int(option.quality);art.custom_minimum_size=Vector2(72,72);art_row.add_child(art)
			var title=hud.label(str(data.get("name",option.id)),21,Color(str(data.get("color","a9e5cf"))),true);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;art_row.add_child(title)
			column.add_child(hud.label("Временная · ранг %d → %d · %s"%[sim.build.temporary_mutation_rank(str(option.id)),mini(3,sim.build.temporary_mutation_rank(str(option.id))+1),Rewards.quality_name(int(option.quality))],18,Color("b6c9cb"),true))
			column.add_child(hud.label(str(data.get("summary","Временное усиление органа")),18,Color("9fe0ca"),true))
			column.add_child(hud.button("Встроить в тело",func():claim_reward(i),true))
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
	var previous_synergies=sim.build.active_synergies().duplicate()
	var option = sim.reward_options[index]
	if option.kind=="mutation" and replace_id=="" and _needs_replacement(option.id):
		reward_index = index
		show_replacement(option.id,"reward")
		return
	if option.kind=="mutation" and option.id in Catalog.ORGANS and replace_id=="":
		if sim.reward_queue.is_empty() or str(sim.reward_queue[0].token) in sim.claimed_rewards:return
		if not _lineage().award(str(option.id),int(option.quality)):return
		sim.claimed_rewards.append(str(sim.reward_queue[0].token));sim.reward_queue.pop_front();sim.reward_options.clear()
		sim._feedback("reward",sim.player,float(option.quality))
	else:
		if not sim.claim_reward(index,replace_id): return
	_tone(720)
	save_run()
	var activated=[]
	for synergy_id in sim.build.active_synergies():
		if synergy_id not in previous_synergies:activated.append(synergy_id)
	if not activated.is_empty():
		show_synergy_reveal(activated,Callable(self,"_continue_after_reward"))
		return
	_continue_after_reward()

func _continue_after_reward():
	if not sim.pending_inventory.is_empty(): _lineage().show_inventory_review()
	elif not sim.reward_queue.is_empty(): show_reward()
	elif sim.pending_levels>0: show_level()
	else: resume_game()
