extends RefCounted
const Catalog = preload("res://core/catalog.gd")
const Legacy = preload("res://core/genome_legacy.gd")
var path: String
var profile: Dictionary
var last_error: String = ""

func _init(file_path: String = "user://profile.json"):
	path = file_path
	profile = defaults()

func defaults() -> Dictionary:
	return {"version":1, "cores":0, "unlocked":Catalog.base_unlocked(), "discovered":[], "synergies":[], "upgrades":{"health":0,"collect":0,"regen":0}, "credited":[], "runs":0, "wins":0, "checkpoint":{}, "best":0.0, "legacy":Legacy.defaults()}

func _read(candidate: String) -> Dictionary:
	if not FileAccess.file_exists(candidate): return {}
	var text = FileAccess.get_file_as_string(candidate)
	var parser = JSON.new()
	if parser.parse(text) != OK: return {}
	var data = parser.data
	if not data is Dictionary or data.get("version", 0) != 1: return {}
	for k in ["unlocked", "discovered", "synergies", "credited"]:
		if not data.get(k, []) is Array: return {}
	if not data.get("upgrades", {}) is Dictionary or not data.get("checkpoint", {}) is Dictionary: return {}
	for key in ["cores","runs","wins","best"]:
		var value = data.get(key, 0)
		if not (value is int or value is float) or not is_finite(float(value)): return {}
	for id in ["health","collect","regen"]:
		var value = data.get("upgrades", {}).get(id, 0)
		if not (value is int or value is float) or not is_finite(float(value)): return {}
	var clean = defaults()
	clean.merge(data, true)
	for id in Catalog.base_unlocked():
		if not id in clean.unlocked:clean.unlocked.append(id)
	clean.cores = maxi(0, int(clean.cores))
	for id in ["health","collect","regen"]:
		clean.upgrades[id] = clampi(int(clean.upgrades.get(id,0)),0,5)
	clean.legacy = Legacy.normalize(clean)
	return clean

func load_profile() -> Dictionary:
	profile = _read(path)
	if profile.is_empty(): profile = _read(path + ".bak")
	if profile.is_empty(): profile = defaults()
	return profile

func write_profile(data: Dictionary = profile) -> bool:
	data = data.duplicate(true)
	data.legacy = Legacy.normalize(data)
	var tmp = path + ".tmp"
	var serialized=JSON.stringify(data)
	if not _write_tmp(tmp,serialized): return false
	# A successful system call is insufficient: reject truncated or altered bytes
	# before touching either the primary save or its known-good backup.
	var stored=JSON.new()
	if stored.parse(FileAccess.get_file_as_string(tmp))!=OK or _read(tmp).is_empty():
		last_error="Проверка сохранения не пройдена"
		return false
	var intended=JSON.parse_string(serialized)
	if JSON.stringify(stored.data)!=JSON.stringify(intended):
		last_error="Данные сохранения записаны не полностью"
		return false
	if not _read(path).is_empty():
		var staged_backup=path+".bak.tmp"
		if DirAccess.copy_absolute(path,staged_backup)!=OK or _read(staged_backup).is_empty() or DirAccess.rename_absolute(staged_backup,path+".bak")!=OK:
			last_error = "Не удалось обновить резервную копию"
			return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		last_error = "Не удалось записать сохранение"
		return false
	profile = data
	last_error = ""
	return true

# Overridable I/O boundary also permits actual-file failure regression tests.
func _write_tmp(tmp: String,serialized: String) -> bool:
	var f=FileAccess.open(tmp,FileAccess.WRITE)
	if f==null:
		last_error="Не удалось открыть сохранение"
		return false
	f.store_string(serialized)
	var stored_ok=f.get_error()==OK
	f.flush()
	var flushed_ok=f.get_error()==OK
	f.close()
	if not stored_ok or not flushed_ok:
		last_error="Не удалось полностью записать сохранение"
		return false
	return true

func bank(amount: int) -> bool:
	if amount < 0: return false
	var next = profile.duplicate(true)
	next.cores += amount
	return write_profile(next)

func credit_once(token: String, amount: int) -> bool:
	if token in profile.credited or amount < 0: return false
	var next = profile.duplicate(true)
	next.credited.append(token)
	next.cores += amount
	return write_profile(next)

func unlock(id: String) -> bool:
	if id in profile.unlocked or id not in Catalog.ORGANS: return false
	var price = Catalog.ORGANS[id].get("unlock", 8)
	if profile.cores < price: return false
	var next = profile.duplicate(true)
	next.cores -= price
	next.unlocked.append(id)
	if id == "division": next.legacy = Legacy.normalize(next)
	return write_profile(next)

func buy_upgrade(id: String) -> bool:
	if id not in profile.upgrades: return false
	var rank = int(profile.upgrades[id])
	var price = 4 + rank * 4
	if rank >= 5 or profile.cores < price: return false
	var next = profile.duplicate(true)
	next.cores -= price
	next.upgrades[id] += 1
	return write_profile(next)

func clear_test_files():
	if not "test-" in path: return
	for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)

# Every action works on a candidate and commits live state only after durable write.
func research(id: String) -> bool:
	var progress=Legacy.focus_progress(profile,id)
	if progress.is_empty() or not progress.ready: return false
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	next.cores-=progress.cost
	var branch=Legacy.RESEARCH[id].branch
	next.legacy.knowledge[branch]=maxi(0,int(next.legacy.knowledge[branch])-mini(progress.knowledge,int(Legacy.RESEARCH[id].cost)))
	next.legacy.research.append(id)
	if id=="colony" and "division" not in next.unlocked: next.unlocked.append("division")
	next.legacy=Legacy.normalize(next)
	return write_profile(next)

func select_form(id: String) -> bool:
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	if id not in next.legacy.forms: return false
	next.legacy.selected_form=id
	return write_profile(next)

func toggle_trait(id: String) -> bool:
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	if id not in next.legacy.traits: return false
	if id in next.legacy.equipped_traits: next.legacy.equipped_traits.erase(id)
	elif next.legacy.equipped_traits.size()<2: next.legacy.equipped_traits.append(id)
	else: return false
	return write_profile(next)

func select_imprint(id: String) -> bool:
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	if not id.is_empty() and not next.legacy.imprints.any(func(x): return x.id==id): return false
	next.legacy.selected_imprint=id
	return write_profile(next)

func reroll_morphology() -> bool:
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	next.legacy.morphology_seed=(int(next.legacy.morphology_seed)*48271)%2147483647
	return write_profile(next)

func save_preset(name: String) -> bool:
	name=name.strip_edges().left(32)
	if name.is_empty(): return false
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	var preset=Legacy.loadout(next)
	preset.name=name
	var found=-1
	for i in range(next.legacy.presets.size()):
		if next.legacy.presets[i].name==name: found=i
	if found>=0: next.legacy.presets[found]=preset
	elif next.legacy.presets.size()<6: next.legacy.presets.append(preset)
	else: return false
	return write_profile(next)

func load_preset(index: int) -> bool:
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	if index<0 or index>=next.legacy.presets.size(): return false
	var preset=next.legacy.presets[index]
	next.legacy.selected_form=preset.form
	next.legacy.equipped_traits=preset.traits.duplicate()
	next.legacy.selected_imprint=preset.imprint
	next.legacy.morphology_seed=preset.seed
	return write_profile(next)

func focus_research(id: String) -> bool:
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	if not id.is_empty() and (id not in Legacy.RESEARCH or id in next.legacy.research): return false
	next.legacy.focus=id
	return write_profile(next)

func claim_imprint(id: String) -> bool:
	var next=profile.duplicate(true)
	next.legacy=Legacy.normalize(next)
	var chosen={}
	for candidate in next.legacy.pending:
		if candidate.id==id: chosen=candidate
	if chosen.is_empty(): return false
	if next.legacy.imprints.any(func(x): return x.id==id):
		var branch=chosen.branch
		next.legacy.knowledge[branch]=mini(3,int(next.legacy.knowledge[branch])+1)
	else: next.legacy.imprints.append(chosen.duplicate(true))
	next.legacy.pending=next.legacy.pending_queue.pop_front() if not next.legacy.pending_queue.is_empty() else []
	next.legacy.selected_imprint=id
	return write_profile(next)
