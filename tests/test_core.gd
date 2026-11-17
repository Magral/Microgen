extends SceneTree

const Build = preload("res://core/build_model.gd")
const Save = preload("res://core/save_store.gd")
var checks := 0
var failures := 0

func check(condition: bool, message: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize():
	var b = Build.new()
	b.unlocked.append("division")
	check(b.apply("tentacle"), "start organ")
	check(b.apply("acid"), "acid")
	check("acid_grasp" in b.active_synergies(), "acid grasp activates")
	for id in ["spikes", "pulse", "division", "trail"]:
		check(b.apply(id), "fill slots")
	check(not b.apply("infection"), "seventh organ rejected")
	b.apply("tentacle")
	b.apply("tentacle")
	check(b.apply("infection", "tentacle"), "replace organ")
	check(b.organs.infection == 2, "half invested rank transferred")
	check(not "acid_grasp" in b.active_synergies(), "lost dependency disables synergy")
	check(b.organs.size() == 6, "slots invariant")
	var old = b.to_dict()
	check(not b.apply("bogus"), "unknown id rejected")
	check(b.to_dict() == old, "failed transaction unchanged")
	check(not b.spend(20), "insufficient currency")
	b.biomass = 30
	check(b.spend(20) and b.biomass == 10, "valid spend")
	for i in range(10): b.apply("acid")
	check(b.organs.acid == 5, "rank cap")
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	var offers = b.offers(rng)
	check(offers.size() == 3, "three choices")
	check(not "acid" in offers, "max rank excluded")
	var restored = Build.new()
	restored.from_dict(b.to_dict())
	check(restored.to_dict() == b.to_dict(), "build roundtrip")
	var save = Save.new("user://test-profile.json")
	save.clear_test_files()
	save.load_profile()
	save.bank(20)
	check(save.unlock("division") and save.profile.cores == 12, "unlock costs eight")
	check(not save.unlock("division") and save.profile.cores == 12, "no double purchase")
	save.bank(1)
	var f = FileAccess.open(save.path, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	var recover = Save.new(save.path)
	recover.load_profile()
	check(recover.profile.cores == 12, "corrupt current recovers backup")
	check("division" in recover.profile.unlocked, "unlock preserved in backup")
	check(recover.credit_once("run1:boss", 5), "first reward")
	check(not recover.credit_once("run1:boss", 5), "reward idempotent")
	recover.clear_test_files()
	print("CORE: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
