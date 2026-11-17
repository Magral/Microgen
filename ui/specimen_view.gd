extends Control
const Catalog = preload("res://core/catalog.gd")
var painter
var recipe: Dictionary
var organs: Dictionary
var number = 0
var time = 0.0

func _process(dt):
	time += dt
	queue_redraw()

func _draw():
	if painter==null or recipe.is_empty(): return
	var style = StyleBoxFlat.new()
	style.bg_color = Color("0b2431")
	style.border_color = Color("2c4a57")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	draw_style_box(style,Rect2(Vector2.ZERO,size))
	painter.paint(self,Vector2(size.x/2,88),46,recipe,organs,time,"specimen",true)
	var font = ThemeDB.fallback_font
	draw_string(font,Vector2(15,24),"%02d" % number,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("95aaa9"))
	var names = []
	for id in organs:
		if id in Catalog.ORGANS: names.append(Catalog.item(id).name)
	draw_string(font,Vector2(12,161)," + ".join(names.slice(0,2)),HORIZONTAL_ALIGNMENT_LEFT,size.x-24,13,Color("b4d1ca"))
	if names.size()>2: draw_string(font,Vector2(12,179)," + ".join(names.slice(2)),HORIZONTAL_ALIGNMENT_LEFT,size.x-24,13,Color("b4d1ca"))
