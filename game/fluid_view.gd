extends Node2D
const Optics=preload("res://game/water_optics.gd")
const PARTICLE_COUNT=100
const WAKE_CAP=96
const DEPTH_COUNT=8
var particles: Array=[]
var wakes: Array=[]
var depths: Array=[]
var clock=0.0
var paused=false
var zoom=1.0
var camera=Vector2.ZERO
var viewport_size=Vector2(1280,720)
var seed_value=-1
var background: ColorRect
var material_instance: ShaderMaterial
var tick=0
var flow_evaluations=0
var haze: Texture2D
var mobile_detail := false

# The very near optical plane veils only a few pixels, after organisms, so the
# creature really sits inside the water rather than above a wallpaper.
class Surface:
	extends Node2D
	var fluid
	func _draw():
		if fluid==null:return
		for item in fluid.particles:
			if item.layer!=2:continue
			var p=fluid.screen_depth(item.pos,1.18)
			var r=float(item.r)*5.5
			if not Rect2(Vector2.ZERO, fluid.viewport_size).grow(r).has_point(p):continue
			draw_texture_rect(fluid.haze,Rect2(p-Vector2.ONE*r,Vector2.ONE*r*2),false,Color(0.48,0.87,0.85,0.055))
func _ready():
	haze=Optics.haze_texture()
	background=ColorRect.new()
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent=true
	material_instance=ShaderMaterial.new()
	material_instance.shader=preload("res://assets/liquid.gdshader")
	material_instance.set_shader_parameter("flow_map",Optics.flow_texture())
	background.material=material_instance
	add_child(background)
static func current_at(p: Vector2,time: float) -> Vector2:
	return Vector2(sin(p.y*0.0019+time*0.23)+cos(p.x*0.0011-p.y*0.0008-time*0.12),cos(p.x*0.0018-time*0.18)-sin(p.y*0.001+time*0.11))*12.0
func reset(value: int,center: Vector2,size: Vector2):
	if is_instance_valid(material_instance):
		material_instance.set_shader_parameter("mobile_detail",mobile_detail)
	seed_value=value;camera=center;viewport_size=size
	clock=0.0;tick=0;flow_evaluations=0
	wakes=[];particles=[];depths=[]
	var rng=RandomNumberGenerator.new()
	rng.seed=value+710917
	for i in range(PARTICLE_COUNT):
		if mobile_detail and i % 3 == 1:continue
		var layer=0 if i<60 else (1 if i<90 else 2)
		var depth=[0.55,0.88,1.18][layer]
		var p=center+Vector2(rng.randf_range(-size.x*0.65/(zoom*depth),size.x*0.65/(zoom*depth)),rng.randf_range(-size.y*0.7/(zoom*depth),size.y*0.7/(zoom*depth)))
		particles.append({"pos":p,"r":rng.randf_range(0.9,2.5),"phase":rng.randf()*TAU,"depth":depth,"layer":layer,"flow":current_at(p,clock)})
	for i in range(DEPTH_COUNT):
		var contour=PackedVector2Array()
		var phase=rng.randf()*TAU
		for j in range(32):
			var angle=j*TAU/32.0
			contour.append(Vector2.from_angle(angle)*(1+0.12*sin(angle*3+phase)+0.07*cos(angle*5-phase)))
		var outline=contour.duplicate()
		outline.append(outline[0])
		depths.append({"line":outline,"pos":center+Vector2(rng.randf_range(-size.x,size.x),rng.randf_range(-size.y,size.y))/(zoom*0.38),"r":rng.randf_range(60,150),"phase":phase,"shape":contour})
func update(dt: float,sim,size: Vector2,view_zoom: float=1.0):
	zoom=maxf(0.2,view_zoom)
	if seed_value!=int(sim.world.seed_value):reset(int(sim.world.seed_value),sim.player,size)
	camera=sim.player;viewport_size=size;paused=sim.paused
	dt=clampf(dt,0.0,0.1)
	if not paused:
		clock+=dt;tick+=1
		for i in range(particles.size()):
			var item=particles[i]
			# A staggered current sample each six frames is visually continuous but
			# removes repeated trigonometry for most motes in every frame.
			if (i+tick)%6==0:
				item.flow=current_at(item.pos,clock)
				flow_evaluations+=1
			item.pos+=item.flow*dt*item.depth
			var relative=item.pos-camera
			var span=size*Vector2(0.65,0.7)/(zoom*item.depth)
			item.pos=camera+Vector2(wrapf(relative.x,-span.x,span.x),wrapf(relative.y,-span.y,span.y))
		for i in range(wakes.size()-1,-1,-1):
			var wake = wakes[i]
			wake.life -= dt
			if wake.life <= 0.0:
				wakes.remove_at(i)
				continue
			if (i + tick) % 4 == 0 or not wake.has("flow"):
				wake.flow = current_at(wake.pos,clock)
			wake.pos += wake.flow * dt * 0.35
	# Wrapping is camera-dependent, so it also works after paused resizing.
	for item in depths:
		var span=size*Vector2(0.8,0.85)/(zoom*0.38)
		var relative=item.pos-camera
		item.pos=camera+Vector2(wrapf(relative.x,-span.x,span.x),wrapf(relative.y,-span.y,span.y))
	if is_instance_valid(background):
		background.size=size
		material_instance.set_shader_parameter("fluid_time",clock)
		material_instance.set_shader_parameter("world_origin",camera-size*Vector2(0.5,0.51)/zoom)
		material_instance.set_shader_parameter("viewport_size",size/zoom)
		material_instance.set_shader_parameter("boundary_phase",sim.world.boundary_phase)
	queue_redraw()
func emit_wake(p: Vector2,velocity: Vector2,radius: float):
	if paused or velocity.length()<10:return
	if wakes.size()>=WAKE_CAP:wakes.pop_front()
	wakes.append({"pos":p,"angle":velocity.angle(),"r":radius,"life":1.8,"flow":current_at(p,clock)})
func screen(p: Vector2) -> Vector2:
	return (p-camera)*zoom+viewport_size*Vector2(0.5,0.51)
func screen_depth(p: Vector2,depth: float) -> Vector2:
	return (p-camera)*zoom*depth+viewport_size*Vector2(0.5,0.51)
func _draw():
	var frame := Rect2(Vector2.ZERO, viewport_size)
	# Low-contrast far organisms and defocused lenses create depth at fixed count.
	for item in depths:
		draw_set_transform(Vector2.ZERO)
		var p=screen_depth(item.pos,0.38)
		var r=float(item.r)*(0.9+sin(clock*0.12+item.phase)*0.06)
		if not frame.grow(r*1.6).has_point(p):continue
		draw_texture_rect(haze,Rect2(p-Vector2(r*1.5,r),Vector2(r*3,r*2)),false,Color(0.08,0.32,0.36,0.20))
		draw_set_transform(p,float(item.phase)+sin(clock*0.07+item.phase)*0.05,Vector2(r,r*0.7))
		draw_colored_polygon(item.shape,Color(0.015,0.085,0.11,0.22))
		draw_polyline(item.line,Color(0.15,0.48,0.48,0.08),0.02,true)
	draw_set_transform(Vector2.ZERO)
	for wake in wakes:
		var age=1.0-wake.life/1.8
		var opacity=0.22*pow(1.0-age,2)
		var p = screen(wake.pos)
		if not frame.grow(float(wake.r)*zoom*2.5).has_point(p):continue
		draw_set_transform(p,wake.angle,Vector2(0.4+age*0.65,1.0+age*1.15))
		draw_arc(Vector2.ZERO,wake.r*zoom*(0.65+age*0.5),PI*0.4,PI*1.6,22,Color(0.45,0.8,0.76,opacity),1.3,true)
	draw_set_transform(Vector2.ZERO)
	for item in particles:
		var p=screen_depth(item.pos,float(item.depth))
		var r=float(item.r)
		if not frame.grow(r*8.0).has_point(p):continue
		if item.layer==0:
			draw_circle(p,r*0.75,Color(0.53,0.8,0.74,0.15))
		elif item.layer==1:
			draw_texture_rect(haze,Rect2(p-Vector2.ONE*r*3,Vector2.ONE*r*6),false,Color(0.50,0.87,0.81,0.22))
			draw_line(p-item.flow.normalized()*5,p,Color(0.68,0.9,0.82,0.23),0.9,true)
		else:
			draw_texture_rect(haze,Rect2(p-Vector2.ONE*r*7,Vector2.ONE*r*14),false,Color(0.57,0.9,0.87,0.09))
