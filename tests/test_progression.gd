extends SceneTree
const Build = preload("res://core/build_model.gd")
const Catalog = preload("res://core/catalog.gd")
const Rewards = preload("res://core/rewards.gd")
const Inspector = preload("res://core/build_inspector.gd")
var checks = 0
var failures = 0
func check(value: bool, message: String):
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize():
	var b = Build.new()
	check(b.apply("tentacle", "", 2) and b.quality("tentacle")==2, "incoming quality applies")
	check(b.apply("tentacle") and b.quality("tentacle")==2, "legacy apply preserves quality")
	check(b.apply("tentacle", "", 0) and b.quality("tentacle")==2, "common offer never downgrades")
	check(b.apply("tentacle", "", 3) and b.quality("tentacle")==3, "better offer raises quality")
	var snapshot = b.to_dict()
	check(not b.apply("acid","missing",3) and b.to_dict()==snapshot, "failed replacement fully rolls back")
	check(not b.evolve("tentacle") and b.to_dict()==snapshot, "ineligible evolution fully rolls back")
	check(b.apply("acid","tentacle",1) and b.rank("acid")==4 and b.quality("acid")==3, "replacement inherits quality-based invested rank and best quality")
	check(b.quality("tentacle")==0 and not b.evolved("tentacle"), "removed organ metadata cleared")
	var before = b.to_dict()
	var preview = Inspector.comparison(b,"acid",0)
	check("→" in preview and b.to_dict()==before, "quality comparison is pure")
	var maxed = Build.new()
	maxed.from_dict({"organs":{"tentacle":Catalog.max_rank("tentacle")},"qualities":{"tentacle":2}})
	var maxed_state = maxed.to_dict()
	check(not maxed.apply("tentacle","",2) and maxed.to_dict()==maxed_state,"same quality at cap fully rolls back")
	check(not maxed.apply("tentacle","",1) and maxed.to_dict()==maxed_state,"lower quality at cap fully rolls back")
	check(not maxed.apply("tentacle") and maxed.to_dict()==maxed_state,"legacy apply at cap fully rolls back")
	check("недоступно" not in Inspector.comparison(maxed,"tentacle",3) and maxed.to_dict()==maxed_state,"quality-only comparison at cap is available and pure")
	check(maxed.apply("tentacle","",3) and maxed.stored_rank("tentacle")==Catalog.max_rank("tentacle") and maxed.quality("tentacle")==3,"better quality at exact storage limit preserves rank")
	var maxed_restored = Build.new()
	maxed_restored.from_dict(JSON.parse_string(JSON.stringify(maxed.to_dict())))
	check(maxed_restored.to_dict()==maxed.to_dict(),"quality-only upgrade survives save restore")
	var maxed_passive = Build.new()
	maxed_passive.from_dict({"adaptations":{"regen":6}})
	check(maxed_passive.apply("regen","",2) and maxed_passive.rank("regen")==6 and is_equal_approx(maxed_passive.passive("regen"),3.75),"quality-only passive upgrade improves actual effect at cap")
	var old = Build.new()
	old.from_dict({"organs":{"tentacle":6},"adaptations":{"magnet":3,"armor":3,"regen":2,"catalysis":2}})
	check(old.quality("tentacle")==0 and is_equal_approx(old.power("tentacle"),1.0), "legacy saves default to common")
	check(is_equal_approx(old.passive("armor"),0.36) and is_equal_approx(old.passive("regen"),1.0), "common passives retain old balance")
	check(old.evolution_candidates()==["tentacle"], "6 organ and 3 matching passive unlock recipe")
	check(old.evolve("tentacle") and old.evolved("tentacle") and is_equal_approx(old.power("tentacle"),1.30), "evolution grants precise universal 30 percent")
	check(not old.evolve("tentacle") and old.evolution_candidates().is_empty(), "evolution is one time")
	old.apply("tentacle","",3)
	check(is_equal_approx(old.power("tentacle"),1.45*1.30), "quality and evolution multiply")
	var restored = Build.new()
	restored.from_dict(JSON.parse_string(JSON.stringify(old.to_dict())))
	check(restored.to_dict()==old.to_dict(), "quality and evolution survive JSON roundtrip")
	check("×1,30" in Inspector.synergy_lines(old,"tentacle") and "3/3" in Inspector.synergy_lines(old,"tentacle"), "inspector exposes recipe ranks and real bonus")
	check("DPS" in Inspector.effect_text(old,"tentacle"), "inspector exposes damage and DPS")
	for organ in Catalog.EVOLUTIONS:
		var recipe = Catalog.EVOLUTIONS[organ]
		var recipe_build = Build.new()
		recipe_build.from_dict({"organs":{organ:5},"adaptations":{recipe.passive:3}})
		check(not recipe_build.evolve(organ), "rank five cannot evolve "+organ)
		recipe_build.apply(organ)
		check(recipe_build.evolve(organ), "all six recipes validated "+organ)
	var p = Build.new()
	p.from_dict({"adaptations":{"armor":6,"speed":6,"metabolism":3,"catalysis":3},"qualities":{"armor":3,"speed":3,"metabolism":2,"catalysis":1}})
	check(is_equal_approx(p.passive("armor"),0.60) and is_equal_approx(p.passive("speed"),0.60), "quality respects defense and speed caps")
	check(is_equal_approx(p.passive("metabolism"),0.18*1.25) and is_equal_approx(p.passive("catalysis"),0.24*1.12), "quality scales XP and catalysis")
	var cache = Build.new()
	cache.organs = {"tentacle":1}
	check(cache.active_synergies().is_empty(), "initial synergy cache empty")
	cache.organs["acid"] = 1
	check("acid_grasp" in cache.active_synergies(), "direct organ mutation invalidates cache")
	cache.organs = {"division":1}
	cache.adaptations["metabolism"] = 1
	check("metabolic_colony" in cache.active_synergies(), "direct passive mutation invalidates cache")
	cache.from_dict({"organs":{"spikes":1,"pulse":1}})
	check(cache.active_synergies()==["spike_pulse"], "restore invalidates synergy cache")
	var rng = RandomNumberGenerator.new()
	rng.seed = 1091
	var counts = [0,0,0,0]
	for i in range(20000): counts[Rewards.roll_quality(rng)] += 1
	check(counts[0]>counts[1] and counts[1]>counts[2] and counts[2]>counts[3] and counts[3]>100, "quality rarity weights produce all four meaningful outcomes")
	var rng2 = RandomNumberGenerator.new()
	var rng3 = RandomNumberGenerator.new()
	rng2.seed = 55; rng3.seed = 55
	for i in range(20): check(Rewards.roll_quality(rng2,2)==Rewards.roll_quality(rng3,2), "seeded quality roll reproducible")
	check(Rewards.quality_weights(10)[3]>Rewards.quality_weights(0)[3], "higher tier improves legendary weight")
	check(Rewards.quality_name(3)=="легендарная" and is_equal_approx(Rewards.multiplier(2),1.25), "quality names describe mechanical grades")
	print("PROGRESSION: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
