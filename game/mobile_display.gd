extends Node
## Render the water and organisms separately. The window still draws interface
## text and receives touch at its usual resolution.
const WORLD_HEIGHTS = [540.0, 432.0, 336.0, 270.0]
const DETAIL_LIMITS = [2, 1, 0, 0]
const FRAME_WINDOW = 2.0
var target: SubViewport
var image: TextureRect
var root_window: Window
var world_view
var level := 0
var interval := 0.0
var slow_windows := 0
var frame_times := PackedFloat32Array()
var frame_summary := ""
var simulation_us := 0
var simulation_samples := 0
var last_draw_us := 0

func mount(window: Window, view: Node2D):
	root_window = window
	world_view = view
	target = SubViewport.new()
	target.disable_3d = true
	target.world_2d = World2D.new()
	target.gui_disable_input = true
	target.size_2d_override_stretch = true
	target.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(target)
	target.add_child(view)
	image = TextureRect.new()
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.texture = target.get_texture()
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_window.size_changed.connect(resize)
	resize()

func resize():
	var extent = root_window.get_visible_rect().size
	if extent.x < 2.0 or extent.y < 2.0:return
	var logical = Vector2i(extent.round())
	var height = minf(WORLD_HEIGHTS[level], float(root_window.size.y))
	var pixel_size = Vector2i((extent * (height / extent.y)).round()).max(Vector2i(2, 2))
	target.size_2d_override = logical
	target.size = pixel_size
	world_view.canvas_extent = Vector2(logical)
	world_view.detail_limit = DETAIL_LIMITS[level]
	world_view.mobile_detail = true
	world_view.fluid.mobile_detail = true
	world_view.queue_redraw()
	# A resized texture must get a fresh frame even with the game on pause.
	if world_view.paused_frame_ready:
		world_view.paused_frame_ready = false
		target.render_target_update_mode = SubViewport.UPDATE_ONCE

func record_simulation(usec: int):
	simulation_us += usec
	simulation_samples += 1

func sample_frame(seconds: float, active: bool):
	if not active:
		interval = 0.0
		slow_windows = 0
		frame_times.clear()
		simulation_us = 0
		simulation_samples = 0
		last_draw_us = world_view.draw_us
		return
	if seconds <= 0.0:return
	interval += seconds
	frame_times.append(seconds)
	if interval < FRAME_WINDOW:return
	frame_times.sort()
	var p90 = frame_times[int((frame_times.size() - 1) * 0.90)]
	var p95 = frame_times[int((frame_times.size() - 1) * 0.95)]
	var fps = frame_times.size() / interval
	var game_ms = float(simulation_us) / maxf(1.0, simulation_samples) / 1000.0
	var draw_ms = float(world_view.draw_us - last_draw_us) / frame_times.size() / 1000.0
	last_draw_us = world_view.draw_us
	frame_summary = "%.0f FPS · 95%% кадров до %.1f мс · Мир %d px · Логика %.1f мс · Динамика CPU %.1f мс" % [fps, p95 * 1000.0, target.size.y, game_ms, draw_ms]
	simulation_us = 0
	simulation_samples = 0
	slow_windows = slow_windows + 1 if fps < 57.0 and p90 > 0.0185 else 0
	# Sustained misses lower quality. A severe drop skips the second window.
	if (slow_windows >= 2 or fps < 35.0) and level < WORLD_HEIGHTS.size() - 1:
		level += 1
		slow_windows = 0
		resize()
	interval = 0.0
	frame_times.clear()
