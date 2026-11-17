extends RefCounted
const Genome=preload("res://core/genome.gd")

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
	var contour=Genome.contour(recipe,24)
	if motion!=null: contour=motion.deform_points(contour,float(recipe.phase))
	var growth=clampf((4.5-remaining)*1.8,0.12,1.0)
	for i in range(7):
		var a=contour[(i*3+2)%contour.size()]*radius*0.68*growth
		var middle=a*0.53+a.orthogonal()*0.1
		var color=Color("eca0ce",0.42+0.18*sin(time*3+i))
		_thread(canvas,p,p+middle,color,time+i,0.8,1.8)
		_thread(canvas,p+middle,p+a,color,time+i,0.8,1.2)
		canvas.draw_circle(p+a,radius*(0.045+0.018*sin(time*4+i)),Color("df8ac8",0.85))
		canvas.draw_circle(p+a,radius*0.022,Color("ffd4e4",0.9))
		var dust=p+contour[(i*3)%contour.size()]*radius*(0.8+fposmod(time*0.13+i*0.17,0.5))
		canvas.draw_circle(dust,1.0,Color("d7a3dd",0.3))

static func field(canvas: CanvasItem,p: Vector2,radius: float,kind: String,life: float,maximum: float,time: float):
	var color=Color("e499b6") if kind.begins_with("enemy") else (Color("dfa3ec") if kind=="spore" else Color("b2dd75"))
	var alpha=minf(1.0,life/0.5)*0.45
	for i in range(9):
		var angle=i*2.399+time*0.12
		var distance=radius*(0.25+0.5*fposmod(i*0.31+time*0.07,1.0))
		var q=p+Vector2.from_angle(angle)*distance
		canvas.draw_circle(q,1.2+sin(time*2+i)*0.4,Color(color,alpha))
		if i%3==0: _thread(canvas,q,q+Vector2.from_angle(angle+0.8)*9,Color(color,alpha*0.4),time+i,0.7,2)

static func paint(canvas: CanvasItem,effect: Dictionary,camera: Vector2,center: Vector2,time: float,clones: Array=[]) -> bool:
	var kind=str(effect.type)
	if kind not in ["bite","infection","acid_grasp","spike_pulse","toxic_colony","spore_feast","assimilate","mutation"]: return false
	var p=effect.pos-camera+center
	var t=clampf(1.0-float(effect.life)/float(effect.max),0.0,1.0)
	var alpha=sin(PI*t)
	var radius=float(effect.r)
	if kind=="bite":
		var end=effect.end-camera+center
		for i in range(5):
			var a=i*2.399
			var q=p.lerp(end,0.3)+Vector2.from_angle(a)*radius*t
			canvas.draw_circle(q,1.2*(1-t)+0.4,Color("d7dfbb",alpha*0.55))
	elif kind=="infection" or kind=="acid_grasp":
		var end=effect.end-camera+center
		var color=Color("eba6da") if kind=="infection" else Color("c3ed7d")
		var normal=(end-p).normalized().orthogonal()
		for i in range(3):
			var spread=(i-1)*5.0
			var start=p+normal*spread
			var finish=end if kind=="acid_grasp" else p.lerp(end,smoothstep(0.0,0.55,t))
			_thread(canvas,start,finish+normal*spread,Color(color,alpha*0.65),time+i,1.6,7.0)
			for j in range(5):
				var u=fposmod(t*1.6+j/5.0,1.0)
				var q=start.lerp(finish,u)+normal*sin(u*PI*3+time*4)*3
				canvas.draw_circle(q,1.5,Color(color.lightened(0.3),alpha*0.8))
		if kind=="acid_grasp":
			for i in range(6):
				var q=end+Vector2.from_angle(i*2.399)*radius*t*0.6
				canvas.draw_circle(q,2.0*(1-t),Color(color,alpha))
	elif kind=="spike_pulse":
		var ring=radius*(0.18+t*0.9)
		var points=PackedVector2Array()
		for i in range(65):
			var a=i*TAU/64
			points.append(p+Vector2.from_angle(a)*ring*(1+sin(a*8-time*5)*0.035))
		canvas.draw_polyline(points,Color("81b9e5",alpha*0.1),12,true)
		canvas.draw_polyline(points,Color("c9def3",alpha*0.55),1.7,true)
		for i in range(8):
			var direction=Vector2.from_angle(i*TAU/8)
			var q=p+direction*ring
			var side=direction.orthogonal()*4*(1-t)
			canvas.draw_colored_polygon(PackedVector2Array([q-direction*12-side,q+direction*9,q-direction*12+side]),Color("f2d9ac",alpha))
	elif kind=="toxic_colony":
		for clone in clones:
			var q=clone-camera+center
			_thread(canvas,p,q,Color("a8d986",alpha*0.2),time,1.0,8)
			for i in range(5):
				var a=i*TAU/5+time*0.4
				var bubble=q+Vector2.from_angle(a)*(14+t*18)
				canvas.draw_circle(bubble,3.5*(1-t),Color("b1e495",alpha*0.55))
	elif kind=="spore_feast":
		for i in range(18):
			var a=i*2.399
			var root=p+Vector2.from_angle(a)*radius*0.08
			var q=p+Vector2.from_angle(a+sin(t*3+i)*0.1)*radius*(0.1+t*(0.5+(i%4)*0.1))
			_thread(canvas,root,q,Color("bb84d4",alpha*0.2),time+i,0.7,4)
			canvas.draw_circle(q,2.0+sin(t*PI)*1.3,Color("dda6e3",alpha*0.7))
			canvas.draw_circle(q,0.9,Color("f4d6e8",alpha))
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
