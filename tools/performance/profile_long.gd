extends SceneTree
const Sim=preload("res://game/simulation.gd")
var sim
var stage_total=0
var peak={}
var samples=[]
func _initialize():
 sim=Sim.new()
 sim.new_run(44)
 sim.max_hp=10000000
 sim.hp=sim.max_hp
 sim.boss_spawned=true
 sim.build.organs={"tentacle":3,"acid":3,"infection":3,"trail":3,"division":3,"pulse":3}
 sim.build.adaptations={"speed":3,"regen":3,"armor":3,"magnet":3}
 for frame in range(36001):
  if frame%10800==0 or frame==21600 or frame==36000:
   report(frame)
   var file=FileAccess.open(OS.get_environment("MICROGEN_PROFILE_OUTPUT").path_join("state-%d.json")%int(frame/60),FileAccess.WRITE)
   file.store_string(JSON.stringify(sim.snapshot()))
  if frame==36000:break
  sim.pending_levels=0
  sim.events.clear()
  sim.feedback.clear()
  var before=Time.get_ticks_usec()
  sim.step(1.0/60.0,Vector2.from_angle(floor(frame/360.0)*1.25))
  var duration=Time.get_ticks_usec()-before
  stage_total+=duration
  samples.append(duration)
  for key in ["enemies","fields","shots","remains","pickups","effects"]:
   peak[key]=maxi(peak.get(key,0),sim.get(key).size())
 quit()
func report(frame):
 samples.sort()
 var counts={}
 for key in ["enemies","fields","shots","remains","pickups","effects","events","feedback"]:counts[key]=sim.get(key).size()
 var result={"seconds":frame/60,"counts":counts,"peak":peak.duplicate(),"elapsed":sim.elapsed,"memory_static_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0,"mean_step_us":float(stage_total)/maxi(1,samples.size()),"p95_step_us":samples[int(samples.size()*0.95)] if samples.size()>0 else 0,"stage_times_us":sim.profile_times.duplicate(),"stage_frames":samples.size(),"kills":sim.kills,"organs":sim.build.organs}
 print("PROFILE ",JSON.stringify(result))
 stage_total=0
 samples.clear()
 peak.clear()
 sim.profile_times.clear()
