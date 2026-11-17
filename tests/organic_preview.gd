extends RefCounted
const Genome=preload("res://core/genome.gd")
var elapsed=0.0
var phase=-1

func setup(sim):
	sim.enemies.clear()
	sim.remains.clear()
	sim.pickups.clear()
	sim.world.nests.clear()
	sim.spawn_timer=10000
	sim.build.organs={"tentacle":1}
	sim.build.unlocked.append("division")
	sim.spawn_enemy(sim.player+Vector2(35,0),"hunter")
	var enemy=sim.enemies.back()
	enemy.genome.palette=3
	sim._die(sim.enemies.size()-1,false)
	for i in range(sim.remains.size()):
		var part=sim.remains[i]
		part.pos=sim.player+Vector2.from_angle(i*2.2)*36
		part.vel=Vector2.ZERO
		part.duration=2.0
	sim.effects.clear()

func step(sim,dt: float):
	elapsed+=dt
	if elapsed<6.2:
		# Real digestion, isolated from combat so the membrane is visible.
		sim._update_remains(dt)
		for i in range(sim.effects.size()-1,-1,-1):
			sim.effects[i].life-=dt
			if sim.effects[i].life<=0:sim.effects.remove_at(i)
	else:
		if phase==-1:
			sim.build.organs={"tentacle":1,"acid":1,"infection":1,"devour":1,"spikes":1,"pulse":1}
			sim.spawn_enemy(sim.player+Vector2(130,-25),"hunter")
			sim.enemies.back().max_hp=1500
			sim.enemies.back().hp=1500
			phase=0
		if elapsed>8.6 and phase==0:
			sim.build.organs={"division":2,"trail":2,"infection":1,"devour":1}
			sim.cooldowns.clear()
			phase=1
		if elapsed>10.0 and phase==1:
			sim.enemies.back().infect=3.0
			sim._die(sim.enemies.size()-1,true)
			phase=2
		sim.step(dt,Vector2.RIGHT*0.2 if elapsed>10.8 else Vector2.ZERO)
