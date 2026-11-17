extends SceneTree
const Sim=preload("res://game/simulation.gd")
var failures=0
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func clean():
	var s=Sim.new()
	s.new_run(77)
	s.enemies.clear()
	s.pickups.clear()
	s.world.nests.clear()
	s.spawn_timer=10000
	return s
func _initialize():call_deferred("run")
func run():
	var s=clean()
	check(s.has_method("body_radius"),"organism has persistent physical growth model")
	if not s.has_method("body_radius"):
		quit(1)
		return
	var small=s.body_radius()
	s.spawn_enemy(s.player,"hunter")
	s.enemies[0].r=65.0
	var fixed_radius=s.enemies[0].r
	check(not s._is_engulfing(s.enemies[0]),"large organism is not early food")
	s.level=20
	check(s.body_radius()>small*3 and s.enemies[0].r==fixed_radius,"player grows while same enemy retains actual size")
	check(s._is_engulfing(s.enemies[0]),"formerly huge organism becomes food after growth")
	check(s.residents.size()>=3,"persistent giant silhouettes exist from first frame")
	var a=clean()
	var b=clean()
	check(a.residents==b.residents,"same seed produces stable giant ecology")
	s=clean()
	s.spawn_enemy(s.player,"hunter")
	s._die(0,false)
	for part in s.remains:
		part.pos=s.player
		part.vel=Vector2.ZERO
	s._update_remains(0.01)
	check(s.remains.all(func(part):return part.get("captured",false)),"every overlapping fragment captured immediately")
	var count=s.remains.size()
	check(count==3 and s.xp==0,"capture preserves visible animation before reward")
	s.player+=Vector2(200,0)
	for i in range(20): s._update_remains(0.05)
	check(s.remains.is_empty() and s.xp==9 and s.build.biomass==4,"all captured pieces digest quickly during movement exactly once")
	var food=clean()
	food._drop(food.player,"dna",3)
	food._collect(0.01)
	check(food.pickups.size()==1 and food.pickups[0].get("captured",false) and food.xp==0,"DNA also enters living digestion animation")
	food.player+=Vector2(100,0)
	food._collect(0.8)
	check(food.pickups.is_empty() and food.xp==3,"captured DNA finishes on the move")
	var remote=clean()
	remote._drop(remote.player+Vector2(75,0),"dna",3)
	var start=remote.pickups[0].pos
	remote._collect(0.1)
	check(remote.pickups[0].pos==start,"no remote attraction at start")
	remote.build.apply("magnet")
	remote._collect(0.1)
	check(remote.pickups[0].pos.distance_to(remote.player)<75,"receptors unlock longer attraction")
	var sweep=clean()
	sweep._drop(sweep.player+Vector2(45,0),"dna",3)
	sweep.player_velocity=Vector2(145,0)
	sweep.step(0.5,Vector2.RIGHT)
	check(sweep.pickups.is_empty() or sweep.pickups[0].get("captured",false),"fast crossing cannot miss touching food")
	var heal=clean()
	heal._drop(heal.player,"heal",7)
	heal._collect(0.1)
	check(heal.pickups.size()==1 and not heal.pickups[0].get("captured",false),"healing tissue retained when already healthy")
	heal.hp=40
	heal._collect(0.01)
	heal._collect(0.8)
	check(heal.hp==47 and heal.pickups.is_empty(),"bright healing food restores small exact amount after animation")
	var spare=clean()
	spare.hp=95
	spare._drop(spare.player,"heal",6)
	spare._collect(0.01)
	spare.hp=spare.max_hp
	spare._collect(0.8)
	check(spare.pickups.size()==1 and not spare.pickups[0].get("captured",false),"unneeded healing is released instead of wasted after regeneration")
	var legacy=clean()
	legacy.spawn_enemy(legacy.player,"hunter")
	legacy._die(0,false)
	legacy.remains.resize(1)
	legacy.remains[0].internal=true
	legacy.remains[0].progress=0.2
	legacy.remains[0].duration=2.0
	legacy._update_remains(0.01)
	check(legacy.remains[0].duration<=0.65,"old internally captured tissue adopts quick digestion")
	var carried=clean()
	carried._drop(carried.player,"dna",3)
	carried._collect(0.05)
	var restored=Sim.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(carried.snapshot()))),"growth capture checkpoint restores")
	check(restored.pickups[0].get("captured",false) and restored.residents.size()==carried.residents.size() and restored.residents[0].pos.is_equal_approx(carried.residents[0].pos) and restored.residents[0].id==carried.residents[0].id,"capture and persistent ecosystem survive save")
	print("GROWTH CONTACT: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
