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
	print("MOUTH SHAPE: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
