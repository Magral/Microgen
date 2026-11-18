extends SceneTree
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func descendants(node):
	var result=[node]
	for child in node.get_children():result.append_array(descendants(child))
	return result
func _initialize():call_deferred("run")
func run():
	var app=load("res://main.tscn").instantiate()
	root.add_child(app);app.set_process(false);app.sound_enabled=false
	app.store.path="user://test-home-layout.json";app.store.profile=app.store.defaults()
	app.store.profile.checkpoint={"outcome":"victory"}
	app.store.profile.legacy.pending={"generation":1,"candidates":[]}
	for viewport_size in [Vector2i(1280,720),Vector2i(1600,720),Vector2i(1280,640)]:
		root.size=viewport_size
		root.content_scale_size=viewport_size
		app.show_menu()
		await process_frame;await process_frame;await process_frame
		var viewport_rect=app.get_viewport_rect()
		check(absf(app.hud.content.get_global_rect().get_center().x-viewport_rect.get_center().x)<0.5,"home actions are horizontally centered")
		check(viewport_rect.size.is_equal_approx(Vector2(viewport_size)),"fixture uses actual requested logical viewport")
		check(not descendants(app.hud.modal).any(func(node):return node is ScrollContainer),"home has no scroll container")
		check(app.hud.modal.get_global_rect().is_equal_approx(viewport_rect),"home background layer fills viewport")
		var backdrop=app.hud.modal.get_node_or_null("Backdrop")
		check(backdrop!=null and backdrop.get_global_rect().is_equal_approx(viewport_rect),"home backdrop has no frame or uncovered borders")
		for node in descendants(app.hud.content):
			if node is Button:
				check(viewport_rect.encloses(node.get_global_rect()),"all home actions fit without scrolling: "+node.text)
				check(node.size.y>=50,"home buttons keep touch-sized height")
	if DisplayServer.get_name()!="headless" and OS.get_environment("MICROGEN_HOME_CAPTURE")!="":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("MICROGEN_HOME_CAPTURE"))
	app.store.clear_test_files();app.queue_free();await process_frame
	print("HOME LAYOUT: %d failures"%failures)
	quit(0 if failures==0 else 1)
