extends SceneTree
const Sim=preload("res://game/simulation.gd")
const Catalog=preload("res://core/catalog.gd")
var fails=0
func check(ok: bool,label: String):
	if not ok:fails+=1;push_error(label)
func make():
	var s=Sim.new()
	s.new_run(99)
	s.enemies.clear()
	s.pickups.clear()
	s.build.organs.clear()
	s.spawn_enemy(s.player+Vector2(40,0),"hunter")
	s.enemies[0].r=22
	s.enemies[0].hp=1000
	s.enemies[0].max_hp=1000
	s.enemies[0].tissue_budget=1000
	s.enemies[0].traits=[]
	s.facing=0
	return s
func _initialize():call_deferred("run")
func run():
	check(Catalog.ORGANS.size()==12 and Catalog.ADAPTATIONS.size()==6 and Catalog.SYNERGIES.size()==10,"expanded catalog has12organs6passives10synergies")
	for id in ["cilia","enzymes","electric"]:
		var s=make()
		s.build.organs={id:1}
		var before=s.enemies[0].hp
		s._attack()
		check(s.enemies[0].hp<before or s.enemies[0].get("enzyme_time",0)>0,"real combat effect for "+id)
	var shield=make()
	shield.build.organs={"barrier":1}
	shield.hurt_player(20)
	check(is_equal_approx(shield.hp,94),"shield absorbs14of20incomingdamage")
	var loot=make()
	loot._die(0,false)
	check(loot.remains[0].get("quality",-1)>loot.remains[2].get("quality",-1),"organelle visually outranks ordinary tissue")
	check(loot.remains[0].dna>loot.remains[2].dna,"valuable organelle actually yields moreDNA")
	var dna=0
	var bio=0
	for part in loot.remains:dna+=part.dna;bio+=part.bio
	check(dna==9 and bio==4,"graded normal corpse conserves total material")
	var combo=make()
	combo.build.organs={"electric":1,"acid":1}
	combo._attack()
	check(combo.enemies[0].slow>0 and combo.fields.any(func(f):return f.kind=="acid_arc"),"conductive bath creates slowing acid discharge")
	combo=make()
	combo.build.organs={"cilia":1,"spikes":1}
	combo._attack()
	check(combo.shots.size()>=3,"barbed cilia emits its actual extra spines")
	combo=make()
	combo.build.organs={"barrier":1,"pulse":1}
	combo.cooldowns.barrier=7.0
	combo._attack()
	check(combo.cooldowns.barrier<=5.0,"shield pulse reduces next shield recharge")
	combo=make()
	combo.build.organs={"enzymes":1,"devour":1}
	combo._attack()
	check(combo.enemies[0].get("enzyme_time",0)>0,"enzyme bite coats frontal target")
	combo=make()
	combo.build.organs={"enzymes":1,"trail":1}
	combo._attack()
	check(combo.fields.any(func(f):return f.kind=="poison" and f.damage==10.0),"ferment cloud increases poison field damage")
	combo=make()
	combo.build.organs={"division":1}
	combo.build.adaptations={"metabolism":1}
	combo.hp=80.0
	combo.step(0.1,Vector2.ZERO)
	check(combo.hp>80,"metabolic colony actually restores HP")
	print("NEW CONTENT: %d failures" % fails)
	quit(0 if fails==0 else 1)
