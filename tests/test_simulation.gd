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
	combat.spawn_enemy(combat.player + Vector2(20,0), "prey")
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
	check(not soak.boss_spawned, "boss waits for stage objectives instead of timer")
	soak.enemies.clear()
	soak.minibosses_defeated=soak.stage_miniboss_target()
	soak.step(0.01,Vector2.ZERO)
	check(soak.boss_spawned, "boss unlocks after the miniboss objective")
	soak.enemies.clear()
	soak.shots.clear()
	soak.spawn_enemy(soak.player+Vector2(120,0),"boss")
	var boss = soak.enemies[0]
	boss.shot_cd = 0.0
	soak._update_boss_attack(boss, 0.01)
	check(boss.get("boss_windup", 0.0) > 0.0 and soak.shots.is_empty(), "boss locks its direction before firing")
	var charging = Sim.new()
	check(charging.restore(soak.snapshot()), "checkpoint accepts boss windup")
	var resumed_boss = charging.enemies[0]
	charging._update_boss_attack(resumed_boss, 1.2)
	check(charging.shots.size() == int(charging.boss_attack().count) and resumed_boss.get("boss_exposed", 0.0) > 0.0, "resumed windup fires one procedural attack and exposes the core")
	resumed_boss.tissue_budget = 100.0
	var exposed_hit = charging.hit_enemy(resumed_boss, 10.0)
	resumed_boss.boss_exposed = 0.0
	check(exposed_hit > charging.hit_enemy(resumed_boss, 10.0), "exposed core increases damage below the tissue ceiling")
	soak.enemies[0].hp = 0
	soak.step(0.01,Vector2.ZERO)
	check(soak.stage_transition and soak.outcome=="", "boss death continues the run at the next stage")
	var terminal = Sim.new()
	check(terminal.restore(soak.snapshot()) and terminal.stage_transition and terminal.stage_index==1, "stage transition survives checkpoint")
	check(terminal.boss_reward.get("organ", "") == terminal.boss_attack().organ and not terminal.boss_reward.get("claimed", true), "boss organ persists until the player claims it")
	var reward_count = 0
	for event in soak.events:
		if event.type == "core" and event.token.begins_with(soak.run_id+":boss:"): reward_count += 1
	soak.step(0.01,Vector2.ZERO)
	check(reward_count == 1 and soak.events.any(func(event):return event.type=="stage_clear"), "one stage boss reward and clear event")
	print("SIMULATION: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
