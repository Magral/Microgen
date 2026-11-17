extends Node2D
const Sim = preload("res://game/simulation.gd")
const View = preload("res://game/world_view.gd")
const HUD = preload("res://ui/hud.gd")
const Save = preload("res://core/save_store.gd")
const Catalog = preload("res://core/catalog.gd")
const Map = preload("res://ui/minimap.gd")
const Genome = preload("res://core/genome.gd")
const Specimen = preload("res://ui/specimen_view.gd")
const Painter = preload("res://game/organism_painter.gd")
var store = Save.new()
var sim
var view
var hud
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
	sound_player = AudioStreamPlayer.new()
	sound_player.volume_db = -18
	add_child(sound_player)
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
			for id in ["acid","spikes","pulse","trail"]: sim.build.apply(id)
			sim.build.biomass = 47
			sim.elapsed = 142
			for i in range(16): sim.spawn_enemy(sim.player+Vector2.from_angle(i*TAU/16)*randf_range(160,440),"hunter" if i%3 else "prey")
			for i in range(18): sim.step(0.016,Vector2.ZERO)
			sim.paused = true
		elif capture_mode == "organic":
			organic_preview=load("res://tests/organic_preview.gd").new()
			organic_preview.setup(sim)
			hud.message.text="Ускоренная демонстрация роста и повреждений"
		elif capture_mode == "motion":
			sim.build.apply("acid")
			sim.spawn_enemy(sim.player+Vector2(90,25),"hunter")
			sim._die(sim.enemies.size()-1,false)
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
		elif sim.pending_levels>0:
			show_level()
		checkpoint_timer += dt
		if checkpoint_timer>=12:
			checkpoint_timer = 0
			save_run()
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
	# finger on the three HUD buttons while the first keeps the joystick.
	if event is InputEventScreenTouch:
		if not event.pressed and event.index==button_touch_id:
			var button = touched_button
			button_touch_id = -1
			touched_button = null
			get_viewport().set_input_as_handled()
			if is_instance_valid(button) and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position): button.pressed.emit()
			return
		if event.pressed and stage=="game" and stick_id>=0 and event.index!=stick_id:
			for button in [hud.pause_button,hud.map_button,hud.shop_button]:
				if button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
					button_touch_id = event.index
					touched_button = button
					get_viewport().set_input_as_handled()
					return
	# Release is observed even if a finger ends over a button or a modal opens.
	if event is InputEventScreenTouch and not event.pressed and event.index == stick_id: clear_stick()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and stick_id == -2: clear_stick()
	if stage!="game": return
	if event is InputEventScreenDrag and event.index == stick_id: _move_stick(event.position)
	if event is InputEventMouseMotion and stick_id == -2: _move_stick(event.position)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE: show_pause()
		if event.keycode==KEY_M: show_map()
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
	var box = hud.open("МИКРОГЕН", "Маленькая жизнь. Непредсказуемая эволюция.\nТестовая версия 0.5.0 · офлайн",740)
	box.add_child(hud.label("Собери организм, который сможет выжить.",25,Color("9ce3cf"),true))
	box.add_child(hud.label("Исследуй случайный микромир, поглощай ДНК и соединяй мутации. Атаки автоматические — управляй только движением.",20,Color("a3bfc0"),true))
	if not store.profile.checkpoint.is_empty(): box.add_child(hud.button("Продолжить забег",continue_run,true))
	box.add_child(hud.button("Новый организм",show_start,true))
	var row = hud.row()
	box.add_child(row)
	for entry in [["Геном",show_genome],["Атлас",show_atlas],["Как играть",show_help]]:
		var b = hud.button(entry[0],entry[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	box.add_child(hud.label("Ядра наследия: %d   ·   Забеги: %d   ·   Победы: %d" % [store.profile.cores,store.profile.runs,store.profile.wins],18,Color("ccb2e7")))
	var footer_actions=hud.row()
	box.add_child(footer_actions)
	var gallery_button=hud.button("Случайные формы · коллекция",show_gallery)
	gallery_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer_actions.add_child(gallery_button)
	footer_actions.add_child(hud.button("Выход",exit_game))
	box.add_child(hud.label("2 области · 8 органов · 4 синергии · процедурные организмы",16,Color("78989f"),true))

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

func show_start():
	set_stage("start")
	var box = hud.open("Наследственный геном", "Выбранная ветка немного чаще встречается при прокачке. Мир создаётся заново для каждого организма.",800)
	if not store.profile.checkpoint.is_empty(): box.add_child(hud.label("Новый забег заменит незавершённый. Открытия и ядра сохранятся.",18,Color("e9b99b"),true))
	var row = hud.row()
	box.add_child(row)
	for branch in ["predator","toxic","colony"]:
		var title = {"predator":"Хищник","toxic":"Токсин","colony":"Колония"}[branch]
		var b = hud.button(("● " if selected_branch==branch else "")+title,func(): selected_branch=branch; show_start())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	box.add_child(hud.label("Хищник: щупальца, шипы, поглощение.\nТоксин: кислота, заражение, ядовитый след.\nКолония: деление; сначала открой его в разделе «Геном».",20,Color("b8d2cf"),true))
	box.add_child(hud.button("Начать эволюцию",func(): start_run(),true))
	box.add_child(hud.button("Назад",show_menu))

func start_run(seed_value: int = -1):
	if seed_value<0: seed_value = int(Time.get_unix_time_from_system()*1000)%2147483647
	sim = Sim.new()
	sim.new_run(seed_value,store.profile.unlocked,store.profile.upgrades,selected_branch)
	view.sim = sim
	checkpoint_timer = 0
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
	if sim.pending_levels>0: show_level()

func save_run():
	if sim==null or stage in ["menu","start","genome","atlas","help","results","gallery"]: return
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
	box.add_child(hud.label("Ядра наследия: %d\nИзученные синергии: %d/4" % [store.profile.cores,store.profile.synergies.size()],22))
	box.add_child(hud.button("Новый организм",show_start,true))
	box.add_child(hud.button("Развить геном",show_genome))
	box.add_child(hud.button("В меню",show_menu))

func show_level():
	set_stage("level")
	if sim.current_offers.is_empty(): sim.current_offers = sim.build.offers(sim.rng)
	var box = hud.open("Мутация · уровень %d" % sim.level,"Выбери одно улучшение. Новые органы можно заменить прямо здесь. Биомасса: %d" % sim.build.biomass)
	var row = hud.row()
	box.add_child(row)
	if sim.current_offers.is_empty():
		box.add_child(hud.label("Все доступные мутации развиты. Получи 15 биомассы.",22))
		box.add_child(hud.button("Поглотить ДНК",func(): sim.build.biomass+=15; _complete_level(),true))
	else:
		for id in sim.current_offers: row.add_child(_mutation_card(id,func(): choose_mutation(id)))
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

func _mutation_card(id: String,callback: Callable) -> PanelContainer:
	var card = hud.card()
	card.custom_minimum_size.x = 250
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	card.add_child(column)
	var item = Catalog.item(id)
	column.add_child(hud.label(item.name,23,Color(item.color),true))
	var rank = sim.build.rank(id)
	column.add_child(hud.label(("Новый орган" if id in Catalog.ORGANS else "Адаптация") if rank==0 else "Уровень %d → %d" % [rank,rank+1],17,Color("97b6ba")))
	var description = hud.label(item.desc,19,Color("c5d8d7"),true)
	description.custom_minimum_size.y = 66
	column.add_child(description)
	var hints = hud.label(Catalog.synergy_hint(id,sim.build.organs),16,Color("d0b3e8"),true)
	hints.custom_minimum_size.y = 75
	column.add_child(hints)
	var full = sim.build.rank(id)==0 and ((id in Catalog.ORGANS and sim.build.organs.size()>=6) or (id in Catalog.ADAPTATIONS and sim.build.adaptations.size()>=4))
	column.add_child(hud.button("Заменить орган" if full else "Выбрать",callback,true))
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
	show_level()

func choose_mutation(id: String):
	if stage!="level" or id not in sim.current_offers or sim.pending_levels<=0: return
	if _needs_replacement(id):
		show_replacement(id,"level")
		return
	if sim.build.apply(id): _complete_level()

func _complete_level():
	sim.pending_levels = maxi(0,sim.pending_levels-1)
	sim.current_offers = []
	sim.rerolls = 0
	_tone(640)
	if sim.pending_levels>0: show_level()
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
		box.add_child(hud.button(text,func(): confirm_replacement(old)))
	box.add_child(hud.button("Отмена",func(): show_level() if origin=="level" else show_shop()))

func confirm_replacement(old: String):
	if stage!="replace": return
	if replacement_origin=="shop":
		var item = sim.world.colonies[active_shop].stock[replacement_stock]
		if item.sold or sim.build.biomass<item.price: return
		if sim.build.apply(replacement_id,old):
			sim.build.spend(item.price)
			item.sold = true
			save_run()
			show_shop()
	else:
		if sim.build.apply(replacement_id,old): _complete_level()

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
		col.add_child(hud.label("Восстановить 40 здоровья" if item.id=="heal" else Catalog.item(item.id).desc,19,Color("b3cfcb"),true))
		if item.id!="heal": col.add_child(hud.label(Catalog.synergy_hint(item.id,sim.build.organs),16,Color("ccb0e5"),true))
		var b = hud.button("Получено" if item.sold else "Купить · %d" % item.price,func(): buy_shop(i),true)
		b.disabled = item.sold or sim.build.biomass<item.price or (item.id=="heal" and sim.hp>=sim.max_hp) or (item.id!="heal" and sim.build.rank(item.id)>=Catalog.max_rank(item.id))
		col.add_child(b)
	box.add_child(hud.button("Вернуться в микромир",resume_game))

func buy_shop(index: int):
	if stage!="shop" or active_shop<0: return
	var stock = sim.world.colonies[active_shop].stock
	if index<0 or index>=stock.size(): return
	var item = stock[index]
	if item.sold or sim.build.biomass<item.price: return
	if item.id=="heal":
		if sim.hp>=sim.max_hp: return
		sim.hp = minf(sim.max_hp,sim.hp+40)
	elif _needs_replacement(item.id):
		show_replacement(item.id,"shop",index)
		return
	elif not sim.build.apply(item.id): return
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
	box.add_child(hud.button("Карта микромира",show_map))
	box.add_child(hud.button("Звук: "+("вкл." if sound_enabled else "выкл."),func(): sound_enabled=not sound_enabled; show_pause()))
	box.add_child(hud.button("Сохранить и выйти в меню",func(): save_run(); show_menu()))
	box.add_child(hud.label("Seed: %d · %s" % [sim.world.seed_value,sim.run_id],15,Color("75949c"),true))

func resume_game():
	hud.close()
	set_stage("game")
	hud.game_visible(true)
	hud.update_game(sim)
	if sim.pending_levels>0: show_level()

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
	var box = hud.open("Наследственный геном", "Ядра: %d. Открытия сохраняются после гибели; бонусы имеют предел." % store.profile.cores)
	var division_unlocked = "division" in store.profile.unlocked
	var b = hud.button("Деление: открыто" if division_unlocked else "Открыть деление · 8 ядер",func(): store.unlock("division"); show_genome(),true)
	b.disabled = division_unlocked or store.profile.cores<8
	box.add_child(b)
	box.add_child(hud.label("Деление + ядовитый след → Токсичная колония",18,Color("cfb0e6"),true))
	for id in ["health","collect","regen"]:
		var rank = int(store.profile.upgrades[id])
		var title = {"health":"Жизнеспособность: +5 здоровья","collect":"Чувствительность: +8 к радиусу рецепторов","regen":"Обмен веществ: +0,1 HP/сек."}[id]
		var btn = hud.button("%s  ·  %d/5  ·  %s" % [title,rank,"Максимум" if rank>=5 else str(4+rank*4)+" ядер"],func(): store.buy_upgrade(id); show_genome())
		btn.disabled = rank>=5 or store.profile.cores<4+rank*4
		box.add_child(btn)
	box.add_child(hud.button("В меню",show_menu))

func show_atlas():
	set_stage("atlas")
	var box = hud.open("Атлас эволюции", "Изучи органы в забегах и открой все четыре сочетания.")
	for id in Catalog.SYNERGIES:
		var item = Catalog.SYNERGIES[id]
		var known = id in store.profile.synergies
		box.add_child(hud.label(("✓ " if known else "◇ ")+item.name,23,Color("c8abe8")))
		var text = Catalog.item(item.needs[0]).name+" + "+Catalog.item(item.needs[1]).name
		box.add_child(hud.label(text+"\n"+(item.desc if known else "Собери оба органа, чтобы изучить взаимодействие."),18,Color("a8c5c5"),true))
	box.add_child(hud.label("Органы и адаптации",25))
	for id in Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys():
		var state = "Изучен" if id in store.profile.discovered else ("Доступен" if id in store.profile.unlocked else "Закрыт: геном")
		box.add_child(hud.label(Catalog.item(id).name+" — "+state,19,Color("a9ceca"),true))
	box.add_child(hud.button("В меню",show_menu))

func show_help():
	set_stage("help")
	var box = hud.open("Как выжить в капле", "Движение — единственное действие во время боя.",850)
	box.add_child(hud.label("• Коснись любого свободного места экрана и веди палец: появится джойстик.\n• На ПК: WASD или стрелки; M — карта; E — колония; Esc — пауза.\n• Зелёные фрагменты ДНК повышают уровень. Янтарная биомасса нужна для покупок и перебросов. Фиолетовые ядра сохраняются между забегами.\n• Касание захватывает пищу: можно плыть дальше, пока она переваривается. Рецепторы открывают притягивание. Бирюзовые кусочки лечат. Рост меняет соотношение сил: бывшие хищники становятся пищей. Других врагов сначала ослабь; хищная пасть помогает поглощать их раньше.\n• Собирай пары органов: щупальца + кислота, шипы + импульс, деление + след, заражение + пасть.\n• На миникарте отмечаются изученные места. Светлые колонии безопасны; внутри доступен магазин.\n• Оформление, проходы, местные условия, находки и противники меняются с каждым seed.\n• На 10-й минуте появляется Архицит. Найди его по карте и победи. Таймер не завершает забег автоматически.\n• Игра сохраняет забег при паузе и уходе в фон; в меню есть «Продолжить».",20,Color("b8d0cd"),true))
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
		if stage in ["game","map","shop","level","replace"]: show_pause()
	elif what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if stage=="game": show_pause()
		elif stage in ["pause","map","shop"]: resume_game()
		elif stage in ["genome","atlas","help","start","gallery"]: show_menu()
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		save_run()
		get_tree().quit()

func _capture():
	await RenderingServer.frame_post_draw
	var image = get_viewport().get_texture().get_image()
	var result = image.save_png(capture_path)
	print("CAPTURE: ",capture_path," status=",result)
	get_tree().quit()
