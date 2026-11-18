extends SceneTree
const Families=preload("res://core/family_model.gd")
const Save=preload("res://core/save_store.gd")
const Legacy=preload("res://core/genome_legacy.gd")
const Genome=preload("res://core/genome.gd")
var checks=0
var failures=0
class FailingStore extends "res://core/save_store.gd":
	func _write_tmp(_tmp: String,_serialized: String) -> bool:
		return false
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func put(path: String,data: Dictionary):
	var f=FileAccess.open(path,FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
func _initialize():
	var source={"checkpoint":{"nested":[1]},"families":{"items":[{"state":{"large":[2]}}]}}
	var projection=Families.state(source)
	projection.checkpoint.nested.append(3)
	check(not projection.has("families") and source.checkpoint.nested==[1],"active projection omits archives and owns its nested data")
	var s=Save.new("user://test-families.json")
	s.clear_test_files()
	check(s.has_method("create_family"),"family creation API exists")
	if not s.has_method("create_family"):
		quit(1)
		return
	check(s.family_id()=="" and s.family_summaries().is_empty(),"fresh registry has no family")
	check(s.bank(12) and s.create_family("First","predator"),"first creation preserves unassigned currency")
	check(s.family_id()=="family-1" and s.profile.cores==12,"first family owns flat progress")
	check(s.save_checkpoint({"family_id":"family-1","outcome":"","hp":7},"family-1"),"owned checkpoint saved")
	check(s.credit_once("same",2),"first family credits token")
	var candidate={"id":"tentacle","recipe":Genome.create(48,0,"player",1),"origin":{"generation":2,"biome":1,"elapsed":65}}
	var progress=s.profile.duplicate(true)
	progress.legacy.pending=[candidate]
	progress.legacy.pending_queue=[[candidate]]
	progress.legacy.imprints=[candidate]
	progress.legacy.generation=2
	progress.legacy.history=[{"generation":2,"elapsed":65,"outcome":"dead","form":"predator","candidates":["tentacle"]}]
	progress.upgrades.health=1
	check(s.write_profile(progress),"family inheritance queue and purchase persisted")
	check(s.create_family("Second","colony") and s.profile.cores==0,"new family independent economy")
	check(Legacy.loadout(s.profile).form=="colony" and "division" in s.profile.unlocked,"colony starter ready")
	check(s.credit_once("same",3),"credit token local to second family")
	check(s.profile.legacy.pending.is_empty() and s.profile.legacy.pending_queue.is_empty() and s.profile.upgrades.health==0,"new family has independent inheritance and purchases")
	check(s.save_checkpoint({"family_id":"family-2","outcome":""},"family-2"),"second live family saved")
	check(s.family_summaries().filter(func(x):return x.alive).size()==2,"several families can be alive")
	var before=s.profile.duplicate(true)
	check(not s.save_checkpoint({"family_id":"family-1"},"family-1") and s.profile==before,"stale family save rejected")
	check(not s.save_checkpoint({"family_id":"family-1"},"family-2"),"conflicting snapshot owner rejected")
	check(not s.save_checkpoint({},""),"empty owner rejected")
	check(s.select_family("family-1") and s.profile.cores==14 and s.profile.checkpoint.hp==7,"selection restores first progress and checkpoint")
	check(not s.credit_once("same",2),"first token remains credited")
	check(s.profile.legacy.pending.size()==1 and s.profile.legacy.pending_queue.size()==1 and s.profile.upgrades.health==1,"archived inheritance queue and purchases restored")
	check("division" not in s.profile.unlocked and s.profile.legacy.generation==2,"form unlock and generation independent")
	var reopened=Save.new(s.path)
	reopened.load_profile()
	check(reopened.family_id()=="family-1" and reopened.profile.checkpoint.hp==7 and reopened.family_summaries().size()==2,"registry and live checkpoints survive reopening")
	check(s.profile.families.items[0].state.is_empty(),"active checkpoint not duplicated")
	check(s.save_checkpoint({"family_id":"family-1","outcome":"dead","token":"pending"},"family-1"),"ended checkpoint saved")
	check(s.select_family("family-2") and s.select_family("family-1") and s.profile.checkpoint.token=="pending","ended uncredited checkpoint preserved")
	check(s.family_summaries()[0].ended and not s.family_summaries()[0].alive,"ended summary explicit")
	var faulty=FailingStore.new(s.path)
	faulty.load_profile()
	before=faulty.profile.duplicate(true)
	var disk=FileAccess.get_file_as_string(s.path)
	check(not faulty.select_family("family-2") and faulty.profile==before,"failed selection leaves memory unchanged")
	check(not faulty.create_family("Failure","toxic") and faulty.profile==before,"failed creation leaves memory unchanged")
	check(not faulty.delete_family("family-1") and faulty.profile==before,"failed deletion leaves memory unchanged")
	check(FileAccess.get_file_as_string(s.path)==disk,"failed transactions preserve disk")
	check(s.delete_family("family-2") and s.family_id()=="family-1","inactive deletion preserves active")
	check(s.create_family("Third","toxic") and s.family_id()=="family-3" and Legacy.loadout(s.profile).form=="toxic","IDs monotonic and toxic starter ready")
	check(s.delete_family("family-3") and s.family_id()=="family-1","active deletion restores survivor")
	check(s.delete_family("family-1") and s.family_id()=="" and s.profile.cores==0 and s.profile.checkpoint.is_empty(),"last deletion clears projection")
	check(s.create_family("Fourth","predator") and s.family_id()=="family-4","ID counter survives empty registry")
	s.clear_test_files()
	var old=s.defaults()
	old.erase("families")
	old.cores=41
	old.unlocked.append("division")
	old.checkpoint={"outcome":"dead","token":"old-pending"}
	old.legacy.generation=8
	old.legacy.research=["colony","memory"]
	old.legacy.knowledge.memory=2
	old.legacy.pending=[candidate]
	old.legacy.pending_queue=[[candidate]]
	old.legacy.imprints=[candidate]
	old.credited=["old-token"]
	old.upgrades.regen=2
	put(s.path,old)
	s.load_profile()
	check(s.family_id()=="family-1" and s.profile.cores==41 and s.profile.legacy.generation==8 and s.profile.checkpoint.token=="old-pending","old profile migrated intact")
	check(FileAccess.get_file_as_string(s.path+".bak")==JSON.stringify(old),"migration backs up original")
	check(s.profile.legacy.pending.size()==1 and s.profile.legacy.pending_queue.size()==1 and s.profile.legacy.imprints.size()==1 and s.profile.upgrades.regen==2 and s.profile.credited==["old-token"],"migration retains rewards purchases and archived imprints")
	s.load_profile()
	check(s.family_summaries().size()==1,"migration happens once")
	check(s.create_family("Other","predator") and s.bank(1),"healthy backup contains inactive family")
	var broken=s.profile.duplicate(true)
	broken.families.items[0].state.cores="corrupt"
	put(s.path,broken)
	s.load_profile()
	check(s.family_summaries().size()==2 and s.profile.cores==0,"corrupt inactive record recovers known-good backup")
	broken=s.profile.duplicate(true)
	broken.families.items[1].id=broken.families.items[0].id
	put(s.path,broken)
	s.load_profile()
	check(s.family_summaries().size()==2 and s.family_id()=="family-2","duplicate registry IDs recover backup")
	s.clear_test_files()
	var original=Save.new("user://test-family-path-one.json")
	original.clear_test_files()
	check(original.create_family("Original","predator") and original.bank(6),"original path saved")
	var original_bytes=FileAccess.get_file_as_string(original.path)
	original.path="user://test-family-path-two.json"
	original.clear_test_files()
	check(original.bank(1) and FileAccess.get_file_as_string("user://test-family-path-one.json")==original_bytes,"changing path never writes previous file")
	original.clear_test_files()
	original.path="user://test-family-path-one.json"
	original.clear_test_files()
	print("FAMILIES: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
