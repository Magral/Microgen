extends RefCounted
var elapsed=0.0
var phase=0
func setup(sim):
	sim.enemies.clear()
	sim.remains.clear()
	sim.pickups.clear()
	sim.world.nests.clear()
	sim.spawn_timer=10000
	sim.build.organs={"tentacle":1}
	sim.spawn_enemy(sim.player+Vector2(25,0),"hunter")
	sim.enemies.back().genome.palette=3
	sim._die(sim.enemies.size()-1,false)
	for part in sim.remains:
		part.pos=sim.player+Vector2.from_angle(float(part.part)*2.1)*20
		part.vel=Vector2.ZERO
	sim._drop(sim.player+Vector2(-50,0),"heal",6)
	sim.effects.clear()
func step(sim,dt: float):
	elapsed+=dt
	var direction=Vector2.ZERO
	if elapsed>=2.0 and elapsed<5.0:sim.gain_xp(dt*450.0)
	if elapsed>=5.0 and elapsed<8.7:direction=Vector2.RIGHT*0.35
	if elapsed>=9.0 and phase==0:
		sim.hp=18
		phase=1
	if elapsed>=10.8 and phase==1:
		sim._drop(sim.player,"heal",8)
		phase=2
	sim.step(dt,direction)
