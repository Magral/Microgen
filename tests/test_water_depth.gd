extends SceneTree
const Fluid=preload("res://game/fluid_view.gd")
const Optics=preload("res://game/water_optics.gd")
class WaterWorld:
	extends RefCounted
	var seed_value=91
	var boundary_phase=0.4
class WaterSim:
	extends RefCounted
	var world=WaterWorld.new()
	var player=Vector2(400,300)
	var paused=false
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func run():
	seed(113);var expected=randf();seed(113)
	var water=Fluid.new()
	root.add_child(water)
	var sim=WaterSim.new()
	water.update(0.016,sim,Vector2(1280,720),3.0)
	check(randf()==expected,"water creation leaves gameplay RNG untouched")
	for item in water.depths:
		check(not Geometry2D.triangulate_polygon(item.shape).is_empty(),"deep silhouette has valid nonduplicate polygon vertices")
		check(item.line[0]==item.line[-1],"deep silhouette membrane closes without a second polygon vertex")
	var texture=Optics.flow_texture()
	check(texture==Optics.flow_texture() and Optics.generations==1,"shared optical texture generated once")
	check(texture.get_width()==256 and texture.get_height()==256,"optical atlas stays bounded")
	var far_before=water.screen_depth(Vector2(500,400),0.55)
	var near_before=water.screen_depth(Vector2(500,400),1.18)
	water.camera+=Vector2(10,0)
	check(is_equal_approx(far_before.x-water.screen_depth(Vector2(500,400),0.55).x,16.5),"far suspended matter has reduced camera parallax")
	check(is_equal_approx(near_before.x-water.screen_depth(Vector2(500,400),1.18).x,35.4),"near lens moves faster than tissue plane")
	for i in range(60):water.update(1.0/60,sim,Vector2(1280,720),3.0)
	check(water.flow_evaluations<=1100,"staggered currents avoid per-particle trig every frame")
	for zoom in [0.9,3.0,1.7]:
		sim.player+=Vector2(1700,-900)
		water.update(0.016,sim,Vector2(1280,720),zoom)
		for mote in water.particles:
			var p=water.screen_depth(mote.pos,float(mote.depth))
			check(p.x>= -200 and p.x<=1500 and p.y>= -200 and p.y<=950,"growth and camera jumps wrap depth layers around viewport")
	sim.paused=true
	var time=water.clock
	var first=water.particles[0].pos
	water.update(0.5,sim,Vector2(1280,720),1.7)
	check(water.clock==time and water.particles[0].pos==first,"pause freezes water and depth motion")
	sim.world.seed_value=92
	water.update(0.0,sim,Vector2(1280,720),1.7)
	check(water.depths.size()==Fluid.DEPTH_COUNT and water.particles.size()==Fluid.PARTICLE_COUNT,"new run replaces bounded depth collections")
	check(water.wakes.is_empty() and water.clock==0,"new seed clears old wakes and optical time")
	water.queue_free();await process_frame
	print("WATER DEPTH: %d failures"%failures)
	quit(0 if failures==0 else 1)
