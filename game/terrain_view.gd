extends Node2D
# Native canvas commands are recorded once per six-tile patch. Everything here is
# substrate: no physics nodes, gameplay RNG calls, or changes to the map cells.
const World=preload("res://game/world.gd")
const RasterCache=preload("res://game/terrain_raster_cache.gd")
const CHUNK=6
const OVERHANG=114.0
var chunks: Array=[]
var source
var source_seed=-1
var rebuilds=0
var mobile_detail := false
var raster_enabled := OS.has_environment("MICROGEN_TERRAIN_RASTER") or "--terrain-raster-cache" in OS.get_cmdline_user_args()
var raster_cache: Node

# Integer coordinate hashing keeps neighboring patches and new runs repeatable.
static func grain(x: int,y: int,seed_value: int,salt: int=0) -> float:
	var n=posmod(x*73856093+y*19349663+seed_value*83492791+salt*15485863,2147483647)
	n=posmod(n*48271+12820163,2147483647)
	return float(n)/2147483647.0

class Patch:
	extends Node2D
	const Substrate=preload("res://game/substrate_mesh.gd")
	var mesh=Substrate.new()
	var tiles: Array=[]
	var commands: Array=[]
	var draw_builds=0
	var mobile_detail := false
	var raster_texture: Texture2D
	var raster_bounds := Rect2()
	var geometry_bounds := Rect2()
	func prepare_geometry():
		if draw_builds==0:
			_build()
			mesh.bake(commands)
			if not mesh.points.is_empty():
				geometry_bounds=Rect2(mesh.points[0],Vector2.ZERO)
				for point in mesh.points:geometry_bounds=geometry_bounds.expand(point)
			draw_builds+=1
	func intersects(area: Rect2, fallback: Rect2) -> bool:
		if draw_builds==0:return fallback.intersects(area,true)
		return geometry_bounds.has_area() and geometry_bounds.intersects(area,true)
	func show_raster(texture: Texture2D, bounds: Rect2, blend: ShaderMaterial):
		if raster_texture==texture:return
		raster_texture=texture
		raster_bounds=bounds
		material=blend
		queue_redraw()
	func _draw():
		if raster_texture!=null:
			draw_texture_rect(raster_texture,raster_bounds,false)
			return
		prepare_geometry()
		mesh.paint(self)
	func _polygon(points: PackedVector2Array,color: Color):
		commands.append({"kind":0,"points":points,"color":color})
	func _line(points: PackedVector2Array,color: Color,width: float):
		commands.append({"kind":1,"points":points,"color":color,"width":width})
	func _dot(p: Vector2,radius: float,color: Color):
		commands.append({"kind":2,"p":p,"radius":radius,"color":color})
	func _blob(p: Vector2,r: float,color: Color,phase: float,stretch: Vector2=Vector2.ONE):
		var points=PackedVector2Array()
		var samples = 12 if mobile_detail else 24
		for i in range(samples):
			var a=i*TAU/samples
			var radius=r*(1+sin(a*5+phase)*0.065+sin(a*3-phase)*0.095)
			points.append(p+Vector2.from_angle(a)*radius*stretch)
		_polygon(points,color)
	func _build():
		# Floor first so overhanging tissue always casts a coherent solid silhouette.
		for t in tiles:
			if not t.wall:_bed(t)
		for t in tiles:
			if t.wall:_wall(t)
	func _wall(t: Dictionary):
		var p: Vector2=t.p
		var phase: float=t.phase
		var warm: bool=t.biome==1
		var tissue=Color("294b42") if warm else Color("204650")
		var middle=Color("365b4c") if warm else Color("2b5560")
		var light=Color("7b9d73") if warm else Color("71a6a6")
		# The offset black skirt gives the wall thickness into the fluid, while
		# connected broad lobes avoid a grid of independent circular boulders.
		_blob(p+Vector2(9,14),80,Color(0.012,0.038,0.048,0.58),phase,Vector2(1.02,0.94))
		if not mobile_detail:_blob(p+Vector2(3,5),77,Color("102d32") if not warm else Color("172f2b"),phase)
		var shape=PackedVector2Array()
		var world_shape=PackedVector2Array()
		var center=p+Vector2(-3,-7)
		for i in range(24):
			var a=i*TAU/24.0
			var point=Vector2.from_angle(a)*(1+sin(a*5+phase)*0.065+sin(a*3-phase)*0.095)
			shape.append(point);world_shape.append(center+point*72)
		commands.append({"kind":3,"points":world_shape,"shape":shape,"p":center,"radius":72.0,"body":middle,"edge":light,"shadow":tissue.darkened(0.45),"rich":not mobile_detail})
		# A narrow broken rim follows only the lit upper-left surface.
		var rim=PackedVector2Array()
		for i in range(13):
			var a=2.95+float(i)*0.155
			var radius=72*(1+sin(a*5+phase)*0.065+sin(a*3-phase)*0.095)
			rim.append(p+Vector2(-3,-7)+Vector2.from_angle(a)*radius)
		_line(rim,Color(light,0.27),4.3)
		_line(rim,Color(light,0.34),1.1)
		if mobile_detail:return
		# Shallow capillary furrows arc through the same cellular tissue.
		for branch in range(2):
			var vein=PackedVector2Array()
			for i in range(9):
				var u=float(i)/8
				vein.append(p+Vector2(-49+u*84,-19+branch*28+sin(u*3.8+phase+branch)*12))
			_line(vein,Color(0.008,0.035,0.038,0.45),3.3)
			_line(vein,Color(light,0.12),0.8)
		# Asymmetric pore colonies; dark recess and a tiny moist lower lip.
		for i in range(5):
			var a=phase*0.7+i*2.399
			var q=p+Vector2.from_angle(a)*(14+float(i)*6.4)+Vector2(-7,-9)
			var r=2.6+fmod(phase+i*1.7,3.0)
			_dot(q+Vector2(0,1.5),r+1.3,Color(light,0.19))
			_dot(q,r,Color(0.006,0.026,0.03,0.75))
			_dot(q+Vector2(-0.8,-0.8),r*0.47,Color(0.01,0.035,0.038,0.6))
	func _bed(t: Dictionary):
		var phase: float=t.phase
		var p: Vector2=t.p
		var warm: bool=t.biome==1
		# Three-tile domain fields put growth into colonies instead of confetti.
		if t.growth<0.43:
			var pigment=Color(0.30,0.36,0.13,0.12) if warm else Color(0.10,0.31,0.32,0.12)
			_blob(p+Vector2(-13,10),57,pigment,phase,Vector2(1.2,0.72))
			if mobile_detail:return
			_blob(p+Vector2(6,9),35,Color(pigment,pigment.a*0.8),phase+1,Vector2(1.1,0.64))
			# Sinuous, tapering collagen filaments lie along the nutrient bed.
			for strand in range(3):
				var points=PackedVector2Array()
				for i in range(13):
					var u=float(i)/12
					points.append(p+Vector2(-48+u*94,(strand-1)*10+sin(u*4.5+phase)*10+sin(u*8+phase)*3))
				_line(points,Color(0.37,0.47,0.24,0.13) if warm else Color(0.23,0.49,0.46,0.14),1.2 if strand==1 else 0.65)
			for i in range(4):
				var a=phase+i*2.4
				var q=p+Vector2.from_angle(a)*float(10+i*7)
				_blob(q,3.0+float(i)*0.8,Color(0.47,0.49,0.19,0.20) if warm else Color(0.28,0.48,0.41,0.19),a,Vector2(1.6,0.7))
		# Rare long double fibrils are molecular structures, never collectible icons.
		if t.detail<0.095:
			var strand_a=PackedVector2Array()
			var strand_b=PackedVector2Array()
			var angle=phase*0.19
			for i in range(25):
				var u=float(i)/24
				var center=Vector2((u-0.5)*86,sin(u*3+phase)*11)
				var offset=Vector2(0,sin(u*TAU*2.3+phase)*6)
				strand_a.append(p+(center+offset).rotated(angle))
				strand_b.append(p+(center-offset).rotated(angle))
				if i%3==0:_line(PackedVector2Array([strand_a[i],strand_b[i]]),Color(0.30,0.56,0.49,0.18),0.8)
			_line(strand_a,Color(0.36,0.62,0.55,0.23),1.15)
			_line(strand_b,Color(0.50,0.56,0.34,0.20),1.15)

func update_world(world,camera: Vector2,viewport: Vector2,zoom: float):
	if source!=world or source_seed!=world.seed_value:
		if raster_cache!=null:raster_cache.clear()
		for chunk in chunks:chunk.node.queue_free()
		chunks.clear()
		source=world
		source_seed=world.seed_value
		rebuilds+=1
		for cy in range(0,World.H,CHUNK):
			for cx in range(0,World.W,CHUNK):
				var patch=Patch.new()
				patch.mobile_detail=mobile_detail
				for y in range(cy,mini(cy+CHUNK,World.H)):
					for x in range(cx,mini(cx+CHUNK,World.W)):
						var p=Vector2(x+0.5,y+0.5)*World.TILE
						patch.tiles.append({"p":p,"biome":world.biome(p),"wall":world.cells[y*World.W+x]==1,"phase":grain(x,y,source_seed)*TAU,"growth":grain(x/3,y/3,source_seed,1),"detail":grain(x,y,source_seed,2)})
				add_child(patch)
				chunks.append({"node":patch,"bounds":Rect2(Vector2(cx,cy)*World.TILE,Vector2.ONE*CHUNK*World.TILE).grow(OVERHANG)})
	position=viewport*Vector2(0.5,0.51)-camera*zoom
	scale=Vector2.ONE*zoom
	# The screen rectangle uses the same upward camera bias as the transform.
	# Patch bounds already include their wall overhang and antialias geometry.
	var visible_area=Rect2(-position/zoom,viewport/zoom)
	for chunk in chunks:
		var patch=chunk.node
		patch.visible=patch.intersects(visible_area,chunk.bounds)
	if raster_enabled and DisplayServer.get_name()!="headless":
		if raster_cache==null:
			raster_cache=RasterCache.new()
			add_child(raster_cache)
		var physical_scale := get_viewport().get_final_transform().get_scale().abs()
		raster_cache.update(chunks,camera,zoom*maxf(physical_scale.x,physical_scale.y))
	elif raster_cache!=null:
		raster_cache.clear()
