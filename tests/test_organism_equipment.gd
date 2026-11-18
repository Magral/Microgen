extends SceneTree
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():
	var path="res://core/organism_equipment.gd"
	check(ResourceLoader.exists(path),"persistent equipment model exists")
	if failures>0:quit(1);return
	var equipment=load(path)
	var profile={"legacy":{"selected_form":"toxic","imprints":[{"id":"barrier","rank":5,"quality":3}]},"checkpoint":{"build":{"organs":{"devour":9,"division":7,"acid":4,"tentacle":2},"qualities":{"devour":3,"acid":2}}}}
	var before=profile.duplicate(true)
	var state=equipment.from_profile(profile)
	check(equipment.validate(state)=="","checkpoint migrates into valid records")
	check(state.form=="toxic" and state.body_capacity==10 and state.stock_capacity==3,"checkpoint capacity grandfathered to preserve all equipped organs")
	check(equipment.aggregate(state).organs.devour==9 and equipment.aggregate(state).qualities.devour==3,"rank and quality survive migration")
	check(state.reserve.size()==1 and state.reserve[0].kind=="barrier" and state.reserve[0].rank==5,"legacy organ imprint preserved in archive")
	check(state==equipment.from_profile(profile) and state.equipped[0].id=="organ-1","migration IDs are deterministic")
	check(profile==before,"migration does not mutate profile")
	check(equipment.from_profile({"organism":{"bad":true}}).is_empty(),"malformed existing equipment cannot silently reset")
	var starter=equipment.from_profile({"legacy":{"selected_form":"colony"}})
	check(starter.form=="colony" and starter.body_capacity==8 and starter.equipped[0].kind=="division","selected form controls starter and capacity")
	check(equipment.cell_cost("armor")==0 and equipment.cell_cost("tentacle")==2,"only catalog organs have costs")
	var small=equipment.from_profile({})
	small.body_capacity=3;small.stock_capacity=0
	var result=equipment.award(small,"acid",2)
	check(result.ok and result.location=="reserve" and result.state.reserve.size()==1,"earned organ survives full body and stock")
	var direct_install=equipment.move(result.state,result.id,"body",[result.state.equipped[0].id])
	check(direct_install.ok and direct_install.state.equipped.any(func(part):return part.id==result.id) and direct_install.state.reserve.any(func(part):return part.id==small.equipped[0].id),"archived discovery can be installed directly while displaced organ remains archived")
	check(small.reserve.is_empty(),"award does not alias input")
	var same=equipment.award(small,"devour",2)
	check(same.ok and same.state.equipped.size()==1 and same.state.equipped[0].rank==4 and same.state.equipped[0].quality==2,"rare level-up improves existing instance by three ranks")
	same.state.equipped[0].rank=9007199254740991
	check(not equipment.award(same.state,"devour",1).ok,"max rank without quality improvement rejects")
	check(equipment.award(same.state,"devour",3).state.equipped[0].quality==3,"max rank can gain quality")
	var expanded=equipment.expand(result.state,"stock").state
	var restored=equipment.move(expanded,result.id,"stock_from_archive")
	check(restored.ok and restored.state.stock.size()==1 and restored.state.reserve.is_empty(),"archive may enter an available stock position")
	var swapped=equipment.move(restored.state,result.id,"body",[small.equipped[0].id])
	check(swapped.ok and swapped.state.equipped[0].kind=="acid" and swapped.state.stock[0].kind=="devour","free replacement preserves displaced organ")
	var refreshed=equipment.refresh(swapped.state,{"organs":{"acid":6},"qualities":{"acid":3}})
	check(refreshed.ok and refreshed.state.stock[0].kind=="devour" and refreshed.state.equipped[0].rank==6,"refresh retains swapped out organ and updates equipped rank")
	var overflow=equipment.refresh(refreshed.state,{"organs":{"acid":6,"division":8},"qualities":{"division":2}})
	check(overflow.ok and overflow.state.reserve[0].rank==8 and overflow.state.body_capacity==3,"refresh preserves new ranks without growing body capacity")
	var archive=equipment.move(swapped.state,swapped.state.equipped[0].id,"archive")
	check(archive.ok and archive.state.reserve.size()==1,"archive preserves existing instance")
	var pair=equipment.from_profile({"checkpoint":{"build":{"organs":{"spikes":3,"pulse":4}}}})
	pair.body_capacity=3
	var large=equipment.award(pair,"division").state
	var exchange=equipment.move(large,large.stock[0].id,"body",[pair.equipped[0].id,pair.equipped[1].id])
	check(exchange.ok and exchange.state.stock.size()==2,"one large organ can freely replace multiple small organs")
	var duplicate=pair.equipped.filter(func(part):return part.kind=="spikes")[0].duplicate(true);duplicate.id="organ-99";duplicate.rank=9;duplicate.quality=3
	pair.equipped.append(duplicate);pair.next_id=100
	check(equipment.validate(pair)=="" and equipment.aggregate(pair).organs.spikes==12 and equipment.aggregate(pair).qualities.spikes==3,"same-kind instances aggregate unbounded ranks and best grade")
	var twins=pair.duplicate(true)
	for part in twins.equipped:
		if part.kind=="spikes":part.rank=10;part.quality=3
	twins.equipped[2].rank=2
	check(equipment.award(twins,"spikes",0).ok,"same-kind upgrade finds an eligible instance after a maximum instance")
	var invalid=pair.duplicate(true);invalid.reserve.append(duplicate)
	check(equipment.validate(invalid)!="","cross-location duplicate IDs rejected")
	invalid=pair.duplicate(true);invalid.equipped[0].rank=1.5
	check(equipment.validate(invalid)!="" and not equipment.award(invalid,"acid").ok,"fractional rank rejects state and operation")
	invalid=pair.duplicate(true);invalid.equipped[0].quality=INF
	check(equipment.validate(invalid)!="","infinite quality rejected")
	invalid=pair.duplicate(true);invalid.equipped[0].cells=2
	check(equipment.validate(invalid)!="","noncanonical cell cost rejected")
	invalid=pair.duplicate(true);invalid.next_id=1
	check(equipment.validate(invalid)!="","next identifier must not reuse existing IDs")
	var serialized=JSON.parse_string(JSON.stringify(equipment.expand(pair,"body").state))
	check(equipment.validate(serialized)=="" and equipment.from_profile({"organism":serialized})==serialized,"expansion and IDs survive JSON serialization")
	print("ORGANISM EQUIPMENT: %d failures"%failures)
	quit(0 if failures==0 else 1)
