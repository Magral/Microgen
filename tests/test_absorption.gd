extends SceneTree
const Genome = preload("res://core/genome.gd")
var failures=0
var checks=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var path="res://game/absorption.gd"
	check(ResourceLoader.exists(path),"organic absorption geometry exists")
	if ResourceLoader.exists(path):
		var absorption=load(path)
		for seed_value in range(40):
			var contour=Genome.contour(Genome.create(seed_value,3,"player",0))
			var direction=Vector2.from_angle(seed_value*0.7)
			var source=direction*46.0
			var start=absorption.pose(source,0.0,contour,34.0)
			var crossing=absorption.pose(source,0.45,contour,34.0)
			var finish=absorption.pose(source,0.98,contour,34.0)
			check(start.offset.distance_to(source)<0.01,"fragment begins at real source")
			check(crossing.offset.length()<start.offset.length(),"tissue crosses membrane inward")
			check(Geometry2D.is_point_in_polygon(finish.offset/34.0,contour),"late fragment is inside body")
			check(finish.scale<0.25 and finish.alpha<0.15,"internal tissue dissolves at completion")
			for progress in [0.1,0.35,0.6,0.9]:
				var pose=absorption.pose(source,progress,contour,34.0)
				var shape=absorption.membrane(contour,pose,34.0)
				check(Geometry2D.triangulate_polygon(shape).size()>0,"contact membrane remains triangulatable")
				for point in shape: check(point.length()<2.5,"localized membrane stretch bounded")
	print("ABSORPTION: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
