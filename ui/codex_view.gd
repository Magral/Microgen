extends RefCounted
# Long-form descriptions live here; gameplay cards stay short and scannable.
const Catalog=preload("res://core/catalog.gd")
const Art=preload("res://ui/organ_art.gd")
const Development=preload("res://ui/development_view.gd")
var app
var category=""
var page=0

func _init(owner):
	app=owner

func home():
	app.set_stage("atlas")
	app.hud.game_visible(false)
	var box=app.hud.open_fixed("Кодекс","Подробности органов и взаимодействий. Боевые окна оставлены короткими.",760)
	var grid=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10);box.add_child(grid)
	for data in [["Органы","organs",Catalog.ORGANS.size()],["Адаптации","adaptations",Catalog.ADAPTATIONS.size()],["Временные мутации","temporary",Catalog.TEMP_MUTATIONS.size()],["Синергии","synergies",Catalog.SYNERGIES.size()],["Специализации","specializations",_specialization_count()],["Эволюции","evolutions",Catalog.EVOLUTIONS.size()]]:
		var button=app.hud.button("%s\n%d записей"%[data[0],int(data[2])],open_category.bind(str(data[1]),0),true)
		button.custom_minimum_size.y=72;grid.add_child(button)
	box.add_child(app.hud.button("В меню",app.show_menu))

func _specialization_count()->int:
	var count=0
	for options in Catalog.SPECIALIZATIONS.values():count+=options.size()
	return count

func _entries(kind: String)->Array:
	var out=[]
	match kind:
		"organs":
			for id in Catalog.ORGANS:out.append({"type":"organ","id":str(id)})
		"adaptations":
			for id in Catalog.ADAPTATIONS:out.append({"type":"adaptation","id":str(id)})
		"temporary":
			for id in Catalog.TEMP_MUTATIONS:out.append({"type":"temporary","id":str(id)})
		"synergies":
			for id in Catalog.SYNERGIES:out.append({"type":"synergy","id":str(id)})
		"specializations":
			for organ in Catalog.SPECIALIZATIONS:
				for option in Catalog.SPECIALIZATIONS[organ]:out.append({"type":"specialization","id":str(option.id),"organ":str(organ)})
		"evolutions":
			for organ in Catalog.EVOLUTIONS:out.append({"type":"evolution","id":str(organ)})
	return out

func _category_name(kind: String)->String:
	return {"organs":"Органы","adaptations":"Адаптации","temporary":"Временные мутации","synergies":"Синергии","specializations":"Специализации","evolutions":"Эволюции"}.get(kind,"Кодекс")

func open_category(kind: String,requested_page: int=0):
	category=kind
	var entries=_entries(kind)
	var pages=maxi(1,ceili(float(entries.size())/6.0))
	page=clampi(requested_page,0,pages-1)
	app.set_stage("codex_category")
	var box=app.hud.open_fixed(_category_name(kind),"Выбери запись для подробного описания.",880)
	var grid=VBoxContainer.new();grid.add_theme_constant_override("separation",6);box.add_child(grid)
	for record in entries.slice(page*6,mini(entries.size(),page*6+6)):
		var label=_entry_label(record)
		var button=app.hud.button(label,open_entry.bind(record),false)
		button.custom_minimum_size.y=48;grid.add_child(button)
	if entries.is_empty():box.add_child(app.hud.label("Записей пока нет.",21))
	var nav=app.hud.row();box.add_child(nav)
	var previous=app.hud.button("‹",func():open_category(kind,maxi(0,page-1)));previous.disabled=page<=0;nav.add_child(previous)
	var counter=app.hud.label("%d / %d"%[page+1,pages],20);counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;counter.size_flags_horizontal=Control.SIZE_EXPAND_FILL;nav.add_child(counter)
	var next=app.hud.button("›",func():open_category(kind,page+1));next.disabled=page+1>=pages;nav.add_child(next)
	var bottom=app.hud.row();box.add_child(bottom)
	bottom.add_child(app.hud.button("К категориям",home))
	bottom.add_child(app.hud.button("В меню",app.show_menu))

func _entry_label(record: Dictionary)->String:
	var id=str(record.id)
	var item={}
	var status=""
	match str(record.type):
		"organ","adaptation","temporary":
			item=Catalog.item(id)
			if record.type=="temporary":item=Catalog.temporary_mutation(id);status="✦"
			else:status="✓" if id in app.store.profile.get("discovered",[]) else ("◇" if id in app.store.profile.get("unlocked",[]) else "·")
		"synergy":
			item=Catalog.SYNERGIES.get(id,{})
			status="✓" if id in app.store.profile.get("synergies",[]) else "◇"
		"specialization":
			item=Catalog.specialization_data(str(record.organ),id)
			status="✦"
		"evolution":
			item=Catalog.EVOLUTIONS.get(id,{})
			status="↗"
	return "%s  %s"%[status,str(item.get("name",id))]

func open_entry(record: Dictionary):
	app.set_stage("codex_entry")
	var type=str(record.get("type",""));var id=str(record.get("id",""))
	var entry={}
	var title="Запись Кодекса";var subtitle="Подробное описание"
	match type:
		"organ","adaptation","temporary":
			entry=Catalog.temporary_mutation(id) if type=="temporary" else Catalog.item(id);title=str(entry.get("name",id));subtitle="Временная мутация · сбрасывается после гибели" if type=="temporary" else ("Орган · характеристики и взаимодействия" if type=="organ" else "Адаптация · постоянный эффект в рамках жизни")
		"synergy":
			entry=Catalog.SYNERGIES.get(id,{});title=str(entry.get("name",id));subtitle="Синергия · собери оба компонента"
		"specialization":
			entry=Catalog.specialization_data(str(record.organ),id);title=str(entry.get("name",id));subtitle="Специализация · "+str(Catalog.item(str(record.organ)).get("name",record.organ))
		"evolution":
			entry=Catalog.EVOLUTIONS.get(id,{});title=str(entry.get("name",id));subtitle="Эволюция · постоянная перестройка органа"
	var box=app.hud.open_fixed(title,subtitle,860)
	if type in ["organ","adaptation","temporary"]:
		var art_center=CenterContainer.new();art_center.custom_minimum_size.y=132;box.add_child(art_center)
		var art=Art.new();art.organ_id=str(entry.get("organ",id)) if type=="temporary" else id;art.custom_minimum_size=Vector2(132,132);art_center.add_child(art)
		box.add_child(app.hud.label(str(entry.get("desc","")),20,Color("b8d0cd"),true))
		box.add_child(app.hud.label(("Эффект · "+str(entry.get("summary","Временное усиление органа"))) if type=="temporary" else "Ранг 1 · "+Development.effect_text(id,1),20,Color("9fe0ca"),true))
		if type=="organ":
			box.add_child(app.hud.label("Ветви развития",22,Color("cdb3eb")))
			for option in Catalog.SPECIALIZATIONS.get(id,[]):box.add_child(app.hud.label("✦ %s\n%s"%[str(option.name),str(option.desc)],18,Color(str(option.color)),true))
		var related=[]
		for synergy in Catalog.SYNERGIES.values():
			if id in synergy.needs:related.append(synergy)
		if not related.is_empty():
			box.add_child(app.hud.label("Связи",23,Color("cdb3eb")))
			for synergy in related:
				var partner=str(synergy.needs[1] if synergy.needs[0]==id else synergy.needs[0])
				box.add_child(app.hud.label("%s + %s · %s"%[str(entry.name),str(Catalog.item(partner).name),str(synergy.name)],18,Color("aec3c7"),true))
	elif type=="synergy":
		var needs=[]
		for organ in entry.get("needs",[]):needs.append(str(Catalog.item(str(organ)).get("name",organ)))
		box.add_child(app.hud.label("Нужны: "+" + ".join(needs),22,Color("b7dfd2"),true))
		box.add_child(app.hud.label(str(entry.get("desc","")),21,Color("d0b3e8"),true))
	elif type=="specialization":
		var art=Art.new();art.organ_id=str(record.organ);art.custom_minimum_size=Vector2(150,150);box.add_child(art)
		box.add_child(app.hud.label(str(entry.get("desc","")),22,Color("b8d0cd"),true))
		var stats=[]
		for key in ["power","synergy_power","reach_mult","radius_mult","duration_mult","shot_bonus","clone_bonus","target_bonus","bite_cooldown_mult"]:
			if not entry.has(key):continue
			var value=float(entry[key])
			if key in ["shot_bonus","clone_bonus","target_bonus"]:stats.append("+%d"%int(value))
			elif key=="bite_cooldown_mult":stats.append("интервал укуса −%d%%"%roundi((1.0-value)*100.0))
			elif key in ["power","synergy_power"]:stats.append("сила ×%.2f"%value)
			else:stats.append("+%d%% к %s"%[roundi((value-1.0)*100.0),{"reach_mult":"дальности","radius_mult":"радиусу","duration_mult":"длительности"}.get(key,key)])
		box.add_child(app.hud.label("Параметры: "+" · ".join(stats),21,Color("9fe0ca"),true))
	elif type=="evolution":
		var organ=str(id);var passive=str(entry.get("passive",""))
		var art=Art.new();art.organ_id=organ;art.custom_minimum_size=Vector2(150,150);box.add_child(art)
		box.add_child(app.hud.label("Условие: %s · ранг 6 + %s · ранг 3"%[str(Catalog.item(organ).name),str(Catalog.item(passive).name)],21,Color("b7dfd2"),true))
		box.add_child(app.hud.label("После получения: урон органа ×1,30. Пассивный признак и дополнительное поведение сохраняются в этой жизни."+(("\n"+str(entry.behavior)) if entry.has("behavior") else ""),20,Color("b8d0cd"),true))
	var nav=app.hud.row();box.add_child(nav)
	nav.add_child(app.hud.button("К списку",func():open_category(category,page)))
	nav.add_child(app.hud.button("Кодекс",home))
	nav.add_child(app.hud.button("В меню",app.show_menu))

func open_entry_for_kind(kind: String):
	var category_kind="organs" if kind in Catalog.ORGANS else "adaptations"
	category=category_kind
	open_entry({"type":"organ" if category_kind=="organs" else "adaptation","id":kind})
