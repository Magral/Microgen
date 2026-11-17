extends RefCounted
const Catalog = preload("res://core/catalog.gd")
var organs: Dictionary = {}
var adaptations: Dictionary = {}
var qualities: Dictionary = {}
var stats: Dictionary = {"evolutions": {}}
var biomass: int = 0
var unlocked: Array = Catalog.base_unlocked()
var branch: String = "predator"
var _synergy_organs_hash: int = -1
var _synergy_adaptations_hash: int = -1
var _synergy_cache: Array = []

func rank(id: String) -> int:
	return int(organs.get(id, adaptations.get(id, 0)))

func apply(id: String, replace_id: String = "", grade: int = -1) -> bool:
	if Catalog.item(id).is_empty() or id not in unlocked:
		return false
	var target = organs if id in Catalog.ORGANS else adaptations
	var limit = 6 if id in Catalog.ORGANS else 4
	if id in target:
		if replace_id != "": return false
		if target[id] >= Catalog.max_rank(id):
			if clampi(grade, 0, 3) <= quality(id): return false
			qualities[id] = clampi(grade, 0, 3)
			return true
		target[id] += 1
		qualities[id] = maxi(quality(id), clampi(grade, 0, 3))
		return true
	if replace_id != "":
		if replace_id not in target: return false
		var inherited = 1 + int(floor((int(target[replace_id]) - 1) / 2.0))
		var inherited_quality = quality(replace_id)
		target.erase(replace_id)
		qualities.erase(replace_id)
		stats.evolutions.erase(replace_id)
		target[id] = mini(inherited, Catalog.max_rank(id))
		qualities[id] = maxi(inherited_quality, clampi(grade, 0, 3))
		return true
	if target.size() >= limit: return false
	target[id] = 1
	qualities[id] = clampi(grade, 0, 3)
	return true

func active_synergies() -> Array:
	# Dictionaries remain public for old saves/tests: hashes also catch direct edits.
	var organ_hash = hash(organs)
	var adaptation_hash = hash(adaptations)
	if organ_hash == _synergy_organs_hash and adaptation_hash == _synergy_adaptations_hash:
		return _synergy_cache
	var out = []
	for id in Catalog.SYNERGIES:
		var needs = Catalog.SYNERGIES[id].needs
		if rank(needs[0]) > 0 and rank(needs[1]) > 0: out.append(id)
	out.make_read_only()
	_synergy_cache = out
	_synergy_organs_hash = organ_hash
	_synergy_adaptations_hash = adaptation_hash
	return _synergy_cache

func offers(rng: RandomNumberGenerator, filter_branch: String = "") -> Array:
	var pool = []
	for id in unlocked:
		if Catalog.item(id).is_empty() or rank(id) >= Catalog.max_rank(id): continue
		if filter_branch != "" and Catalog.item(id).get("branch", "") != filter_branch: continue
		pool.append(id)
	var out = []
	while out.size() < 3 and not pool.is_empty():
		var weights = []
		var total = 0.0
		for id in pool:
			var w = 1.35 if Catalog.item(id).get("branch", "") == branch else 1.0
			weights.append(w)
			total += w
		var roll = rng.randf() * total
		var index = 0
		for i in range(pool.size()):
			roll -= weights[i]
			if roll <= 0:
				index = i
				break
		out.append(pool[index])
		pool.remove_at(index)
	return out

func spend(amount: int) -> bool:
	if amount < 0 or biomass < amount: return false
	biomass -= amount
	return true

func to_dict() -> Dictionary:
	return {"organs":organs.duplicate(), "adaptations":adaptations.duplicate(), "biomass":biomass, "unlocked":unlocked.duplicate(), "branch":branch, "qualities":qualities.duplicate(), "stats":stats.duplicate(true)}

func from_dict(data: Dictionary):
	organs = {}
	adaptations = {}
	qualities = {}
	stats = {"evolutions": {}}
	unlocked = []
	for id in data.get("unlocked", Catalog.base_unlocked()):
		if not Catalog.item(str(id)).is_empty(): unlocked.append(str(id))
	for key in ["organs","adaptations"]:
		var source = data.get(key, {})
		if not source is Dictionary: continue
		var target = organs if key == "organs" else adaptations
		var limit = 6 if key == "organs" else 4
		for id in source:
			var valid = id in Catalog.ORGANS if key == "organs" else id in Catalog.ADAPTATIONS
			if valid and target.size() < limit:
				target[id] = clampi(int(source[id]), 1, Catalog.max_rank(id))
	var saved_qualities = data.get("qualities", {})
	if saved_qualities is Dictionary:
		for id in organs.keys() + adaptations.keys():
			qualities[id] = clampi(int(saved_qualities.get(id, 0)), 0, 3)
	var saved_stats = data.get("stats", {})
	if saved_stats is Dictionary and saved_stats.get("evolutions", {}) is Dictionary:
		for id in Catalog.EVOLUTIONS:
			if rank(id) > 0 and bool(saved_stats.get("evolutions", {}).get(id, false)):
				stats.evolutions[id] = true
	biomass = maxi(0, int(data.get("biomass", 0)))
	branch = str(data.get("branch", "predator"))

func quality(id: String) -> int:
	return clampi(int(qualities.get(id, 0)), 0, 3) if rank(id) > 0 else 0

func power(id: String) -> float:
	return Catalog.quality_multiplier(quality(id)) * (1.30 if evolved(id) else 1.0)

func passive(id: String) -> float:
	var r = rank(id)
	var multiplier = Catalog.quality_multiplier(quality(id))
	match id:
		"armor", "speed": return minf(0.60, Catalog.adaptation_bonus(r) * multiplier)
		"regen": return 0.5 * r * multiplier
		"magnet": return 55.0 * r * multiplier
		"metabolism": return 0.06 * r * multiplier
		"catalysis": return 0.08 * r * multiplier
	return 0.0

func evolved(id: String) -> bool:
	return rank(id) > 0 and bool(stats.get("evolutions", {}).get(id, false))

func evolution_candidates() -> Array:
	var out = []
	for id in Catalog.EVOLUTIONS:
		var recipe = Catalog.EVOLUTIONS[id]
		if not evolved(id) and rank(id) >= 6 and rank(recipe.passive) >= 3:
			out.append(id)
	return out

func evolve(id: String) -> bool:
	if id not in evolution_candidates(): return false
	stats.evolutions[id] = true
	return true
