extends RefCounted
const Catalog = preload("res://core/catalog.gd")
const Build = preload("res://core/build_model.gd")

# Values before enemy resistance and size-rule attenuation, using current catalysis.
static func effect_text(build, id: String, scale: float = 1.0,tempo: float = 1.0) -> String:
	var r = build.rank(id)
	if r <= 0: return "Не установлено"
	var mult = build.power(id) * (1.0 + build.passive("catalysis"))
	var synergies = build.active_synergies()
	if id == "devour" and "enzyme_bite" in synergies: mult *= 1.25
	if id == "trail" and "ferment_cloud" in synergies: mult *= 1.25
	var damage = 0.0
	var interval = 1.0
	var details = ""
	var continuous = false
	match id:
		"tentacle":
			damage = 9+r*7; interval = 0.85
			details = "; щупалец %d; суммарный залп делится между ними; дальность %.1f" % [Catalog.tentacle_count(r),(165+r*12)*build.specialization_value(id,"reach_mult")*scale]
		"acid":
			damage = 4+r*3; continuous = true
			details = "; радиус %.1f" % ((75+r*9)*build.specialization_value(id,"radius_mult")*scale)
		"spikes":
			damage = 12+r*5; interval = 1.3
			details = "; шипов %d (DPS на один шип)" % mini(7,Catalog.shot_count(r)+build.specialization_bonus(id,"shot_bonus"))
		"pulse":
			damage = 12+r*8; interval = 3.2
			details = "; радиус %.1f" % ((130+r*18)*build.specialization_value(id,"radius_mult")*scale)
		"division":
			damage = 8+r*4; continuous = true
			details = "; копий %d (урон одной копии)" % mini(6,Catalog.clone_count(r)+build.specialization_bonus(id,"clone_bonus"))
		"trail":
			damage = 5+r*3; continuous = true
			details = "; радиус %.1f; поле %.1f с; интервал 0,6 с" % [50+r*6,3.0*build.specialization_value(id,"duration_mult")]
		"infection":
			damage = 4+r*3; continuous = true
			details = "; заражение %.1f с; интервал %.2f с" % [4.5*build.specialization_value(id,"duration_mult"),1.6*tempo]
		"devour":
			damage = 7+r*5; interval = 0.45*build.specialization_value(id,"bite_cooldown_mult")
			details = "; сектор 80°; время переваривания −35%%; лечение %.1f HP за поглощение" % (r*0.8)
		"cilia":
			damage = 10+r*6; interval = 1.4
			details = "; дальность %.1f; сектор 120°" % ((100+r*10)*build.specialization_value(id,"reach_mult")*scale)
		"enzymes":
			damage = 3+r*2; continuous = true
			details = "; ферменты %.1f с; интервал 2 с" % (4.0*build.specialization_value(id,"duration_mult"))
		"electric":
			damage = 12+r*6; interval = 2.6
			details = "; целей %d" % mini(7,Catalog.electric_targets(r)+build.specialization_bonus(id,"target_bonus"))
		"barrier":
			return "Щит %.1f HP; восстановление 8 с" % (Catalog.scaled_damage(8+r*6,r)*build.power(id))
		"armor": return "Снижение урона %.1f%% (предел 60%%)" % (build.passive(id)*100)
		"speed": return "Скорость +%.1f%% (предел 60%%)" % (build.passive(id)*100)
		"regen": return "Регенерация %.2f HP/с" % build.passive(id)
		"magnet": return "Радиус притяжения: тело + %.1f" % build.passive(id)
		"metabolism": return "Получаемая ДНК (XP) +%.1f%%" % (build.passive(id)*100)
		"catalysis": return "Урон органов +%.1f%%" % (build.passive(id)*100)
		_: return Catalog.item(id).get("desc", "")
	if id in ["tentacle","spikes","pulse"]:interval*=tempo
	damage = Catalog.scaled_damage(damage,r)*mult
	if build.evolved("acid") and id=="acid":details+="; ответная кислота %.2f DPS, 1,2 с, радиус %.1f, раз в 2 с" % [Catalog.scaled_damage(3+r*1.5,r)*mult,34*scale*0.8]
	if build.evolved("infection") and id=="infection":details+="; споры %.2f DPS, 2,4 с, радиус %.1f за 3 порции" % [Catalog.scaled_damage(4+r*2,r)*mult,34*scale*2.3]
	if build.evolved("tentacle") and id=="tentacle" and build.rank("acid")>0:details+="; удерживающая кислота %.2f DPS на цель" % (Catalog.scaled_damage(1+build.rank("acid"),build.rank("acid"))*build.power("acid")*(1+build.passive("catalysis")))
	if build.evolved(id):details+="; "+str(Catalog.EVOLUTIONS.get(id,{}).get("behavior","Урон эволюции ×1,30"))
	if continuous: return "Урон %.2f/с (DPS)" % damage + details
	return "Урон %.2f; DPS %.2f; интервал %.2f с" % [damage,damage/interval,interval] + details

static func comparison(build, id: String, quality: int, replace_id: String = "",scale: float=1.0,tempo: float=1.0) -> String:
	var next = Build.new()
	next.from_dict(build.to_dict())
	var current_id = replace_id if replace_id != "" else id
	var current = effect_text(build,current_id,scale,tempo)
	if not next.apply(id,replace_id,quality):
		if replace_id=="" and build.rank(id)==0 and not Catalog.item(id).is_empty():
			var target=next.organs if id in Catalog.ORGANS else next.adaptations
			target[id]=1;next.qualities[id]=clampi(quality,0,3)
			return "После выбора замены: "+effect_text(next,id,scale,tempo)+". Наследуемые ранг и качество уточнятся после выбора органа."
		return current + " → недоступно"
	return current + " → " + effect_text(next,id,scale,tempo)

static func synergy_lines(build, id: String) -> String:
	var lines: Array[String] = []
	var specialization=Catalog.specialization_data(id,str(build.specializations.get(id,"")))
	if specialization.has("synergy_power"):
		var linked=false
		for synergy_id in build.active_synergies():
			if id in Catalog.SYNERGIES[synergy_id].needs:linked=true;break
		lines.append("✦ %s: сила органа ×%.2f%s."%[str(specialization.name),float(specialization.synergy_power)," · активирована синергия" if linked else " · включится при синергии"])
	for synergy in Catalog.SYNERGIES.values():
		if id not in synergy.needs: continue
		var a = synergy.needs[0]
		var b = synergy.needs[1]
		var ready = build.rank(a)>0 and build.rank(b)>0
		lines.append(("✓ " if ready else "◇ ")+synergy.name+": "+Catalog.item(a).name+" %d/1 + " % build.rank(a)+Catalog.item(b).name+" %d/1. " % build.rank(b)+synergy.desc)
	for organ in Catalog.EVOLUTIONS:
		var recipe = Catalog.EVOLUTIONS[organ]
		if id != organ and id != recipe.passive: continue
		var state = "✓ Эволюция" if build.evolved(organ) else ("Готова эволюция" if organ in build.evolution_candidates() else "◇ Эволюция")
		lines.append(state+": "+recipe.name+". "+Catalog.item(organ).name+" %d/6 + " % build.rank(organ)+Catalog.item(recipe.passive).name+" %d/3; урон органа ×1,30 (+30%%)." % build.rank(recipe.passive))
	return "\n".join(lines)

static func synergy_summary(build,id: String)->String:
	var lines=[]
	for synergy in Catalog.SYNERGIES.values():
		if id not in synergy.needs:continue
		var a=str(synergy.needs[0]);var b=str(synergy.needs[1])
		lines.append(("✓ " if build.rank(a)>0 and build.rank(b)>0 else "◇ ")+str(synergy.name)+" · "+str(Catalog.item(a).name)+" + "+str(Catalog.item(b).name))
	return "\n".join(lines) if not lines.is_empty() else "Нет связей с другими органами."
