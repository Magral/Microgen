extends SceneTree
const Equipment = preload("res://core/organism_equipment.gd")
var failures = 0
func check(ok: bool, text: String):
	if not ok:
		failures += 1
		push_error(text)
func has_text(node,needle: String) -> bool:
	if node is Label and needle in node.text: return true
	if node is Button and needle in node.text: return true
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
	check(has_text(scene.hud.content,"Урон"),"inspector shows the organ's key combat output")
	scene._lineage().show_part(organ.id,"growth")
	check(has_text(scene.hud.content,"Ловчая корона") and has_text(scene.hud.content,"Улучшить · ранг %d → %d"%[int(organ.rank),int(organ.rank)+1]),"growth tab shows this organ's evolution and exact next rank")
	scene._lineage().show_body(true)
	scene.show_development(true)
	check(scene.stage=="organ_mutations" and has_text(scene.hud.content,"Последние повреждения"),"incoming history has a direct journal view")
	scene.show_development(false)
	check(scene.stage=="development" and has_text(scene.hud.content,"Тело"),"journal can return to build without resuming battle")
	var flow=scene._lineage()
	var identity=flow.state()
	var n=int(identity.next_id)
	identity.body_capacity+=2
	identity.equipped.append({"id":"organ-%d"%n,"kind":"acid","cells":2,"rank":6,"quality":3,"evolved":true})
	identity.reserve.append({"id":"organ-%d"%(n+1),"kind":"acid","cells":2,"rank":1,"quality":0})
	identity.next_id=n+2
	check(flow.commit_state(identity),"identity fixture persists distinct same-kind organs")
	flow.show_part("organ-%d"%(n+1))
	check(not has_text(scene.hud.content,"ответная кислота"),"plain archived organ inspector does not borrow equipped evolution")
	flow.show_part("organ-%d"%n)
	check(has_text(scene.hud.content,"ответная кислота"),"evolved organ inspector retains its own behavior")
	scene.show_atlas()
	check(scene.stage=="atlas" and has_text(scene.hud.content,"Временные мутации"),"Codex groups run-only mutations separately")
	scene.codex_view.open_category("temporary",0)
	var mutation_button=scene.hud.content.find_children("*","Button",true,false).filter(func(button):return "Кислотные везикулы" in button.text)
	check(not mutation_button.is_empty(),"Codex lists the detailed mutation entry")
	if not mutation_button.is_empty():mutation_button[0].pressed.emit()
	check(scene.stage=="codex_entry" and has_text(scene.hud.content,"Кислота +12%"),"Codex describes temporary mutation effects on the organism")
	scene.close_modal()
	scene.continue_run()
	scene.deferred_choices = true
	scene.sim._spawn_cyst(scene.sim.player, 2, "fresh-during-deferral")
	var fresh_cyst = scene.sim.cysts.back()
	fresh_cyst.captured = true
	fresh_cyst.progress = 0.99
	scene._process(0.02)
	check(scene.stage == "reward" and scene.sim.reward_queue.size() == 1, "a newly digested cyst reopens reward choice after an older choice was deferred")
	scene.close_modal()
	flow.live_mode = true
	var exchange = flow.state()
	exchange.equipped = []
	exchange.body_capacity = 6
	for kind in ["devour", "acid", "spikes"]:
		exchange = Equipment.award(exchange, kind).state
	check(flow.commit_state(exchange), "full body fixture persists")
	scene.sim.reward_queue = [{"token":"exchange-cyst", "tier":3}]
	scene.sim.reward_options = [{"kind":"mutation", "id":"division", "quality":3}]
	scene.show_reward()
	scene.reward_reveal.skip()
	scene.claim_reward(0)
	check(scene.stage == "replace", "oversized cyst trophy opens the actual family exchange")
	var outgoing = exchange.equipped.filter(func(part):return part.kind != "devour").map(func(part):return part.id)
	scene.replacement_selected = outgoing
	scene._show_organ_replacement()
	var confirm = scene.hud.content.find_children("*", "Button", true, false).filter(func(b):return b.text == "Применить")
	check(confirm.size() == 1 and not confirm[0].disabled, "two organs free enough space for the incoming trophy")
	if not confirm.is_empty():confirm[0].pressed.emit()
	var persisted = scene.store.profile.organism
	check(persisted.equipped.any(func(part):return part.kind == "division" and part.quality == 3) and scene.sim.build.rank("division") == 1, "installed organ remains in combat and in the checkpoint")
	check(persisted.stock.filter(func(part):return part.id in outgoing).size() + persisted.reserve.filter(func(part):return part.id in outgoing).size() == 2, "both replaced organs keep their IDs")
	check(scene.sim.reward_queue.is_empty(), "successful exchange consumes one reward")
	scene.sim.build.organs["barrier"] = 1
	scene.hud.update_game(scene.sim)
	check(scene.hud.hp_bar.custom_minimum_size.x == 240 and scene.hud.shield_label.visible and scene.hud.shield_bar.value == 100, "compact health and ready shield are distinct")
	scene.sim.hurt_player(8)
	scene.hud.update_game(scene.sim)
	check("восстановление" in scene.hud.shield_label.text and scene.hud.shield_bar.value == 0, "blocked hit starts visible shield recovery")
	scene.store.clear_test_files()
	scene.queue_free()
	await process_frame
	print("UI REWARDS: %d failures" % failures)
	quit(0 if failures==0 else 1)
