extends RefCounted
const Catalog = preload("res://core/catalog.gd")
const Art = preload("res://ui/organ_art.gd")
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
	box.add_child(hud.label("Боевые органы · %d/6" % sim.build.organs.size(),26))
	_equipped(hud,box,sim,sim.build.organs)
	box.add_child(hud.label("Пассивные адаптации · %d/4" % sim.build.adaptations.size(),26))
	_equipped(hud,box,sim,sim.build.adaptations)
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
		box.add_child(item_card(hud,id,sim.build.rank(id)))

static func item_card(hud,id: String,rank: int):
	var card=hud.card()
	var row=hud.row()
	card.add_child(row)
	var art=Art.new()
	art.organ_id=id
	art.custom_minimum_size=Vector2(94,94)
	row.add_child(art)
	var details=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var item=Catalog.item(id)
	details.add_child(hud.label("%s · %d/%d" % [item.name,rank,Catalog.max_rank(id)],23,Color(item.color),true))
	details.add_child(hud.label(item.desc,18,Color("bed2d1"),true))
	details.add_child(hud.label(effect_text(id,rank),18,Color("9fe0ca"),true))
	return card

static func effect_text(id: String,rank: int) -> String:
	# Catalog owns combat numbers so descriptions stay synchronized with balance.
	var catalog=Catalog.new()
	if catalog.has_method("effect_text"): return catalog.call("effect_text",id,rank)
	return Catalog.item(id).desc
