extends SceneTree
const Damage = preload("res://game/tissue_damage.gd")
const Genome = preload("res://core/genome.gd")
const Jelly = preload("res://game/jelly_motion.gd")
const Absorption = preload("res://game/absorption.gd")
var failures=0
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func loss(a: PackedVector2Array,b: PackedVector2Array) -> float:
	var total=0.0
	for i in range(a.size()): total+=a[i].distance_to(b[i])
	return total/a.size()
func _initialize():
	var recipe=Genome.create(431,7,"player",0)
	var base=Genome.contour(recipe)
	check(Damage.contour(base,recipe,1.0)==base,"healthy membrane preserves exact genome")
	var damaged=Damage.contour(base,recipe,0.25)
	var dying=Damage.contour(base,recipe,0.1)
	check(loss(base,damaged)>0.10,"quarter health has substantial tissue loss")
	check(loss(base,dying)>loss(base,damaged)*1.1,"near death visibly worsens body breakdown")
	check(Damage.contour(base,recipe,0.25)==damaged,"damage sites are deterministic")
	check(Damage.contour(base,recipe,1.0)==base,"healing restores original identity")
	check(loss(damaged,Damage.contour(base,recipe,0.251))<0.003,"healing changes membrane continuously")
	check(Damage.wounds(recipe,1.0).is_empty(),"healthy tissue has no leaking wounds")
	check(Damage.wounds(recipe,0.1).size()>=4,"near death opens multiple wounds")
	check(Damage.contour(base,recipe,-2.0)==Damage.contour(base,recipe,0.0),"negative health bounded")
	check(Damage.contour(base,recipe,4.0)==base,"excess health bounded")
	var next_recipe=Genome.create(432,7,"player",0)
	check(Damage.wounds(recipe,0.25)[0].angle!=Damage.wounds(next_recipe,0.25)[0].angle,"different genomes have individual scars")
	for seed_value in range(80):
		var genome=Genome.create(seed_value,seed_value+3,"player",0)
		var jelly=Jelly.new(genome.rotation)
		for i in range(30): jelly.step(1.0/60,Vector2.from_angle(i*0.1)*220)
		for detail in [24,48]:
			var outline=Genome.contour(genome,detail)
			for hp in [1.0,0.75,0.5,0.25,0.1,0.0]:
				var torn=Damage.contour(outline,genome,hp)
				check(torn.size()==outline.size(),"damage preserves ordered contour samples")
				for i in range(torn.size()):
					check(torn[i].is_finite() and torn[i].length()>=outline[i].length()*0.29 and torn[i].length()<=outline[i].length()*1.001,"radial damage bounded without detached vertices")
				var moving=jelly.deform_points(torn,genome.phase)
				var state=Absorption.pose(Vector2(80,-40),0.35,moving,40)
				moving=Absorption.membrane(moving,state,40)
				check(not Geometry2D.triangulate_polygon(moving).is_empty(),"damaged moving absorbing tissue triangulates")
	print("TISSUE DAMAGE: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
