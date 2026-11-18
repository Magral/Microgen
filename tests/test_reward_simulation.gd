extends SceneTree
const Inspector=preload("res://core/build_inspector.gd")
const Catalog=preload("res://core/catalog.gd")
const Build=preload("res://core/build_model.gd")
const Sim=preload("res://game/simulation.gd")
var failures=0
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func fresh():
	var s=Sim.new();s.new_run(44);s.enemies.clear();s.pickups.clear();s.fields.clear();return s
func _initialize():call_deferred("run")
func run():
	for id in Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys():
		var inspected=Build.new();inspected.unlocked.append(id)
		if id in Catalog.ORGANS:inspected.organs[id]=1
		else:inspected.adaptations[id]=1
		check(not Inspector.effect_text(inspected,id,1.4,0.88).is_empty(),"every organ and passive has a numerical inspector: "+id)
		check(not Inspector.comparison(inspected,id,2,"",1.4,0.88).is_empty(),"every quality comparison formats safely: "+id)
	var s=fresh()
	s.build.organs={"tentacle":6};s.build.qualities={"tentacle":2};s.build.adaptations={"magnet":3}
	s.spawn_enemy(s.player+Vector2(100,0),"hunter")
	var e=s.enemies.back();e.hp=100;e.max_hp=100;e.tissue_budget=100
	var dealt=s.hit_enemy(e,10,"tentacle")
	check(is_equal_approx(dealt,12.5) and is_equal_approx(s.combat_stats.damage_dealt,dealt),"quality scales real damage and attributed totals equally")
	s.reward_queue=[{"token":"evolution-test","tier":2}]
	var options=s.prepare_reward().duplicate(true)
	check(options[0].kind=="evolution","qualified organ/passive offers evolution in epic reward")
	var loaded=Sim.new()
	check(loaded.restore(JSON.parse_string(JSON.stringify(s.snapshot()))),"reward checkpoint survives actual JSON")
	check(loaded.prepare_reward()==options,"reopening after restore cannot reroll stable rewards")
	check(not loaded.claim_reward(99) and loaded.reward_queue.size()==1,"invalid claim leaves reward pending")
	check(loaded.claim_reward(0) and loaded.build.evolved("tentacle"),"evolution grant is real and atomic")
	check(not loaded.claim_reward(0),"reward cannot be claimed twice")
	var temporary=fresh();temporary.build.organs={"acid":2}
	var baseline_power=temporary.build.power("acid")
	check(temporary.build.apply_temporary_mutation("acid_vesicles",2),"temporary mutation can be installed")
	check(temporary.build.power("acid")>baseline_power and temporary.build.temporary_mutation_rank("acid_vesicles")==1,"temporary mutation changes its documented organ power")
	temporary.reward_queue=[{"token":"temporary-reward","tier":2}]
	temporary.reward_options=[{"kind":"temporary","id":"charged_nucleus","quality":2}]
	var temp_checkpoint=Sim.new();check(temp_checkpoint.restore(JSON.parse_string(JSON.stringify(temporary.snapshot()))),"temporary mutation survives checkpoint JSON restore")
	check(temp_checkpoint.claim_reward(0) and temp_checkpoint.build.temporary_mutation_rank("charged_nucleus")==1,"temporary mutation cyst reward claims exactly once")
	temp_checkpoint.new_run(55)
	check(temp_checkpoint.build.temporary_mutations.is_empty(),"new life clears all temporary mutations")
	loaded.enemies[0].tissue_budget=100
	check(is_equal_approx(loaded.hit_enemy(loaded.enemies[0],10,"tentacle"),16.25),"evolved quality damage follows visible multipliers")
	var h=fresh();h.hp=50;h.build.organs={};h.build.adaptations={"armor":1}
	h.hurt_player(10,{"kind":"projectile","name":"Плюющая амёба","pos":h.player+Vector2(100,0),"id":9})
	check(is_equal_approx(h.hp,41.2) and is_equal_approx(h.combat_stats.blocked,1.2),"actual health damage and armor prevention are separately recorded")
	check(h.last_damage.kind=="projectile" and h.last_damage.source_id==9 and h.damage_markers.size()==1,"incoming damage retains identity and directional marker")
	h.heal_player(100)
	check(h.hp==h.max_hp and is_equal_approx(h.combat_stats.healed,58.8),"healing statistics count health restored only")
	h.build.adaptations={};h.fields.clear();h._field(h.player,60,6,2,"enemy_toxin",true,"Токсин охотника",17)
	h._update_fields(0.5)
	check(h.last_damage.kind=="toxin" and h.last_damage.name=="Токсин охотника","hazard ticking damage has a visible named source")
	var c=fresh();c.cysts.clear();c._spawn_cyst(c.player,3,"test-contact")
	c._update_cysts(0.1)
	check(c.cysts.size()==1 and c.cysts[0].captured and c.reward_queue.is_empty(),"cyst contact starts visible digestion before reward")
	for i in range(8):c._update_cysts(0.1)
	check(c.cysts.is_empty() and c.reward_queue.size()==1,"fully digested cyst grants exactly one reward")
	var snap=c.snapshot();snap.erase("combat_stats");snap.erase("pending_inventory");snap.elapsed=200
	var old=Sim.new();check(old.restore(JSON.parse_string(JSON.stringify(snap))),"legacy statistics-free checkpoint migrates")
	check(old.combat_stats.tracking_start==200 and old.pending_inventory.is_empty(),"old save migrates missing combat history and inventory queue safely")
	var obsolete=fresh()
	obsolete.build.organs={"tentacle":9007199254740991,"acid":9007199254740991,"spikes":9007199254740991}
	obsolete.build.qualities={"tentacle":3,"acid":3,"spikes":3}
	obsolete.reward_queue=[{"token":"deferred-stale","tier":1}]
	obsolete.reward_options=[{"kind":"mutation","id":"tentacle","quality":1},{"kind":"mutation","id":"acid","quality":1},{"kind":"mutation","id":"spikes","quality":1}]
	var rng_before=obsolete.rng.state
	check(obsolete.prepare_reward().all(func(option):return option.kind=="biomass"),"deferred capped rewards become fixed biomass instead of blocking queue")
	check(obsolete.rng.state==rng_before,"obsolete reward conversion does not reroll RNG")
	check(obsolete.claim_reward(1) and obsolete.build.biomass==40,"converted reward can be claimed exactly once")
	print("REWARD SIMULATION: %d failures"%failures)
	quit(0 if failures==0 else 1)
