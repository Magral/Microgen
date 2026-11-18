extends RefCounted
const Equipment=preload("res://core/organism_equipment.gd")
const Slots=preload("res://core/organism_slots.gd")
const Home=preload("res://ui/family_home.gd")
const Body=preload("res://ui/organism_view.gd")
const Sim=preload("res://game/simulation.gd")
const Legacy=preload("res://core/genome_legacy.gd")
const Heredity=preload("res://game/heredity.gd")
const Build=preload("res://core/build_model.gd")
const Inspector=preload("res://core/build_inspector.gd")
const Development=preload("res://ui/development_view.gd")
const Catalog=preload("res://core/catalog.gd")
const Rewards=preload("res://core/rewards.gd")
var app
var live_mode=false
var pages={"alive":0,"ancestral":0}
var body_page=0
var stock_page=0
var run_state={}
var run_family=""
var preview
var incoming=""
var selected=[]
var picker_mode="stock"
var last_award_location=""

func _init(owner):app=owner

func family_name() -> String:
	for entry in app.store.family_summaries():
		if entry.id==app.store.family_id():return entry.name
	return "Новое семейство"

func _profile_for(id: String) -> Dictionary:
	if id==app.store.family_id():return app.store.profile
	for entry in app.store.profile.families.items:
		if entry.id==id:return entry.state
	return {}

func _entries() -> Array:
	var result=app.store.family_summaries()
	for entry in result:
		var profile=_profile_for(entry.id)
		var checkpoint=profile.get("checkpoint",{})
		entry.recipe=checkpoint.get("player_genome",{})
		if entry.recipe.is_empty():entry.recipe=Heredity.recipe(Legacy.loadout({"legacy":profile.legacy,"unlocked":profile.unlocked}))
		var equipment=Equipment.from_profile(profile)
		if not equipment.is_empty():entry.organs=Equipment.aggregate(equipment).organs
		elif not checkpoint.is_empty():entry.organs=checkpoint.build.organs
	return result

func show_home():
	live_mode=false
	app.set_stage("menu")
	app.sim=Sim.new();app.sim.new_run(14481);app.sim.paused=true
	app.view.sim=app.sim;app.hud.game_visible(false)
	var box=app.hud.open_home(1120)
	Home.populate(app.hud,box,_entries(),{"resume":func(id):select_family(id,true),"prepare":func(id):select_family(id,false),"delete":confirm_delete,"new":show_new,"page":func(group,index):pages[group]=index;show_home(),"genome":app.show_genome,"atlas":app.show_atlas,"help":app.show_help,"updates":app.show_updates,"exit":app.exit_game},pages)
	var version=app.hud.label("Версия %s · игра без интернета"%ProjectSettings.get_setting("application/config/version","1.0.1"),20)
	version.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;box.add_child(version)

func show_new():
	live_mode=false;app.set_stage("new_family")
	var box=app.hud.open_fixed("Новое семейство","Выбери базовую форму. Прежние семейства и их жизни сохранятся.")
	Body.forms(app.hud,box,{"choose":create_family,"back":show_home})

func create_family(form: String):
	var name="Семейство %d"%int(app.store.profile.families.next_id)
	if not app.store.create_family(name,form):app.message(app.store.last_error,5);return
	body_page=0;stock_page=0
	show_preparation()

func select_family(id: String,resume: bool):
	if not app.store.select_family(id):app.message(app.store.last_error,5);return
	run_state={};run_family="";body_page=0;stock_page=0
	if resume or not app.store.profile.checkpoint.is_empty():app.continue_run()
	else:show_preparation()

func confirm_delete(id: String):
	var name="семейство"
	for entry in app.store.family_summaries():
		if entry.id==id:name=entry.name
	app.set_stage("family_delete")
	var box=app.hud.open_fixed("Удалить "+name+"?","Удалятся сохранённая жизнь, органы, материалы и наследие только этого семейства.",850)
	box.add_child(app.hud.label("Другие семейства сохранятся. Это действие нельзя отменить.",24))
	var row=app.hud.row();box.add_child(row)
	row.add_child(app.hud.button("Оставить",show_home,true))
	row.add_child(app.hud.button("Удалить семейство",func():
		if not app.store.delete_family(id):app.message(app.store.last_error,5);return
		run_state={};run_family="";show_home()))

func ensure_family() -> bool:
	if not app.store.family_id().is_empty():return true
	return app.store.create_family("Семейство %d"%int(app.store.profile.families.next_id),str(app.store.profile.legacy.selected_form))

func state() -> Dictionary:
	if live_mode and run_family==app.store.family_id() and not run_state.is_empty():return run_state.duplicate(true)
	return Equipment.from_profile(app.store.profile)

func bind_run(value: Dictionary):
	run_state=value.duplicate(true);run_family=app.store.family_id()

func capture(build: Dictionary) -> Dictionary:
	var current=run_state if run_family==app.store.family_id() and not run_state.is_empty() else Equipment.from_profile(app.store.profile)
	var result=Equipment.refresh(current,build)
	if not result.ok:return {}
	var next=result.state
	for kind in build.get("stats",{}).get("evolutions",{}):
		if not bool(build.stats.evolutions[kind]):continue
		var matching=next.equipped.filter(func(part):return part.kind==kind)
		if not matching.is_empty() and not matching.any(func(part):return part.get("evolved",false)):matching[0].evolved=true
	bind_run(next)
	return next

static func apply_to_build(value: Dictionary,build):
	var merged=Equipment.aggregate(value)
	build.organs=merged.organs
	build.specializations=merged.specializations
	for kind in Catalog.ORGANS:
		build.qualities.erase(kind)
		build.stats.evolutions.erase(kind)
	for kind in merged.qualities:build.qualities[kind]=merged.qualities[kind]
	for part in value.equipped:
		if part.get("evolved",false) and part.kind in Catalog.EVOLUTIONS:build.stats.evolutions[part.kind]=true
	for kind in build.organs:
		if kind not in build.unlocked:build.unlocked.append(kind)
	build.organ_capacity=int(value.body_capacity)
	var by_kind=0
	for kind in build.organs:by_kind+=Equipment.cell_cost(kind)
	build.extra_organ_cells=maxi(0,Slots.used_cells(value)-by_kind)

func show_preparation():
	live_mode=false
	if not ensure_family():app.message(app.store.last_error,5);return
	if not app.store.profile.checkpoint.is_empty():app.continue_run();return
	var value=state()
	if value.is_empty():_error("Не удалось прочитать органы семейства");return
	if not app.store.profile.has("organism"):
		var next=app.store.profile.duplicate(true);next.organism=value
		if not app.store.write_profile(next):_error(app.store.last_error);return
	show_body(false)

func show_body(live: bool):
	live_mode=live
	var value=state()
	if value.is_empty():_error("Не удалось прочитать органы");return
	if live and (app.sim==null or app.sim.family_id!=app.store.family_id()):_error("Эта жизнь принадлежит другому семейству");return
	app.set_stage("development" if live else "start");app.hud.game_visible(false)
	preview=app.sim if live else app._legacy_preview()
	if not live:apply_to_build(value,preview.build)
	var model=value.duplicate(true);model.family_name=family_name();model.live=live;model.stock_page=stock_page
	model.organium=int(app.store.profile.get("organium",0));model.organ_materials=app.store.profile.get("organ_materials",{}).duplicate(true)
	var box=app.hud.open_fixed("Организм","Нажми на орган или свободные ячейки. Перестановка бесплатна; бой на паузе.")
	Body.populate(app.hud,box,model,preview,{"part":show_part,"empty_body":func():show_picker("stock"),"empty_stock":show_stock_sources,"page":func(index):body_page=index;show_body(live_mode),"stock_page":func(index):stock_page=index;show_body(live_mode),"start":app.start_run,"back":close_body,"archive":func():show_picker("archive"),"legacy":app.show_genome,"mutations":show_statistics,"reroll":func():
		if app.store.reroll_morphology():show_body(false)},body_page)

func close_body():
	if not live_mode:show_home()
	elif app.sim!=null and app.sim.stage_transition:app.show_stage_briefing()
	elif app.development_origin=="pause":app.show_pause()
	else:app.resume_game()

func show_part(id: String,tab: String="stats"):
	var value=state();var part={};var location=""
	for group in ["equipped","stock","reserve"]:
		for item in value[group]:
			if item.id==id:part=item.duplicate(true);location=group
	if part.is_empty():return
	var part_preview=app._legacy_preview()
	part_preview.build.organs={part.kind:int(part.rank)}
	part_preview.build.qualities={part.kind:int(part.quality)}
	part_preview.build.stats.evolutions={part.kind:true} if part.get("evolved",false) else {}
	var source=app.sim if live_mode else preview
	var projected=Build.new();projected.from_dict(source.build.to_dict());projected.organs[part.kind]=int(part.rank);projected.qualities[part.kind]=int(part.quality)
	projected.specializations[part.kind]=str(part.get("specialization",""))
	if part.get("evolved",false):projected.stats.evolutions[part.kind]=true
	else:projected.stats.evolutions.erase(part.kind)
	part.effect_text=Inspector.effect_text(projected,part.kind,source.ability_scale(),source.cooldown_factor())
	part.detail_tab=tab
	if part.kind in Catalog.EVOLUTIONS:
		var recipe=Catalog.EVOLUTIONS[part.kind]
		part.growth_text="%s · ранг %d\nПассив: %s · %d/3 · урон органа ×1,30"%[recipe.name,int(part.rank),Catalog.item(recipe.passive).name,source.build.rank(recipe.passive)]
	else:part.growth_text=Catalog.milestone_text(part.kind,int(part.rank))
	part.synergy_text=Inspector.synergy_summary((app.sim if live_mode else preview).build,part.kind)
	part.organium=int(app.store.profile.get("organium",0));part.upgrade_cost=Equipment.upgrade_cost(part)
	part.upgrade_ingredient=mini(128,1+int(floor(float(part.rank)/8.0)))
	var current_spec=str(part.get("specialization",""))
	var active_spec=Catalog.specialization_data(part.kind,current_spec)
	part.specialization_name=str(active_spec.get("name","Нет"))
	part.specialization_effect=str(active_spec.get("name","Не выбрана"))
	var resources=app.store.profile.get("organ_materials",{})
	part.materials_available=resources.duplicate(true)
	part.specialization_options=[]
	for choice in Catalog.SPECIALIZATIONS.get(part.kind,[]):
		var option=choice.duplicate(true)
		option.active=str(option.id)==current_spec
		option.cost=12 if current_spec.is_empty() else mini(9007199254740991,18+int(part.rank))
		option.ingredient=1 if current_spec.is_empty() else 2
		option.material=part.kind if int(resources.get(part.kind,0))>=int(option.ingredient) else "organelle"
		option.available=not option.active and int(app.store.profile.get("organium",0))>=int(option.cost) and int(resources.get(option.material,0))>=int(option.ingredient)
		part.specialization_options.append(option)
	part.materials_text="Материал «%s»: %d · Органеллы: %d"%[Catalog.item(part.kind).name,int(resources.get(part.kind,0)),int(resources.get("organelle",0))]
	part.can_dismantle=true
	part.can_equip=location in ["stock","reserve"]
	part.can_unequip=location=="equipped" and value.stock.size()<int(value.stock_capacity)
	part.can_archive=not live_mode and location!="reserve"
	app.set_stage("organ_detail")
	var box=app.hud.open_fixed(Catalog.item(part.kind).name,"Свойства принадлежат этому экземпляру и сохраняются в семействе.")
	Body.detail(app.hud,box,part,part_preview,{"equip":func():incoming=id;selected=[];show_exchange(),"unequip":func():move(id,"stock"),"archive":func():move(id,"archive"),"tab":func(value):show_part(id,value),"upgrade":func():upgrade_part(id),"specialize":func(specialization):specialize_part(id,str(specialization)),"dismantle":func():confirm_dismantle(id),"codex":func():app.show_codex_entry(str(part.kind)),"back":func():show_body(live_mode)})

func show_picker(mode: String,page: int=0):
	picker_mode=mode
	if mode=="archive" and live_mode:return
	var value=state();var parts=[]
	for item in (value.reserve if mode=="archive" else (value.equipped if mode=="unequip" else value.stock)):
		var part=item.duplicate(true);part.preferred=Catalog.item(part.kind).get("branch","")==value.form;parts.append(part)
	app.set_stage("organ_picker")
	var box=app.hud.open_fixed("Архив семейства" if mode=="archive" else "Запас органов","Архив доступен между жизнями. Запас можно менять в любой момент." if mode=="archive" else "Выбери орган для установки в тело.")
	Body.picker(app.hud,box,parts,{"choose":func(id):
		if picker_mode=="archive":move(id,"stock_from_archive")
		elif picker_mode=="unequip":move(id,"stock")
		else:incoming=id;selected=[];show_exchange(),"page":func(index):show_picker(picker_mode,index),"back":func():show_body(live_mode)},page)

func show_exchange(page: int=0):
	var value=state();var result=Equipment.move(value,incoming,"body",selected)
	app.set_stage("organ_exchange")
	var box=app.hud.open_fixed("Перестройка","Отметь органы, которые уйдут в запас. Перед применением проверяются оба ограничения.")
	Body.exchange(app.hud,box,value,incoming,selected,"" if result.ok else result.error,{"toggle":func(id):
		if id in selected:selected.erase(id)
		else:selected.append(id)
		show_exchange(page),"apply":func():move(incoming,"body",selected),"page":show_exchange,"back":func():show_body(live_mode)},page)

func move(id: String,destination: String,replacements: Array=[]):
	var previous_synergies=app.sim.build.active_synergies().duplicate() if live_mode and app.sim!=null else []
	var result=Equipment.move(state(),id,destination,replacements)
	if not result.ok:app.message(result.error,4);return
	var resolves_pending=destination=="body" and live_mode and id in app.sim.pending_inventory
	if resolves_pending:app.sim.pending_inventory.erase(id)
	if not commit_state(result.state):
		if resolves_pending:app.sim.pending_inventory.append(id)
		return
	var activated=[]
	if live_mode:
		for synergy_id in app.sim.build.active_synergies():
			if synergy_id not in previous_synergies:activated.append(synergy_id)
	if not activated.is_empty():
		app.show_synergy_reveal(activated,Callable(self,"_after_body_synergy").bind(resolves_pending))
		return
	if resolves_pending:app.open_pending();return
	show_body(live_mode)

func _after_body_synergy(resolves_pending: bool):
	if resolves_pending:app.open_pending()
	else:show_body(live_mode)

func commit_state(value: Dictionary,economy: Dictionary={}) -> bool:
	var next=app.store.profile.duplicate(true);next.organism=value
	if economy.has("organium"):next.organium=int(economy.organium)
	if economy.has("organ_materials"):next.organ_materials=economy.organ_materials.duplicate(true)
	if live_mode:
		if app.sim.family_id!=app.store.family_id():_error("Семейство изменилось; жизнь не перезаписана");return false
		var checkpoint=app.sim.snapshot()
		var merged=Equipment.aggregate(value)
		checkpoint.build.organs=merged.organs
		for kind in Catalog.ORGANS:checkpoint.build.qualities.erase(kind)
		for kind in merged.qualities:checkpoint.build.qualities[kind]=merged.qualities[kind]
		checkpoint.build.specializations=merged.specializations.duplicate(true)
		checkpoint.build.organ_capacity=int(value.body_capacity)
		var by_kind=0
		for kind in merged.organs:by_kind+=Equipment.cell_cost(kind)
		checkpoint.build.extra_organ_cells=maxi(0,Slots.used_cells(value)-by_kind)
		for kind in Catalog.ORGANS:checkpoint.build.stats.evolutions.erase(kind)
		for part in value.equipped:
			if part.get("evolved",false) and part.kind in Catalog.EVOLUTIONS:checkpoint.build.stats.evolutions[part.kind]=true
		var installed = checkpoint.build.organs.keys() + checkpoint.build.adaptations.keys()
		for kind in installed:
			if kind not in next.discovered:next.discovered.append(kind)
		for synergy in Catalog.SYNERGIES:
			if synergy in next.synergies:continue
			if Catalog.SYNERGIES[synergy].needs.all(func(kind):return kind in installed):next.synergies.append(synergy)
		next.checkpoint=checkpoint
	if not app.store.write_profile(next):_error(app.store.last_error);return false
	if live_mode:bind_run(value);apply_to_build(value,app.sim.build);app.sim.stock_capacity=int(value.stock_capacity)
	return true

func upgrade_part(id: String):
	var result=Equipment.upgrade(state(),id,int(app.store.profile.get("organium",0)),app.store.profile.get("organ_materials",{}))
	if not result.ok:app.message(result.error,4);return
	if not commit_state(result.state,{"organium":result.organium,"organ_materials":result.materials}):return
	show_part(id,"growth")

func specialize_part(id: String,specialization: String):
	var result=Equipment.specialize(state(),id,specialization,int(app.store.profile.get("organium",0)),app.store.profile.get("organ_materials",{}))
	if not result.ok:app.message(result.error,4);return
	if not commit_state(result.state,{"organium":result.organium,"organ_materials":result.materials}):return
	show_part(id,"growth")

func confirm_dismantle(id: String):
	var materials=app.store.profile.get("organ_materials",{})
	var result=Equipment.dismantle(state(),id,int(app.store.profile.get("organium",0)),materials)
	if not result.ok:app.message(result.error,4);return
	var box=app.hud.open_fixed("Расщепить орган?","Ранг и орган будут потеряны. Возврат записывается вместе с удалением.")
	box.add_child(app.hud.label("Вернётся %d органиума и %d материала «%s»."%[int(result.get("refund",0)),int(result.materials.get(str(result.get("kind","")),0))-int(materials.get(str(result.get("kind","")),0)),Catalog.item(str(result.get("kind",""))).name],23,Color("c5eab8"),true))
	var row=app.hud.row();box.add_child(row)
	row.add_child(app.hud.button("Оставить",func():show_part(id)))
	row.add_child(app.hud.button("Расщепить",func():
		var resolves_pending=live_mode and id in app.sim.pending_inventory
		if resolves_pending:app.sim.pending_inventory.erase(id)
		if not commit_state(result.state,{"organium":result.organium,"organ_materials":result.materials}):
			if resolves_pending:app.sim.pending_inventory.append(id)
			return
		if resolves_pending:app.open_pending()
		else:show_body(live_mode),true))

func award(kind: String,grade: int) -> bool:
	var current=capture(app.sim.build.to_dict())
	if current.is_empty():return false
	var result=Equipment.award(current,kind,grade)
	if not result.ok:app.message(result.error,4);return false
	last_award_location=result.location
	bind_run(result.state);apply_to_build(result.state,app.sim.build)
	if result.location=="reserve" and not result.id in app.sim.pending_inventory:app.sim.pending_inventory.append(result.id)
	if result.location!="body":app.message("Орган сохранён "+("в запасе" if result.location=="stock" else "в архиве семейства для следующей жизни"),5)
	return true

func show_inventory_review():
	live_mode=true
	var id=str(app.sim.pending_inventory[0]) if not app.sim.pending_inventory.is_empty() else ""
	var value=state();var part={}
	for candidate in value.reserve:
		if str(candidate.get("id",""))==id:part=candidate;break
	if part.is_empty():
		app.sim.pending_inventory.erase(id)
		app.open_pending();return
	app.set_stage("inventory_review")
	var box=app.hud.open_fixed("Запас заполнен","Находка сохранена в архиве. Выбери, что сделать с ней.",900)
	var card=app.hud.card();box.add_child(card)
	var row=app.hud.row();card.add_child(row)
	var art=Home.Portrait.new();art.recipe=Home.recipe_for(part);art.organs={str(part.kind):int(part.rank)};art.custom_minimum_size=Vector2(120,120);row.add_child(art)
	var summary=VBoxContainer.new();summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(summary)
	summary.add_child(app.hud.label(Catalog.item(str(part.kind)).name+" · ранг %d · %s"%[int(part.rank),Rewards.quality_name(int(part.quality))],23,Color("9fe0ca"),true))
	summary.add_child(app.hud.label("Тело %d/%d кл. · запас %d/%d мест"%[Slots.used_cells(value),int(value.body_capacity),value.stock.size(),int(value.stock_capacity)],20,Color("b8d0cd"),true))
	var actions=app.hud.row();box.add_child(actions)
	actions.add_child(app.hud.button("Подробности",func():show_part(id)))
	var cells_fit=int(part.cells)<=int(value.body_capacity)
	var equip_button=app.hud.button("Установить",func():incoming=id;selected=[];show_exchange(),true)
	equip_button.disabled=not cells_fit
	actions.add_child(equip_button)
	actions.add_child(app.hud.button("Расщепить",func():confirm_dismantle(id)))
	box.add_child(app.hud.button("Оставить в архиве",func():
		app.sim.pending_inventory.erase(id)
		app.save_run()
		app.open_pending(),true))

func show_mutations(page: int=0):
	app.set_stage("organ_mutations")
	var source=app.sim.build if live_mode else preview.build
	var keys=source.temporary_mutations
	var box=app.hud.open_fixed("Временные мутации","Эти изменения принадлежат только текущей жизни и исчезнут после гибели.")
	for active in keys.slice(page*3,page*3+3):
		var data=Catalog.temporary_mutation(str(active.id))
		box.add_child(app.hud.label("%s · ранг %d · %s\n%s"%[str(data.get("name",active.id)),int(active.get("rank",1)),Rewards.quality_name(int(active.get("quality",0))),str(data.get("summary","Временное усиление"))],20,Color(str(data.get("color","9ce3cf"))),true))
	if keys.is_empty():box.add_child(app.hud.label("Редкие цисты дают временные мутации организма.",22,Color("a5c4c4"),true))
	var row=app.hud.row();box.add_child(row)
	var prev=app.hud.button("‹",func():show_mutations(maxi(0,page-1)));prev.disabled=page<=0;row.add_child(prev)
	var next=app.hud.button("›",func():show_mutations(page+1));next.disabled=(page+1)*3>=keys.size();row.add_child(next)
	box.add_child(app.hud.button("К организму",func():show_body(live_mode)))

func _error(message: String):
	app.set_stage("family_error")
	var box=app.hud.open_fixed("Данные не изменены",message,850)
	box.add_child(app.hud.button("Повторить",func():show_body(live_mode),true))
	box.add_child(app.hud.button("В меню",show_home))

func show_statistics(page: int=0):
	app.set_stage("organ_mutations")
	var source=app.sim if live_mode else preview
	var box=app.hud.open_fixed("Сводка организма","Фактические показатели текущей жизни; бой на паузе.")
	box.add_child(app.hud.label(Development.combat_summary(source),22,Color("9ce3cf"),true))
	box.add_child(app.hud.label("Последние повреждения · источники",24))
	var entries=source.combat_stats.get("history",[]).duplicate(true)
	entries.reverse()
	for entry in entries.slice(page*4,page*4+4):
		box.add_child(app.hud.label("%02d:%02d · %s · −%.1f HP"%[int(entry.get("time",0))/60,int(entry.get("time",0))%60,str(entry.get("name","Источник не указан")),float(entry.get("amount",0))],20,Color("dfb8a7"),true))
	if entries.is_empty():box.add_child(app.hud.label("Повреждений ещё не было.",22))
	var nav=app.hud.row();box.add_child(nav)
	var previous=app.hud.button("‹",func():show_statistics(maxi(0,page-1)));previous.disabled=page<=0;nav.add_child(previous)
	var next=app.hud.button("›",func():show_statistics(page+1));next.disabled=(page+1)*4>=entries.size();nav.add_child(next)
	nav.add_child(app.hud.button("Мутации",show_mutations))
	box.add_child(app.hud.button("К организму",func():show_body(live_mode)))

func show_stock_sources():
	var value=state()
	if live_mode or value.reserve.is_empty():show_picker("unequip");return
	app.set_stage("organ_picker")
	var box=app.hud.open_fixed("Заполнить запас","Выбери, откуда взять орган.",850)
	box.add_child(app.hud.button("Из тела",func():show_picker("unequip")))
	box.add_child(app.hud.button("Из архива семейства",func():show_picker("archive")))
	box.add_child(app.hud.button("К организму",func():show_body(live_mode)))

var legacy_tab="research"
var legacy_page=0
var legacy_from_body=false
func show_legacy(tab: String="",page: int=-1):
	if app.stage not in ["genome","inherit"]:legacy_from_body=app.stage in ["start","development","organ_detail","organ_picker","organ_exchange","organ_mutations"]
	if tab!="":legacy_tab=tab
	if page>=0:legacy_page=page
	app.set_stage("genome")
	var box=app.hud.open_fixed("Геном семейства","Ядра: %d · сохранённые исследования и признаки линии"%int(app.store.profile.cores))
	preload("res://ui/legacy_panel.gd").populate(app.hud,box,app.store.profile,{"tab":func(id):show_legacy(id,0),"page":func(index):show_legacy("",index),"research":func(id):edit_legacy("research",id),"focus":func(id):edit_legacy("focus",id),"trait":func(id):edit_legacy("trait",id),"imprint":func(id):edit_legacy("imprint",id),"upgrade":func(id):edit_legacy("upgrade",id),"pending":func():app.show_imprints("genome"),"back":close_legacy},legacy_tab,legacy_page)

func edit_legacy(action: String,id: String):
	var ok=false
	match action:
		"research":ok=app.store.research(id)
		"focus":ok=app.store.focus_research(id)
		"trait":ok=app.store.toggle_trait(id)
		"imprint":ok=app.store.select_imprint(id)
		"upgrade":ok=app.store.buy_upgrade(id)
	if not ok:app.message(app.store.last_error if app.store.last_error!="" else "Действие сейчас недоступно",4)
	show_legacy()

func close_legacy():
	if legacy_from_body:show_body(live_mode)
	else:app.show_menu()

func show_pending(origin: String,page: int=0):
	app.imprint_origin=origin
	app.set_stage("inherit")
	var box=app.hud.open_fixed("Архив отпечатков","Совместимое наследие прежних жизней. Выбор можно отложить крестиком.")
	preload("res://ui/legacy_panel.gd").pending(app.hud,box,app.store.profile,{"claim":func(id):
		if not app.store.claim_imprint(id):app.message(app.store.last_error if app.store.last_error!="" else "Отпечаток недоступен",4)
		show_pending(origin,page),"page":func(index):show_pending(origin,index),"back":app._close_imprints},page)
