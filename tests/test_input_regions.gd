extends SceneTree
var failures = 0
func check(ok: bool,text: String):
	if not ok:
		failures+=1
		push_error(text)
func _initialize(): call_deferred("run")
func run():
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.sound_enabled=false
	await process_frame
	var size = root.get_visible_rect().size
	for point in [Vector2(8,8),Vector2(size.x-8,8),Vector2(size.x-8,size.y-8),Vector2(8,size.y-8),size/2,Vector2(size.x*0.85,size.y*0.6)]:
		check(scene._stick_region(point),"free screen point accepted: "+str(point))
	check(not scene._stick_region(Vector2(-1,200)),"outside left rejected")
	check(not scene._stick_region(Vector2(size.x+1,200)),"outside right rejected")
	check(not scene._stick_region(Vector2(200,-1)),"outside top rejected")
	check(scene.hud.hp_bar.mouse_filter==Control.MOUSE_FILTER_IGNORE,"health HUD passes touches")
	check(scene.hud.xp_bar.mouse_filter==Control.MOUSE_FILTER_IGNORE,"DNA HUD passes touches")
	scene.queue_free()
	await process_frame
	print("INPUT REGIONS: %d failures" % failures)
	quit(0 if failures==0 else 1)
