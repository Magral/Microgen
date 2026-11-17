extends SceneTree
const Sim = preload("res://game/simulation.gd")
var failures = 0
var checks = 0
func check(ok: bool, text: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(text)
func _initialize():
	var a = Sim.new()
	var b = Sim.new()
	a.new_run(12345)
	b.new_run(12345)
	check(a.world.cells == b.world.cells, "same seed terrain")
	check(a.world.colonies == b.world.colonies, "same seed colonies")
	var c = Sim.new()
	c.new_run(12346)
	check(a.world.cells != c.world.cells, "different seed terrain")
	for poi in a.world.colonies + a.world.nests:
		check(a.world.reachable(poi.pos), "POI reachable")
	check(a.world.reachable(a.world.boss_pos), "boss reachable")
	var before = a.player
	a.step(0.1,Vector2.RIGHT)
	check(a.player.x > before.x, "movement")
	a.paused = true
	var time = a.elapsed
	a.step(1.0,Vector2.RIGHT)
	check(a.elapsed == time, "pause freezes time")
	var snap = a.snapshot()
	var restored = Sim.new()
	check(restored.restore(snap), "restore accepted")
	check(restored.player.is_equal_approx(a.player), "position roundtrip")
	check(restored.world.cells == a.world.cells, "terrain roundtrip")
	check(restored.build.to_dict() == a.build.to_dict(), "build roundtrip")
	var combat = Sim.new()
	combat.new_run(4)
	combat.spawn_enemy(combat.player + Vector2(35,0), "prey")
	for i in range(30): combat.step(0.05,Vector2.ZERO)
	check(combat.xp > 0 or combat.pending_levels > 0, "prey absorbed yields DNA")
	combat.build.apply("acid")
	combat.spawn_enemy(combat.player + Vector2(100,0), "hunter")
	var enemy = combat.enemies.back()
	combat.cooldowns["tentacle"] = 0.0
	combat.step(0.05,Vector2.ZERO)
	check(enemy.slow > 0, "acid grasp mechanically slows")
	combat.build.apply("spikes")
	combat.build.apply("pulse")
	combat.cooldowns.pulse = 0.0
	combat.step(0.05,Vector2.ZERO)
	check(combat.shots.size() >= 8, "spike pulse fires eight shots")
	combat.build.unlocked.append("division")
	combat.build.apply("division")
	combat.build.apply("trail")
	combat.cooldowns.trail = 0.0
	combat.step(0.05,Vector2.ZERO)
	check(combat.fields.size() >= 3, "copies leave toxic fields")
	var s = Sim.new()
	s.new_run(55)
	s.build.apply("infection")
	s.build.apply("devour")
	s.spawn_enemy(s.player+Vector2(25,0),"hunter")
	s.enemies[0].hp = 0.0
	s.enemies[0].infect = 3.0
	s.step(0.01,Vector2.ZERO)
	for i in range(140): s._update_remains(0.05)
	check(s.fields.size()>0, "infected meal makes spores")
	var full = Sim.new()
	full.new_run(8)
	full.pickups.clear()
	for i in range(600): full.pickups.append({"pos":full.player,"type":"dna","amount":1,"id":i})
	full._drop(full.player,"core",2)
	var core_total = 0
	var dna_total = 0
	for item in full.pickups:
		if item.type=="core": core_total+=item.amount
		if item.type=="dna": dna_total+=item.amount
	check(core_total==2 and dna_total==600 and full.pickups.size()<=600,"pickup cap preserves rare and common resources")
	var tracking = Sim.new()
	tracking.new_run(12)
	tracking.enemies.clear()
	tracking.boss_spawned = true
	tracking.spawn_enemy(tracking.player+Vector2(200,0),"boss")
	tracking.step(0.1,Vector2.ZERO)
	check(tracking.boss_marker.is_equal_approx(tracking.enemies[0].pos),"map tracks live boss")
	var tracking_copy = Sim.new()
	tracking_copy.restore(tracking.snapshot())
	check(tracking_copy.boss_marker.is_equal_approx(tracking.enemies[0].pos),"restored boss marker follows enemy")
	for seed_value in range(20):
		var sim = Sim.new()
		sim.new_run(seed_value)
		check(sim.world.reachable(sim.world.boss_pos), "seed boss path")
		for shop in sim.world.colonies: check(sim.world.reachable(shop.pos),"seed shop path")
	var soak = Sim.new()
	soak.new_run(44)
	soak.max_hp = 100000
	soak.hp = 100000
	for i in range(1200): soak.step(0.5,Vector2.ZERO)
	check(soak.enemies.size() <= Sim.ENEMY_CAP and soak.fields.size() <= 80 and soak.shots.size() <= 200, "late wave caps")
	check(soak.boss_spawned, "boss appears after ten minutes")
	soak.enemies.clear()
	soak.spawn_enemy(soak.player+Vector2(120,0),"boss")
	soak.enemies[0].hp = 0
	soak.step(0.01,Vector2.ZERO)
	check(soak.outcome == "victory", "boss death wins")
	var terminal = Sim.new()
	check(terminal.restore(soak.snapshot()) and terminal.outcome=="victory", "terminal outcome survives checkpoint")
	var reward_count = 0
	for event in soak.events:
		if event.type == "core" and event.token.ends_with(":boss"): reward_count += 1
	soak.step(0.01,Vector2.ZERO)
	check(reward_count == 1, "one boss reward event")
	print("SIMULATION: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
