extends SceneTree
const Mouth=preload("res://game/mouth_shape.gd")
const Genome=preload("res://core/genome.gd")
const Damage=preload("res://game/tissue_damage.gd")
const Jelly=preload("res://game/jelly_motion.gd")
var failures=0
func _initialize():call_deferred("run")
func run():
	var comparisons=0
	for seed_value in range(30):
		var recipe=Genome.create(seed_value,seed_value+7,"hunter",0)
		var jelly=Jelly.new(float(recipe.rotation))
		for frame in range(5):
			jelly.step(0.08,Vector2.from_angle(frame*2.0)*180)
			for health in [1.0,0.5,0.05]:
				var contour=jelly.deform_points(Damage.contour(Genome.contour(recipe),recipe,health),float(recipe.phase))
				var angles=Mouth.radial_angles(contour)
				var headings=[]
				for ray in range(90):headings.append(ray*TAU/90.0)
				for point in contour:headings.append(point.angle())
				for seam in [-0.000001,0.0,0.000001]:headings.append(contour[0].angle()+seam)
				for heading in headings:
					var actual=Mouth.radial_boundary(contour,heading,angles)
					var expected=Mouth.boundary(contour,heading)
					if actual.distance_to(expected)>0.00005:failures+=1
					comparisons+=1
	# Deliberately unordered input must safely retain the original general solver.
	var nonradial=PackedVector2Array([Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)])
	if not Mouth.radial_angles(nonradial).is_empty():failures+=1
	print("RADIAL BOUNDARY: %d exact comparisons, %d failures"%[comparisons,failures])
	quit(0 if failures==0 else 1)
