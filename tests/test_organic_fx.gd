extends SceneTree
const Sim=preload("res://game/simulation.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:
		failures+=1
		push_error(message)
func has_effect(s,type):
	return s.effects.any(func(effect): return effect.type==type)
func _initialize(): call_deferred("run")
func run():
	for pair in [["tentacle","acid","acid_grasp"],["spikes","pulse","spike_pulse"],["division","trail","toxic_colony"],["infection","devour","spore_feast"]]:
		var s=Sim.new()
		s.new_run(32)
		s.enemies.clear()
		s.build.organs.clear()
		s.build.unlocked.append("division")
		s.build.apply(pair[0])
		s.build.apply(pair[1])
		s.spawn_enemy(s.player+Vector2(65,0),"hunter")
		if pair[2]=="spore_feast":
			s.enemies[0].infect=2.0
			s._die(0,true)
		else: s._attack()
		check(has_effect(s,pair[2]),"real synergy emits specific visual: "+pair[2])
	var s=Sim.new()
	s.new_run(32)
	s.enemies.clear()
	s.spawn_enemy(s.player+Vector2(100,0),"hunter")
	s.build.organs={"infection":1}
	s._attack()
	check(has_effect(s,"infection"),"infection launch emits organism-to-target effect")
	if s.has_method("_effect"):
		for i in range(400): s._effect({"type":"infection","pos":s.player,"end":s.player,"r":20.0,"life":0.5,"max":0.5})
		check(s.effects.size()<=160,"visual events remain bounded")
	else: check(false,"bounded effect event emitter exists")
	s.paused=true
	var before=s.effects.duplicate(true)
	s.step(1.0,Vector2.ZERO)
	check(s.effects==before,"paused combat freezes transient effects")
	print("ORGANIC FX: %d failures" % failures)
	quit(0 if failures==0 else 1)
