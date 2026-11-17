extends SceneTree
const Audio=preload("res://game/audio_bus.gd")
class FakeSim:
	extends RefCounted
	var feedback: Array=[]
	var elapsed=1.0
	var paused=false
	var player_velocity=Vector2.ZERO
	var run_id="audio-test-run"
var checks=0
var failures=0
func check(ok: bool,message: String):
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
func _initialize():
	call_deferred("run_checks")
func run_checks():
	var audio=Audio.new()
	root.add_child(audio)
	var sim=FakeSim.new()
	check(audio.samples.size()==Audio.KINDS.size() and audio.generated_samples==Audio.KINDS.size(),"all procedural clips generated once")
	check(audio.voices.size()==Audio.VOICE_CAP,"audio has bounded voice pool")
	var original=audio.samples.hit
	var signatures={}
	for kind in audio.samples:
		var sample: AudioStreamWAV=audio.samples[kind]
		check(sample.mix_rate==22050 and not sample.stereo,"compact mono PCM format")
		check(sample.get_length()>0.1 and sample.get_length()<=1.0,"sound duration bounded")
		var peak=0
		for i in range(0,sample.data.size(),2): peak=maxi(peak,absi(sample.data.decode_s16(i)))
		check(peak>1000 and peak<30000,"PCM audible with safe headroom")
		signatures[hash(sample.data)]=true
	check(signatures.size()==Audio.KINDS.size(),"feedback sounds have distinct waveforms")
	for i in range(20): sim.feedback.append({"kind":"hit","pos":Vector2.ZERO})
	audio.consume(sim,true)
	check(sim.feedback.is_empty() and audio.played_events==0,"outgoing hit spam is silent by default")
	sim.feedback=[{"kind":"synergy"}]
	audio.consume(sim,true)
	check(audio.played_events==0,"synergy loops do not add a repeated shooting cue")
	sim.elapsed+=0.1
	sim.feedback=[{"kind":"hit"},{"kind":"absorb"},{"kind":"danger"},{"kind":"synergy"}]
	audio.consume(sim,true)
	check(audio.played_events==1,"all feedback shares a sparse global budget")
	check(audio.voices.any(func(voice): return voice.stream==audio.samples.danger),"warning cue takes priority over feeding in a crowded frame")
	sim.elapsed+=0.1
	sim.feedback=[{"kind":"danger"},{"kind":"miniboss"}]
	audio.consume(sim,true)
	check(audio.played_events==1,"warning cues share one second throttle")
	sim.paused=true
	sim.feedback=[{"kind":"absorb"}]
	audio.consume(sim,true)
	check(sim.feedback.is_empty() and audio.played_events==1,"pause drains feedback without new sounds")
	for voice in audio.voices:
		if voice.playing: check(voice.stream_paused,"pause freezes active audio voice")
	sim.paused=false
	sim.feedback=[{"kind":"absorb"}]
	audio.consume(sim,false)
	check(sim.feedback.is_empty() and audio.played_events==1,"muted queue clears without replay")
	for voice in audio.voices: check(not voice.playing,"mute stops active audio")
	var before_spam=audio.played_events
	var spam_start=sim.elapsed
	for i in range(600):
		sim.elapsed+=0.05
		sim.feedback=[{"kind":"hit"},{"kind":"absorb"},{"kind":"synergy"},{"kind":"hurt"},{"kind":"danger"}]
		audio.consume(sim,true)
	check(audio.played_events-before_spam<=int((sim.elapsed-spam_start)*2.5)+1,"long combat spam stays under 2.5 sounds per second globally")
	check(audio.voices.size()==Audio.VOICE_CAP,"busy combat never allocates more voices")
	check(audio.generated_samples==Audio.KINDS.size() and audio.samples.hit==original,"PCM cache reused across every consume")
	var pending_audio=Audio.new()
	root.add_child(pending_audio)
	var pending_sim=FakeSim.new()
	pending_sim.elapsed=10.0
	pending_sim.feedback=[{"kind":"absorb"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=10.1
	pending_sim.feedback=[{"kind":"danger"},{"kind":"miniboss"},{"kind":"danger"}]
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==1,"pending warning obeys current global sound budget")
	pending_sim.elapsed=10.4
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==2 and pending_audio.voices.any(func(voice): return voice.stream==pending_audio.samples.miniboss),"highest priority blocked warning survives an empty later frame")
	pending_sim.elapsed=10.8
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==2,"deferred warning plays exactly once")
	pending_sim.elapsed=12.0
	pending_sim.feedback=[{"kind":"absorb"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=12.1
	pending_sim.feedback=[{"kind":"miniboss"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.paused=true
	pending_sim.elapsed=12.5
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==3,"pause keeps a warning pending without playback")
	pending_sim.paused=false
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==4,"resume delivers the paused warning once")
	pending_sim.elapsed=14.0
	pending_sim.feedback=[{"kind":"absorb"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=14.1
	pending_sim.feedback=[{"kind":"danger"}]
	pending_audio.consume(pending_sim,true)
	pending_audio.consume(pending_sim,false)
	pending_sim.elapsed=14.5
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==5,"mute discards a pending warning")
	pending_sim.elapsed=16.0
	pending_sim.feedback=[{"kind":"absorb"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=16.1
	pending_sim.feedback=[{"kind":"miniboss"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=0.0
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=0.5
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==6,"new run discards stale pending warnings")
	pending_sim.elapsed=20.0
	pending_sim.feedback=[{"kind":"absorb"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=20.1
	pending_sim.feedback=[{"kind":"miniboss"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.run_id="another-run"
	pending_sim.elapsed=20.5
	pending_audio.consume(pending_sim,true)
	check(pending_audio.played_events==7,"run identity change clears warning even without clock rollback")
	# Damage blocked by a just-played absorb survives until the next sound slot.
	pending_sim.elapsed=30.0
	pending_sim.feedback=[{"kind":"absorb"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=30.1
	pending_sim.feedback=[{"kind":"hurt","source":"toxin"}]
	pending_audio.consume(pending_sim,true)
	pending_sim.elapsed=30.4
	pending_audio.consume(pending_sim,true)
	check(pending_audio.voices.any(func(voice): return voice.stream==pending_audio.samples.hurt_toxin and voice.volume_db>=-12.0),"deferred toxin hurt is distinct and loud")
	pending_sim.elapsed=32.0
	pending_sim.feedback=[{"kind":"hurt","source":"projectile"},{"kind":"absorb"}]
	pending_audio.consume(pending_sim,true)
	check(pending_audio.voices.any(func(voice): return voice.stream==pending_audio.samples.hurt_projectile),"projectile hurt wins over absorb")
	var events_before_motion=pending_audio.played_events
	pending_sim.player_velocity=Vector2(100,0)
	for i in range(30):
		pending_sim.elapsed+=0.02
		pending_audio.consume(pending_sim,true)
	check(pending_audio.movement_voice.playing and pending_audio.movement_voice.volume_db>-30.0,"movement fades into one fluid loop")
	check(pending_audio.played_events==events_before_motion,"movement creates no repeated combat events")
	check(pending_audio.movement_voice.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"movement PCM loops")
	pending_sim.paused=true
	pending_audio.consume(pending_sim,true)
	check(pending_audio.movement_voice.stream_paused,"pause freezes movement loop")
	pending_sim.paused=false
	pending_sim.player_velocity=Vector2.ZERO
	for i in range(80):
		pending_sim.elapsed+=0.02
		pending_audio.consume(pending_sim,true)
	check(not pending_audio.movement_voice.playing,"stationary movement fades to silence")
	pending_sim.player_velocity=Vector2(100,0)
	pending_sim.elapsed+=0.1
	pending_audio.consume(pending_sim,true)
	pending_audio.consume(pending_sim,false)
	check(not pending_audio.movement_voice.playing,"mute stops the movement loop")
	pending_sim.run_id="movement-reset"
	pending_sim.player_velocity=Vector2.ZERO
	pending_audio.consume(pending_sim,true)
	check(not pending_audio.movement_voice.playing,"run reset clears movement gain")
	for voice in pending_audio.voices: voice.stop()
	pending_audio.free()
	for voice in audio.voices: voice.stop()
	audio.free()
	await create_timer(0.25).timeout
	print("AUDIO: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
