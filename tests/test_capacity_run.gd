extends SceneTree
const Build=preload("res://core/build_model.gd")
const Equipment=preload("res://core/organism_equipment.gd")
const Catalog=preload("res://core/catalog.gd")
const Sim=preload("res://game/simulation.gd")
var checks=0
var failures=0
func check(ok: bool,label: String):
	checks+=1
	if not ok:failures+=1;push_error(label)
func expansions(sim) -> Array:
	return sim.pickups.filter(func(p):return p.type in ["body_extension","stock_extension"])
func _initialize():
	var b=Build.new()
	b.from_dict({"organ_capacity":4,"organs":{"tentacle":1,"acid":1}})
	check(not b.apply("spikes"),"full cell budget rejects another kind")
	check(b.has_method("used_organ_cells") and b.has_method("can_fit"),"capacity API exists")
	if b.has_method("used_organ_cells"):_capacity_cases()
	_run_cases()
	print("Capacity run: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
func _capacity_cases():
	var b=Build.new()
	b.organ_capacity=4
	check(b.can_fit("tentacle") and b.apply("tentacle") and b.apply("acid"),"exact fit accepts two large organs")
	check(b.used_organ_cells()==4 and not b.can_fit("spikes"),"cell count and excess preflight")
	check(b.apply("tentacle") and b.used_organ_cells()==4,"rank upgrades use no additional cells")
	var before=b.to_dict()
	check(not b.can_fit("devour","acid") and not b.apply("devour","acid",3) and b.to_dict()==before,"oversize replacement rolls back all state")
	check(b.can_fit("spikes","acid") and b.apply("spikes","acid",2) and b.used_organ_cells()==3,"smaller replacement succeeds")
	b.extra_organ_cells=1
	check(b.used_organ_cells()==4 and not b.apply("pulse"),"duplicate instance cells consume capacity")
	var restored=Build.new();restored.from_dict(b.to_dict())
	check(restored.to_dict()==b.to_dict() and restored.used_organ_cells()==4,"capacity and duplicate cells serialize")
	restored.from_dict({})
	check(restored.organ_capacity==0 and restored.extra_organ_cells==0,"old save capacity defaults reset")
	var legacy=Build.new();legacy.unlocked=Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys()
	for id in ["tentacle","acid","devour","electric","barrier","division"]:check(legacy.apply(id),"legacy six-kind acceptance "+id)
	check(not legacy.apply("spikes") and legacy.can_fit("spikes","acid"),"legacy count limit and replacement")
	var roomy=Build.new();roomy.organ_capacity=30;roomy.unlocked=legacy.unlocked.duplicate()
	for id in Catalog.ORGANS:check(roomy.apply(id),"cell capacity permits kinds beyond six "+id)
	var roomy_restored=Build.new();roomy_restored.from_dict(roomy.to_dict())
	check(roomy_restored.organs==roomy.organs,"cell mode restores more than six kinds")
	for id in ["armor","regen","speed","magnet"]:check(roomy.apply(id),"four adaptations remain available")
	check(not roomy.apply("metabolism"),"fifth adaptation still rejected")
	for id in Catalog.ORGANS:
		var one=Build.new();one.organs[id]=1
		check(one.used_organ_cells()==Equipment.cell_cost(id),"cost agrees with family equipment "+id)
func _run_cases():
	var a=Sim.new();a.new_run(901)
	var b=Sim.new();b.new_run(901)
	var loot=expansions(a)
	check(loot.size()==2,"new run has two discoverable extensions")
	check(loot==expansions(b),"same seed gives same extension types positions and ids")
	for item in loot:
		check(a.world.walkable(item.pos,7) and a.world.reachable(item.pos),"extension walkable and reachable")
		check(item.pos.distance_to(a.world.start)>=500,"extension needs exploration")
		check(a.world.nutrients.any(func(n):return n.pos==item.pos),"extension uses a nutrient position")
		check(not a.pickups.any(func(p):return p.id!=item.id and p.pos.distance_to(item.pos)<1),"extension replaces nutrient without overlap")
	if loot.size()==2:check(loot[0].pos.distance_to(loot[1].pos)>=220,"extensions spaced apart")
	var capped=Sim.new();capped.new_run(901)
	capped.pickups=expansions(capped)
	for i in range(598):capped.pickups.append({"pos":capped.player,"type":"dna","amount":1,"id":10000+i})
	capped._drop(capped.player,"core",1)
	check(capped.pickups.size()<=600 and expansions(capped)==loot,"pickup compaction preserves both expansions within cap")
	var restored=Sim.new()
	check(restored.restore(a.snapshot()) and expansions(restored)==loot,"restore preserves exact unclaimed extensions")
	if loot.is_empty():return
	for seed_value in [1,2,3,4,5,17,42,12345,99001]:
		var sampled=Sim.new();sampled.new_run(seed_value)
		var finds=expansions(sampled)
		check(finds.size()==2 and finds.all(func(p):return p.pos.distance_to(sampled.world.start)>=500 and sampled.world.reachable(p.pos)),"two reachable finds for seed "+str(seed_value))
	a.new_run(901)
	check(expansions(a)==loot,"reusing simulator starts fresh extension set")
	for found in loot:
		_collect_case(a,found)
func _collect_case(a,found: Dictionary):
	var item=found.duplicate(true)
	a.pickups=[item];a.events=[];a.player=item.pos
	a._collect(0.01)
	check(a.pickups.size()==1 and item.get("captured",false) and a.events.is_empty(),"contact starts absorption before reward")
	var partial=Sim.new();check(partial.restore(a.snapshot()),"captured extension restores")
	partial._collect(2.0);partial._collect(2.0)
	check(partial.events.size()==1 and partial.events[0].type=="expansion","absorption emits exactly one expansion")
	if partial.events.size()==1:
		var event=partial.events[0]
		check(event.get("target","")==("body" if item.type=="body_extension" else "stock") and event.amount==1 and event.token==a.run_id+":"+str(item.id),"expansion carries target amount and durable token")
	check(partial.cores_found==0 and not partial.events.any(func(e):return e.type=="core"),"extension never credits cores")
	var done=Sim.new();done.restore(partial.snapshot())
	check(expansions(done).is_empty() and done.events==partial.events,"claimed extension does not respawn and event survives restore")
