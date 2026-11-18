extends RefCounted
const Catalog = preload("res://core/catalog.gd")
const Art = preload("res://ui/organ_art.gd")
const Build = preload("res://core/build_model.gd")
const Inspector = preload("res://core/build_inspector.gd")
const Rewards = preload("res://core/rewards.gd")
const Growth = preload("res://core/growth.gd")

static func populate(hud,box,sim):
	var overview=hud.card()
	box.add_child(overview)
	var summary=hud.row()
	overview.add_child(summary)
	var preview=Art.new()
	preview.sim=sim
	preview.custom_minimum_size=Vector2(180,180)
	summary.add_child(preview)
	var info=VBoxContainer.new()
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	summary.add_child(info)
	info.add_child(hud.label("Текущий организм · уровень %d" % sim.level,25,Color("9ce3cf"),true))
	info.add_child(hud.label("Размер ×%.2f · радиус %.1f\nЗдоровье %.1f / %.1f · биомасса %d\nРост до уровня %d: %d / %d ДНК\nРадиус следующего уровня: %.1f" % [sim.body_radius()/22.0,sim.body_radius(),sim.hp,sim.max_hp,sim.build.biomass,sim.level+1,sim.xp,sim.xp_needed(),Growth.radius(sim.level+1)],19,Color("c5dbd7"),true))
	info.add_child(hud.label("Рост меняет соотношение размеров: меньших противников легче захватить и переварить.",17,Color("95b7ba"),true))
	box.add_child(hud.label("Равные и крупные противники защищены стойкой тканью: она снижает быстрый суммарный урон. Цифры в бою показывают действительный урон.",17,Color("a1b8b9"),true))
	box.add_child(hud.label(combat_summary(sim),21,Color("b7dfd2"),true))
	box.add_child(hud.label("Числа органов ниже — до сопротивления ткани врага. Фактический DPS — урон за время учёта, включая движение и ожидание.",19,Color("9cbabc"),true))
	if sim.build.evolved("infection"):box.add_child(hud.label("Споровые камеры: %d/3 · третья заражённая порция выпускает облако" % sim.spore_charge,21,Color("e6aad8"),true))
	box.add_child(hud.label("Боевые органы · %d/6" % sim.build.organs.size(),26))
	_equipped(hud,box,sim,sim.build.organs)
	box.add_child(hud.label("Пассивные адаптации · %d/4" % sim.build.adaptations.size(),26))
	_equipped(hud,box,sim,sim.build.adaptations)
	box.add_child(hud.label("Эволюции · орган 6 + адаптация 3",26))
	for id in Catalog.EVOLUTIONS:
		var recipe = Catalog.EVOLUTIONS[id]
		var state = "✓ Получена" if sim.build.evolved(id) else ("Готова · ищи в наградах" if id in sim.build.evolution_candidates() else "◇ Требуются мутации")
		box.add_child(hud.label("%s · %s · %s %d/6 + %s %d/3" % [recipe.name,state,Catalog.item(id).name,sim.build.stored_rank(id),Catalog.item(recipe.passive).name,sim.build.rank(recipe.passive)],19,Color("d3c19f"),true))
	var legacy=[]
	for id in sim.upgrades:
		var rank=int(sim.upgrades[id])
		if rank<=0: continue
		match id:
			"health": legacy.append("Здоровье +%d" % (rank*5))
			"collect": legacy.append("Рецепторы +%d к радиусу" % (rank*8))
			"regen": legacy.append("Восстановление +%.1f HP/сек." % (rank*0.1))
	if not legacy.is_empty(): box.add_child(hud.label("Наследственный геном: "+" · ".join(legacy),19,Color("cfb0e6"),true))
	box.add_child(hud.label("Синергии · %d/%d активны" % [sim.build.active_synergies().size(),Catalog.SYNERGIES.size()],26))
	for active in [true,false]:
		for id in Catalog.SYNERGIES:
			var synergy=Catalog.SYNERGIES[id]
			var enabled=id in sim.build.active_synergies()
			if enabled!=active: continue
			var column=VBoxContainer.new()
			box.add_child(column)
			column.add_child(hud.label(("✓ " if enabled else "◇ ")+synergy.name,20,Color("cdb3eb"),true))
			var names=[]
			for required in synergy.needs:
				names.append(("✓ " if sim.build.rank(required)>0 else "+ ")+Catalog.item(required).name)
			column.add_child(hud.label(" + ".join(names),17,Color("abd1c8"),true))

static func _equipped(hud,box,sim,items):
	if items.is_empty():
		box.add_child(hud.label("Пока нет. Мутации появятся при повышении уровня и в колониях.",19,Color("91b1b8"),true))
	for id in items:
		box.add_child(item_card(hud,id,sim.build.rank(id),sim))

static func item_card(hud,id: String,rank: int,sim=null):
	var card=hud.card()
	var row=hud.row()
	card.add_child(row)
	var art=Art.new()
	art.organ_id=id
	if sim!=null:art.quality=sim.build.quality(id)
	art.custom_minimum_size=Vector2(76,76)
	row.add_child(art)
	var details=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var item=Catalog.item(id)
	var stored_rank=sim.build.stored_rank(id) if sim!=null else rank
	details.add_child(hud.label(("%s · ранг %d"%[item.name,stored_rank] if id in Catalog.ORGANS else "%s · %d/%d" % [item.name,rank,Catalog.max_rank(id)]),22,Color(item.color),true))
	if sim!=null:
		var grade=sim.build.quality(id)
		var marks=Rewards.quality_name(grade)
		if sim.build.evolved(id):marks+=" · Эволюция"
		details.add_child(hud.label(marks,18,Rewards.quality_color(grade),true))
		details.add_child(hud.label(short_effect(id,sim.build,sim.ability_scale(),sim.cooldown_factor()),19,Color("9fe0ca"),true))
	else:
		details.add_child(hud.label(short_effect(id,null),19,Color("9fe0ca"),true))
	return card

static func short_effect(id: String,build,scale: float=1.0,tempo: float=1.0)->String:
	var rank=build.rank(id) if build!=null else 1
	var power=build.power(id) if build!=null else 1.0
	var suffix=""
	match id:
		"tentacle":suffix="%d щупалец · залп %.0f · дальность %.0f"%[Catalog.tentacle_count(rank),Catalog.scaled_damage(9+rank*7,rank)*power,(165+rank*12)*build.specialization_value(id,"reach_mult")*scale if build!=null else 165+rank*12]
		"acid":suffix="%.1f урона/с · радиус %.0f"%[Catalog.scaled_damage(4+rank*3,rank)*power,(75+rank*9)*build.specialization_value(id,"radius_mult")*scale if build!=null else 75+rank*9]
		"spikes":suffix="%d шипов · %.1f урона за шип"%[mini(7,Catalog.shot_count(rank)+(build.specialization_bonus(id,"shot_bonus") if build!=null else 0)),Catalog.scaled_damage(12+rank*5,rank)*power]
		"pulse":suffix="%.1f урона · радиус %.0f"%[Catalog.scaled_damage(12+rank*8,rank)*power,(130+rank*18)*build.specialization_value(id,"radius_mult")*scale if build!=null else 130+rank*18]
		"division":suffix="%d копий · %.1f урона/с"%[mini(6,Catalog.clone_count(rank)+(build.specialization_bonus(id,"clone_bonus") if build!=null else 0)),Catalog.scaled_damage(8+rank*4,rank)*power]
		"trail":suffix="%.1f урона/с · поле %.1f с"%[Catalog.scaled_damage(5+rank*3,rank)*power,3.0*(build.specialization_value(id,"duration_mult") if build!=null else 1.0)]
		"infection":suffix="%.1f урона/с · заражение %.1f с"%[Catalog.scaled_damage(4+rank*3,rank)*power,4.5*(build.specialization_value(id,"duration_mult") if build!=null else 1.0)]
		"devour":suffix="укус %.1f · интервал %.2f с"%[Catalog.scaled_damage(7+rank*5,rank)*power,0.45*(build.specialization_value(id,"bite_cooldown_mult") if build!=null else 1.0)]
		"cilia":suffix="веер %.1f · дальность %.0f"%[Catalog.scaled_damage(10+rank*6,rank)*power,(100+rank*10)*build.specialization_value(id,"reach_mult")*scale if build!=null else 100+rank*10]
		"enzymes":suffix="%.1f урона/с · метка %.1f с"%[Catalog.scaled_damage(3+rank*2,rank)*power,4.0*(build.specialization_value(id,"duration_mult") if build!=null else 1.0)]
		"electric":suffix="%.1f урона · %d целей"%[Catalog.scaled_damage(12+rank*6,rank)*power,mini(7,Catalog.electric_targets(rank)+(build.specialization_bonus(id,"target_bonus") if build!=null else 0))]
		"barrier":suffix="щит %.1f HP · перезарядка 8 с"%[Catalog.scaled_damage(8+rank*6,rank)*power]
		_:
			if build!=null:suffix=Inspector.effect_text(build,id,scale,tempo)
			else:suffix=effect_text(id,rank)
	return suffix

static func effect_text(id: String,rank: int) -> String:
	# Catalog owns combat numbers so descriptions stay synchronized with balance.
	var catalog=Catalog.new()
	if catalog.has_method("effect_text"): return catalog.call("effect_text",id,rank)
	return Catalog.item(id).desc

static func combat_summary(sim) -> String:
	var data = sim.combat_stats
	return "Урон нанесён %.1f · получен %.1f\nDPS %.2f — средний за время учёта · щитом/бронёй заблокировано %.1f · лечение %.1f HP" % [float(data.get("damage_dealt",0)),float(data.get("damage_taken",0)),float(data.get("damage_dealt",0))/maxf(0.01,sim.elapsed-float(sim.combat_stats.get("tracking_start",0))),float(data.get("blocked",0)),float(data.get("healed",0))]

static func damage_view(hud,box,sim):
	box.add_child(hud.label(combat_summary(sim),22,Color("b7dfd2"),true))
	_history(hud,box,sim)

static func _history(hud,box,sim):
	box.add_child(hud.label("Последние повреждения · источники",26))
	var sources = sim.combat_stats.get("sources",{}).values()
	sources.sort_custom(func(a,b): return float(a.get("damage",0))>float(b.get("damage",0)))
	for i in range(mini(8,sources.size())):
		var source = sources[i]
		box.add_child(hud.label("%s · всего %.1f HP · событий урона %d (включая тики)" % [source.get("name","Неизвестный источник"),float(source.get("damage",0)),int(source.get("hits",0))],20,Color("dbb5a3"),true))
	var history = sim.combat_stats.get("history",[])
	if history.is_empty():
		box.add_child(hud.label("Повреждений пока не было.",20,Color("91b1b8"),true))
	for i in range(history.size()-1,maxi(-1,history.size()-11),-1):
		var entry = history[i]
		var time = int(entry.get("time",0))
		var kind = str(entry.get("kind",""))
		var names = {"collision":"Столкновение","unknown":"Источник неизвестен","contact":"Контакт","projectile":"Снаряд","hazard":"Среда","toxin":"Токсин","boss":"Архицит","damage":"Повреждение","enemy":"Противник"}
		box.add_child(hud.label("%02d:%02d · %s · %s · −%.1f HP" % [time/60,time%60,names.get(kind,kind),entry.get("name","Неизвестный источник"),float(entry.get("amount",0))],19,Color("dfb8a7"),true))

static func evolution_preview(build,id: String,scale: float=1.0,tempo: float=1.0) -> String:
	var next = Build.new()
	next.from_dict(build.to_dict())
	if not next.evolve(id): return Inspector.effect_text(build,id,scale,tempo)
	return Inspector.effect_text(build,id,scale,tempo)+" → "+Inspector.effect_text(next,id,scale,tempo)
