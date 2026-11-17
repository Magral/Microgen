extends RefCounted
# Bounded immediate-mode artwork: at most 15 draw calls per cyst.
static func color(tier: int) -> Color:
	return [Color("62f2ee"),Color("c28aff"),Color("ffdb72")][clampi(tier,1,3)-1]

static func contour(tier: int,radius: float,time: float,phase: float) -> PackedVector2Array:
	var points=PackedVector2Array()
	for i in range(36):
		var a=i*TAU/36.0
		var shape=1.0
		if tier==1:shape=1.0+0.22*cos(a*2)+0.08*sin(a*3)
		elif tier==2:shape=1.0+0.23*cos(a*3)
		else:shape=1.0+0.20*cos(a*6)
		points.append(Vector2.from_angle(a)*radius*(shape+sin(time*2.0+phase+a*2)*0.035))
	return points

static func paint(canvas: CanvasItem,p: Vector2,tier: int,time: float,id: int,progress: float=0.0):
	var tint=color(tier)
	var dissolve=smoothstep(0.6,1.0,progress)
	var radius=(12.0+tier*3.0)*lerpf(1.0,0.12,dissolve)
	var alpha=1.0-dissolve
	var pulse=1.0+sin(time*2.3+id)*0.045
	var points=contour(tier,radius*pulse,time,float(id))
	var outer=Transform2D(0,Vector2.ONE,0,p)*points
	canvas.draw_circle(p,radius*1.8,Color(tint,0.045*alpha))
	canvas.draw_colored_polygon(outer,Color(tint,0.22*alpha))
	outer.append(outer[0])
	canvas.draw_polyline(outer,Color(tint,0.92*alpha),1.8,true)
	var inner=Transform2D(0,Vector2.ONE*0.75,0,p)*points
	inner.append(inner[0])
	canvas.draw_polyline(inner,Color(tint.lightened(0.3),0.30*alpha),1.0,true)
	var nucleus=p+Vector2(sin(time+id),cos(time*0.8+id))*radius*0.12
	canvas.draw_circle(nucleus,radius*0.43,Color(tint.darkened(0.4),0.9*alpha))
	canvas.draw_circle(nucleus,radius*0.28,Color(tint.lightened(0.2),0.88*alpha))
	canvas.draw_arc(nucleus,radius*0.48,PI*1.05,PI*1.8,12,Color("f1ffef",0.75*alpha),1.4,true)
	for i in range(tier+1):
		var q=p+Vector2.from_angle(i*TAU/(tier+1)+id*0.3+time*0.12)*radius*0.64
		canvas.draw_circle(q,1.5,Color(tint.lightened(0.5),0.85*alpha))
	if progress>0:
		canvas.draw_arc(p,radius*1.35,-PI/2,-PI/2+TAU*progress,24,Color(tint,0.7*alpha),1.5,true)

static func marker(canvas: CanvasItem,p: Vector2,tier: int,alpha: float=1.0,radius: float=4.0):
	var points=Transform2D(0,Vector2.ONE,0,p)*contour(tier,radius,0,0)
	canvas.draw_colored_polygon(points,Color(color(tier),alpha))
