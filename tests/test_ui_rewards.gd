extends SceneTree
var failures = 0
func check(ok: bool, text: String):
	if not ok:
		failures += 1
		push_error(text)
func has_text(node,needle: String) -> bool:
	if node is Label and needle in node.text: return true
	for child in node.get_children():
		if has_text(child,needle): return true
	return false
func _initialize(): call_deferred("run")
func run():
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.sound_enabled = false
	scene.store.path = "user://test-ui-rewards.json"
	scene.store.profile = scene.store.defaults()
	scene.start_run(904)
	scene.sim.build.organs={"tentacle":1}
	scene.sim.gain_xp(12)
	scene.show_level()
	await process_frame
	await process_frame
	var offers = scene.sim.current_offers.duplicate()
	var grades = scene.sim.offer_quality.duplicate()
	var scroll = scene.hud.scroll_container
	check(scene.hud.content.get_global_rect().end.x<=scroll.get_v_scroll_bar().global_position.x+1,"content stays clear of wide scrollbar instead of being clipped behind it")
	check(scroll.get_v_scroll_bar().size.x>=44,"scrollbar has 44px touch area")
	var close_buttons = scene.hud.modal.find_children("*","Button",true,false).filter(func(b): return b.text=="×")
	check(close_buttons.size()==1,"every modal has one close control")
	check(close_buttons[0].size.x>=48 and close_buttons[0].size.y>=48,"close control is touch sized")
	close_buttons[0].pressed.emit()
	check(scene.stage=="game" and not scene.sim.paused,"close defers mutation and resumes game")
	scene._process(0)
	check(scene.stage=="game","deferred choice does not immediately reopen")
	check(scene.sim.current_offers==offers and scene.sim.offer_quality==grades,"close preserves offer quality and IDs")
	check(scene.hud.pending_button.visible,"pending choice can be reopened from HUD")
	scene.open_pending()
	check(scene.stage=="level" and scene.sim.offer_quality==grades,"reopen keeps quality stable")
	scene.sim.pending_levels=0
	scene.sim.current_offers=[]
	scene.sim.offer_quality={}
	scene.sim.reward_queue.append({"tier":1,"token":"test-ui"})
	scene.show_reward()
	var rewards = scene.sim.reward_options.duplicate(true)
	scene.close_modal()
	scene._process(0)
	check(scene.stage=="game" and scene.sim.reward_queue.size()==1,"reward close preserves queue")
	scene.open_pending()
	check(scene.stage=="reward" and scene.sim.reward_options==rewards,"reward options stable on reopen")
	var choice = rewards.size()-1
	scene.reward_reveal.skip()
	scene.claim_reward(choice)
	check(scene.sim.reward_queue.is_empty(),"reward claim consumes exactly one queued reward")
	check(scene.stage=="game","claimed reward returns to game")
	scene.sim.combat_stats.damage_dealt=25.0
	scene.sim.elapsed=5.0
	scene.sim.last_damage={"amount":3.0,"name":"Тестовый хищник"}
	scene.hud.update_game(scene.sim)
	check("Тестовый хищник" in scene.hud.damage_source.text,"HUD identifies incoming damage source")
	scene.show_development()
	scene._lineage().show_statistics()
	check(has_text(scene.hud.content,"средний за время учёта"),"actual DPS clearly labeled run average")
	scene._lineage().show_body(true)
	var organ=scene._lineage().state().equipped.filter(func(part):return part.kind=="tentacle")[0]
	scene._lineage().show_part(organ.id)
	check(has_text(scene.hud.content,"дальность %.1f" % ((165+scene.sim.build.rank("tentacle")*12)*scene.sim.body_radius()/34.0)),"organ inspector uses actual world range rather than display-size scale")
	check(has_text(scene.hud.content,"до сопротивления"),"inspector damage labels resistance limit")
	scene._lineage().show_part(organ.id,"growth")
	check(has_text(scene.hud.content,"/6 +"),"evolution recipe shows required/current ranks")
	scene._lineage().show_body(true)
	scene.show_development(true)
	check(scene.stage=="organ_mutations" and has_text(scene.hud.content,"Последние повреждения"),"incoming history has a direct journal view")
	scene.show_development(false)
	check(scene.stage=="development" and has_text(scene.hud.content,"Тело"),"journal can return to build without resuming battle")
	scene.store.clear_test_files()
	scene.queue_free()
	await process_frame
	print("UI REWARDS: %d failures" % failures)
	quit(0 if failures==0 else 1)
