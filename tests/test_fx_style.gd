extends SceneTree
const FX=preload("res://game/organic_fx.gd")
const Damage=preload("res://game/tissue_damage.gd")
const Jelly=preload("res://game/jelly_motion.gd")
const Genome=preload("res://core/genome.gd")
const Painter=preload("res://game/organism_painter.gd")
const SYNERGIES=["acid_grasp","spike_pulse","toxic_colony","spore_feast","enzyme_bite","conductive_bath","barbed_cilia","shield_pulse","metabolic_colony","ferment_cloud"]
class EffectCanvas:
	extends Node2D
	var accepted=0
	func _draw():
		for i in range(SYNERGIES.size()):
			var kind=SYNERGIES[i]
			var p=Vector2(100+(i%4)*200,100+(i/4)*200)
			var effect={"type":kind,"pos":p,"end":p+Vector2(65,20),"r":65.0,"life":0.6,"max":1.0}
			if FX.paint(self,effect,Vector2.ZERO,Vector2.ZERO,1.7,[p+Vector2(45,20),p+Vector2(-25,40),p+Vector2(0,-55),p+Vector2(50,-40)]): accepted+=1
			# Optional endpoints must also be safe for all area-only events.
			effect.erase("end")
			if FX.paint(self,effect,Vector2.ZERO,Vector2.ZERO,1.7): accepted+=1
		FX.infected(self,Vector2(400,400),40.0,Genome.create(44,4,"hunter",0),1.7,2.0)
		FX.field(self,Vector2(300,400),80.0,"spore",2.0,4.0,1.7)
var failures=0
func check(ok: bool,message: String):
	if not ok:
		failures+=1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var constants=FX.new().get_script().get_script_constant_map()
	check(constants.has("SYNERGY_STYLES"),"named synergy visual styles exist")
	if constants.has("SYNERGY_STYLES"):
		var styles=constants.SYNERGY_STYLES
		var identities={}
		for kind in SYNERGIES:
			check(styles.has(kind),"supported visual event: "+kind)
			if not styles.has(kind): continue
			identities[styles[kind].form]=true
			check(styles[kind].budget<=25,"bounded draw primitives: "+kind)
		check(identities.size()==10,"every synergy has its own readable silhouette")
	var fx=FX.new()
	check(fx.has_method("_infection_contour"),"infection reuses a bounded anatomy contour cache")
	if fx.has_method("_infection_contour"):
		var recipe=Genome.create(44,8,"hunter",0)
		check(fx.call("_infection_contour",recipe)==Genome.contour(recipe,24),"cached infection branches match actual tissue")
		var changed=recipe.duplicate()
		changed.rotation+=0.3
		check(fx.call("_infection_contour",recipe)!=fx.call("_infection_contour",changed),"cache respects mutated anatomy")
	var painter=Painter.new()
	check(painter.has_method("_prepare_anchors"),"attachment directions normalize once per painted contour")
	if painter.has_method("_prepare_anchors"):
		var mismatches=0
		painter.mobile_tissue=true
		for genome_seed in range(24):
			var recipe=Genome.create(genome_seed,genome_seed+4,"hunter",0)
			var jelly=Jelly.new(recipe.rotation)
			for step_index in range(15): jelly.step(1.0/60.0,Vector2(150,-90))
			for detail in [24,48]:
				for health in [1.0,0.7,0.3,0.05]:
					var contour=jelly.deform_points(Damage.contour(Genome.contour(recipe,detail),recipe,health),recipe.phase)
					painter.call("_prepare_anchors",contour)
					for angle_index in range(90):
						var angle=angle_index*TAU/90.0+0.137
						var direction=Vector2.from_angle(angle)
						var score=-2.0
						var reference=contour[0]
						for point in contour:
							var candidate=point.normalized().dot(direction)
							if candidate>score:
								score=candidate
								reference=point
						if painter._anchor(contour,angle)!=reference: mismatches+=1
		painter.mobile_tissue=false
		check(mismatches==0,"cached attachments exactly match original rays under jelly and damage")
	check(painter.has_method("visual_stage"),"organ ranks have visual milestone stages")
	if painter.has_method("visual_stage"):
		for pair in [[0,0],[2,0],[3,1],[5,1],[6,2],[9,2],[10,3],[30,3]]:
			check(painter.call("visual_stage",pair[0])==pair[1],"visual stage milestone: "+str(pair[0]))
	check(painter.has_method("_wound_scar"),"damaged membrane scars expose safe geometry")
	if painter.has_method("_wound_scar"):
		var invalid_scars=0
		var missing_visible_scars=0
		for genome_seed in range(40):
			var recipe=Genome.create(genome_seed,genome_seed+7,"hunter",0)
			for health_step in range(101):
				var health=health_step/100.0
				var contour=Damage.contour(Genome.contour(recipe),recipe,health)
				for wound in Damage.wounds(recipe,health):
					var lip=painter._anchor(contour,float(wound.angle))
					var outward=lip.normalized()
					var normal=outward.orthogonal()
					var root_point=lip*40.0
					var amount=float(wound.strength)
					var reach=40.0*(0.16+amount*0.15)
					var end_point=root_point-outward*reach
					var kink=root_point-outward*reach*0.45+normal*reach*0.15
					for offset in [Vector2.ZERO,Vector2(800,1500),Vector2(1600,3000)]:
						for scale_value in [0.1,0.5,1.0,3.0]:
							var scar=painter.call("_wound_scar",root_point*scale_value+offset,kink*scale_value+offset,end_point*scale_value+offset,normal,40.0*scale_value*0.035*amount)
							if not scar.is_empty() and Geometry2D.triangulate_polygon(scar).is_empty(): invalid_scars+=1
							if amount>0.1 and scale_value>=0.5 and scar.is_empty(): missing_visible_scars+=1
		check(invalid_scars==0,"all health levels produce valid damage scars; invalid: "+str(invalid_scars))
		check(missing_visible_scars==0,"visible damage scars retain their pigmented fill")
	var canvas=EffectCanvas.new()
	root.add_child(canvas)
	seed(7193)
	var expected_random=randi()
	seed(7193)
	canvas.queue_redraw()
	await process_frame
	await process_frame
	check(randi()==expected_random,"visual effects never consume gameplay RNG")
	check(canvas.accepted==20,"every named synergy renders with and without optional endpoint")
	canvas.free()
	print("FX STYLE: %d failures" % failures)
	quit(0 if failures==0 else 1)
