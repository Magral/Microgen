extends RefCounted
# One normalized snapshot per open panel; writes remain in Store/controller.
const Legacy=preload("res://core/genome_legacy.gd")
const Home=preload("res://ui/family_home.gd")
const Catalog=preload("res://core/catalog.gd")
const GREEN=Color("9ce3cf")
const MUTED=Color("a5c4c4")
const TABS={"research":"Исследования","traits":"Признаки","imprints":"Отпечатки","upgrades":"Наследие","history":"История"}

static func _action(hud,parent,text: String,callbacks: Dictionary,key: String,args: Array=[],enabled: bool=true,primary: bool=false):
	return Home.action(hud,parent,text,callbacks,key,args,enabled,primary)

static func _card(hud,parent,id: String):
	var card=hud.card();card.name="Entry_"+id;parent.add_child(card)
	return card

static func _column(parent):
	var col=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;col.add_theme_constant_override("separation",5);parent.add_child(col)
	return col

static func _pager(hud,box,callbacks: Dictionary,page: int,count: int,per_page: int):
	var row=hud.row();box.add_child(row)
	var previous=_action(hud,row,"‹",callbacks,"page",[maxi(0,page-1)],page>0);previous.name="page_prev"
	var label=hud.label("%d / %d"%[page+1,maxi(1,ceili(float(count)/per_page))],20,MUTED);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
	var next=_action(hud,row,"›",callbacks,"page",[page+1],(page+1)*per_page<count);next.name="page_next"

static func populate(hud,box,profile: Dictionary,callbacks: Dictionary,tab: String="research",page: int=0):
	var state=Legacy.normalize(profile)
	box.add_theme_constant_override("separation",6)
	if tab not in TABS:tab="research"
	var tabs=hud.row();box.add_child(tabs)
	for id in TABS:_action(hud,tabs,TABS[id],callbacks,"tab",[id],id!=tab)
	var ids=[]
	var per_page=3
	match tab:
		"research":ids=Legacy.RESEARCH.keys();per_page=2
		"traits":ids=Legacy.TRAITS.keys();per_page=2
		"imprints":ids=state.imprints
		"upgrades":ids=["health","collect","regen"]
		"history":ids=state.history
	var index=clampi(page,0,maxi(0,ceili(float(ids.size())/per_page)-1))
	var visible=ids.slice(index*per_page,index*per_page+per_page)
	var content
	if tab in ["traits","imprints"]:
		content=hud.row();box.add_child(content)
	else:content=_column(box)
	if visible.is_empty():content.add_child(hud.label("Здесь пока нет записей.",22,MUTED,true))
	match tab:
		"research":
			for id in visible:_research(hud,content,profile,state,id,callbacks)
		"traits":
			box.add_child(hud.label("Выбрано признаков %d/2"%state.equipped_traits.size(),20,MUTED))
			for id in visible:_trait(hud,content,state,id,callbacks)
		"imprints":
			for item in visible:_imprint(hud,content,item,callbacks,"imprint",str(state.selected_imprint)==str(item.id))
			_action(hud,box,"Без отпечатка"+(" · выбрано" if str(state.selected_imprint)=="" else ""),callbacks,"imprint",[""],str(state.selected_imprint)!="")
		"upgrades":
			box.add_child(hud.label("Совместимые улучшения линии · предел каждого 5",20,MUTED,true))
			for id in visible:_upgrade(hud,content,profile,id,callbacks)
		"history":
			for life in visible:
				var col=_column(_card(hud,content,str(life.generation)))
				var form=Legacy.FORMS.get(str(life.form),Legacy.FORMS.predator)
				col.add_child(hud.label("Поколение %d · %s · %d:%02d · %s"%[int(life.generation),form.name,int(life.elapsed)/60,int(life.elapsed)%60,"победа" if life.outcome=="victory" else "жизнь завершена"],22,GREEN,true))
	_pager(hud,box,callbacks,index,ids.size(),per_page)
	var footer=hud.row();box.add_child(footer)
	_action(hud,footer,"Назад",callbacks,"back")
	_action(hud,footer,"Отпечатки · %d ожидают · ещё поколений %d"%[state.pending.size(),state.pending_queue.size()],callbacks,"pending")

static func _research(hud,parent,profile: Dictionary,state: Dictionary,id: String,callbacks: Dictionary):
	var data: Dictionary=Legacy.RESEARCH[id]
	var progress=Legacy.focus_progress_in(profile,state,id)
	var complete=id in state.research
	var row=hud.row();_card(hud,parent,id).add_child(row)
	var col=_column(row)
	col.add_child(hud.label(data.name+(" · изучено" if complete else " · %d ядер · есть %d"%[progress.cost,progress.cores]),22,GREEN,true))
	col.add_child(hud.label(data.effect,20,MUTED,true))
	var required=[]
	for prerequisite in data.requires:required.append(("✓ " if prerequisite in state.research else "◇ ")+Legacy.RESEARCH[prerequisite].name)
	col.add_child(hud.label("Условия: "+("нет" if required.is_empty() else ", ".join(required))+" · знание %d"%progress.knowledge,20,MUTED,true))
	var actions=_column(row);actions.custom_minimum_size.x=190;actions.size_flags_horizontal=Control.SIZE_SHRINK_END
	_action(hud,actions,"Изучено" if complete else "Исследовать",callbacks,"research",[id],not complete and progress.ready,true)
	_action(hud,actions,"Цель выбрана" if state.focus==id else "Отслеживать",callbacks,"focus",[id],not complete and state.focus!=id)

static func _trait(hud,parent,state: Dictionary,id: String,callbacks: Dictionary):
	var data: Dictionary=Legacy.TRAITS[id]
	var col=_column(_card(hud,parent,id))
	var selected=id in state.equipped_traits
	var unlocked=id in state.traits
	col.add_child(hud.label(data.name+(" · выбран" if selected else ""),23,GREEN,true))
	col.add_child(hud.label(data.desc,20,MUTED,true))
	col.add_child(hud.label("Ограничение: "+data.tradeoff,20,Color("efb6a9"),true))
	col.add_child(hud.label(data.visual,20,MUTED,true))
	_action(hud,col,"Убрать" if selected else ("Выбрать" if unlocked else "Нужно исследование"),callbacks,"trait",[id],unlocked and (selected or state.equipped_traits.size()<2))

static func _imprint(hud,parent,item: Dictionary,callbacks: Dictionary,key: String,selected: bool=false):
	var col=_column(_card(hud,parent,str(item.id)))
	var id=str(item.id)
	var art=Home.Portrait.new();art.recipe=Home.recipe_for(item);art.custom_minimum_size=Vector2(0,60)
	var organ=id if not id.begins_with("trait:") else {"elastic":"regen","sensory":"magnet","folds":"devour","receptive":"catalysis"}.get(id.trim_prefix("trait:"),"regen")
	art.organs={organ:1};col.add_child(art)
	col.add_child(hud.label(Legacy.imprint_name(id)+(" · выбран" if selected else ""),22,GREEN,true))
	var origin: Dictionary=item.get("origin",{})
	var biome=int(origin.get("biome",0))
	var area="Токсичная зона" if biome==1 else ("Питательная среда" if biome==0 else "Биом %d"%biome)
	col.add_child(hud.label("Поколение %d · %d сек.\n%s"%[int(origin.get("generation",0)),int(origin.get("elapsed",0)),area],20,MUTED,true))
	col.add_child(hud.label("Особенность тела" if id.begins_with("trait:") else "Потомок: ранг 1\nобычное качество",20,MUTED,true))
	_action(hud,col,"Выбран" if selected else ("Сохранить" if key=="claim" else "Передать"),callbacks,key,[id],not selected)

static func _upgrade(hud,parent,profile: Dictionary,id: String,callbacks: Dictionary):
	var rank=clampi(int(profile.get("upgrades",{}).get(id,0)),0,5)
	var next=mini(rank+1,5)
	var text={"health":"Здоровье +%d → +%d HP"%[rank*5,next*5],"collect":"Радиус сбора +%d → +%d"%[rank*8,next*8],"regen":"Регенерация +%.1f → +%.1f HP/с"%[rank*0.1,next*0.1]}[id]
	var row=hud.row();_card(hud,parent,id).add_child(row)
	var label=hud.label(text+" · %d/5"%rank,22,GREEN,true);row.add_child(label)
	var b=_action(hud,row,"Предел достигнут" if rank>=5 else "Улучшить · %d ядер"%(4+rank*4),callbacks,"upgrade",[id],rank<5 and int(profile.get("cores",0))>=4+rank*4)
	b.size_flags_horizontal=Control.SIZE_SHRINK_END;b.custom_minimum_size.x=260

static func pending(hud,box,profile: Dictionary,callbacks: Dictionary,page: int=0):
	var state=Legacy.normalize(profile)
	box.add_theme_constant_override("separation",6)
	box.add_child(hud.label("Один отпечаток · остальные кандидаты этого поколения исчезнут.",22,GREEN,true))
	box.add_child(hud.label("Можно выбрать позже: кандидаты сохранятся. Ещё поколений: %d."%state.pending_queue.size(),20,MUTED,true))
	var index=clampi(page,0,maxi(0,ceili(float(state.pending.size())/3)-1))
	var row=hud.row();box.add_child(row)
	for item in state.pending.slice(index*3,index*3+3):_imprint(hud,row,item,callbacks,"claim")
	if state.pending.is_empty():row.add_child(hud.label("Нет ожидающих отпечатков.",22,MUTED,true))
	_pager(hud,box,callbacks,index,state.pending.size(),3)
	_action(hud,box,"Выбрать позже",callbacks,"back")
