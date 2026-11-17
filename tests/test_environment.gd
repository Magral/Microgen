extends SceneTree
const World=preload("res://game/world.gd")
const Terrain=preload("res://game/terrain_view.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	var world=World.new()
	world.generate(108)
	var original=world.cells.duplicate()
	var terrain=Terrain.new()
	root.add_child(terrain)
	seed(314159)
	var expected_random=randf()
	seed(314159)
	terrain.update_world(world,world.start,Vector2(1280,720),3.0)
	await process_frame;await process_frame
	check(randf()==expected_random,"substrate must not consume gameplay/global randomness")
	check(world.cells==original,"decorations must preserve exact collision cells")
	check(terrain.chunks.size()==63,"terrain cache remains bounded to six-tile patches")
	var first_tiles=terrain.chunks[0].node.tiles.duplicate(true)
	var visible=0
	for chunk in terrain.chunks:
		if chunk.node.visible:visible+=1
	check(visible>0 and visible<12,"close camera culls the great majority of patches")
	# Sweep the map to materialize every native command cache once.
	for y in range(0,World.H,6):
		for x in range(0,World.W,6):
			terrain.update_world(world,Vector2(x+3,y+3)*World.TILE,Vector2(1280,720),3.0)
			await process_frame
	var command_count=0
	for chunk in terrain.chunks:
		var patch=chunk.node
		check(patch.draw_builds==1,"each patch builds geometry only once when revealed")
		command_count+=patch.commands.size()
		for command in patch.commands:
			if command.kind!=2:
				for point in command.points:
					check(chunk.bounds.has_point(point),"native geometry stays inside its culling overhang")
		patch.queue_redraw()
	await process_frame;await process_frame
	for chunk in terrain.chunks:check(chunk.node.draw_builds==1,"canvas redraw reuses geometry")
	check(command_count<100000,"static native command cache has a hard map-sized budget")
	check(terrain.rebuilds==1,"camera sweep never rebuilds terrain")
	world.generate(109)
	terrain.update_world(world,world.start,Vector2(1280,720),3.0)
	check(terrain.rebuilds==2,"reseed of same world replaces cached substrate")
	world.generate(108)
	terrain.update_world(world,world.start,Vector2(1280,720),3.0)
	check(terrain.chunks[0].node.tiles==first_tiles,"same seed restores identical positions and domain fields")
	terrain.queue_free()
	await process_frame
	print("ENVIRONMENT: %d failures, %d cached native commands"%[failures,command_count])
	quit(0 if failures==0 else 1)
