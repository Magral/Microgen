extends SceneTree
const Sim=preload("res://game/simulation.gd")
const Catalog=preload("res://core/catalog.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	# Real checkpoint JSON must restore attack impulses, not just typed dictionaries.
	var s=Sim.new()
	s.new_run(44)
	s.enemies.clear()
	s.spawn_enemy(s.player+Vector2(60,0),"hunter")
	s.enemies[0].impulse=Vector2(12,-4)
	var restored=Sim.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot()))),"checkpoint restores")
	check(restored.enemies[0].impulse is Vector2,"checkpoint pulse impulse is a vector")
	restored.step(0.016,Vector2.ZERO)
	# Rank cap increases must not increase multiplicative actor/shot work without bounds.
	s.build.organs={"division":10}
	check(s.clone_positions().size()==5,"rank10 colony stays at five clones")
	for rank in [1,3,6,10]:
		s.level=rank;s.xp=rank*0.1
		check(is_equal_approx(s.body_radius(),Sim.Growth.radius(s.level,s.xp/s.xp_needed())),"cached radius follows changing growth")
	check(Catalog.adaptation_bonus(4)<Catalog.adaptation_bonus(5) and Catalog.adaptation_bonus(5)<Catalog.adaptation_bonus(6),"final armor and speed ranks both improve their bonus")
	check(is_equal_approx(Catalog.adaptation_bonus(3),0.36) and is_equal_approx(Catalog.adaptation_bonus(6),0.6),"old adaptation ranks preserved and final rank capped")
	# Every available combination has a real, separate visual trigger.
	for id in Catalog.SYNERGIES:
		var pair=Catalog.SYNERGIES[id].needs
		var scene=Sim.new()
		scene.new_run(32)
		scene.enemies.clear()
		scene.build.organs={pair[0]:3,pair[1]:3}
		scene.build.adaptations.clear()
		for key in pair:
			if key in Catalog.ADAPTATIONS:
				scene.build.organs.erase(key);scene.build.adaptations[key]=3
		scene.facing=0.0
		scene.spawn_enemy(scene.player+Vector2(20,0),"hunter")
		scene.enemies[0].r=40.0
		if id=="spore_feast":
			scene.enemies[0].infect=2;scene._die(0,true)
		elif id=="metabolic_colony":
			scene.hp=scene.max_hp-10;scene._attack()
		else:scene._attack()
		check(scene.effects.any(func(effect):return effect.type==id),"synergy visual triggers: "+id)
	print("SUSTAINED PLAY: %d failures"%failures)
	quit(0 if failures==0 else 1)
