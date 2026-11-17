extends SceneTree
const Hud=preload("res://ui/hud.gd")
const View=preload("res://ui/genome_view.gd")
const Store=preload("res://core/save_store.gd")
const Legacy=preload("res://core/genome_legacy.gd")
const Sim=preload("res://game/simulation.gd")
const Genome=preload("res://core/genome.gd")
var failures=0
var calls=[]
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func _initialize():call_deferred("run")
func callback_map() -> Dictionary:
	return {"form":func(id):calls.append(["form",id]),"trait":func(id):calls.append(["trait",id]),"imprint":func(id):calls.append(["imprint",id]),"reroll":func():calls.append(["reroll"]),"save_preset":func(index):calls.append(["save_preset",index]),"load_preset":func(index):calls.append(["load_preset",index]),"start":func():calls.append(["start"]),"back":func():calls.append(["back"]),"research":func(id):calls.append(["research",id]),"focus":func(id):calls.append(["focus",id]),"upgrade":func(id):calls.append(["upgrade",id]),"imprints":func():calls.append(["imprints"]),"claim":func(id):calls.append(["claim",id])}
func button_named(node,name_value: String):
	for child in node.get_children():
		if child is Button and str(child.name)==name_value:return child
		var found=button_named(child,name_value)
		if found!=null:return found
	return null
func has_text(node,needle: String) -> bool:
	if node is Label and needle in node.text:return true
	for child in node.get_children():
		if has_text(child,needle):return true
	return false
func layout(hud):
	var scroll=hud.scroll_container
	check(scroll.get_v_scroll_bar().size.x>=44,"44px scroll touch gutter")
	check(hud.content.get_global_rect().end.x<=scroll.get_v_scroll_bar().global_position.x+1,"content clears scrollbar at 1280x720")
	for node in hud.modal.find_children("*","Control",true,false):
		if node is Button:
			check(node.get_theme_font_size("font_size")>=24,"button font >=24")
			check(node.size.x<=1000,"button fits modal width")
		if node is Label:check(node.get_theme_font_size("font_size")>=20,"body font >=20")
	var exits=hud.modal.find_children("*","Button",true,false).filter(func(b):return b.text=="×")
	check(exits.size()==1,"one inherited header close button")
func run():
	root.size=Vector2i(1280,720)
	var hud=Hud.new();root.add_child(hud)
	hud.on_close=func():calls.append(["close"])
	await process_frame
	var store=Store.new("user://test-genome-view.json")
	# A real v1 file exercises migration without discarding old currency and ranks.
	var old={"version":1,"cores":47,"unlocked":["devour","division"],"discovered":["acid"],"synergies":[],"upgrades":{"health":3,"collect":2,"regen":1},"credited":[],"runs":9,"wins":1,"checkpoint":{},"best":120.0}
	var file=FileAccess.open(store.path,FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	store.load_profile()
	check(store.profile.cores==47 and store.profile.upgrades.health==3,"v1 migration keeps currency and passive purchases")
	var before=store.profile.duplicate(true)
	var sim=Sim.new();sim.new_run(301)
	var callbacks=callback_map()
	var box=hud.open("Новое поколение")
	View.populate_start(hud,box,store,sim,callbacks)
	await process_frame;await process_frame
	layout(hud)
	check(store.profile==before,"rendering start does not mutate migrated profile")
	check(has_text(box,"Признаки 0/2"),"start shows two trait slots")
	check(has_text(box,"Отпечаток · 1 место"),"start shows one imprint slot")
	var preview=box.find_child("LivingPreview",true,false)
	check(preview!=null and preview.sim==sim and preview.size.y>=300,"large live preview uses caller simulation")
	check(button_named(box,"form_toxic").disabled,"unresearched glandular form locked")
	button_named(box,"reroll_action").pressed.emit()
	button_named(box,"start_action").pressed.emit()
	button_named(box,"save_preset_2").pressed.emit()
	check(["save_preset",2] in calls,"three preset save slots pass index")
	check(button_named(box,"load_preset_2").disabled,"empty preset load disabled")
	button_named(box,"imprint_").pressed.emit()
	check(["reroll"] in calls and ["start"] in calls and ["imprint",""] in calls,"start callbacks retain arity and IDs")
	box=hud.open("Геном")
	View.populate_genome(hud,box,store,sim,callbacks)
	await process_frame;await process_frame
	layout(hud)
	for branch in ["Строение","Приспособление","Генетическая память"]:check(has_text(box,branch),"all research branches visible")
	check(has_text(box,"3/5") and has_text(box,"Стоимость:"),"legacy ranks and research costs readable")
	button_named(box,"focus_elastic").pressed.emit()
	check(["focus","elastic"] in calls,"research focus callback carries research ID")
	store.profile.legacy.pending=[{"id":"devour","name":"Пасть предка","branch":"structure","origin":{"generation":8,"biome":1,"elapsed":126},"recipe":Genome.create(301,0,"player",1),"rank":1,"quality":0}]
	var pending=store.profile.legacy.pending.duplicate(true)
	box=hud.open("Отпечатки")
	View.populate_imprints(hud,box,store,callbacks)
	await process_frame;await process_frame
	layout(hud)
	check(has_text(box,"Поколение 8") and has_text(box,"Токсичная зона"),"imprint preserves visible generation and biome provenance")
	check(has_text(box,"кандидаты сохранятся"),"safe imprint deferral explained")
	button_named(box,"back_action").pressed.emit()
	check(store.profile.legacy.pending==pending,"deferring does not discard pending imprint")
	button_named(box,"claim_devour").pressed.emit()
	check(["claim","devour"] in calls,"imprint claim identifies organ")
	store.profile.legacy.research=["toxic","elastic","sensory","folds"]
	store.profile.legacy.equipped_traits=["elastic","sensory"]
	store.profile.legacy.pending.append({"id":"trait:elastic","origin":{"generation":9,"biome":0,"elapsed":240},"recipe":Genome.create(305,0,"player",0)})
	box=hud.open("Новое поколение")
	View.populate_start(hud,box,store,sim,callbacks)
	await process_frame;await process_frame
	layout(hud)
	button_named(box,"form_toxic").pressed.emit()
	button_named(box,"trait_elastic").pressed.emit()
	check(["form","toxic"] in calls and ["trait","elastic"] in calls,"unlocked form and equipped trait deliver IDs")
	check(button_named(box,"trait_folds").disabled,"third trait disabled when both slots occupied")
	box=hud.open("Отпечатки")
	View.populate_imprints(hud,box,store,callbacks)
	await process_frame;await process_frame
	layout(hud)
	check(has_text(box,"особенность тела") and has_text(box,"Контактный урон +8%"),"trait imprint shows body effect and tradeoff")
	button_named(box,"claim_trait_elastic").pressed.emit()
	check(["claim","trait:elastic"] in calls,"body imprint callback preserves prefix")
	store.clear_test_files()
	hud.queue_free()
	await process_frame
	print("GENOME VIEW: %d failures" % failures)
	quit(0 if failures==0 else 1)
