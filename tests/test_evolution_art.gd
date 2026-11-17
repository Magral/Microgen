extends SceneTree
const Painter=preload("res://game/organism_painter.gd")
const Genome=preload("res://core/genome.gd")
const Anatomy=preload("res://game/evolution_anatomy.gd")
const Tissue=preload("res://game/tissue_damage.gd")
class Sheet extends Node2D:
	var painter=Painter.new()
	var time=0.0
	const FX=preload("res://game/organic_fx.gd")
	func _draw():
		draw_rect(Rect2(0,0,1280,720),Color("0a202a"))
		var kinds=["tentacle","acid","infection"]
		var labels=["Ловчая корона","Растворяющая мантия","Споровая утроба"]
		var descriptions=["Чувствительные гребни и захват добычи","Живые складки выдавливают кислоту","Камеры наполняются от заражённой пищи"]
		for i in range(3):
			var id=kinds[i];var center=Vector2(210+i*430,345)
			var organs={id:6}
			organs[["magnet","armor","metabolism"][i]]=3
			var state={"evolved":{id:true},"qualities":{id:2},"lashes":{},"spore_charge":int(time)%3,"mantle_flash":sin(time*2)*0.5+0.5}
			if i==0:
				organs.acid=3;organs.infection=3
				var target=center+Vector2(135,-65)
				painter.paint(self,target,22,Genome.create(84,21,"hunter",0),{},time,"hunter",true)
				for limb in range(6):state.lashes[limb]={"tip":target-center+Vector2(0,(-1 if limb%2==0 else 1)*18),"extension":0.65+sin(time*2)*0.30}
			painter.paint(self,center,72,Genome.create(144,i,"player",0),organs,time,"player",true,null,[],Color(-1,-1,-1),0.0,1.0,0.1,state)
			draw_string(ThemeDB.fallback_font,Vector2(40+i*430,100),labels[i],HORIZONTAL_ALIGNMENT_LEFT,400,28,Color("ceecdf"))
			if i==1:FX.paint(self,{"type":"mantle","pos":center,"end":center+Vector2(60,0),"r":72.0,"life":0.30,"max":0.65},Vector2.ZERO,Vector2.ZERO,time)
			var words=descriptions[i].split(" ");var line="";var y=580.0
			for word in words:
				if (line+word).length()>32:
					draw_string(ThemeDB.fallback_font,Vector2(25+i*430,y),line,HORIZONTAL_ALIGNMENT_LEFT,400,19,Color("9fc5bc"));y+=26;line=""
				line+=word+" "
			draw_string(ThemeDB.fallback_font,Vector2(25+i*430,y),line,HORIZONTAL_ALIGNMENT_LEFT,400,19,Color("9fc5bc"))
var failures=0
func check(ok: bool,label: String):
	if not ok:failures+=1;push_error(label)
func _initialize():call_deferred("run")
func run():
	for seed_value in range(12):
		var recipe=Genome.create(seed_value,4,"player",0)
		for hp in [1.0,0.4,0.05]:
			for flags in [{"tentacle":true},{"acid":true},{"infection":true},{"tentacle":true,"acid":true,"infection":true}]:
				var contour=Anatomy.shape(Tissue.contour(Genome.contour(recipe),recipe,hp),flags,1.4,recipe.phase)
				check(not Geometry2D.triangulate_polygon(contour).is_empty(),"evolved tissue preserves safe wound geometry")
	var plain=Genome.contour(Genome.create(44,0,"player",0))
	check(Anatomy.shape(plain,{"tentacle":true,"acid":true,"infection":true},1.0,0,{"tentacle":0.0,"acid":0.0,"infection":0.0})==plain,"zero growth starts from original tissue")
	check(Anatomy.shape(plain,{"tentacle":true},1.0,0,{"tentacle":0.5})!=plain,"intermediate growth visibly reshapes tissue")
	var sheet=Sheet.new();root.size=Vector2i(1280,720);root.add_child(sheet)
	for frame in range(30):sheet.time=frame*0.09;sheet.queue_redraw();await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/Microgen-evolutions.png")
	sheet.queue_free();await process_frame
	print("EVOLUTION ART: %d failures; three evolving anatomies rendered"%failures);quit(0 if failures==0 else 1)
