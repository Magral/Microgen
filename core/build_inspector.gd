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
			details = "; щупалец %d; суммарный залп делится между ними; дальность %.1f" % [Catalog.tentacle_count(r),(165+r*12)*scale]
		"acid":
			damage = 4+r*3; continuous = true
			details = "; радиус %.1f" % ((75+r*9)*scale)
		"spikes":
			damage = 12+r*5; interval = 1.3
			details = "; шипов %d (DPS на один шип)" % Catalog.shot_count(r)
		"pulse":
			damage = 12+r*8; interval = 3.2
			details = "; радиус %.1f" % ((130+r*18)*scale)
		"division":
			damage = 8+r*4; continuous = true
			details = "; копий %d (урон одной копии)" % Catalog.clone_count(r)
		"trail":
			damage = 5+r*3; continuous = true
			details = "; радиус %.1f; поле 3 с; интервал 0,6 с" % (50+r*6)
		"infection":
			damage = 4+r*3; continuous = true
			details = "; заражение 4,5 с; интервал %.2f с" % (1.6*tempo)
		"devour":
			damage = 7+r*5; interval = 0.45
			details = "; сектор 80°; время переваривания −35%%; лечение %.1f HP за поглощение" % (r*0.8)
		"cilia":
			damage = 10+r*6; interval = 1.4
			details = "; дальность %.1f; сектор 120°" % ((100+r*10)*scale)
		"enzymes":
			damage = 3+r*2; continuous = true
			details = "; ферменты 4 с; интервал 2 с"
		"electric":
			damage = 12+r*6; interval = 2.6
			details = "; целей %d" % Catalog.electric_targets(r)
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
