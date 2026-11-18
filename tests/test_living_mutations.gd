extends SceneTree
const Sim=preload("res://game/simulation.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func fresh():
	var s=Sim.new();s.new_run(44);s.enemies.clear();s.effects.clear();s.pickups.clear();return s
func run():
	var s=fresh();s.hp=90;s.heal_player(50)
	var heals=s.effects.filter(func(e):return e.type=="heal")
	check(heals.size()==1,"actual healing creates a green-number effect")
	if not heals.is_empty():check(is_equal_approx(heals[0].amount,10.0),"overheal is excluded from displayed healing")
	s.heal_player(10)
	check(s.effects.filter(func(e):return e.type=="heal").size()==1,"full HP creates no additional heal text")
	var regen=fresh();regen.hp=50
	for i in range(60):regen.heal_player(0.01)
	check(regen.effects.filter(func(e):return e.type=="heal").size()<=1,"continuous healing batches into one popup")
	for rank in [1,3,6,10]:
		var combat=fresh();combat.build.organs={"tentacle":rank};combat.cooldowns={}
		for i in range(3):
			combat.spawn_enemy(combat.player+Vector2(80,i*12),"hunter")
			var foe=combat.enemies.back();foe.hp=1000;foe.max_hp=1000;foe.tissue_budget=1000
			foe.r = combat.body_radius()
		combat._attack()
		var limbs=combat.effects.filter(func(e):return e.type=="lash")
		check(limbs.size()==rank,"one functional limb per rank: %d"%rank)
		var expected=(9+rank*7)*preload("res://core/catalog.gd").milestone_multiplier(rank)
		var shown=0.0
		for effect in combat.effects:
			if effect.type=="damage":shown+=effect.amount
		check(is_equal_approx(shown,expected),"same-volley limb damage appears in current popups without lag")
		check(is_equal_approx(combat.combat_stats.damage_dealt,expected),"volley preserves total damage at rank %d"%rank)
		if rank>=3:check(combat.enemies.all(func(e):return e.hp<1000),"multiple limbs can damage separate foes")
		check(combat.enemies[0].pos==combat.player+Vector2(80,0),"limb strikes never teleport targets")
	print("LIVING MUTATIONS: %d failures"%failures)
	quit(0 if failures==0 else 1)
