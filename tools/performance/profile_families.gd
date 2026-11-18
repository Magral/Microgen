extends SceneTree
const Store=preload("res://core/save_store.gd")
const Sim=preload("res://game/simulation.gd")
const Equipment=preload("res://core/organism_equipment.gd")
func _initialize():
	var s=Store.new("user://test-profile-families.json");s.clear_test_files()
	var model=Sim.new();model.new_run(44)
	var snapshot=model.snapshot()
	for family_count in [1,5,10]:
		while s.family_summaries().size()<family_count:
			assert(s.create_family("Measured family","predator"))
			var candidate=s.profile.duplicate(true);candidate.organism=Equipment.from_profile(candidate)
			snapshot.family_id=s.family_id();candidate.checkpoint=snapshot.duplicate(true)
			assert(s.write_profile(candidate))
		var durations=[]
		for i in range(12):
			var start=Time.get_ticks_usec()
			assert(s.save_checkpoint(s.profile.checkpoint,s.family_id()))
			durations.append(Time.get_ticks_usec()-start)
		durations.sort()
		var switches=[]
		var entries=s.family_summaries()
		for i in range(12):
			var start=Time.get_ticks_usec()
			assert(s.select_family(entries[i%entries.size()].id))
			switches.append(Time.get_ticks_usec()-start)
		switches.sort()
		print("FAMILIES ",JSON.stringify({"families":family_count,"file_bytes":FileAccess.get_file_as_bytes(s.path).size(),"save_median_us":durations[6],"save_max_us":durations[-1],"switch_median_us":switches[6],"switch_max_us":switches[-1]}))
	s.clear_test_files();quit()
