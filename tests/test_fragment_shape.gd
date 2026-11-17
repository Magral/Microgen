extends SceneTree
var failures=0
func _initialize():call_deferred("run")
func run():
	var painter=load("res://game/organism_painter.gd").new()
	var genome=load("res://core/genome.gd")
	var first=painter.anatomy(genome.create(31,4,"hunter",0))
	if not first.has("fragments"):
		push_error("fragment shapes are precomputed as valid tissue polygons")
		quit(1)
		return
	for seed_value in range(180):
		var data=painter.anatomy(genome.create(seed_value,seed_value%17,"hunter",seed_value%2))
		for contour in data.fragments:
			if contour.size()<3 or Geometry2D.triangulate_polygon(contour).is_empty():
				failures+=1
				push_error("fragment must remain triangulatable across procedural body families")
	print("FRAGMENT SHAPE: %d failures" % failures)
	quit(0 if failures==0 else 1)
