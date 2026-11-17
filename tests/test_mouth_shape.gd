extends SceneTree
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func _initialize():
	if not ResourceLoader.exists("res://game/mouth_shape.gd"):
		check(false,"mouth geometry implementation exists")
		quit(1)
		return
	var Mouth=load("res://game/mouth_shape.gd")
	var outline=PackedVector2Array([Vector2(-1,-1),Vector2(2,-1),Vector2(2,1),Vector2(-1,1)])
	check(Mouth.boundary(outline,0.0).is_equal_approx(Vector2(2,0)),"mouth attaches to interpolated boundary, not closest vertex")
	check(Mouth.boundary(outline,PI/2).is_equal_approx(Vector2(0,1)),"mouth tracks front heading")
	for angle in [0.0,0.4,1.7,-2.4]:
		var shape=Mouth.pose(outline,angle,0.0,0.0)
		var rotated=PackedVector2Array()
		for point in outline: rotated.append(point.rotated(0.8))
		check(Mouth.boundary(rotated,angle+0.8).is_equal_approx(shape.anchor.rotated(0.8)),"mouth anchoring rotates with contour")
		check(Geometry2D.is_point_in_polygon(shape.center,outline),"mouth cavity remains within tissue")
		check(not Geometry2D.triangulate_polygon(shape.slit).is_empty(),"mouth slit forms a valid polygon")
		var biting=Mouth.pose(outline,angle,1.0,0.0)
		check(biting.gap>shape.gap*2.0,"bite opens a visibly wider mouth")
		check(biting.anchor.is_equal_approx(shape.anchor),"bite does not detach the mouth from membrane")
	check(Mouth.pose(outline,0.0,0.0,1.0).gap>Mouth.pose(outline,0.0,0.0,0.0).gap,"front ingestion opens mouth")
	var round_body=PackedVector2Array()
	for i in range(64): round_body.append(Vector2.from_angle(i*TAU/64.0))
	for heading in [0.0,1.4,-2.8]:
		var idle=Mouth.pose(round_body,heading,0.0,0.0)
		var open=Mouth.pose(round_body,heading,1.0,0.0)
		check(open.width>idle.width*1.6,"engulfing jaw widens substantially")
		check(open.lower[8].distance_to(open.upper[8])>0.3,"engulfing opens a deep gullet")
		check(open.lower[8].distance_to(idle.lower[8])>open.upper[8].distance_to(idle.upper[8]),"lower jaw hinges farther than upper lip")
		for point in open.slit:
			check(Geometry2D.is_point_in_polygon(point,round_body),"open jaw stays in continuous body tissue")
			check(absf(angle_difference(heading,point.angle()))<0.7,"visual mouth stays in physical bite cone")
		var feeding=Mouth.pose(round_body,heading,0.0,1.0)
		check(feeding.slit==open.slit,"feeding and biting share engulfing pose")
	var Genome=load("res://core/genome.gd")
	var Tissue=load("res://game/tissue_damage.gd")
	for identity in range(180):
		var recipe=Genome.create(732 if identity==0 else identity,0,"player",0)
		for hp in [1.0,0.5,0.1]:
			var tissue=Tissue.contour(Genome.contour(recipe),recipe,hp)
			for turn in [0.0,0.7,1.5,3.2,4.8]:
				for bite in [0.0,0.5,1.0]:
					var pose=Mouth.pose(tissue,float(recipe.rotation)+turn,bite,0.0)
					check(not Geometry2D.triangulate_polygon(pose.slit).is_empty(),"jaw triangulates across 180 genomes, wounds, headings and bite stages")
	print("MOUTH SHAPE: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
