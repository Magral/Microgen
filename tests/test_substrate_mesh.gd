extends SceneTree
const Substrate=preload("res://game/substrate_mesh.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():
	var mesh=Substrate.new()
	var commands=[{"kind":0,"points":PackedVector2Array([Vector2(0,0),Vector2(20,0),Vector2(20,20),Vector2(0,20)]),"color":Color(0.2,0.4,0.6,0.7)}, {"kind":1,"points":PackedVector2Array([Vector2(20,20),Vector2(30,24),Vector2(40,20)]),"width":1.5,"color":Color(0.3,0.7,0.8,0.6)}, {"kind":2,"p":Vector2(10,10),"radius":3.0,"color":Color(0.5,0.8,0.3,0.5)}]
	mesh.bake(commands)
	check(mesh.colors.size()==mesh.points.size() and mesh.indices.size()%3==0,"baked environment has complete colored triangles")
	for index in mesh.indices:check(index>=0 and index<mesh.points.size(),"every environment index addresses an actual vertex")
	for i in range(0,mesh.indices.size(),3):
		var a=mesh.points[mesh.indices[i]];var b=mesh.points[mesh.indices[i+1]];var c=mesh.points[mesh.indices[i+2]]
		check((b-a).cross(c-a)>=0,"environment faces retain their winding")
	check(mesh.colors.has(Color(0.3,0.7,0.8,0.0)),"stroke feather includes transparent outside edge")
	var points=mesh.points.duplicate();var indices=mesh.indices.duplicate();var colors=mesh.colors.duplicate()
	mesh.bake(commands)
	check(mesh.points==points and mesh.indices==indices and mesh.colors==colors,"rebaking is deterministic and does not append stale geometry")
	mesh.bake([])
	check(mesh.points.is_empty() and mesh.colors.is_empty() and mesh.indices.is_empty(),"empty patch clears old geometry")
	print("SUBSTRATE MESH: %d failures"%failures)
	quit(0 if failures==0 else 1)
