extends SceneTree
const Genome = preload("res://core/genome.gd")
const Sim = preload("res://game/simulation.gd")
const Painter = preload("res://game/organism_painter.gd")
var checks = 0
var failures = 0
func check(ok: bool,text: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func _initialize():
	var a = Genome.create(42,10,"player",0)
	check(a==Genome.create(42,10,"player",0),"same recipe reproducible")
	check(a!=Genome.create(42,11,"player",0),"different identity changes recipe")
	check(not Genome.validate({"version":1}),"partial recipe rejected")
	var invalid = a.duplicate()
	invalid.rotation = NAN
	check(not Genome.validate(invalid),"nonfinite recipe rejected")
	var shapes = {}
	var palettes = {}
	for i in range(200):
		var recipe = Genome.create(i,i*13,"hunter",i%2)
		check(Genome.validate(recipe),"recipe valid")
		shapes[recipe.family] = true
		palettes[recipe.palette] = true
		for detail in [24,48]:
			var contour = Genome.contour(recipe,detail)
			check(contour.size()==detail and not Geometry2D.triangulate_polygon(contour).is_empty(),"contour triangulates")
			for p in contour: check(p.length()<1.6 and p.length()>0.15,"contour bounded")
	check(shapes.size()==6,"six shape families")
	check(palettes.size()>=7,"palette diversity")
	seed(334)
	var expected = randi()
	seed(334)
	Genome.create(0,0,"hunter",0)
	check(randi()==expected,"generator preserves global RNG")
	var painter = Painter.new()
	for i in range(280): painter.anatomy(Genome.create(i,1,"hunter",0))
	check(painter.cache.size()<=260,"anatomy cache bounded")
	var sim = Sim.new()
	sim.new_run(66)
	check(Genome.validate(sim.player_genome),"player recipe present")
	sim.elapsed = 420
	for i in range(50): sim.spawn_enemy(sim.player+Vector2(150+i*2,0),"hunter")
	for e in sim.enemies: check(e.traits.size()<=3 and Genome.validate(e.genome),"bounded traits and valid appearance")
	var snap = sim.snapshot()
	var copy = Sim.new()
	check(copy.restore(snap),"new snapshot accepted")
	check(copy.player_genome==sim.player_genome,"player recipe persists")
	check(copy.enemies[0].genome==sim.enemies[0].genome,"enemy recipe persists")
	var json_copy = Sim.new()
	check(json_copy.restore(JSON.parse_string(JSON.stringify(snap))),"JSON save restores")
	check(json_copy.player_genome.family==sim.player_genome.family and is_equal_approx(json_copy.player_genome.rotation,sim.player_genome.rotation),"JSON preserves phenotype")
	snap.erase("player_genome")
	for enemy in snap.enemies:
		enemy.erase("genome")
		enemy.erase("traits")
	var legacy = Sim.new()
	check(legacy.restore(snap),"0.1 checkpoint accepted")
	check(Genome.validate(legacy.player_genome) and legacy.enemies[0].traits.is_empty(),"0.1 fallback preserves gameplay")
	for malformed_recipe in [null, [], "broken", 12]:
		var damaged = sim.snapshot()
		damaged.player_genome = malformed_recipe
		damaged.enemies[0].genome = malformed_recipe
		var recovered = Sim.new()
		check(recovered.restore(damaged),"malformed phenotype checkpoint accepted")
		check(Genome.validate(recovered.player_genome) and Genome.validate(recovered.enemies[0].genome),"malformed phenotype regenerated")
	for malformed_enemy in [null, [], "broken", 12]:
		var damaged_enemy = sim.snapshot()
		damaged_enemy.enemies[0].genome = malformed_enemy
		var recovered_enemy = Sim.new()
		check(recovered_enemy.restore(damaged_enemy),"malformed enemy recipe accepted")
		check(Genome.validate(recovered_enemy.enemies[0].genome),"enemy recipe regenerated")
	var regen = Sim.new()
	regen.new_run(82)
	regen.spawn_enemy(regen.player+Vector2(250,0),"hunter")
	regen.enemies[0].traits = ["regen"]
	regen.enemies[0].hp = 10
	regen.step(0.1,Vector2.ZERO)
	check(regen.enemies[0].hp>10,"regeneration heals")
	var toxic = Sim.new()
	toxic.new_run(83)
	toxic.spawn_enemy(toxic.player+Vector2(250,0),"hunter")
	toxic.enemies[0].traits = ["toxic"]
	toxic.enemies[0].emission_cd = 0.0
	toxic.step(0.1,Vector2.ZERO)
	check(toxic.fields.any(func(f): return f.get("hostile",false)),"toxic gland emits")
	var hp = toxic.hp
	toxic._field(toxic.player,70,10,2,"enemy_toxin",true)
	toxic.step(0.1,Vector2.ZERO)
	check(toxic.hp<hp,"hostile toxin damages player")
	var spores = Sim.new()
	spores.new_run(84)
	spores.spawn_enemy(spores.player+Vector2(250,0),"hunter")
	spores.enemies[0].traits = ["spores"]
	spores.enemies[0].hp = 0
	spores.step(0.01,Vector2.ZERO)
	check(spores.fields.any(func(f): return f.get("hostile",false)),"spore death emits")
	print("GENOME: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
