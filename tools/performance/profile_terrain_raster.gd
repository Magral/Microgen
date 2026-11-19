extends SceneTree

const Terrain = preload("res://game/terrain_view.gd")
const World = preload("res://game/world.gd")
const Growth = preload("res://core/growth.gd")
const CAMERA := Vector2(2860,2090)
const WARMUP := 28
const SAMPLES := 120

func _initialize():
	run.call_deferred()

func run():
	Engine.max_fps=0
	root.size=Vector2i(2460,1080)
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	var world=World.new()
	world.generate(44)
	var viewport := root.get_visible_rect().size
	var zoom := Growth.zoom(Growth.radius(37))
	for mode in ["legacy","geometry","raster"]:
		var terrain := Terrain.new()
		terrain.raster_enabled=mode=="raster"
		root.add_child(terrain)
		for i in range(WARMUP):
			update(terrain,world,CAMERA,viewport,zoom,mode=="legacy")
			await RenderingServer.frame_post_draw
		var times: Array[int] = []
		var last := Time.get_ticks_usec()
		for i in range(SAMPLES):
			update(terrain,world,CAMERA+Vector2(sin(i*0.17),cos(i*0.11))*18.0,viewport,zoom,mode=="legacy")
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			times.append(now-last)
			last=now
		times.sort()
		update(terrain,world,CAMERA,viewport,zoom,mode=="legacy")
		await RenderingServer.frame_post_draw
		var visible := 0
		var quads := 0
		var triangles := 0
		for chunk in terrain.chunks:
			if not chunk.node.visible:continue
			visible+=1
			if chunk.node.raster_texture!=null:quads+=1
			else:triangles+=chunk.node.mesh.indices.size()/3
		var output := OS.get_environment("MICROGEN_PROFILE_OUTPUT")
		root.get_texture().get_image().save_png(output.path_join("terrain_"+mode+".png"))
		print("TERRAIN ",JSON.stringify({"mode":mode,"canvas":str(viewport),"zoom":zoom,"visible":visible,"quads":quads,"triangles":triangles+quads*2,"median_ms":times[SAMPLES/2]/1000.0,"p95_ms":times[int(SAMPLES*0.95)]/1000.0,"resident_pixels":terrain.raster_cache.resident_pixels if mode=="raster" else 0}))
		terrain.queue_free()
		await process_frame
	quit()

func update(terrain: Node2D, world, camera: Vector2, viewport: Vector2, zoom: float, legacy: bool):
	terrain.update_world(world,camera,viewport,zoom)
	if legacy:
		var area := Rect2(camera-viewport/(2*zoom),viewport/zoom).grow(100)
		for chunk in terrain.chunks:chunk.node.visible=chunk.bounds.intersects(area)
