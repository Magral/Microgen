extends Control
# Small illustrations are drawn in code, keeping cards crisp and lightweight.
const Catalog = preload("res://core/catalog.gd")
const Painter = preload("res://game/organism_painter.gd")
var organ_id = ""
var quality=0
var animation_time=0.0
var sim
var painter
func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
func _process(dt):
	animation_time+=dt
	if is_visible_in_tree():queue_redraw()
func _draw():
	var center = size/2
	if sim!=null:
		if painter==null: painter=Painter.new()
		var organs=sim.build.organs.duplicate()
		organs.merge(sim.build.adaptations)
		painter.paint(self,center,minf(57,minf(size.x,size.y)*0.24),sim.player_genome,organs,animation_time,"player",true,null,[],sim.body_color(),0.0,sim.hp/sim.max_hp,0.15+0.15*sin(animation_time*2),{"qualities":sim.build.qualities,"evolved":sim.build.stats.evolutions,"spore_charge":sim.spore_charge,"hereditary_traits":sim.inherited_traits})
		return
	var color=Color(Catalog.item(organ_id).get("color","9ce3cf"))
	if quality>0:color=color.lerp(preload("res://core/rewards.gd").quality_color(quality),0.55)
	var radius=minf(size.x,size.y)*0.28
	draw_circle(center,radius*1.2,Color(color,0.10))
	draw_circle(center,radius,Color(color,0.25))
	draw_arc(center,radius,0,TAU,32,color,2,true)
	match organ_id:
		"tentacle", "speed", "cilia":
			for i in range(7 if organ_id=="cilia" else 4):
				var angle=i*TAU/(7 if organ_id=="cilia" else 4)
				var points=PackedVector2Array()
				for j in range(10):
					var p=center+Vector2.from_angle(angle)*(radius+j*2)+Vector2.from_angle(angle+PI/2)*sin(j*0.65+animation_time*2.2)*5
					points.append(p)
				draw_polyline(points,color,2 if organ_id=="cilia" else 3,true)
		"spikes":
			for i in range(8):
				var angle=i*TAU/8
				var p=center+Vector2.from_angle(angle)*radius
				draw_colored_polygon(PackedVector2Array([p+Vector2.from_angle(angle+PI/2)*4,center+Vector2.from_angle(angle)*radius*1.8,p-Vector2.from_angle(angle+PI/2)*4]),color)
		"pulse", "barrier", "armor":
			draw_arc(center,radius*1.35,0,TAU,40,color,4 if organ_id=="armor" else 2,true)
			if organ_id=="pulse": draw_arc(center,radius*1.7,0,TAU,40,Color(color,0.5),2,true)
			if organ_id=="barrier": draw_arc(center,radius*1.7,-1.1,1.1,24,color,5,true)
		"division":
			for i in range(3):
				var p=center+Vector2.from_angle(i*TAU/3)*radius*1.5
				draw_circle(p,8,Color(color,0.5))
				draw_circle(p,3,color)
		"devour":
			draw_arc(center+Vector2(radius*0.6,0),radius*0.85,-1.5,1.5,20,color,4,true)
			for i in range(5):
				var p=center+Vector2(radius,(-2+i)*6)
				draw_line(p,p+Vector2(-8,0),color,2,true)
		"electric", "catalysis":
			draw_polyline(PackedVector2Array([center+Vector2(-7,-26),center+Vector2(10,-5),center+Vector2(-9,3),center+Vector2(9,26)]),color,4,true)
		"regen":
			draw_line(center+Vector2(-13,0),center+Vector2(13,0),color,6,true)
			draw_line(center+Vector2(0,-13),center+Vector2(0,13),color,6,true)
		"magnet":
			for i in range(6):
				var angle=i*TAU/6
				var p=center+Vector2.from_angle(angle)*radius*1.6
				draw_line(center+Vector2.from_angle(angle)*radius,p,color,2,true)
				draw_circle(p,4,color)
		_:
			for i in range(6):
				var p=center+Vector2.from_angle(i*TAU/6)*radius*(1.5 if organ_id=="trail" else 0.65)
				if organ_id=="trail": p.x-=i*3
				draw_circle(p,4+i%3,Color(color,0.8))
	if organ_id not in ["electric","catalysis","regen"]: draw_circle(center+Vector2(-3,2),radius*0.25,color)
