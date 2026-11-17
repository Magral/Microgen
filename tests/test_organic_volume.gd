extends SceneTree
const Volume=preload("res://game/organic_volume.gd")
const Genome=preload("res://core/genome.gd")
const Damage=preload("res://game/tissue_damage.gd")
const Jelly=preload("res://game/jelly_motion.gd")
const Absorption=preload("res://game/absorption.gd")
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func _initialize():
	var volume=Volume.new()
	for seed_value in range(18):
		var recipe=Genome.create(71+seed_value,seed_value,"player",0)
		recipe.family=seed_value%6
		var jelly=Jelly.new(recipe.rotation)
		for step in range(12): jelly.step(1.0/60,Vector2.from_angle(step*0.2)*210)
		for rich in [false,true]:
			var count=48 if rich else 24
			for hp in [1.0,0.75,0.5,0.25,0.1,0.0]:
				var contour=jelly.deform_points(Damage.contour(Genome.contour(recipe,count),recipe,hp),recipe.phase)
				var pose=Absorption.pose(Vector2(80,-30),0.47,contour,40)
				contour=Absorption.membrane(contour,pose,40)
				var colors=Genome.colors(recipe)
				var mesh=volume.mesh(contour,Vector2(500,300),40,colors[0],colors[1],colors[4],rich,recipe.phase)
				check(mesh.points.size()<=337,"rich volume has a bounded 337 vertex budget")
				check(mesh.points.size()==mesh.colors.size(),"every vertex has a continuous material color")
				check(mesh.indices.size()%3==0,"mesh has complete triangles")
				for index in mesh.indices: check(index>=0 and index<mesh.points.size(),"index within live deformed mesh")
				for point in mesh.points: check(point.is_finite(),"all deformed volume vertices finite")
				for index in range(count):
					check(mesh.points[mesh.points.size()-count+index].is_equal_approx(Vector2(500,300)+contour[index]*40),"outer ring follows exact damaged feeding silhouette")
				for color in mesh.colors: check(is_finite(color.r) and color.a>0.5 and color.a<=1.0,"lighting alpha remains translucent and finite")
	var damaged=Genome.create(71,0,"player",0)
	damaged.family=3;damaged.lobes=7;damaged.rotation=0.0;damaged.phase=0.0;damaged.stretch=0.91;damaged.asymmetry=0.12
	var lagged=Jelly.new(0.0)
	lagged.strain=Vector2(0.23586207,0);lagged.lag=Vector2(-0.08689655,0);lagged.speed_factor=1.2413793;lagged.clock=0.0
	var damaged_contour=lagged.deform_points(Damage.contour(Genome.contour(damaged,48),damaged,0.0),0.0)
	var dc=Genome.colors(damaged)
	var damaged_mesh=volume.mesh(damaged_contour,Vector2.ZERO,1.0,dc[0],dc[1],dc[4],true)
	var reversed=0
	for i in range(0,damaged_mesh.indices.size(),3):
		var a=damaged_mesh.points[damaged_mesh.indices[i]]
		var b=damaged_mesh.points[damaged_mesh.indices[i+1]]
		var c=damaged_mesh.points[damaged_mesh.indices[i+2]]
		if (b-a).cross(c-a)< -0.0000001:reversed+=1
	check(reversed==0,"damaged moving branched tissue never produces inverted overlapping volume faces")
	var circle=PackedVector2Array()
	for i in range(48): circle.append(Vector2.from_angle(i*TAU/48))
	for rich in [false,true]:
		var mesh=volume.mesh(circle,Vector2.ZERO,1.0,Color("249eaa"),Color("95f2df"),Color("153844"),rich)
		var first=1+(2 if rich else 1)*48
		check(mesh.colors[first+30].get_luminance()>mesh.colors[first+6].get_luminance()*1.3,"upper-left light is visibly brighter than lower-right at both LODs")
		check(mesh==volume.mesh(circle,Vector2.ZERO,1.0,Color("249eaa"),Color("95f2df"),Color("153844"),rich),"mesh deterministic and has no random-state dependency")
	var close_a=volume.material(Color(0.501,0.501,0.501),Color.WHITE,Color.BLACK,true)
	var close_b=volume.material(Color(0.507,0.507,0.507),Color.WHITE,Color.BLACK,true)
	check(close_a==close_b,"tiny pigment changes reuse the same deterministic lighting palette")
	for i in range(200):volume.material(Color(float(i)/200,0.4,0.3),Color.WHITE,Color.BLACK,true)
	check(volume._materials.size()<=Volume.MATERIAL_LIMIT,"long mutation histories retain a bounded palette cache")
	for phase_value in range(100):volume.density(48,float(phase_value))
	check(volume._densities.size()<=48,"species density texture math has a bounded reusable cache")
	for samples in range(3,100): volume.topology(samples,true)
	check(volume._topologies.size()<=6,"arbitrary input cannot grow persistent topology cache")
	check(volume.mesh(PackedVector2Array(),Vector2.ZERO,1,Color.WHITE,Color.WHITE,Color.BLACK,true).indices.is_empty(),"empty contour safely skipped")
	print("ORGANIC VOLUME: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
