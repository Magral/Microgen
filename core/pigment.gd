extends RefCounted

# Approximate translucent pigment absorption with optical density in linear RGB.
# This is an artistic tissue model, not a spectral chemistry simulation.
static func create(base: Color) -> Dictionary:
	return {"density":_density(base),"mass":18.0}

static func _density(value: Color) -> Array:
	var linear=value.srgb_to_linear()
	return [-log(maxf(0.008,linear.r)),-log(maxf(0.008,linear.g)),-log(maxf(0.008,linear.b))]

static func feed(state: Dictionary,value: Color,amount: float):
	var incoming={"density":_density(value),"mass":maxf(0.0,amount)}
	combine(state,incoming)
	state.mass=minf(80.0,state.mass)

# A merged corpse retains all pigment mass; the organism itself has finite turnover.
static func combine(state: Dictionary,incoming: Dictionary):
	var mass=maxf(0.001,float(state.mass))
	var weight=maxf(0.0,float(incoming.mass))
	for i in range(3): state.density[i]=(float(state.density[i])*mass+float(incoming.density[i])*weight)/(mass+weight)
	state.mass=mass+weight

static func color(state: Dictionary) -> Color:
	return Color(exp(-float(state.density[0])),exp(-float(state.density[1])),exp(-float(state.density[2]))).linear_to_srgb()

static func restore(saved,base: Color) -> Dictionary:
	if saved is Dictionary and saved.get("density") is Array and saved.density.size()==3 and (saved.get("mass") is float or saved.get("mass") is int):
		var valid=true
		for value in saved.density:
			if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0 or float(value)>5: valid=false
		if valid and is_finite(float(saved.mass)) and float(saved.mass)>0:
			return {"density":saved.density.duplicate(),"mass":clampf(float(saved.mass),1,80)}
	return create(base)
