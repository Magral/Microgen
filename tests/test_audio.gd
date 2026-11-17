extends SceneTree
const Audio=preload("res://game/audio_bus.gd")
class FakeSim:
	extends RefCounted
	var feedback: Array=[]
	var elapsed=1.0
	var paused=false
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
	check(audio.samples.size()==6 and audio.generated_samples==6,"all procedural clips generated once")
	check(audio.voices.size()==Audio.VOICE_CAP,"audio has bounded voice pool")
	var original=audio.samples.hit
	var signatures={}
	for kind in audio.samples:
		var sample: AudioStreamWAV=audio.samples[kind]
		check(sample.mix_rate==22050 and not sample.stereo,"compact mono PCM format")
		check(sample.get_length()>0.1 and sample.get_length()<0.7,"sound duration bounded")
		var peak=0
		for i in range(0,sample.data.size(),2): peak=maxi(peak,absi(sample.data.decode_s16(i)))
		check(peak>1000 and peak<30000,"PCM audible with safe headroom")
		signatures[hash(sample.data)]=true
	check(signatures.size()==6,"feedback sounds have distinct waveforms")
	for i in range(20): sim.feedback.append({"kind":"hit","pos":Vector2.ZERO})
	audio.consume(sim,true)
	check(sim.feedback.is_empty() and audio.played_events==1,"impact bursts drain and throttle")
	sim.elapsed+=0.1
	sim.feedback=[{"kind":"hit"},{"kind":"absorb"},{"kind":"danger"},{"kind":"synergy"}]
	audio.consume(sim,true)
	check(audio.played_events==5,"independent feedback kinds play together")
	sim.elapsed+=0.1
	sim.feedback=[{"kind":"danger"},{"kind":"miniboss"}]
	audio.consume(sim,true)
	check(audio.played_events==5,"warning cues share one second throttle")
	sim.paused=true
	sim.feedback=[{"kind":"absorb"}]
	audio.consume(sim,true)
	check(sim.feedback.is_empty() and audio.played_events==5,"pause drains feedback without new sounds")
	for voice in audio.voices:
		if voice.playing: check(voice.stream_paused,"pause freezes active audio voice")
	sim.paused=false
	sim.feedback=[{"kind":"absorb"}]
	audio.consume(sim,false)
	check(sim.feedback.is_empty() and audio.played_events==5,"muted queue clears without replay")
	for voice in audio.voices: check(not voice.playing,"mute stops active audio")
	for i in range(60):
		sim.elapsed+=0.13
		sim.feedback=[{"kind":"hit"},{"kind":"absorb"},{"kind":"synergy"}]
		audio.consume(sim,true)
	check(audio.voices.size()==Audio.VOICE_CAP,"busy combat never allocates more voices")
	check(audio.generated_samples==6 and audio.samples.hit==original,"PCM cache reused across every consume")
	for voice in audio.voices: voice.stop()
	audio.free()
	await create_timer(0.25).timeout
	print("AUDIO: %d assertions, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
