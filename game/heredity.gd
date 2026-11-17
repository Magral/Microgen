extends RefCounted
const Genome=preload("res://core/genome.gd")
const Catalog=preload("res://core/catalog.gd")
const TRAITS=["elastic","sensory","folds","receptive"]
static func normalize(source: Dictionary) -> Dictionary:
	if source.is_empty():return {}
	var seed_value=source.get("seed",1)
	if not (seed_value is int or seed_value is float) or not is_finite(float(seed_value)):seed_value=1
	var out={"form":str(source.get("form","predator")),"traits":[],"imprint":str(source.get("imprint","")),"seed":clampi(int(seed_value),0,2147483647),"branch":str(source.get("branch","predator"))}
	if out.form not in ["predator","toxic","colony"]:out.form="predator"
	if out.branch not in ["predator","toxic","colony"]:out.branch="predator"
	var selected=source.get("traits",[])
	if not selected is Array:selected=[]
	for trait_id in selected.slice(0,8):
		if trait_id in TRAITS and trait_id not in out.traits and out.traits.size()<2:out.traits.append(trait_id)
	if out.imprint.begins_with("trait:"):
		if out.imprint.trim_prefix("trait:") not in TRAITS:out.imprint=""
	elif out.imprint not in Catalog.ORGANS:out.imprint=""
	var ancestor=source.get("ancestry_recipe",{})
	if out.imprint!="" and ancestor is Dictionary and Genome.validate(ancestor):
		out.ancestry_recipe=ancestor.duplicate(true)
		for key in ["version","seed","identity","family","palette","lobes","membrane","nuclei","tissue","biome"]:out.ancestry_recipe[key]=int(ancestor.get(key,0))
	return out
static func traits(loadout: Dictionary) -> Array:
	var out=loadout.get("traits",[]).duplicate()
	var imprint=str(loadout.get("imprint",""))
	if imprint.begins_with("trait:"):
		var trait_id=imprint.trim_prefix("trait:")
		if trait_id in TRAITS and trait_id not in out:out.append(trait_id)
	return out
static func recipe(loadout: Dictionary) -> Dictionary:
	var r=Genome.create(int(loadout.get("seed",1)),0,"player",0)
	var ancestor=loadout.get("ancestry_recipe",{})
	if ancestor is Dictionary and Genome.validate(ancestor):r.membrane=int(ancestor.membrane);r.tissue=int(ancestor.tissue)
	r.family={"predator":1,"toxic":0,"colony":4}.get(loadout.get("form","predator"),1)
	if "elastic" in traits(loadout):r.stretch=1.12;r.asymmetry=0.13
	if "sensory" in traits(loadout):r.membrane=1
	if "folds" in traits(loadout):r.membrane=2
	return r
