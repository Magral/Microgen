extends SceneTree
const Painter=preload("res://game/organism_painter.gd")
var indices=Painter.new()._tendril_indices
class FoldedTendril extends Node2D:
	var painter=Painter.new()
	func _draw():
		var contour=PackedVector2Array()
		for i in range(48):contour.append(Vector2.from_angle(i*TAU/48))
		for i in range(8):painter._tendril(self,Vector2(250+i*60,200),contour,100,0,i*0.3,1.1,Color("9ce3cf"),4,Vector2(-160,0),110.0/346.0)
func _initialize():call_deferred("run")
func run():
	var checks=0
	for angle_index in range(16):
		for extension_index in range(11):
			for time_index in range(16):
				var points=PackedVector2Array()
				var p=Vector2(900,600);var radius=100.0
				var a=Vector2.RIGHT;var normal=Vector2.UP
				var tip=Vector2.from_angle(angle_index*TAU/16)*160
				var extension=extension_index/10.0;var time=time_index*TAU/16
				if angle_index==8 and extension_index==4:extension=110.0/346.0
				for i in range(10):
					var t=i/9.0
					var resting=p+a*radius*(0.76+t*1.1)+normal*radius*sin(t*4+time*1.5)*t*0.24
					var strike=(p+a*radius*0.76).lerp(p+tip,t)+normal*sin(t*PI)*radius*0.25
					points.append(resting.lerp(strike,extension))
				var flesh=Painter._tendril_shape(points,normal,radius,4)
				checks+=1
				if not valid_ribbon(flesh):
					push_error("Tendril shape invalid at angle=%d extension=%d time=%d points=%s"%[angle_index,extension_index,time_index,points]);quit(1);return
	var rng=RandomNumberGenerator.new();rng.seed=8129
	for sample in range(20000):
		var points=PackedVector2Array()
		var p=Vector2(640,360);var radius=rng.randf_range(40,250)
		var a=Vector2.from_angle(rng.randf()*TAU)*rng.randf_range(0.6,1.4);var normal=a.normalized().orthogonal()
		var tip=Vector2.from_angle(rng.randf()*TAU)*radius*rng.randf_range(0.1,5)
		var extension=rng.randf();var time=rng.randf()*1000
		for i in range(10):
			var t=i/9.0
			var resting=p+a*radius*(0.76+t*1.1)+normal*radius*sin(t*4+time*1.5)*t*0.24
			var strike=(p+a*radius*0.76).lerp(p+tip,t)+normal*sin(t*PI)*radius*0.25
			points.append(resting.lerp(strike,extension))
		var flesh=Painter._tendril_shape(points,normal,radius,4)
		checks+=1
		if not valid_ribbon(flesh):
			push_error("Tendril invalid random sample=%d radius=%f normal=%s points=%s"%[sample,radius,normal,points]);quit(1);return
	var canvas=FoldedTendril.new();root.add_child(canvas)
	await process_frame;await process_frame;await process_frame
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	print("TENDRIL SHAPE: %d poses, 0 failures"%checks);quit()
func valid_ribbon(points: PackedVector2Array) -> bool:
	if points.size()!=20:return false
	for point in points:
		if not point.is_finite():return false
	if indices.size()!=51:return false
	for index in indices:
		if index<0 or index>=points.size():return false
	return true
