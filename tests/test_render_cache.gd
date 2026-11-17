extends SceneTree
const Sim=preload("res://game/simulation.gd")
const Terrain=preload("res://game/terrain_view.gd")
const Map=preload("res://ui/minimap.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var sim=Sim.new()
	sim.new_run(44)
	var terrain=Terrain.new()
	root.add_child(terrain)
	var map=Map.new()
	map.sim=sim;map.size=Vector2(260,190)
	root.add_child(map)
	for i in range(30):
		terrain.update_world(sim.world,sim.player+Vector2(i,0),Vector2(1280,720),sim.view_zoom())
		map.queue_redraw()
		await process_frame
	check(terrain.rebuilds==1,"moving camera reuses terrain draw commands")
	check(map.rebuilds==1,"stationary exploration reuses minimap texture")
	var visible=terrain.chunks.filter(func(chunk):return chunk.node.visible).size()
	check(visible>0 and visible<terrain.chunks.size(),"offscreen terrain chunks are culled")
	var idx=0
	while idx in sim.explored:idx+=1
	sim.explored[idx]=true
	map.queue_redraw()
	await process_frame;await process_frame
	check(map.rebuilds==2,"new exploration refreshes minimap once")
	sim.new_run(45)
	terrain.update_world(sim.world,sim.player,Vector2(1280,720),sim.view_zoom())
	map.queue_redraw()
	await process_frame;await process_frame
	check(terrain.rebuilds==2 and map.rebuilds==3,"new run replaces old visual caches")
	terrain.queue_free();map.queue_free()
	await process_frame
	print("RENDER CACHE: %d failures"%failures)
	quit(0 if failures==0 else 1)
