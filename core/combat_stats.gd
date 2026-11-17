extends RefCounted
# Actual health changes only. Attribution is descriptive and never changes gameplay.
const HISTORY_LIMIT=32
const SOURCE_LIMIT=32
const OTHER_SOURCE_KEY="__other_sources__"
const OTHER_SOURCE_NAME="Прочие источники"

static func create() -> Dictionary:
	return {"tracking_start":0.0,"damage_dealt":0.0,"damage_taken":0.0,"blocked":0.0,"healed":0.0,"organs":{},"kills_by_source":{},"history":[],"sources":{}}

static func _number(value) -> float:
	if not (value is float or value is int): return 0.0
	var result=float(value)
	return maxf(0.0,result) if is_finite(result) else 0.0

static func _organ(stats: Dictionary,source: String) -> Dictionary:
	if not stats.organs.has(source): stats.organs[source]={"damage":0.0,"hits":0,"kills":0}
	return stats.organs[source]

# Summaries track source types; individual actor identities belong only to history.
static func _record_source(sources: Dictionary,kind: String,name: String,damage: float,hits: int,overflow: bool=false):
	var category=kind if not kind.is_empty() else "unknown"
	var label=name if not name.strip_edges().is_empty() else "Неизвестный источник"
	var key="%s:%s" % [category,label]
	var named_count=sources.size()-(1 if sources.has(OTHER_SOURCE_KEY) else 0)
	if overflow or (not sources.has(key) and named_count>=SOURCE_LIMIT):
		key=OTHER_SOURCE_KEY
		category="other"
		label=OTHER_SOURCE_NAME
	if not sources.has(key): sources[key]={"name":label,"kind":category,"source_id":"","damage":0.0,"hits":0}
	sources[key].damage+=damage
	sources[key].hits+=hits

static func record_damage(stats: Dictionary,source: String,amount: float):
	var actual=_number(amount)
	if actual<=0.0: return
	stats.damage_dealt+=actual
	var organ=_organ(stats,source)
	organ.damage+=actual
	organ.hits+=1

static func record_kill(stats: Dictionary,source: String):
	var organ=_organ(stats,source)
	organ.kills+=1
	stats.kills_by_source[source]=int(stats.kills_by_source.get(source,0))+1

static func record_heal(stats: Dictionary,actual: float):
	stats.healed+=_number(actual)

static func record_taken(stats: Dictionary,time: float,amount: float,blocked: float,kind: String,name: String,pos: Vector2,source_id) -> Dictionary:
	var actual=_number(amount)
	stats.blocked+=_number(blocked)
	if actual<=0.0: return {}
	stats.damage_taken+=actual
	var label=name if not name.strip_edges().is_empty() else "Неизвестный источник"
	var category=kind if not kind.is_empty() else "unknown"
	var entry={"time":_number(time),"amount":actual,"kind":category,"name":label,"pos":[pos.x if is_finite(pos.x) else 0.0,pos.y if is_finite(pos.y) else 0.0],"source_id":source_id}
	var history: Array=stats.history
	if not history.is_empty():
		var last: Dictionary=history.back()
		if last.kind==category and last.name==label and last.source_id==source_id and time>=float(last.time) and time-float(last.time)<=1.0:
			entry.amount+=float(last.amount)
			history.pop_back()
	history.append(entry)
	while history.size()>HISTORY_LIMIT: history.pop_front()
	_record_source(stats.sources,category,label,actual,1)
	return entry

static func restore(data) -> Dictionary:
	var clean=create()
	if not data is Dictionary: return clean
	for key in ["tracking_start","damage_dealt","damage_taken","blocked","healed"]: clean[key]=_number(data.get(key,0))
	if data.get("organs") is Dictionary:
		for id in data.organs:
			var raw=data.organs[id]
			if not raw is Dictionary: continue
			clean.organs[str(id)]={"damage":_number(raw.get("damage",0)),"hits":int(_number(raw.get("hits",0))),"kills":int(_number(raw.get("kills",0)))}
	if data.get("kills_by_source") is Dictionary:
		for id in data.kills_by_source: clean.kills_by_source[str(id)]=int(_number(data.kills_by_source[id]))
	if data.get("history") is Array:
		for raw in data.history:
			if not raw is Dictionary or _number(raw.get("amount",0))<=0: continue
			var pos=raw.get("pos",[0,0])
			if not pos is Array or pos.size()!=2: pos=[0,0]
			var x=float(pos[0]) if pos[0] is float or pos[0] is int else 0.0
			var y=float(pos[1]) if pos[1] is float or pos[1] is int else 0.0
			var label=str(raw.get("name","Неизвестный источник"))
			if label.strip_edges().is_empty(): label="Неизвестный источник"
			clean.history.append({"time":_number(raw.get("time",0)),"amount":_number(raw.amount),"kind":str(raw.get("kind","unknown")),"name":label,"pos":[x if is_finite(x) else 0.0,y if is_finite(y) else 0.0],"source_id":raw.get("source_id","")})
		while clean.history.size()>HISTORY_LIMIT: clean.history.pop_front()
	if data.get("sources") is Dictionary:
		for id in data.sources:
			var raw=data.sources[id]
			if not raw is Dictionary: continue
			_record_source(clean.sources,str(raw.get("kind","unknown")),str(raw.get("name","Неизвестный источник")),_number(raw.get("damage",0)),int(_number(raw.get("hits",0))),str(id)==OTHER_SOURCE_KEY)
	return clean
