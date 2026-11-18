extends RefCounted
## Small reusable texture masks replace tessellating concentric strokes every frame.
static var masks: Array[ImageTexture] = []
const RING := 0
const LOBES := 1
const THORNS := 2
const SHIELD := 3
const PLUME := 4

static func _mask(shape: int) -> ImageTexture:
	if masks.is_empty():masks.resize(5)
	if masks[shape] != null:return masks[shape]
	var image = Image.create_empty(128,128,false,Image.FORMAT_RGBA8)
	for y in range(128):
		for x in range(128):
			var point = (Vector2(x,y) - Vector2.ONE*63.5)/57.0
			var length = point.length()
			var angle = point.angle()
			var distance = absf(length-0.95)
			var strength = 1.0
			match shape:
				LOBES:distance = absf(length-0.84-0.10*sin(angle*5.0))
				THORNS:distance = absf(length-0.83-0.12*pow(0.5+0.5*cos(angle*8.0),3.0))
				SHIELD:
					var edge = 0.02*sin(angle*4.0)
					distance = minf(absf(length-0.94-edge),absf(length-0.76-edge))
				PLUME:
					distance = absf(length-0.80-0.13*sin(angle*3.0))
					strength = smoothstep(-0.8,0.25,cos(angle))
			var alpha = (0.78*(1.0-smoothstep(0.012,0.032,distance))+0.20*(1.0-smoothstep(0.02,0.085,distance)))*strength
			image.set_pixel(x,y,Color(1,1,1,alpha))
	masks[shape] = ImageTexture.create_from_image(image)
	return masks[shape]

static func wave(canvas: CanvasItem, center: Vector2, radius: float, color: Color, shape: int = RING):
	var extent = Vector2.ONE * maxf(1.0,radius*1.18)
	canvas.draw_texture_rect(_mask(shape),Rect2(center-extent,extent*2.0),false,color)

static func link(canvas: CanvasItem, start: Vector2, end: Vector2, color: Color, time: float, width: float):
	var normal = (end-start).normalized().orthogonal()
	var points = PackedVector2Array([start])
	for i in range(1,5):
		var u = i/5.0
		points.append(start.lerp(end,u)+normal*sin(u*PI)*sin(time*4.0+u*9.0)*6.0)
	points.append(end)
	canvas.draw_polyline(points,color,width)

static func synergy(canvas: CanvasItem, kind: String, p: Vector2, end: Vector2, radius: float, t: float, color: Color, time: float, clones: Array, camera: Vector2, center: Vector2):
	var reach = maxf(8.0,radius)
	match kind:
		"shield_pulse":
			wave(canvas,p,reach*(0.82+t*0.34),color,SHIELD)
		"spike_pulse":
			wave(canvas,p,reach*(0.35+t*0.90),color,THORNS)
		"spore_feast":
			wave(canvas,p,reach*(0.92-t*0.63),color,LOBES)
		"ferment_cloud":
			wave(canvas,p.lerp(end,0.4),reach*(0.44+t*0.52),color,PLUME)
		"toxic_colony","metabolic_colony":
			if clones.is_empty():
				wave(canvas,p,reach*(0.40+t*0.37),color,LOBES)
			for i in range(mini(3,clones.size())):
				var q = clones[i]-camera+center
				wave(canvas,q,reach*(0.35+t*0.40),color,LOBES)
				if kind=="metabolic_colony":link(canvas,p,q,color,time+i,1.5)
		"enzyme_bite":
			var q = end if p.distance_squared_to(end)>1.0 else p
			for side in [-1,1]:
				canvas.draw_arc(q,reach*(0.26+t*0.16),(q-p).angle()+side*0.7,1.5+(q-p).angle()+side*0.7,8,color,2.8)
		"barbed_cilia":
			var direction = (end-p).normalized()
			for i in range(-2,3):
				link(canvas,p,p+direction.rotated(i*0.16)*reach*(0.55+t*0.22),color,time+i,1.6)
		_:
			link(canvas,p,end,color,time,2.8)
			wave(canvas,end,reach*(0.27+t*0.34),color,THORNS if kind=="conductive_bath" else LOBES)
