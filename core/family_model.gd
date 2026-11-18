extends RefCounted
# A single flat active projection; only inactive families carry archived state.
const Legacy=preload("res://core/genome_legacy.gd")

static func registry() -> Dictionary:
	return {"version":1,"active":"","next_id":1,"items":[]}

static func state(profile: Dictionary) -> Dictionary:
	var result={}
	for key in profile:
		if key!="families":result[key]=profile[key]
	# Copy the active state only; archived lives can be large and are omitted.
	return result.duplicate(true)

static func index(items: Array,id: String) -> int:
	for i in range(items.size()):
		if items[i].id==id: return i
	return -1

static func migrate(profile: Dictionary) -> Dictionary:
	var result=profile.duplicate(true)
	var form=str(Legacy.normalize(profile).selected_form)
	result.families={"version":1,"active":"family-1","next_id":2,"items":[{"id":"family-1","name":"Семья 1","form":form,"state":{}}]}
	return result

static func summaries(profile: Dictionary) -> Array:
	var result=[]
	for family in profile.families.items:
		var data=profile if family.id==profile.families.active else family.state
		var checkpoint=data.get("checkpoint",{})
		var ended=not str(checkpoint.get("outcome","")).is_empty()
		result.append({"id":family.id,"name":family.name,"form":family.form,"alive":not checkpoint.is_empty() and not ended,"ended":ended,"generation":int(data.legacy.generation),"runs":int(data.runs),"cores":int(data.cores),"best":float(data.best),"best_stage":int(data.get("best_stage",0))})
	return result
