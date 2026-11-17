extends Control
# Cosmetic roll only. Saved Simulation.reward_options remain the sole outcome.
signal finished
const Catalog=preload("res://core/catalog.gd")
const Rewards=preload("res://core/rewards.gd")
const Art=preload("res://ui/organ_art.gd")
const Cyst=preload("res://game/reward_art.gd")
var tier=1
var options: Array=[]
var age=0.0
var complete=false
var icons: Array=[]
var caption: Label
var skip_button: Button
var _last_step=-1
var frames: Array=[]
const DURATION=2.6
func _ready():
	custom_minimum_size=Vector2(0,390)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	frames=[_frame(Rewards.quality_color(tier),false),_frame(Rewards.quality_color(tier),true)]
	for i in range(5):
		var icon=Art.new();icon.custom_minimum_size=Vector2(88,82);icon.size=Vector2(88,82)
		add_child(icon);icons.append(icon)
	caption=Label.new();caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",25);caption.add_theme_color_override("font_color",Rewards.quality_color(tier))
	add_child(caption)
	skip_button=Button.new();skip_button.text="Раскрыть сразу";skip_button.custom_minimum_size=Vector2(250,54)
	skip_button.pressed.connect(skip);add_child(skip_button)
	advance(0)
func _process(dt):advance(dt)
func advance(dt: float):
	if complete:return
	age=minf(DURATION,age+maxf(0,dt))
	var step=int(24.0*(1.0-pow(1.0-age/DURATION,2.4)))
	if step!=_last_step:
		_last_step=step
		var pool=Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys()
		for i in range(icons.size()):
			icons[i].organ_id=pool[posmod(step*7+i*3+tier,pool.size())]
			icons[i].quality=tier;icons[i].queue_redraw()
	queue_redraw()
	if age>=DURATION:skip()
func skip():
	if complete:return
	complete=true;age=DURATION;set_process(false)
	finished.emit()
func _draw():
	if caption==null:return
	var center=Vector2(size.x/2,120)
	var tint=Rewards.quality_color(tier)
	var opening=smoothstep(0.9,1.9,age)
	var burst=maxf(0,1-absf(age-1.75)/0.6)
	for layer in range(3):draw_circle(center,48+layer*24+opening*32,Color(tint,(0.05+burst*0.08)*(1-layer*0.20)))
	for i in range(12):
		var a=i*TAU/12+age*0.15
		var r=35+opening*40
		draw_line(center+Vector2.from_angle(a)*r,center+Vector2.from_angle(a)*(r+18+burst*20),Color(tint,0.18+burst*0.45),2,true)
	# Split membrane lobes reveal a bright organic nucleus.
	for side in [-1,1]:
		draw_set_transform(center+Vector2(side*opening*32,0),side*opening*0.35,Vector2.ONE*2.0)
		var shell=Cyst.shell(tier,17,age,side)
		if shell.size()>2:
			draw_colored_polygon(shell,Color(tint.darkened(0.35),0.7))
			shell.append(shell[0]);draw_polyline(shell,Color(tint,0.9),1.5,true)
	draw_set_transform(Vector2.ZERO)
	draw_circle(center,12+opening*12,Color(tint.lightened(0.5),0.8))
	var strip_y=233.0
	for i in range(icons.size()):
		var x=size.x/2+(i-2)*112-44
		icons[i].position=Vector2(x,strip_y)
		icons[i].modulate=Color(1,1,1,1.0 if i==2 else 0.35)
		draw_style_box(frames[1 if i==2 else 0],Rect2(x-5,strip_y-5,98,92))
	caption.position=Vector2(0,184);caption.size=Vector2(size.x,36)
	caption.text=["Редкая циста","Эпическая циста","Легендарная циста"][clampi(tier,1,3)-1]+(" · мембрана раскрывается" if age<1.7 else " · мутации сформированы")
	skip_button.position=Vector2(size.x/2-125,332);skip_button.size=Vector2(250,54)
func _frame(color: Color,selected: bool) -> StyleBoxFlat:
	var frame=StyleBoxFlat.new();frame.bg_color=Color(color,0.06)
	frame.border_color=Color(color,0.85 if selected else 0.18);frame.set_border_width_all(2 if selected else 1);frame.set_corner_radius_all(12)
	return frame
