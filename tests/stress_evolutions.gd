extends SceneTree
const Sim=preload("res://game/simulation.gd")
var failures=0
func _initialize():call_deferred("run")
func run():
	var s=Sim.new();s.new_run(44);s.max_hp=10000000;s.hp=s.max_hp;s.boss_spawned=true
	s.build.organs={"tentacle":6,"acid":6,"infection":6,"devour":4,"electric":3,"barrier":3}
	s.build.adaptations={"magnet":3,"armor":3,"metabolism":3,"regen":3}
	s.build.stats.evolutions={"tentacle":true,"acid":true,"infection":true}
	var peaks={"enemies":0,"fields":0,"remains":0,"effects":0,"held":0};var checkpoints=[]
	for frame in range(36001):
		if frame%10800==0 or frame==36000:
			var data=JSON.parse_string(JSON.stringify(s.snapshot()));var loaded=Sim.new()
			if not loaded.restore(data) or loaded.spore_charge!=s.spore_charge:failures+=1;push_error("evolution checkpoint restore failed")
			s=loaded;s.max_hp=10000000;s.hp=s.max_hp;s.boss_spawned=true
			checkpoints.append({"seconds":int(frame/60),"kills":s.kills,"charge":s.spore_charge,"memory_mb":Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0})
		if frame==36000:break
		s.pending_levels=0;s.events.clear();s.feedback.clear()
		s.step(1.0/60,Vector2.from_angle(floor(frame/360.0)*1.25))
		for key in ["enemies","fields","remains","effects"]:peaks[key]=maxi(peaks[key],s.get(key).size())
		var held=s.enemies.filter(func(e):return float(e.get("crown_time",0))>0).size();peaks.held=maxi(peaks.held,held)
		if held>2 or s.spore_charge<0 or s.spore_charge>2:failures+=1;push_error("evolution state escaped bounds");break
	if peaks.enemies>28 or peaks.fields>80 or peaks.remains>96 or peaks.effects>160:failures+=1;push_error("scene caps exceeded")
	var result={"failures":failures,"peaks":peaks,"checkpoints":checkpoints}
	var file=FileAccess.open("res://build/evolution-stress.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("EVOLUTION STRESS: ",JSON.stringify(result));quit(0 if failures==0 else 1)
