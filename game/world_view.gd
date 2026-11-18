extends Node2D
const Catalog = preload("res://core/catalog.gd")
const World = preload("res://game/world.gd")
const Painter = preload("res://game/organism_painter.gd")
const TissueDamage=preload("res://game/tissue_damage.gd")
const Absorption = preload("res://game/absorption.gd")
const OrganicFX = preload("res://game/organic_fx.gd")
const Jelly = preload("res://game/jelly_motion.gd")
const Fluid = preload("res://game/fluid_view.gd")
const EvolutionRules=preload("res://game/evolution_rules.gd")
const EvolutionAnatomy=preload("res://game/evolution_anatomy.gd")
const RewardArt=preload("res://game/reward_art.gd")
const Terrain=preload("res://game/terrain_view.gd")
var terrain=Terrain.new()
var painter = Painter.new()
var fluid = Fluid.new()
var water_surface=Fluid.Surface.new()
var motions = {}
var tracked_sim
var feeding: Array=[]
var reaction=0.0
var evolution_growth: Dictionary={}
var previous_build=0
var previous_traits: Dictionary={}
var player_anatomy: Dictionary={}
var _anatomy_key=0
var detailed_enemies: Dictionary={}
var zoom=3.09
var organ_cache: Dictionary={}
var organ_cache_hits=0
var organ_cache_misses=0
var absorbable: Array=[]

func _ready():
	fluid.show_behind_parent = true
	add_child(fluid)
	terrain.show_behind_parent=true
	add_child(terrain)
	water_surface.fluid=fluid
	add_child(water_surface)

func _motion(key,position: Vector2,recipe: Dictionary,dt: float,radius: float):
	if not motions.has(key):
		motions[key] = {"jelly":Jelly.new(float(recipe.rotation)),"position":position,"distance":0.0}
		if key is String and key=="player":motions[key].jelly.angle=sim.facing
	var state = motions[key]
	var displacement = position-state.position
	state.position = position
	if not sim.paused:
		var velocity = displacement/maxf(dt,0.001) if displacement.length()<100 else Vector2.ZERO
		state.jelly.step(dt,velocity)
		if key is String and key=="player":state.jelly.angle=sim.facing
		state.distance += displacement.length() if displacement.length()<100 else 0.0
		if state.distance>radius*0.7:
			fluid.emit_wake(position,velocity,radius)
			state.distance = 0.0
	return state.jelly

func motion_for(key):
	return motions[key].jelly if motions.has(key) else null
var sim
var visual_time = 0.0
var menu = false
var joystick_origin = Vector2.ZERO
var joystick_tip = Vector2.ZERO
var joystick_visible = false
var font = ThemeDB.fallback_font

func _process(dt):
	if sim != null:
		if tracked_sim != sim:
			motions.clear()
			organ_cache.clear()
			tracked_sim = sim
			previous_build=hash([sim.build.organs,sim.build.adaptations,sim.build.qualities,sim.build.stats.evolutions])
			_anatomy_key=0
			previous_traits=_mutation_traits()
			evolution_growth={}
			for id in sim.build.stats.evolutions:evolution_growth[id]=1.0
			reaction=0.0
			zoom=sim.view_zoom()
			fluid.zoom=zoom
			fluid.reset(sim.world.seed_value,sim.player,get_viewport_rect().size)
		if not sim.paused:zoom=lerpf(zoom,sim.view_zoom(),1.0-exp(-dt*2.0))
		fluid.update(dt,sim,get_viewport_rect().size,zoom)
		terrain.update_world(sim.world,sim.player,get_viewport_rect().size,zoom)
		if not sim.paused:
			visual_time += dt
			reaction=maxf(0,reaction-dt*1.4)
			var build_key=hash([sim.build.organs,sim.build.adaptations,sim.build.qualities,sim.build.stats.evolutions])
			if build_key!=previous_build:
				reaction=1.0
				previous_build=build_key
				var changed=_mutation_traits()
				var tint=Color("98eecb")
				var title="Мутация организма"
				for id in changed:
					if changed[id]!=previous_traits.get(id,[]):
						var grade=sim.build.quality(id)
						tint=preload("res://core/rewards.gd").quality_color(grade) if grade>0 else Color("98eecb")
						title=Catalog.item(id).name+" · "+preload("res://core/rewards.gd").quality_name(grade)
						break
				previous_traits=changed
				sim._effect({"type":"mutation","pos":sim.player,"r":sim.body_radius()*2,"color":tint,"text":title,"life":1.8,"max":1.8})
		for id in sim.build.stats.evolutions:
			if not evolution_growth.has(id):evolution_growth[id]=0.0
			if not sim.paused:evolution_growth[id]=minf(1.0,float(evolution_growth[id])+dt/2.2)
		for id in evolution_growth.keys():
			if not sim.build.evolved(id):evolution_growth.erase(id)
		var anatomy_key=hash([sim.build.organs,sim.build.adaptations])
		if anatomy_key!=_anatomy_key or player_anatomy.is_empty():
			player_anatomy=sim.build.organs.merged(sim.build.adaptations,true)
			_anatomy_key=anatomy_key
		var visible=[]
		var bounds=get_viewport_rect().size/(2*zoom)+Vector2.ONE*120
		for enemy in sim.enemies:
			var offset=enemy.pos-sim.player
			if absf(offset.x)<bounds.x and absf(offset.y)<bounds.y and enemy.r*zoom>=22:
				visible.append(enemy)
		visible.sort_custom(func(a,b):return sim.player.distance_squared_to(a.pos)<sim.player.distance_squared_to(b.pos))
		detailed_enemies.clear()
		for i in range(mini(6,visible.size())):detailed_enemies[visible[i].id]=true
		_prune_organ_cache()
		var alive = {"player":true}
		_motion("player",sim.player,sim.player_genome,dt,sim.body_radius())
		var physical=TissueDamage.contour(painter.anatomy(sim.player_genome).contour,sim.player_genome,sim.hp/sim.max_hp)
		physical=EvolutionAnatomy.shape(physical,sim.build.stats.evolutions,visual_time,float(sim.player_genome.phase),evolution_growth)
		physical=motion_for("player").deform_points(physical,float(sim.player_genome.phase))
		_prepare_feeding()
		for entry in feeding:
			var pose=entry.pose.duplicate()
			pose.bulge/=maxf(1.0,float(feeding.size()))
			physical=Absorption.membrane(physical,pose,sim.body_radius())
		var phase=float(sim.player_genome.phase)+motion_for("player").angle_delta()
		var breathe=1+sin(visual_time*1.7+phase)*0.025+reaction*0.055
		sim.contact_contour=Transform2D(0,Vector2.ONE*breathe,0,Vector2.ZERO)*physical
		for enemy in sim.enemies:
			alive[enemy.id] = true
			_motion(enemy.id,enemy.pos,enemy.genome,dt,enemy.r)
		if sim.build.rank("division")>0:
			var clone_index = 0
			for position in sim.clone_positions():
				var key = "clone:%d" % clone_index
				alive[key] = true
				_motion(key,position,sim.player_genome,dt,17)
				clone_index += 1
		for key in motions.keys():
			if not alive.has(key): motions.erase(key)
	water_surface.queue_redraw()
	queue_redraw()

func screen(p: Vector2) -> Vector2:
	return p-sim.player+get_viewport_rect().size*Vector2(0.5,0.51)

func _draw():
	var size = get_viewport_rect().size
	if sim == null: return
	var b = sim.world.biome(sim.player)
	var center=size*Vector2(0.5,0.51)
	draw_set_transform(center*(1.0-zoom),0,Vector2.ONE*zoom)
	var area = Rect2(sim.player-size/(2*zoom)-Vector2.ONE*150,size/zoom+Vector2.ONE*300)
	for nest in sim.world.nests:
		if not area.has_point(nest.pos) or nest.used: continue
		var p = screen(nest.pos)
		draw_circle(p,45,Color(0.48,0.27,0.6,0.08))
		for i in range(5):
			var q = p+Vector2.from_angle(i*TAU/5+visual_time*0.15)*22
			_blob(q,10,Color("ae80dd"),i,0.5,false)
		draw_arc(p,49,0,TAU,40,Color(0.7,0.5,0.9,0.25),1.5,true)
	for shop in sim.world.colonies:
		if not area.has_point(shop.pos): continue
		var p = screen(shop.pos)
		draw_circle(p,150,Color(0.2,0.7,0.65,0.035))
		draw_arc(p,150,0,TAU,80,Color(0.35,0.8,0.7,0.12),1.5,true)
		for i in range(8):
			var q = p+Vector2.from_angle(i*TAU/8+sin(visual_time*0.4)*0.05)*35
			_blob(q,24,Color("468c85"),i*1.2,0.45,true)
		_blob(p,28,Color("82dbb5"),0,0.4,true)
		draw_string(font,p+Vector2(-55,80),"КОЛОНИЯ",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("83cdbd"))
	for f in sim.fields:
		if not area.has_point(f.pos): continue
		var col = Color("c67688") if f.get("hostile",false) else (Color("b684da") if f.kind == "spore" else Color("97ba53"))
		_blob(screen(f.pos),f.r,Color(col,0.12*f.life/f.max),f.pos.x*0.2,0.5,false)
		OrganicFX.field(self,screen(f.pos),f.r,str(f.kind),float(f.life),float(f.max),visual_time)
	for pickup in sim.pickups:
		if pickup.get("captured",false):continue
		if not area.has_point(pickup.pos): continue
		var p = screen(pickup.pos)+Vector2(0,sin(visual_time*2+pickup.id)*2)
		var col = Color("6bffb8") if pickup.type=="heal" else (Color("87eed2") if pickup.type=="dna" else (Color("ecc185") if pickup.type=="bio" else Color("c794f2")))
		draw_circle(p,10 if pickup.type=="core" else 6,Color(col,0.07))
		if pickup.type in ["body_extension","stock_extension"]:
			var cell_color=Color("98f2d3") if pickup.type=="body_extension" else Color("c5b1ff")
			draw_circle(p,17,Color(cell_color,0.13))
			_blob(p,11,Color(cell_color,0.75),float(pickup.id),0.7,true)
			for offset in [-4,4]:draw_circle(p+Vector2(offset,0),2,Color("e1fff0"))
		elif pickup.type=="heal":
			draw_circle(p,12,Color(col,0.12))
			_blob(p,6.0,Color(col,0.8),float(pickup.id),0.8,true)
			draw_line(p-Vector2(2,0),p+Vector2(2,0),Color("e1fff0"),1.0,true)
			draw_line(p-Vector2(0,2),p+Vector2(0,2),Color("e1fff0"),1.0,true)
		elif pickup.type == "dna":
			draw_line(p+Vector2(-4,-6),p+Vector2(4,6),col,2,true)
			draw_line(p+Vector2(4,-6),p+Vector2(-4,6),Color(col,0.6),2,true)
			draw_line(p+Vector2(-4,-4),p+Vector2(4,-4),col,1,true)
			draw_line(p+Vector2(-4,4),p+Vector2(4,4),col,1,true)
		elif pickup.type == "core":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-10),p+Vector2(8,0),p+Vector2(0,10),p+Vector2(-8,0)]),col)
		else: draw_circle(p,4,col)
	var clones=sim.clone_positions() if sim.build.rank("division")>0 else []
	absorbable.clear()
	for cyst in sim.cysts:
		if not area.has_point(cyst.pos) or cyst.get("used",false) or cyst.get("captured",false):continue
		RewardArt.paint(self,screen(cyst.pos),int(cyst.tier),visual_time,int(cyst.id),float(cyst.get("progress",0.0)))
	for fragment in sim.remains:
		if fragment.get("captured",false): continue
		if area.has_point(fragment.pos): painter.paint_fragment(self,screen(fragment.pos),fragment,fragment.id==sim.digesting_id)
	for resident in sim.residents:
		if not resident.active and not resident.dead and area.grow(resident.r).has_point(resident.pos):_silhouette(resident)
	for e in sim.enemies:
		if e.r>sim.body_radius()*2 and e.pos.distance_to(sim.player)>sim.body_radius()*6+e.r:
			if area.grow(e.r).has_point(e.pos):_silhouette(e)
			continue
		if not area.has_point(e.pos): continue
		if feeding.any(func(entry): return entry.get("enemy_id",-1)==e.id): continue
		if can_mark_absorbable(e):absorbable.append(e)
		var organs = enemy_organs(e)
		painter.paint(self,screen(e.pos),e.r*1.17*(1.0-float(e.get("engulf",0))*0.65),e.genome,organs,visual_time,"prey" if e.r<sim.body_radius()*0.82 else e.kind,e.kind=="boss" or detailed_enemies.has(e.id),motion_for(e.id),[],Color(-1,-1,-1),0.0,e.hp/e.max_hp)
		if float(e.get("enzyme_time",0))>0:OrganicFX.infected(self,screen(e.pos),e.r,e.genome,visual_time,float(e.enzyme_time),motion_for(e.id),true)
		if e.infect>0: OrganicFX.infected(self,screen(e.pos),e.r,e.genome,visual_time,float(e.infect),motion_for(e.id))
		if e.kind=="miniboss":draw_string(font,screen(e.pos)+Vector2(-e.r,-e.r*1.5-20),e.get("title","Минибосс"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("f1c987"))
		if e.hp<e.max_hp:
			var p = screen(e.pos)+Vector2(-e.r,-e.r*1.5-10)
			draw_line(p,p+Vector2(e.r*2,0),Color(0.1,0.1,0.15,0.8),3,true)
			draw_line(p,p+Vector2(e.r*2*maxf(0,e.hp/e.max_hp),0),Color("e9a5ad"),3,true)
	if sim.build.rank("division")>0:
		var clone_index = 0
		for p in clones:
			painter.paint(self,screen(p),17,sim.player_genome,{"trail":sim.build.rank("trail")},visual_time+1,"clone",false,motion_for("clone:%d" % clone_index),[],sim.body_color(),0.0,sim.hp/sim.max_hp)
			clone_index += 1
	_draw_player()
	if sim.last_damage.get("kind","")=="toxin" and sim.elapsed-float(sim.last_damage.get("time",-10))<1.5:OrganicFX.infected(self,screen(sim.player),sim.body_radius(),sim.player_genome,visual_time,2.0,motion_for("player"))
	for cyst in sim.cysts:
		if cyst.get("captured",false):RewardArt.paint(self,screen(cyst.pos),int(cyst.tier),visual_time,int(cyst.id),float(cyst.get("progress",0.0)))
	for shot in sim.shots:
		var p = screen(shot.pos)
		var col = Color("e27e9d") if shot.hostile else Color("e7d1a7")
		draw_line(p-shot.vel.normalized()*13,p,col,3,true)
		draw_circle(p,3,col)
	for effect in sim.effects:
		if effect.type in ["damage","heal","lash"]:continue
		if not area.grow(float(effect.r)).has_point(effect.pos):continue
		if OrganicFX.paint(self,effect,sim.player,size*Vector2(0.5,0.51),visual_time,clones): continue
		var p = screen(effect.pos)
		var alpha = effect.life/effect.max
		if effect.type=="lash":
			var end = screen(effect.end)
			var points = PackedVector2Array()
			for i in range(13):
				var t = i/12.0
				points.append(p.lerp(end,t)+Vector2(0,sin(t*PI)*20*alpha))
			draw_polyline(points,Color(0.6,0.95,0.85,alpha),4,true)
		else:
			var col = Color("f5989e") if effect.type=="hurt" else Color("9be8db")
			draw_arc(p,effect.r*(1-alpha*0.6),0,TAU,40,Color(col,alpha*0.55),2,true)
	_draw_damage_sources()
	draw_set_transform(Vector2.ZERO)
	_draw_absorbable(size)
	for cyst in sim.cysts:
		if cyst.get("captured",false) or cyst.get("used",false) or not area.has_point(cyst.pos):continue
		var p=(cyst.pos-sim.player)*zoom+size*Vector2(0.5,0.51)
		var tier=clampi(int(cyst.tier),1,3)
		var label=["Редкая циста","Эпическая циста","Легендарная циста"][tier-1]
		var width=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
		var q=p+Vector2(-width/2,(12.0+tier*3.0)*zoom*1.3+18)
		draw_string(font,q+Vector2.ONE,label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(0.02,0.06,0.08,0.9))
		draw_string(font,q,label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,RewardArt.color(tier))
	if "sensory" in sim.inherited_traits:
		var sensed={};var best=pow(sim.sensing_radius(),2)
		for cyst in sim.cysts:
			var distance=sim.player.distance_squared_to(cyst.pos)
			if not cyst.get("captured",false) and distance<best:best=distance;sensed=cyst
		if not sensed.is_empty():
			var q=size*Vector2(0.5,0.51)+(sensed.pos-sim.player).normalized()*180
			draw_circle(q,6,RewardArt.color(int(sensed.tier)))
			draw_string(font,q+Vector2(-60,25),"Ценная ткань · %d"%sqrt(best),HORIZONTAL_ALIGNMENT_LEFT,-1,20,RewardArt.color(int(sensed.tier)))
	_draw_incoming_damage(size)
	for enemy in sim.enemies:
		if not area.has_point(enemy.pos) or enemy.get("captured",false):continue
		var status="ЗАРАЖЁН" if enemy.infect>0 else ("ФЕРМЕНТЫ" if float(enemy.get("enzyme_time",0))>0 else "")
		if status=="":continue
		var q=(enemy.pos-sim.player)*zoom+size*Vector2(0.5,0.51)+Vector2(-38,enemy.r*zoom*1.35+20)
		draw_string(font,q+Vector2.ONE,status,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("10212b"))
		draw_string(font,q,status,HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("ff9bda") if enemy.infect>0 else Color("ffd78f"))
	for effect in sim.effects:
		if effect.type!="mutation" or not effect.has("text"):continue
		var title=str(effect.text)
		var text_size=font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,22)
		var q=size*Vector2(0.5,0.51)+Vector2(-text_size.x/2,minf(170,sim.body_radius()*zoom*1.5+35))
		draw_string(font,q+Vector2.ONE,title,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("10212b"))
		draw_string(font,q,title,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color(effect.color,minf(1,effect.life*1.5)))
	# Damage labels keep a small constant screen size as the world camera scales.
	for effect in sim.effects:
		if effect.type not in ["damage","heal"]:continue
		var age=1.0-float(effect.life)/float(effect.max)
		var p=(effect.pos-sim.player)*zoom+size*Vector2(0.5,0.51)+Vector2(7,-18-age*24)
		if not Rect2(Vector2.ZERO,size).grow(30).has_point(p):continue
		var amount=float(effect.get("amount",0))
		var healing=effect.type=="heal"
		var text_value=(("+%.2f" % amount) if amount<0.1 else ("+%.1f" % amount)) if healing else str(maxi(1,roundi(amount)))
		var color=Color("69ffaf") if healing else (Color("ff7185") if effect.get("player",false) else Color("ef9199"))
		if healing:p+=Vector2(-45,-20)
		draw_string(font,p+Vector2(1,1),text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(0.05,0.02,0.03,float(effect.life)/float(effect.max)))
		draw_string(font,p,text_value,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color(color,minf(1.0,float(effect.life)*2.0)))
	if joystick_visible:
		draw_circle(joystick_origin,66,Color(0.6,0.9,0.85,0.05))
		draw_arc(joystick_origin,66,0,TAU,48,Color(0.6,0.9,0.85,0.28),2,true)
		draw_circle(joystick_tip,25,Color(0.6,0.9,0.85,0.25))
	if b==1: draw_rect(Rect2(Vector2.ZERO,size),Color(0.15,0.2,0.02,0.025))
	if menu: draw_rect(Rect2(Vector2.ZERO,size),Color(0.015,0.03,0.05,0.45))

func _silhouette(organism: Dictionary):
	var contour=painter.anatomy(organism.genome).contour
	var points=Transform2D(0,Vector2.ONE*float(organism.r)*1.17,0,screen(organism.pos))*contour
	draw_colored_polygon(points,Color(0.07,0.16,0.19,0.5))
	points.append(points[0])
	draw_polyline(points,Color(0.27,0.45,0.47,0.2),1.2,true)
	draw_circle(screen(organism.pos),float(organism.r)*0.2,Color(0.27,0.23,0.36,0.3))

func player_radius() -> float:
	return sim.body_radius()

func _prepare_feeding():
	feeding.clear()
	var radius=player_radius()
	var contour=TissueDamage.contour(painter.anatomy(sim.player_genome).contour,sim.player_genome,sim.hp/sim.max_hp)
	var motion=motion_for("player")
	contour=EvolutionAnatomy.shape(contour,sim.build.stats.evolutions,visual_time,float(sim.player_genome.phase),evolution_growth)
	if motion!=null: contour=motion.deform_points(contour,float(sim.player_genome.phase))
	for fragment in sim.remains:
		if not fragment.get("captured",false): continue
		var offset=fragment.pos-sim.player
		if fragment.get("internal",false): offset=Vector2.from_angle(float(fragment.get("entry_angle",0)))*float(fragment.get("entry_distance",36))
		feeding.append({"pose":Absorption.pose(offset,float(fragment.progress),contour,radius),"fragment":fragment})
	for pickup in sim.pickups:
		if not pickup.get("captured",false):continue
		var recipe=sim.player_genome.duplicate()
		recipe.palette=7 if pickup.type=="heal" else (0 if pickup.type=="dna" else (1 if pickup.type=="core" else 5))
		var offset=Vector2.from_angle(float(pickup.get("entry_angle",0)))*float(pickup.get("entry_distance",0))
		feeding.append({"pose":Absorption.pose(offset,float(pickup.progress),contour,radius),"fragment":{"genome":recipe,"r":6.0,"part":int(pickup.id)%3,"progress":0.0}})
	for enemy in sim.enemies:
		if float(enemy.get("engulf",0))<=0 or not sim._is_engulfing(enemy): continue
		var source=Vector2.from_angle(float(enemy.get("entry_angle",0)))*float(enemy.get("entry_distance",enemy.r)) if enemy.get("captured",false) else enemy.pos-sim.player
		feeding.append({"enemy_id":enemy.id,"pose":Absorption.pose(source,float(enemy.engulf),contour,radius),"fragment":{"genome":enemy.genome,"r":enemy.r*0.8,"part":0,"progress":0.0}})
		if feeding.size()>=12: break

func _draw_player():
	var p = screen(sim.player)
	var rank_sum = 0
	for rank in sim.build.organs.values(): rank_sum += rank
	var radius = player_radius()
	if sim.build.rank("acid")>0:
		var acid_radius=(75+sim.build.rank("acid")*9)*sim.build.specialization_value("acid","radius_mult")*sim.ability_scale()
		draw_circle(p,acid_radius,Color(0.55,0.83,0.3,0.04))
		draw_arc(p,acid_radius,0,TAU,48,Color(0.6,0.85,0.4,0.14),1.0,true)
	var anatomy = player_anatomy if not player_anatomy.is_empty() else sim.build.organs.merged(sim.build.adaptations,true)
	var appearance={"body_chambers":maxi(0,sim.build.organ_capacity-preload("res://core/organism_equipment.gd").base_capacity(str(sim.run_loadout.get("form","predator")))),"stock_chambers":maxi(0,sim.stock_capacity-3),"qualities":sim.build.qualities,"specializations":sim.build.specializations,"temporary_mutations":sim.build.temporary_mutations,"evolved":sim.build.stats.evolutions,"hereditary_traits":sim.inherited_traits,"growth":evolution_growth,"spore_charge":sim.spore_charge,"mantle_flash":0.0,"lashes":{}}
	for effect in sim.effects:
		if effect.type=="mantle":appearance.mantle_flash=sin(PI*(1-float(effect.life)/float(effect.max)))
		if effect.type=="lash":
			var age=1.0-float(effect.life)/float(effect.max)
			appearance.lashes[int(effect.get("limb",0))]={"tip":effect.end-sim.player,"extension":sin(PI*smoothstep(0.0,1.0,age))}
	for enemy in sim.enemies:
		if float(enemy.get("crown_time",0))<=0 or not sim.build.evolved("tentacle") or not EvolutionRules.crown_eligible(radius,enemy,sim.build.rank("magnet")):continue
		var extension=smoothstep(0,0.18,float(enemy.get("crown_age",0)))*smoothstep(0,0.18,float(enemy.crown_time))
		for value in enemy.get("crown_limbs",[]):
			var limb=int(value)
			appearance.lashes[limb]={"tip":EvolutionRules.crown_tip(enemy.pos-sim.player,enemy.r,-1.0 if limb%2==0 else 1.0,visual_time+limb),"extension":extension}
	painter.paint(self,p,radius,sim.player_genome,anatomy,visual_time,"player",true,motion_for("player"),feeding,sim.body_color(),reaction,sim.hp/sim.max_hp,sim.bite_flash,appearance)
	if sim.invuln>0: draw_arc(p,radius*1.4,0,TAU,40,Color("f2c3d1",0.2+0.2*sin(visual_time*24)),2,true)

func enemy_organs(e: Dictionary) -> Dictionary:
	var signature=hash(e.kind)^(int(e.variant)*31)^hash(e.get("traits",[]))
	var cached=organ_cache.get(e.id,{})
	if cached.get("signature",-1)==signature:
		organ_cache_hits+=1
		return cached.organs
	organ_cache_misses+=1
	var organs = {}
	if e.kind=="spitter": organs.infection = 1
	if e.kind in ["boss","miniboss"]:
		organs.tentacle = 2
		organs.spikes = 2
	if int(e.variant)==1: organs.armor = 1
	if int(e.variant)==2: organs.speed = 1
	for mutation in e.get("traits",[]):
		var id = {"shell":"armor","swift":"speed","regen":"regen","toxic":"acid","spores":"infection"}.get(mutation,"")
		if id!="": organs[id] = 2
	organ_cache[e.id]={"signature":signature,"organs":organs}
	return organs

func _blob(p: Vector2,radius: float,color: Color,phase: float,lobes: float,nucleus: bool):
	var points = PackedVector2Array()
	for i in range(24):
		var a = i*TAU/24.0
		var variation = 1+sin(a*5+phase+visual_time*0.7)*0.11*lobes+sin(a*3-phase+visual_time*0.5)*0.16*lobes
		points.append(p+Vector2.from_angle(a)*radius*variation)
	draw_colored_polygon(points,Color(color,0.16 if nucleus else color.a))
	points.append(points[0])
	draw_polyline(points,Color(color,0.72 if nucleus else color.a*0.4),1.6,true)
	if nucleus:
		draw_circle(p+Vector2(radius*0.12,-radius*0.08),radius*0.33,Color(color.lightened(0.2),0.35))
		draw_arc(p+Vector2(radius*0.12,-radius*0.08),radius*0.33,0,TAU,16,Color(color.lightened(0.3),0.6),1,true)
		for i in range(3):
			var q = p+Vector2.from_angle(i*2.2+phase+visual_time*0.13)*radius*0.55
			draw_circle(q,radius*0.1,Color(color,0.35))

func _prune_organ_cache():
	var alive={}
	for enemy in sim.enemies:alive[enemy.id]=true
	for key in organ_cache.keys():
		if not alive.has(key):organ_cache.erase(key)
	# View switches must not retain a cache proportional to the entire world.
	if organ_cache.size()>256:organ_cache.clear()

func can_mark_absorbable(enemy: Dictionary) -> bool:
	if enemy.hp<=0 or enemy.kind=="boss" or enemy.get("captured",false):return false
	if enemy.kind=="miniboss" and enemy.hp>enemy.max_hp*0.15:return false
	# Interaction performs size/contact checks only for nearby visible organisms.
	var reach=sim.body_radius()*5.0+float(enemy.r)
	if enemy.pos.distance_squared_to(sim.player)>reach*reach:return false
	return sim.interaction(enemy).eligible

func _draw_absorbable(size: Vector2):
	absorbable.sort_custom(func(a,b):return a.pos.distance_squared_to(sim.player)<b.pos.distance_squared_to(sim.player))
	for i in range(absorbable.size()):
		var enemy=absorbable[i]
		var p=(enemy.pos-sim.player)*zoom+size*Vector2(0.5,0.51)
		var radius=float(enemy.r)*zoom*1.25+7
		var tint=Color("7ef3e5",0.74+sin(visual_time*3)*0.10)
		if i<3:
			for angle in [0.0,PI]:draw_arc(p,radius,angle-0.36,angle+0.36,8,tint,1.7,true)
			var label="Можно поглотить"
			var width=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x
			var origin=p+Vector2(-width/2,-radius-11)
			draw_string(font,origin+Vector2(1,1),label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(0.01,0.06,0.08,0.9))
			draw_string(font,origin,label,HORIZONTAL_ALIGNMENT_LEFT,-1,18,tint)
		var q=p+Vector2(0,-radius-3)
		draw_polyline(PackedVector2Array([q+Vector2(-4,-3),q+Vector2(0,1),q+Vector2(4,-3)]),tint,1.7,true)

func _draw_damage_sources():
	for marker in sim.damage_markers:
		var alpha=clampf(float(marker.life)/maxf(0.01,float(marker.max)),0,1)
		var p=screen(marker.pos)
		var toxin=str(marker.kind) in ["toxin","acid","spore","toxic","pool"]
		var radius=19.0
		for enemy in sim.enemies:
			if enemy.pos.distance_squared_to(marker.pos)<16:radius=float(enemy.r)*1.3;break
		draw_arc(p,radius,0,TAU,24,Color("f1b76c" if toxin else "ff8398",alpha*0.68),1.4,true)

func _draw_incoming_damage(size: Vector2):
	var source=sim.last_damage
	if source.is_empty():return
	var age=float(sim.elapsed)-float(source.get("time",-10.0))
	if age<0 or age>3.0:return
	var coords=source.get("pos",[])
	var position=coords if coords is Vector2 else (Vector2(coords[0],coords[1]) if coords.size()>=2 else sim.player)
	var offset=position-sim.player
	var alpha=minf(1.0,(3.0-age)*1.3)
	var toxin=str(source.get("kind","")) in ["toxin","acid","spore","toxic","pool"]
	var tint=Color("efbf77" if toxin else "ff879b",alpha*0.85)
	var center=size*Vector2(0.5,0.51)
	# A pool beneath the cell has no meaningful incoming direction.
	if offset.length()<sim.body_radius()*1.6:
		var radius=sim.body_radius()*zoom*1.35+8
		draw_arc(center,radius,0,TAU,48,Color(tint,alpha*0.45),1.7,true)
		if toxin:draw_arc(center,radius+8+sin(visual_time*4)*2,0,TAU,48,Color(tint,alpha*0.25),1.2,true)
		draw_string(font,center+Vector2(-50,radius+25),str(source.get("name","Опасная среда")),HORIZONTAL_ALIGNMENT_LEFT,-1,20,tint)
	else:
		var direction=offset.normalized()
		var extents=Vector2(maxf(80,size.x*0.5-270),maxf(60,size.y*0.5-190))
		var reach=minf(200,minf(extents.x/maxf(0.001,absf(direction.x)),extents.y/maxf(0.001,absf(direction.y))))
		var p=center+direction*reach
		var side=direction.orthogonal()
		draw_polyline(PackedVector2Array([p-direction*11+side*7,p,p-direction*11-side*7]),tint,2.5,true)
		draw_arc(center,reach-13,direction.angle()-0.10,direction.angle()+0.10,12,Color(tint,alpha*0.4),2.0,true)
		var label=str(source.get("name","Источник урона"))
		var width=font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x
		var text_pos=p-direction*30+Vector2(-width/2,5)
		draw_string(font,text_pos+Vector2.ONE,label,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color(0.03,0.02,0.04,alpha*0.9))
		draw_string(font,text_pos,label,HORIZONTAL_ALIGNMENT_LEFT,-1,20,tint)
	if age<0.4:
		draw_arc(center,sim.body_radius()*zoom*1.18,0,TAU,48,Color("ff9aab",(1.0-age/0.4)*0.20),2.0,true)

func _mutation_traits() -> Dictionary:
	var out={}
	for id in sim.build.organs.keys()+sim.build.adaptations.keys():out[id]=[sim.build.rank(id),sim.build.quality(id),sim.build.evolved(id)]
	return out
