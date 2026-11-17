extends RefCounted
# A single bounded indexed draw supplies actual smoothly interpolated lighting.
# The topology never depends on species, health, time or world coordinates.
const RICH_RINGS = [0.18,0.38,0.59,0.76,0.89,0.96,1.0]
const SIMPLE_RINGS = [0.32,0.65,0.88,1.0]
const LIGHT = Vector2(-0.70710678,-0.70710678)
var _topologies: Dictionary = {}
var _materials: Dictionary = {}
var _densities: Dictionary = {}
var _shading: Dictionary = {}
const SHADING_LIMIT=96
const MATERIAL_LIMIT=48
const LIGHT_SAMPLES=49

func topology(samples: int,rich: bool) -> Dictionary:
	# Only authored contour resolutions enter the persistent cache. Arbitrary
	# callers may build a topology, but cannot grow a lifetime cache.
	var key=samples*2+int(rich)
	if key in _topologies: return _topologies[key]
	var rings=RICH_RINGS if rich else SIMPLE_RINGS
	var indices=PackedInt32Array()
	for i in range(samples):
		var next=(i+1)%samples
		indices.append_array(PackedInt32Array([0,1+i,1+next]))
	for ring in range(1,rings.size()):
		var previous=1+(ring-1)*samples
		var current=1+ring*samples
		for i in range(samples):
			var next=(i+1)%samples
			indices.append_array(PackedInt32Array([previous+i,current+i,current+next,previous+i,current+next,previous+next]))
	var normals=PackedFloat32Array()
	for radial in rings: normals.append(sqrt(maxf(0.0,1.0-radial*radial)))
	var result={"indices":indices,"rings":rings,"height":normals}
	if samples in [12,24,48]: _topologies[key]=result
	return result

static func palette_color(color: Color) -> Color:
	# Six-bit channels retain pigment hues while avoiding an entire lighting LUT
	# rebuild for tiny health/pigment changes in every frame of a long fight.
	return Color(roundf(color.r*63)/63.0,roundf(color.g*63)/63.0,roundf(color.b*63)/63.0,color.a)

func material(body: Color,edge: Color,shadow: Color,rich: bool) -> PackedColorArray:
	body=palette_color(body);edge=palette_color(edge);shadow=palette_color(shadow)
	# A small palette/health LUT amortizes all color math across organisms and
	# frames. Lighting remains world-oriented through per-frame normal lookup.
	var key=Vector4i(body.to_rgba32(),edge.to_rgba32(),shadow.to_rgba32(),int(rich))
	if key in _materials: return _materials[key]
	var rings=RICH_RINGS if rich else SIMPLE_RINGS
	var colors=PackedColorArray()
	for radial in rings:
		var z=sqrt(maxf(0.0,1.0-radial*radial))
		for sample in range(LIGHT_SAMPLES):
			var facing=sample*2.0/(LIGHT_SAMPLES-1)-1.0
			var diffuse=clampf(0.52+facing*radial*0.55+z*0.25,0.0,1.0)
			var lit=shadow.lerp(body,smoothstep(0.12,0.86,diffuse))
			lit=lit.lerp(edge,maxf(0.0,diffuse-0.55)*0.74)
			var rim=smoothstep(0.86,0.97,radial)*(1.0-smoothstep(0.97,1.0,radial))
			lit=lit.lerp(edge,clampf((facing*0.60+0.25)*rim,0.0,0.72))
			var highlight=maxf(0.0,facing*radial*0.63+z*0.78)
			highlight=highlight*highlight*highlight*highlight*highlight*highlight*highlight*highlight
			lit=lit.lerp(Color(0.90,1.0,0.96),highlight*0.33)
			colors.append(Color(lit,lerpf(0.90,0.74,smoothstep(0.78,1.0,radial))))
	if _materials.size()>=MATERIAL_LIMIT: _materials.erase(_materials.keys()[0])
	_materials[key]=colors
	return colors

func density(samples: int,phase: float) -> PackedFloat32Array:
	var key="%d:%.9f" % [samples,phase]
	if key in _densities:return _densities[key]
	var values=PackedFloat32Array()
	for radial in RICH_RINGS:
		for i in range(samples):
			values.append(maxf(0.0,sin(i*2.399+phase+radial*19.0)*sin(i*0.83-radial*12.0))*0.13*(1.0-radial))
	if _densities.size()>=48:_densities.erase(_densities.keys()[0])
	_densities[key]=values
	return values

func mesh(contour: PackedVector2Array,p: Vector2,radius: float,body: Color,edge: Color,shadow: Color,rich: bool,phase: float=0.0) -> Dictionary:
	if contour.size()<3: return {"indices":PackedInt32Array(),"points":PackedVector2Array(),"colors":PackedColorArray()}
	# Lag can move a badly torn branched membrane outside the radial origin.
	# Use the exact polygon triangulation there instead of overlapping ring faces.
	for i in range(contour.size()):
		if contour[i].cross(contour[(i+1)%contour.size()])< -0.0000001:
			return _irregular_mesh(contour,p,radius,body,edge,shadow)
	var topo=topology(contour.size(),rich)
	var points=PackedVector2Array([p])
	for radial in topo.rings:
		points.append_array(Transform2D(0,Vector2.ONE*radius*float(radial),0,p)*contour)
	return {"indices":topo.indices,"points":points,"colors":_lighting(contour,body,edge,shadow,rich,phase)}

func _lighting(contour: PackedVector2Array,body: Color,edge: Color,shadow: Color,rich: bool,phase: float) -> PackedColorArray:
	# Normals already use a 49-step LUT. Reuse the exact final vertex colors
	# while these bins and the material are unchanged; positions stay live.
	var light_samples=PackedInt32Array()
	for i in range(contour.size()):
		var tangent=contour[(i+1)%contour.size()]-contour[posmod(i-1,contour.size())]
		var facing=Vector2(tangent.y,-tangent.x).normalized().dot(LIGHT)
		light_samples.append(clampi(roundi((facing+1.0)*0.5*(LIGHT_SAMPLES-1)),0,LIGHT_SAMPLES-1))
	var key=[body,edge,shadow,rich,phase,light_samples]
	if key in _shading:return _shading[key].duplicate()
	var palette=material(body,edge,shadow,rich)
	var grain=density(contour.size(),phase) if rich else PackedFloat32Array()
	var rings=RICH_RINGS if rich else SIMPLE_RINGS
	var colors=PackedColorArray([Color(body.lerp(edge,0.20),0.88)])
	for ring in range(rings.size()):
		for i in range(contour.size()):
			var lit: Color=palette[ring*LIGHT_SAMPLES+light_samples[i]]
			if rich:
				var alpha=lit.a
				lit=lit.lerp(shadow,grain[ring*contour.size()+i]);lit.a=alpha
			colors.append(lit)
	if _shading.size()>=SHADING_LIMIT:_shading.erase(_shading.keys()[0])
	_shading[key]=colors
	return colors.duplicate()

func _irregular_mesh(contour: PackedVector2Array,p: Vector2,radius: float,body: Color,edge: Color,shadow: Color) -> Dictionary:
	var indices=Geometry2D.triangulate_polygon(contour)
	var points=Transform2D(0,Vector2.ONE*radius,0,p)*contour
	var colors=PackedColorArray()
	for i in range(contour.size()):
		var tangent=contour[(i+1)%contour.size()]-contour[posmod(i-1,contour.size())]
		var facing=Vector2(tangent.y,-tangent.x).normalized().dot(LIGHT)
		var lit=body.lerp(edge,maxf(0.0,facing)*0.24).lerp(shadow,maxf(0.0,-facing)*0.55)
		colors.append(Color(lit,0.82))
	return {"indices":indices,"points":points,"colors":colors}

func paint(canvas: CanvasItem,contour: PackedVector2Array,p: Vector2,radius: float,body: Color,edge: Color,shadow: Color,rich: bool,phase: float=0.0):
	var data=mesh(contour,p,radius,body,edge,shadow,rich,phase)
	if data.indices.is_empty(): return
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(),data.indices,data.points,data.colors)
