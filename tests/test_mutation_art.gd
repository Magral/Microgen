extends SceneTree
const Painter=preload("res://game/organism_painter.gd")
const Catalog=preload("res://core/catalog.gd")
const Genome=preload("res://core/genome.gd")
class Sheet extends Node2D:
	var painter=Painter.new()
	var time=0.0
	func _draw():
		draw_rect(Rect2(0,0,1280,720),Color("0a202a"))
		var ids=Catalog.ORGANS.keys()+Catalog.ADAPTATIONS.keys()
		for i in range(ids.size()):
			var id=ids[i];var center=Vector2(105+(i%6)*211,110+int(i/6)*228)
			var recipe=Genome.create(44,i,"player",0)
			var appearance={"qualities":{id:1+i%3},"evolved":{id:true},"lashes":{}}
			if id=="tentacle":
				for limb in range(10):appearance.lashes[limb]={"tip":Vector2.from_angle(limb*TAU/10)*70,"extension":0.5+sin(time)*0.5}
			painter.paint(self,center,28,recipe,{id:10},time,"player",true,null,[],Color(-1,-1,-1),0,0.7,0.4+sin(time)*0.4,appearance)
			draw_string(ThemeDB.fallback_font,center+Vector2(-90,87),Catalog.item(id).name,HORIZONTAL_ALIGNMENT_LEFT,200,17,Color("bde4d6"))
var sheet
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1280,720);sheet=Sheet.new();root.add_child(sheet)
	for i in range(36):
		sheet.time=i*0.17;sheet.queue_redraw();await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/Microgen-anatomy.png")
	sheet.queue_free();await process_frame
	print("MUTATION ART: all 18 skill anatomies / qualities / animated poses rendered")
	quit()
