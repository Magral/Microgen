extends SceneTree

const MobileDisplay = preload("res://game/mobile_display.gd")
const View = preload("res://game/world_view.gd")
const HUD = preload("res://ui/hud.gd")
const Sim = preload("res://game/simulation.gd")
var failures := 0

func _initialize():
	run.call_deferred()

func check(ok: bool, description: String):
	if ok:return
	failures += 1
	push_error(description)

func run():
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size = Vector2i(2460, 1080)
	var display = MobileDisplay.new()
	root.add_child(display)
	var world = View.new()
	display.mount(root, world)
	var hud = HUD.new()
	root.add_child(hud)
	await process_frame
	var extent = root.get_visible_rect().size
	print("Wide layout: window ", root.size, " · canvas ", extent, " · world ", display.target.size)
	check(absf(extent.x - 1640.0) <= 1.0 and extent.y == 720.0, "wide phone gets the whole expanded logical canvas")
	check(display.target.size == Vector2i(extent) and world.layout_size() == extent, "world buffer preserves viewport aspect and coordinates")
	check(display.image.size.is_equal_approx(extent) and display.image.mouse_filter == Control.MOUSE_FILTER_IGNORE, "world image fills the real window without catching touch")
	hud.set_safe_area(Rect2(Vector2.ZERO,extent), Rect2(45, 0, 2370, 1080), Transform2D(0, Vector2(1.5,1.5), 0, Vector2.ZERO))
	check(absf(hud.safe_margins.x - 30.0) <= 1.0 and absf(hud.safe_margins.z - 30.0) <= 1.0 and absf(hud.layout_size().x - 1580.0) <= 2.0, "camera cutout insets HUD while world keeps the same width")
	for i in range(250):display.sample_frame(1.0/60.0, true)
	check(display.level == 0, "stable 60 FPS keeps initial quality")
	for i in range(160):display.sample_frame(0.028, true)
	check(display.level == 1 and display.target.size.y == 612 and world.layout_size() == extent, "sustained missed frames reduce only world pixels")
	for i in range(160):display.sample_frame(0.028, true)
	check(display.level == 2 and display.target.size.y == 504, "sustained slowdown reaches bounded minimum")
	world.sim = Sim.new()
	world.sim.new_run(44)
	world.sim.paused = true
	world._process(0.0)
	display.target.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.size = Vector2i(984, 432)
	display.resize()
	check(display.target.size.y == 432 and display.target.render_target_update_mode == SubViewport.UPDATE_ONCE, "same-aspect resize repaints paused world")
	world.sim.paused = false
	world._process(0.0)
	check(display.target.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "resumed world keeps rendering after paused resize")
	print("MOBILE DISPLAY: %d failures" % failures)
	quit(0 if failures == 0 else 1)
