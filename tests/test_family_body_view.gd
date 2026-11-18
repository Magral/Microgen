extends SceneTree
const Hud=preload("res://ui/hud.gd")
const Home=preload("res://ui/family_home.gd")
const Body=preload("res://ui/organism_view.gd")
const Genome=preload("res://core/genome.gd")
const Sim=preload("res://game/simulation.gd")
const Catalog=preload("res://core/catalog.gd")
var failures=0
var calls=[]
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func button(node,id):return node.find_child(id,true,false)
func fixed(hud):
	if hud.has_method("open_fixed"):return hud.open_fixed("Семьи")
	return hud.open_home()
func verify(hud):
	await process_frame
	await process_frame
	check(hud.modal.find_children("*","ScrollContainer",true,false).is_empty(),"no scroll containers")
	for b in hud.modal.find_children("*","Button",true,false):
		check(b.size.y>=50,"touch buttons >=50")
		check(b.get_global_rect().position.y>=0 and b.get_global_rect().end.y<=root.size.y+1,"buttons fit logical height: "+str(b.name)+" "+str(b.get_global_rect())+" root "+str(root.size))
		check(b.get_global_rect().position.x>=0 and b.get_global_rect().end.x<=root.size.x+1,"buttons fit logical width: "+str(b.name))
func run():
	root.size=Vector2i(1280,640)
	root.content_scale_size=root.size
	var hud=Hud.new();root.add_child(hud)
	await process_frame
	var cb={"resume":func(id):calls.append(["resume",id]),"prepare":func(id):calls.append(["prepare",id]),"delete":func(id):calls.append(["delete",id]),"new":func():calls.append(["new"]),"page":func(group,index):calls.append([group,index])}
	var saved=Genome.create(88,0,"player",0)
	var entries=[{"id":"a","name":"Первая","form":"toxic","alive":true,"recipe":saved},{"id":"b","name":"Вторая","alive":true},{"id":"c","name":"Новая","alive":false,"ended":false},{"id":"d","name":"Предок","alive":false,"ended":true}]
	var before=entries.duplicate(true)
	var box=fixed(hud)
	Home.populate(hud,box,entries,cb)
	await verify(hud)
	check(button(box,"resume_a")!=null and button(box,"resume_b")==null,"living family pagination shows one card")
	check(button(box,"prepare_c")!=null,"fresh family is preparable")
	check(box.find_child("Portrait_a",true,false).recipe==saved,"portrait uses saved morphology")
	check(box.find_children("form_*","Button",true,false).is_empty(),"home has no form selector")
	button(box,"resume_a").pressed.emit();button(box,"delete_c").pressed.emit()
	check(["resume","a"] in calls and ["delete","c"] in calls,"family callbacks preserve IDs")
	button(box,"page_alive_next").pressed.emit()
	check(["alive",1] in calls,"family page callback")
	check(entries==before,"home is presentation only")
	var parts=[]
	for i in range(10):parts.append({"id":"part-%d"%i,"kind":"devour","cells":2 if i==0 else 1,"rank":2,"quality":1})
	var model={"family_name":"Первая","form":"toxic","body_capacity":16,"stock_capacity":3,"equipped":parts,"stock":[{"id":"stored","kind":"acid","cells":1,"rank":1,"quality":0}],"reserve":[],"live":false}
	var bcb={"part":func(id):calls.append(["part",id]),"empty_body":func():calls.append(["empty_body"]),"empty_stock":func():calls.append(["empty_stock"]),"page":func(index):calls.append(["body",index]),"stock_page":func(index):calls.append(["stock",index]),"start":func():calls.append(["start"])}
	box=fixed(hud);Body.populate(hud,box,model,null,bcb)
	await verify(hud)
	check(box.find_child("LivingPreview",true,false)!=null,"large tissue preview")
	check(button(box,"part_part-0")!=null and button(box,"part_stored")!=null,"body and stock identity")
	button(box,"part_part-0").pressed.emit();button(box,"page_next").pressed.emit()
	check(["part","part-0"] in calls and ["body",1] in calls,"organ callbacks preserve IDs and pages")
	check(button(box,"start_action")!=null,"preparation starts life")
	model.stock[0].cells=3
	box=fixed(hud);Body.populate(hud,box,model,null,bcb)
	await verify(hud)
	check(button(box,"empty_stock_cell_1")!=null,"large stock organ uses one position")
	var regular_capacity=model.body_capacity
	model.body_capacity=1000000000
	box=fixed(hud);Body.populate(hud,box,model,null,bcb,124999999)
	await verify(hud)
	check(button(box,"empty_body_cell_999999999")!=null,"large capacity renders only the selected page")
	check(box.find_children("empty_body_cell_*","Button",true,false).size()==8,"empty body cells remain bounded to eight per page")
	model.body_capacity=regular_capacity
	model.live=true
	box=fixed(hud);Body.populate(hud,box,model,null,bcb,1)
	await verify(hud)
	check(button(box,"part_part-8")!=null and button(box,"part_part-0")==null,"second body page")
	check(button(box,"start_action")==null and button(box,"archive_action")==null,"live organism has no start or archive")
	box=fixed(hud);Body.forms(hud,box,{"choose":func(id):calls.append(["choose",id])})
	await verify(hud)
	check(box.find_children("choose_*","Button",true,false).size()==3,"exactly three base forms")
	button(box,"choose_colony").pressed.emit();check(["choose","colony"] in calls,"form callback")
	box=fixed(hud);Body.picker(hud,box,parts,{"choose":func(id):calls.append(["choose",id])},1)
	await verify(hud)
	check(button(box,"choose_part-4")!=null and button(box,"choose_part-0")==null,"picker has short pages")
	box=fixed(hud);Body.detail(hud,box,parts[0].merged({"can_equip":true}),null,{"equip":func():calls.append(["equip"])})
	await verify(hud)
	check(button(box,"equip_action")!=null and button(box,"unequip_action")==null,"detail respects action flags")
	box=fixed(hud);Body.exchange(hud,box,model,"stored",[],"Недостаточно места",{})
	await verify(hud)
	check(button(box,"apply_action").disabled,"invalid exchange cannot apply")
	var body_before=model.duplicate(true)
	var sim=Sim.new();sim.new_run(345)
	model.stock=parts.slice(0,7);model.stock_capacity=12;model.stock_page=1
	box=fixed(hud);Body.populate(hud,box,model,sim,bcb,1)
	await verify(hud)
	check(box.find_child("LivingPreview",true,false).sim==sim,"preview uses current simulation")
	check(button(box,"stock_page_next")!=null,"stock pages have navigation")
	button(box,"stock_page_next").pressed.emit();check(["stock",2] in calls,"stock callback page identity")
	box=fixed(hud);Home.populate(hud,box,[],cb)
	await verify(hud)
	check(button(box,"new_action")!=null,"empty home can create a family")
	check(Home.recipe_for({"id":"fallback","form":"colony"})==Home.recipe_for({"id":"fallback","form":"colony"}),"fallback morphology deterministic")
	model=body_before
	var all_parts=[]
	for kind in Catalog.ORGANS:
		all_parts.append({"id":"all-"+kind,"kind":kind,"cells":3,"rank":10,"quality":3})
	model.equipped=all_parts
	box=fixed(hud);Body.populate(hud,box,model,null,bcb)
	await verify(hud)
	box=fixed(hud);Body.picker(hud,box,all_parts,{"choose":func(id):calls.append(["choose",id])})
	await verify(hud)
	root.size=Vector2i(1280,720)
	root.content_scale_size=root.size
	box=fixed(hud);Home.populate(hud,box,entries,cb,{"alive":1,"ancestral":1})
	await verify(hud)
	check(button(box,"resume_b")!=null and button(box,"prepare_d")!=null,"home pages applied independently")
	hud.queue_free();await process_frame
	print("FAMILY BODY VIEW: %d failures"%failures)
	quit(0 if failures==0 else 1)
