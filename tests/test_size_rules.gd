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
	s.new_run(51)
	s.enemies.clear()
	s.pickups.clear()
	s.build.organs={"tentacle":1,"acid":1}
	s.spawn_timer=10000
	return s
func _initialize():call_deferred("run")
func run():
	check(ResourceLoader.exists("res://core/size_rules.gd"),"size-ratio interaction model exists")
	if ResourceLoader.exists("res://core/size_rules.gd"):
		var rules=load("res://core/size_rules.gd")
		var tiny=rules.profile(40,18,1.0,2,1,false)
		var small=rules.profile(40,32,0.7,2,1,false)
		var peer=rules.profile(40,40,0.7,2,1,false)
		var large=rules.profile(40,70,1.0,3,3,false)
		check(tiny.threshold>small.threshold and small.threshold>peer.threshold,"smaller enemy yields at higher HP")
		check(tiny.pull>small.pull and small.pull>peer.pull,"pull falls with enemy relative size")
		check(tiny.impact==0 and small.impact==0 and peer.impact==0,"smaller and equal collisions are harmless")
		var slightly=rules.profile(40,44,1.0,3,1,false)
		check(slightly.impact>0 and slightly.impact<large.impact*0.4,"slightly larger foe deals only small impact")
		check(large.pull==0 and large.speed<peer.speed,"healthy giant resists pull and swims slower")
		check(rules.profile(40,40,0.8,1,1,false).pull==0,"weak pull skill cannot reel in a peer")
		var previous=1.0
		for i in range(100):
			var ratio=0.65+i*0.01
			var current=rules.profile(40,40*ratio,0.5,2,3,false).threshold
			check(current<=previous+0.00001,"capture threshold never rises with larger enemy")
			previous=current
		var mouth=rules.profile(40,40,0.5,2,2,true)
		check(mouth.threshold>peer.threshold and mouth.duration<peer.duration,"frontal mouth improves capture and digestion")
		check(rules.profile(40,52,0.05,3,2,false).pull>0,"severely damaged borderline larger foe can yield gradually")
	var s=clean()
	s.spawn_enemy(s.player+Vector2(95,0),"hunter")
	s.enemies[0].r=12
	var source=s.enemies[0].pos
	s._attack()
	check(s.enemies[0].pos==source,"acid grasp hit never teleports target")
	check(s.has_method("mouth_contact"),"directional mouth contact model exists")
	if s.has_method("mouth_contact"):
		s.facing=0.0
		s.build.organs={"devour":1}
		var target=s.enemies[0]
		target.r=s.body_radius()
		target.max_hp=100
		target.hp=50
		target.pos=s.player+Vector2(20,0)
		check(s.mouth_contact(target) and s._is_engulfing(target),"front mouth captures damaged peer earlier")
		target.pos=s.player+Vector2(0,20)
		check(not s.mouth_contact(target) and not s._is_engulfing(target),"side membrane has stricter peer HP threshold")
		target.pos=s.player+Vector2(20,0)
		target.hp=100
		# Isolate bite mechanics from the independent per-frame tissue budget.
		target.tissue_budget=100.0
		var before=target.hp
		s._attack()
		check(target.hp<before and s.bite_flash>0,"mouth actually damages frontal tissue")
		var restored=Sim.new()
		restored.restore(JSON.parse_string(JSON.stringify(s.snapshot())))
		check(is_equal_approx(restored.facing,s.facing),"mouth direction survives save")
	var drag=clean()
	drag.build.organs.clear()
	drag.build.adaptations={"magnet":3}
	drag.spawn_enemy(drag.player+Vector2(95,0),"hunter")
	var pulled=drag.enemies[0]
	pulled.r=12.0
	pulled.speed=0.0
	pulled.hp=pulled.max_hp
	var original=pulled.pos
	drag._update_enemies(0.016)
	check(pulled.pos.distance_to(original)>0 and pulled.pos.distance_to(original)<2,"small prey accelerates continuously without pull jump")
	pulled.r=60.0
	pulled.pos=drag.player+Vector2(110,0)
	pulled.vel=Vector2.ZERO
	original=pulled.pos
	drag._update_enemies(0.016)
	check(pulled.pos.is_equal_approx(original),"healthy giant remains unmoved by strongest receptors")
	var impact=clean()
	impact.build.organs.clear()
	impact.spawn_enemy(impact.player,"hunter")
	var other=impact.enemies[0]
	other.r=impact.body_radius()
	other.hp=other.max_hp
	impact._update_enemies(0.01)
	check(impact.hp==impact.max_hp,"equal-size actual collision does not harm player")
	other.r=impact.body_radius()*1.1
	other.pos=impact.player
	impact._update_enemies(0.01)
	check(impact.hp<impact.max_hp and impact.hp>impact.max_hp-3,"slightly larger actual collision is only a graze")
	var blocked=clean()
	blocked.facing=0.0
	for i in range(blocked.world.cells.size()):blocked.world.cells[i]=1
	blocked.step(0.1,Vector2.UP)
	check(is_equal_approx(blocked.facing,0.0),"blocked movement cannot rotate bite cone away from visible body")
	print("SIZE RULES: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
