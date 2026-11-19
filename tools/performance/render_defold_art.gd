extends SceneTree

const Fixture = preload("res://tools/performance/defold_fixture.gd")
const View = preload("res://game/world_view.gd")
const Terrain = preload("res://game/terrain_view.gd")
const Fluid = preload("res://game/fluid_view.gd")
const Painter = preload("res://game/organism_painter.gd")
const Genome = preload("res://core/genome.gd")

class Portrait extends Node2D:
	var painter = Painter.new()
	var recipe: Dictionary
	var organs: Dictionary
	var appearance: Dictionary
	var role: String
	var radius: float
	var tint := Color(-1, -1, -1)
	func _draw():
		painter.paint(self, Vector2.ZERO, radius, recipe, organs, 1.0, role, true, null, [], tint, 0.0, 1.0, 0.0, appearance)

var destination: String

func _initialize():
	run.call_deferred()

func run():
	destination = OS.get_environment("MICROGEN_ART_DIR")
	if destination.is_empty():
		push_error("Set MICROGEN_ART_DIR to the output directory.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var sim = Fixture.make()
	if OS.has_environment("MICROGEN_EXPORT_BASE_BODIES"):
		var base_bodies = []
		for family in range(Genome.FAMILIES.size()):
			var recipe = Genome.create(71 + family, 0, "player", 0)
			recipe.family = family
			base_bodies.append({"name":"body_%d" % family,"recipe":recipe,"organs":{},
				"radius":108.0,"role":"player","appearance":{}})
		await capture_portraits(base_bodies)
		return
	var world = SubViewport.new()
	world.size = Fixture.SIZE
	world.disable_3d = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(world)
	var fluid = Fluid.new()
	world.add_child(fluid)
	fluid.update(0.0, sim, Fixture.SIZE, Fixture.ZOOM)
	var terrain = Terrain.new()
	if "raster_enabled" in terrain:terrain.raster_enabled = false
	world.add_child(terrain)
	terrain.update_world(sim.world, sim.player, Fixture.SIZE, Fixture.ZOOM)
	var surface = Fluid.Surface.new()
	surface.fluid = fluid
	world.add_child(surface)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not save(world, "terrain"):
		quit(1)
		return
	world.queue_free()

	var view = View.new()
	view.sim = sim
	var portraits = []
	var index = 0
	for enemy in sim.enemies:
		var role = "prey" if enemy.r < sim.body_radius() * 0.82 else str(enemy.kind)
		portraits.append({"name":"actor_%02d" % index,"recipe":enemy.genome,"organs":view.enemy_organs(enemy),
			"radius":enemy.r * Fixture.ZOOM * 1.17,"role":role,"appearance":{}})
		index += 1
	view.fluid.free()
	view.terrain.free()
	view.water_surface.free()
	view.free()
	portraits.append({"name":"player","recipe":sim.player_genome,"organs":sim.build.organs,
		"radius":sim.body_radius() * Fixture.ZOOM,"role":"player","tint":sim.body_color(),
		"appearance":{"active_synergies":sim.build.active_synergies(),"evolved":sim.build.stats.evolutions,"growth":{"acid":1.0,"tentacle":1.0,"infection":1.0}}})

	await capture_portraits(portraits)

func capture_portraits(portraits: Array):
	var capture = SubViewport.new()
	capture.disable_3d = true
	capture.transparent_bg = true
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	for data in portraits:
		var portrait = Portrait.new()
		portrait.radius = data.radius
		portrait.recipe = data.recipe
		portrait.organs = data.organs
		portrait.role = data.role
		portrait.appearance = data.appearance
		portrait.tint = data.get("tint",Color(-1,-1,-1))
		var side = int(ceil(portrait.radius * 6.0 / 2.0)) * 2
		capture.size = Vector2i(side,side)
		portrait.position = Vector2(side,side) * 0.5
		capture.add_child(portrait)
		await RenderingServer.frame_post_draw
		if not save(capture,data.name):
			quit(1)
			return
		portrait.free()
	capture.free()
	print("Rendered ", portraits.size(), " full-detail organisms.")
	quit()

func save(viewport: SubViewport, asset: String) -> bool:
	var image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Empty frame for " + asset)
		return false
	return image.save_png(destination.path_join(asset + ".png")) == OK
