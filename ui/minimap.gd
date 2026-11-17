extends Control
const World = preload("res://game/world.gd")
var sim
var large = false
var font = ThemeDB.fallback_font
var _world
var _seed=-1
var _explored_count=-1
var _texture: ImageTexture
var rebuilds=0
func _update_texture():
	if _world==sim.world and _seed==sim.world.seed_value and _explored_count==sim.explored.size():return
	_world=sim.world
	_seed=sim.world.seed_value
	_explored_count=sim.explored.size()
	var pixels=Image.create(World.W,World.H,false,Image.FORMAT_RGBA8)
	pixels.fill(Color.TRANSPARENT)
	for idx in sim.explored:
		var x=int(idx)%World.W
		var y=int(int(idx)/World.W)
		var wall=sim.world.cells[int(idx)]==1
		var col=Color("294e54") if wall else (Color("72814c") if sim.world.biome(Vector2(x+0.5,y+0.5)*World.TILE)==1 else Color("477c78"))
		pixels.set_pixel(x,y,col)
	if _texture==null:_texture=ImageTexture.create_from_image(pixels)
	else:_texture.update(pixels)
	rebuilds+=1

func _draw():
	if sim==null: return
	var scale_value = minf(size.x/(World.W*World.TILE),size.y/(World.H*World.TILE))
	var offset = (size-Vector2(World.W,World.H)*World.TILE*scale_value)/2
	draw_style_box(_box(),Rect2(Vector2.ZERO,size))
	_update_texture()
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	draw_texture_rect(_texture,Rect2(offset,Vector2(World.W,World.H)*World.TILE*scale_value),false)
	for shop in sim.world.colonies:
		if shop.visited:
			var p = offset+shop.pos*scale_value
			draw_rect(Rect2(p-Vector2.ONE*3.5,Vector2.ONE*7),Color("99efc6"))
	for nest in sim.world.nests:
		var c = sim.world.tile(nest.pos)
		if c.y*World.W+c.x in sim.explored and not nest.used:
			draw_circle(offset+nest.pos*scale_value,3,Color("ce9bec"))
	if sim.boss_spawned and sim.outcome=="": draw_circle(offset+sim.boss_marker*scale_value,5,Color("f1869a"))
	for enemy in sim.enemies:
		if enemy.kind=="miniboss":draw_circle(offset+enemy.pos*scale_value,4,Color("efc17f"))
	var player = offset+sim.player*scale_value
	draw_circle(player,5 if large else 4,Color("ffffff"))
	draw_arc(player,8,0,TAU,20,Color("96f6dc"),1.5,true)
	if large:
		draw_string(font,Vector2(15,size.y-15),"● Ты    ■ Колония    ● Находка    ● Босс",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("d6e7e5"))

func _box() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = Color("0c202b")
	s.border_color = Color("2a4d55")
	s.set_border_width_all(1)
	s.set_corner_radius_all(12)
	return s
