extends SceneTree
const Sim=preload("res://game/simulation.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:
		failures+=1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	check(ResourceLoader.exists("res://core/pigment.gd"),"persistent tissue pigment model exists")
	if ResourceLoader.exists("res://core/pigment.gd"):
		var pigment=load("res://core/pigment.gd")
		var state=pigment.create(Color(1,0.9,0.05))
		var before=pigment.color(state)
		pigment.feed(state,Color(0.04,0.2,1),0.5)
		var first=pigment.color(state)
		check(first.r>0.8,"one small fragment changes color gradually")
		for i in range(35): pigment.feed(state,Color(0.04,0.2,1),0.5)
		var mixed=pigment.color(state)
		check(mixed.g>mixed.r and mixed.g>mixed.b,"yellow and blue pigment form green rather than gray")
		check(Vector3(mixed.r,mixed.g,mixed.b).distance_to(Vector3(before.r,before.g,before.b))>Vector3(first.r,first.g,first.b).distance_to(Vector3(before.r,before.g,before.b)),"repeated tissue has cumulative color influence")
		for i in range(200): pigment.feed(state,Color(0.3,0.1,0.8),3.0)
		check(state.mass<=80.0 and pigment.color(state).r>0,"pigment accumulation bounded and finite")
	var s=Sim.new()
	s.new_run(55)
	check(s.has_method("body_color"),"organism exposes mixed tissue color")
	if s.has_method("body_color"):
		s.enemies.clear()
		s.spawn_enemy(s.player,"hunter")
		s._die(0,false)
		for fragment in s.remains:
			fragment.pos=s.player
			fragment.duration=0.1
		for i in range(4):s._update_remains(0.1)
		var restored=Sim.new()
		restored.restore(JSON.parse_string(JSON.stringify(s.snapshot())))
		check(s.body_color().is_equal_approx(restored.body_color()),"pigment mix survives real JSON checkpoint")
	var capped=Sim.new()
	capped.new_run(29)
	capped.enemies.clear()
	for i in range(33):
		capped.spawn_enemy(capped.player,"hunter")
		capped.enemies[0].genome.palette=4 if i==32 else 3
		capped._die(0,false)
	var merged=capped.remains.back()
	check(merged.get("pigment",{}).get("mass",0)>merged.r*0.12*2,"cap merge conserves incoming pigment mass")
	check(merged.get("pigment",{}).get("density",[]).size()==3,"cap merge retains mixed pigment density")
	print("PIGMENT: %d failures" % failures)
	quit(0 if failures==0 else 1)
