extends ScrollContainer
# Handle real screen gestures independently of Godot's single emulated mouse.
# Physical mouse/wheel events keep their ordinary ScrollContainer behavior.
var _finger=-1
var _start=Vector2.ZERO
var _from=0.0
var _dragging=false
var _on_bar=false
var _on_thumb=false
var _bar_scale=1.0
var _track_top=0.0
var _thumb_size=0.0
var _button: BaseButton
var _normal_style: StyleBox
var _had_normal_override=false

func _clear_button():
	if is_instance_valid(_button):
		if _had_normal_override:_button.add_theme_stylebox_override("normal",_normal_style)
		else:_button.remove_theme_stylebox_override("normal")
	_button=null
	_normal_style=null

func reset_gesture():
	_finger=-1
	_dragging=false
	_clear_button()

func _notification(what):
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_EXIT_TREE]:reset_gesture()
	if what==NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():reset_gesture()

func _input(event):
	if not is_visible_in_tree():return
	if event is InputEventMouse and event.device==-1:
		if _finger>=0 or get_global_rect().has_point(event.position):get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.index==_finger:reset_gesture()
			if _finger>=0:
				if get_global_rect().has_point(event.position):get_viewport().set_input_as_handled()
				return
			if not get_global_rect().has_point(event.position):return
			_finger=event.index;_start=event.position;_from=scroll_vertical
			_dragging=false
			var bar=get_v_scroll_bar()
			_on_bar=bar.is_visible_in_tree() and bar.get_global_rect().has_point(event.position)
			if _on_bar:_prepare_bar(bar,event.position)
			_button=null if _on_bar else _button_at(event.position)
			if is_instance_valid(_button):
				_had_normal_override=_button.has_theme_stylebox_override("normal")
				_normal_style=_button.get_theme_stylebox("normal")
				_button.add_theme_stylebox_override("normal",_button.get_theme_stylebox("pressed"))
			get_viewport().set_input_as_handled()
		elif event.index==_finger:
			get_viewport().set_input_as_handled()
			var button=_button
			var activate=not event.canceled and not _dragging and get_global_rect().has_point(event.position) and _start.distance_to(event.position)<=scroll_deadzone
			if _on_bar and activate and not _on_thumb:
				var bar=get_v_scroll_bar()
				bar.value=bar.min_value+(event.position.y-_track_top-_thumb_size/2)*_bar_scale
			reset_gesture()
			if activate and is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and button.get_global_rect().has_point(event.position):
				if button.toggle_mode:button.button_pressed=not button.button_pressed
				button.pressed.emit()
	elif event is InputEventScreenDrag and event.index==_finger:
		get_viewport().set_input_as_handled()
		var delta=event.position-_start
		if not _dragging and delta.length()<=scroll_deadzone:return
		_dragging=true
		_clear_button()
		if _on_bar:
			var bar=get_v_scroll_bar()
			bar.value=_from+delta.y*_bar_scale
		else:scroll_vertical=roundi(_from-delta.y)

func _prepare_bar(bar: VScrollBar,point: Vector2):
	var decrement=bar.get_theme_icon("decrement").get_height()
	var increment=bar.get_theme_icon("increment").get_height()
	var background=bar.get_theme_stylebox("scroll")
	var minimum=bar.get_theme_stylebox("grabber").get_minimum_size().y
	var area=maxf(1,bar.size.y-background.get_minimum_size().y-decrement-increment-minimum)
	var total=maxf(1,bar.max_value-bar.min_value)
	_track_top=bar.global_position.y+decrement+background.get_content_margin(SIDE_TOP)
	_thumb_size=bar.page/total*area+minimum
	_bar_scale=total/area
	var thumb_top=_track_top+(bar.value-bar.min_value)/_bar_scale
	_on_thumb=point.y>=thumb_top and point.y<=thumb_top+_thumb_size

func _button_at(point: Vector2) -> BaseButton:
	var buttons=find_children("*","BaseButton",true,false)
	buttons.reverse()
	for button in buttons:
		if button.is_visible_in_tree() and not button.disabled and button.mouse_filter!=Control.MOUSE_FILTER_IGNORE and button.get_global_rect().has_point(point):return button
	return null
