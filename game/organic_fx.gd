extends RefCounted
const Genome=preload("res://core/genome.gd")

# One signature per synergy, with bounded silhouettes rather than particle spam.
const SYNERGY_STYLES={
	"acid_grasp":{"form":"constricting_vines","color":Color("b9f27b"),"budget":20},
	"spike_pulse":{"form":"thorn_wave","color":Color("90d4f2"),"budget":20},
	"toxic_colony":{"form":"rooted_poison_lobes","color":Color("a9db69"),"budget":24},
	"spore_feast":{"form":"inward_spore_petals","color":Color("e1a1ee"),"budget":24},
	"enzyme_bite":{"form":"folding_amber_jaws","color":Color("ffcf84"),"budget":12},
	"conductive_bath":{"form":"branching_ion_paths","color":Color("8ef4ef"),"budget":23},
	"barbed_cilia":{"form":"sweeping_barbed_comb","color":Color("a7efbf"),"budget":23},
	"shield_pulse":{"form":"layered_membrane_corona","color":Color("a4bfff"),"budget":18},
	"metabolic_colony":{"form":"pumping_vascular_roots","color":Color("f4b992"),"budget":24},
	"ferment_cloud":{"form":"curling_ferment_plumes","color":Color("e4bd77"),"budget":24}
}

static var _infection_cache: Dictionary={}
static var _field_basis: PackedVector2Array=_make_field_basis()

static func _infection_contour(recipe: Dictionary) -> PackedVector2Array:
	var key=hash(recipe)
	if _infection_cache.has(key): return _infection_cache[key]
	if _infection_cache.size()>=192: _infection_cache.erase(_infection_cache.keys()[0])
	var contour=Genome.contour(recipe,24)
	_infection_cache[key]=contour
	return contour

static func _make_field_basis() -> PackedVector2Array:
	var points=PackedVector2Array()
	points.resize(21)
	for i in range(21):
		var a=i*TAU/20.0
		points[i]=Vector2.from_angle(a)*(0.86+sin(a*3)*0.10+cos(a*5)*0.04)
	return points

static func _thread(canvas: CanvasItem,a: Vector2,b: Vector2,color: Color,time: float,width: float=1.5,bend: float=10.0):
	var points=PackedVector2Array()
	var normal=(b-a).normalized().orthogonal()
	for i in range(19):
		var t=i/18.0
		points.append(a.lerp(b,t)+normal*sin(t*PI)*sin(t*7+time*3)*bend)
	canvas.draw_polyline(points,Color(color,color.a*0.15),width*4,true)
	canvas.draw_polyline(points,color,width,true)
	canvas.draw_polyline(points,Color(color.lightened(0.4),color.a*0.6),maxf(0.6,width*0.3),true)

static func infected(canvas: CanvasItem,p: Vector2,radius: float,recipe: Dictionary,time: float,remaining: float,motion=null):
	var contour=_infection_contour(recipe)
	if motion!=null: contour=motion.deform_points(contour,float(recipe.phase))
	var growth=clampf((4.5-remaining)*1.8,0.12,1.0)
	# Three thick vascular stems, each with one fork and a living spore head.
	# 18 primitives replace 63; cached anatomy still follows this exact host.
	for i in range(3):
		var a=contour[(i*8+2)%contour.size()]*radius*0.78*growth
		var color=Color("eda0d6",0.66+0.10*sin(time*3+i))
		_thread(canvas,p-a*0.12,p+a,color,time+i,maxf(1.1,radius*0.032),radius*0.10)
		var middle=p+a*0.53
		var fork=middle+a.orthogonal()*0.30+a*0.18
		canvas.draw_polyline(PackedVector2Array([middle,fork,middle+a*0.43]),Color("f6b9e3",0.58),maxf(0.9,radius*0.020),true)
		var head=maxf(1.6,radius*(0.065+0.012*sin(time*4+i)))
		canvas.draw_circle(p+a,head,Color("d877bd",0.44))
		canvas.draw_arc(p+a,head,0.2,5.8,9,Color("ffd1eb",0.76),1.0,true)

static func field(canvas: CanvasItem,p: Vector2,radius: float,kind: String,life: float,maximum: float,time: float):
	var color=Color("e499b6") if kind.begins_with("enemy") else (Color("dfa3ec") if kind=="spore" else Color("b2dd75"))
	var alpha=minf(1.0,life/0.5)*0.55
	var age=maximum-life
	# Two translucent breathing membranes read as a real organic field. Cached
	# lobed geometry removes 57 thread samples and reduces 18 calls to four.
	for layer in range(2):
		var scale_value=radius*(0.64+layer*0.23+sin(time*1.2+layer+age)*0.035)
		var transform=Transform2D(time*0.08+layer*1.7,Vector2(1.0,0.84+layer*0.08)*scale_value,0,p)
		var points=transform*_field_basis
		canvas.draw_polyline(points,Color(color,alpha*0.10),5.5,true)
		canvas.draw_polyline(points,Color(color,alpha*(0.65-layer*0.20)),1.6+layer*0.6,true)

static func paint(canvas: CanvasItem,effect: Dictionary,camera: Vector2,center: Vector2,time: float,clones: Array=[]) -> bool:
	var kind=str(effect.type)
	if kind not in SYNERGY_STYLES and kind not in ["electric","enzymes","cilia","bite","infection","assimilate","mutation"]: return false
	var p=effect.pos-camera+center
	var t=clampf(1.0-float(effect.life)/float(effect.max),0.0,1.0)
	var alpha=pow(sin(PI*t),0.65)
	var radius=float(effect.r)
	if kind in SYNERGY_STYLES:
		_synergy(canvas,kind,p,effect.get("end",effect.pos)-camera+center,radius,t,alpha,time,clones,camera,center)
	elif kind in ["electric","enzymes","cilia"]:
		var end=effect.get("end",effect.pos)-camera+center
		var color=Color("a6e5ef") if kind=="electric" else (Color("ebc787") if kind=="enzymes" else Color("b1e8c9"))
		_thread(canvas,p,end,Color(color,alpha*0.75),time,1.2 if kind=="electric" else 2.1,7)
		if kind=="cilia":
			var direction=(end-p).normalized()
			for side in [-1,1]:_thread(canvas,p,p+direction.rotated(side*0.5)*radius,Color(color,alpha*0.35),time+side,1.1,5)
	elif kind=="bite":
		var end=effect.get("end",effect.pos)-camera+center
		for i in range(5):
			var a=i*2.399
			var q=p.lerp(end,0.3)+Vector2.from_angle(a)*radius*t
			canvas.draw_circle(q,1.2*(1-t)+0.4,Color("d7dfbb",alpha*0.55))
	elif kind=="infection":
		var end=effect.get("end",effect.pos)-camera+center
		var color=Color("eba6da")
		var normal=(end-p).normalized().orthogonal()
		for i in range(3):
			var spread=(i-1)*5.0
			var start=p+normal*spread
			var finish=p.lerp(end,smoothstep(0.0,0.55,t))
			_thread(canvas,start,finish+normal*spread,Color(color,alpha*0.65),time+i,1.6,7.0)
			for j in range(5):
				var u=fposmod(t*1.6+j/5.0,1.0)
				var q=start.lerp(finish,u)+normal*sin(u*PI*3+time*4)*3
				canvas.draw_circle(q,1.5,Color(color.lightened(0.3),alpha*0.8))
	elif kind=="assimilate" or kind=="mutation":
		# Tissue response stays attached to the organism while it swims.
		p=center
		var color: Color=effect.get("color",Color("d3b7f0"))
		for i in range(12):
			var a=i*2.399+time*0.15
			var q=p+Vector2.from_angle(a)*radius*(0.15+0.55*t)
			canvas.draw_circle(q,2.0*(1-t)+0.5,Color(color.lightened(0.3),alpha*0.55))
			if i%3==0: _thread(canvas,p+Vector2.from_angle(a)*radius*0.15,q,Color(color,alpha*0.3),time+i,0.8,3)
	return true

# Two transparent strokes leave the cell anatomy visible through every wave.
static func _wave(canvas: CanvasItem,p: Vector2,radius: float,start: float,sweep: float,color: Color,width: float,phase: float,lobes: float=3.0):
	var points=PackedVector2Array()
	points.resize(33)
	for i in range(33):
		var u=i/32.0
		var a=start+sweep*u
		var ripple=1.0+sin(a*lobes+phase)*0.065+sin(a*5.0-phase)*0.025
		points[i]=p+Vector2.from_angle(a)*radius*ripple
	canvas.draw_polyline(points,Color(color,color.a*0.16),width*3.3,true)
	canvas.draw_polyline(points,color,width,true)

static func _petal(canvas: CanvasItem,root: Vector2,tip: Vector2,width: float,color: Color,phase: float):
	var normal=(tip-root).normalized().orthogonal()
	var points=PackedVector2Array()
	points.resize(17)
	for i in range(17):
		var u=i/16.0
		points[i]=root.lerp(tip,u)+normal*sin(u*PI)*width*(0.8+0.2*sin(u*TAU+phase))
	canvas.draw_polyline(points,Color(color,color.a*0.18),maxf(3.0,absf(width)*0.42),true)
	canvas.draw_polyline(points,color,2.2,true)

static func _synergy(canvas: CanvasItem,kind: String,p: Vector2,end: Vector2,radius: float,t: float,alpha: float,time: float,clones: Array,camera: Vector2,center: Vector2):
	var color: Color=SYNERGY_STYLES[kind].color
	color.a=alpha*0.88
	var r=maxf(22.0,radius)
	var heading=(end-p).angle() if end.distance_squared_to(p)>1.0 else time*0.12
	match kind:
		"acid_grasp":
			var normal=Vector2.from_angle(heading).orthogonal()
			for side in [-1,1]:
				var root=p+normal*side*r*0.15
				var tip=end+normal*side*r*0.19*(1.0-t)
				_thread(canvas,root,tip,color,time+side,3.4,r*0.19)
				_petal(canvas,tip,end+Vector2.from_angle(heading)*r*0.17,side*r*0.27,color,time)
			_wave(canvas,end,r*(0.23+0.30*t),time,TAU*0.88,Color(color,alpha*0.58),2.4,time,5.0)
		"spike_pulse":
			var reach=r*(0.35+t*0.9)
			_wave(canvas,p,reach,0.0,TAU,color,3.0,-time*3,8.0)
			for i in range(8):
				var direction=Vector2.from_angle(i*TAU/8+0.09*sin(time))
				var root=p+direction*reach*0.94
				_petal(canvas,root,p+direction*(reach+r*0.26*(1.0-t)),r*0.055,color,float(i))
		"toxic_colony","metabolic_colony":
			var count=mini(3,clones.size())
			# An absent clone still has a localized living halo at its source.
			for i in range(maxi(1,count)):
				var q=clones[i]-camera+center if count>0 else p
				if q.distance_squared_to(p)>4.0:
					_thread(canvas,p,q,Color(color,alpha*0.6),time+i,3.0,14.0)
				if kind=="toxic_colony":
					_wave(canvas,q,r*(0.33+t*0.38),0.0,TAU,color,3.2,time+i,5.0)
					_wave(canvas,q,r*(0.4+t*0.4),0.4,PI*1.3,Color(color,alpha*0.42),1.5,-time,3.0)
				else:
					var beat=sin(t*PI*3+i)*0.10
					_wave(canvas,q,r*(0.35+beat),0.0,TAU,color,3.6,time,3.0)
					_petal(canvas,q+Vector2(-r*0.33,0),q+Vector2(r*0.33,0),r*(0.3+beat),Color(color,alpha*0.65),time)
		"spore_feast":
			# Six broad seed husks curl inward: visibly different from an outward pulse.
			for i in range(6):
				var a=i*TAU/6+time*0.18
				var direction=Vector2.from_angle(a)
				var root=p+direction*r*(0.95-0.56*t)
				var tip=p+direction.rotated(0.48)*r*(0.35-0.20*t)
				_petal(canvas,root,tip,r*0.22,color,time+i)
				_wave(canvas,root,r*0.09*(1.0-t*0.6),a,TAU*0.78,Color(color,alpha*0.72),2.0,time,2.0)
		"enzyme_bite":
			var q=end if p.distance_squared_to(end)>1.0 else p
			for side in [-1,1]:
				var a=heading+side*(0.65+0.48*(1.0-t))
				_wave(canvas,q,r*(0.35+0.10*sin(t*PI)),a,side*1.65,color,4.6,time,2.0)
				var root=q+Vector2.from_angle(a)*r*0.44
				_petal(canvas,root,q+Vector2.from_angle(heading)*r*0.12,side*r*0.30,color,time)
			_wave(canvas,q,r*(0.22+t*0.35),heading+PI*0.5,PI,Color(color,alpha*0.48),2.1,time)
		"conductive_bath":
			var tip=end if p.distance_squared_to(end)>4.0 else p+Vector2.from_angle(heading)*r*0.8
			_thread(canvas,p,tip,color,time*2.0,3.0,10.0)
			for i in range(4):
				var junction=p.lerp(tip,0.2+i*0.18)
				var direction=Vector2.from_angle(heading+(-1.0 if i%2==0 else 1.0))
				_thread(canvas,junction,junction+direction*r*0.36,Color(color,alpha*0.68),time+i,1.8,5.0)
			_wave(canvas,tip,r*(0.28+0.42*t),0.0,TAU,Color(color,alpha*0.63),2.5,time*3,5.0)
		"barbed_cilia":
			var facing=Vector2.from_angle(heading)
			var normal=facing.orthogonal()
			for i in range(5):
				var spread=(i-2)*r*0.18
				var root=p+normal*spread
				var tip=root+facing*r*(0.45+0.3*sin(t*PI))+normal*r*0.13*sin(t*PI+i*0.4)
				_thread(canvas,root,tip,color,time+i,2.0,5.0)
				canvas.draw_line(tip,tip-facing*r*0.16+normal*r*0.10,Color(color.lightened(0.3),alpha*0.8),2.0,true)
		"shield_pulse":
			for layer in range(3):
				var reach=r*(0.58+layer*0.13+t*0.35)
				_wave(canvas,p,reach,0.0,TAU,Color(color,alpha*(0.84-layer*0.2)),3.6-layer*0.8,time*0.7+layer,4.0)
			for i in range(4):
				var a=i*TAU/4+time*0.08
				_wave(canvas,p,r*(0.86+t*0.34),a,0.8,Color(color.lightened(0.2),alpha*0.8),3.4,time,4.0)
		"ferment_cloud":
			# Three overlapping open plumes have no opaque interior or smoke disk.
			for i in range(3):
				var a=heading+PI+(i-1)*0.58
				var q=p+Vector2.from_angle(a)*r*(0.3+0.48*t)
				var spread=r*(0.24+0.20*t)
				_wave(canvas,q,spread,a-1.4,PI*1.6,Color(color,alpha*0.70),4.5,time+i,3.0)
				_wave(canvas,q+Vector2.from_angle(a+0.7)*spread*0.4,spread*0.60,a,PI*1.5,Color(color.lightened(0.18),alpha*0.65),2.2,-time+i,2.0)
				_petal(canvas,p+Vector2.from_angle(a)*r*0.12,q,spread*0.65,Color(color,alpha*0.44),time)
