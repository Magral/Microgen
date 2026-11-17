extends SceneTree
const Volume=preload("res://game/organic_volume.gd")
const Genome=preload("res://core/genome.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func reference(volume,contour,p,radius,body,edge,shadow,rich,phase):
	var topo=volume.topology(contour.size(),rich)
	var palette=volume.material(body,edge,shadow,rich)
	var grain=volume.density(contour.size(),phase) if rich else PackedFloat32Array()
	var points=PackedVector2Array([p])
	var colors=PackedColorArray([Color(body.lerp(edge,0.20),0.88)])
	var light=[]
	for i in range(contour.size()):
		var tangent=contour[(i+1)%contour.size()]-contour[posmod(i-1,contour.size())]
		var facing=Vector2(tangent.y,-tangent.x).normalized().dot(Volume.LIGHT)
		light.append(clampi(roundi((facing+1.0)*0.5*(Volume.LIGHT_SAMPLES-1)),0,Volume.LIGHT_SAMPLES-1))
	for ring in range(topo.rings.size()):
		for i in range(contour.size()):
			points.append(p+contour[i]*radius*topo.rings[ring])
			var lit:Color=palette[ring*Volume.LIGHT_SAMPLES+light[i]]
			if rich:
				var alpha=lit.a
				lit=lit.lerp(shadow,grain[ring*contour.size()+i]);lit.a=alpha
			colors.append(lit)
	return {"points":points,"colors":colors,"indices":topo.indices}
func _initialize():
	var volume=Volume.new()
	check(volume.get("_shading") is Dictionary,"volume reuses bounded lighting for unchanged normals")
	if failures>0:quit(1);return
	for seed_value in range(12):
		var recipe=Genome.create(703,seed_value,"player",0)
		for rich in [true,false]:
			var contour=Genome.contour(recipe,48 if rich else 24)
			var palette=Genome.colors(recipe)
			for change in range(4):
				var body=palette[0].lerp(palette[4],change*0.09)
				var phase=recipe.phase+change*0.3
				var p=Vector2(501,-340);var radius=17.0+change*37.5
				var mesh=volume.mesh(contour,p,radius,body,palette[1],palette[4],rich,phase)
				var original=reference(volume,contour,p,radius,body,palette[1],palette[4],rich,phase)
				check(mesh.indices==original.indices,"volume topology stays identical")
				check(mesh.colors==original.colors,"cached lighting matches original health/pigment/detail/phase math exactly")
				for i in range(mesh.points.size()):check(mesh.points[i].distance_to(original.points[i])<0.0002,"packed transforms preserve mesh position")
				var cache_count=volume._shading.size()
				var moved=volume.mesh(contour,p+Vector2(40,10),radius*0.6,body,palette[1],palette[4],rich,phase)
				check(volume._shading.size()==cache_count and moved.colors==mesh.colors,"movement and size reuse lighting")
				mesh.colors[0]=Color.MAGENTA
				check(volume.mesh(contour,p,radius,body,palette[1],palette[4],rich,phase).colors==original.colors,"caller cannot corrupt cached lighting")
				contour=Transform2D(0.2,Vector2(1.05,0.95),0,Vector2.ZERO)*contour
	check(volume._shading.size()<=96,"long histories keep at most 96 shading entries")
	var circle=PackedVector2Array()
	for i in range(48):circle.append(Vector2.from_angle(i*TAU/48))
	var shared=Volume.new()
	shared.mesh(circle,Vector2.ZERO,40,Color("249eaa"),Color("95f2df"),Color("153844"),true,5480*0.00001)
	var other=shared.mesh(circle,Vector2.ZERO,40,Color("249eaa"),Color("95f2df"),Color("153844"),true,34917*0.00001)
	var fresh=Volume.new().mesh(circle,Vector2.ZERO,40,Color("249eaa"),Color("95f2df"),Color("153844"),true,34917*0.00001)
	check(other.colors==fresh.colors,"colliding phase hashes cannot reuse another organism's lighting")
	print("VOLUME REUSE: %d failures"%failures)
	quit(0 if failures==0 else 1)
