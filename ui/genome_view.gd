extends RefCounted
# Presentation only: persistence and generation changes belong to the caller.
const Legacy = preload("res://core/genome_legacy.gd")
const Art = preload("res://ui/organ_art.gd")
const Catalog = preload("res://core/catalog.gd")
const Genome = preload("res://core/genome.gd")
const Painter = preload("res://game/organism_painter.gd")
const GREEN = Color("9ce3cf")
const MUTED = Color("a5c4c4")

class LargePreview extends "res://ui/organ_art.gd":
	func _draw():
		# OrganArt's normal inspector radius is 57px; enlarge the living body here.
		var zoom = 1.8 if size.y>=280 else 1.1
		draw_set_transform(size * 0.5 * (1.0-zoom),0,Vector2.ONE*zoom)
		super._draw()

class ImprintArt extends "res://ui/organ_art.gd":
	var recipe: Dictionary = {}
	func _draw():
		if not Genome.validate(recipe):
			super._draw()
			return
		if painter==null:painter=Painter.new()
		painter.paint(self,size/2,minf(size.x,size.y)*0.28,recipe,{organ_id:1},animation_time,"player",true,null,[],Genome.colors(recipe)[0],0.0,1.0,0.2,{"qualities":{},"evolved":{}})

static func _section(hud,box,title: String):
	box.add_child(hud.label(title,26,GREEN,true))

static func _column(hud,box):
	var card=hud.card()
	box.add_child(card)
	var column=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",10)
	card.add_child(column)
	return column

static func _action(hud,box,text: String,callbacks: Dictionary,key: String,args: Array=[],enabled: bool=true,primary: bool=false):
	var callback: Callable=callbacks.get(key,Callable())
	var button=hud.button(text,func():
		if callback.is_valid():callback.callv(args)
	,primary)
	button.disabled=not enabled or not callback.is_valid()
	button.name="%s_%s" % [key,str(args[0]) if not args.is_empty() else "action"]
	button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	box.add_child(button)
	return button

static func _preview(hud,box,sim,caption: String,height: float=300):
	var column=_column(hud,box)
	var art=LargePreview.new()
	art.name="LivingPreview"
	art.sim=sim
	art.custom_minimum_size=Vector2(0,height)
	art.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_child(art)
	column.add_child(hud.label(caption,22,GREEN,true))
	return art

static func populate_start(hud,box,store,preview_sim,callbacks: Dictionary):
	var state=Legacy.normalize(store.profile)
	var loadout=Legacy.loadout(store.profile)
	var form=Legacy.FORMS.get(loadout.form,Legacy.FORMS.predator)
	_preview(hud,box,preview_sim,"%s · %s\nПризнаки %d/2 · отпечаток %d/1" % [form.name,Catalog.item(form.organ).name,loadout.traits.size(),0 if str(loadout.imprint)=="" else 1])
	var can_start=state.pending_queue.size()<8
	_action(hud,box,"Начать жизнь" if can_start else "Сначала сохраните ожидающее наследие",callbacks,"start",[],can_start,true)
	if not can_start:_action(hud,box,"Выбрать отпечаток",callbacks,"imprints")
	_action(hud,box,"Изменить внешность",callbacks,"reroll")
	box.add_child(hud.label("Меняется только рисунок тела. Форма, органы и эффекты сохраняются.",20,MUTED,true))
	_section(hud,box,"Стартовая форма · 1 из 3")
	for id in Legacy.FORMS:
		var data=Legacy.FORMS[id]
		var unlocked=id in state.forms
		var column=_column(hud,box)
		column.add_child(hud.label(data.name+(" · выбрана" if loadout.form==id else ""),24,GREEN,true))
		column.add_child(hud.label(data.desc,22,MUTED,true))
		column.add_child(hud.label("Старт: %s · ранг 1" % Catalog.item(data.organ).name,22,GREEN,true))
		if not unlocked:column.add_child(hud.label("Закрыто · исследование «%s»" % Legacy.RESEARCH[data.research].name,20,Color("dcc399"),true))
		_action(hud,column,"Выбрана" if loadout.form==id else ("Выбрать форму" if unlocked else "Требуется исследование"),callbacks,"form",[id],unlocked and loadout.form!=id)
	_section(hud,box,"Наследственные признаки · %d/2" % loadout.traits.size())
	box.add_child(hud.label("Два места: выбирай преимущество вместе с ограничением. Можно оставить пустыми.",20,MUTED,true))
	for id in Legacy.TRAITS:
		var data=Legacy.TRAITS[id]
		var selected=id in loadout.traits
		var unlocked=id in state.traits
		var column=_column(hud,box)
		column.add_child(hud.label(data.name+(" · выбран" if selected else ""),24,GREEN,true))
		column.add_child(hud.label(data.desc+"\nОграничение: "+data.tradeoff+"\nТело: "+data.visual,22,MUTED,true))
		_action(hud,column,"Убрать признак" if selected else ("Выбрать признак" if unlocked else "Изучить в геноме"),callbacks,"trait",[id],unlocked and (selected or loadout.traits.size()<2))
	_section(hud,box,"Отпечаток · 1 место")
	box.add_child(hud.label("Передаётся орган ранга 1 обычного качества или одна особенность тела. Полная сборка предка не переносится.",20,MUTED,true))
	_action(hud,box,"Без отпечатка"+(" · выбрано" if str(loadout.imprint)=="" else ""),callbacks,"imprint",[""])
	for item in state.imprints:
		_imprint_card(hud,box,item,callbacks,"imprint",str(loadout.imprint)==str(item.id))
	_section(hud,box,"Сохранённые наборы · 3 места")
	for index in range(3):
		var preset_name="Набор %d" % (index+1)
		var actual=-1
		for i in range(state.presets.size()):
			if state.presets[i].name==preset_name:actual=i
		if actual<0 and index<state.presets.size() and not str(state.presets[index].name).begins_with("Набор "):actual=index
		var load_button=_action(hud,box,"Загрузить · "+preset_name+(" · пусто" if actual<0 else ""),callbacks,"load_preset",[actual],actual>=0)
		load_button.name="load_preset_%d" % index
		_action(hud,box,"Сохранить в набор %d" % (index+1),callbacks,"save_preset",[index])
	_action(hud,box,"Назад",callbacks,"back")

static func populate_genome(hud,box,store,preview_sim,callbacks: Dictionary):
	var state=Legacy.normalize(store.profile)
	_preview(hud,box,preview_sim,"Генетическая память · поколение %d\nЯдра наследия: %d" % [state.generation,int(store.profile.get("cores",0))],200)
	if str(state.focus)!="":
		var progress=Legacy.focus_progress_in(store.profile,state)
		var name=Legacy.RESEARCH.get(state.focus,{}).get("name",state.focus)
		box.add_child(hud.label("Цель: %s · ядра %d/%d · изучение %d\nДо оплаты: %d ядер" % [name,progress.cores,progress.cost,progress.knowledge,progress.remaining],22,GREEN,true))
	for branch in ["structure","adaptation","memory"]:
		_section(hud,box,{"structure":"Строение","adaptation":"Приспособление","memory":"Генетическая память"}[branch])
		for id in Legacy.RESEARCH:
			var data=Legacy.RESEARCH[id]
			if data.branch!=branch:continue
			var complete=id in state.research
			var progress=Legacy.focus_progress_in(store.profile,state,id)
			var column=_column(hud,box)
			column.add_child(hud.label(data.name+(" · изучено" if complete else ""),24,GREEN,true))
			column.add_child(hud.label(data.effect+"\nТело: "+data.visual,22,MUTED,true))
			if id in Legacy.TRAITS:
				var trait_data=Legacy.TRAITS[id]
				column.add_child(hud.label(trait_data.desc+"\nОграничение: "+trait_data.tradeoff,22,MUTED,true))
			var requirements=[]
			for required in data.requires:requirements.append(("✓ " if required in state.research else "◇ ")+Legacy.RESEARCH[required].name)
			column.add_child(hud.label("Условия: "+("нет" if requirements.is_empty() else ", ".join(requirements))+"\nСтоимость: %d ядер · есть %d · изучение ветви %d" % [progress.cost,progress.cores,progress.knowledge],20,MUTED,true))
			_action(hud,column,"Изучено" if complete else "Исследовать · %d ядер" % progress.cost,callbacks,"research",[id],not complete and progress.ready)
			if not complete:_action(hud,column,"Цель выбрана" if state.focus==id else "Отслеживать в итогах",callbacks,"focus",[id],state.focus!=id)
	_section(hud,box,"Сохранённое наследие · предел 5")
	for id in ["health","collect","regen"]:
		var rank=int(store.profile.get("upgrades",{}).get(id,0))
		var text={"health":"Здоровье +%d HP → +%d HP" % [rank*5,mini(5,rank+1)*5],"collect":"Сбор +%d → +%d к радиусу" % [rank*8,mini(5,rank+1)*8],"regen":"Регенерация +%.1f → +%.1f HP/с" % [rank*0.1,mini(5,rank+1)*0.1]}[id]
		box.add_child(hud.label("%s · %d/5" % [text,rank],22,MUTED,true))
		_action(hud,box,"Предел достигнут" if rank>=5 else "Улучшить · %d ядер" % (4+rank*4),callbacks,"upgrade",[id],rank<5 and int(store.profile.get("cores",0))>=4+rank*4)
	_section(hud,box,"Последние поколения")
	if state.history.is_empty():box.add_child(hud.label("История появится после первой завершённой жизни.",20,MUTED,true))
	for life in state.history:
		var form_name=Legacy.FORMS.get(life.form,{}).get("name","Первичная амёба")
		box.add_child(hud.label("Поколение %d · %s · %d:%02d · %s" % [life.generation,form_name,int(life.elapsed)/60,int(life.elapsed)%60,"победа" if life.outcome=="victory" else "жизнь завершена"],20,MUTED,true))
	_action(hud,box,"Отпечатки · %d ожидают" % state.pending.size(),callbacks,"imprints")
	_action(hud,box,"Назад",callbacks,"back")

static func _imprint_organ(id: String) -> String:
	if id.begins_with("trait:"):
		return {"elastic":"regen","sensory":"magnet","folds":"devour","receptive":"catalysis"}.get(id.trim_prefix("trait:"),"regen")
	return id

static func _imprint_name(id: String) -> String:
	if id.begins_with("trait:"):return Legacy.TRAITS.get(id.trim_prefix("trait:"),{}).get("name","Особенность тела")
	return Catalog.item(id).name

static func _imprint_description(id: String) -> String:
	if id.begins_with("trait:"):
		var data=Legacy.TRAITS.get(id.trim_prefix("trait:"),{})
		return str(data.get("desc",""))+"\nОграничение: "+str(data.get("tradeoff",""))+"\nТело: "+str(data.get("visual",""))
	return Catalog.item(id).desc

static func _imprint_card(hud,box,item: Dictionary,callbacks: Dictionary,key: String,selected: bool=false):
	var column=_column(hud,box)
	var art=ImprintArt.new()
	art.organ_id=_imprint_organ(str(item.id))
	art.recipe=item.get("recipe",{})
	art.custom_minimum_size=Vector2(0,170)
	column.add_child(art)
	var origin=item.get("origin",{})
	var biome=origin.get("biome",0)
	var area="Питательная среда" if str(biome)=="0" else ("Токсичная зона" if str(biome)=="1" else str(biome))
	column.add_child(hud.label(str(item.get("name",_imprint_name(str(item.id))))+(" · выбран" if selected else ""),24,GREEN,true))
	var inheritance="особенность тела" if str(item.id).begins_with("trait:") else "ранг 1 · обычное качество"
	column.add_child(hud.label("Поколение %d · %s · %d сек.\nПотомок: %s · %s" % [int(origin.get("generation",0)),area,int(origin.get("elapsed",0)),_imprint_name(str(item.id)),inheritance],20,MUTED,true))
	column.add_child(hud.label(_imprint_description(str(item.id)),22,MUTED,true))
	_action(hud,column,"Выбран" if selected else "Передать отпечаток",callbacks,key,[str(item.id)],not selected)

static func populate_imprints(hud,box,store,callbacks: Dictionary):
	var state=Legacy.normalize(store.profile)
	_section(hud,box,"Один отпечаток для следующего поколения")
	box.add_child(hud.label("Выбери орган или особенность тела. После выбора остальные кандидаты этого поколения исчезнут. Ранг и качество предка не передаются.",22,MUTED,true))
	if state.pending.is_empty():box.add_child(hud.label("Нет ожидающих отпечатков. Освой орган в новой жизни, чтобы сохранить его ткань.",22,MUTED,true))
	if not state.get("pending_queue",[]).is_empty():box.add_child(hud.label("Ещё поколений с отпечатками: %d. Их выбор появится после текущего." % state.pending_queue.size(),20,MUTED,true))
	for item in state.pending:_imprint_card(hud,box,item,callbacks,"claim")
	box.add_child(hud.label("Можно отложить выбор: кандидаты сохранятся. Крестик закрывает этот экран без передачи отпечатка.",20,MUTED,true))
	_action(hud,box,"Выбрать позже",callbacks,"back")
