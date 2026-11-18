extends RefCounted
# Family navigation is presentation only. All persistence is owned by the caller.
const Genome=preload("res://core/genome.gd")
const Legacy=preload("res://core/genome_legacy.gd")
const Painter=preload("res://game/organism_painter.gd")
const GREEN=Color("9ce3cf")
const MUTED=Color("a5c4c4")

class Portrait extends Control:
	var recipe: Dictionary={}
	var organs: Dictionary={}
	var painter=Painter.new()
	var time=0.0
	func _ready():mouse_filter=Control.MOUSE_FILTER_IGNORE
	func _process(dt):
		time+=dt
		if is_visible_in_tree():queue_redraw()
	func _draw():
		if Genome.validate(recipe):
			painter.paint(self,size/2,minf(size.x,size.y)*0.30,recipe,organs,time,"player",true,null,[],Genome.colors(recipe)[0],0.0,1.0,0.2,{"qualities":{},"evolved":{}})

static func recipe_for(entry: Dictionary) -> Dictionary:
	var saved=entry.get("recipe",{})
	if saved is Dictionary and Genome.validate(saved):return saved.duplicate(true)
	var recipe=Genome.create(absi(str(entry.get("id",entry.get("form","predator"))).hash())%100000,0,"player",0)
	match str(entry.get("form","predator")):
		"predator":recipe.family=1
		"toxic":recipe.family=0;recipe.tissue=2
		"colony":recipe.family=4
	return recipe

static func action(hud,parent,text: String,callbacks: Dictionary,key: String,args: Array=[],enabled: bool=true,primary: bool=false):
	var callback: Callable=callbacks.get(key,Callable())
	var b=hud.button(text,func():
		if callback.is_valid():callback.callv(args)
	,primary)
	b.set_meta("compact_action",true)
	b.name=key+"_"+(str(args[0]) if not args.is_empty() else "action")
	b.custom_minimum_size.y=50
	b.add_theme_font_size_override("font_size",20)
	for state in ["normal","hover","pressed","disabled"]:
		var style=b.get_theme_stylebox(state).duplicate()
		style.content_margin_top=4;style.content_margin_bottom=4
		b.add_theme_stylebox_override(state,style)
	b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	b.disabled=not enabled or not callback.is_valid()
	parent.add_child(b)
	return b

static func populate(hud,box,entries: Array,callbacks: Dictionary,pages: Dictionary={}):
	box.add_theme_constant_override("separation",8)
	var title=hud.label("МИКРОГЕН · Семьи",30,GREEN)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var groups=hud.row()
	box.add_child(groups)
	var alive=[]
	var ancestral=[]
	for entry in entries:
		if entry.get("alive",false):alive.append(entry)
		else:ancestral.append(entry)
	_group(hud,groups,"Живые организмы","alive",alive,callbacks,int(pages.get("alive",0)))
	_group(hud,groups,"Семьи · подготовка","ancestral",ancestral,callbacks,int(pages.get("ancestral",0)))
	action(hud,box,"Новый организм",callbacks,"new",[],true,true)
	var nav=hud.row();box.add_child(nav)
	for item in [["Геном","genome"],["Атлас","atlas"],["Помощь","help"],["Обновления","updates"],["Выход","exit"]]:
		action(hud,nav,item[0],callbacks,item[1])

static func _group(hud,parent,title: String,group: String,entries: Array,callbacks: Dictionary,page: int):
	var card=hud.card();parent.add_child(card)
	var column=VBoxContainer.new();column.add_theme_constant_override("separation",6);card.add_child(column)
	column.add_child(hud.label(title,24,GREEN))
	var index=clampi(page,0,maxi(0,entries.size()-1))
	if entries.is_empty():
		var prompt=hud.label("Нет живых организмов.\nСоздайте новую семью." if group=="alive" else "Здесь появятся семьи\nдля следующего поколения.",20,MUTED,true)
		prompt.custom_minimum_size.y=238
		column.add_child(prompt)
	else:
		var entry: Dictionary=entries[index]
		var id=str(entry.get("id",""))
		var form: Dictionary=Legacy.FORMS.get(str(entry.get("form","predator")),Legacy.FORMS.predator)
		var line=hud.row();column.add_child(line)
		var art=Portrait.new();art.name="Portrait_"+id;art.recipe=recipe_for(entry);art.organs=entry.get("organs",{form.organ:1});art.custom_minimum_size=Vector2(140,140)
		line.add_child(art)
		var text=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(text)
		text.add_child(hud.label(str(entry.get("name","Семья")),24,GREEN,true))
		text.add_child(hud.label(form.name+" форма",20,MUTED,true))
		text.add_child(hud.label("Поколение %d · жизни %d"%[int(entry.get("generation",0)),int(entry.get("runs",0))],20,MUTED,true))
		text.add_child(hud.label("Ядра %d · рекорд %d с"%[int(entry.get("cores",0)),int(entry.get("best",0))],20,MUTED,true))
		column.add_child(hud.label("Жизнь сохранена · один наследник" if group=="alive" else ("Жизнь завершена · новый наследник" if entry.get("ended",false) else "Готова к первой жизни · сохранения нет"),20,MUTED,true))
		var buttons=hud.row();column.add_child(buttons)
		action(hud,buttons,"Продолжить" if group=="alive" else "Подготовить",callbacks,"resume" if group=="alive" else "prepare",[id],true,true)
		action(hud,buttons,"Удалить…",callbacks,"delete",[id])
	var pager=hud.row();column.add_child(pager)
	var prev=action(hud,pager,"‹",callbacks,"page",[group,maxi(0,index-1)],index>0);prev.name="page_"+group+"_prev"
	var counter=hud.label("%d / %d"%[index+1 if not entries.is_empty() else 0,entries.size()],20,MUTED)
	counter.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;counter.size_flags_horizontal=Control.SIZE_EXPAND_FILL;pager.add_child(counter)
	var next=action(hud,pager,"›",callbacks,"page",[group,index+1],index+1<entries.size());next.name="page_"+group+"_next"
