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
		if part.has("specialization") and (not part.specialization is String or (not Catalog.has_specialization(part.kind,part.specialization) and part.specialization not in ["feral","resonant"])):return "Некорректная специализация органа"
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
		if not existing is Dictionary or validate(existing)!="":return {}
		var migrated=existing.duplicate(true)
		for group in ["equipped","stock","reserve"]:
			for part in migrated.get(group,[]):
				if part.has("specialization"):part.specialization=Catalog.legacy_specialization(str(part.kind),str(part.specialization))
		return migrated
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
		var specialization=build.get("specializations",{}).get(kind,"") if build.get("specializations",{}) is Dictionary else ""
		var normalized_specialization=Catalog.legacy_specialization(kind,str(specialization))
		if normalized_specialization!="":migrated.specialization=normalized_specialization
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
	var result={"organs":{},"qualities":{},"specializations":{}}
	if validate(state)!="":return result
	for part in state.equipped:
		var current=int(result.organs.get(part.kind,0));var added=int(part.rank)
		result.organs[part.kind]=current+mini(added,Catalog.max_rank(part.kind)-current)
		result.qualities[part.kind]=maxi(int(result.qualities.get(part.kind,0)),int(part.quality))
		if part.has("specialization"):
			if added>=current:result.specializations[part.kind]=part.specialization
	return result

static func upgrade_cost(part: Dictionary) -> int:
	var rank=int(part.get("rank",1))
	return mini(9007199254740991,6+int(floor(4.0*pow(float(rank),0.72))))

static func upgrade(state: Dictionary,id: String,organium: int,materials: Dictionary={}) -> Dictionary:
	var error=validate(state)
	if error!="":return {"ok":false,"error":error,"state":state.duplicate(true),"organium":organium,"spent":0}
	var next=state.duplicate(true)
	for group in ["equipped","stock","reserve"]:
		for part in next[group]:
			if part.id!=id:continue
			var price=upgrade_cost(part)
			var ingredient=mini(128,1+int(floor(float(part.rank)/8.0)))
			if organium<price:return {"ok":false,"error":"Нужно органиума: %d"%price,"state":state.duplicate(true),"organium":organium,"materials":materials.duplicate(true),"spent":0}
			if int(materials.get("organelle",0))<ingredient:return {"ok":false,"error":"Нужно органелл: %d"%ingredient,"state":state.duplicate(true),"organium":organium,"materials":materials.duplicate(true),"spent":0}
			if int(part.rank)>=9007199254740991:return {"ok":false,"error":"Достигнут предел точности сохранения","state":state.duplicate(true),"organium":organium,"spent":0}
			part.rank=int(part.rank)+1
			var remaining=materials.duplicate(true);remaining.organelle=int(remaining.get("organelle",0))-ingredient
			return {"ok":true,"error":"","state":next,"organium":organium-price,"materials":remaining,"spent":price,"ingredient":ingredient}
	return {"ok":false,"error":"Орган не найден","state":state.duplicate(true),"organium":organium,"materials":materials.duplicate(true),"spent":0}

static func specialize(state: Dictionary,id: String,specialization: String,organium: int,materials: Dictionary={}) -> Dictionary:
	var error=validate(state)
	if error!="":return {"ok":false,"error":error,"state":state.duplicate(true),"organium":organium,"spent":0}
	for group in ["equipped","stock","reserve"]:
		for part in state[group]:
			if part.id!=id:continue
			if not Catalog.has_specialization(str(part.kind),specialization):return {"ok":false,"error":"Неизвестная специализация этого органа","state":state.duplicate(true),"organium":organium,"spent":0}
			var old=str(part.get("specialization",""))
			if old==specialization:return {"ok":false,"error":"Эта специализация уже активна","state":state.duplicate(true),"organium":organium,"spent":0}
			var price=12 if old.is_empty() else mini(9007199254740991,18+int(part.rank))
			if organium<price:return {"ok":false,"error":"Смена специализации стоит %d органиума"%price,"state":state.duplicate(true),"organium":organium,"spent":0}
			var ingredient=1 if old.is_empty() else 2
			var material_kind=part.kind if int(materials.get(part.kind,0))>=ingredient else "organelle"
			if int(materials.get(material_kind,0))<ingredient:return {"ok":false,"error":"Нужно фрагментов %s: %d"%[Catalog.item(part.kind).name,ingredient],"state":state.duplicate(true),"organium":organium,"materials":materials.duplicate(true),"spent":0}
			var next=state.duplicate(true)
			for candidate in next[group]:
				if candidate.id==id:candidate.specialization=specialization
			var remaining=materials.duplicate(true);remaining[material_kind]=int(remaining.get(material_kind,0))-ingredient
			return {"ok":true,"error":"","state":next,"organium":organium-price,"materials":remaining,"spent":price,"ingredient":ingredient,"ingredient_kind":material_kind}
	return {"ok":false,"error":"Орган не найден","state":state.duplicate(true),"organium":organium,"materials":materials.duplicate(true),"spent":0}

static func dismantle(state: Dictionary,id: String,organium: int,materials: Dictionary) -> Dictionary:
	if validate(state)!="":return {"ok":false,"error":validate(state),"state":state.duplicate(true),"organium":organium,"materials":materials.duplicate(true)}
	var next=state.duplicate(true)
	for group in ["equipped","stock","reserve"]:
		for part in next[group]:
			if part.id!=id:continue
			var refund=maxi(1,int(floor(0.35*pow(float(maxi(0,int(part.rank)-1)),0.72))))
			next[group]=next[group].filter(func(candidate):return candidate.id!=id)
			var stock=materials.duplicate(true);stock[part.kind]=mini(9007199254740991,int(stock.get(part.kind,0))+maxi(1,int(part.rank)))
			return {"ok":true,"error":"","state":next,"organium":mini(9007199254740991,organium+refund),"materials":stock,"refund":refund,"kind":part.kind}
	return {"ok":false,"error":"Орган не найден","state":state.duplicate(true),"organium":organium,"materials":materials.duplicate(true)}

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
		part.rank=mini(Catalog.max_rank(kind),int(part.rank)+Catalog.duplicate_rank_gain(grade))
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

static func draft_exchange(state: Dictionary, kind: String, grade: int) -> Dictionary:
	var error = validate(state)
	if not error.is_empty():return _result(state, error)
	if kind not in Catalog.ORGANS or int(state.next_id) >= Slots.MAX_EXACT_INTEGER:
		return _result(state, "Не удалось подготовить орган")
	var next = state.duplicate(true)
	var part = _new_part(next, kind, 1, clampi(grade, 0, 3))
	next.reserve.append(part)
	return _result(next, "", "reserve", part.id)

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
			matching=next.equipped.filter(func(part):return part.kind==kind)
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
		var specializations=build.get("specializations",{})
		var normalized=Catalog.legacy_specialization(kind,str(specializations.get(kind,""))) if specializations is Dictionary else ""
		if normalized!="" and not matching.is_empty():matching[0].specialization=normalized
	return _result(next)

static func move(state: Dictionary,id: String,destination: String,replacements: Array=[]) -> Dictionary:
	var error=validate(state)
	if error!="":return _result(state,error)
	if destination=="stock":return Slots.move(state,id,destination,replacements)
	if destination=="body":
		var source_group="stock" if state.stock.any(func(part):return str(part.id)==id) else "reserve"
		var incoming_list=state[source_group].filter(func(part):return str(part.id)==id)
		if incoming_list.size()!=1:return _result(state,"Орган не найден в запасе или архиве")
		var removed=[];var seen={}
		for replacement in replacements:
			if not replacement is String or replacement in seen:return _result(state,"Некорректная замена органов")
			var found=state.equipped.filter(func(part):return str(part.id)==replacement)
			if found.size()!=1:return _result(state,"Орган для замены не найден в теле")
			seen[replacement]=true;removed.append(found[0])
		var incoming=incoming_list[0]
		var cells=Slots.used_cells(state)-Slots.used_cells({"equipped":removed})+int(incoming.cells)
		if cells>int(state.body_capacity):return _result(state,"Не хватает ячеек тела даже после выбранной замены")
		var next=state.duplicate(true)
		next[source_group]=next[source_group].filter(func(part):return str(part.id)!=id)
		next.equipped=next.equipped.filter(func(part):return not str(part.id) in seen)
		next.equipped.append(incoming.duplicate(true))
		for outgoing in removed:
			if next.stock.size()<int(next.stock_capacity):next.stock.append(outgoing.duplicate(true))
			else:next.reserve.append(outgoing.duplicate(true))
		error=validate(next)
		return _result(next) if error=="" else _result(state,error)
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
