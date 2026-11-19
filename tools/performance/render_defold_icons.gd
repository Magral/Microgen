extends SceneTree

const Art = preload("res://ui/organ_art.gd")
const Catalog = preload("res://core/catalog.gd")

func _initialize():
	render.call_deferred()

func render():
	var dst := OS.get_environment("MICROGEN_ART_DIR")
	if dst.is_empty():
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(dst)
	var view := SubViewport.new()
	view.size = Vector2i(144,144)
	view.disable_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for id in Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys():
		var icon := Art.new()
		icon.size = Vector2(view.size)
		icon.organ_id = id
		view.add_child(icon)
		icon.set_process(false)
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		if image.save_png(dst.path_join("icon_%s.png" % id)) != OK:
			quit(1)
			return
		icon.free()
	quit()
