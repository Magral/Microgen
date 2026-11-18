extends RefCounted
const Catalog = preload("res://core/catalog.gd")
const Equipment = preload("res://core/organism_equipment.gd")
# Zero retains six-kind compatibility for legacy builds.
var organ_capacity: int = 0
var extra_organ_cells: int = 0
var organs: Dictionary = {}
var adaptations: Dictionary = {}
var qualities: Dictionary = {}
var specializations: Dictionary = {}
var temporary_mutations: Array = []
var stats: Dictionary = {"evolutions": {}}
var biomass: int = 0
var unlocked: Array = Catalog.base_unlocked()
var branch: String = "predator"
var branch_weight=1.35
var _synergy_organs_hash: int = -1
var _synergy_adaptations_hash: int = -1
var _synergy_cache: Array = []

func rank(id: String) -> int:
	var stored=int(organs.get(id, adaptations.get(id, 0)))
	if id in Catalog.ORGANS and stored>10:return Catalog.effective_rank(stored)
	return stored

func stored_rank(id: String) -> int:
	return int(organs.get(id, adaptations.get(id,0)))

func used_organ_cells() -> int:
	var total = maxi(0, extra_organ_cells)
	for id in organs:
		total += Equipment.cell_cost(id)
	return total

func can_fit(id: String, replace_id: String = "") -> bool:
	if Catalog.item(id).is_empty(): return false
	var is_organ = id in Catalog.ORGANS
	var target = organs if is_organ else adaptations
	if id in target: return replace_id == ""
	if replace_id != "" and replace_id not in target: return false
	if is_organ and organ_capacity > 0:
		return used_organ_cells() + Equipment.cell_cost(id) - Equipment.cell_cost(replace_id) <= organ_capacity
	return replace_id != "" or target.size() < (6 if is_organ else 4)

func apply(id: String, replace_id: String = "", grade: int = -1) -> bool:
	if Catalog.item(id).is_empty() or id not in unlocked:
		return false
	var target = organs if id in Catalog.ORGANS else adaptations
	if id in target:
		if replace_id != "": return false
		if target[id] >= Catalog.max_rank(id):
			if clampi(grade, 0, 3) <= quality(id): return false
			qualities[id] = clampi(grade, 0, 3)
			return true
		target[id] += 1
		qualities[id] = maxi(quality(id), clampi(grade, 0, 3))
		return true
	if not can_fit(id, replace_id): return false
	if replace_id != "":
		if replace_id not in target: return false
		var inherited = 1 + int(floor((int(target[replace_id]) - 1) / 2.0))
		var inherited_quality = quality(replace_id)
		target.erase(replace_id)
		qualities.erase(replace_id)
		specializations.erase(replace_id)
		stats.evolutions.erase(replace_id)
		target[id] = mini(inherited, Catalog.max_rank(id))
		qualities[id] = maxi(inherited_quality, clampi(grade, 0, 3))
		return true
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
		if Catalog.item(id).is_empty() or stored_rank(id) >= Catalog.max_rank(id): continue
		if filter_branch != "" and Catalog.item(id).get("branch", "") != filter_branch: continue
		pool.append(id)
	var out = []
	while out.size() < 3 and not pool.is_empty():
		var weights = []
		var total = 0.0
		for id in pool:
			var w = branch_weight if Catalog.item(id).get("branch", "") == branch else 1.0
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
	return {"organ_capacity":organ_capacity,"extra_organ_cells":extra_organ_cells,"organs":organs.duplicate(), "adaptations":adaptations.duplicate(), "biomass":biomass, "unlocked":unlocked.duplicate(), "branch":branch, "qualities":qualities.duplicate(), "specializations":specializations.duplicate(), "temporary_mutations":temporary_mutations.duplicate(true), "stats":stats.duplicate(true)}

func from_dict(data: Dictionary):
	organ_capacity = maxi(0, int(data.get("organ_capacity", 0)))
	extra_organ_cells = maxi(0, int(data.get("extra_organ_cells", 0)))
	organs = {}
	adaptations = {}
	qualities = {}
	specializations = {}
	temporary_mutations=[]
	stats = {"evolutions": {}}
	unlocked = []
	for id in data.get("unlocked", Catalog.base_unlocked()):
		if not Catalog.item(str(id)).is_empty(): unlocked.append(str(id))
	for key in ["organs","adaptations"]:
		var source = data.get(key, {})
		if not source is Dictionary: continue
		var target = organs if key == "organs" else adaptations
		for id in source:
			var valid = id in Catalog.ORGANS if key == "organs" else id in Catalog.ADAPTATIONS
			if valid and can_fit(id):
				target[id] = clampi(int(source[id]), 1, Catalog.max_rank(id))
	var saved_qualities = data.get("qualities", {})
	if saved_qualities is Dictionary:
		for id in organs.keys() + adaptations.keys():
			qualities[id] = clampi(int(saved_qualities.get(id, 0)), 0, 3)
	var saved_specializations=data.get("specializations",{})
	if saved_specializations is Dictionary:
		for id in organs.keys():
			var saved=str(saved_specializations.get(id,""))
			var migrated=Catalog.legacy_specialization(str(id),saved)
			if migrated!="":specializations[id]=migrated
	var saved_temporary=data.get("temporary_mutations",[])
	if saved_temporary is Array:
		for active in saved_temporary:
			if not active is Dictionary:continue
			var id=str(active.get("id",""))
			if not Catalog.TEMP_MUTATIONS.has(id) or temporary_mutations.size()>=3 or temporary_mutations.any(func(entry):return str(entry.id)==id):continue
			temporary_mutations.append({"id":id,"rank":clampi(int(active.get("rank",1)),1,3),"quality":clampi(int(active.get("quality",0)),0,3)})
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
	var saved_rank=stored_rank(id)
	if str(specializations.get(id,"")).is_empty() and temporary_mutations.is_empty() and (id not in Catalog.ORGANS or saved_rank<=10):
		return Catalog.quality_multiplier(quality(id))*(1.30 if evolved(id) else 1.0)
	var mutation=1.0
	var specialization=str(specializations.get(id,""))
	if not specialization.is_empty():
		var specification=Catalog.specialization_data(id,specialization)
		mutation=float(specification.get("power",1.0))
		if specification.has("synergy_power"):
			for synergy_id in active_synergies():
				if id in Catalog.SYNERGIES[synergy_id].needs:mutation=float(specification.synergy_power);break
	var endless=1.0
	if id in Catalog.ORGANS:
		if saved_rank>10:endless=1.0+minf(0.45,0.02*log(1.0+float(saved_rank-10)))
	var temporary=1.0
	if not temporary_mutations.is_empty():
		for active in temporary_mutations:
			var targets=Catalog.temporary_mutation(str(active.get("id",""))).get("power_targets",{})
			if not targets.has(id):continue
			var potency=float(active.get("rank",1))*Catalog.quality_multiplier(int(active.get("quality",0)))
			temporary*=pow(float(targets[id]),potency)
	return Catalog.quality_multiplier(quality(id)) * mutation * endless * temporary * (1.30 if evolved(id) else 1.0)

func specialization_value(id: String,key: String,fallback: float=1.0) -> float:
	var value=Catalog.specialization_value(id,str(specializations.get(id,"")),key,fallback)
	if not temporary_mutations.is_empty():
		for active in temporary_mutations:
			var targets=Catalog.temporary_mutation(str(active.get("id",""))).get("value_targets",{}).get(id,{})
			if not targets.has(key):continue
			var potency=float(active.get("rank",1))*Catalog.quality_multiplier(int(active.get("quality",0)))
			value*=pow(float(targets[key]),potency)
	return value

func specialization_bonus(id: String,key: String) -> int:
	var value=Catalog.specialization_bonus(id,str(specializations.get(id,"")),key)
	if not temporary_mutations.is_empty():
		for active in temporary_mutations:
			var targets=Catalog.temporary_mutation(str(active.get("id",""))).get("bonus_targets",{}).get(id,{})
			if targets.has(key):value+=int(targets[key])*int(active.get("rank",1))
	return value

func apply_temporary_mutation(id: String,grade: int=0) -> bool:
	if not Catalog.TEMP_MUTATIONS.has(id):return false
	for active in temporary_mutations:
		if str(active.get("id",""))!=id:continue
		if int(active.get("rank",1))>=3 and int(active.get("quality",0))>=grade:return false
		active.rank=mini(3,int(active.get("rank",1))+1)
		active.quality=maxi(int(active.get("quality",0)),clampi(grade,0,3))
		return true
	if temporary_mutations.size()>=3:return false
	temporary_mutations.append({"id":id,"rank":1,"quality":clampi(grade,0,3)})
	return true

func temporary_mutation_rank(id: String)->int:
	for active in temporary_mutations:
		if str(active.get("id",""))==id:return int(active.get("rank",1))
	return 0

func temporary_mutation_quality(id: String)->int:
	for active in temporary_mutations:
		if str(active.get("id",""))==id:return int(active.get("quality",0))
	return 0

func temporary_passive_bonus(id: String) -> float:
	var total=0.0
	if not temporary_mutations.is_empty():
		for active in temporary_mutations:
			var bonus=float(Catalog.temporary_mutation(str(active.get("id",""))).get("passive_bonuses",{}).get(id,0.0))
			total+=bonus*float(active.get("rank",1))*Catalog.quality_multiplier(int(active.get("quality",0)))
	return total

func passive(id: String) -> float:
	var r = rank(id)
	var multiplier = Catalog.quality_multiplier(quality(id))
	match id:
		"armor": return minf(0.60, Catalog.adaptation_bonus(r) * multiplier+temporary_passive_bonus(id))
		"speed": return minf(0.60, Catalog.adaptation_bonus(r) * multiplier)
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
