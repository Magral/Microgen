extends SceneTree
const Sim=preload("res://game/simulation.gd")
const View=preload("res://game/world_view.gd")
var sim
var view
var times=[0,180,360,600]
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
 frame=0
func _process(_dt):
 if frame_start>0 and frame>60:frame_us.append(Time.get_ticks_usec()-frame_start)
 frame_start=Time.get_ticks_usec()
 sim.pending_levels=0
 sim.events.clear()
 sim.feedback.clear()
 var t=Time.get_ticks_usec()
 sim.step(1.0/60,Vector2.from_angle(floor(frame/360.0)*1.25))
 total_step_us+=Time.get_ticks_usec()-t
 view._process(1.0/60)
 frame+=1
 if frame==60:
  view.profile_draw.clear()
  view.profile_draw_us=0
  view.profile_process_us=0
  view.profile_terrain_us=0
  total_step_us=0
 if frame==241:
  frame_us.sort()
  print("RENDER ",JSON.stringify({"seconds":times[stage],"draw_mean_us":view.profile_draw_us/180.0,"process_mean_us":view.profile_process_us/181.0,"step_mean_us":total_step_us/181.0,"frame_median_us":frame_us[frame_us.size()/2],"frame_p95_us":frame_us[int(frame_us.size()*0.95)],"draw_sections_us":view.profile_draw,"terrain_update_us":view.profile_terrain_us/181.0,"terrain_rebuilds":view.terrain.rebuilds if view.get("terrain")!=null else 0,"cache":view.painter.cache.size(),"motions":view.motions.size(),"feeding":view.feeding.size(),"wakes":view.fluid.wakes.size(),"fields":sim.fields.size(),"remains":sim.remains.size(),"effects":sim.effects.size(),"enemies":sim.enemies.size(),"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0}))
  frame_us.clear()
  stage+=1
  if stage==times.size():quit();return true
  load_stage()
 return false
