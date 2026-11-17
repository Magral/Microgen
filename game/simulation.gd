extends RefCounted
const World = preload("res://game/world.gd")
const Build = preload("res://core/build_model.gd")
const Catalog = preload("res://core/catalog.gd")
const Genome = preload("res://core/genome.gd")
const TissueDamage=preload("res://game/tissue_damage.gd")
const CombatTissue=preload("res://core/combat_tissue.gd")
const CombatStats=preload("res://core/combat_stats.gd")
const Rewards=preload("res://core/rewards.gd")
var combat_stats: Dictionary=CombatStats.create()
var last_damage: Dictionary={}
var damage_markers: Array=[]
var cysts: Array=[]
var reward_queue: Array=[]
var reward_options: Array=[]
var offer_quality: Dictionary={}
var claimed_rewards: Array=[]
var feedback: Array=[]
var minibosses_spawned=0
var next_miniboss_at=180.0
var _danger_at=-10.0
const SizeRules=preload("res://core/size_rules.gd")
var facing=0.0
var bite_flash=0.0
var _cached_contact_polygon=PackedVector2Array()
var _cached_contact_radius=-1.0
var _cached_contact_health=-1.0
var _cached_contact_hash=0
const Growth=preload("res://core/growth.gd")
var residents: Array=[]
var previous_player=Vector2.ZERO
var contact_contour=PackedVector2Array()
const Pigment = preload("res://core/pigment.gd")
var tissue_pigment: Dictionary = {}
const ENEMY_CAP = 28
const REMAINS_CAP = 96
var player_velocity = Vector2.ZERO
var remains: Array = []
var digesting_id: int = -1
var player_genome: Dictionary = {}
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
	combat_stats=CombatStats.create();last_damage={};damage_markers=[];cysts=[];reward_queue=[];reward_options=[];offer_quality={};claimed_rewards=[]
	rng.seed = seed_value
	world.generate(seed_value)
	player_genome = Genome.create(seed_value,0,"player",0)
	facing=float(player_genome.rotation)
	_cached_contact_polygon=PackedVector2Array()
	contact_contour=PackedVector2Array()
	tissue_pigment = Pigment.create(Genome.colors(player_genome)[0])
	build = Build.new()
	build.unlocked = unlocked.duplicate()
	build.branch = selected_branch
	build.apply("tentacle")
	upgrades = permanent.duplicate()
	max_hp = 100.0+float(upgrades.get("health",0))*5.0
	hp = max_hp
	player = world.start
	previous_player=player
	_create_residents()
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
	for i in range(12):
		var p=player+Vector2.from_angle(i*2.399)*float(85+i*27)
		if world.walkable(p,7): _drop(p,"heal",6)
	_create_cysts()
	_grade_stocks()
	_reveal()
	# Enough near-start food for a quick first mutation.
	for i in range(8):
		var p = player + Vector2.from_angle(i*TAU/8.0)*rng.randf_range(70,220)
		pickups.append({"pos":p,"type":"dna","amount":3,"id":next_id})
		next_id += 1

func _feedback(kind: String,position: Vector2,amount: float=0.0,source: String=""):
	if feedback.size()>=48:
		if kind=="hit":return
		var expendable=-1
		for i in range(feedback.size()):
			if feedback[i].kind=="hit":expendable=i;break
		if expendable>=0:feedback.remove_at(expendable)
		else:feedback.pop_front()
	feedback.append({"kind":kind,"pos":position,"amount":amount,"tier":int(amount),"source":source})

func hit_enemy(enemy: Dictionary,amount: float,source: String="unknown") -> float:
	if enemy.hp<=0 or enemy.get("captured",false):return 0.0
	var raw=maxf(0.0,amount)*(1.0+build.passive("catalysis"))*build.power(source)
	var budget=float(enemy.get("tissue_budget",enemy.max_hp*0.01))
	var dealt=minf(enemy.hp,minf(raw,budget))
	enemy.tissue_budget=maxf(0,budget-dealt)
	enemy.hp-=dealt
	if dealt>0:
		enemy.last_damage_source=source
		CombatStats.record_damage(combat_stats,source,dealt)
		_feedback("hit",enemy.pos,dealt)
		enemy.popup_damage=float(enemy.get("popup_damage",0))+dealt
		if elapsed-float(enemy.get("popup_at",-1))>=0.24 and enemy.popup_damage>=0.8:
			_effect({"type":"damage","pos":enemy.pos,"amount":enemy.popup_damage,"player":false,"r":0.0,"life":0.75,"max":0.75})
			enemy.popup_damage=0.0
			enemy.popup_at=elapsed
	return dealt

func heal_player(amount: float):
	var actual=maxf(0.0,minf(max_hp-hp,amount))
	hp+=actual
	CombatStats.record_heal(combat_stats,actual)

func hurt_player(amount: float,source: Dictionary={}):
	if hp<=0:return
	var incoming=maxf(0.0,amount)
	var damage=incoming*(1.0-build.passive("armor"))
	if build.rank("barrier")>0 and cooldowns.get("barrier",0)<=0:
		damage=maxf(0.0,damage-Catalog.scaled_damage(8+build.rank("barrier")*6,build.rank("barrier"))*build.power("barrier"))
		cooldowns.barrier=8.0
		_effect({"type":"pulse","pos":player,"r":body_radius()*1.4,"life":0.4,"max":0.4})
		_feedback("synergy",player)
	var actual=minf(maxf(0.0,hp),damage)
	var kind=str(source.get("kind","unknown"))
	var label=str(source.get("name","Неизвестный источник"))
	var origin: Vector2=source.get("pos",player)
	var entry=CombatStats.record_taken(combat_stats,elapsed,actual,incoming-damage,kind,label,origin,int(source.get("id",0)))
	if actual<=0:return
	hp-=actual
	last_damage=entry.duplicate(true)
	_feedback("hurt",origin,actual,kind)
	var marked=false
	for marker in damage_markers:
		if marker.kind==kind and marker.name==label and marker.pos.distance_squared_to(origin)<10000:
			marker.amount+=actual;marker.life=1.5;marker.pos=origin;marked=true;break
	if not marked:
		if damage_markers.size()>=6:damage_markers.pop_front()
		damage_markers.append({"pos":origin,"kind":kind,"name":label,"amount":actual,"life":1.5,"max":1.5})
	var merged=false
	for effect in effects:
		if effect.type=="damage" and effect.get("player",false) and effect.life>0.5:
			effect.amount+=actual;merged=true;break
	if not merged:_effect({"type":"damage","pos":player,"amount":actual,"player":true,"r":0.0,"life":0.75,"max":0.75})

func _enemy_label(enemy: Dictionary) -> String:
	if enemy.kind=="boss":return "Архицит"
	if enemy.kind=="miniboss":return str(enemy.get("title","Минибосс"))
	if enemy.kind=="spitter":return "Плюющая амёба"
	return "Крупная амёба" if enemy.r>body_radius()*1.08 else "Враждебная амёба"

func _update_minibosses():
	if minibosses_spawned>=2 or elapsed<next_miniboss_at or enemies.size()>=ENEMY_CAP:return
	var p=player+Vector2.from_angle(float(minibosses_spawned)*PI+0.3)*330
	if not world.walkable(p,25):p=world.nests[minibosses_spawned].pos if world.nests.size()>minibosses_spawned else world.boss_pos
	spawn_enemy(p,"miniboss")
	var enemy=enemies.back()
	enemy.r=clampf(body_radius()*1.22,48,110)
	enemy.max_hp=380.0+elapsed*0.2
	enemy.hp=enemy.max_hp
	enemy.speed=28.0
	enemy.title="Матриарх" if minibosses_spawned==0 else "Фагоцит"
	enemy.elite_token=run_id+":elite:"+str(minibosses_spawned)
	enemy.traits=["shell","toxic"] if minibosses_spawned==0 else ["shell","spores"]
	minibosses_spawned+=1
	next_miniboss_at=maxf(180*(minibosses_spawned+1),elapsed+90)
	_feedback("miniboss",p)
	events.append({"type":"message","text":"Минибосс: "+enemy.title})

var _radius_level=-1
var _radius_xp=-1.0
var _radius_value=22.0
func body_radius() -> float:
	if level!=_radius_level or xp!=_radius_xp:
		_radius_level=level
		_radius_xp=xp
		_radius_value=Growth.radius(level,xp/xp_needed())
	return _radius_value

func view_zoom() -> float:
	return Growth.zoom(body_radius())

func ability_scale() -> float:
	return body_radius()/34.0

func cooldown_factor() -> float:
	return 0.88 if world.conditions[world.biome(player)]==2 else 1.0

func _create_residents():
	residents.clear()
	var ecology_rng=RandomNumberGenerator.new()
	ecology_rng.seed=world.seed_value+991721
	for i in range(4):
		var anchor=player+Vector2.from_angle(0.15+i*1.65)*float(215+i*320)
		for attempt in range(30):
			var candidate=anchor+Vector2(ecology_rng.randf_range(-60,60),ecology_rng.randf_range(-60,60))
			if not world.walkable(candidate,26): continue
			residents.append({"id":-100-i,"pos":candidate,"r":72.0+i*2.0,"hp":360.0+i*60,"max_hp":360.0+i*60,"genome":Genome.create(world.seed_value,-100-i,"hunter",world.biome(candidate)),"active":false,"dead":false})
			break
		if residents.size()<=i:
			var candidate=player+Vector2(195,i*18-27)
			residents.append({"id":-100-i,"pos":candidate,"r":72.0+i*2.0,"hp":360.0+i*60,"max_hp":360.0+i*60,"genome":Genome.create(world.seed_value,-100-i,"hunter",0),"active":false,"dead":false})

func _update_ecology():
	for resident in residents:
		if resident.dead or resident.active or enemies.size()>=ENEMY_CAP: continue
		if player.distance_to(resident.pos)>650: continue
		if elapsed<8 and not _touches(resident.pos,resident.r):continue
		spawn_enemy(resident.pos,"hunter")
		var actor=enemies.back()
		actor.id=resident.id
		actor.resident_id=resident.id
		actor.r=resident.r
		actor.hp=resident.hp
		actor.max_hp=resident.max_hp
		actor.genome=resident.genome.duplicate(true)
		actor.speed=23.0
		resident.active=true

func _touches(position: Vector2,object_radius: float=0.0) -> bool:
	var start=previous_player
	var nearest=Geometry2D.get_closest_point_to_segment(position,start,player)
	var broad=body_radius()*1.7+object_radius
	if nearest.distance_squared_to(position)>broad*broad: return false
	var shape_hash=hash(contact_contour)
	var radius=body_radius()
	var health=hp/max_hp
	if _cached_contact_polygon.is_empty() or radius!=_cached_contact_radius or health!=_cached_contact_health or shape_hash!=_cached_contact_hash:
		var shape=contact_contour if not contact_contour.is_empty() else TissueDamage.contour(Genome.contour(player_genome),player_genome,health)
		_cached_contact_polygon=Transform2D(0,Vector2.ONE*radius,0,Vector2.ZERO)*shape
		_cached_contact_radius=radius
		_cached_contact_health=health
		_cached_contact_hash=shape_hash
	var polygon=_cached_contact_polygon
	var steps=maxi(1,ceili(start.distance_to(player)/maxf(4.0,body_radius()*0.3)))
	for step in range(steps+1):
		var relative=position-start.lerp(player,float(step)/steps)
		if Geometry2D.is_point_in_polygon(relative,polygon): return true
		for i in range(polygon.size()):
			if relative.distance_squared_to(Geometry2D.get_closest_point_to_segment(relative,polygon[i],polygon[(i+1)%polygon.size()]))<=pow(object_radius+3.0,2): return true
	return false

func attraction_radius() -> float:
	var rank=build.rank("magnet")
	return body_radius() if rank<=0 else body_radius()+build.passive("magnet")+float(upgrades.get("collect",0))*8

func _capture(item: Dictionary):
	item.captured=true
	item.internal=true
	item.entry_angle=(item.pos-player).angle()
	item.entry_distance=player.distance_to(item.pos)
	item.progress=clampf(float(item.get("progress",0)),0.0,0.7)
	item.duration=minf(0.65,float(item.get("duration",0.55)))
	item.vel=Vector2.ZERO

func body_color() -> Color:
	if tissue_pigment.is_empty(): tissue_pigment=Pigment.create(Genome.colors(player_genome)[0])
	return Pigment.color(tissue_pigment)

func _assimilate(recipe: Dictionary,amount: float,source: Vector2,material: Dictionary={}):
	if tissue_pigment.is_empty(): tissue_pigment=Pigment.create(Genome.colors(player_genome)[0])
	var pigment=Genome.colors(recipe)[0]
	if material.is_empty(): Pigment.feed(tissue_pigment,pigment,amount)
	else:
		Pigment.combine(tissue_pigment,material)
		tissue_pigment.mass=minf(80.0,tissue_pigment.mass)
		pigment=Pigment.color(material)
	_feedback("absorb",player)
	_effect({"type":"assimilate","pos":player,"end":source,"color":pigment,"r":36.0,"life":1.1,"max":1.1})

func _effect(value: Dictionary):
	if value.type in Catalog.SYNERGIES or value.type in ["electric","enzymes","cilia"]:_feedback("synergy",value.pos)
	if effects.size()>=160: effects.pop_front()
	effects.append(value)

func xp_needed() -> float:
	return 12.0+float(level-1)*6.0

func gain_xp(amount: float):
	xp += amount*(1.0+build.passive("metabolism"))
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
	previous_player=player
	var speed = (72.0+body_radius()*0.6)*(1.0+build.passive("speed"))*(0.85 if condition == 1 else 1.0)
	var desired = direction.limit_length()*speed
	var response = exp(-dt/0.2)
	var travel = desired*dt+(player_velocity-desired)*0.2*(1.0-response)
	player_velocity = desired+(player_velocity-desired)*response
	bite_flash=maxf(0.0,bite_flash-dt*4.5)
	player = world.move_body(player,travel,minf(26.0,body_radius()*0.65))
	var resolved_velocity=(player-previous_player)/maxf(0.001,dt)
	if resolved_velocity.length_squared()>4.0:facing=lerp_angle(facing,resolved_velocity.angle(),1.0-exp(-dt*9.0))
	var colony_regen=build.rank("division")*0.15 if "metabolic_colony" in build.active_synergies() else 0.0
	heal_player((build.passive("regen")+float(upgrades.get("regen",0))*0.1+colony_regen)*dt)
	if hp<max_hp*0.25 and elapsed-_danger_at>2.0:_feedback("danger",player);_danger_at=elapsed
	_reveal()
	for k in cooldowns: cooldowns[k] = maxf(0,cooldowns[k]-dt)
	spawn_timer -= dt
	if spawn_timer <= 0:
		spawn_timer = maxf(2.0,2.6-elapsed/1000.0)
		_spawn_wave()
	if elapsed >= 600.0 and not boss_spawned:
		boss_spawned = true
		boss_marker = world.boss_pos
		if enemies.size() >= ENEMY_CAP:
			_die(0,false)
		spawn_enemy(world.boss_pos,"boss")
		events.append({"type":"message","text":"Пробудился Архицит! Найди его на карте."})
	_check_nests()
	_update_ecology()
	_update_minibosses()
	_update_enemies(dt)
	if outcome != "": return
	_attack_dt = dt
	_attack()
	_update_shots(dt)
	_update_fields(dt)
	_update_remains(dt)
	_collect(dt)
	_update_cysts(dt)
	for i in range(damage_markers.size()-1,-1,-1):
		damage_markers[i].life-=dt
		if damage_markers[i].life<=0:damage_markers.remove_at(i)
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
	if enemies.size()>=ENEMY_CAP-2: return
	var count = mini(2,1+int(elapsed/180.0))
	for i in range(count):
		if enemies.size()>=ENEMY_CAP: break
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
	if enemies.size()>=ENEMY_CAP: return
	var boss = kind == "boss"
	var prey = kind == "prey"
	var variant = rng.randi_range(0,3)
	var traits = Genome.traits(world.seed_value,next_id,elapsed,kind)
	var health = (8.0 if prey else 40.0+elapsed*0.17)*(1.4 if variant == 1 else 1.0)
	if boss: health = 1600.0
	if "shell" in traits: health *= 1.3
	enemies.append({"pos":p,"kind":kind,"hp":health,"max_hp":health,"r":12.0 if prey else (140.0 if boss else 23.0+rng.randf()*6),"speed":42.0 if prey else (48.0 if boss else 44.0+minf(25,elapsed*0.035)+(12 if variant==2 else 0)),"vel":Vector2.ZERO,"engulf":0.0,"phase":rng.randf()*TAU,"variant":variant,"infect":0.0,"slow":0.0,"shot_cd":2.5,"id":next_id,"biome":world.biome(p),"genome":Genome.create(world.seed_value,next_id,kind,world.biome(p)),"traits":traits,"emission_cd":rng.randf_range(1.0,3.0)})
	if not prey and not boss and posmod(next_id*31+world.seed_value,7)==0:
		enemies.back().r=44.0+float(posmod(next_id,5))
		enemies.back().hp*=1.7
		enemies.back().max_hp=enemies.back().hp
	next_id += 1

# Eligibility also governs attack exclusion: retracting visual progress alone
# must never protect an enemy that healed or moved out of absorption range.
func mouth_contact(e: Dictionary) -> bool:
	if build.rank("devour")<=0:return false
	var offset=e.pos-player
	if offset.length()>body_radius()*1.18+e.r:return false
	return offset.length_squared()<0.01 or offset.normalized().dot(Vector2.from_angle(facing))>=cos(0.7)

func interaction(e: Dictionary) -> Dictionary:
	var rank=build.rank("magnet")+(1 if float(e.get("grasp",0))>0 else 0)
	return SizeRules.profile(body_radius(),e.r,e.hp/maxf(1.0,e.max_hp),rank,build.rank("devour"),mouth_contact(e))

func _is_engulfing(e: Dictionary) -> bool:
	if e.hp<=0 or e.kind=="boss":return false
	if e.get("captured",false):return true
	if e.kind=="miniboss" and e.hp>e.max_hp*0.15:return false
	if not interaction(e).eligible:return false
	return _touches(e.pos,e.r*1.17)

func _update_enemies(dt: float):
	for i in range(enemies.size()-1,-1,-1):
		var e = enemies[i]
		if e.hp <= 0:
			_die(i,false)
			continue
		var rate=CombatTissue.damage_rate(e.r/body_radius(),e.kind in ["boss","miniboss"])
		e.tissue_budget=minf(e.max_hp*0.06,float(e.get("tissue_budget",0))+e.max_hp*rate*dt)
		e.slow = maxf(0,e.slow-dt)
		e.grasp=maxf(0.0,float(e.get("grasp",0))-dt)
		if e.infect>0:
			e.infect -= dt
			hit_enemy(e,Catalog.scaled_damage(4.0+build.rank("infection")*3.0,build.rank("infection"))*dt,"infection")
		if "regen" in e.get("traits",[]) and e.kind!="miniboss": e.hp = minf(e.max_hp,e.hp+e.max_hp*0.012*dt)
		if e.get("enzyme_time",0)>0:
			e.enzyme_time=maxf(0.0,e.enzyme_time-dt)
			hit_enemy(e,Catalog.scaled_damage(3+build.rank("enzymes")*2,build.rank("enzymes"))*dt,"enzymes")
		if "toxic" in e.get("traits",[]):
			e.emission_cd -= dt
			if e.emission_cd<=0:
				e.emission_cd = 2.5
				_field(e.pos,48,6.0,2.8,"enemy_toxin",true,_enemy_label(e)+" · токсин",int(e.id))
		if e.hp <= 0:
			_die(i,false)
			continue
		var offset = player-e.pos
		var dist = offset.length()
		if dist>1600 and not e.kind in ["boss","miniboss"] and not e.has("resident_id"):
			enemies.remove_at(i)
			continue
		if _is_engulfing(e):
			if not e.get("captured",false):
				e.entry_angle=offset.angle()+PI
				e.entry_distance=dist
				e.captured=true
				e.via_mouth=mouth_contact(e)
				e.digest_duration=interaction(e).duration
			e.engulf = minf(1.0,float(e.get("engulf",0.0))+dt/float(e.get("digest_duration",0.6)))
			e.vel = e.get("vel",Vector2.ZERO)*exp(-dt/0.18)
			e.pos = player+Vector2.from_angle(float(e.get("entry_angle",0)))*body_radius()*0.35
			if e.engulf >= 1.0: _die(i,true)
			continue
		e.engulf = maxf(0.0,float(e.get("engulf",0.0))-dt*0.12)
		var dir = offset.normalized()
		if e.r<body_radius()*0.82: dir = -dir if dist<180+body_radius() else dir.rotated(e.phase)
		if e.kind == "spitter" and dist<300: dir = -dir*0.3
		if _safe_zone(player) and e.kind != "prey": dir = -dir
		var rules=interaction(e)
		var desired = dir*e.speed*rules.speed*(0.35 if e.slow>0 else 1.0)*(1.2 if "swift" in e.get("traits",[]) else 1.0)
		var pull_range=maxf(attraction_radius(),(165+build.rank("tentacle")*12)*ability_scale() if e.grasp>0 else 0.0)
		if dist<pull_range and rules.pull>0:desired+=offset.normalized()*rules.pull
		e.impulse=e.get("impulse",Vector2.ZERO)*exp(-dt/0.25)
		desired+=e.impulse
		var old_velocity = e.get("vel",Vector2.ZERO)
		var response = exp(-dt/0.28)
		e.vel = desired+(old_velocity-desired)*response
		e.pos = world.move_body(e.pos,desired*dt+(old_velocity-desired)*0.28*(1.0-response),minf(26.0,e.r*0.6))
		if e.kind=="boss": boss_marker = e.pos
		if e.kind in ["spitter","boss","miniboss"]:
			e.shot_cd -= dt
			if e.shot_cd<=0 and dist<850:
				e.shot_cd = 2.0 if e.kind=="spitter" else 1.5
				if e.kind == "boss":
					for n in range(10): _shot(e.pos,Vector2.from_angle(n*TAU/10.0+elapsed*0.2)*135,10,true,"enemy",_enemy_label(e),int(e.id))
				elif e.kind=="miniboss":
					for n in range(5):_shot(e.pos,Vector2.from_angle(n*TAU/5+elapsed)*100,7,true,"enemy",_enemy_label(e),int(e.id))
				else: _shot(e.pos,offset.normalized()*155,8,true,"enemy",_enemy_label(e),int(e.id))
		if dist<e.r+body_radius()*0.75 and rules.impact>0 and invuln<=0 and not _safe_zone(player):
			hurt_player(rules.impact*(1.2 if e.kind in ["boss","miniboss"] else 1.0),{"kind":"collision","name":_enemy_label(e),"pos":e.pos,"id":e.id})
			invuln = 0.65
			e.impulse=-offset.normalized()*24.0
			_effect({"type":"hurt","pos":player,"life":0.3,"max":0.3,"r":45.0})
		if e.hp<=0: _die(i,false)

func _die(index: int,absorbed: bool):
	var e = enemies[index]
	enemies.remove_at(index)
	for resident in residents:
		if resident.id==e.get("resident_id",0):resident.dead=true; resident.active=false
	kills += 1
	CombatStats.record_kill(combat_stats,"devour" if absorbed else str(e.get("last_damage_source","unknown")))
	if "spores" in e.get("traits",[]): _field(e.pos,75,8.0,2.5,"enemy_spore",true,_enemy_label(e)+" · споры",int(e.id))
	if absorbed:
		var meal_scale=maxf(1.0,e.r/26.0) if e.r>40 else 1.0
		_assimilate(e.genome,maxf(1.0,e.r/12.0),e.pos)
		gain_xp(4 if e.kind=="prey" else int(6*meal_scale))
		build.biomass += 1 if e.kind=="prey" else int(3*meal_scale)
		heal_player(build.rank("devour")*0.8)
		if e.infect>0 and "spore_feast" in build.active_synergies(): _field(e.pos,100,14,2.5,"spore")
	else:
		_leave_remains(e)
		if kills%3==0: _drop(e.pos,"heal",6)
	if e.kind == "boss":
		outcome = "victory"
		events.append({"type":"core","token":run_id+":boss","amount":12})
		events.append({"type":"end","outcome":"victory"})
	elif e.kind=="miniboss":
		_spawn_cyst(e.pos,3,"elite:"+str(e.id))
		events.append({"type":"core","token":e.get("elite_token",run_id+":elite:"+str(e.id)),"amount":4})
		events.append({"type":"message","text":"Минибосс повержен: +4 ядра наследия"})
	elif kills%18 == 0:
		_drop(e.pos,"core",1)
	_effect({"type":"burst","pos":e.pos,"life":0.4,"max":0.4,"r":e.r+20})

# Body rewards remain embodied until a single fragment is fully digested.
func _leave_remains(e: Dictionary):
	var size_reward=maxf(1.0,e.r/26.0) if e.r>40 else 1.0
	var dna_total = 80 if e.kind == "boss" else (4 if e.kind == "prey" else int(9*size_reward))
	var bio_total = 40 if e.kind == "boss" else (1 if e.kind == "prey" else int(4*size_reward))
	if e.kind=="miniboss":dna_total=maxi(45,dna_total*2);bio_total=maxi(24,bio_total*2)
	var source_grade=3 if e.kind in ["boss","miniboss"] else (2 if e.r>=60 else (1 if e.r>=40 else 0))
	var dna_split=[int(ceil(dna_total*0.5)),int(floor(dna_total*0.3)),0]
	dna_split[2]=dna_total-dna_split[0]-dna_split[1]
	var bio_split=[int(ceil(bio_total*0.5)),int(floor(bio_total*0.25)),0]
	bio_split[2]=bio_total-bio_split[0]-bio_split[1]
	for part in range(3):
		var angle = rng.randf()*TAU
		var fragment = {"id":next_id,"pos":e.pos+Vector2.from_angle(angle)*e.r*0.45,"vel":Vector2.from_angle(angle)*rng.randf_range(6.0,15.0),"r":maxf(7.0,e.r*0.36),"genome":e.genome.duplicate(true),"part":part,"quality":maxi(1,source_grade) if part==0 else maxi(0,source_grade-1),"material":"organelle" if part==0 else ("membrane" if part==1 else "plasma"),"dna":dna_split[part],"bio":bio_split[part],"progress":0.0,"duration":rng.randf_range(1.2,2.0),"internal":false,"infected":e.infect>0 and part == 0}
		fragment.pigment=Pigment.create(Genome.colors(e.genome)[0])
		fragment.pigment.mass=maxf(0.5,fragment.r*0.12)
		next_id += 1
		# At the cap merge materials into an existing body, preserving its progress.
		# Infected material stays infected, but never produces repeated feast procs.
		if remains.size() >= REMAINS_CAP:
			var receiver = remains.back()
			receiver.dna += fragment.dna
			receiver.bio += fragment.bio
			receiver.infected = receiver.infected or fragment.infected
			receiver.quality=maxi(int(receiver.get("quality",0)),int(fragment.quality))
			if not receiver.has("pigment"):
				receiver.pigment=Pigment.create(Genome.colors(receiver.genome)[0])
				receiver.pigment.mass=maxf(0.5,receiver.r*0.12)
			Pigment.combine(receiver.pigment,fragment.pigment)
		else:
			remains.append(fragment)

func _update_remains(dt: float):
	digesting_id=-1
	for i in range(remains.size()-1,-1,-1):
		var part=remains[i]
		if part.get("internal",false) and not part.has("captured"):
			part.captured=true
			part.duration=minf(0.65,float(part.duration))
		if not part.get("captured",false):
			part.pos=world.move_body(part.pos,part.vel*dt,part.r*0.5)
			part.vel*=exp(-dt/0.8)
			if _touches(part.pos,part.r): _capture(part)
			elif build.rank("magnet")>0 and player.distance_to(part.pos)<attraction_radius():part.pos=part.pos.move_toward(player,dt*(70+build.rank("magnet")*25))
		if not part.get("captured",false): continue
		if digesting_id==-1:digesting_id=int(part.id)
		part.pos=player+Vector2.from_angle(float(part.get("entry_angle",0)))*body_radius()*0.35
		part.progress=minf(1.0,float(part.progress)+dt/float(part.duration))
		if part.progress<1.0: continue
		_assimilate(part.genome,maxf(0.5,part.r*0.12),part.pos,part.get("pigment",{}))
		gain_xp(part.dna)
		build.biomass+=int(part.bio)
		if part.infected and "spore_feast" in build.active_synergies():_field(part.pos,100,14,2.5,"spore")
		remains.remove_at(i)
	if remains.is_empty():digesting_id=-1

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
		if _is_engulfing(e): continue
		var d = player.distance_squared_to(e.pos)
		if d<best:
			best = d
			nearest = e
	return nearest

func _bite():
	var rank=build.rank("devour")
	if rank<=0 or cooldowns.get("bite",0)>0:return
	var target={}
	var nearest=INF
	for enemy in enemies:
		if enemy.hp<=0 or enemy.get("captured",false) or not mouth_contact(enemy):continue
		var distance=player.distance_squared_to(enemy.pos)
		if distance<nearest:nearest=distance;target=enemy
	if target.is_empty():return
	cooldowns.bite=0.45
	bite_flash=1.0
	hit_enemy(target,Catalog.scaled_damage(7.0+rank*5.0,rank)*(1.25 if "enzyme_bite" in build.active_synergies() else 1.0),"devour")
	if "enzyme_bite" in build.active_synergies():
		target.enzyme_time=3.0
		_effect({"type":"enzyme_bite","pos":player,"end":target.pos,"r":body_radius(),"life":0.7,"max":0.7})
	_effect({"type":"bite","pos":player+Vector2.from_angle(facing)*body_radius()*0.8,"end":target.pos,"r":body_radius()*0.25,"life":0.3,"max":0.3})

func _attack():
	_bite()
	var combos=build.active_synergies()
	if build.rank("cilia")>0 and cooldowns.get("cilia",0)<=0:
		var touched=false
		for enemy in enemies:
			var offset=enemy.pos-player
			if enemy.get("captured",false) or offset.length()>(100+build.rank("cilia")*10)*ability_scale():continue
			if offset.normalized().dot(Vector2.from_angle(facing))<0.5:continue
			hit_enemy(enemy,Catalog.scaled_damage(10+build.rank("cilia")*6,build.rank("cilia")),"cilia")
			touched=true
		if touched:
			cooldowns.cilia=1.4
			_effect({"type":"cilia","pos":player,"end":player+Vector2.from_angle(facing)*body_radius()*3,"r":body_radius()*3,"life":0.4,"max":0.4})
			if "barbed_cilia" in combos:
				_effect({"type":"barbed_cilia","pos":player,"end":player+Vector2.from_angle(facing)*body_radius()*3,"r":body_radius()*3,"life":0.8,"max":0.8})
				for i in range(3):_shot(player,Vector2.from_angle(facing+(i-1)*0.35)*300,Catalog.scaled_damage(12+build.rank("spikes")*5,build.rank("spikes")),false)
	if build.rank("enzymes")>0 and cooldowns.get("enzymes",0)<=0:
		var target=_nearest(230*ability_scale())
		if not target.is_empty():
			target.enzyme_time=4.0
			cooldowns.enzymes=2.0
			_effect({"type":"enzymes","pos":player,"end":target.pos,"r":float(target.r),"life":0.5,"max":0.5})
	if build.rank("electric")>0 and cooldowns.get("electric",0)<=0:
		var target=_nearest(280*ability_scale())
		if not target.is_empty():
			var previous=player
			var hit=[]
			for i in range(Catalog.electric_targets(build.rank("electric"))):
				var nearest={}
				var distance=pow(280*ability_scale(),2)
				for enemy in enemies:
					if enemy.id in hit or enemy.get("captured",false) or enemy.hp<=0:continue
					var d=previous.distance_squared_to(enemy.pos)
					if d<distance:distance=d;nearest=enemy
				if nearest.is_empty():break
				hit.append(nearest.id)
				hit_enemy(nearest,Catalog.scaled_damage(12+build.rank("electric")*6,build.rank("electric")),"electric")
				_effect({"type":"electric","pos":previous,"end":nearest.pos,"r":20.0,"life":0.35,"max":0.35})
				if "conductive_bath" in combos:
					nearest.slow=1.2
					_effect({"type":"conductive_bath","pos":previous,"end":nearest.pos,"r":float(nearest.r)+25,"life":0.7,"max":0.7})
					_field(nearest.pos,30,3,1.0,"acid_arc")
				previous=nearest.pos
			cooldowns.electric=2.6
	if "metabolic_colony" in combos and cooldowns.get("colony_visual",0)<=0 and hp<max_hp:
		cooldowns.colony_visual=2.0
		_effect({"type":"metabolic_colony","pos":player,"r":body_radius()*2.5,"life":1.4,"max":1.4})
	var metabolic = cooldown_factor()
	var synergies = build.active_synergies()
	if build.rank("tentacle")>0 and cooldowns.get("tentacle",0)<=0:
		var target = _nearest((165.0+build.rank("tentacle")*12)*ability_scale())
		if not target.is_empty():
			cooldowns.tentacle = 0.85*metabolic
			hit_enemy(target,Catalog.scaled_damage(9.0+build.rank("tentacle")*7,build.rank("tentacle")),"tentacle")
			_effect({"type":"lash","pos":player,"end":target.pos,"life":0.22,"max":0.22,"r":0})
			if "acid_grasp" in synergies:
				_effect({"type":"acid_grasp","pos":player,"end":target.pos,"r":30.0,"life":0.65,"max":0.65})
				target.slow = 1.3
				target.grasp=1.3
	if build.rank("acid")>0:
		for e in enemies:
			if _is_engulfing(e): continue
			if player.distance_squared_to(e.pos)<pow((75+build.rank("acid")*9)*ability_scale(),2): hit_enemy(e,Catalog.scaled_damage(4+build.rank("acid")*3,build.rank("acid"))*_attack_dt,"acid")
	if build.rank("spikes")>0 and cooldowns.get("spikes",0)<=0:
		var target = _nearest(650)
		if not target.is_empty():
			cooldowns.spikes = 1.3*metabolic
			var dir = (target.pos-player).normalized()
			for i in range(Catalog.shot_count(build.rank("spikes"))):
				_shot(player,dir.rotated((i-(Catalog.shot_count(build.rank("spikes"))-1)/2.0)*0.13)*450,Catalog.scaled_damage(12+build.rank("spikes")*5,build.rank("spikes")),false)
	if build.rank("pulse")>0 and cooldowns.get("pulse",0)<=0:
		cooldowns.pulse = 3.2*metabolic
		if "shield_pulse" in synergies:
			cooldowns.barrier=maxf(0,float(cooldowns.get("barrier",0))-2.0)
			_effect({"type":"shield_pulse","pos":player,"r":body_radius()*2.4,"life":1.0,"max":1.0})
		var radius = (130+build.rank("pulse")*18)*ability_scale()
		for e in enemies:
			if _is_engulfing(e): continue
			if player.distance_squared_to(e.pos)<radius*radius:
				hit_enemy(e,Catalog.scaled_damage(12+build.rank("pulse")*8,build.rank("pulse")),"pulse")
				e.impulse=e.get("impulse",Vector2.ZERO)+(e.pos-player).normalized()*100.0
		_effect({"type":"pulse","pos":player,"r":float(radius),"life":0.55,"max":0.55})
		if "spike_pulse" in synergies:
			_effect({"type":"spike_pulse","pos":player,"r":float(radius),"life":0.8,"max":0.8})
			for i in range(8): _shot(player,Vector2.from_angle(i*TAU/8.0)*370,Catalog.scaled_damage(18+build.rank("spikes")*4,build.rank("spikes")),false)
	if build.rank("infection")>0 and cooldowns.get("infection",0)<=0:
		var target = _nearest(420*ability_scale())
		if not target.is_empty():
			target.infect = 4.5
			_effect({"type":"infection","pos":player,"end":target.pos,"r":float(target.r),"life":0.85,"max":0.85})
			cooldowns.infection = 1.6*metabolic
	if build.rank("trail")>0 and cooldowns.get("trail",0)<=0:
		cooldowns.trail = 0.6
		_field(player,50+build.rank("trail")*6,Catalog.scaled_damage(5+build.rank("trail")*3,build.rank("trail")),3.0,"poison")
		if "toxic_colony" in synergies:
			for p in clone_positions():
				_field(p,40,Catalog.scaled_damage(3+build.rank("trail")*1.5,build.rank("trail")),2,"poison")
			_effect({"type":"toxic_colony","pos":player,"r":105.0,"life":0.65,"max":0.65})
	if build.rank("division")>0:
		for p in clone_positions():
			for e in enemies:
				if _is_engulfing(e): continue
				if p.distance_squared_to(e.pos)<pow(e.r+18,2): hit_enemy(e,Catalog.scaled_damage(8+build.rank("division")*4,build.rank("division"))*_attack_dt,"division")

var _attack_dt = 0.016

func clone_positions() -> Array:
	var out = []
	for i in range(Catalog.clone_count(build.rank("division"))):
		out.append(player+Vector2.from_angle(elapsed*1.6+i*TAU/Catalog.clone_count(build.rank("division")))*105)
	return out

func _shot(p: Vector2,velocity: Vector2,damage: float,hostile: bool,source: String="spikes",actor_name: String="",actor_id: int=0):
	if shots.size()>=200: return
	shots.append({"pos":p,"vel":velocity,"damage":damage,"hostile":hostile,"life":2.0,"source":source,"origin":p,"actor_name":actor_name,"actor_id":actor_id})

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
			if shot.pos.distance_squared_to(player)<pow(body_radius()*0.78+3,2):
				hit = true
				if invuln<=0 and not _safe_zone(player):
					hurt_player(shot.damage,{"kind":"projectile","name":str(shot.get("actor_name","")) if str(shot.get("actor_name",""))!="" else "Вражеский снаряд","pos":shot.get("origin",shot.pos),"id":int(shot.get("actor_id",0))})
					invuln = 0.4
		else:
			var cell = Vector2i(shot.pos/100.0)
			for y in range(-1,2):
				for x in range(-1,2):
					for e in buckets.get(cell+Vector2i(x,y),[]):
						if not hit and shot.pos.distance_squared_to(e.pos)<pow(e.r+8,2):
							hit_enemy(e,shot.damage,str(shot.get("source","spikes")))
							hit = true
		if hit or shot.life<=0 or not world.walkable(shot.pos): shots.remove_at(i)

func _field(p: Vector2,radius: float,damage: float,life: float,kind: String,hostile: bool=false,actor_name: String="",actor_id: int=0):
	if not hostile and "ferment_cloud" in build.active_synergies() and kind=="poison":
		damage*=1.25
		if cooldowns.get("ferment_visual",0)<=0:
			cooldowns.ferment_visual=1.2
			_effect({"type":"ferment_cloud","pos":p,"r":radius*1.25,"life":1.2,"max":1.2})
	if kind=="spore": _effect({"type":"spore_feast","pos":p,"r":radius,"life":1.4,"max":1.4})
	if fields.size()>=80: fields.pop_front()
	fields.append({"pos":p,"r":radius,"damage":damage,"life":life,"max":life,"kind":kind,"hostile":hostile,"source":"infection" if kind=="spore" else ("electric" if kind=="acid_arc" else "trail"),"actor_name":actor_name,"actor_id":actor_id})

func _update_fields(dt: float):
	var ferment="ferment_cloud" in build.active_synergies()
	for i in range(fields.size()-1,-1,-1):
		var f = fields[i]
		f.life -= dt
		if f.get("hostile",false):
			if f.pos.distance_squared_to(player)<pow(f.r+body_radius()*0.65,2) and not _safe_zone(player): hurt_player(f.damage*dt,{"kind":"toxin","name":str(f.get("actor_name","")) if str(f.get("actor_name",""))!="" else ("Вражеские споры" if f.kind=="enemy_spore" else "Ядовитое облако"),"pos":f.pos,"id":int(f.get("actor_id",0))})
		else:
			for e in enemies:
				if f.pos.distance_squared_to(e.pos)<pow(f.r+e.r*0.5,2):
					hit_enemy(e,f.damage*dt,str(f.get("source","infection" if f.kind=="spore" else ("electric" if f.kind=="acid_arc" else "trail"))))
					if ferment:e.enzyme_time=2.0
		if f.life<=0: fields.remove_at(i)

func _collect(dt: float):
	for i in range(pickups.size()-1,-1,-1):
		var item=pickups[i]
		if not item.get("captured",false):
			if item.type=="heal" and hp>=max_hp:continue
			if _touches(item.pos,7.0):_capture(item)
			elif build.rank("magnet")>0 and player.distance_to(item.pos)<attraction_radius():item.pos=item.pos.move_toward(player,dt*(95+35*build.rank("magnet")))
		if not item.get("captured",false):continue
		item.pos=player+Vector2.from_angle(float(item.get("entry_angle",0)))*body_radius()*0.3
		item.progress=minf(1.0,float(item.progress)+dt/float(item.duration))
		if item.progress<1.0:continue
		if item.type=="heal" and hp>=max_hp:
			item.captured=false
			item.internal=false
			item.progress=0.0
			item.pos=player+Vector2.from_angle(float(item.get("entry_angle",0)))*(body_radius()*1.6+12.0)
			continue
		_feedback("absorb",player)
		if item.type=="dna":gain_xp(item.amount)
		elif item.type=="bio":build.biomass+=int(item.amount)
		elif item.type=="heal":
			heal_player(float(item.amount))
			_effect({"type":"assimilate","pos":player,"end":item.pos,"r":body_radius(),"color":Color("7dfcd4"),"life":0.8,"max":0.8})
		else:
			cores_found+=item.amount
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
	return {"version":1,"combat_stats":combat_stats.duplicate(true),"last_damage":last_damage.duplicate(true),"cysts":_pack(cysts),"reward_queue":reward_queue.duplicate(true),"reward_options":reward_options.duplicate(true),"offer_quality":offer_quality.duplicate(),"claimed_rewards":claimed_rewards.duplicate(),"player_genome":player_genome.duplicate(true),"minibosses_spawned":minibosses_spawned,"next_miniboss_at":next_miniboss_at,"facing":facing,"tissue_pigment":tissue_pigment.duplicate(true),"residents":_pack(residents),"outcome":outcome,"events":_pack(events),"seed":world.seed_value,"rng_state":str(rng.state),"run_id":run_id,"player":_vec(player),"player_velocity":_vec(player_velocity),"remains":_pack(remains),"digesting_id":digesting_id,"hp":hp,"max_hp":max_hp,"elapsed":elapsed,"xp":xp,"level":level,"pending_levels":pending_levels,"build":build.to_dict(),"enemies":_pack(enemies),"pickups":_pack(pickups),"colonies":_pack(world.colonies),"nests":_pack(world.nests),"explored":explored.keys(),"boss_spawned":boss_spawned,"kills":kills,"cores_found":cores_found,"next_id":next_id,"upgrades":upgrades,"cooldowns":cooldowns.duplicate(),"offers":current_offers.duplicate(),"rerolls":rerolls,"fields":_pack(fields),"shots":_pack(shots)}

func restore(data: Dictionary) -> bool:
	if data.get("version",0) != 1 or not data.get("player",null) is Array: return false
	for key in ["enemies","pickups","colonies","nests","explored"]:
		if not data.get(key,null) is Array: return false
	world.generate(int(data.get("seed",0)))
	var saved_recipe = data.get("player_genome",{})
	player_genome = saved_recipe if saved_recipe is Dictionary else {}
	if not Genome.validate(player_genome): player_genome = Genome.create(world.seed_value,0,"player",0)
	facing=float(data.get("facing",player_genome.rotation))
	_cached_contact_polygon=PackedVector2Array()
	contact_contour=PackedVector2Array()
	tissue_pigment = Pigment.restore(data.get("tissue_pigment",{}),Genome.colors(player_genome)[0])
	rng.seed = int(data.seed)
	rng.state = int(data.get("rng_state","0"))
	player = Vector2(data.player[0],data.player[1])
	previous_player=player
	_create_residents()
	if data.get("residents") is Array:residents=_unpack(data.residents)
	if not world.walkable(player,22): player = world.start
	var saved_velocity = data.get("player_velocity",[])
	player_velocity = Vector2(saved_velocity[0],saved_velocity[1]) if saved_velocity is Array and saved_velocity.size()==2 else Vector2.ZERO
	remains = _unpack(data.get("remains",[])) if data.get("remains",[]) is Array else []
	digesting_id = int(data.get("digesting_id",-1))
	outcome = str(data.get("outcome",""))
	events = _unpack(data.get("events",[]))
	hp = float(data.get("hp",100))
	max_hp = float(data.get("max_hp",100))
	elapsed = float(data.get("elapsed",0))
	minibosses_spawned=int(data.get("minibosses_spawned",0))
	next_miniboss_at=float(data.get("next_miniboss_at",maxf(180,elapsed+20)))
	xp = float(data.get("xp",0))
	level = int(data.get("level",1))
	pending_levels = int(data.get("pending_levels",0))
	build.from_dict(data.get("build",{}))
	for id in Catalog.base_unlocked():
		if not id in build.unlocked:build.unlocked.append(id)
	enemies = _unpack(data.enemies)
	for enemy in enemies:
		var saved_enemy_recipe = enemy.get("genome",{})
		if not (saved_enemy_recipe is Dictionary) or not Genome.validate(saved_enemy_recipe): enemy.genome = Genome.create(world.seed_value,int(enemy.id),str(enemy.kind),int(enemy.biome))
		if not enemy.get("traits",null) is Array: enemy.traits = []
		if not enemy.has("emission_cd"): enemy.emission_cd = 2.5
		if not enemy.has("vel"): enemy.vel = Vector2.ZERO
		if not enemy.has("engulf"): enemy.engulf = 0.0
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
	combat_stats=CombatStats.restore(data.get("combat_stats",{}))
	if not data.has("combat_stats"):combat_stats.tracking_start=elapsed
	last_damage=data.get("last_damage",{}).duplicate(true) if data.get("last_damage") is Dictionary else {}
	cysts=_unpack(data.cysts) if data.get("cysts") is Array else []
	if not data.has("cysts"):_create_cysts()
	reward_queue=data.get("reward_queue",[]).duplicate(true) if data.get("reward_queue") is Array else []
	reward_options=data.get("reward_options",[]).duplicate(true) if data.get("reward_options") is Array else []
	offer_quality=data.get("offer_quality",{}).duplicate() if data.get("offer_quality") is Dictionary else {}
	claimed_rewards=data.get("claimed_rewards",[]).duplicate() if data.get("claimed_rewards") is Array else []
	var clean_queue=[]
	for entry in reward_queue:
		if entry is Dictionary and str(entry.get("token",""))!="" and not str(entry.token) in claimed_rewards:
			clean_queue.append({"token":str(entry.token),"tier":clampi(int(entry.get("tier",1)),1,3)})
	reward_queue=clean_queue.slice(0,12)
	var clean_options=[]
	for entry in reward_options:
		if not entry is Dictionary:continue
		var kind=str(entry.get("kind",""));var id=str(entry.get("id",""))
		if (kind=="mutation" and not Catalog.item(id).is_empty()) or (kind=="evolution" and id in Catalog.EVOLUTIONS):
			clean_options.append({"kind":kind,"id":id,"quality":clampi(int(entry.get("quality",0)),0,3)})
		elif kind=="biomass":clean_options.append({"kind":kind,"id":"biomass","quality":clampi(int(entry.get("quality",0)),0,3),"amount":maxi(0,int(entry.get("amount",0)))})
	reward_options=clean_options.slice(0,3) if not reward_queue.is_empty() else []
	roll_offer_quality()
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
		for k in ["pos","vel","impulse","origin"]:
			if copy.get(k,null) is Array and copy[k].size()==2: copy[k] = Vector2(copy[k][0],copy[k][1])
		out.append(copy)
	return out

func _grade_stocks():
	var reward_rng=RandomNumberGenerator.new()
	reward_rng.seed=world.seed_value+889711
	for colony in world.colonies:
		for stock in colony.stock:
			if stock.id!="heal":stock.quality=Rewards.roll_quality(reward_rng,1)

func _spawn_cyst(p: Vector2,tier: int,identity: String):
	if cysts.size()>=12:return
	var token=run_id+":cyst:"+identity
	if token in claimed_rewards:return
	for cyst in cysts:
		if cyst.token==token:return
	cysts.append({"id":-300-posmod(hash(identity),1000000000),"pos":p,"tier":clampi(tier,1,3),"r":21.0+tier*4,"token":token,"captured":false,"progress":0.0,"duration":0.65})

func _create_cysts():
	cysts.clear()
	var reward_rng=RandomNumberGenerator.new()
	reward_rng.seed=world.seed_value+811733
	var tiers=[1,1,2,1,2,3]
	for i in range(tiers.size()):
		for attempt in range(100):
			var p=world.start+Vector2.from_angle(reward_rng.randf()*TAU)*reward_rng.randf_range(380,650) if i==0 else Vector2(reward_rng.randf_range(220,World.W*World.TILE-220),reward_rng.randf_range(220,World.H*World.TILE-220))
			if not world.walkable(p,28) or p.distance_to(world.start)<350 or _safe_zone(p):continue
			if cysts.any(func(c):return c.pos.distance_to(p)<220):continue
			_spawn_cyst(p,tiers[i],"map:"+str(i))
			break

func _update_cysts(dt: float):
	for i in range(cysts.size()-1,-1,-1):
		var cyst=cysts[i]
		if not cyst.captured:
			if not _touches(cyst.pos,float(cyst.r)):continue
			_capture(cyst)
		cyst.pos=player+Vector2.from_angle(float(cyst.get("entry_angle",0)))*body_radius()*(0.75-cyst.progress*0.65)
		cyst.progress=minf(1.0,cyst.progress+dt/float(cyst.duration))
		if cyst.progress<1.0:continue
		var duplicate=cyst.token in claimed_rewards or reward_queue.any(func(q):return q.token==cyst.token)
		if not duplicate:reward_queue.append({"token":cyst.token,"tier":int(cyst.tier)})
		_feedback("reward",player,float(cyst.tier))
		_effect({"type":"assimilate","pos":player,"end":cyst.pos,"r":body_radius(),"color":Rewards.quality_color(int(cyst.tier)),"life":1.1,"max":1.1})
		cysts.remove_at(i)

func roll_offer_quality():
	var clean={}
	for id in current_offers:
		clean[id]=clampi(int(offer_quality[id]),0,3) if id in offer_quality else Rewards.roll_quality(rng,mini(5,int(elapsed/120)))
	offer_quality=clean

func prepare_reward() -> Array:
	# Stable options are saved, so neither menu X nor checkpoint restore rerolls loot.
	while not reward_queue.is_empty() and str(reward_queue[0].token) in claimed_rewards:reward_queue.pop_front();reward_options.clear()
	if reward_queue.is_empty():reward_options.clear();return reward_options
	if not reward_options.is_empty():
		_refresh_reward_options()
		return reward_options
	var tier=clampi(int(reward_queue[0].tier),1,3)
	if tier>=2:
		var evolutions=build.evolution_candidates()
		if not evolutions.is_empty():reward_options.append({"kind":"evolution","id":evolutions[0],"quality":build.quality(evolutions[0])})
	var pool=build.offers(rng)
	# Even a rank-capped organ can still gain a truly superior material quality.
	for id in build.organs.keys()+build.adaptations.keys():
		if build.rank(id)>=Catalog.max_rank(id) and build.quality(id)<tier and not id in pool:pool.append(id)
	for id in pool:
		if reward_options.size()>=3:break
		var grade=maxi(tier,Rewards.roll_quality(rng,tier+2))
		reward_options.append({"kind":"mutation","id":id,"quality":grade})
	if reward_options.is_empty():reward_options.append({"kind":"biomass","id":"biomass","quality":tier,"amount":20+tier*20})
	return reward_options

func _refresh_reward_options():
	for i in range(reward_options.size()):
		var option=reward_options[i]
		var obsolete=false
		if option.kind=="mutation":obsolete=build.rank(str(option.id))>=Catalog.max_rank(str(option.id)) and build.quality(str(option.id))>=int(option.quality)
		elif option.kind=="evolution":obsolete=not str(option.id) in build.evolution_candidates()
		if obsolete:
			var grade=int(option.get("quality",1))
			reward_options[i]={"kind":"biomass","id":"biomass","quality":grade,"amount":20+20*maxi(1,grade)}

func claim_reward(index: int,replace_id: String="") -> bool:
	_refresh_reward_options()
	if reward_queue.is_empty() or index<0 or index>=reward_options.size():return false
	var token=str(reward_queue[0].token)
	if token in claimed_rewards:return false
	var option=reward_options[index]
	var accepted=false
	match str(option.kind):
		"mutation":accepted=build.apply(str(option.id),replace_id,int(option.quality))
		"evolution":accepted=replace_id=="" and build.evolve(str(option.id))
		"biomass":
			if replace_id=="":build.biomass+=int(option.amount);accepted=true
	if not accepted:return false
	claimed_rewards.append(token)
	# Each run has at most six map cysts and two elite cysts. Preserve all tokens.
	reward_queue.pop_front();reward_options.clear()
	_feedback("reward",player,3 if option.kind=="evolution" else float(option.get("quality",1)))
	_effect({"type":"mutation","pos":player,"r":body_radius()*1.6,"life":1.2,"max":1.2})
	return true
