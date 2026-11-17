extends RefCounted
const EvolutionAnatomy=preload("res://game/evolution_anatomy.gd")
const Catalog = preload("res://core/catalog.gd")
const Rewards = preload("res://core/rewards.gd")
const Pigment = preload("res://core/pigment.gd")
const Absorption = preload("res://game/absorption.gd")
const Genome = preload("res://core/genome.gd")
const TissueDamage = preload("res://game/tissue_damage.gd")
const MouthShape = preload("res://game/mouth_shape.gd")
const OrganicVolume = preload("res://game/organic_volume.gd")
var volume=OrganicVolume.new()
var _tissue_basis=PackedVector2Array()
var _tissue_indices=PackedInt32Array()
var cache: Dictionary = {}
var glow: GradientTexture2D
var _anchor_contour=PackedVector2Array()
var _anchor_directions=PackedVector2Array()
var _anchors_active=false

# Distinct authored growth steps keep upgrades legible after appendage counts cap.
static func visual_stage(rank: int) -> int:
	if rank>=10: return 3
	if rank>=6: return 2
	if rank>=3: return 1
	return 0

func _init():
	for i in range(12):
		_tissue_basis.append(Vector2.from_angle(i*TAU/12.0))
		_tissue_indices.append_array(PackedInt32Array([0,1+i,1+(i+1)%12]))
	var gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0,0.32,0.7,1.0])
	gradient.colors = PackedColorArray([Color(1,1,1,0.9),Color(1,1,1,0.7),Color(1,1,1,0.22),Color(1,1,1,0)])
	glow = GradientTexture2D.new()
	glow.gradient = gradient
	glow.width = 96
	glow.height = 96
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5,0.5)
	glow.fill_to = Vector2(1,0.5)

func anatomy(recipe: Dictionary) -> Dictionary:
	var key = hash(recipe)
	if key in cache: return cache[key]
	if cache.size()>=260: cache.erase(cache.keys()[0])
	var rng = RandomNumberGenerator.new()
	rng.seed = int(recipe.seed)*1664525+int(recipe.identity)*1013904223+59273
	var contour = Genome.contour(recipe)
	var particles = []
	for attempt in range(180):
		if particles.size()>=12: break
		var p = Vector2(rng.randf_range(-0.85,0.85),rng.randf_range(-0.85,0.85))
		if Geometry2D.is_point_in_polygon(p*1.22,contour): particles.append({"pos":p,"size":rng.randf_range(0.025,0.075),"type":rng.randi_range(0,2)})
	var veins = []
	for i in range(particles.size()):
		var best = -1
		var distance = 10.0
		for j in range(i+1,particles.size()):
			var d = particles[i].pos.distance_squared_to(particles[j].pos)
			if d<distance:
				distance = d
				best = j
		if best>=0 and distance<0.4 and veins.size()<8: veins.append([particles[i].pos,particles[best].pos])
	# Chromatin reads as a single soft region within continuous cytoplasm.
	var nuclei = [Vector2(-0.08,0.05)]
	var fragments=[]
	for part in range(3):
		var points=PackedVector2Array()
		for point_index in range(19):points.append(contour[(part*13+point_index)%contour.size()])
		points.append(Vector2(-0.13,0.09))
		var hull=Geometry2D.convex_hull(points)
		if hull.size()>1 and hull[0].is_equal_approx(hull[-1]):hull.resize(hull.size()-1)
		fragments.append(hull)
	var data = {"contour":contour,"contour_lod":Genome.contour(recipe,24),"particles":particles,"veins":veins,"nuclei":nuclei,"colors":Genome.colors(recipe),"fragments":fragments}
	cache[key] = data
	return data

func paint(canvas: CanvasItem,p: Vector2,radius: float,recipe: Dictionary,organs: Dictionary,time: float,role: String="player",detail: bool=true,motion=null,feeding: Array=[],tint: Color=Color(-1,-1,-1),reaction: float=0.0,health_ratio: float=1.0,bite_strength: float=0.0,appearance: Dictionary={}):
	if not Genome.validate(recipe): return
	var data = anatomy(recipe)
	var body: Color = data.colors[0]
	var edge: Color = data.colors[1]
	var core: Color = data.colors[2]
	var accent: Color = data.colors[3]
	var shadow: Color = data.colors[4]
	if tint.r>=0:
		body=tint
		edge=tint.lightened(0.38)
		shadow=tint.darkened(0.42)
	var highest_rank=0
	for rank in organs.values(): highest_rank=maxi(highest_rank,int(rank))
	var stage=visual_stage(highest_rank)
	var distress = TissueDamage.severity(health_ratio)
	var wounds = TissueDamage.wounds(recipe,health_ratio)
	body=body.lerp(shadow,distress*0.18)
	var base_phase = float(recipe.phase)
	var turn = motion.angle_delta() if motion != null else 0.0
	var phase = base_phase+turn
	var facing = float(recipe.rotation)+turn
	var breathe = 1+sin(time*1.7+phase)*0.025+reaction*0.055
	var contour = TissueDamage.contour(data.contour if detail else data.contour_lod,recipe,health_ratio)
	contour=EvolutionAnatomy.shape(contour,appearance.get("evolved",{}),time,base_phase,appearance.get("growth",{}))
	if motion != null: contour = motion.deform_points(contour,base_phase)
	for entry in feeding:
		var pose=entry.pose.duplicate()
		pose.bulge/=maxf(1.0,float(feeding.size()))
		contour=Absorption.membrane(contour,pose,radius)
	_prepare_anchors(contour)
	if int(organs.get("speed",0))>0:
		for i in range(3):
			_tendril(canvas,p,contour,radius,facing+PI+i*0.55-0.55,time+phase+i,0.9+visual_stage(int(organs.speed))*0.16,_organ_color("speed",edge,appearance),1.4+visual_stage(int(organs.speed))*0.4)
	if int(organs.get("regen",0))>0:
		for i in range(3): _branch(canvas,p,contour,radius,i*TAU/3+phase,time,_organ_color("regen",edge.lerp(Color("a4dfbc"),0.5),appearance))
	if int(organs.get("magnet",0))>0 or int(recipe.family)==5:
		var count = 16 if detail else 8
		for i in range(count): _tendril(canvas,p,contour,radius,i*TAU/count+phase,time+phase+i,0.27+sin(time*2+i)*0.05,Color(_organ_color("magnet",edge,appearance),0.75),0.8)
	var outer = _transform(contour,p,radius*breathe)
	if detail:canvas.draw_colored_polygon(_transform(contour,p+Vector2(2,4),radius*1.025*breathe),Color(0.0,0.02,0.035,0.35))
	volume.paint(canvas,contour,p,radius*breathe,body,edge,shadow,detail,base_phase)
	for entry in feeding: _inclusion(canvas,p,radius,entry,body,edge,time)
	if reaction>0.01:
		for i in range(5):
			var a=phase+i*TAU/5
			var q=p+_anchor(contour,a)*radius*(0.45+reaction*0.2)
			canvas.draw_circle(q,radius*(0.07+reaction*0.09),Color(accent,0.18*reaction))
	if detail:
		for fold_index in range(5):
			var fold=PackedVector2Array()
			for j in range(13):
				var u=j/12.0
				var sample=posmod(int(fold_index*contour.size()/5.0+j*contour.size()/90.0),contour.size())
				var point=contour[sample]*(0.30+u*0.49)
				fold.append(p+point*radius*breathe)
			canvas.draw_polyline(fold,Color(shadow,0.16),maxf(1.2,radius*0.035),true)
			canvas.draw_polyline(fold,Color(edge,0.16),maxf(0.6,radius*0.012),true)
		for vein in data.veins:
			var a = p+_tissue_point(vein[0],wounds,motion,base_phase)*radius*breathe
			var b = p+_tissue_point(vein[1],wounds,motion,base_phase)*radius*breathe
			var strand=PackedVector2Array()
			for i in range(9):
				var u=i/8.0
				strand.append(a.lerp(b,u)+(b-a).orthogonal()*sin(u*PI)*0.12)
			canvas.draw_polyline(strand,Color(edge,0.075),maxf(0.6,radius*0.016),true)
		for particle in data.particles:
			var point = p+_tissue_point(particle.pos,wounds,motion,base_phase)*radius*breathe
			var color = accent if particle.type==0 else edge
			_soft_tissue(canvas,point,particle.size*radius*1.15,Color(color,0.22),float(particle.type)*2.1+point.x*0.01)
	var n = 0
	for nucleus in data.nuclei:
		_nucleus(canvas,p+_tissue_point(nucleus,wounds,motion,base_phase)*radius,radius*0.205*(1.0+distress*0.06*sin(time*(4.5+distress*2.0)+n*2.3)),core.lerp(shadow,distress*0.35),edge,time+phase+n,detail)
		n += 1
	if distress>(0.001 if detail else 0.55): _wounds(canvas,p,contour,radius*breathe,wounds,turn,time,body,edge,shadow,detail)
	var loop = outer.duplicate()
	loop.append(loop[0])
	canvas.draw_polyline(loop,Color(edge,0.43+stage*0.045),(1.8+stage*0.45) if detail else 1.2,true)
	# Directional wet membrane catches upper-left light; underside stays thick.
	var wet_rim=PackedVector2Array()
	for i in range(contour.size()+1):
		var index=i%contour.size()
		if contour[index].normalized().dot(OrganicVolume.LIGHT)>0.30:
			wet_rim.append(p+contour[index]*radius*breathe*0.958)
		else:
			if wet_rim.size()>1: canvas.draw_polyline(wet_rim,Color(edge.lightened(0.22),0.59),maxf(0.7,radius*0.018),true)
			wet_rim=PackedVector2Array()
	if wet_rim.size()>1: canvas.draw_polyline(wet_rim,Color(edge.lightened(0.22),0.59),maxf(0.7,radius*0.018),true)
	if role=="player" and stage>0 and detail:
		# Broad pigmented membrane folds stay part of the same continuous body.
		for fold_index in range(3):
			var fold=PackedVector2Array()
			for j in range(11):
				var a=phase+fold_index*TAU/3+(j/10.0-0.5)*(0.55+stage*0.12)
				fold.append(p+_anchor(contour,a)*radius*(0.94+sin(j/10.0*PI)*0.018))
			canvas.draw_polyline(fold,Color(edge.lerp(accent,0.35),0.18+stage*0.07),radius*(0.028+stage*0.012),true)
	var inner = _transform(contour,p,radius*0.91*breathe)
	inner.append(inner[0])
	if detail:canvas.draw_polyline(inner,Color(edge,0.25),0.8,true)
	if detail and int(recipe.membrane)==1:
		for i in range(0,contour.size(),3): canvas.draw_line(p+contour[i]*radius*0.92,p+contour[i]*radius,Color(edge,0.45),1,true)
	elif detail and int(recipe.membrane)==2:
		for i in range(0,contour.size(),6): _soft_tissue(canvas,p+contour[i]*radius*0.95,radius*0.045,Color(edge,0.23),float(i))
	if int(organs.get("armor",0))>0: _plates(canvas,p,contour,radius*(1.0+sin(time*1.8)*0.018),phase,_organ_color("armor",accent,appearance),int(organs.armor))
	if int(organs.get("spikes",0))>0: _spikes(canvas,p,contour,radius*(1.0+0.045*sin(time*3.4)),phase,_organ_color("spikes",accent,appearance),int(organs.spikes))
	if int(organs.get("tentacle",0))>0:
		var count = Catalog.tentacle_count(int(organs.tentacle))
		for i in range(count):
			var strike=appearance.get("lashes",{}).get(i,{})
			var tentacle_color=_organ_color("tentacle",edge,appearance)
			if bool(appearance.get("evolved",{}).get("tentacle",false)):
				if int(organs.get("acid",0))>0:tentacle_color=tentacle_color.lerp(Color("bbec76"),0.35)
				if int(organs.get("infection",0))>0:tentacle_color=tentacle_color.lerp(Color("ec9bd5"),0.25)
			_tendril(canvas,p,contour,radius,phase+i*TAU/count,time+phase+i,0.9+visual_stage(int(organs.tentacle))*0.20,tentacle_color,(3.0 if detail else 2.0)+visual_stage(int(organs.tentacle))*0.65,strike.get("tip"),float(strike.get("extension",0)))
	if int(organs.get("cilia",0))>0 and detail:
		for i in range(8):_tendril(canvas,p,contour,radius,facing-1.2+i*0.34,time+i,0.20+visual_stage(int(organs.cilia))*0.065+sin(time*5+i*0.3)*0.06,_organ_color("cilia",edge,appearance),0.7+visual_stage(int(organs.cilia))*0.35)
	if int(organs.get("enzymes",0))>0:
		for i in range(2):_vesicle(canvas,p+_anchor(contour,phase+i*2.6)*radius*0.74,radius*(0.16+visual_stage(int(organs.enzymes))*0.025)*(1+sin(time*3.2+i)*0.15),_organ_color("enzymes",body.lerp(Color("e7c28b"),0.45),appearance),detail)
	if int(organs.get("electric",0))>0 and detail:
		for i in range(3):
			var root=p+_anchor(contour,phase+i*2.0)*radius*0.68
			canvas.draw_line(p+(root-p)*0.38,root,Color(_organ_color("electric",body.lerp(Color("afdfe9"),0.65),appearance),0.20+0.06*sin(time*2+i)),0.9,true)
	if int(organs.get("barrier",0))>0:
		var reinforced=_transform(contour,p,radius*0.97)
		reinforced.append(reinforced[0])
		canvas.draw_polyline(reinforced,Color(_organ_color("barrier",edge,appearance),0.45+visual_stage(int(organs.barrier))*0.08+sin(time*2.5)*0.10),maxf(1.4,radius*(0.035+visual_stage(int(organs.barrier))*0.013)),true)
	if int(organs.get("acid",0))>0:
		for i in range(mini(5,2+int(organs.acid))):
			_vesicle(canvas,p+_anchor(contour,phase+0.7+i*2.15)*radius*0.75,radius*(0.17+visual_stage(int(organs.acid))*0.02)*(1+sin(time*2.8+i)*0.14),_organ_color("acid",body.lerp(Color("b4d952"),0.55),appearance),detail)
	if int(organs.get("infection",0))>0:
		for i in range(3):
			var center = p+_anchor(contour,phase+i*2.1)*radius*0.87
			_vesicle(canvas,center,radius*(0.14+sin(time*3.8+i)*0.025),_organ_color("infection",body.lerp(Color("e48abd"),0.65),appearance),detail)
			if detail:
				for j in range(3): _soft_tissue(canvas,center+Vector2.from_angle(j*TAU/3)*radius*0.06,radius*0.025,Color("f1bddb",0.28),float(j))
	if int(organs.get("trail",0))>0: _vesicle(canvas,p+_anchor(contour,facing+PI)*radius*0.88,radius*(0.19+sin(time*2.6)*0.025),_organ_color("trail",body.lerp(Color("8fbd5b"),0.6),appearance),detail)
	var front_feeding=0.0
	for entry in feeding:
		if entry.pose.direction.normalized().dot(Vector2.from_angle(facing))>cos(0.7):
			front_feeding=maxf(front_feeding,sin(float(entry.pose.progress)*PI))
	_mouth(canvas,p,contour,radius*breathe,facing,time+phase,body,_organ_color("devour",edge,appearance),shadow,bite_strength,front_feeding,int(organs.get("devour",0)),detail)
	if int(organs.get("pulse",0))>0:
		var ring = _transform(contour,p,radius*(1.04+sin(time*2+phase)*0.045))
		ring.append(ring[0])
		canvas.draw_polyline(ring,Color(_organ_color("pulse",Color("a7cbe1"),appearance),0.45+sin(time*2+phase)*0.18),1.2,true)
	if int(organs.get("division",0))>0:
		for i in range(mini(4,1+int(organs.division))):
			var bud = p+_anchor(contour,phase+1+i*1.6)*radius*0.95
			_soft_tissue(canvas,bud,radius*(0.19+0.02*sin(time*2+i)),Color(_organ_color("division",body,appearance),0.82),phase+i)
			_soft_tissue(canvas,bud-Vector2.ONE*radius*0.015,radius*0.14,Color(edge,0.14),phase+i)
			_nucleus(canvas,bud,radius*0.08,core,edge,time+i,false)
	if role=="player" and detail:_hereditary_marks(canvas,p,contour,radius,time,phase,body,edge,appearance.get("hereditary_traits",[]))
	if role=="player" and detail:_evolved_organs(canvas,p,contour,radius,organs,time,phase,body,edge,appearance)
	if role=="player" and detail:_living_marks(canvas,p,contour,radius,organs,time,phase,body,edge,appearance)
	if role=="player":
		canvas.draw_arc(p,radius*1.48,0.35,2.8,22,Color("d4fff2",0.33),1.2,true)
		var marker = p+Vector2(0,radius*1.5+8)
		canvas.draw_colored_polygon(PackedVector2Array([marker+Vector2(-4,4),marker+Vector2(4,4),marker+Vector2(0,-3)]),Color("d4fff2"))
	elif role in ["hunter","boss","spitter"]:
		var indicator = p+Vector2(0,-radius*1.22)
		canvas.draw_line(indicator-Vector2(7,0),indicator+Vector2(7,0),Color("ed939c",0.9),1.6,true)
	elif role=="prey":
		canvas.draw_arc(p,radius*1.15,0.1,1.9,12,Color("e9d58e",0.65),1,true)

	_anchors_active=false

func _tissue_point(point: Vector2,wounds: Array,motion,phase: float) -> Vector2:
	return _deform(TissueDamage.deform_point(point,wounds),motion,phase)

func _wounds(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,wounds: Array,turn: float,time: float,body: Color,edge: Color,shadow: Color,detail: bool):
	for wound in wounds:
		var amount=float(wound.strength)
		var lip=_anchor(contour,float(wound.angle)+turn)
		var outward=lip.normalized()
		var normal=outward.orthogonal()
		var root=p+lip*radius
		var reach=radius*(0.16+amount*0.15)
		var width=radius*0.035*amount
		var end=root-outward*reach
		var kink=root-outward*reach*0.45+normal*reach*0.15
		# Translucent fissures branch inward from torn membrane; the cytoplasm
		# remains visible through them rather than producing opaque black holes.
		var scar=_wound_scar(root,kink,end,normal,width)
		if scar.size()>=3: canvas.draw_colored_polygon(scar,Color(shadow.darkened(0.5),amount*0.63))
		canvas.draw_polyline(PackedVector2Array([root,kink,end]),Color(shadow.darkened(0.7),amount*0.78),maxf(0.7,radius*0.025*amount),true)
		for side in [-1,1]:
			var branch=kink-outward*reach*0.35+normal*side*reach*0.34
			canvas.draw_line(kink,branch,Color(shadow,amount*0.65),maxf(0.7,radius*0.014),true)
			var strand=root+normal*width*side
			canvas.draw_line(strand,strand+outward*radius*0.09*amount+normal*side*radius*0.035,Color(edge,amount*0.75),0.9,true)
		if detail or amount>0.6:
			for i in range(3):
				var travel=fposmod(time*(0.26+amount*0.12)+float(wound.index)*0.273+i/3.0,1.0)
				var drift=outward*radius*(0.02+travel*(0.24+amount*0.16))+normal*sin(travel*3.0+float(i))*radius*0.07*travel
				var opacity=sin(travel*PI)*amount*0.7
				var mote_radius=radius*(0.018+0.026*amount)*(1.0-travel*0.58)
				canvas.draw_line(root,root+drift*0.5,Color(body,opacity*0.13),mote_radius*1.2,true)
				canvas.draw_circle(root+drift,mote_radius,Color(body.lightened(0.15),opacity))
				canvas.draw_arc(root+drift,mote_radius,0.3,4.8,7,Color(edge,opacity*0.7),0.6,true)

func _deform(point: Vector2,motion,phase: float) -> Vector2:
	return point if motion == null else motion.deform_point(point,phase)

func paint_fragment(canvas: CanvasItem,p: Vector2,fragment: Dictionary,active: bool,opacity: float=1.0):
	var data = anatomy(fragment.genome)
	var fragment_color: Color=Pigment.color(fragment.pigment) if fragment.has("pigment") else data.colors[0]
	var quality=clampi(int(fragment.get("quality",0)),0,3)
	var accent_color=Rewards.quality_color(quality)
	var progress = float(fragment.progress)
	var radius = float(fragment.r)*(1.0-progress*0.72)
	var local: PackedVector2Array=data.fragments[posmod(int(fragment.part),3)]
	var points=_transform(local,p,radius)
	if quality>0:
		canvas.draw_circle(p,radius*1.55,Color(accent_color,(0.10+quality*0.035)*opacity))
	canvas.draw_colored_polygon(points,Color(fragment_color.lerp(accent_color,quality*0.14),(0.72-progress*0.2)*opacity))
	canvas.draw_polyline(points,Color(data.colors[1].lerp(accent_color,quality*0.24),(0.55+quality*0.14)*opacity),1.0+quality*0.35,true)
	if quality>=2:
		for i in range(quality):
			var glint=p+Vector2.from_angle(i*TAU/quality+float(fragment.id)*0.7)*radius*0.8
			canvas.draw_circle(glint,1.1+quality*0.25,Color(accent_color,0.75*opacity))
	for i in range(3):
		var q = p+(points[posmod(1+i*5,points.size())]-p)*0.65
		canvas.draw_circle(q,radius*0.09,Color(data.colors[3],0.75*opacity))


func _inclusion(canvas: CanvasItem,p: Vector2,radius: float,entry: Dictionary,body: Color,edge: Color,time: float):
	var state=entry.pose
	var t=float(state.progress)
	var q=p+state.offset
	var color: Color=Pigment.color(entry.fragment.pigment) if entry.fragment.has("pigment") else Genome.colors(entry.fragment.genome)[0]
	var fragment=entry.fragment.duplicate()
	fragment.progress=0.0
	fragment.r*=float(state.scale)
	# Lip folds and translucent film physically join the body to incoming tissue.
	if t<0.68:
		var normal=state.direction.orthogonal()
		var spread=radius*(0.16+sin(t*PI)*0.12)
		for side in [-1,1]:
			var points=PackedVector2Array()
			var root=p+state.edge*0.72+normal*spread*side
			var tip=q+normal*float(fragment.r)*0.4*side
			for i in range(13):
				var u=i/12.0
				points.append(root.lerp(tip,u)+normal*side*sin(u*PI)*spread*0.6)
			canvas.draw_polyline(points,Color(body,0.4*(1-t)),6,true)
			canvas.draw_polyline(points,Color(edge,0.65*(1-t)),1.3,true)
	paint_fragment(canvas,q,fragment,false,float(state.alpha))
	if t>0.32:
		# A vesicle membrane closes around the inclusion, then breaks into pigment.
		var capsule=float(entry.fragment.r)*(1.1-float(state.progress)*0.65)
		canvas.draw_arc(q,capsule,0.15+time*0.2,TAU-0.3+time*0.2,24,Color(edge,0.4*float(state.alpha)),1.0,true)
		for i in range(9):
			var a=i*2.399+float(entry.fragment.part)
			var destination=Vector2.from_angle(a)*radius*(0.22+0.05*(i%4))
			var mote=q.lerp(p+destination,smoothstep(0.35,1.0,t))
			var opacity=sin(smoothstep(0.3,1.0,t)*PI)
			canvas.draw_circle(mote,1.1+sin(a+time)*0.3,Color(color.lightened(0.24),opacity*0.8))

func _transform(points: PackedVector2Array,p: Vector2,radius: float) -> PackedVector2Array:
	return Transform2D(0,Vector2.ONE*radius,0,p)*points

func _prepare_anchors(contour: PackedVector2Array):
	_anchor_contour=contour
	_anchor_directions.resize(contour.size())
	for i in range(contour.size()): _anchor_directions[i]=contour[i].normalized()
	_anchors_active=true

func _anchor(contour: PackedVector2Array,angle: float) -> Vector2:
	var best = -2.0
	var chosen = contour[0]
	var direction = Vector2.from_angle(angle)
	if _anchors_active and contour==_anchor_contour:
		# Armor alone asks for up to45 anchors. Normalize each living contour
		# once, preserving exactly the original nearest-direction choice.
		for i in range(contour.size()):
			var score=_anchor_directions[i].dot(direction)
			if score>best:
				best=score
				chosen=contour[i]
		return chosen
	for point in contour:
		var score = point.normalized().dot(direction)
		if score>best:
			best = score
			chosen = point
	return chosen

# Irregular translucent layers merge with living tissue instead of looking like
# separate glass marbles or inventory icons floating inside the cell.
func _soft_tissue(canvas: CanvasItem,p: Vector2,radius: float,color: Color,phase: float):
	# One pre-triangulated soft patch: no polygon triangulation or trigonometry
	# for every organelle. Dark lower edge gives inclusions optical thickness.
	var points=PackedVector2Array([p])
	var colors=PackedColorArray([Color(color.lightened(0.15),color.a)])
	for i in range(12):
		var basis: Vector2=_tissue_basis[i]
		var ripple=1.0+sin(i*TAU/4.0+phase)*0.11
		points.append(p+basis*Vector2(1.18,0.82)*radius*ripple)
		var light=basis.dot(OrganicVolume.LIGHT)
		colors.append(Color(color.lightened(maxf(0.0,light)*0.20).darkened(maxf(0.0,-light)*0.37),color.a*0.12))
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),_tissue_indices,points,colors)

func _nucleus(canvas: CanvasItem,p: Vector2,radius: float,color: Color,edge: Color,time: float,detail: bool):
	var phase=time*0.08
	# A broad recessed organ: lower bright wall, upper occlusion and visible
	# tangled chromatin share the body palette and remain beneath the wet film.
	_soft_tissue(canvas,p+Vector2(radius*0.16,radius*0.23),radius*1.52,Color(edge,0.26),phase)
	_soft_tissue(canvas,p-Vector2(radius*0.07,radius*0.09),radius*1.28,Color(color.darkened(0.65),0.76),phase)
	_soft_tissue(canvas,p,radius,Color(color,0.70),phase)
	_soft_tissue(canvas,p-Vector2(radius*0.28,radius*0.31),radius*0.52,Color(edge,0.25),phase+1.4)
	if detail:
		for strand_index in range(3):
			var strand=PackedVector2Array()
			for i in range(17):
				var u=i/16.0
				strand.append(p+Vector2((u-0.5)*1.6,sin(u*TAU*1.5+phase+strand_index)*0.23+(strand_index-1)*0.25)*radius)
			canvas.draw_polyline(strand,Color(color.darkened(0.65),0.52),maxf(0.65,radius*0.09),true)
		_soft_tissue(canvas,p+Vector2(radius*0.18,-radius*0.05),radius*0.30,Color(color.darkened(0.65),0.85),phase)

func _vesicle(canvas: CanvasItem,p: Vector2,radius: float,color: Color,detail: bool):
	_soft_tissue(canvas,p+Vector2(0,radius*0.12),radius*1.2,Color(color.lightened(0.26),0.29),p.x*0.1)
	_soft_tissue(canvas,p,radius,Color(color.darkened(0.40),0.48),p.x*0.1)
	if not detail: return
	_soft_tissue(canvas,p-Vector2(radius*0.12,radius*0.16),radius*0.70,Color(color,0.48),p.x*0.1+0.6)
	var fold=PackedVector2Array()
	for i in range(10):
		var a=0.3+i*0.24
		fold.append(p+Vector2(cos(a),sin(a)*0.65)*radius*0.8)
	canvas.draw_polyline(fold,Color(color.lightened(0.25),0.35),0.9,true)

func _mouth(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,heading: float,time: float,body: Color,edge: Color,shadow: Color,bite: float,feeding: float,rank: int,detail: bool):
	var shape=MouthShape.pose(contour,heading,bite,feeding)
	var activation=float(shape.activation)
	var direction: Vector2=shape.direction
	var tangent: Vector2=shape.tangent
	# Broad, pigmented jaw tissue blends into the membrane around the cavity.
	# The inward lower lip opens much farther than the anchored upper lip.
	for lip in [shape.upper,shape.lower]:
		var points=_transform(lip,p,radius)
		canvas.draw_polyline(points,Color(body.lerp(shadow,0.18),0.86),maxf(2.2,radius*(0.09+activation*0.035)),true)
	canvas.draw_colored_polygon(_transform(shape.slit,p,radius),Color(shadow.darkened(0.65),0.90))
	if activation>0.12:
		var inner=PackedVector2Array()
		for point in shape.slit:
			inner.append(shape.throat+(point-shape.throat)*0.58)
		canvas.draw_colored_polygon(_transform(inner,p,radius),Color(shadow.darkened(0.88),activation*0.69))
	for lip in [shape.upper,shape.lower]:
		canvas.draw_polyline(_transform(lip,p,radius),Color(body.lerp(edge,0.23),0.79),maxf(0.8,radius*0.026),true)
	if not detail: return
	# Elastic throat pleats are recessed organic folds, visible during engulfing.
	if activation>0.15:
		for i in range(5):
			var u=0.22+i*0.14
			var root: Vector2=shape.lower[int(u*16)]
			var end: Vector2=root.lerp(shape.throat,0.62)
			var curve=PackedVector2Array([root,root.lerp(end,0.5)+tangent*radius*0.0003*sin(time+i),end])
			canvas.draw_polyline(_transform(curve,p,radius),Color(body.lerp(edge,0.15),activation*0.28),maxf(0.6,radius*0.011),true)
	if rank>0:
		for i in range(5):
			var root: Vector2=shape.upper[4+i*2]
			var tip=root-direction*(0.013+mini(rank,2)*0.007+visual_stage(rank)*0.009)
			canvas.draw_line(p+root*radius,p+tip*radius,Color(edge,0.38),maxf(0.6,radius*0.012),true)

func _spikes(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,phase: float,color: Color,rank: int):
	var count = mini(12,5+rank)
	for i in range(count):
		var a = _anchor(contour,i*TAU/count+phase)
		var normal = a.normalized().orthogonal()
		var root = p+a*radius*0.9
		var tip = p+a*radius+a.normalized()*radius*(0.35+visual_stage(rank)*0.095+0.15*sin(i*3.7+phase))
		var bend=root.lerp(tip,0.56)+normal*radius*0.025*sin(i*2.3)
		canvas.draw_colored_polygon(PackedVector2Array([root-normal*radius*0.085,bend-normal*radius*0.025,tip,bend+normal*radius*0.025,root+normal*radius*0.085]),Color(color.darkened(0.15),0.88))
		canvas.draw_line(root,tip,Color(color.lightened(0.35),0.85),1,true)

func _plates(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,phase: float,color: Color,rank: int):
	# Thickened scalloped membrane follows the silhouette, not rigid diamonds.
	var count=3+mini(2,rank)
	for i in range(count):
		var angle=i*TAU/count+phase
		var pad=PackedVector2Array()
		for j in range(9):
			var u=j/8.0
			var a=angle+(u-0.5)*0.65
			pad.append(p+_anchor(contour,a)*radius*(0.97+sin(u*PI)*0.045))
		canvas.draw_polyline(pad,Color(color.darkened(0.25),0.55),maxf(2.0,radius*(0.105+visual_stage(rank)*0.026)),true)
		canvas.draw_polyline(pad,Color(color.lightened(0.15),0.54),maxf(1.0,radius*(0.042+visual_stage(rank)*0.010)),true)

func _tendril(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,angle: float,time: float,length_scale: float,color: Color,width: float,tip=null,extension: float=0.0):
	var a = _anchor(contour,angle)
	var normal = a.normalized().orthogonal()
	var points = PackedVector2Array()
	var flesh=PackedVector2Array()
	for i in range(10):
		var t = i/9.0
		var resting=p+a*radius*(0.76+t*length_scale)+normal*radius*sin(t*4+time*1.5)*t*0.24
		if tip!=null:
			var strike=(p+a*radius*0.76).lerp(p+Vector2(tip),t)+normal*sin(t*PI)*radius*0.25
			resting=resting.lerp(strike,extension)
		points.append(resting)
	# A broad taper grows directly out of the cytoplasm and narrows to a whip.
	for i in range(points.size()):
		var t=i/float(points.size()-1)
		flesh.append(points[i]-normal*(radius*0.09+width*0.3)*pow(1.0-t,1.6))
	for i in range(points.size()-1,-1,-1):
		var t=i/float(points.size()-1)
		flesh.append(points[i]+normal*(radius*0.09+width*0.3)*pow(1.0-t,1.6))
	canvas.draw_colored_polygon(flesh,Color(color.darkened(0.17),0.72))
	canvas.draw_polyline(points,Color(color.lightened(0.08),0.76),maxf(0.7,width*0.65),true)

func _branch(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,angle: float,time: float,color: Color):
	var a = _anchor(contour,angle)
	var root = p+a*radius*0.9
	var tip = p+a*radius*1.28
	canvas.draw_line(root,tip,Color(color.darkened(0.15),0.7),maxf(1.8,radius*0.065),true)
	for side in [-1,1]:
		var end = tip+a.normalized().rotated(side*0.7)*radius*0.22
		canvas.draw_line(tip,end+Vector2(0,sin(time+angle)*radius*0.02),Color(color,0.5),maxf(0.8,radius*0.025),true)

static func _wound_scar(root: Vector2,kink: Vector2,end: Vector2,normal: Vector2,width: float) -> PackedVector2Array:
	# At screen coordinates, subpixel fissures can collapse under float precision.
	# Their visible center strand is drawn separately; skip an invisible fill.
	if width<0.02: return PackedVector2Array()
	var hull=Geometry2D.convex_hull(PackedVector2Array([root-normal*width,kink-normal*width*0.6,end,kink+normal*width*0.6,root+normal*width]))
	if hull.size()<4: return PackedVector2Array()
	hull.resize(hull.size()-1)
	if Geometry2D.triangulate_polygon(hull).is_empty(): return PackedVector2Array()
	return hull

# Rare pigments follow the actual organs; no floating inventory shapes.
func _organ_color(id: String,base: Color,appearance: Dictionary) -> Color:
	var grade=clampi(int(appearance.get("qualities",{}).get(id,0)),0,3)
	return base.lerp(Rewards.quality_color(grade),0.63 if grade>0 else 0.0)

func _living_marks(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,organs: Dictionary,time: float,phase: float,body: Color,edge: Color,appearance: Dictionary):
	# Two metabolic canals and catalytic folds give these otherwise invisible passives tissue.
	for id in ["metabolism","catalysis"]:
		if int(organs.get(id,0))<=0:continue
		var col=_organ_color(id,Color("b3ee8b") if id=="metabolism" else Color("ffc383"),appearance)
		for i in range(2):
			var a=phase+(0.7 if id=="metabolism" else 3.6)+i*0.6
			var root=p+_anchor(contour,a)*radius*0.22
			var end=p+_anchor(contour,a+0.35)*radius*0.70
			var flow=PackedVector2Array([root,root.lerp(end,0.5)+Vector2(0,sin(time*2+i)*radius*0.07),end])
			canvas.draw_polyline(flow,Color(body.lerp(col,0.4),0.45),radius*0.09,true)
			canvas.draw_polyline(flow,Color(col,0.65),maxf(0.8,radius*0.018),true)
			canvas.draw_circle(root.lerp(end,fposmod(time*0.4+i*0.4,1.0)),radius*0.025,Color(col.lightened(0.3),0.8))
	# Each rare organ owns a short patch of perfused membrane, in a stable catalog slot.
	var ids=Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys()
	for index in range(ids.size()):
		var id=ids[index]
		if int(organs.get(id,0))<=0:continue
		var grade=int(appearance.get("qualities",{}).get(id,0))
		var evolved=bool(appearance.get("evolved",{}).get(id,false))
		if grade<=0 and not evolved:continue
		var col=Rewards.quality_color(grade) if grade>0 else edge
		var a=phase+index*TAU/ids.size()
		var points=PackedVector2Array()
		var anchor_index=contour.find(_anchor(contour,a))
		for j in range(7):points.append(p+contour[posmod(anchor_index+j-3,contour.size())]*radius*(0.89+sin(j*0.5+time*2)*0.012))
		canvas.draw_polyline(points,Color(col,0.22),radius*0.085,true)
		canvas.draw_polyline(points,Color(col.lightened(0.2),0.65+0.20*sin(time*2+index)),maxf(1.0,radius*0.025),true)
		if evolved:
			for j in range(points.size()):points[j]=p+(points[j]-p)*0.92
			canvas.draw_polyline(points,Color(col,0.85),maxf(0.8,radius*0.018),true)

func _evolved_organs(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,organs: Dictionary,time: float,phase: float,body: Color,edge: Color,appearance: Dictionary):
	var evolved=appearance.get("evolved",{})
	if evolved.get("tentacle",false):
		var growing=float(appearance.get("growth",{}).get("tentacle",1.0))
		var col=_organ_color("tentacle",edge,appearance)
		# Thick perfused collar joins every tentacle root to the membrane.
		var collar=_transform(contour,p,radius*0.92);collar.append(collar[0])
		canvas.draw_polyline(collar,Color(body.lerp(col,0.30),0.58),maxf(0.1,radius*0.13*growing),true)
		canvas.draw_polyline(collar,Color(col,0.65),maxf(1,radius*0.023),true)
		for i in range(Catalog.tentacle_count(int(organs.get("tentacle",0)))):
			var a=phase+i*TAU/Catalog.tentacle_count(int(organs.tentacle))
			var root=p+_anchor(contour,a)*radius*0.90
			var direction=(root-p).normalized()
			for side in [-1,1]:
				var end=root+direction.rotated(side*0.45)*radius*(0.23+sin(time*2+i)*0.025)*growing
				canvas.draw_line(root,end,Color(col,0.7),maxf(1,radius*0.028),true)
			var strike=appearance.get("lashes",{}).get(i,{})
			if int(organs.get("infection",0))>0 and strike.has("tip"):
				var q=root.lerp(p+Vector2(strike.tip),float(strike.get("extension",0)))
				_soft_tissue(canvas,q,radius*0.055,Color("e4a4d1",0.65),time+i)
	if evolved.get("acid",false):
		var contraction=float(appearance.get("mantle_flash",0))
		var growing=float(appearance.get("growth",{}).get("acid",1.0))
		var col=_organ_color("acid",body.lerp(Color("c3e97e"),0.5),appearance)
		for i in range(6):
			var fold=PackedVector2Array()
			for j in range(9):
				var a=phase+i*TAU/6+(j/8.0-0.5)*0.48
				fold.append(p+_anchor(contour,a)*radius*(0.83+sin(j/8.0*PI)*(0.08-contraction*0.055)))
			canvas.draw_polyline(fold,Color(col.darkened(0.4),0.75),maxf(0.1,radius*0.10*growing),true)
			canvas.draw_polyline(fold,Color(col.lightened(0.15),0.65),radius*0.028,true)
	if evolved.get("infection",false):
		var charge=clampi(int(appearance.get("spore_charge",0)),0,2)
		var growing=float(appearance.get("growth",{}).get("infection",1.0))
		var col=_organ_color("infection",Color("d990c6"),appearance)
		for i in range(3):
			var a=phase+0.6+i*TAU/3
			var q=p+_anchor(contour,a)*radius*0.68
			var fullness=1.0 if i<charge else 0.65
			var r=maxf(0.1,radius*(0.25+0.035*sin(time*2.8+i))*fullness*growing)
			canvas.draw_line(p+(q-p)*0.22,q,Color(col,0.4),radius*0.045,true)
			_vesicle(canvas,q,r,body.lerp(col,fullness*0.75),true)
			if i<charge:_soft_tissue(canvas,q,r*0.35,Color(col.lightened(0.45),0.8),time+i)

func _hereditary_marks(canvas: CanvasItem,p: Vector2,contour: PackedVector2Array,radius: float,time: float,phase: float,body: Color,edge: Color,traits: Array):
	if "sensory" in traits:
		for i in range(6):_tendril(canvas,p,contour,radius,phase+i*TAU/6,time+i,0.20+sin(time*2+i)*0.035,edge.lerp(Color("c5e3f3"),0.5),1.2)
	if "folds" in traits:
		for i in range(3):
			var a=phase+i*TAU/3
			var points=PackedVector2Array()
			for j in range(9):points.append(p+_anchor(contour,a+j*0.04)*radius*(0.50+sin(j*0.5+time*1.8)*0.08))
			canvas.draw_polyline(points,Color(body.darkened(0.5),0.55),radius*0.06,true)
			canvas.draw_polyline(points,Color(edge,0.42),radius*0.02,true)
	if "receptive" in traits:
		for i in range(3):
			var a=phase+i*2.1;var q=p+_anchor(contour,a)*radius*0.55
			canvas.draw_line(p,q,Color("c4abe7",0.35),1.2,true)
			_soft_tissue(canvas,q,radius*(0.075+sin(time*2+i)*0.012),Color("dcabe6",0.55),time+i)
