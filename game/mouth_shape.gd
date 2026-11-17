extends RefCounted

# Intersect a front-facing ray with the actual deformed membrane. Sampling a
# nearest vertex makes lips jump sideways on coarse or strongly asymmetric cells.
static func boundary(contour: PackedVector2Array,heading: float) -> Vector2:
	var direction=Vector2.from_angle(heading)
	var nearest=INF
	for i in range(contour.size()):
		var a=contour[i]
		var segment=contour[(i+1)%contour.size()]-a
		var cross=direction.cross(segment)
		if absf(cross)<0.00001: continue
		var distance=a.cross(segment)/cross
		var along=a.cross(direction)/cross
		if distance>0.0 and along>=0.0 and along<=1.0: nearest=minf(nearest,distance)
	return direction*(nearest if is_finite(nearest) else 0.8)

static func pose(contour: PackedVector2Array,heading: float,bite: float,feeding: float) -> Dictionary:
	var direction=Vector2.from_angle(heading)
	var tangent=direction.orthogonal()
	var anchor=boundary(contour,heading)
	var activation=clampf(maxf(bite,feeding),0.0,1.0)
	var gap=0.025+activation*0.075
	var center=anchor-direction*0.105
	var slit=PackedVector2Array()
	# Ends taper to narrow commissures; the middle opens inward like a gullet.
	for i in range(32):
		var angle=i*TAU/32.0
		slit.append(center+tangent*cos(angle)*0.22+direction*sin(angle)*gap*(0.82+0.18*sin(angle)))
	return {"anchor":anchor,"center":center,"direction":direction,"tangent":tangent,"gap":gap,"slit":slit}
