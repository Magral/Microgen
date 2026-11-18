extends SceneTree
const Hud=preload("res://ui/hud.gd")
var failures=0
var taps=0
var hud
var first_button
func check(ok: bool,message: String):
	if not ok:failures+=1;push_error(message)
func touch(index: int,p: Vector2,pressed: bool,canceled: bool=false):
	var event=InputEventScreenTouch.new()
	event.index=index;event.position=p;event.pressed=pressed;event.canceled=canceled
	Input.parse_input_event(event)
	await process_frame;await process_frame
func drag(index: int,from: Vector2,to: Vector2):
	var event=InputEventScreenDrag.new()
	event.index=index;event.position=to;event.relative=to-from;event.velocity=(to-from)*30
	Input.parse_input_event(event)
	await process_frame;await process_frame
func fill():
	var box=hud.open("Проверка жестов")
	for i in range(18):
		var card=hud.card();box.add_child(card)
		var column=VBoxContainer.new();card.add_child(column)
		var art=Control.new();art.custom_minimum_size=Vector2(400,80);column.add_child(art)
		var button=hud.button("Выбор %d"%i,func():taps+=1)
		column.add_child(button)
		if i==0:first_button=button
func _initialize():call_deferred("run")
func run():
	if DisplayServer.get_name()=="headless":quit(2);return
	hud=Hud.new();root.add_child(hud);hud.on_close=func():hud.close()
	fill();await process_frame;await process_frame;await process_frame
	var scroll=hud.scroll_container
	var p=first_button.get_global_rect().get_center()
	await touch(0,p,true)
	await drag(0,p,p-Vector2(0,100))
	await touch(0,p-Vector2(0,100),false)
	check(scroll.scroll_vertical>50,"swipe beginning on a button scrolls content")
	check(taps==0,"swiping across a button never selects it")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	# Finger 0 can rest outside the list. A scrolling finger need not be the
	# finger Godot selected for emulated mouse events.
	await touch(0,Vector2(8,8),true)
	var bar=scroll.get_v_scroll_bar()
	p=bar.global_position+Vector2(bar.size.x/2,35)
	await touch(1,p,true);await drag(1,p,p+Vector2(0,130))
	await touch(1,p+Vector2(0,130),false);await touch(0,Vector2(8,8),false)
	check(scroll.scroll_vertical>100,"a second finger can drag the full scrollbar")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	p=first_button.get_global_rect().get_center()
	var normal=first_button.get_theme_stylebox("normal")
	await touch(0,p,true)
	check(first_button.get_theme_stylebox("normal")==first_button.get_theme_stylebox("pressed"),"touch shows pressed feedback")
	await touch(0,p,false)
	check(first_button.get_theme_stylebox("normal")==normal,"touch restores original button style")
	check(taps==1,"normal button tap fires exactly once after scrolling")
	await touch(0,p,true);await touch(0,p,false,true)
	check(taps==1,"canceled touch cannot activate a button")
	await touch(2,p,true);await drag(2,p,p-Vector2(0,100))
	await touch(2,Vector2(-20,-20),false)
	check(scroll.scroll_vertical>50,"finger index reuse and release outside keep scrolling usable")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	p=first_button.get_global_rect().get_center()
	await touch(3,p,true)
	# Rebuild while a finger is down: a retired list cannot own the next menu.
	fill();await process_frame;await process_frame;await process_frame
	await touch(3,p,false)
	scroll=hud.scroll_container;p=first_button.get_global_rect().get_center()
	await touch(4,p,true);await drag(4,p,p-Vector2(0,100));await touch(4,p-Vector2(0,100),false)
	check(scroll.scroll_vertical>50,"new menu scrolls after prior menu retired mid-gesture")
	check(taps==1,"menu rebuild and drags do not activate choices")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	p=first_button.get_global_rect().get_center()
	await touch(5,p,true)
	scroll.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await touch(5,p,false)
	await touch(6,p,true);await drag(6,p,p-Vector2(0,100));await touch(6,p-Vector2(0,100),false)
	check(scroll.scroll_vertical>50,"focus interruption releases old gesture ownership")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	p=first_button.get_global_rect().get_center()
	var bar_again=scroll.get_v_scroll_bar()
	p=bar_again.global_position+Vector2(bar_again.size.x/2,10)
	await touch(0,p,true);await touch(0,p,false)
	check(scroll.scroll_vertical==0,"stationary thumb tap never jumps the list")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	p=first_button.get_global_rect().get_center()
	await touch(0,p,true)
	# Simulate a lost release: a fresh press of the same id must recover.
	await touch(0,p+Vector2(0,70),true)
	await drag(0,p+Vector2(0,70),p-Vector2(0,30));await touch(0,p-Vector2(0,30),false)
	check(scroll.scroll_vertical>=90,"fresh press recovers the same finger after a lost release")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	p=first_button.get_global_rect().get_center()
	var before=taps
	await touch(0,Vector2(8,8),true)
	await touch(1,p,true);await touch(1,p,false);await touch(0,Vector2(8,8),false)
	check(taps==before+1,"button tap works when another finger rests outside the list")
	before=taps
	var edge_button=scroll.find_children("*","BaseButton",true,false)[4]
	scroll.scroll_vertical+=roundi(edge_button.global_position.y-(scroll.get_global_rect().end.y-6))
	await process_frame;await process_frame
	var edge=Vector2(edge_button.get_global_rect().get_center().x,scroll.get_global_rect().end.y-3)
	await touch(0,edge,true);await touch(0,edge+Vector2(0,6),false)
	check(taps==before,"release beyond clipping boundary cannot activate a partially visible choice")
	scroll.scroll_vertical=0;await process_frame;await process_frame
	p=first_button.get_global_rect().get_center()
	before=taps
	for pressed in [true,false]:
		var mouse=InputEventMouseButton.new()
		mouse.position=p;mouse.global_position=p;mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=pressed
		Input.parse_input_event(mouse);await process_frame;await process_frame
	check(taps==before+1,"physical mouse button remains native and activates once")
	var wheel=InputEventMouseButton.new()
	wheel.position=p;wheel.global_position=p;wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true
	Input.parse_input_event(wheel);await process_frame;await process_frame
	check(scroll.scroll_vertical>0,"physical mouse wheel still scrolls the list")
	hud.queue_free();await process_frame
	print("SCROLL TOUCH: %d failures"%failures)
	quit(0 if failures==0 else 1)
