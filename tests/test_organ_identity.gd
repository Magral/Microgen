extends SceneTree
const Equipment=preload("res://core/organism_equipment.gd")
const Flow=preload("res://ui/organism_flow.gd")
const Save=preload("res://core/save_store.gd")
const Build=preload("res://core/build_model.gd")
class Owner extends RefCounted:
	var store=Save.new("user://test-organ-identity.json")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():
	var owner=Owner.new()
	var value=Equipment.from_profile(owner.store.profile)
	value.body_capacity=6
	var rare=value.equipped[0].duplicate(true);rare.quality=3;rare.evolved=true
	var plain=rare.duplicate(true);plain.id="organ-2";plain.quality=0;plain.evolved=false
	value.next_id=3;value.equipped=[plain,rare]
	var merged=Equipment.aggregate(value)
	var saved=Equipment.refresh(value,{"organs":merged.organs,"qualities":merged.qualities})
	check(saved.ok and saved.state.equipped[0].quality==0,"ordinary save cannot copy another instance's rare quality")
	var build=Build.new();build.stats.evolutions={"devour":true}
	var single=value.duplicate(true);single.equipped=[plain]
	Flow.apply_to_build(single,build)
	check(not build.evolved("devour"),"swapping evolved organ for plain same-kind instance clears behavior")
	owner.store.profile.organism=value
	var flow=Flow.new(owner);flow.bind_run(value)
	Flow.apply_to_build(value,build)
	var captured=flow.capture(build.to_dict())
	check(not captured.equipped[0].get("evolved",false) and captured.equipped[1].get("evolved",false),"capture preserves each instance's evolution ownership")
	var legacy=owner.store.defaults();legacy.checkpoint={"build":{"organs":{"devour":6},"qualities":{"devour":3},"stats":{"evolutions":{"devour":true}}}}
	var migrated=Equipment.from_profile(legacy)
	check(migrated.equipped[0].get("evolved",false),"migration retains an earned evolution on its original organ")
	print("ORGAN IDENTITY: %d failures"%failures)
	quit(0 if failures==0 else 1)
