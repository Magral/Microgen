extends RefCounted
const Catalog = preload("res://core/catalog.gd")
var organs: Dictionary = {}
var adaptations: Dictionary = {}
var biomass: int = 0
var unlocked: Array = Catalog.base_unlocked()
var branch: String = "predator"

func rank(id: String) -> int:
	return int(organs.get(id, adaptations.get(id, 0)))

func apply(id: String, replace_id: String = "") -> bool:
	if Catalog.item(id).is_empty() or id not in unlocked:
		return false
	var target = organs if id in Catalog.ORGANS else adaptations
	var limit = 6 if id in Catalog.ORGANS else 4
	if id in target:
		if target[id] >= Catalog.max_rank(id) or replace_id != "": return false
		target[id] += 1
		return true
	if replace_id != "":
		if replace_id not in target: return false
		var inherited = 1 + int(floor((int(target[replace_id]) - 1) / 2.0))
		target.erase(replace_id)
		target[id] = mini(inherited, Catalog.max_rank(id))
		return true
	if target.size() >= limit: return false
	target[id] = 1
	return true

func active_synergies() -> Array:
	var out = []
	for id in Catalog.SYNERGIES:
		var needs = Catalog.SYNERGIES[id].needs
		if rank(needs[0]) > 0 and rank(needs[1]) > 0: out.append(id)
	return out

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
	return {"organs":organs.duplicate(), "adaptations":adaptations.duplicate(), "biomass":biomass, "unlocked":unlocked.duplicate(), "branch":branch}

func from_dict(data: Dictionary):
	organs = {}
	adaptations = {}
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
	biomass = maxi(0, int(data.get("biomass", 0)))
	branch = str(data.get("branch", "predator"))
