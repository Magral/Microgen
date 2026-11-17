extends SceneTree
const Sim = preload("res://game/simulation.gd")
var checks = 0
var failures = 0
func check(ok: bool, message: String):
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func clean(seed_value: int = 77):
	var s = Sim.new()
	s.new_run(seed_value)
	s.pickups.clear()
	s.world.nests.clear()
	s.build.organs.clear()
	s.spawn_timer = 10000
	return s
func advance(s, seconds: float):
	for i in range(int(ceil(seconds / 0.05))): s.step(0.05, Vector2.ZERO)
func _initialize():
	var s = clean()
	s.spawn_enemy(s.player + Vector2(140,0), "hunter")
	s.enemies[0].hp = 0
	s.step(0.05, Vector2.ZERO)
	check(s.pickups.is_empty(), "dead enemies leave body parts instead of instant resource pickups")
	check(s.get("remains") is Array, "simulation exposes persistent remains")
	if not s.get("remains") is Array:
		print("HARVEST: %d assertions, %d failures" % [checks, failures])
		quit(1)
		return
	check(s.remains.size() == 3 and s.xp == 0 and s.build.biomass == 0, "death creates three unrewarded fragments")
	var dna = 0
	var bio = 0
	for part in s.remains:
		dna += part.dna
		bio += part.bio
	check(dna == 9 and bio == 4, "normal body contains nine DNA and four biomass")
	var part = s.remains[0]
	s.player = part.pos
	s.step(0.3, Vector2.ZERO)
	check(part.progress > 0 and part.progress < 1 and s.xp == 0, "contact begins digestion without paying early")
	var saved_progress = part.progress
	s.player_velocity = Vector2(12.0,-7.0)
	var target = s.digesting_id
	var restored = Sim.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot()))), "harvest snapshot restores")
	check(restored.digesting_id == target and is_equal_approx(restored.remains[0].progress, saved_progress), "target and partial meal survive JSON save")
	check(restored.player_velocity.is_equal_approx(s.player_velocity) and restored.remains[0].vel.is_equal_approx(s.remains[0].vel), "player and fragment velocities survive JSON save")
	s.player_velocity = Vector2.ZERO
	s.paused = true
	s.step(0.5,Vector2.ZERO)
	check(part.progress == saved_progress, "pause freezes digestion")
	s.paused = false
	s.player += Vector2(300,0)
	s.step(0.2, Vector2.ZERO)
	check(part.progress > 0 and part.progress <= saved_progress, "interrupted digestion decays slowly")
	s.player = part.pos
	advance(s, 2.2)
	check(s.remains.size() < 3 and s.xp > 0, "sustained contact completes harvest")
	var prey = clean()
	prey.spawn_enemy(prey.player, "prey")
	prey.step(0.1, Vector2.ZERO)
	check(prey.enemies.size() == 1 and prey.enemies[0].get("engulf",0) > 0 and prey.xp == 0, "living prey absorbs progressively")
	var prey_copy = Sim.new()
	check(prey_copy.restore(prey.snapshot()) and is_equal_approx(prey_copy.enemies[0].engulf,prey.enemies[0].engulf), "living engulf progress persists")
	advance(prey, 1.5)
	check(prey.enemies.is_empty() and prey.xp == 4 and prey.build.biomass == 1, "living prey pays once after absorption")
	var weak = clean()
	weak.build.unlocked.append("devour")
	weak.build.apply("devour")
	weak.spawn_enemy(weak.player, "hunter")
	weak.enemies[0].hp = 3
	var health = weak.hp
	weak.step(0.2, Vector2.ZERO)
	check(weak.hp == health and weak.enemies[0].get("engulf",0) > 0, "engulfing weak enemy cannot deal contact damage")
	weak.player += Vector2(100,0)
	weak.build.apply("tentacle")
	var weak_health = weak.enemies[0].hp
	weak._attack()
	check(weak.enemies[0].hp < weak_health, "interrupted engulf target remains vulnerable to attacks")
	var recovered = clean()
	recovered.build.apply("devour")
	recovered.spawn_enemy(recovered.player,"hunter")
	var regenerator = recovered.enemies[0]
	regenerator.max_hp = 100.0
	regenerator.hp = 17.9
	regenerator.traits = ["regen"]
	regenerator.speed = 0.0
	var player_health = recovered.hp
	for i in range(20): recovered._update_enemies(0.05)
	check(regenerator.hp > 19.0 and regenerator.engulf > 0.0, "regeneration interrupts engulf while visual progress retracts")
	check(recovered.hp < player_health, "regenerated enemy resumes contact damage")
	check(recovered._nearest(100).get("id",-1) == regenerator.id, "regenerated enemy becomes targetable despite residual engulf")
	recovered.build.apply("tentacle")
	var recovered_health = regenerator.hp
	recovered._attack()
	check(regenerator.hp < recovered_health, "regenerated enemy receives attacks during engulf retraction")
	var distant = clean()
	distant.spawn_enemy(distant.player+Vector2(1700,0),"hunter")
	distant.enemies[0].hp = 0.1
	distant.enemies[0].infect = 2.0
	distant._update_enemies(0.1)
	check(distant.remains.size() == 3, "distant infection death leaves a body before population cleanup")
	var capped = clean()
	for i in range(40):
		capped.spawn_enemy(capped.player + Vector2(200,0), "hunter")
		capped._die(0, false)
	dna = 0
	bio = 0
	for fragment in capped.remains:
		dna += fragment.dna
		bio += fragment.bio
	check(capped.remains.size() <= 96 and dna == 360 and bio == 160, "fragment cap conserves all material")
	var feast = clean()
	feast.build.apply("infection")
	feast.build.apply("devour")
	feast.spawn_enemy(feast.player,"prey")
	feast.enemies[0].hp = 0
	feast.enemies[0].infect = 2.0
	feast.enemies[0].traits = ["spores"]
	feast.step(0.05,Vector2.ZERO)
	check(feast.fields.filter(func(f): return f.kind == "enemy_spore").size() == 1, "infected corpse preserves hostile death spores exactly once")
	for fragment in feast.remains: fragment.pos = feast.player
	for i in range(150): feast._update_remains(0.05)
	check(feast.fields.filter(func(f): return f.kind == "spore").size() == 1, "infected corpse feast triggers once across its fragments")
	var reward_xp = feast.xp
	feast._update_remains(0.5)
	check(feast.xp == reward_xp and feast.build.biomass == 1, "finished fragments cannot pay or feast twice")
	var movement = clean()
	var start = movement.player
	movement.step(0.1,Vector2.RIGHT)
	check(movement.player.x - start.x < 14.5 and movement.player_velocity.x > 0, "viscous movement accelerates gradually")
	var velocity = movement.player_velocity.x
	movement.step(0.1,Vector2.ZERO)
	check(movement.player_velocity.x > 0 and movement.player_velocity.x < velocity, "viscous movement coasts and decays")
	var waves = clean()
	waves.elapsed = 300
	waves._spawn_wave()
	check(waves.enemies.size() <= 2, "waves contain at most two enemies")
	waves.enemies.clear()
	for i in range(60): waves.spawn_enemy(waves.player + Vector2(200,0), "hunter")
	check(waves.enemies.size() == 28 and waves.enemies[0].max_hp >= 91, "enemy population capped at twenty eight tougher organisms")
	var carried = clean()
	carried.spawn_enemy(carried.player,"hunter")
	carried._die(0,false)
	carried.remains.resize(1)
	var tissue = carried.remains[0]
	tissue.pos=carried.player+Vector2(30,0)
	tissue.vel=Vector2.ZERO
	tissue.duration=2.0
	carried._update_remains(0.9)
	check(tissue.get("internal",false),"crossed tissue is captured inside organism")
	var carried_id=tissue.id
	carried.player+=Vector2(200,0)
	carried._update_remains(0.1)
	check(carried.digesting_id==carried_id and tissue.pos.distance_to(carried.player)<40,"internal digestion follows moving organism")
	var carried_restore=Sim.new()
	carried_restore.restore(JSON.parse_string(JSON.stringify(carried.snapshot())))
	check(carried_restore.remains[0].get("internal",false),"internal tissue persists in checkpoint")
	var centered=clean()
	centered.spawn_enemy(centered.player,"hunter")
	centered._die(0,false)
	centered.remains.resize(1)
	centered.remains[0].pos=centered.player
	centered.remains[0].vel=Vector2.ZERO
	centered.remains[0].duration=2.0
	centered._update_remains(0.9)
	check(centered.remains[0].get("entry_distance",-1)==0.0,"central tissue preserves true entry distance without outward jump")
	var old = s.snapshot()
	old.erase("remains")
	old.erase("digesting_id")
	old.erase("player_velocity")
	check(restored.restore(old) and restored.remains.is_empty() and restored.player_velocity == Vector2.ZERO, "old saves default to no fragments and zero velocity")
	print("HARVEST: %d assertions, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
