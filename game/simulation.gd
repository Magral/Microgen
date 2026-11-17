extends RefCounted
const World = preload("res://game/world.gd")
const Build = preload("res://core/build_model.gd")
const Catalog = preload("res://core/catalog.gd")
var world = World.new()
var build = Build.new()
var rng = RandomNumberGenerator.new()
var player = Vector2.ZERO
var hp = 100.0
var max_hp = 100.0
var elapsed = 0.0
var xp = 0.0
var level = 1
var pending_levels = 0
var enemies: Array = []
var pickups: Array = []
var fields: Array = []
var shots: Array = []
var effects: Array = []
var events: Array = []
var explored: Dictionary = {}
var cooldowns: Dictionary = {}
var paused = false
var outcome = ""
var spawn_timer = 0.0
var invuln = 0.0
var boss_spawned = false
var kills = 0
var cores_found = 0
var next_id = 0
var run_id = ""
var upgrades: Dictionary = {}
var current_offers: Array = []
var rerolls = 0
var boss_marker = Vector2.ZERO
var last_tile = Vector2i(-100,-100)

func new_run(seed_value: int, unlocked: Array = Catalog.base_unlocked(), permanent: Dictionary = {}, selected_branch: String = "predator"):
	rng.seed = seed_value
	world.generate(seed_value)
	build = Build.new()
	build.unlocked = unlocked.duplicate()
	build.branch = selected_branch
	build.apply("tentacle")
	upgrades = permanent.duplicate()
	max_hp = 100.0+float(upgrades.get("health",0))*5.0
	hp = max_hp
	player = world.start
	run_id = "%d-%d" % [seed_value,Time.get_ticks_usec()]
	for nutrient in world.nutrients:
		pickups.append({"pos":nutrient.pos,"type":"dna","amount":8 if nutrient.rich else 3,"id":next_id})
		next_id += 1
	for colony in world.colonies:
		var organ_pool = build.unlocked.filter(func(id): return id in Catalog.ORGANS)
		var stock = []
		for i in range(2):
			if organ_pool.is_empty(): break
			var pool = organ_pool.filter(func(id): return Catalog.item(id).get("branch","") == ("toxic" if world.biome(colony.pos) == 1 else "predator"))
			var source = pool if not pool.is_empty() else organ_pool
			var id = source[rng.randi_range(0,source.size()-1)]
			organ_pool.erase(id)
			stock.append({"id":id,"price":18+rng.randi_range(0,6),"sold":false})
		stock.append({"id":"heal","price":12,"sold":false})
		colony.stock = stock
	_reveal()
	# Enough near-start food for a quick first mutation.
	for i in range(8):
		var p = player + Vector2.from_angle(i*TAU/8.0)*rng.randf_range(70,220)
		pickups.append({"pos":p,"type":"dna","amount":3,"id":next_id})
		next_id += 1

func xp_needed() -> float:
	return 12.0+float(level-1)*6.0

func gain_xp(amount: float):
	xp += amount
	while xp >= xp_needed():
		xp -= xp_needed()
		level += 1
		pending_levels += 1

func step(dt: float,direction: Vector2):
	if paused or outcome != "": return
	dt = clampf(dt,0,0.5)
	elapsed += dt
	invuln = maxf(0,invuln-dt)
	var condition = world.conditions[world.biome(player)]
	var speed = 190.0*(1.0+build.rank("speed")*0.12)*(0.85 if condition == 1 else 1.0)
	player = world.move_body(player,direction.limit_length()*speed*dt,22)
	hp = minf(max_hp,hp+(build.rank("regen")*0.5+float(upgrades.get("regen",0))*0.1)*dt)
	_reveal()
	for k in cooldowns: cooldowns[k] = maxf(0,cooldowns[k]-dt)
	spawn_timer -= dt
	if spawn_timer <= 0:
		spawn_timer = maxf(0.24,1.4-elapsed/650.0)
		_spawn_wave()
	if elapsed >= 600.0 and not boss_spawned:
		boss_spawned = true
		boss_marker = world.boss_pos
		if enemies.size() >= 140: enemies.pop_front()
		spawn_enemy(world.boss_pos,"boss")
		events.append({"type":"message","text":"Пробудился Архицит! Найди его на карте."})
	_check_nests()
	_update_enemies(dt)
	if outcome != "": return
	_attack_dt = dt
	_attack()
	_update_shots(dt)
	_update_fields(dt)
	_collect(dt)
	for i in range(effects.size()-1,-1,-1):
		effects[i].life -= dt
		if effects[i].life<=0: effects.remove_at(i)
	if hp <= 0:
		outcome = "death"
		events.append({"type":"end","outcome":"death"})

func _reveal():
	var c = world.tile(player)
	if c == last_tile: return
	last_tile = c
	for y in range(maxi(0,c.y-4),mini(World.H,c.y+5)):
		for x in range(maxi(0,c.x-4),mini(World.W,c.x+5)):
			if Vector2(x-c.x,y-c.y).length()<=4.5: explored[y*World.W+x] = true
	for shop in world.colonies:
		if player.distance_to(shop.pos)<550: shop.visited = true

func _spawn_wave():
	if enemies.size()>=140: return
	var count = 1+int(elapsed/110.0)
	for i in range(count):
		if enemies.size()>=140: break
		for attempt in range(12):
			var p = player+Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(650,900)
			if not world.walkable(p,25): continue
			if _safe_zone(p): continue
			var kind = "prey" if rng.randf()<0.24 else ("spitter" if world.biome(p)==1 and rng.randf()<0.3 else "hunter")
			spawn_enemy(p,kind)
			break

func _safe_zone(p: Vector2) -> bool:
	for colony in world.colonies:
		if p.distance_squared_to(colony.pos)<150.0*150.0: return true
	return false

func spawn_enemy(p: Vector2,kind: String):
	if enemies.size()>=140: return
	var boss = kind == "boss"
	var prey = kind == "prey"
	var variant = rng.randi_range(0,3)
	var health = (8.0 if prey else 22.0+elapsed*0.13)*(1.4 if variant == 1 else 1.0)
	if boss: health = 1600.0
	enemies.append({"pos":p,"kind":kind,"hp":health,"max_hp":health,"r":12.0 if prey else (66.0 if boss else 23.0+rng.randf()*6),"speed":58.0 if prey else (66.0 if boss else 65.0+minf(60,elapsed*0.08)+(25 if variant==2 else 0)),"phase":rng.randf()*TAU,"variant":variant,"infect":0.0,"slow":0.0,"shot_cd":2.5,"id":next_id,"biome":world.biome(p)})
	next_id += 1

func _update_enemies(dt: float):
	for i in range(enemies.size()-1,-1,-1):
		var e = enemies[i]
		if e.hp <= 0:
			_die(i,false)
			continue
		e.slow = maxf(0,e.slow-dt)
		if e.infect>0:
			e.infect -= dt
			e.hp -= (4.0+build.rank("infection")*3.0)*dt
		var offset = player-e.pos
		var dist = offset.length()
		if dist>1600 and e.kind != "boss":
			enemies.remove_at(i)
			continue
		var threshold = e.max_hp*(0.12+build.rank("devour")*0.07)
		if dist < 27+e.r and (e.kind == "prey" or (e.kind != "boss" and e.hp<=threshold and build.rank("devour")>0)):
			_die(i,true)
			continue
		var dir = offset.normalized()
		if e.kind == "prey": dir = -dir if dist<180 else dir.rotated(e.phase)
		if e.kind == "spitter" and dist<300: dir = -dir*0.3
		if _safe_zone(player) and e.kind != "prey": dir = -dir
		e.pos = world.move_body(e.pos,dir*e.speed*dt*(0.35 if e.slow>0 else 1.0),e.r*0.6)
		if e.kind=="boss": boss_marker = e.pos
		if e.kind == "spitter" or e.kind == "boss":
			e.shot_cd -= dt
			if e.shot_cd<=0 and dist<850:
				e.shot_cd = 2.0 if e.kind=="spitter" else 1.5
				if e.kind == "boss":
					for n in range(10): _shot(e.pos,Vector2.from_angle(n*TAU/10.0+elapsed*0.2)*135,10,true)
				else: _shot(e.pos,offset.normalized()*155,8,true)
		if dist<e.r+21 and e.kind != "prey" and invuln<=0 and not _safe_zone(player):
			hp -= (10.0 if e.kind!="boss" else 22.0)*(1.0-build.rank("armor")*0.12)
			invuln = 0.65
			e.pos = world.move_body(e.pos,-offset.normalized()*30,e.r*0.6)
			effects.append({"type":"hurt","pos":player,"life":0.3,"max":0.3,"r":45.0})
		if e.hp<=0: _die(i,false)

func _die(index: int,absorbed: bool):
	var e = enemies[index]
	enemies.remove_at(index)
	kills += 1
	if absorbed:
		gain_xp(4 if e.kind=="prey" else 6)
		build.biomass += 1 if e.kind=="prey" else 3
		hp = minf(max_hp,hp+build.rank("devour")*0.8)
		if e.infect>0 and "spore_feast" in build.active_synergies(): _field(e.pos,100,14,2.5,"spore")
	else:
		_drop(e.pos,"dna",5 if e.kind!="boss" else 80)
		_drop(e.pos+Vector2(8,8),"bio",2 if e.kind!="boss" else 40)
	if e.kind == "boss":
		outcome = "victory"
		events.append({"type":"core","token":run_id+":boss","amount":12})
		events.append({"type":"end","outcome":"victory"})
	elif kills%18 == 0:
		_drop(e.pos,"core",1)
	effects.append({"type":"burst","pos":e.pos,"life":0.4,"max":0.4,"r":e.r+20})

func _drop(p: Vector2,kind: String,amount: int):
	if pickups.size()>=600:
		# Merge into same resource, retaining the persistent token of the receiver.
		for item in pickups:
			if item.type==kind:
				item.amount += amount
				return
		# Compact two pickups of the same resource rather than deleting a rare new drop.
		var first_by_type = {}
		for i in range(pickups.size()):
			var existing = pickups[i]
			if existing.type in first_by_type:
				var first = int(first_by_type[existing.type])
				pickups[first].amount += existing.amount
				pickups.remove_at(i)
				break
			first_by_type[existing.type] = i
	pickups.append({"pos":p,"type":kind,"amount":amount,"id":next_id})
	next_id += 1

func _nearest(radius: float) -> Dictionary:
	var nearest = {}
	var best = radius*radius
	for e in enemies:
		var d = player.distance_squared_to(e.pos)
		if d<best:
			best = d
			nearest = e
	return nearest

func _attack():
	var metabolic = 0.88 if world.conditions[world.biome(player)] == 2 else 1.0
	var synergies = build.active_synergies()
	if build.rank("tentacle")>0 and cooldowns.get("tentacle",0)<=0:
		var target = _nearest(165.0+build.rank("tentacle")*12)
		if not target.is_empty():
			cooldowns.tentacle = 0.85*metabolic
			target.hp -= 9.0+build.rank("tentacle")*7
			effects.append({"type":"lash","pos":player,"end":target.pos,"life":0.22,"max":0.22,"r":0})
			if "acid_grasp" in synergies:
				target.slow = 1.3
				target.pos = world.move_body(target.pos,(player-target.pos).limit_length(65),target.r*0.6)
	if build.rank("acid")>0:
		for e in enemies:
			if player.distance_squared_to(e.pos)<pow(75+build.rank("acid")*9,2): e.hp -= (4+build.rank("acid")*3)*_attack_dt
	if build.rank("spikes")>0 and cooldowns.get("spikes",0)<=0:
		var target = _nearest(650)
		if not target.is_empty():
			cooldowns.spikes = 1.3*metabolic
			var dir = (target.pos-player).normalized()
			for i in range(1+int(build.rank("spikes")/2.0)):
				_shot(player,dir.rotated((i-build.rank("spikes")/4.0)*0.13)*450,12+build.rank("spikes")*5,false)
	if build.rank("pulse")>0 and cooldowns.get("pulse",0)<=0:
		cooldowns.pulse = 3.2*metabolic
		var radius = 130+build.rank("pulse")*18
		for e in enemies:
			if player.distance_squared_to(e.pos)<radius*radius:
				e.hp -= 12+build.rank("pulse")*8
				e.pos = world.move_body(e.pos,(e.pos-player).normalized()*65,e.r*0.6)
		effects.append({"type":"pulse","pos":player,"r":float(radius),"life":0.55,"max":0.55})
		if "spike_pulse" in synergies:
			for i in range(8): _shot(player,Vector2.from_angle(i*TAU/8.0)*370,18+build.rank("spikes")*4,false)
	if build.rank("infection")>0 and cooldowns.get("infection",0)<=0:
		var target = _nearest(420)
		if not target.is_empty():
			target.infect = 4.5
			cooldowns.infection = 1.6*metabolic
	if build.rank("trail")>0 and cooldowns.get("trail",0)<=0:
		cooldowns.trail = 0.6
		_field(player,50+build.rank("trail")*6,5+build.rank("trail")*3,3.0,"poison")
		if "toxic_colony" in synergies:
			for p in clone_positions(): _field(p,40,3+build.rank("trail")*1.5,2,"poison")
	if build.rank("division")>0:
		for p in clone_positions():
			for e in enemies:
				if p.distance_squared_to(e.pos)<pow(e.r+18,2): e.hp -= (8+build.rank("division")*4)*_attack_dt

var _attack_dt = 0.016

func clone_positions() -> Array:
	var out = []
	for i in range(1+build.rank("division")):
		out.append(player+Vector2.from_angle(elapsed*1.6+i*TAU/(1+build.rank("division")))*105)
	return out

func _shot(p: Vector2,velocity: Vector2,damage: float,hostile: bool):
	if shots.size()>=200: return
	shots.append({"pos":p,"vel":velocity,"damage":damage,"hostile":hostile,"life":2.0})

func _update_shots(dt: float):
	_attack_dt = dt
	# Bucket enemy positions: projectiles inspect nearby cells instead of every enemy.
	var buckets = {}
	for e in enemies:
		var key = Vector2i(e.pos/100.0)
		if not key in buckets: buckets[key] = []
		buckets[key].append(e)
	for i in range(shots.size()-1,-1,-1):
		var shot = shots[i]
		shot.life -= dt
		shot.pos += shot.vel*dt
		var hit = false
		if shot.hostile:
			if shot.pos.distance_squared_to(player)<28*28:
				hit = true
				if invuln<=0 and not _safe_zone(player):
					hp -= shot.damage*(1-build.rank("armor")*0.12)
					invuln = 0.4
		else:
			var cell = Vector2i(shot.pos/100.0)
			for y in range(-1,2):
				for x in range(-1,2):
					for e in buckets.get(cell+Vector2i(x,y),[]):
						if not hit and shot.pos.distance_squared_to(e.pos)<pow(e.r+8,2):
							e.hp -= shot.damage
							hit = true
		if hit or shot.life<=0 or not world.walkable(shot.pos): shots.remove_at(i)

func _field(p: Vector2,radius: float,damage: float,life: float,kind: String):
	if fields.size()>=80: fields.pop_front()
	fields.append({"pos":p,"r":radius,"damage":damage,"life":life,"max":life,"kind":kind})

func _update_fields(dt: float):
	for i in range(fields.size()-1,-1,-1):
		var f = fields[i]
		f.life -= dt
		for e in enemies:
			if f.pos.distance_squared_to(e.pos)<pow(f.r+e.r*0.5,2): e.hp -= f.damage*dt
		if f.life<=0: fields.remove_at(i)

func _collect(dt: float):
	var radius = 80+build.rank("magnet")*35+float(upgrades.get("collect",0))*8
	for i in range(pickups.size()-1,-1,-1):
		var item = pickups[i]
		var dist = player.distance_to(item.pos)
		if dist<radius:
			item.pos = item.pos.move_toward(player,dt*(220+400*(1-dist/radius)))
			if dist<28:
				if item.type == "dna": gain_xp(item.amount)
				elif item.type == "bio": build.biomass += int(item.amount)
				else:
					cores_found += item.amount
					events.append({"type":"core","token":run_id+":"+str(item.id),"amount":int(item.amount)})
				pickups.remove_at(i)

func _check_nests():
	for nest in world.nests:
		if nest.used or player.distance_squared_to(nest.pos)>100*100: continue
		nest.used = true
		if nest.kind == 0:
			gain_xp(20)
			events.append({"type":"message","text":"Найден древний геном: +20 ДНК"})
		elif nest.kind == 1:
			build.biomass += 20
			events.append({"type":"message","text":"Питательный сгусток: +20 биомассы"})
		else:
			_drop(nest.pos,"core",2)
			for i in range(5):
				var p = nest.pos+Vector2.from_angle(i*TAU/5)*200
				if world.walkable(p,25): spawn_enemy(p,"hunter")
			events.append({"type":"message","text":"Паразитический очаг! Защити найденное ядро."})

func nearby_colony() -> int:
	for i in range(world.colonies.size()):
		if player.distance_squared_to(world.colonies[i].pos)<150*150: return i
	return -1

func snapshot() -> Dictionary:
	return {"version":1,"outcome":outcome,"events":_pack(events),"seed":world.seed_value,"rng_state":str(rng.state),"run_id":run_id,"player":_vec(player),"hp":hp,"max_hp":max_hp,"elapsed":elapsed,"xp":xp,"level":level,"pending_levels":pending_levels,"build":build.to_dict(),"enemies":_pack(enemies),"pickups":_pack(pickups),"colonies":_pack(world.colonies),"nests":_pack(world.nests),"explored":explored.keys(),"boss_spawned":boss_spawned,"kills":kills,"cores_found":cores_found,"next_id":next_id,"upgrades":upgrades,"cooldowns":cooldowns.duplicate(),"offers":current_offers.duplicate(),"rerolls":rerolls,"fields":_pack(fields),"shots":_pack(shots)}

func restore(data: Dictionary) -> bool:
	if data.get("version",0) != 1 or not data.get("player",null) is Array: return false
	for key in ["enemies","pickups","colonies","nests","explored"]:
		if not data.get(key,null) is Array: return false
	world.generate(int(data.get("seed",0)))
	rng.seed = int(data.seed)
	rng.state = int(data.get("rng_state","0"))
	player = Vector2(data.player[0],data.player[1])
	if not world.walkable(player,22): player = world.start
	outcome = str(data.get("outcome",""))
	events = _unpack(data.get("events",[]))
	hp = float(data.get("hp",100))
	max_hp = float(data.get("max_hp",100))
	elapsed = float(data.get("elapsed",0))
	xp = float(data.get("xp",0))
	level = int(data.get("level",1))
	pending_levels = int(data.get("pending_levels",0))
	build.from_dict(data.get("build",{}))
	enemies = _unpack(data.enemies)
	pickups = _unpack(data.pickups)
	world.colonies = _unpack(data.colonies)
	world.nests = _unpack(data.nests)
	for idx in data.explored: explored[int(idx)] = true
	boss_spawned = data.get("boss_spawned",false)
	boss_marker = world.boss_pos if boss_spawned else Vector2.ZERO
	for enemy in enemies:
		if enemy.kind=="boss": boss_marker = enemy.pos
	kills = int(data.get("kills",0))
	cores_found = int(data.get("cores_found",0))
	next_id = int(data.get("next_id",0))
	run_id = str(data.get("run_id","restored"))
	upgrades = data.get("upgrades",{})
	cooldowns = data.get("cooldowns",{})
	current_offers = data.get("offers",[])
	rerolls = int(data.get("rerolls",0))
	fields = _unpack(data.get("fields",[]))
	shots = _unpack(data.get("shots",[]))
	return true

func _vec(v: Vector2) -> Array: return [v.x,v.y]

func _pack(source: Array) -> Array:
	var out = []
	for entry in source:
		var copy = entry.duplicate(true)
		for k in copy:
			if copy[k] is Vector2: copy[k] = _vec(copy[k])
		out.append(copy)
	return out

func _unpack(source: Array) -> Array:
	var out = []
	for entry in source:
		var copy = entry.duplicate(true)
		for k in ["pos","vel"]:
			if copy.get(k,null) is Array and copy[k].size()==2: copy[k] = Vector2(copy[k][0],copy[k][1])
		out.append(copy)
	return out
