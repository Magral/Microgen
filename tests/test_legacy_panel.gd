extends SceneTree
const Hud=preload("res://ui/hud.gd")
const View=preload("res://ui/legacy_panel.gd")
const Legacy=preload("res://core/genome_legacy.gd")
const Catalog=preload("res://core/catalog.gd")
const Genome=preload("res://core/genome.gd")
var failures=0
var calls=[]
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func button(box,id):return box.find_child(id,true,false)
func has_text(node,needle: String) -> bool:
	if (node is Label or node is Button) and needle in node.text:return true
	for child in node.get_children():
		if has_text(child,needle):return true
	return false
func verify(hud):
	await process_frame;await process_frame
	check(hud.modal.find_children("*","ScrollContainer",true,false).is_empty(),"no scrolling in legacy panel")
	for node in hud.modal.find_children("*","Control",true,false):
		if node is Button:
			check(node.size.y>=50,"buttons at least50")
			check(node.get_global_rect().position.x>=0 and node.get_global_rect().end.x<=root.size.x+1,"buttons fit width "+str(node.name))
			check(node.get_global_rect().position.y>=0 and node.get_global_rect().end.y<=root.size.y+1,"buttons fit height "+str(node.name)+str(node.get_global_rect()))
		if node is Label:check(node.get_theme_font_size("font_size")>=20,"font at least20")
func run():
	root.size=Vector2i(1280,640)
	var hud=Hud.new();root.add_child(hud);await process_frame
	var profile={"cores":50,"upgrades":{"health":5,"collect":2,"regen":0},"legacy":Legacy.defaults()}
	var items=[]
	for id in Catalog.ORGANS.keys()+["trait:elastic","trait:sensory"]:
		items.append({"id":id,"name":Legacy.imprint_name(id),"rank":5,"quality":3,"recipe":Genome.create(88,0,"player",0),"origin":{"generation":8,"elapsed":240,"biome":1}})
	profile.legacy.imprints=items
	profile.legacy.pending=items
	for i in range(9):profile.legacy.pending_queue.append(items)
	for i in range(12):profile.legacy.history.append({"generation":i,"elapsed":240,"form":"colony","outcome":"victory"})
	profile.legacy.research=["elastic","sensory"]
	profile.legacy.equipped_traits=["elastic","sensory"]
	var cb={}
	for key in ["tab","page","research","focus","trait","imprint","upgrade","claim"]:
		cb[key]=func(id):calls.append([key,id])
	for key in ["back","pending"]:cb[key]=func():calls.append([key])
	var before=profile.duplicate(true)
	for height in [640,720]:
		root.size=Vector2i(1280,height)
		for tab in ["research","traits","imprints","upgrades","history"]:
			for page in range(0,8):
				var box=hud.open_fixed("Геном")
				View.populate(hud,box,profile,cb,tab,page)
				await verify(hud)
				check(box.find_children("Entry_*","PanelContainer",true,false).size()<= (2 if tab=="traits" else 3),"short pages")
				if page==0:
					button(box,"tab_history").pressed.emit()
					check(["tab","history"] in calls,"tabs carry ID")
					button(box,"pending_action").pressed.emit()
					check(["pending"] in calls,"pending callback")
					if not button(box,"page_next").disabled:
						button(box,"page_next").pressed.emit();check(["page",1] in calls,"page callback index")
					if tab=="research":
						button(box,"research_toxic").pressed.emit();check(["research","toxic"] in calls,"research ID")
						button(box,"focus_toxic").pressed.emit();check(["focus","toxic"] in calls,"focus ID")
					if tab=="traits":
						check(has_text(box,"Контактный урон +8%"),"trait tradeoff visible")
						button(box,"trait_elastic").pressed.emit();check(["trait","elastic"] in calls,"trait ID")
					if tab=="imprints":
						check(has_text(box,"ранг 1") and has_text(box,"Поколение 8"),"inheritance and provenance")
						button(box,"imprint_tentacle").pressed.emit();check(["imprint","tentacle"] in calls,"imprint ID")
					if tab=="upgrades":
						check(button(box,"upgrade_health").disabled,"finite5 rank limit")
						button(box,"upgrade_collect").pressed.emit();check(["upgrade","collect"] in calls,"upgrade ID")
		for page in range(5):
			var box=hud.open_fixed("Ожидающие отпечатки")
			View.pending(hud,box,profile,cb,page)
			await verify(hud)
			check(box.find_children("Entry_*","PanelContainer",true,false).size()<=3,"pending max3")
			if page==0:
				button(box,"claim_tentacle").pressed.emit();check(["claim","tentacle"] in calls,"claim ID")
				check(has_text(box,"поколений: 8"),"normalized bounded queue count")
			if page==4:
				button(box,"claim_trait_elastic").pressed.emit();check(["claim","trait:elastic"] in calls,"trait imprint prefix preserved")
	check(profile==before,"rendering does not mutate profile")
	profile.cores=0
	var box=hud.open_fixed("Геном");View.populate(hud,box,profile,cb,"research")
	check(button(box,"research_toxic").disabled,"unaffordable research disabled")
	profile.legacy.research=["toxic"]
	box=hud.open_fixed("Геном");View.populate(hud,box,profile,cb,"research")
	check(button(box,"research_toxic").disabled,"purchased research disabled")
	profile.cores=100
	profile.legacy.research=[]
	box=hud.open_fixed("Геном");View.populate(hud,box,profile,cb,"research",2)
	check(button(box,"research_folds").disabled,"missing prerequisite disables research")
	profile.legacy.research=Legacy.RESEARCH.keys()
	profile.legacy.equipped_traits=["elastic","sensory"]
	box=hud.open_fixed("Геном");View.populate(hud,box,profile,cb,"traits",1)
	check(button(box,"trait_folds").disabled and button(box,"trait_receptive").disabled,"two equipped slots enforce selection limit")
	hud.queue_free();await process_frame
	print("LEGACY PANEL: %d failures"%failures)
	quit(0 if failures==0 else 1)
