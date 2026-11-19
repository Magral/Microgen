extends SceneTree

const Terrain = preload("res://game/terrain_view.gd")
const Optics = preload("res://game/water_optics.gd")

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
			for kind in ["wall","bed","fibril","bed_fibril"]:
				var patch := Terrain.Patch.new()
				var growth := 0.0 if kind in ["bed","bed_fibril"] else 1.0
				var detail := 0.0 if kind in ["fibril","bed_fibril"] else 1.0
				patch.tiles = [{"p":Vector2(104,104),"wall":kind=="wall","biome":biome,"phase":float(index)*TAU/4.0,"growth":growth,"detail":detail}]
				view.add_child(patch)
				await RenderingServer.frame_post_draw
				var png := view.get_texture().get_image()
				if png.save_png(output.path_join("%s_%d_%d.png" % [kind, biome, index])) != OK:
					quit(1)
					return
				patch.free()
	var error := Optics.flow_texture().get_image().save_png(output.path_join("liquid_flow.png"))
	quit(0 if error == OK else 1)
