extends SceneTree
const Jelly = preload("res://game/jelly_motion.gd")
const Genome = preload("res://core/genome.gd")
var failures = 0
var checks = 0
func check(ok: bool,text: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(text)
func extent(points: PackedVector2Array) -> Vector2:
	var rect = Rect2(points[0],Vector2.ZERO)
	for point in points: rect = rect.expand(point)
	return rect.size
func _initialize():
	var circle = PackedVector2Array()
	for i in range(48): circle.append(Vector2.from_angle(i*TAU/48))
	var j = Jelly.new(0.0)
	var before = j.deform_points(circle,0.4)
	for i in range(90): j.step(1.0/60,Vector2.ZERO)
	var after = j.deform_points(circle,0.4)
	check(before!=after,"idle membrane changes shape")
	check(absf(after[0].length()/before[0].length()-after[12].length()/before[12].length())>0.01,"local waves rather than uniform scaling")
	for i in range(120): j.step(1.0/60,Vector2(145,0))
	var right = extent(j.deform_points(circle,0.4))
	check(right.x>right.y*1.15,"moving right stretches along direction")
	var before_turn = j.deform_points(circle,0.4)
	j.step(1.0/60,Vector2(0,-145))
	check(before_turn!=j.deform_points(circle,0.4),"turn deforms immediately but smoothly")
	for i in range(120): j.step(1.0/60,Vector2(0,-145))
	var up = extent(j.deform_points(circle,0.4))
	check(up.y>up.x*1.15,"moving up changes stretch axis")
	var early_strain = j.strain.length()
	for i in range(240): j.step(1.0/60,Vector2.ZERO)
	check(j.strain.length()<0.005 and early_strain>0.1,"stop settles spring")
	var sixty = Jelly.new(0.0)
	var thirty = Jelly.new(0.0)
	for i in range(120): sixty.step(1.0/60,Vector2(130,20))
	for i in range(60): thirty.step(1.0/30,Vector2(130,20))
	check(sixty.strain.distance_to(thirty.strain)<0.005,"spring independent of frame rate")
	check(absf(sixty.angle_delta()-thirty.angle_delta())<0.005,"heading independent of frame rate")
	for seed_value in range(80):
		var recipe = Genome.create(seed_value,7,"player",0)
		var motion = Jelly.new(recipe.rotation)
		for i in range(80): motion.step(1.0/60,Vector2.from_angle(i*0.08)*220)
		var outline = motion.deform_points(Genome.contour(recipe),recipe.phase)
		check(not Geometry2D.triangulate_polygon(outline).is_empty(),"moving outline triangulates")
		for point in outline: check(point.length()<2.2,"jelly displacement bounded")
	var clamped = Jelly.new(0.0)
	clamped.step(2.0,Vector2(10000,10000))
	check(clamped.strain.length()<=0.29 and clamped.lag.length()<=0.16,"slow frame and teleport remain bounded")
	print("JELLY: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
