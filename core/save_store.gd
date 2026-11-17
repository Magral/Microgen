extends RefCounted
const Catalog = preload("res://core/catalog.gd")
var path: String
var profile: Dictionary
var last_error: String = ""

func _init(file_path: String = "user://profile.json"):
	path = file_path
	profile = defaults()

func defaults() -> Dictionary:
	return {"version":1, "cores":0, "unlocked":Catalog.base_unlocked(), "discovered":[], "synergies":[], "upgrades":{"health":0,"collect":0,"regen":0}, "credited":[], "runs":0, "wins":0, "checkpoint":{}, "best":0.0}

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
	var clean = defaults()
	clean.merge(data, true)
	for id in Catalog.base_unlocked():
		if not id in clean.unlocked:clean.unlocked.append(id)
	clean.cores = maxi(0, int(clean.cores))
	for id in ["health","collect","regen"]:
		clean.upgrades[id] = clampi(int(clean.upgrades.get(id,0)),0,5)
	return clean

func load_profile() -> Dictionary:
	profile = _read(path)
	if profile.is_empty(): profile = _read(path + ".bak")
	if profile.is_empty(): profile = defaults()
	return profile

func write_profile(data: Dictionary = profile) -> bool:
	var tmp = path + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "Не удалось открыть сохранение"
		return false
	f.store_string(JSON.stringify(data))
	f.flush()
	f.close()
	if not _read(path).is_empty():
		if DirAccess.copy_absolute(path, path + ".bak") != OK:
			last_error = "Не удалось обновить резервную копию"
			return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		last_error = "Не удалось записать сохранение"
		return false
	profile = data
	last_error = ""
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
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
