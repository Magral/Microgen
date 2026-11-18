extends SceneTree
const Sim=preload("res://game/simulation.gd")
var fails=0
func check(ok: bool,label: String):
	if not ok:fails+=1;push_error(label)
func battle_time(kind: String,ratio: float) -> float:
	var sim=Sim.new()
	sim.new_run(51)
	sim.enemies.clear()
	sim.build.organs={"devour":5}
	sim.facing=0.0
	sim.spawn_enemy(sim.player+Vector2(25,0),kind)
	var target=sim.enemies[0]
	target.r=sim.body_radius()*ratio
	target.max_hp=200.0
	target.hp=200.0
	target.speed=0.0
	target.traits=[]
	var seconds=0.0
	while not sim.enemies.is_empty() and seconds<35:
		sim.elapsed+=0.05
		sim._update_enemies(0.05)
		if not sim.enemies.is_empty():sim.hit_enemy(sim.enemies[0],100000.0)
		seconds+=0.05
	return seconds
func _initialize():call_deferred("run")
func run():
	var s=Sim.new()
	s.new_run(51)
	s.enemies.clear()
	s.pickups.clear()
	check(s.has_method("hit_enemy"),"all damage uses tissue resistance and feedback")
	if not s.has_method("hit_enemy"):
		quit(1)
		return
	s.spawn_enemy(s.player+Vector2(25,0),"hunter")
	var e=s.enemies[0]
	e.r=s.body_radius()
	e.hp=200
	e.max_hp=200
	e.speed=0
	e.traits=[]
	s.build.organs={"devour":5}
	s.facing=0
	var seconds=0.0
	while not s.enemies.is_empty() and seconds<35:
		s.elapsed+=0.05
		s._update_enemies(0.05)
		if not s.enemies.is_empty():s.hit_enemy(s.enemies[0],100000.0)
		seconds+=0.05
	check(seconds>=5 and seconds<=30,"even enormous frontal burst allows a5–30second peer fight")
	var giant_seconds=battle_time("hunter",2.0)
	var elite_seconds=battle_time("miniboss",1.2)
	check(giant_seconds>=15 and giant_seconds<=30,"large tissue withstands15–30seconds of maximum stacked damage")
	check(elite_seconds>=20 and elite_seconds<=30,"miniboss sustains20–30seconds against maximum stacked damage")
	print("PACING measured seconds: peer=%.2f giant=%.2f miniboss=%.2f" % [seconds,giant_seconds,elite_seconds])
	check(s.effects.any(func(f):return f.type=="damage"),"outgoing damage generates numbers")
	s.hurt_player(5)
	check(s.effects.any(func(f):return f.type=="damage" and f.get("player",false)),"incoming damage generates red numbers")
	check(s.feedback.any(func(f):return f.kind=="hurt"),"real damage feeds sound")
	var elite=Sim.new()
	elite.new_run(99)
	elite.enemies.clear()
	for nest_index in range(mini(2,elite.world.nests.size())):elite.world.nests[nest_index].used=true
	elite.step(0.01,Vector2.ZERO)
	var minibosses=elite.enemies.filter(func(enemy):return enemy.kind=="miniboss")
	check(not minibosses.is_empty(),"explored nests spawn a miniboss")
	if not minibosses.is_empty():
		var elite_id=minibosses[0].id
		elite.enemies.filter(func(enemy):return enemy.id==elite_id)[0].pos=elite.player+Vector2(1700,0)
		elite._update_enemies(0.01)
		check(elite.enemies.any(func(enemy):return enemy.id==elite_id),"unique miniboss cannot disappear when avoided")
		var restored=Sim.new()
		restored.restore(JSON.parse_string(JSON.stringify(elite.snapshot())))
		check(restored.minibosses_spawned==elite.minibosses_spawned,"miniboss progress persists")
	print("COMBAT PACING: %d failures" % fails)
	quit(0 if fails==0 else 1)
