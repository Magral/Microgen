extends Node2D
const PARTICLE_COUNT=100
const WAKE_CAP=96
var particles: Array=[]
var wakes: Array=[]
var clock=0.0
var paused=false
var zoom=1.0
var camera=Vector2.ZERO
var viewport_size=Vector2(1280,720)
var seed_value=-1
var background: ColorRect
var material_instance: ShaderMaterial

func _ready():
	background=ColorRect.new()
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.show_behind_parent=true
	material_instance=ShaderMaterial.new()
	material_instance.shader=preload("res://assets/liquid.gdshader")
	background.material=material_instance
	add_child(background)

static func current_at(p: Vector2,time: float) -> Vector2:
	return Vector2(sin(p.y*0.0019+time*0.23)+cos(p.x*0.0011-p.y*0.0008-time*0.12),cos(p.x*0.0018-time*0.18)-sin(p.y*0.001+time*0.11))*12.0

func reset(value: int,center: Vector2,size: Vector2):
	seed_value=value
	camera=center
	viewport_size=size
	clock=0.0
	wakes=[]
	particles=[]
	var rng=RandomNumberGenerator.new()
	rng.seed=value+710917
	for i in range(PARTICLE_COUNT):
		particles.append({"pos":center+Vector2(rng.randf_range(-size.x*0.65/zoom,size.x*0.65/zoom),rng.randf_range(-size.y*0.7/zoom,size.y*0.7/zoom)),"r":rng.randf_range(0.8,2.5),"phase":rng.randf()*TAU,"depth":rng.randf_range(0.35,1.0)})

func update(dt: float,sim,size: Vector2,view_zoom: float=1.0):
	zoom=maxf(0.2,view_zoom)
	if seed_value!=int(sim.world.seed_value): reset(int(sim.world.seed_value),sim.player,size)
	camera=sim.player
	viewport_size=size
	paused=sim.paused
	dt=clampf(dt,0.0,0.1)
	if not paused:
		clock+=dt
		for item in particles:
			item.pos+=current_at(item.pos,clock)*dt*item.depth
			var relative=item.pos-camera
			item.pos=camera+Vector2(wrapf(relative.x,-size.x*0.65/zoom,size.x*0.65/zoom),wrapf(relative.y,-size.y*0.7/zoom,size.y*0.7/zoom))
		for i in range(wakes.size()-1,-1,-1):
			wakes[i].life-=dt
			wakes[i].pos+=current_at(wakes[i].pos,clock)*dt*0.35
			if wakes[i].life<=0: wakes.remove_at(i)
	if is_instance_valid(background):
		background.size=size
		material_instance.set_shader_parameter("fluid_time",clock)
		material_instance.set_shader_parameter("world_origin",camera-size*Vector2(0.5,0.51)/zoom)
		material_instance.set_shader_parameter("viewport_size",size/zoom)
		material_instance.set_shader_parameter("boundary_phase",sim.world.boundary_phase)
	queue_redraw()

func emit_wake(p: Vector2,velocity: Vector2,radius: float):
	if paused or velocity.length()<10: return
	if wakes.size()>=WAKE_CAP: wakes.pop_front()
	wakes.append({"pos":p,"angle":velocity.angle(),"r":radius,"life":1.8})

func screen(p: Vector2) -> Vector2:
	return (p-camera)*zoom+viewport_size*Vector2(0.5,0.51)

func _draw():
	for wake in wakes:
		var age=1.0-wake.life/1.8
		var opacity=0.14*pow(1.0-age,2)
		draw_set_transform(screen(wake.pos),wake.angle,Vector2(0.4+age*0.65,1.0+age*1.15))
		draw_arc(Vector2.ZERO,wake.r*zoom*(0.65+age*0.5),PI*0.4,PI*1.6,22,Color(0.45,0.8,0.76,opacity),1.3,true)
	draw_set_transform(Vector2.ZERO)
	for item in particles:
		var p=screen(item.pos)
		var col=Color(0.53,0.8,0.74,0.10+item.depth*0.08)
		draw_circle(p,item.r,col)
		if item.r>2.0:
			var flow=current_at(item.pos,clock).normalized()
			draw_line(p-flow*7,p,Color(col,0.08),0.8,true)
