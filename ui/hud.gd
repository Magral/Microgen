extends CanvasLayer
const MiniMap = preload("res://ui/minimap.gd")
const TouchScroll = preload("res://ui/touch_scroll.gd")
const Catalog = preload("res://core/catalog.gd")
var root: Control
var status: VBoxContainer
var hp_bar: ProgressBar
var xp_bar: ProgressBar
var stats: Label
var damage_source: Label
var pending_button: Button
var on_pending: Callable
var on_close: Callable
var area_label: Label
var minimap: Control
var modal: Control
var scroll_container: ScrollContainer
var content: VBoxContainer
var message: Label
var shop_button: Button
var pause_button: Button
var map_button: Button
var build_button: Button
var on_pause: Callable
var on_map: Callable
var on_shop: Callable
var on_build: Callable

func _ready():
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	root.theme = _theme()
	status = VBoxContainer.new()
	status.position = Vector2(28,22)
	status.custom_minimum_size = Vector2(760,0)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status)
	area_label = label("",20,Color("9bbfbb"))
	status.add_child(area_label)
	hp_bar = _bar(Color("78d9bd"),14)
	xp_bar = _bar(Color("ba99e4"),6)
	status.add_child(hp_bar)
	status.add_child(xp_bar)
	stats = label("",24)
	status.add_child(stats)
	damage_source = label("",20,Color("efb6a9"),true)
	status.add_child(damage_source)
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
	build_button = button("Организм",func(): on_build.call())
	build_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	build_button.position = Vector2(-220,240)
	build_button.size = Vector2(192,54)
	root.add_child(build_button)
	pending_button = button("",func(): on_pending.call(),true)
	pending_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	pending_button.position = Vector2(-220,304)
	pending_button.size = Vector2(192,54)
	pending_button.hide()
	root.add_child(pending_button)
	message = label("",22,Color("e8d9b5"))
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message.position = Vector2(-330,208)
	message.custom_minimum_size = Vector2(660,0)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(message)

func update_game(sim):
	minimap.sim = sim
	minimap.queue_redraw()
	hp_bar.value = sim.hp/sim.max_hp*100
	xp_bar.value = sim.xp/sim.xp_needed()*100
	area_label.text = ("ПИТАТЕЛЬНАЯ СРЕДА" if sim.world.biome(sim.player)==0 else "ТОКСИЧНАЯ ЗОНА")+"  ·  "+sim.world.condition_name(sim.world.biome(sim.player))
	stats.text = "Размер ×%.1f  ·  Ур. %d  ·  %d/%d HP\nБиомасса %d  ·  %02d:%02d" % [sim.body_radius()/22.0,sim.level,int(sim.hp),int(sim.max_hp),sim.build.biomass,int(sim.elapsed)/60,int(sim.elapsed)%60]
	var damage = sim.last_damage
	damage_source.text = "Последний урон: −%.1f HP · %s" % [float(damage.get("amount",0)),damage.get("name","неизвестный источник")] if not damage.is_empty() else ""
	pending_button.text = "Награда · %d" % sim.reward_queue.size() if not sim.reward_queue.is_empty() else "Мутация · %d" % sim.pending_levels
	pending_button.visible = modal==null and (not sim.reward_queue.is_empty() or sim.pending_levels>0)
	shop_button.visible = sim.nearby_colony()>=0 and modal==null

func game_visible(value: bool):
	for child in root.get_children():
		if child != modal and not child.get_meta("retired",false): child.visible = value
	shop_button.visible = false

func open_home() -> VBoxContainer:
	close()
	scroll_container=null
	modal=Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(modal)
	var backdrop=ColorRect.new()
	backdrop.name="Backdrop"
	backdrop.color=Color(0.015,0.035,0.05,0.34)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(backdrop)
	var margin=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right"]:margin.add_theme_constant_override("margin_"+side,40)
	for side in ["top","bottom"]:margin.add_theme_constant_override("margin_"+side,24)
	modal.add_child(margin)
	var center=CenterContainer.new()
	margin.add_child(center)
	content=VBoxContainer.new()
	content.custom_minimum_size.x=minf(700,root.get_viewport_rect().size.x-80)
	content.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	content.add_theme_constant_override("separation",10)
	center.add_child(content)
	return content

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
	panel.custom_minimum_size = Vector2(minf(width,size.x-50),size.y-28)
	panel.size = panel.custom_minimum_size
	panel.add_theme_stylebox_override("panel",box(Color("0c202b"),Color("2c5159"),22))
	center.add_child(panel)
	var frame = VBoxContainer.new()
	panel.add_child(frame)
	var heading = row()
	frame.add_child(heading)
	var title_label = label(title,30,Color("e2f4ed"),true)
	heading.add_child(title_label)
	var close_button = button("×",func(): on_close.call())
	close_button.custom_minimum_size = Vector2(56,56)
	heading.add_child(close_button)
	var scroll = TouchScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container=scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_deadzone = 12
	frame.add_child(scroll)
	var scrollbar = scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 44
	for state in ["grabber","grabber_highlight","grabber_pressed"]:
		var handle = box(Color("79bfb3"),Color("b3eadd"),0)
		handle.content_margin_left = 12
		handle.content_margin_right = 12
		handle.set_expand_margin(SIDE_LEFT,-9)
		handle.set_expand_margin(SIDE_RIGHT,-9)
		scrollbar.add_theme_stylebox_override(state,handle)
	scrollbar.add_theme_stylebox_override("scroll",box(Color("213f49"),Color("315962"),0))
	var gutter=MarginContainer.new()
	gutter.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	gutter.add_theme_constant_override("margin_right",44)
	scroll.add_child(gutter)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",15)
	gutter.add_child(content)
	if subtitle!="": content.add_child(label(subtitle,22,Color("94b5b8"),true))
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
	l.add_theme_font_size_override("font_size",maxi(20,font_size))
	l.add_theme_color_override("font_color",color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func button(text: String,callback: Callable,primary: bool=false) -> Button:
	var b = Button.new()
	b.text = text
	b.custom_minimum_size.y = 56
	b.add_theme_font_size_override("font_size",24)
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
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(380,height)
	bar.add_theme_stylebox_override("background",box(Color("193540"),Color("193540"),0))
	bar.add_theme_stylebox_override("fill",box(color,color,0))
	return bar

func _theme() -> Theme:
	var t = Theme.new()
	t.default_font_size = 22
	t.set_stylebox("normal","Button",box(Color("173946"),Color("37616a"),12))
	t.set_stylebox("hover","Button",box(Color("24515b"),Color("78cbb8"),12))
	t.set_stylebox("pressed","Button",box(Color("306255"),Color("9ce5cb"),12))
	t.set_stylebox("disabled","Button",box(Color("162933"),Color("243c46"),12))
	t.set_color("font_color","Button",Color("d6eeea"))
	t.set_color("font_disabled_color","Button",Color("637b82"))
	t.set_color("font_hover_color","Button",Color.WHITE)
	return t
