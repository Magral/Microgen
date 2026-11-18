extends SceneTree
const Equipment=preload("res://core/organism_equipment.gd")
var failures=0
var app
func _initialize():call_deferred("run")
func inspect(screen: String):
	await process_frame;await process_frame;await process_frame
	var rect=Rect2(Vector2.ZERO,Vector2(root.size))
	for button in app.hud.content.find_children("*","Button",true,false):
		if not rect.encloses(button.get_global_rect()):
			failures+=1;push_error("%s: action outside viewport: %s %s"%[screen,button.text,button.get_global_rect()])
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/family-%s-%d.png"%[screen,root.size.y])
func run():
	app=load("res://main.tscn").instantiate();root.add_child(app)
	app.set_process(false);app.sound_enabled=false
	app.store.path="user://test-family-native.json";app.store.clear_test_files();app.store.profile=app.store.defaults()
	var flow=app._lineage()
	flow.create_family("predator");app.start_run(491)
	var first=app.store.family_id()
	app.show_menu();flow.create_family("toxic");app.start_run(492)
	app.show_menu();flow.create_family("colony")
	var third=app.store.family_id()
	for height in [640,720]:
		root.size=Vector2i(1280,height);root.content_scale_size=root.size
		flow.show_home();await inspect("home")
		flow.show_new();await inspect("forms")
		flow.select_family(third,false);await inspect("preparation")
		flow.confirm_delete(first);await inspect("delete")
		flow.select_family(first,true)
		app.show_development();await inspect("body")
		var organ=flow.state().equipped[0]
		flow.show_part(organ.id);await inspect("detail")
		flow.show_part(organ.id,"synergies");await inspect("synergies")
		flow.show_part(organ.id,"growth");await inspect("growth")
		flow.show_body(true);flow.show_statistics();await inspect("statistics")
		flow.show_body(true);app.show_genome();await inspect("legacy")
		flow.show_body(true);flow.show_picker("stock");await inspect("picker")
		app.show_menu()
	app.store.clear_test_files();app.queue_free();await process_frame
	print("FAMILY NATIVE: %d failures"%failures);quit(0 if failures==0 else 1)
