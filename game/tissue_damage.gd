extends RefCounted

# Stateless visual geometry. Sites depend on genome identity, never health/time or
# gameplay RNG. Radial cuts keep ordered vertices and recover continuously.
static func severity(health_ratio: float) -> float:
	return smoothstep(0.04,1.0,1.0-clampf(health_ratio,0.0,1.0))

static func wounds(recipe: Dictionary,health_ratio: float) -> Array:
	var amount=severity(health_ratio)
	if amount<=0.0: return []
	var sites=[]
	var seed_phase=fposmod(float(int(recipe.seed)*73+int(recipe.identity)*151),997.0)/997.0*TAU
	for i in range(5):
		sites.append({"angle":seed_phase+i*TAU/5+0.16*sin(i*4.73+seed_phase)+float(recipe.rotation),"width":0.30+0.055*sin(i*2.83+seed_phase),"depth":amount*(0.61+0.08*sin(i*3.17+seed_phase)),"strength":amount,"index":i})
	return sites

static func contour(points: PackedVector2Array,recipe: Dictionary,health_ratio: float) -> PackedVector2Array:
	var sites=wounds(recipe,health_ratio)
	if sites.is_empty(): return points
	var out=points.duplicate()
	for i in range(points.size()): out[i]=deform_point(points[i],sites)
	return out

static func deform_point(point: Vector2,sites: Array) -> Vector2:
	var cut=0.0
	for site in sites:
		var distance=absf(wrapf(point.angle()-float(site.angle),-PI,PI))
		var bite=1.0-smoothstep(0.0,float(site.width)*1.8,distance)
		# A narrow deep tear surrounded by a scalloped, frayed wound lip.
		var ragged=0.80+0.20*cos(distance*37.0+float(site.index)*2.2)
		cut=maxf(cut,float(site.depth)*bite*ragged)
	return point*(1.0-clampf(cut,0.0,0.70))
