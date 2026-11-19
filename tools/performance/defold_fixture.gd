extends RefCounted

const Sim = preload("res://game/simulation.gd")
const World = preload("res://game/world.gd")
const Genome = preload("res://core/genome.gd")
const SEED := 47
const ZOOM := 1.18
const SIZE := Vector2(2460, 1080)
const CAMERA := Vector2(0.50, 0.51)

static func make():
	var sim = Sim.new()
	sim.new_run(44)
	for scene_seed in [45, 46, SEED]:
		sim.stage_transition = true
		sim.pending_stage_seed = scene_seed
		sim.enter_next_stage()
	sim.level = 37
	sim.elapsed = 1581.0
	for organ in ["acid","pulse","barrier","division","trail","tentacle","infection","devour","enzymes"]:
		sim.build.organs[organ] = 6
	sim.build.stats.evolutions = {"acid":true,"tentacle":true,"infection":true}
	sim.player = sim.world.boss_pos - Vector2(175,0)
	sim.previous_player = sim.player
	sim.player_genome = Genome.create(SEED, 0, "player", 0)
	var types = ["prey","hunter","spitter"]
	for i in range(100):
		if sim.enemies.size() == 18:break
		var p = sim.player + Vector2.from_angle(i*2.39996)*float(120 + (i*73)%540)
		if sim.world.walkable(p, 30):sim.spawn_enemy(p, types[i%types.size()])
	sim.spawn_enemy(sim.world.boss_pos + Vector2(82,0), "boss")
	sim.boss_spawned = true
	sim.boss_marker = sim.enemies.back().pos
	for i in range(24):
		var p = sim.player + Vector2.from_angle(i*2.39996)*float(40+(i*33)%220)
		sim.fields.append({"pos":p,"r":55.0+(i%4)*10.0,"life":3.0,"max":4.0,"kind":"enemy_toxin" if i%6==0 else ("spore" if i%3==0 else "poison"),"hostile":i%6==0,"damage":4.0})
	return sim

static func describe(sim) -> Dictionary:
	var origin: Vector2 = sim.player - SIZE * CAMERA / ZOOM
	var bounds := Rect2(origin, SIZE / ZOOM)
	var walls := []
	for y in range(World.H):
		for x in range(World.W):
			var p := Vector2(x+0.5,y+0.5)*World.TILE
			if sim.world.cells[y*World.W+x] == 1 and bounds.grow(120.0).has_point(p):
				walls.append({"pos":_point((p-origin)*ZOOM),"warm":sim.world.biome(p)==1,"phase":x*0.31+y*0.17})
	var actors := []
	for enemy in sim.enemies:
		actors.append({"pos":_point((enemy.pos-origin)*ZOOM),"radius":enemy.r*ZOOM,"kind":enemy.kind,"phase":enemy.phase})
	var fields := []
	for field in sim.fields:
		fields.append({"pos":_point((field.pos-origin)*ZOOM),"radius":field.r*ZOOM,"kind":field.kind})
	var pickups := []
	for item in sim.pickups:
		if bounds.has_point(item.pos):
			pickups.append({"pos":_point((item.pos-origin)*ZOOM),"kind":item.type,"phase":float(item.id)})
	return {"seed":SEED,"size":_point(SIZE),"stage":4,"stage_name":sim.stage_name(),"walls":walls,"actors":actors,"fields":fields,"pickups":pickups,"player":{"pos":_point((sim.player-origin)*ZOOM),"radius":sim.body_radius()*ZOOM}}

static func _point(p: Vector2) -> Array:
	return [p.x, p.y]
