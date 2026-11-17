extends SceneTree
const Sim=preload("res://game/simulation.gd")
const View=preload("res://game/world_view.gd")
var sim
var view
var times=[600]
var stage=0
var frame=0
var total_step_us=0
var frame_us=[]
var frame_start=0
func _initialize():
 Engine.max_fps=0
 root.size=Vector2i(1280,720)
 view=View.new()
 root.add_child(view)
 view.set_process(false)
 load_stage()
func load_stage():
 sim=Sim.new()
 var file=FileAccess.open(OS.get_environment("MICROGEN_PROFILE_OUTPUT").path_join("state-%d.json")%times[stage],FileAccess.READ)
 sim.restore(JSON.parse_string(file.get_as_text()))
 for enemy in sim.enemies:
  if enemy.get("impulse",null) is Array:enemy.impulse=Vector2(enemy.impulse[0],enemy.impulse[1])
 sim.max_hp=10000000
 sim.hp=sim.max_hp
 sim.boss_spawned=true
 view.sim=sim
 make_worst()
 frame=0
func make_worst():
 while sim.enemies.size()<28:sim.spawn_enemy(sim.player+Vector2(120,0),"hunter")
 for i in range(sim.enemies.size()):
  sim.enemies[i].pos=sim.player+Vector2.from_angle(i*TAU/28.0)*(110+i%3*35)
  sim.enemies[i].infect=3.0
 while sim.remains.size()<96:sim.remains.append(sim.remains[0].duplicate(true))
 for i in range(sim.remains.size()):sim.remains[i].pos=sim.player+Vector2.from_angle(i*2.399)*(65+i%6*18)
 while sim.pickups.size()<600:sim.pickups.append(sim.pickups[0].duplicate(true))
 for i in range(sim.pickups.size()):sim.pickups[i].pos=sim.player+Vector2.from_angle(i*2.399)*(90+i%8*16)
 sim.fields.clear()
 for i in range(80):sim.fields.append({"pos":sim.player+Vector2.from_angle(i*2.399)*(25+i%5*20),"r":68.0,"life":3.0,"max":3.0,"kind":"poison","hostile":false,"damage":14.0})
 sim.effects.clear()
 for i in range(160):sim.effects.append({"type":"damage" if i%2==0 else "toxic_colony","pos":sim.player+Vector2.from_angle(i*2.399)*80,"r":105.0,"life":0.6,"max":0.75,"amount":12,"player":false})
 sim.shots.clear()
 for i in range(200):sim.shots.append({"pos":sim.player+Vector2.from_angle(i*2.399)*120,"vel":Vector2.RIGHT*100,"hostile":false})
func _process(_dt):
 if frame_start>0 and frame>20:frame_us.append(Time.get_ticks_usec()-frame_start)
 frame_start=Time.get_ticks_usec()
 sim.pending_levels=0
 sim.events.clear()
 sim.feedback.clear()
 var t=Time.get_ticks_usec()
 pass
 total_step_us+=Time.get_ticks_usec()-t
 view._process(1.0/60)
 frame+=1
 if frame==20:
  view.profile_draw.clear()
  view.profile_draw_us=0
  view.profile_process_us=0
  view.profile_terrain_us=0
  total_step_us=0
 if frame==81:
  frame_us.sort()
  print("WORST_RENDER ",JSON.stringify({"seconds":times[stage],"draw_mean_us":view.profile_draw_us/60.0,"process_mean_us":view.profile_process_us/61.0,"step_mean_us":total_step_us/61.0,"frame_median_us":frame_us[frame_us.size()/2],"frame_p95_us":frame_us[int(frame_us.size()*0.95)],"draw_sections_us":view.profile_draw,"terrain_update_us":view.profile_terrain_us/61.0,"terrain_rebuilds":view.terrain.rebuilds if view.get("terrain")!=null else 0,"cache":view.painter.cache.size(),"motions":view.motions.size(),"feeding":view.feeding.size(),"wakes":view.fluid.wakes.size(),"fields":sim.fields.size(),"remains":sim.remains.size(),"effects":sim.effects.size(),"enemies":sim.enemies.size(),"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}))
  frame_us.clear()
  stage+=1
  if stage==times.size():quit();return true
  load_stage()
 return false
