extends RefCounted
# Pure transactions: body cells and stock positions are different capacities.
# Identity/properties remain attached to each organ throughout every exchange.
const MAX_EXACT_INTEGER=9007199254740991

static func _count(value,minimum: int=0) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=minimum and value<=MAX_EXACT_INTEGER

static func used_cells(state: Dictionary) -> int:
	# Requires organ arrays with validated positive integer cell costs.
	# validate() checks record shapes/costs before calling this helper.
	var total=0
	for part in state.get("equipped",[]):
		var cells=int(part.get("cells",0))
		if cells>MAX_EXACT_INTEGER-total:return MAX_EXACT_INTEGER+1
		total+=cells
	return total

static func validate(state: Dictionary) -> String:
	if not _count(state.get("body_capacity"),1) or not _count(state.get("stock_capacity")):return "Некорректная вместимость"
	if not state.get("equipped") is Array or not state.get("stock") is Array:return "Некорректный список органов"
	var ids={}
	for part in state.equipped+state.stock:
		if not part is Dictionary:return "Некорректный орган"
		var id=part.get("id")
		if not id is String or id.is_empty() or id in ids:return "Повторяющийся или отсутствующий орган"
		if not _count(part.get("cells"),1):return "Некорректный размер органа"
		ids[id]=true
	if used_cells(state)>int(state.body_capacity):return "Не хватает ячеек тела"
	if state.stock.size()>int(state.stock_capacity):return "Запас заполнен"
	return ""

static func _result(state: Dictionary,error: String="") -> Dictionary:
	return {"ok":error.is_empty(),"error":error,"state":state.duplicate(true)}

static func move(state: Dictionary,id: String,destination: String,replacements: Array=[]) -> Dictionary:
	var error=validate(state)
	if error!="":return _result(state,error)
	if destination not in ["body","stock"]:return _result(state,"Неизвестное место установки")
	var source=state.stock if destination=="body" else state.equipped
	var incoming=source.filter(func(part):return part.id==id)
	if incoming.size()!=1:return _result(state,"Орган не найден в исходном месте")
	if destination=="stock" and not replacements.is_empty():return _result(state,"Замена применима только к телу")
	var seen={}
	for replacement in replacements:
		if not replacement is String or replacement in seen or not state.equipped.any(func(part):return part.id==replacement):return _result(state,"Некорректная замена органов")
		seen[replacement]=true
	var next=state.duplicate(true)
	if destination=="body":
		next.stock=next.stock.filter(func(part):return part.id!=id)
		for replacement in replacements:
			var outgoing=next.equipped.filter(func(part):return part.id==replacement)[0]
			next.stock.append(outgoing)
		next.equipped=next.equipped.filter(func(part):return part.id not in seen)
		next.equipped.append(incoming[0].duplicate(true))
	else:
		next.equipped=next.equipped.filter(func(part):return part.id!=id)
		next.stock.append(incoming[0].duplicate(true))
	error=validate(next)
	return _result(next) if error=="" else _result(state,error)

static func expand(state: Dictionary,target: String) -> Dictionary:
	var error=validate(state)
	if error!="":return _result(state,error)
	if target not in ["body","stock"]:return _result(state,"Неизвестный тип расширения")
	var key=target+"_capacity"
	if int(state[key])>=MAX_EXACT_INTEGER:return _result(state,"Недопустимая вместимость")
	var next=state.duplicate(true)
	next[key]=int(next[key])+1
	return _result(next)
