extends SceneTree

const Terrain = preload("res://game/terrain_view.gd")
const Fluid = preload("res://game/fluid_view.gd")
const Fixture = preload("res://tools/performance/defold_fixture.gd")

func _initialize():
	capture.call_deferred()

func capture():
	var output := OS.get_environment("MICROGEN_ART_DIR")
	if output.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output)
	var view := SubViewport.new()
	view.disable_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.size = Vector2i(208, 208)
	root.add_child(view)
	for biome in range(2):
		for index in range(4):
			var patch := Terrain.Patch.new()
			patch.tiles = [{"p":Vector2(104,104),"wall":true,"biome":biome,"phase":float(index)*TAU/4.0,"growth":0.0,"detail":0.0}]
			view.add_child(patch)
			await RenderingServer.frame_post_draw
			var png := view.get_texture().get_image()
			if png.save_png(output.path_join("wall_%d_%d.png" % [biome, index])) != OK:
				quit(1)
				return
			patch.free()
	view.size = Vector2i(1280, 1280)
	var sim = Fixture.make()
	var fluid := Fluid.new()
	view.add_child(fluid)
	fluid.update(0.0, sim, Vector2(view.size), 1.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var error := view.get_texture().get_image().save_png(output.path_join("fluid.png"))
	quit(0 if error == OK else 1)
