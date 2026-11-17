extends Node2D
# Static tissue formations retain native canvas commands. Only fluid and organisms
# need rebuilding each frame; offscreen chunks do not submit any geometry.
const World=preload("res://game/world.gd")
const CHUNK=6
var chunks: Array=[]
var source
var source_seed=-1
var rebuilds=0
class Patch:
	extends Node2D
	var tiles: Array=[]
	func _draw():
		for t in tiles:
			if t.biome==1:draw_circle(t.p,85,Color(0.16,0.23,0.10,0.12),false,12)
			if t.wall:
				var color=Color("294536") if t.biome==1 else Color("183640")
				_blob(t.p,110*0.69,color,t.phase*0.3,0.6)
				_blob(t.p+Vector2(7,-8),110*0.48,Color(color,0.45),t.phase,0.3)
			elif t.phase<11:draw_arc(t.p,22+t.phase,0.3,4.7,18,Color(0.4,0.65,0.6,0.08),1.5,true)
	func _blob(p: Vector2,r: float,col: Color,phase: float,lobes: float):
		var points=PackedVector2Array()
		for i in range(24):
			var a=i*TAU/24.0
			points.append(p+Vector2.from_angle(a)*r*(1+sin(a*5+phase)*0.11*lobes+sin(a*3-phase)*0.16*lobes))
		draw_colored_polygon(points,col)
		points.append(points[0])
		draw_polyline(points,Color(col,col.a*0.4),1.6,true)
func update_world(world,camera: Vector2,viewport: Vector2,zoom: float):
	if source!=world or source_seed!=world.seed_value:
		for chunk in chunks:chunk.node.queue_free()
		chunks.clear()
		source=world
		source_seed=world.seed_value
		rebuilds+=1
		for cy in range(0,World.H,CHUNK):
			for cx in range(0,World.W,CHUNK):
				var patch=Patch.new()
				for y in range(cy,mini(cy+CHUNK,World.H)):
					for x in range(cx,mini(cx+CHUNK,World.W)):
						var p=Vector2(x+0.5,y+0.5)*World.TILE
						patch.tiles.append({"p":p,"biome":world.biome(p),"wall":world.cells[y*World.W+x]==1,"phase":posmod(x*157+y*977+world.seed_value,100)})
				add_child(patch)
				chunks.append({"node":patch,"bounds":Rect2(Vector2(cx,cy)*World.TILE,Vector2.ONE*CHUNK*World.TILE).grow(85)})
	position=viewport*Vector2(0.5,0.51)-camera*zoom
	scale=Vector2.ONE*zoom
	var visible_area=Rect2(camera-viewport/(2*zoom),viewport/zoom).grow(100)
	for chunk in chunks:chunk.node.visible=chunk.bounds.intersects(visible_area)
