extends Node2D
const Catalog = preload("res://core/catalog.gd")
const World = preload("res://game/world.gd")
const Painter = preload("res://game/organism_painter.gd")
var painter = Painter.new()
var sim
var visual_time = 0.0
var menu = false
var joystick_origin = Vector2.ZERO
var joystick_tip = Vector2.ZERO
var joystick_visible = false
var font = ThemeDB.fallback_font

func _process(dt):
	visual_time += dt
	queue_redraw()

func screen(p: Vector2) -> Vector2:
	return p-sim.player+get_viewport_rect().size*Vector2(0.5,0.51)

func _draw():
	var size = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO,size),Color("07141e"))
	if sim == null: return
	var b = sim.world.biome(sim.player)
	var area = Rect2(sim.player-size/2-Vector2.ONE*150,size+Vector2.ONE*300)
	# Layered particles suggest a fluid rather than a flat board.
	for i in range(85):
		var base = Vector2(fposmod(i*237.71+sim.world.seed_value*0.13,2100),fposmod(i*371.91,1300))
		var p = Vector2(fposmod(base.x-sim.player.x*0.22+sin(visual_time*0.1+i)*15,size.x+80)-40,fposmod(base.y-sim.player.y*0.22+visual_time*(2+i%4),size.y+80)-40)
		draw_circle(p,1.3+i%4,Color(0.3,0.7,0.7,0.05+0.018*(i%4)))
	var c1 = sim.world.tile(area.position)
	var c2 = sim.world.tile(area.end)
	for y in range(maxi(0,c1.y),mini(World.H,c2.y+1)):
		for x in range(maxi(0,c1.x),mini(World.W,c2.x+1)):
			var p = Vector2(x+0.5,y+0.5)*World.TILE
			var biome = sim.world.biome(p)
			var hash_value = posmod(x*157+y*977+sim.world.seed_value,100)
			if biome == 1:
				draw_circle(screen(p),85,Color(0.16,0.23,0.10,0.12),false,12)
			if sim.world.cells[y*World.W+x] == 1:
				var color = Color("294536") if biome == 1 else Color("183640")
				_blob(screen(p),World.TILE*0.69,color,hash_value*0.3,0.6,false)
				_blob(screen(p)+Vector2(7,-8),World.TILE*0.48,Color(color,0.45),hash_value,0.3,false)
			elif hash_value<11:
				draw_arc(screen(p),22+hash_value,0.3,4.7,18,Color(0.4,0.65,0.6,0.08),1.5,true)
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
		draw_arc(screen(f.pos),f.r*0.8,0,TAU,24,Color(col,0.17),1,true)
	for pickup in sim.pickups:
		if not area.has_point(pickup.pos): continue
		var p = screen(pickup.pos)+Vector2(0,sin(visual_time*2+pickup.id)*2)
		var col = Color("87eed2") if pickup.type=="dna" else (Color("ecc185") if pickup.type=="bio" else Color("c794f2"))
		draw_circle(p,10 if pickup.type=="core" else 6,Color(col,0.07))
		if pickup.type == "dna":
			draw_line(p+Vector2(-4,-6),p+Vector2(4,6),col,2,true)
			draw_line(p+Vector2(4,-6),p+Vector2(-4,6),Color(col,0.6),2,true)
			draw_line(p+Vector2(-4,-4),p+Vector2(4,-4),col,1,true)
			draw_line(p+Vector2(-4,4),p+Vector2(4,4),col,1,true)
		elif pickup.type == "core":
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-10),p+Vector2(8,0),p+Vector2(0,10),p+Vector2(-8,0)]),col)
		else: draw_circle(p,4,col)
	for e in sim.enemies:
		if not area.has_point(e.pos): continue
		var organs = enemy_organs(e)
		painter.paint(self,screen(e.pos),e.r*1.17,e.genome,organs,visual_time,e.kind,e.kind=="boss" or (e.r>20 and sim.enemies.size()<90))
		if e.infect>0: draw_arc(screen(e.pos),e.r+6,0,TAU,20,Color("b3d47c",0.5),1.4,true)
		if e.hp<e.max_hp:
			var p = screen(e.pos)+Vector2(-e.r,-e.r*1.5-10)
			draw_line(p,p+Vector2(e.r*2,0),Color(0.1,0.1,0.15,0.8),3,true)
			draw_line(p,p+Vector2(e.r*2*maxf(0,e.hp/e.max_hp),0),Color("e9a5ad"),3,true)
	if sim.build.rank("division")>0:
		for p in sim.clone_positions():
			painter.paint(self,screen(p),17,sim.player_genome,{"trail":sim.build.rank("trail")},visual_time+1,"clone",false)
	_draw_player()
	for shot in sim.shots:
		var p = screen(shot.pos)
		var col = Color("e27e9d") if shot.hostile else Color("e7d1a7")
		draw_line(p-shot.vel.normalized()*13,p,col,3,true)
		draw_circle(p,3,col)
	for effect in sim.effects:
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
	if joystick_visible:
		draw_circle(joystick_origin,66,Color(0.6,0.9,0.85,0.05))
		draw_arc(joystick_origin,66,0,TAU,48,Color(0.6,0.9,0.85,0.28),2,true)
		draw_circle(joystick_tip,25,Color(0.6,0.9,0.85,0.25))
	if b==1: draw_rect(Rect2(Vector2.ZERO,size),Color(0.15,0.2,0.02,0.025))
	if menu: draw_rect(Rect2(Vector2.ZERO,size),Color(0.015,0.03,0.05,0.45))

func _draw_player():
	var p = screen(sim.player)
	var rank_sum = 0
	for rank in sim.build.organs.values(): rank_sum += rank
	var radius = minf(44,34+rank_sum*0.36)
	if sim.build.rank("acid")>0:
		draw_circle(p,75+sim.build.rank("acid")*9,Color(0.55,0.83,0.3,0.04))
		draw_arc(p,75+sim.build.rank("acid")*9,0,TAU,48,Color(0.6,0.85,0.4,0.14),1.0,true)
	var anatomy = sim.build.organs.duplicate()
	anatomy.merge(sim.build.adaptations,true)
	painter.paint(self,p,radius,sim.player_genome,anatomy,visual_time,"player",true)
	if sim.invuln>0: draw_arc(p,radius*1.4,0,TAU,40,Color("f2c3d1",0.2+0.2*sin(visual_time*24)),2,true)

func enemy_organs(e: Dictionary) -> Dictionary:
	var organs = {}
	if e.kind=="spitter": organs.infection = 1
	if e.kind=="boss":
		organs.tentacle = 2
		organs.spikes = 2
	if int(e.variant)==1: organs.armor = 1
	if int(e.variant)==2: organs.speed = 1
	for mutation in e.get("traits",[]):
		var id = {"shell":"armor","swift":"speed","regen":"regen","toxic":"acid","spores":"infection"}.get(mutation,"")
		if id!="": organs[id] = 2
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
