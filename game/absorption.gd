extends RefCounted

# Geometry only. Progress is authoritative gameplay state; decoration never moves it.
static func pose(source: Vector2,progress: float,contour: PackedVector2Array,radius: float) -> Dictionary:
	var t=clampf(progress,0.0,1.0)
	var direction=source.normalized() if source.length()>0.01 else Vector2.RIGHT
	var boundary=radius
	for i in range(contour.size()):
		var a=contour[i]*radius
		var segment=(contour[(i+1)%contour.size()]-contour[i])*radius
		var cross=direction.cross(segment)
		if absf(cross)<0.0001: continue
		var distance=a.cross(segment)/cross
		var along=a.cross(direction)/cross
		if distance>0 and along>=0 and along<=1: boundary=distance
	var edge=direction*boundary
	var crossing=smoothstep(0.12,0.72,t)
	var destination=edge*0.36 if source.length()>edge.length()*0.36 else source*0.35
	var offset=source.lerp(destination,crossing)
	var dissolution=smoothstep(0.55,1.0,t)
	return {"offset":offset,"edge":edge,"direction":direction,"progress":t,"scale":lerpf(1.0,0.04,dissolution),"alpha":1.0-dissolution,"bulge":sin(PI*clampf(t/0.76,0,1))*0.32,"internal":t>=0.42}

static func membrane(contour: PackedVector2Array,state: Dictionary,radius: float) -> PackedVector2Array:
	var result=contour.duplicate()
	for i in range(result.size()):
		var alignment=maxf(0.0,result[i].normalized().dot(state.direction))
		result[i]+=state.direction*pow(alignment,12)*float(state.bulge)
	return result
