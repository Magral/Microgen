extends RefCounted
# View modules never change inventory or simulation state.
const Home=preload("res://ui/family_home.gd")
const Art=preload("res://ui/organ_art.gd")
const Catalog=preload("res://core/catalog.gd")
const Legacy=preload("res://core/genome_legacy.gd")
const Rewards=preload("res://core/rewards.gd")
const GREEN=Color("9ce3cf")
const MUTED=Color("a5c4c4")

class LivingArt extends "res://ui/organ_art.gd":
	func _draw():
		var zoom=1.8
		draw_set_transform(size*0.5*(1.0-zoom),0,Vector2.ONE*zoom)
		super._draw()

static func _action(hud,parent,text: String,callbacks: Dictionary,key: String,args: Array=[],enabled: bool=true,primary: bool=false):
	return Home.action(hud,parent,text,callbacks,key,args,enabled,primary)

static func _name(part: Dictionary) -> String:
	return str(Catalog.item(str(part.get("kind","devour"))).get("name",part.get("kind","Орган")))

static func _used(parts: Array) -> int:
	var total=0
	for part in parts:total+=int(part.get("cells",1))
	return total

static func _caption(part: Dictionary) -> String:
	var cost=maxi(1,int(part.get("cells",1)))
	return "%s · %d кл.\nРанг %d · %s"%[_name(part),cost,int(part.get("rank",1)),Rewards.quality_name(int(part.get("quality",0)))]

static func _pager(hud,parent,callbacks: Dictionary,key: String,page: int,count: int,per_page: int):
	var pages=maxi(1,ceili(float(count)/per_page))
	var r=hud.row();parent.add_child(r)
	var previous=_action(hud,r,"‹",callbacks,key,[maxi(0,page-1)],page>0);previous.name=key+"_prev"
	var label=hud.label("%d / %d"%[page+1,pages],20,MUTED);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;r.add_child(label)
	var next=_action(hud,r,"›",callbacks,key,[page+1],page+1<pages);next.name=key+"_next"
	return r

static func _part_button(hud,parent,part: Dictionary,callbacks: Dictionary,key: String="part",selected: bool=false):
	var id=str(part.get("id",""))
	var cost=maxi(1,int(part.get("cells",1)))
	var label=("✓ " if selected else ("✧ " if part.get("preferred",false) else ""))+_name(part)+"\n"+"Занимает %d кл."%cost
	var b=_action(hud,parent,label,callbacks,key,[id])
	for state in ["normal","hover","pressed","disabled"]:
		var style=b.get_theme_stylebox(state).duplicate()
		style.content_margin_top=2;style.content_margin_bottom=2
		b.add_theme_stylebox_override(state,style)
	b.set_meta("part_id",id);b.set_meta("cells",cost)
	return b

static func _preview(parent,model: Dictionary,sim,height: float=250):
	var art
	if sim!=null:
		art=LivingArt.new();art.sim=sim
	else:
		art=Home.Portrait.new();art.recipe=Home.recipe_for(model)
		var organs={}
		for part in model.get("equipped",[]):organs[str(part.get("kind","devour"))]=int(part.get("rank",1))
		if organs.is_empty():organs={Legacy.FORMS.get(str(model.get("form","predator")),Legacy.FORMS.predator).organ:1}
		art.organs=organs
	art.name="LivingPreview"
	art.custom_minimum_size=Vector2(260,height)
	art.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(art)
	return art

static func populate(hud,box,model: Dictionary,sim,callbacks: Dictionary,page: int=0):
	box.add_theme_constant_override("separation",6)
	var equipped: Array=model.get("equipped",[])
	var stock: Array=model.get("stock",[])
	var capacity=int(model.get("body_capacity",8))
	var form: Dictionary=Legacy.FORMS.get(str(model.get("form","predator")),Legacy.FORMS.predator)
	box.add_child(hud.label("%s · %s · Тело %d/%d кл."%[str(model.get("family_name","Организм")),form.name,_used(equipped),capacity],24,GREEN,true))
	var scene=hud.row();box.add_child(scene)
	var left=VBoxContainer.new();left.custom_minimum_size.x=250;left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scene.add_child(left)
	_preview(scene,model,sim)
	var right=VBoxContainer.new();right.custom_minimum_size.x=250;right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scene.add_child(right)
	var body_cells=[]
	for part in equipped:
		for offset in range(maxi(1,int(part.get("cells",1)))):body_cells.append({"part":part,"offset":offset})
	var total_cells=maxi(capacity,body_cells.size())
	var index=clampi(page,0,maxi(0,ceili(float(total_cells)/8)-1))
	for slot in range(8):
		var parent=left if slot<4 else right
		var item_index=index*8+slot
		if item_index>=total_cells:continue
		var cell: Dictionary=body_cells[item_index] if item_index<body_cells.size() else {}
		if not cell.is_empty():
			var part: Dictionary=cell.part.duplicate()
			part.preferred=str(part.get("kind",""))==str(form.organ)
			var button=_part_button(hud,parent,part,callbacks)
			if int(cell.offset)>0:
				button.name="part_"+str(part.id)+"_cell_"+str(cell.offset)
				button.text="↳ "+_name(part)+"\nКлетка %d/%d"%[int(cell.offset)+1,int(part.get("cells",1))]
		else:
			var empty=_action(hud,parent,"+ Клетка %d\n✧ %s"%[item_index+1,Catalog.item(form.organ).name],callbacks,"empty_body")
			empty.name="empty_body_cell_"+str(item_index)
	if total_cells>8:_pager(hud,box,callbacks,"page",index,total_cells,8)
	var stockrow=hud.row();box.add_child(stockrow)
	stockrow.add_child(hud.label("Запас %d/%d мест"%[stock.size(),int(model.get("stock_capacity",3))],20,MUTED))
	var stock_capacity=int(model.get("stock_capacity",3))
	var stock_page=clampi(int(model.get("stock_page",0)),0,maxi(0,ceili(float(stock_capacity)/3)-1))
	for i in range(stock_page*3,mini(stock_capacity,stock_page*3+3)):
		if i<stock.size():_part_button(hud,stockrow,stock[i],callbacks)
		else:
			var empty=_action(hud,stockrow,"+ Запас %d"%[i+1],callbacks,"empty_stock")
			empty.name="empty_stock_cell_"+str(i)
	if stock_capacity>3:_pager(hud,box,callbacks,"stock_page",stock_page,stock_capacity,3)
	var nav=hud.row();box.add_child(nav)
	_action(hud,nav,"Назад",callbacks,"back")
	_action(hud,nav,"Геном",callbacks,"legacy")
	_action(hud,nav,"Сводка",callbacks,"mutations")
	if not model.get("live",false):
		_action(hud,nav,"Архив",callbacks,"archive")
		_action(hud,nav,"Облик",callbacks,"reroll")
		_action(hud,nav,"Начать жизнь",callbacks,"start",[],true,true)

static func forms(hud,box,callbacks: Dictionary):
	box.add_child(hud.label("Форма задаёт тело и мягкое предпочтение органов.",20,MUTED,true))
	var row=hud.row();box.add_child(row)
	for id in ["predator","toxic","colony"]:
		var form: Dictionary=Legacy.FORMS[id]
		var card=hud.card();row.add_child(card)
		var col=VBoxContainer.new();card.add_child(col)
		_preview(col,{"id":"base-"+id,"form":id},null,180)
		col.add_child(hud.label(form.name,24,GREEN))
		col.add_child(hud.label(form.desc,20,MUTED,true))
		_action(hud,col,"Выбрать",callbacks,"choose",[id],true,true)
	_action(hud,box,"Назад",callbacks,"back")

static func detail(hud,box,part: Dictionary,sim,callbacks: Dictionary):
	var row=hud.row();box.add_child(row)
	var kind=str(part.get("kind","devour"))
	var art
	if sim!=null:
		art=LivingArt.new();art.sim=sim
	else:
		art=Home.Portrait.new();art.recipe=Home.recipe_for(part);art.organs={kind:int(part.get("rank",1))}
	art.name="PartImage";art.custom_minimum_size=Vector2(300,250);row.add_child(art)
	var col=VBoxContainer.new();col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(col)
	col.add_child(hud.label(_caption(part),24,GREEN,true))
	var tabs=hud.row();col.add_child(tabs)
	for choice in [["Показатели","stats"],["Связи","synergies"],["Развитие","growth"]]:_action(hud,tabs,choice[0],callbacks,"tab",[choice[1]],choice[1]!=str(part.get("detail_tab","stats")))
	match str(part.get("detail_tab","stats")):
		"synergies":col.add_child(hud.label(str(part.get("synergy_text","Нет известных сочетаний")),20,MUTED,true))
		"growth":col.add_child(hud.label(str(part.get("growth_text","Развитие этого органа продолжается в следующих выпусках")),20,GREEN,true))
		_:
			col.add_child(hud.label(str(Catalog.item(kind).get("desc","")),20,MUTED,true))
			if part.has("effect_text"):col.add_child(hud.label(part.effect_text,20,GREEN,true))
			col.add_child(hud.label("Урон указан до сопротивления ткани врага.",20,MUTED,true))
	var nav=hud.row();box.add_child(nav)
	_action(hud,nav,"Назад",callbacks,"back")
	if part.get("can_equip",false):_action(hud,nav,"В тело",callbacks,"equip",[],true,true)
	if part.get("can_unequip",false):_action(hud,nav,"В запас",callbacks,"unequip")
	if part.get("can_archive",false):_action(hud,nav,"В архив",callbacks,"archive")

static func picker(hud,box,parts: Array,callbacks: Dictionary,page: int=0):
	box.add_child(hud.label("Выбрать орган",26,GREEN))
	var index=clampi(page,0,maxi(0,ceili(float(parts.size())/4)-1))
	var grid=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",8);box.add_child(grid)
	for part in parts.slice(index*4,index*4+4):
		var card=hud.card();grid.add_child(card)
		var row=hud.row();card.add_child(row)
		var art=Home.Portrait.new();art.recipe=Home.recipe_for(part);art.organs={str(part.get("kind","devour")):int(part.get("rank",1))};art.custom_minimum_size=Vector2(70,90);row.add_child(art)
		var b=_action(hud,row,("✧ " if part.get("preferred",false) else "")+_caption(part),callbacks,"choose",[str(part.get("id",""))]);b.custom_minimum_size.y=90
	if parts.is_empty():box.add_child(hud.label("Подходящих органов пока нет.",22,MUTED))
	_pager(hud,box,callbacks,"page",index,parts.size(),4)
	_action(hud,box,"Назад",callbacks,"back")

static func exchange(hud,box,state,incoming_id,selected: Array,error: String,callbacks: Dictionary,page: int=0):
	var equipped: Array=state.get("equipped",[])
	var stock: Array=state.get("stock",[])
	var incoming={}
	for part in stock+state.get("reserve",[]):
		if str(part.get("id",""))==str(incoming_id):incoming=part;break
	var removed=[]
	for part in equipped:
		if str(part.get("id","")) in selected:removed.append(part)
	var body_after=_used(equipped)-_used(removed)+int(incoming.get("cells",0))
	var stock_after=stock.size()-(1 if stock.any(func(p):return str(p.get("id",""))==str(incoming_id)) else 0)+removed.size()
	box.add_child(hud.label("Обмен · выберите органы тела",26,GREEN))
	box.add_child(hud.label("Тело %d → %d/%d кл. · Запас %d → %d/%d мест"%[_used(equipped),body_after,int(state.get("body_capacity",0)),stock.size(),stock_after,int(state.get("stock_capacity",3))],20,MUTED,true))
	var index=clampi(page,0,maxi(0,ceili(float(equipped.size())/6)-1))
	var grid=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",12);grid.add_theme_constant_override("v_separation",8);box.add_child(grid)
	for part in equipped.slice(index*6,index*6+6):_part_button(hud,grid,part,callbacks,"toggle",str(part.get("id","")) in selected)
	if error!="":box.add_child(hud.label(error,20,Color("efb6a9"),true))
	_pager(hud,box,callbacks,"page",index,equipped.size(),6)
	var nav=hud.row();box.add_child(nav)
	_action(hud,nav,"Назад",callbacks,"back")
	_action(hud,nav,"Применить",callbacks,"apply",[],error=="",true)
