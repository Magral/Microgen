extends SceneTree
const Legacy=preload("res://core/genome_legacy.gd")
const Save=preload("res://core/save_store.gd")
const Build=preload("res://core/build_model.gd")
const Genome=preload("res://core/genome.gd")
class TestWorld:
	func biome(_position): return 1
class FinishedLife:
	extends RefCounted
	var build=Build.new()
	var outcome="dead"
	var elapsed=61.0
	var combat_stats={"organs":{},"damage_dealt":40.0}
	var player_genome=Genome.create(480,0,"player",1)
	var world=TestWorld.new()
	var player=Vector2.ZERO
	var run_loadout={"traits":[]}
class FaultyStore:
	extends Save
	var corrupt_mode="truncated"
	func _write_tmp(tmp: String,serialized: String) -> bool:
		if not super._write_tmp(tmp,serialized): return false
		var f=FileAccess.open(tmp,FileAccess.WRITE)
		if corrupt_mode=="truncated": f.store_string(serialized.left(20))
		else:
			var wrong=JSON.parse_string(serialized)
			wrong.cores+=100
			f.store_string(JSON.stringify(wrong))
		f.close()
		return true
var failures=0
var checks=0
func check(value: bool,message: String):
	checks+=1
	if not value:
		failures+=1
		push_error(message)
func _initialize():
	var save=Save.new("user://test-legacy.json")
	save.clear_test_files()
	check(save.profile.version==1 and save.profile.legacy.selected_form=="predator","version one retained, predator default")
	var snapshot=save.profile.duplicate(true)
	check(not save.research("bogus") and not save.research("colony") and not save.select_form("toxic"),"invalid and unpaid operations rejected")
	check(save.profile==snapshot,"failed operations preserve entire profile")
	save.bank(60)
	check(save.research("toxic") and save.profile.cores==56,"toxic costs four")
	check(save.research("colony") and "division" in save.profile.unlocked,"colony unlocks division atomically")
	check(not save.unlock("division") and not save.research("colony"),"colony purchase cannot repeat")
	check(save.research("elastic") and save.research("sensory") and save.research("folds"),"traits researched")
	check(save.toggle_trait("elastic") and save.toggle_trait("sensory") and not save.toggle_trait("folds"),"two trait slots")
	check(save.select_form("colony") and save.save_preset("Колония"),"preset stores valid loadout")
	var seed=save.profile.legacy.morphology_seed
	check(save.reroll_morphology() and save.profile.legacy.morphology_seed!=seed,"morphology reroll changes seed")
	check(save.load_preset(0) and save.profile.legacy.morphology_seed==seed,"preset restores morphology")
	check(not save.load_preset(-1) and not save.select_imprint("acid"),"invalid preset and unowned imprint rejected")
	var old=save.defaults()
	old.erase("legacy")
	old.unlocked.append("division")
	old.cores=17
	old.checkpoint={"sentinel":true}
	check(Legacy.normalize(old).selected_form=="predator" and "colony" in Legacy.normalize(old).forms,"old division migrates to colony")
	old.legacy={"selected_form":"division","equipped_traits":["bogus"],"morphology_seed":{},"research":["bogus"],"pending":[null]}
	check(Legacy.normalize(old).selected_form=="colony" and Legacy.normalize(old).pending.is_empty(),"malformed legacy sanitized and division alias migrated")
	check(save.write_profile(old),"old save accepted")
	var restored=Save.new(save.path)
	restored.load_profile()
	check(restored.profile.cores==17 and restored.profile.checkpoint==old.checkpoint and "division" in restored.profile.unlocked,"migration preserves economy checkpoint and unlock")
	var sim=FinishedLife.new()
	sim.outcome="dead"
	sim.elapsed=61
	sim.build.organs={"tentacle":3,"acid":3}
	sim.combat_stats.organs={"tentacle":{"damage":40,"hits":4,"kills":1}}
	Legacy.complete(restored.profile,sim)
	check(restored.profile.legacy.pending.size()==1 and restored.profile.legacy.pending[0].id=="tentacle","only actually used mature organ yields candidate")
	check(restored.write_profile() and restored.claim_imprint("tentacle"),"claim persists candidate")
	check(restored.profile.legacy.pending.is_empty() and restored.profile.legacy.selected_imprint=="tentacle","one choice selects imprint")
	check(not restored.claim_imprint("tentacle"),"claim cannot repeat")
	var purity=restored.profile.duplicate(true)
	check(Legacy.loadout(restored.profile).imprint=="tentacle" and restored.profile==purity,"loadout is pure")
	sim.elapsed=1
	Legacy.complete(restored.profile,sim)
	check(restored.profile.legacy.pending.is_empty(),"instant death cannot farm imprint")
	sim.elapsed=61
	Legacy.complete(restored.profile,sim)
	var cores=restored.profile.cores
	check(restored.claim_imprint("tentacle") and restored.profile.cores==cores,"duplicate mastery grants no currency")
	check(restored.profile.legacy.knowledge.structure==1,"duplicate mastery bounded research knowledge")
	check(restored.write_profile() and JSON.stringify(Legacy.normalize(JSON.parse_string(JSON.stringify(restored.profile))))==JSON.stringify(restored.profile.legacy),"JSON roundtrip preserves normalized state")
	# A body feature can be retained without inheriting an organ rank or quality.
	sim.run_loadout.traits=["elastic"]
	Legacy.complete(restored.profile,sim)
	check(restored.profile.legacy.pending.any(func(x): return x.id=="trait:elastic"),"used body trait can become imprint")
	check(restored.claim_imprint("trait:elastic") and Legacy.loadout(restored.profile).imprint=="trait:elastic","body imprint is selectable")
	Legacy.complete(restored.profile,sim)
	var pending_origin=restored.profile.legacy.pending.duplicate(true)
	sim.elapsed=1
	Legacy.complete(restored.profile,sim)
	check(restored.profile.legacy.pending==pending_origin,"unfinished choice survives a later short run")
	check(restored.claim_imprint("tentacle"),"previous organ choice remains claimable")
	# Finish two eligible generations without claiming the first.
	sim.elapsed=61
	Legacy.complete(restored.profile,sim)
	var first_generation=restored.profile.legacy.pending[0].origin.generation
	Legacy.complete(restored.profile,sim)
	check(restored.profile.legacy.pending_queue.size()==1,"second finished life is queued")
	check(restored.claim_imprint("tentacle") and restored.profile.legacy.pending[0].origin.generation==first_generation+1,"first claim promotes second life with its origin")
	check(restored.claim_imprint("tentacle") and restored.profile.legacy.pending.is_empty(),"second life has its own claim")
	sim.elapsed=61
	for i in range(8):
		Legacy.complete(restored.profile,sim)
		check(restored.claim_imprint("tentacle"),"duplicate claim once per qualified life")
	check(restored.profile.legacy.knowledge.structure==3 and restored.profile.legacy.history.size()<=12,"knowledge and history bounded")
	check(not restored.focus_research("bogus") and restored.focus_research("memory"),"research focus validates ownership and ID")
	var bad=Save.new("user://missing-legacy-dir/profile.json")
	var bad_before=bad.profile.duplicate(true)
	check(not bad.bank(5) and bad.profile==bad_before,"failed disk write preserves live profile")
	bad.profile.cores=10
	bad_before=bad.profile.duplicate(true)
	check(not bad.research("toxic") and bad.profile==bad_before,"failed research disk write does not debit currency or grant form")
	var locked=save.defaults()
	locked.legacy={"selected_form":"toxic","equipped_traits":["elastic","sensory"],"selected_imprint":"acid","presets":[{"name":"hack","form":"toxic","traits":["elastic"],"imprint":"acid"}]}
	var normalized=Legacy.normalize(locked)
	check(normalized.selected_form=="predator" and normalized.equipped_traits.is_empty() and normalized.selected_imprint.is_empty(),"unowned active choices removed")
	check(normalized.presets[0].form=="predator" and normalized.presets[0].traits.is_empty() and normalized.presets[0].imprint.is_empty(),"unowned preset choices removed")
	var invalid=restored.defaults()
	invalid.cores={"broken":true}
	var invalid_file=FileAccess.open(restored.path+".tmp",FileAccess.WRITE)
	invalid_file.store_string(JSON.stringify(invalid))
	invalid_file.close()
	check(restored._read(restored.path+".tmp").is_empty(),"malformed JSON economy is rejected without conversion errors")
	var bounded=save.defaults()
	for i in range(9): check(Legacy.complete(bounded,sim),"nine outstanding lives retained")
	check(not Legacy.can_start(bounded) and bounded.legacy.pending_queue.size()==8,"full backlog blocks new generation")
	var before_overflow=bounded.duplicate(true)
	check(not Legacy.complete(bounded,sim) and bounded==before_overflow,"overflow completion defers without mutating generation rewards or choices")
	var backlog_store=Save.new("user://test-backlog.json")
	check(backlog_store.write_profile(bounded) and backlog_store.claim_imprint("tentacle") and Legacy.can_start(backlog_store.profile),"claim frees backlog capacity")
	check(Legacy.complete(backlog_store.profile,sim) and backlog_store.profile.legacy.pending_queue.size()==8,"deferred completion succeeds after a claim")
	var malformed=bounded.duplicate(true)
	malformed.legacy.pending_queue.append(null)
	malformed.legacy.pending_queue.append({"broken":true})
	malformed.legacy.pending_queue.append(malformed.legacy.pending.duplicate(true))
	check(Legacy.normalize(malformed).pending_queue.size()==8,"malformed or excess incoming backlog is bounded")
	backlog_store.clear_test_files()
	var healthy=Save.new("user://test-verified-write.json")
	healthy.clear_test_files()
	check(healthy.bank(10) and healthy.bank(5),"durable primary and backup created")
	var primary_text=FileAccess.get_file_as_string(healthy.path)
	var backup_text=FileAccess.get_file_as_string(healthy.path+".bak")
	for mode in ["truncated","different_valid_json"]:
		var faulty=FaultyStore.new(healthy.path)
		faulty.load_profile()
		faulty.corrupt_mode=mode
		var before_failed_write=faulty.profile.duplicate(true)
		check(not faulty.bank(7) and faulty.profile==before_failed_write,"temporary corruption never commits live state: "+mode)
		check(FileAccess.get_file_as_string(healthy.path)==primary_text and FileAccess.get_file_as_string(healthy.path+".bak")==backup_text,"temporary corruption preserves existing primary and backup: "+mode)
	check(healthy.bank(2) and healthy.profile.cores==17,"normal verified write still succeeds after failure")
	healthy.clear_test_files()
	restored.clear_test_files()
	print("GENOME_LEGACY: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
