extends RefCounted
# Radial tissue growth preserves angular ordering and follows existing wounds/jelly.
static func shape(contour: PackedVector2Array,evolved: Dictionary,time: float,phase: float,growth: Dictionary={}) -> PackedVector2Array:
	var crown=bool(evolved.get("tentacle",false))
	var mantle=bool(evolved.get("acid",false))
	var womb=bool(evolved.get("infection",false))
	if not crown and not mantle and not womb:return contour
	var out=PackedVector2Array();out.resize(contour.size())
	for i in range(contour.size()):
		var a=contour[i].angle()-phase
		var swell=0.0
		if crown:swell+=(0.08+0.045*cos(a*3))*float(growth.get("tentacle",1.0))
		if mantle:swell+=(0.035+0.065*cos(a*6+sin(time*1.4)*0.2))*float(growth.get("acid",1.0))
		if womb:swell+=(0.06+0.09*cos(a*3-1.8)+0.025*sin(time*2.2+a*3))*float(growth.get("infection",1.0))
		out[i]=contour[i]*(1.0+clampf(swell,-0.08,0.22))
	return out
