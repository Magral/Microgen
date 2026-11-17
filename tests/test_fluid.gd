extends SceneTree
const Fluid = preload("res://game/fluid_view.gd")
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
func check(ok: bool,text: String):
	if not ok:
		failures+=1
		push_error(text)
func _initialize(): call_deferred("run")
func run():
	var sim=WaterSim.new()
	var fluid=Fluid.new()
	root.add_child(fluid)
	fluid.update(0.016,sim,Vector2(1280,720))
	var before=fluid.particles[0].pos
	for i in range(60): fluid.update(1.0/60,sim,Vector2(1280,720))
	check(fluid.particles[0].pos.distance_to(before)>1.0,"suspended matter drifts")
	var a=Fluid.current_at(Vector2(100,100),1.0)
	var b=Fluid.current_at(Vector2(101,100),1.0)
	check(a.length()<50 and a.distance_to(b)<1,"coherent bounded currents")
	for i in range(300): fluid.emit_wake(Vector2(400+i,300),Vector2(145,0),34)
	check(fluid.wakes.size()<=Fluid.WAKE_CAP,"wake history bounded")
	sim.paused=true
	var time=fluid.clock
	before=fluid.particles[0].pos
	fluid.update(1.0,sim,Vector2(1280,720))
	check(fluid.clock==time and fluid.particles[0].pos==before,"pause freezes liquid")
	sim.paused=false
	for i in range(160): fluid.update(1.0/60,sim,Vector2(1280,720))
	check(fluid.wakes.is_empty(),"wake dissipates")
	check(fluid.particles.size()==Fluid.PARTICLE_COUNT,"particle count stays bounded")
	fluid.queue_free()
	await process_frame
	print("FLUID: %d failures" % failures)
	quit(0 if failures==0 else 1)
