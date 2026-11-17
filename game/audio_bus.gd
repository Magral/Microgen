extends Node

# All PCM is cached at startup, with a local RNG independent of simulation state.
const SAMPLE_RATE=22050
const VOICE_CAP=6
const GLOBAL_INTERVAL=0.4
const KINDS=["hit","hurt","hurt_projectile","hurt_toxin","absorb","danger","miniboss","synergy","reward","reward_rare","movement"]
var samples: Dictionary={}
var voices: Array[AudioStreamPlayer]=[]
var movement_voice: AudioStreamPlayer
var generated_samples=0
var played_events=0
var _last: Dictionary={}
var _clock=-1.0
var _cursor=0
var _last_global=-100.0
var _pending: Dictionary={}
var _run_id=""
var _movement_gain=0.0

func _init():
	for kind in KINDS:
		samples[kind]=_synthesize(kind)
		generated_samples+=1

func _ready():
	for i in range(VOICE_CAP):
		var voice=AudioStreamPlayer.new()
		add_child(voice)
		voices.append(voice)
	movement_voice=AudioStreamPlayer.new()
	movement_voice.stream=samples.movement
	movement_voice.volume_db=-80.0
	add_child(movement_voice)

func _stop_all():
	for voice in voices: voice.stop()
	if is_instance_valid(movement_voice):
		movement_voice.stop()
		movement_voice.volume_db=-80.0
	_movement_gain=0.0

func consume(sim,enabled: bool):
	var queue: Array=sim.feedback.duplicate()
	sim.feedback.clear()
	var now=float(sim.elapsed)
	var dt=clampf(now-_clock,0.0,0.1) if _clock>=0.0 else 0.016
	var current_run_id=String(sim.run_id)
	if now<_clock or current_run_id!=_run_id:
		_last.clear()
		_last_global=-100.0
		_pending.clear()
		_stop_all()
	_run_id=current_run_id
	_clock=now
	if not enabled:
		_pending.clear()
		_stop_all()
		return
	for event in queue:
		var kind=String(event.get("kind",""))
		if kind in ["danger","miniboss","hurt","reward"]: _pending[kind]=event
	var frozen=bool(sim.paused)
	for voice in voices: voice.stream_paused=frozen
	movement_voice.stream_paused=frozen
	if frozen: return
	_update_movement(sim,dt)
	if now-_last_global<GLOBAL_INTERVAL-0.000001: return
	for kind in ["miniboss","danger","hurt","reward"]:
		if _pending.has(kind) and _play(kind,now,_pending[kind]):
			_pending.erase(kind)
			# A stronger warning also satisfies a weaker warning from the same burst.
			if kind=="miniboss": _pending.erase("danger")
			return
	for event in queue:
		if event.get("kind","")=="absorb" and _play("absorb",now,event): return

func _update_movement(sim,dt: float):
	var velocity=sim.get("player_velocity")
	var speed=velocity.length() if velocity is Vector2 else 0.0
	var radius=float(sim.body_radius()) if sim.has_method("body_radius") else 34.0
	var target=clampf(speed/110.0,0.0,1.0)*0.24 if speed>3.0 else 0.0
	_movement_gain=lerpf(_movement_gain,target,1.0-exp(-dt*8.0))
	if _movement_gain<0.002 and target==0.0:
		movement_voice.stop()
		return
	movement_voice.volume_db=linear_to_db(maxf(0.0001,_movement_gain))
	movement_voice.pitch_scale=clampf(1.07-radius*0.003+speed*0.001,0.72,1.25)
	if not movement_voice.playing: movement_voice.play()

func _play(kind: String,now: float,event: Dictionary={}) -> bool:
	var warning=kind in ["danger","miniboss"]
	var interval=1.4 if warning else (0.85 if kind=="hurt" else (1.2 if kind=="reward" else 0.65))
	var group="warning" if warning else kind
	if now-float(_last.get(group,-100.0))<interval or voices.is_empty(): return false
	_last[group]=now
	_last_global=now
	var chosen=voices[_cursor]
	for voice in voices:
		if not voice.playing:
			chosen=voice
			break
	_cursor=(_cursor+1)%VOICE_CAP
	var clip=kind
	if kind=="hurt":
		if event.get("source","")=="toxin": clip="hurt_toxin"
		elif event.get("source","")=="projectile": clip="hurt_projectile"
	elif kind=="reward" and int(event.get("tier",1))>=2: clip="reward_rare"
	chosen.stream=samples[clip]
	chosen.stream_paused=false
	chosen.pitch_scale=1.0
	chosen.volume_db=-9.0 if kind=="hurt" else (-11.0 if warning else (-13.0 if kind=="reward" else -19.0))
	chosen.play()
	played_events+=1
	return true

func _synthesize(kind: String) -> AudioStreamWAV:
	var duration=0.28
	if kind=="absorb": duration=0.42
	elif kind in ["danger","miniboss"]: duration=0.64
	elif kind in ["synergy","reward","reward_rare"]: duration=0.48
	elif kind=="hurt_toxin": duration=0.52
	elif kind=="movement": duration=1.0
	var count=int(duration*SAMPLE_RATE)
	var pcm=PackedByteArray()
	pcm.resize(count*2)
	var rng=RandomNumberGenerator.new()
	rng.seed=KINDS.find(kind)*761+931
	var phase=0.0
	var soft_noise=0.0
	var deep_noise=0.0
	for i in range(count):
		var t=float(i)/SAMPLE_RATE
		var u=t/duration
		var noise=rng.randf_range(-1.0,1.0)
		soft_noise=lerpf(soft_noise,noise,0.22)
		deep_noise=lerpf(deep_noise,noise,0.018)
		var attack=minf(1.0,t/0.009)
		var tail=pow(1.0-u,2.0)
		var value=0.0
		if kind in ["hit","hurt","hurt_projectile"]:
			var projectile=kind=="hurt_projectile"
			phase+=TAU*(175.0-115.0*u if projectile else 118.0-67.0*u)/SAMPLE_RATE
			var membrane=sin(phase)*0.52+sin(phase*1.57)*0.17
			var crack=(noise*0.25+soft_noise*0.4)*exp(-t*(42.0 if projectile else 24.0))
			var wet=soft_noise*0.32*(0.65+0.35*sin(t*87.0))
			value=(membrane*tail+crack+wet*tail)*attack
		elif kind=="hurt_toxin":
			phase+=TAU*(104.0+sin(t*49.0)*24.0-46.0*u)/SAMPLE_RATE
			var bubbles=pow(0.5+0.5*sin(t*91.0+sin(t*23.0)),3.0)
			value=(sin(phase)*0.35+soft_noise*(0.3+bubbles*0.6)+noise*0.08)*attack*tail
		elif kind=="absorb":
			phase+=TAU*(130.0+sin(u*TAU*2.7)*65.0-40.0*u)/SAMPLE_RATE
			value=(sin(phase)*0.54+sin(phase*1.98)*0.16+soft_noise*0.22)*attack*tail*(0.65+0.35*sin(u*PI*5.0))
		elif kind in ["danger","miniboss"]:
			var frequency=83.0 if kind=="danger" else 61.0
			var pulse=pow(sin(u*PI*2.0),2.0) if kind=="danger" else pow(sin(u*PI*3.0),2.0)
			value=(sin(TAU*frequency*t)*0.58+sin(TAU*frequency*1.5*t)*0.2+deep_noise*0.15)*pulse*pow(sin(u*PI),0.5)
		elif kind=="movement":
			# Seam-safe continuous water body: no discrete trigger or rapid retrigger.
			var seam=pow(sin(u*PI),0.35)
			value=(deep_noise*1.5+soft_noise*0.24+sin(TAU*47.0*t)*0.05)*seam
		else:
			var lift=230.0 if kind=="reward_rare" else (195.0 if kind=="reward" else 165.0)
			phase+=TAU*(185.0+lift*u)/SAMPLE_RATE
			value=(sin(phase)*0.43+sin(phase*1.5)*0.19+sin(phase*2.0)*0.09)*attack*tail
		pcm.encode_s16(i*2,int(clampf(value*0.85,-0.82,0.82)*32767.0))
	var sample=AudioStreamWAV.new()
	sample.format=AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate=SAMPLE_RATE
	sample.stereo=false
	sample.data=pcm
	if kind=="movement":
		sample.loop_mode=AudioStreamWAV.LOOP_FORWARD
		sample.loop_begin=0
		sample.loop_end=count
	return sample
