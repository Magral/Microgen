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

# The fixed commissures hinge into a deep, asymmetric lower jaw. Every point
# remains in living tissue and in the same +/-0.7 rad front cone as the bite.
static func pose(contour: PackedVector2Array,heading: float,bite: float,feeding: float) -> Dictionary:
	var direction=Vector2.from_angle(heading)
	var tangent=direction.orthogonal()
	var anchor=boundary(contour,heading)
	var activation=clampf(maxf(bite,feeding),0.0,1.0)
	var gap=0.016+activation*0.19
	var width=0.23+activation*0.18
	var center=anchor-direction*(0.105+activation*0.15)
	var upper=PackedVector2Array()
	var lower=PackedVector2Array()
	# Fit the entire jaw with one affine transform. Clamping each vertex to a
	# jagged membrane independently can fold the thin idle slit across itself.
	var across_scale=1.0
	for i in range(17):
		var u=i/16.0
		var arch=pow(maxf(0.0,sin(u*PI)),0.85)
		var across=(u-0.5)*width*2.0
		var depth=center.dot(direction)-gap*arch*1.42
		if absf(across)>0.00001:
			across_scale=minf(across_scale,maxf(0.03,depth)*tan(0.67)/absf(across))
	var fit=1.0
	for i in range(17):
		var u=i/16.0
		var arch=pow(maxf(0.0,sin(u*PI)),0.85)
		var across=tangent*(u-0.5)*width*2.0*across_scale
		upper.append(center+across+direction*gap*arch*0.38)
		lower.append(center+across-direction*gap*arch*1.42)
	for point in upper+lower:
		fit=minf(fit,boundary(contour,point.angle()).length()*0.96/maxf(0.00001,point.length()))
	for i in range(upper.size()):
		upper[i]*=fit
		lower[i]*=fit
	center*=fit
	var slit=upper.duplicate()
	for i in range(15,0,-1): slit.append(lower[i])
	return {"anchor":anchor,"center":center,"direction":direction,"tangent":tangent,"gap":gap*fit,"width":width*across_scale*fit,"activation":activation,"upper":upper,"lower":lower,"slit":slit,"throat":center-direction*gap*fit*0.61}
