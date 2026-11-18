extends SceneTree
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():
	var path="res://core/organism_slots.gd"
	check(ResourceLoader.exists(path),"body/stock transaction model exists")
	if failures>0:quit(1);return
	var slots=load(path)
	var small_a={"id":"a","cells":1,"kind":"tentacle","rank":3}
	var small_b={"id":"b","cells":1,"kind":"acid","quality":2}
	var large={"id":"large","cells":3,"kind":"devour","rank":7,"tissue":{"channels":[1,2]}}
	var state={"body_capacity":3,"stock_capacity":3,"equipped":[small_a,small_b],"stock":[large]}
	var original=state.duplicate(true)
	check(slots.validate(state)=="","valid equipped and stock organs")
	check(slots.used_cells(state)==2,"body counts occupied cells rather than organ count")
	check(not slots.move(state,"large","body").ok,"large organ cannot exceed capacity")
	var result=slots.move(state,"large","body",["a","b"])
	check(result.ok and result.state.equipped.size()==1 and result.state.stock.size()==2,"one large organ can replace several small ones")
	check(result.state.equipped[0].rank==7 and result.state.stock[1].quality==2,"transfers preserve organ properties")
	check(state==original,"successful transaction does not mutate source")
	result.state.equipped[0].rank=99
	result.state.equipped[0].tissue.channels[0]=99
	check(state.stock[0].tissue.channels[0]==1,"nested tissue data cannot alias the source")
	check(state.stock[0].rank==7,"returned state does not alias original organs")
	var full=state.duplicate(true);full.stock_capacity=1
	check(not slots.move(full,"large","body",["a","b"]).ok,"replacement cannot discard organs when stock is full")
	check(full.equipped.size()==2 and full.stock.size()==1,"failed replacement leaves all organs in place")
	check(not slots.move(full,"a","stock").ok,"cannot unequip into full stock")
	check(not slots.move(state,"missing","body").ok,"unknown organ rejected")
	check(not slots.move(state,"large","elsewhere").ok,"unknown destination rejected")
	check(not slots.move(state,"large","body",["a","a"]).ok,"duplicate replacement rejected")
	check(not slots.move(state,"large","body",["not-owned"]).ok,"unknown replacement rejected")
	var duplicate=state.duplicate(true);duplicate.stock.append(small_a.duplicate(true))
	check(slots.validate(duplicate)!="","same instance cannot exist twice")
	var invalid=state.duplicate(true);invalid.stock[0].cells=0
	check(slots.validate(invalid)!="","zero cell cost rejected")
	invalid=state.duplicate(true);invalid.body_capacity=1.5
	check(slots.validate(invalid)!="","fractional capacity rejected")
	result=slots.expand(state,"body")
	check(result.ok and result.state.body_capacity==4 and result.state.stock_capacity==3,"body expansion adds a cell")
	check(result.state.equipped==state.equipped and result.state.stock==state.stock,"expansion preserves every organ")
	check(slots.expand(state,"stock").state.stock_capacity==4,"stock expansion adds an organ position")
	check(not slots.expand(state,"other").ok,"unknown expansion rejected")
	var larger=slots.expand(state,"body").state
	result=slots.move(larger,"large","body",["a"])
	check(result.ok and slots.used_cells(result.state)==4,"replacement accepts exact cell capacity")
	result=slots.move(state,"a","stock")
	check(result.ok and slots.used_cells(result.state)==1 and result.state.stock.size()==2,"unequip preserves the instance in stock")
	var malformed=state.duplicate(true);malformed.stock="bad"
	check(slots.validate(malformed)!="","malformed stock rejected")
	malformed=state.duplicate(true);malformed.equipped.append(null)
	check(slots.validate(malformed)!="","malformed organ rejected")
	malformed=state.duplicate(true);malformed.body_capacity=INF
	check(slots.validate(malformed)!="","infinite capacity rejected")
	malformed=state.duplicate(true);malformed.stock[0].cells=NAN
	check(slots.validate(malformed)!="","non-finite cell costs rejected")
	var huge={"body_capacity":slots.MAX_EXACT_INTEGER,"stock_capacity":0,"equipped":[{"id":"huge","cells":slots.MAX_EXACT_INTEGER},{"id":"one","cells":1}],"stock":[]}
	check(slots.validate(huge)!="","summed costs beyond exact integer range rejected")
	check(not slots.expand({"body_capacity":slots.MAX_EXACT_INTEGER,"stock_capacity":0,"equipped":[],"stock":[]},"body").ok,"expansion cannot overflow numeric representation")
	check(state==original,"all failed operations and expansions keep source intact")
	print("ORGANISM SLOTS: %d failures"%failures)
	quit(0 if failures==0 else 1)
