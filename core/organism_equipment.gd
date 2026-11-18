extends RefCounted
# Family-owned organ instances. Transactions never mutate their input.
const Catalog=preload("res://core/catalog.gd")
const Slots=preload("res://core/organism_slots.gd")
const Legacy=preload("res://core/genome_legacy.gd")

static func base_capacity(form: String) -> int:
	return {"predator":6,"toxic":7,"colony":8}.get(form,6)

static func cell_cost(kind: String) -> int:
	if kind not in Catalog.ORGANS:return 0
	if kind in ["devour","division"]:return 3
	return 2 if kind in ["tentacle","acid","barrier","electric"] else 1

static func validate(state: Dictionary) -> String:
	var error=Slots.validate(state)
	if error!="":return error
	if not Slots._count(state.get("version"),1) or int(state.version)!=1:return "Неизвестная версия органов"
	if not state.get("form") is String or state.form not in Legacy.FORMS:return "Неизвестная форма"
	if not state.get("reserve") is Array:return "Некорректный архив органов"
	if not Slots._count(state.get("next_id"),1):return "Некорректный счётчик органов"
	var ids={}
	for part in state.equipped+state.stock+state.reserve:
		if not part is Dictionary:return "Некорректный орган"
		var id=part.get("id")
		if not id is String or id.is_empty() or id in ids:return "Повторяющийся или отсутствующий орган"
		ids[id]=true
		if not part.get("kind") is String or part.kind not in Catalog.ORGANS:return "Неизвестный орган"
		if not Slots._count(part.get("cells"),1) or int(part.cells)!=cell_cost(part.kind):return "Некорректный размер органа"
		if not Slots._count(part.get("rank"),1) or part.rank>Catalog.max_rank(part.kind):return "Некорректный ранг органа"
		if not Slots._count(part.get("quality")) or part.quality>3:return "Некорректное качество органа"
		if part.has("evolved") and not part.evolved is bool:return "Некорректная эволюция органа"
		if id.begins_with("organ-"):
			var suffix=id.trim_prefix("organ-")
			if suffix.is_valid_int() and int(suffix)>=int(state.next_id):return "Счётчик органов повторяет идентификатор"
	return ""

static func _result(state: Dictionary,error: String="",location: String="",id: String="") -> Dictionary:
	return {"ok":error.is_empty(),"error":error,"state":state.duplicate(true),"location":location,"id":id}

static func _new_part(state: Dictionary,kind: String,rank: int=1,quality: int=0) -> Dictionary:
	var part={"id":"organ-%d"%int(state.next_id),"kind":kind,"cells":cell_cost(kind),"rank":rank,"quality":quality}
	state.next_id=int(state.next_id)+1
	return part

static func from_profile(profile: Dictionary) -> Dictionary:
	if profile.has("organism"):
		var existing=profile.organism
		return existing.duplicate(true) if existing is Dictionary and validate(existing)=="" else {}
	var legacy=profile.get("legacy",{})
	if not legacy is Dictionary:legacy={}
	var form=legacy.get("selected_form","predator")
	if form=="division":form="colony"
	if not form is String or form not in Legacy.FORMS:form="predator"
	var state={"version":1,"next_id":1,"form":form,"body_capacity":base_capacity(form),"stock_capacity":3,"equipped":[],"stock":[],"reserve":[]}
	var checkpoint=profile.get("checkpoint",{})
	var build=checkpoint.get("build",{}) if checkpoint is Dictionary else {}
	if not build is Dictionary:build={}
	var organs=build.get("organs",{})
	var qualities=build.get("qualities",{})
	if not organs is Dictionary:organs={}
	if not qualities is Dictionary:qualities={}
	var keys=organs.keys();keys.sort()
	var represented={}
	for kind in keys:
		if kind not in Catalog.ORGANS:continue
		if not Slots._count(organs[kind],1) or organs[kind]>Catalog.max_rank(kind):return {}
		var grade=qualities.get(kind,0)
		if not Slots._count(grade) or grade>3:return {}
		var migrated=_new_part(state,kind,int(organs[kind]),int(grade))
		if bool(build.get("stats",{}).get("evolutions",{}).get(kind,false)):migrated.evolved=true
		state.equipped.append(migrated)
		represented[kind]=true
	if state.equipped.is_empty():
		var kind=Legacy.FORMS[form].organ
		state.equipped.append(_new_part(state,kind))
		represented[kind]=true
	state.body_capacity=maxi(state.body_capacity,Slots.used_cells(state))
	var imprints=legacy.get("imprints",[])
	if imprints is Array:
		for imprint in imprints:
			if not imprint is Dictionary:continue
			var kind=imprint.get("id","")
			if not kind is String or kind not in Catalog.ORGANS or kind in represented:continue
			var rank=imprint.get("rank",1)
			var grade=imprint.get("quality",0)
			if not Slots._count(rank,1) or rank>Catalog.max_rank(kind) or not Slots._count(grade) or grade>3:return {}
			state.reserve.append(_new_part(state,kind,int(rank),int(grade)))
			represented[kind]=true
	return state

static func aggregate(state: Dictionary) -> Dictionary:
	var result={"organs":{},"qualities":{}}
	if validate(state)!="":return result
	for part in state.equipped:
		result.organs[part.kind]=mini(Catalog.max_rank(part.kind),int(result.organs.get(part.kind,0))+int(part.rank))
		result.qualities[part.kind]=maxi(int(result.qualities.get(part.kind,0)),int(part.quality))
	return result

static func award(state: Dictionary,kind: String,grade: int=0) -> Dictionary:
	var error=validate(state)
	if error!="":return _result(state,error)
	if kind not in Catalog.ORGANS or grade<0 or grade>3:return _result(state,"Некорректная награда")
	var next=state.duplicate(true)
	var owns_kind=false
	for part in next.equipped:
		if part.kind!=kind:continue
		owns_kind=true
		if part.rank>=Catalog.max_rank(kind) and grade<=part.quality:continue
		part.rank=mini(Catalog.max_rank(kind),int(part.rank)+1)
		part.quality=maxi(int(part.quality),grade)
		return _result(next,"","body",part.id)
	if owns_kind:return _result(state,"Орган уже развит")
	if int(next.next_id)>=Slots.MAX_EXACT_INTEGER:return _result(state,"Исчерпаны идентификаторы органов")
	var part=_new_part(next,kind,1,grade)
	var location="reserve"
	if Slots.used_cells(next)+part.cells<=int(next.body_capacity):location="body";next.equipped.append(part)
	elif next.stock.size()<int(next.stock_capacity):location="stock";next.stock.append(part)
	else:next.reserve.append(part)
	return _result(next,"",location,part.id)

static func refresh(state: Dictionary,build: Dictionary) -> Dictionary:
	var error=validate(state)
	if error!="":return _result(state,error)
	var organs=build.get("organs",{})
	var qualities=build.get("qualities",{})
	if not organs is Dictionary or not qualities is Dictionary:return _result(state,"Некорректная сборка")
	var next=state.duplicate(true)
	for kind in organs:
		if kind not in Catalog.ORGANS or not Slots._count(organs[kind],1) or organs[kind]>Catalog.max_rank(kind):return _result(state,"Некорректная сборка")
		var grade=qualities.get(kind,0)
		if not Slots._count(grade) or grade>3:return _result(state,"Некорректное качество")
		var matching=next.equipped.filter(func(part):return part.kind==kind)
		if matching.is_empty():
			var addition=award(next,kind,int(grade))
			if not addition.ok:return _result(state,addition.error)
			next=addition.state
			var list=next.equipped if addition.location=="body" else (next.stock if addition.location=="stock" else next.reserve)
			for part in list:
				if part.id==addition.id:part.rank=int(organs[kind]);part.quality=int(grade)
		else:
			# Gameplay exposes the sum of ranks, so apply only its positive delta
			# to an existing instance; never rewrite inactive family possessions.
			var total=0
			for part in matching:total+=int(part.rank)
			var first=matching[0]
			first.rank=mini(Catalog.max_rank(kind),int(first.rank)+maxi(0,int(organs[kind])-total))
			var best_grade=0
			for part in matching:best_grade=maxi(best_grade,int(part.quality))
			if int(grade)>best_grade:first.quality=int(grade)
	return _result(next)

static func move(state: Dictionary,id: String,destination: String,replacements: Array=[]) -> Dictionary:
	var error=validate(state)
	if error!="":return _result(state,error)
	if destination in ["body","stock"]:return Slots.move(state,id,destination,replacements)
	if destination not in ["archive","stock_from_archive"] or not replacements.is_empty():return _result(state,"Неизвестное место установки")
	var next=state.duplicate(true)
	var source=next.reserve if destination=="stock_from_archive" else next.equipped+next.stock
	var found=source.filter(func(part):return part.id==id)
	if found.size()!=1:return _result(state,"Орган не найден в исходном месте")
	if destination=="stock_from_archive":
		if next.stock.size()>=int(next.stock_capacity):return _result(state,"Запас заполнен")
		next.reserve=next.reserve.filter(func(part):return part.id!=id)
		next.stock.append(found[0])
	else:
		next.equipped=next.equipped.filter(func(part):return part.id!=id)
		next.stock=next.stock.filter(func(part):return part.id!=id)
		next.reserve.append(found[0])
	return _result(next)

static func expand(state: Dictionary,target: String) -> Dictionary:
	var error=validate(state)
	return _result(state,error) if error!="" else Slots.expand(state,target)
