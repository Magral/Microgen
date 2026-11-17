extends SceneTree
const Sim=preload("res://game/simulation.gd")
var fails=0
func check(ok: bool,text: String):
	if not ok:fails+=1;push_error(text)
func _initialize():call_deferred("run")
func run():
	var sanitized=preload("res://game/heredity.gd").normalize({"form":{},"traits":1000000000,"seed":{}})
	check(sanitized.traits.is_empty() and sanitized.seed==1,"malformed inherited configuration cannot hang restore")
	var s=Sim.new()
	check(s.get("run_loadout")!=null,"run snapshots retain inherited configuration")
	if s.get("run_loadout")==null:quit(1);return
	var unlocked=preload("res://core/catalog.gd").base_unlocked();unlocked.append("division")
	for entry in [["predator","devour",1],["toxic","acid",0],["colony","division",4]]:
		s.call("new_run",44,unlocked,{},entry[0],{"form":entry[0],"traits":[],"imprint":"","seed":92,"branch":entry[0]})
		check(s.build.rank(entry[1])==1 and s.build.organs.size()==1,"form has one functional starter organ")
		check(s.player_genome.family==entry[2],"form changes actual anatomy")
	var painter=preload("res://game/organism_painter.gd").new()
	var recipe=preload("res://core/genome.gd").create(92,0,"player",0)
	var old_contour=painter.anatomy(recipe).contour
	var changed=recipe.duplicate();changed.stretch=1.12;changed.asymmetry=0.13
	check(painter.anatomy(changed).contour!=old_contour,"same-seed trait mutation invalidates cached anatomy")
	var normal=Sim.new();normal.new_run(44)
	var collector=Sim.new();collector.new_run(44,unlocked,{"collect":2})
	check(is_equal_approx(collector.attraction_radius(),collector.body_radius()+16),"purchased collection radius applies before learning a magnet organ")
	s.call("new_run",44,unlocked,{},"predator",{"form":"predator","traits":["folds","receptive"],"imprint":"devour","seed":92,"branch":"predator"})
	check(s.build.rank("devour")==1,"duplicate imprint does not add free rank")
	s.hp=50;s.heal_player(10);check(is_equal_approx(s.hp,59),"folds healing tradeoff is real")
	var item={"pos":s.player,"duration":1.0,"progress":0.0,"material":"membrane"};s._capture(item)
	check(is_equal_approx(item.duration,0.52),"folds shorten only detached tissue digestion")
	s.gain_xp(10);check(is_equal_approx(s.xp,9.5),"receptive XP tradeoff is real")
	var ancestor=preload("res://core/genome.gd").create(1234,4,"player",0);ancestor.palette=(int(s.player_genome.palette)+3)%8
	var descendant=Sim.new();descendant.new_run(44,unlocked,{},"predator",{"form":"predator","traits":[],"imprint":"devour","seed":92,"branch":"predator","ancestry_recipe":ancestor})
	var own=preload("res://core/genome.gd").colors(descendant.player_genome)[0]
	check(not descendant.body_color().is_equal_approx(own),"selected imprint mixes an ancestral pigment into descendant")
	var restored=Sim.new();check(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot()))),"loadout survives JSON save")
	check(restored.run_loadout==s.run_loadout,"resume preserves exact traits/form/seed/imprint")
	check(is_equal_approx(restored.build.branch_weight,1.75),"preferred branch remains after restore")
	print("RUN LOADOUT: %d failures"%fails);quit(0 if fails==0 else 1)
