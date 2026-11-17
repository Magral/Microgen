extends SceneTree
const View=preload("res://game/world_view.gd")
const Art=preload("res://game/reward_art.gd")
const Sim=preload("res://game/simulation.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func old_organs(e: Dictionary) -> Dictionary:
	var organs={}
	if e.kind=="spitter":organs.infection=1
	if e.kind in ["boss","miniboss"]:organs.tentacle=2;organs.spikes=2
	if int(e.variant)==1:organs.armor=1
	if int(e.variant)==2:organs.speed=1
	for mutation in e.get("traits",[]):
		var id={"shell":"armor","swift":"speed","regen":"regen","toxic":"acid","spores":"infection"}.get(mutation,"")
		if id!="":organs[id]=2
	return organs
func run():
	var view=View.new()
	var sim=Sim.new();sim.new_run(510)
	view.sim=sim
	var enemy={"id":992,"kind":"miniboss","variant":1,"traits":["shell","swift","regen","toxic","spores"],"pos":sim.player,"hp":10.0,"max_hp":100.0,"r":2.0}
	check(view.enemy_organs(enemy)==old_organs(enemy),"cache preserves organ recipe")
	view.enemy_organs(enemy)
	check(view.organ_cache_hits==1,"unchanged recipe hits cache")
	enemy.traits=["spores"]
	check(view.enemy_organs(enemy)==old_organs(enemy),"traits invalidate organ recipe")
	sim.enemies=[];view._prune_organ_cache()
	check(view.organ_cache.is_empty(),"despawn prunes cache next frame")
	check(not view.can_mark_absorbable({"hp":1,"max_hp":100,"kind":"boss"}),"boss cannot receive absorption marker")
	check(view.can_mark_absorbable(enemy)==sim.interaction(enemy).eligible,"nearby weakened miniboss follows size eligibility")
	enemy.hp=0
	check(not view.can_mark_absorbable(enemy),"dead amoeba cannot receive absorption marker")
	enemy.hp=16
	check(not view.can_mark_absorbable(enemy),"miniboss above 15 percent cannot receive marker")
	enemy.hp=10;enemy.pos=sim.player+Vector2(10000,0)
	check(not view.can_mark_absorbable(enemy),"distant foe culled before interaction")
	check(Art.contour(1,10,0,0)!=Art.contour(2,10,0,0) and Art.contour(2,10,0,0)!=Art.contour(3,10,0,0),"reward rarity has distinct silhouettes")
	enemy.traits=["shell","swift","regen","toxic","spores"]
	var count=80000
	var start=Time.get_ticks_usec()
	for i in range(count):old_organs(enemy)
	var original=Time.get_ticks_usec()-start
	start=Time.get_ticks_usec()
	for i in range(count):view.enemy_organs(enemy)
	var cached=Time.get_ticks_usec()-start
	print("ORGAN CACHE MICROBENCH: %d calls, old %dus cached %dus (%.2fx)"%[count,original,cached,float(original)/maxi(1,cached)])
	view.fluid.free();view.terrain.free();view.water_surface.free();view.free()
	print("REWARD VIEW: %d failures"%failures)
	quit(0 if failures==0 else 1)
