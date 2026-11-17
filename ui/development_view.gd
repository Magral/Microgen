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
	box.add_child(hud.label("Боевые органы · %d/6" % sim.build.organs.size(),26))
	_equipped(hud,box,sim,sim.build.organs)
	box.add_child(hud.label("Пассивные адаптации · %d/4" % sim.build.adaptations.size(),26))
	_equipped(hud,box,sim,sim.build.adaptations)
	box.add_child(hud.label("Эволюции · орган 6 + адаптация 3",26))
	for id in Catalog.EVOLUTIONS:
		var recipe = Catalog.EVOLUTIONS[id]
		var state = "✓ Получена" if sim.build.evolved(id) else ("Готова · ищи в наградах" if id in sim.build.evolution_candidates() else "◇ Требуются мутации")
		box.add_child(hud.label("%s · %s\n%s %d/6 + %s %d/3 · урон ×1,30" % [recipe.name,state,Catalog.item(id).name,sim.build.rank(id),Catalog.item(recipe.passive).name,sim.build.rank(recipe.passive)],20,Color("d3c19f"),true))
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
			var card=hud.card()
			box.add_child(card)
			var column=VBoxContainer.new()
			card.add_child(column)
			column.add_child(hud.label(("✓ Активна · " if enabled else "◇ Можно собрать · ")+synergy.name,22,Color("cdb3eb"),true))
			var names=[]
			for required in synergy.needs:
				names.append(("✓ " if sim.build.rank(required)>0 else "+ ")+Catalog.item(required).name)
			column.add_child(hud.label(" + ".join(names),18,Color("abd1c8"),true))
			column.add_child(hud.label(synergy.desc,18,Color("aec3c7"),true))

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
	art.custom_minimum_size=Vector2(112,112)
	row.add_child(art)
	var details=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var item=Catalog.item(id)
	details.add_child(hud.label("%s · %d/%d" % [item.name,rank,Catalog.max_rank(id)],23,Color(item.color),true))
	details.add_child(hud.label(item.desc,18,Color("bed2d1"),true))
	if sim!=null:
		details.add_child(hud.label(Rewards.quality_name(sim.build.quality(id))+(" · Эволюционировал ×1,30" if sim.build.evolved(id) else ""),20,Rewards.quality_color(sim.build.quality(id)),true))
		details.add_child(hud.label("Сейчас: "+Inspector.effect_text(sim.build,id,sim.ability_scale(),sim.cooldown_factor()),21,Color("9fe0ca"),true))
		var actual = sim.combat_stats.get("organs",{}).get(id,{})
		if id in Catalog.ORGANS:
			details.add_child(hud.label("Факт: урон %.1f · событий урона %d (включая тики) · убийств %d · DPS %.2f (средний за время учёта)" % [float(actual.get("damage",0)),int(actual.get("hits",0)),int(actual.get("kills",0)),float(actual.get("damage",0))/maxf(0.01,sim.elapsed-float(sim.combat_stats.get("tracking_start",0)))],19,Color("b3cbd9"),true))
	else:
		details.add_child(hud.label("Базовый эффект: "+effect_text(id,rank),22,Color("9fe0ca"),true))
	var progress=ProgressBar.new()
	progress.max_value=Catalog.max_rank(id)
	progress.value=rank
	progress.show_percentage=false
	progress.custom_minimum_size.y=12
	details.add_child(progress)
	if rank<Catalog.max_rank(id):
		details.add_child(hud.label(("Следующий ранг: "+Inspector.comparison(sim.build,id,sim.build.quality(id),"",sim.ability_scale(),sim.cooldown_factor())) if sim!=null else "Следующий ранг %d: %s" % [rank+1,effect_text(id,rank+1)],22,Color("c6d8eb"),true))
	else:
		details.add_child(hud.label("Максимальный ранг · орган полностью развит",22,Color("e5cc9c"),true))
	details.add_child(hud.label(Catalog.milestone_text(id,rank),20,Color("d7c39f"),true))
	return card

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
