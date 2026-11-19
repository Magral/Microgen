extends Node
## Experimental static terrain compositor. Retain geometry for cold tiles and
## close views. Moving entities and water are never drawn into these textures.
const PIXELS_PER_UNIT := 1.5
const PIXEL_BUDGET := 14 * 1024 * 1024
const BLEND_SHADER=preload("res://game/terrain_raster.gdshader")

class Surface extends Node2D:
	var mesh
	func _draw():
		mesh.paint(self)

var entries: Dictionary = {}
var resident_pixels := 0
var rasterized := 0
var _frame := 0
var _blend := ShaderMaterial.new()

func _ready():
	_blend.shader=BLEND_SHADER

func update(chunks: Array,camera: Vector2,physical_zoom: float):
	_frame+=1
	var eligible := physical_zoom<=PIXELS_PER_UNIT
	var candidate: Dictionary = {}
	var nearest := INF
	for chunk in chunks:
		var patch=chunk.node
		if entries.has(patch):
			var entry: Dictionary=entries[patch]
			if patch.visible:entry.used=_frame
			var ready := eligible and bool(entry.ready)
			patch.show_raster(entry.target.get_texture() if ready else null,entry.bounds,_blend if ready else null)
		elif eligible and patch.visible and patch.draw_builds>0 and not patch.mesh.indices.is_empty():
			var distance: float=chunk.bounds.get_center().distance_squared_to(camera)
			if distance<nearest:
				nearest=distance
				candidate=chunk
	if not candidate.is_empty():_bake(candidate.node)

func _bake(patch):
	var geometry: Rect2=patch.geometry_bounds.grow(2.0)
	var bounds := Rect2(geometry.position.floor(),geometry.end.ceil()-geometry.position.floor())
	var size := Vector2i((bounds.size*PIXELS_PER_UNIT).ceil())
	var pixels := size.x*size.y
	# Do not thrash visible textures if a camera covers more than fits.
	while resident_pixels+pixels>PIXEL_BUDGET:
		var oldest: Node2D
		var stamp := _frame
		for other in entries:
			if not other.visible and entries[other].used<stamp:
				oldest=other
				stamp=entries[other].used
		if oldest==null:return
		_remove(oldest)
	var target := SubViewport.new()
	target.disable_3d=true
	target.world_2d=World2D.new()
	target.transparent_bg=true
	target.size=size
	target.render_target_update_mode=SubViewport.UPDATE_ONCE
	add_child(target)
	var surface := Surface.new()
	surface.mesh=patch.mesh
	surface.scale=Vector2(size)/bounds.size
	surface.position=-bounds.position*surface.scale
	target.add_child(surface)
	entries[patch]={"target":target,"bounds":bounds,"pixels":pixels,"used":_frame,"ready":false}
	resident_pixels+=pixels
	RenderingServer.frame_post_draw.connect(_mark_ready.bind(patch,target),CONNECT_ONE_SHOT)

func _mark_ready(patch: Node2D,target: SubViewport):
	if is_instance_valid(patch) and entries.has(patch) and entries[patch].target==target:
		target.render_target_update_mode=SubViewport.UPDATE_DISABLED
		entries[patch].ready=true
		rasterized+=1

func _remove(patch):
	var entry: Dictionary=entries[patch]
	patch.show_raster(null,Rect2(),null)
	entry.target.queue_free()
	resident_pixels-=int(entry.pixels)
	entries.erase(patch)

func clear():
	for patch in entries.keys():_remove(patch)
