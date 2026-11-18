extends SceneTree
const Sim=preload("res://game/simulation.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func fresh():
	var s=Sim.new();s.new_run(144);s.enemies.clear();s.effects.clear();s.pickups.clear();s.fields.clear();s.cooldowns={};return s
func foe(s,ratio: float,health: float=1.0):
	s.spawn_enemy(s.player+Vector2(100,0),"hunter")
	var e=s.enemies.back();e.r=s.body_radius()*ratio;e.max_hp=1000;e.hp=1000*health;e.tissue_budget=1000;e.speed=0;e.traits=[];return e
func run():
	var s=fresh();s.build.organs={"tentacle":6};s.build.adaptations={"magnet":3};s.build.stats.evolutions={"tentacle":true};s.facing=PI/2
	var small=foe(s,0.6);var giant=foe(s,2.0);giant.pos+=Vector2(0,40)
	var before=small.pos;s._attack()
	check(giant.hp==giant.max_hp,"ordinary lashes cannot damage a closed giant membrane")
	giant.enzyme_time = 2.0
	s.cooldowns.tentacle = 0.0
	s._attack()
	check(giant.hp<giant.max_hp,"ordinary lashes can hit a giant after enzymes expose its membrane")
	check(float(small.get("crown_time",0))>0,"evolved crown marks smaller prey")
	check(float(giant.get("crown_time",0))==0,"healthy giant cannot be held")
	check(small.pos==before,"crown strike never teleports prey")
	s._update_enemies(0.05)
	check(small.pos.y>before.y,"crown steers prey toward the facing mouth, not just center")
	check(small.pos.distance_to(before)<20,"steering is continuous and bounded")
	small.r=s.body_radius()*1.1;small.hp=small.max_hp
	s._update_enemies(0.01)
	check(float(small.get("crown_time",0))==0,"healthy peer released immediately")
	var contour_test=fresh();contour_test._touches(contour_test.player,0)
	var initial=contour_test._cached_contact_polygon.duplicate()
	contour_test.build.stats.evolutions={"tentacle":true};contour_test._touches(contour_test.player,0)
	check(contour_test._cached_contact_polygon!=initial,"evolution gain invalidates fallback contact shape")
	var evolved_shape=contour_test._cached_contact_polygon.duplicate()
	contour_test.build.stats.evolutions={};contour_test._touches(contour_test.player,0)
	check(contour_test._cached_contact_polygon==initial,"evolution removal restores fallback contact shape")
	contour_test.build.stats.evolutions={"acid":true};contour_test._touches(contour_test.player,0)
	var first=contour_test._cached_contact_polygon.duplicate();contour_test.elapsed=1.1;contour_test._touches(contour_test.player,0)
	check(contour_test._cached_contact_polygon!=first,"animated evolved contact shape refreshes with simulation time")
	check(contour_test.has_method("_crown_destination"),"crown uses a shared actual-contour mouth destination")
	if contour_test.has_method("_crown_destination"):
		contour_test.facing=0;contour_test.contact_contour=PackedVector2Array([Vector2(-0.5,-0.7),Vector2(0.25,-0.7),Vector2(0.25,0.7),Vector2(-0.5,0.7)])
		var local=contour_test.call("_crown_destination")-contour_test.player
		check(local.x<contour_test.body_radius()*0.25,"prey enters a narrow front instead of settling outside membrane")
	var many=fresh();many.build.organs={"tentacle":10};many.build.adaptations={"magnet":3};many.build.stats.evolutions={"tentacle":true}
	for i in range(8):var e=foe(many,0.6);e.pos+=Vector2(0,i*2)
	many._attack();check(many.enemies.filter(func(e):return float(e.get("crown_time",0))>0).size()==2,"at most two crown targets")
	var armor=fresh();armor.build.organs={"acid":6};armor.build.adaptations={"armor":3};armor.build.stats.evolutions={"acid":true}
	armor.hurt_player(10,{"kind":"projectile","pos":armor.player+Vector2(100,0)})
	check(armor.fields.is_empty(),"ranged damage cannot trigger contact mantle")
	armor.hurt_player(10,{"kind":"collision","pos":armor.player+Vector2(40,0)})
	check(armor.fields.size()==1 and armor.fields[0].get("source","")=="acid","contact mantle creates acid-attributed secretion")
	armor.hurt_player(10,{"kind":"collision","pos":armor.player+Vector2(40,0)})
	check(armor.fields.size()==1,"mantle cooldown prevents contact spam")
	var womb=fresh();womb.build.organs={"infection":6};womb.build.adaptations={"metabolism":3};womb.build.stats.evolutions={"infection":true}
	check(womb.has_method("_infected_meal"),"womb consumes completed infected meals")
	if womb.has_method("_infected_meal"):
		womb.call("_infected_meal");womb.call("_infected_meal")
		check(womb.get("spore_charge")==2 and womb.fields.is_empty(),"two meals charge without burst")
		var loaded=Sim.new();check(loaded.restore(JSON.parse_string(JSON.stringify(womb.snapshot()))),"new evolution state survives JSON")
		check(loaded.get("spore_charge")==2,"spore charge persists")
		loaded.call("_infected_meal")
		check(loaded.get("spore_charge")==0 and loaded.fields.size()==1,"third meal releases one burst and resets charge")
		var feeding=fresh();feeding.build.organs={"infection":6};feeding.build.stats.evolutions={"infection":true}
		var meal=foe(feeding,0.6);meal.infect=2.0;feeding._leave_remains(meal)
		feeding.remains=[feeding.remains[0]];feeding.remains[0].pos=feeding.player
		feeding._update_remains(0.3)
		check(feeding.spore_charge==0,"contact with infected fragment does not grant charge")
		feeding._update_remains(0.4);feeding._update_remains(0.4)
		check(feeding.spore_charge==1,"one fully digested infected fragment grants charge exactly once")
		var old=womb.snapshot();old.erase("spore_charge")
		var migrated=Sim.new();migrated.restore(JSON.parse_string(JSON.stringify(old)))
		check(migrated.get("spore_charge")==0,"old saves default to empty chambers")
	print("FUNCTIONAL EVOLUTIONS: %d failures"%failures);quit(0 if failures==0 else 1)
