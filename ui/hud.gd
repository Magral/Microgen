extends CanvasLayer
const MiniMap = preload("res://ui/minimap.gd")
const Catalog = preload("res://core/catalog.gd")
var root: Control
var status: VBoxContainer
var hp_bar: ProgressBar
var xp_bar: ProgressBar
var stats: Label
var area_label: Label
var slots: Label
var synergy_label: Label
var minimap: Control
var modal: Control
var content: VBoxContainer
var message: Label
var shop_button: Button
var pause_button: Button
var map_button: Button
var on_pause: Callable
var on_map: Callable
var on_shop: Callable

func _ready():
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = _theme()
	status = VBoxContainer.new()
	status.position = Vector2(28,22)
	status.custom_minimum_size = Vector2(380,0)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	area_label = label("",16,Color("9bbfbb"))
	status.add_child(area_label)
	hp_bar = _bar(Color("78d9bd"),14)
	xp_bar = _bar(Color("ba99e4"),6)
	status.add_child(hp_bar)
	status.add_child(xp_bar)
	stats = label("",18)
	status.add_child(stats)
	minimap = MiniMap.new()
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-220,24)
	minimap.size = Vector2(192,140)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(minimap)
	map_button = button("Карта",func(): on_map.call())
	map_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	map_button.position = Vector2(-220,172)
	map_button.size = Vector2(192,44)
	root.add_child(map_button)
	pause_button = button("Ⅱ  Пауза",func(): on_pause.call())
	pause_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	pause_button.position = Vector2(-220,-74)
	pause_button.size = Vector2(192,50)
	root.add_child(pause_button)
	shop_button = button("Войти в колонию",func(): on_shop.call())
	shop_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	shop_button.position = Vector2(-140,-85)
	shop_button.size = Vector2(280,54)
	root.add_child(shop_button)
	slots = label("",16)
	slots.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	slots.position = Vector2(28,-110)
	root.add_child(slots)
	synergy_label = label("",15,Color("d1b5ef"))
	synergy_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	synergy_label.position = Vector2(28,-43)
	root.add_child(synergy_label)
	message = label("",22,Color("e8d9b5"))
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message.position = Vector2(-330,120)
	message.custom_minimum_size = Vector2(660,0)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(message)

func update_game(sim):
	minimap.sim = sim
	minimap.queue_redraw()
	hp_bar.value = sim.hp/sim.max_hp*100
	xp_bar.value = sim.xp/sim.xp_needed()*100
	area_label.text = ("ПИТАТЕЛЬНАЯ СРЕДА" if sim.world.biome(sim.player)==0 else "ТОКСИЧНАЯ ЗОНА")+"  ·  "+sim.world.condition_name(sim.world.biome(sim.player))
	stats.text = "Ур. %d   ·   %d/%d HP   ·   Биомасса %d   ·   %02d:%02d" % [sim.level,int(sim.hp),int(sim.max_hp),sim.build.biomass,int(sim.elapsed)/60,int(sim.elapsed)%60]
	var names = []
	for id in sim.build.organs: names.append(Catalog.item(id).name+" "+str(sim.build.rank(id)))
	slots.text = "Органы %d/6   ·   Адаптации %d/4\n" % [sim.build.organs.size(),sim.build.adaptations.size()]+"  /  ".join(names)
	var synergies = []
	for id in sim.build.active_synergies(): synergies.append(Catalog.SYNERGIES[id].name)
	synergy_label.text = "СИНЕРГИИ  "+(" + ".join(synergies) if not synergies.is_empty() else "сочетай органы")
	shop_button.visible = sim.nearby_colony()>=0 and modal==null

func game_visible(value: bool):
	for child in root.get_children():
		if child != modal and not child.get_meta("retired",false): child.visible = value
	shop_button.visible = false

func open(title: String,subtitle: String="",width: float=1030) -> VBoxContainer:
	close()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var shade = ColorRect.new()
	shade.color = Color(0.015,0.035,0.05,0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var size = root.get_viewport_rect().size
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(width,size.x-50),minf(620,size.y-44))
	panel.add_theme_stylebox_override("panel",box(Color("0c202b"),Color("2c5159"),22))
	center.add_child(panel)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",15)
	scroll.add_child(content)
	content.add_child(label(title,32,Color("e2f4ed")))
	if subtitle!="": content.add_child(label(subtitle,18,Color("94b5b8"),true))
	return content

func close():
	if is_instance_valid(modal):
		modal.set_meta("retired",true)
		modal.hide()
		modal.queue_free()
	modal = null

func label(text: String,font_size: int=22,color: Color=Color("d4e7e7"),wrap: bool=false) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size",font_size)
	l.add_theme_color_override("font_color",color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func button(text: String,callback: Callable,primary: bool=false) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = 48
	b.focus_mode = Control.FOCUS_NONE
	if primary:
		b.add_theme_stylebox_override("normal",box(Color("72d4b6"),Color("98eed0"),12))
		b.add_theme_color_override("font_color",Color("09272c"))
	b.pressed.connect(callback)
	return b

func row() -> HBoxContainer:
	var r = HBoxContainer.new()
	r.add_theme_constant_override("separation",14)
	return r

func card() -> PanelContainer:
	var p = PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel",box(Color("122e39"),Color("31545d"),16))
	return p

func box(color: Color,border: Color,padding: int=12) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(14)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s

func _bar(color: Color,height: float) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(380,height)
	bar.add_theme_stylebox_override("background",box(Color("193540"),Color("193540"),0))
	bar.add_theme_stylebox_override("fill",box(color,color,0))
	return bar

func _theme() -> Theme:
	var t = Theme.new()
	t.default_font_size = 21
	t.set_stylebox("normal","Button",box(Color("173946"),Color("37616a"),12))
	t.set_stylebox("hover","Button",box(Color("24515b"),Color("78cbb8"),12))
	t.set_stylebox("pressed","Button",box(Color("306255"),Color("9ce5cb"),12))
	t.set_stylebox("disabled","Button",box(Color("162933"),Color("243c46"),12))
	t.set_color("font_color","Button",Color("d6eeea"))
	t.set_color("font_disabled_color","Button",Color("637b82"))
	t.set_color("font_hover_color","Button",Color.WHITE)
	return t
