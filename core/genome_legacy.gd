extends RefCounted
# Versioned, bounded inheritance. Profile v1 and its economy remain compatible.
const Catalog=preload("res://core/catalog.gd")
const Genome=preload("res://core/genome.gd")
const FORMS={
	"predator":{"name":"Хищная","organ":"devour","branch":"predator","research":"","desc":"Выраженная передняя часть и пасть: сближение и укусы."},
	"toxic":{"name":"Железистая","organ":"acid","branch":"toxic","research":"toxic","desc":"Складчатая мембрана растворяет добычу рядом с телом."},
	"colony":{"name":"Колониальная","organ":"division","branch":"colony","research":"colony","desc":"Живые перемычки связывают доли; почки отделяются в помощников."}}
const TRAITS={
	"elastic":{"name":"Эластичная ткань","research":"elastic","desc":"Разгон и торможение: 0,13 с вместо 0,20 с.","tradeoff":"Контактный урон +8%.","visual":"Вытянутые мягкие доли."},
	"sensory":{"name":"Чувствительная мембрана","research":"sensory","desc":"Обнаружение ценных ресурсов +160.","tradeoff":"Скорость −5%.","visual":"Рецепторные выступы по краю тела."},
	"folds":{"name":"Пищеварительные складки","research":"folds","desc":"Переваривание отделённых фрагментов быстрее на 20%.","tradeoff":"Получаемое лечение −10%.","visual":"Глубокие складки пищеварительной ткани."},
	"receptive":{"name":"Генетическая восприимчивость","research":"receptive","desc":"Вес выбранной ветви мутаций: 1,75 вместо 1,35.","tradeoff":"Получаемая ДНК −5%.","visual":"Светящиеся рецепторные камеры."}}
const RESEARCH={
	"toxic":{"name":"Железистая форма","branch":"structure","cost":4,"requires":[],"effect":"Открывает железистый старт с кислотой.","visual":"Мягкое складчатое тело и железы."},
	"colony":{"name":"Колониальная форма","branch":"structure","cost":8,"requires":[],"effect":"Открывает деление и колониальный старт одной покупкой.","visual":"Доли и живые перемычки."},
	"elastic":{"name":"Эластичная ткань","branch":"adaptation","cost":4,"requires":[],"effect":"Открывает наследственный признак скорости.","visual":"Мягкие вытянутые доли."},
	"sensory":{"name":"Чувствительная мембрана","branch":"adaptation","cost":4,"requires":[],"effect":"Открывает наследственные рецепторы.","visual":"Рецепторные выступы."},
	"folds":{"name":"Пищеварительные складки","branch":"adaptation","cost":6,"requires":["sensory"],"effect":"Открывает наследственный признак усвоения.","visual":"Складки пищеварительной ткани."},
	"receptive":{"name":"Генетическая восприимчивость","branch":"memory","cost":8,"requires":["memory"],"effect":"Открывает предпочтение выбранной ветви мутаций.","visual":"Светящиеся рецепторные камеры."},
	"memory":{"name":"Закрепление памяти","branch":"memory","cost":4,"requires":[],"effect":"Повторные отпечатки дают до 3 знаний на ветвь; каждое заменяет одно ядро исследования.","visual":"Яркое наследственное ядро."}}
const MAX_PENDING_QUEUE=8
const BRANCHES={"structure":"Строение","adaptation":"Приспособление","memory":"Генетическая память"}

static func defaults() -> Dictionary:
	return {"version":1,"generation":0,"research":[],"forms":["predator"],"traits":[],"equipped_traits":[],"selected_form":"predator","selected_imprint":"","morphology_seed":1,"focus":"","knowledge":{"structure":0,"adaptation":0,"memory":0},"imprints":[],"pending":[],"pending_queue":[],"presets":[],"history":[]}

static func _integer(value,fallback: int=0) -> int:
	if not (value is int or value is float): return fallback
	return int(value) if is_finite(float(value)) else fallback

static func _ids(value,allowed: Dictionary,limit: int=32) -> Array:
	var result=[]
	if value is Array:
		for id in value:
			if id is String and id in allowed and id not in result and result.size()<limit: result.append(id)
	return result

static func _imprints(value) -> Array:
	var result=[]
	if not value is Array: return result
	for raw in value:
		if not raw is Dictionary: continue
		var id=str(raw.get("id",""))
		if not valid_imprint(id) or result.any(func(x): return x.id==id): continue
		var recipe=raw.get("recipe",{})
		if not recipe is Dictionary or not Genome.validate(recipe): continue
		var canonical_recipe={}
		for key in ["version","seed","identity","family","palette","lobes","membrane","nuclei","tissue","biome"]: canonical_recipe[key]=_integer(recipe.get(key,0))
		for key in ["phase","rotation","stretch","asymmetry"]: canonical_recipe[key]=float(recipe[key])
		var origin=raw.get("origin",{})
		if not origin is Dictionary: origin={}
		result.append({"id":id,"name":imprint_name(id),"branch":_research_branch(id),"origin":{"generation":maxi(0,_integer(origin.get("generation",0))),"biome":clampi(_integer(origin.get("biome",0)),0,32),"elapsed":maxi(0,_integer(origin.get("elapsed",0)))},"recipe":canonical_recipe,"rank":1,"quality":0})
		if result.size()>=Catalog.ORGANS.size()+TRAITS.size(): break
	return result

static func normalize(profile: Dictionary) -> Dictionary:
	var clean=defaults()
	var raw=profile.get("legacy",{})
	if not raw is Dictionary: raw={}
	clean.generation=maxi(0,_integer(raw.get("generation",0)))
	clean.research=_ids(raw.get("research",[]),RESEARCH)
	# Old division purchase also owns the corresponding form, with no second charge.
	if "division" in profile.get("unlocked",[]) and "colony" not in clean.research: clean.research.append("colony")
	for id in FORMS:
		if FORMS[id].research in clean.research and id not in clean.forms: clean.forms.append(id)
	for id in TRAITS:
		if id in clean.research: clean.traits.append(id)
	for id in _ids(raw.get("equipped_traits",[]),TRAITS,2):
		if id in clean.traits: clean.equipped_traits.append(id)
	var form=str(raw.get("selected_form","predator"))
	if form=="division": form="colony"
	if form in clean.forms: clean.selected_form=form
	clean.morphology_seed=clampi(_integer(raw.get("morphology_seed",1),1),1,2147483646)
	clean.imprints=_imprints(raw.get("imprints",[]))
	clean.pending=_imprints(raw.get("pending",[]))
	var queue=raw.get("pending_queue",[])
	if queue is Array:
		for life in queue:
			var candidates=_imprints(life)
			if not candidates.is_empty() and clean.pending_queue.size()<MAX_PENDING_QUEUE: clean.pending_queue.append(candidates)
	if clean.pending.is_empty() and not clean.pending_queue.is_empty(): clean.pending=clean.pending_queue.pop_front()
	var imprint=str(raw.get("selected_imprint",""))
	if clean.imprints.any(func(x): return x.id==imprint): clean.selected_imprint=imprint
	var focus=str(raw.get("focus",""))
	if focus in RESEARCH and focus not in clean.research: clean.focus=focus
	var knowledge=raw.get("knowledge",{})
	if knowledge is Dictionary:
		for branch in BRANCHES: clean.knowledge[branch]=clampi(_integer(knowledge.get(branch,0)),0,3)
	var presets=raw.get("presets",[])
	if presets is Array:
		for preset in presets:
			if not preset is Dictionary or clean.presets.size()>=6: continue
			var preset_profile=profile.duplicate(true)
			preset_profile.legacy=clean.duplicate(true)
			preset_profile.legacy.presets=[]
			preset_profile.legacy.selected_form=preset.get("form","predator")
			preset_profile.legacy.equipped_traits=preset.get("traits",[])
			preset_profile.legacy.selected_imprint=preset.get("imprint","")
			preset_profile.legacy.morphology_seed=preset.get("seed",1)
			var entry=loadout(preset_profile)
			entry.name=str(preset.get("name","Набор")).left(32)
			clean.presets.append(entry)
	var history=raw.get("history",[])
	if history is Array:
		for entry in history.slice(maxi(0,history.size()-12)):
			if entry is Dictionary: clean.history.append({"generation":maxi(0,_integer(entry.get("generation",0))),"elapsed":maxi(0,_integer(entry.get("elapsed",0))),"outcome":str(entry.get("outcome","")).left(32),"form":str(entry.get("form","predator")),"candidates":_candidate_ids(entry.get("candidates",[]))})
	return clean

static func loadout(profile: Dictionary) -> Dictionary:
	var legacy=normalize(profile)
	var source={}
	for imprint in legacy.imprints:
		if imprint.id==legacy.selected_imprint:source=imprint.recipe.duplicate(true)
	return {"form":legacy.selected_form,"traits":legacy.equipped_traits.duplicate(),"imprint":legacy.selected_imprint,"seed":legacy.morphology_seed,"branch":FORMS[legacy.selected_form].branch,"ancestry_recipe":source}

static func focus_progress(profile: Dictionary,id: String="") -> Dictionary:
	return focus_progress_in(profile,normalize(profile),id)

# One validated snapshot per open panel; research rows reuse it.
static func focus_progress_in(profile: Dictionary,legacy: Dictionary,id: String="") -> Dictionary:
	if id.is_empty(): id=legacy.focus
	if id not in RESEARCH: return {}
	var node=RESEARCH[id]
	var missing=[]
	for requirement in node.requires:
		if requirement not in legacy.research: missing.append(requirement)
	var knowledge=int(legacy.knowledge[node.branch]) if "memory" in legacy.research else 0
	var price=maxi(0,int(node.cost)-knowledge)
	return {"id":id,"cost":price,"cores":maxi(0,_integer(profile.get("cores",0))),"knowledge":knowledge,"remaining":maxi(0,price-_integer(profile.get("cores",0))),"ready":id not in legacy.research and missing.is_empty() and _integer(profile.get("cores",0))>=price,"requires":missing}

static func _candidate_ids(value) -> Array:
	var result=[]
	if value is Array:
		for id in value:
			if id is String and valid_imprint(id) and id not in result: result.append(id)
	return result

static func valid_imprint(id: String) -> bool:
	return id in Catalog.ORGANS or (id.begins_with("trait:") and id.trim_prefix("trait:") in TRAITS)

static func imprint_name(id: String) -> String:
	return TRAITS[id.trim_prefix("trait:")].name if id.begins_with("trait:") else str(Catalog.item(id).get("name",id))

static func _research_branch(organ: String) -> String:
	if organ.begins_with("trait:"): return "memory" if organ=="trait:receptive" else "adaptation"
	return {"predator":"structure","toxic":"adaptation","colony":"memory"}.get(Catalog.item(organ).get("branch","predator"),"structure")

static func can_start(profile: Dictionary) -> bool:
	return normalize(profile).pending_queue.size()<MAX_PENDING_QUEUE

# Caller invokes this only inside the transaction that credits a new finished token.
static func complete(profile: Dictionary,sim) -> bool:
	if str(sim.outcome).is_empty(): return false
	var legacy=normalize(profile)
	legacy.generation+=1
	var candidates=[]
	if sim.elapsed>=60.0:
		for id in sim.build.organs:
			var use=sim.combat_stats.get("organs",{}).get(id,{})
			if sim.build.rank(id)<3 or float(use.get("damage",0))<=0: continue
			candidates.append({"id":id,"name":imprint_name(id),"branch":_research_branch(id),"origin":{"generation":legacy.generation,"biome":sim.world.biome(sim.player),"elapsed":int(sim.elapsed)},"recipe":sim.player_genome.duplicate(true),"rank":1,"quality":0})
		var played_loadout=sim.get("run_loadout")
		if played_loadout is Dictionary and float(sim.combat_stats.get("damage_dealt",0))>0:
			for trait_id in _ids(played_loadout.get("traits",[]),TRAITS,2):
				var id="trait:"+trait_id
				candidates.append({"id":id,"name":imprint_name(id),"branch":_research_branch(id),"origin":{"generation":legacy.generation,"biome":sim.world.biome(sim.player),"elapsed":int(sim.elapsed)},"recipe":sim.player_genome.duplicate(true),"rank":1,"quality":0})
	if not candidates.is_empty() and not legacy.pending.is_empty() and legacy.pending_queue.size()>=MAX_PENDING_QUEUE: return false
	# Keep one explicit choice for every eligible life, preserving each origin.
	if not candidates.is_empty():
		if legacy.pending.is_empty(): legacy.pending=candidates
		else: legacy.pending_queue.append(candidates)
	var ids=[]
	for candidate in candidates: ids.append(candidate.id)
	legacy.history.append({"generation":legacy.generation,"elapsed":int(sim.elapsed),"outcome":str(sim.outcome),"form":str(sim.run_loadout.get("form","ancestral")),"candidates":ids})
	while legacy.history.size()>12: legacy.history.pop_front()
	profile.legacy=legacy
	return true
