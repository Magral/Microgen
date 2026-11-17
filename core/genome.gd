extends RefCounted

const FAMILIES = ["lobed","elongated","crescent","branched","cluster","radial"]
const PALETTES = [
	["249eaa","95f2df","9d6dcc","c8dc67","153844"],
	["7150ad","ccaff3","e184c5","a8d66c","282544"],
	["859f30","e1ef91","9872c9","e9938f","2d3a22"],
	["377bb9","b2d7f2","bd85d9","e1b869","172f49"],
	["ba5a75","f6b3c3","b77cd2","e1ce89","49263b"],
	["b78b3b","f4daa0","9b74bb","78c9b8","443526"],
	["427d83","a7dcd9","9c89de","b7d975","183c43"],
	["4a9b76","b1e6a2","c183ca","e5d383","1b3b35"]
]

static func create(seed_value: int,identity: int,role: String,biome: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value*1664525+identity*1013904223+role.hash()
	var family = rng.randi_range(0,5)
	if role=="prey": family = [0,1,4][rng.randi_range(0,2)]
	return {"version":1,"seed":seed_value,"identity":identity,"family":family,"palette":rng.randi_range(0,7),"lobes":rng.randi_range(3,7),"membrane":rng.randi_range(0,2),"nuclei":rng.randi_range(1,3),"phase":rng.randf()*TAU,"rotation":rng.randf()*TAU,"stretch":rng.randf_range(0.91,1.08),"asymmetry":rng.randf_range(0.04,0.12),"tissue":rng.randi_range(0,2),"biome":biome}

static func validate(recipe: Dictionary) -> bool:
	for key in ["version","seed","identity","family","palette","lobes","membrane","nuclei","phase","rotation","stretch","asymmetry","tissue"]:
		if not recipe.has(key): return false
		if not (recipe[key] is int or recipe[key] is float): return false
		if not is_finite(float(recipe[key])): return false
	return int(recipe.version)==1 and int(recipe.family) in range(6) and int(recipe.palette) in range(8) and int(recipe.nuclei) in range(1,4) and int(recipe.lobes) in range(3,8) and float(recipe.stretch)>=0.85 and float(recipe.stretch)<=1.15 and absf(float(recipe.asymmetry))<=0.15

static func contour(recipe: Dictionary,detail: int=48) -> PackedVector2Array:
	var points = PackedVector2Array()
	var family = int(recipe.family)
	var phase = float(recipe.phase)
	for i in range(detail):
		var angle = i*TAU/detail
		var wave = sin(angle*int(recipe.lobes)+phase)
		var radius = 0.81+0.15*wave
		match family:
			1: radius = 0.85+0.10*sin(angle*4+phase)
			2: radius = 0.67+0.25*cos(angle)+0.12*sin(angle*3+phase)
			3: radius = 0.46+0.61*pow((wave+1)*0.5,2.6)
			4: radius = 0.79+0.20*sin(angle*3+phase)+0.06*sin(angle*6-phase)
			5: radius = 0.85+0.08*sin(angle*10+phase)
		radius += float(recipe.asymmetry)*sin(angle*2-phase)
		var p = Vector2.from_angle(angle)*radius
		if family==1: p *= Vector2(1.32,0.63)
		elif family==2: p *= Vector2(1.10,0.90)
		elif family==4: p *= Vector2(1.1,0.86)
		p.x *= float(recipe.stretch)
		points.append(p.rotated(float(recipe.rotation)))
	return points

static func colors(recipe: Dictionary) -> Array:
	var out = []
	for value in PALETTES[int(recipe.palette)]: out.append(Color(value))
	return out

static func traits(seed_value: int,identity: int,elapsed: float,kind: String) -> Array:
	if kind=="prey": return []
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value*69069+identity*362437+8291
	var count = mini(3,int(elapsed/150.0))
	if kind=="boss": count = 3
	elif elapsed<150 and rng.randf()<0.35: count = 1
	var pool = ["shell","swift","regen","toxic","spores"]
	var out = []
	for i in range(count):
		var index = rng.randi_range(0,pool.size()-1)
		out.append(pool[index])
		pool.remove_at(index)
	return out
