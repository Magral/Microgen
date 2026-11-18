extends RefCounted
# Static colored geometry combines hundreds of tiny wall/fiber canvas commands
# into one indexed draw per visible chunk. No textures or render targets needed.
const Volume=preload("res://game/organic_volume.gd")
var volume=Volume.new()
var points=PackedVector2Array()
var colors=PackedColorArray()
var indices=PackedInt32Array()
func vertex(p: Vector2,color: Color) -> int:
	var result=points.size()
	points.append(p);colors.append(color)
	return result
func triangle(a: int,b: int,c: int):
	if (points[b]-points[a]).cross(points[c]-points[a])<0:
		indices.append_array(PackedInt32Array([a,c,b]))
	else:indices.append_array(PackedInt32Array([a,b,c]))
func quad(a: Vector2,b: Vector2,c: Vector2,d: Vector2,color_a: Color,color_b: Color):
	var start=points.size()
	vertex(a,color_a);vertex(b,color_a);vertex(c,color_b);vertex(d,color_b)
	triangle(start,start+1,start+2);triangle(start,start+2,start+3)
func polygon(shape: PackedVector2Array,color: Color):
	var faces=Geometry2D.triangulate_polygon(shape)
	var start=points.size()
	for point in shape:vertex(point,color)
	for index in faces:indices.append(start+index)
func circle(p: Vector2,radius: float,color: Color):
	var center=vertex(p,color)
	var first=points.size()
	for i in range(16):vertex(p+Vector2.from_angle(i*TAU/16.0)*radius,color)
	for i in range(16):triangle(center,first+i,first+(i+1)%16)
func line(shape: PackedVector2Array,width: float,color: Color):
	var transparent=Color(color,0.0)
	var half=maxf(0.1,width*0.5)
	for i in range(1,shape.size()):
		var a=shape[i-1];var b=shape[i]
		if a.distance_squared_to(b)<0.000001:continue
		var normal=(b-a).normalized().orthogonal()
		var inner=normal*half
		var outer=normal*(half+0.35)
		quad(a-inner,b-inner,b+inner,a+inner,color,color)
		quad(a-outer,b-outer,b-inner,a-inner,transparent,color)
		quad(a+inner,b+inner,b+outer,a+outer,color,transparent)
func bake(commands: Array):
	points=PackedVector2Array();colors=PackedColorArray();indices=PackedInt32Array()
	for command in commands:
		match command.kind:
			0:polygon(command.points,command.color)
			1:line(command.points,float(command.width),command.color)
			2:circle(command.p,float(command.radius),command.color)
			3:
				var data=volume.mesh(command.shape,command.p,float(command.radius),command.body,command.edge,command.shadow,bool(command.get("rich",true)))
				var start=points.size()
				points.append_array(data.points);colors.append_array(data.colors)
				for index in data.indices:indices.append(start+index)
func paint(canvas: CanvasItem):
	if not indices.is_empty():RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),indices,points,colors)
