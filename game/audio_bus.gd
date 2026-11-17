extends Node

# Small, precomputed mono samples keep combat feedback independent of frame rate.
const SAMPLE_RATE=22050
const VOICE_CAP=6
const KINDS=["hit","hurt","absorb","danger","miniboss","synergy"]
var samples: Dictionary={}
var voices: Array[AudioStreamPlayer]=[]
var generated_samples=0
var played_events=0
var _last: Dictionary={}
var _clock=-1.0
var _cursor=0
var _last_global=-100.0
var _pending_warning=""
var _run_id=""
const GLOBAL_INTERVAL=0.4

func _init():
	for kind in KINDS:
		samples[kind]=_synthesize(kind)
		generated_samples+=1

func _ready():
	for i in range(VOICE_CAP):
		var voice=AudioStreamPlayer.new()
		voice.volume_db=-14.0
		add_child(voice)
		voices.append(voice)

func consume(sim,enabled: bool):
	var queue: Array=sim.feedback.duplicate()
	sim.feedback.clear()
	var now=float(sim.elapsed)
	var current_run_id=String(sim.run_id)
	if now<_clock or current_run_id!=_run_id:
		_last.clear()
		_last_global=-100.0
		_pending_warning=""
		for voice in voices: voice.stop()
	_run_id=current_run_id
	_clock=now
	if not enabled:
		_pending_warning=""
		for voice in voices: voice.stop()
		return
	# One string is enough to retain the strongest warning across blocked frames.
	# Repeated danger pulses cannot replace an already pending miniboss cue.
	for event in queue:
		var kind=String(event.get("kind",""))
		if kind=="miniboss" or (kind=="danger" and _pending_warning.is_empty()): _pending_warning=kind
	var frozen=bool(sim.paused)
	for voice in voices: voice.stream_paused=frozen
	if frozen or now-_last_global<GLOBAL_INTERVAL: return
	if not _pending_warning.is_empty() and _play(_pending_warning,now):
		_pending_warning=""
		return
	for event in queue:
		var kind=String(event.get("kind",""))
		if kind in ["hurt","absorb"] and _play(kind,now): return

func _play(kind: String,now: float) -> bool:
	var warning=kind in ["danger","miniboss"]
	var interval=1.4 if warning else (0.85 if kind=="hurt" else 0.65)
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
	chosen.stream=samples[kind]
	chosen.pitch_scale=1.0
	chosen.volume_db=-16.0 if warning else -21.0
	chosen.play()
	played_events+=1
	return true

func _synthesize(kind: String) -> AudioStreamWAV:
	var duration=0.18
	if kind=="absorb": duration=0.42
	elif kind in ["danger","miniboss"]: duration=0.64
	elif kind=="synergy": duration=0.48
	var count=int(duration*SAMPLE_RATE)
	var pcm=PackedByteArray()
	pcm.resize(count*2)
	var rng=RandomNumberGenerator.new()
	rng.seed=KINDS.find(kind)*761+931
	var phase=0.0
	var soft_noise=0.0
	for i in range(count):
		var t=float(i)/SAMPLE_RATE
		var u=t/duration
		var attack=minf(1.0,t/(0.04 if kind=="hurt" else 0.024))
		var tail=pow(1.0-u,2.0)
		soft_noise=lerpf(soft_noise,rng.randf_range(-1.0,1.0),0.17)
		var value=0.0
		if kind in ["hit","hurt"]:
			phase+=TAU*(135.0-95.0*u if kind=="hit" else 105.0-58.0*u)/SAMPLE_RATE
			value=(sin(phase)*0.65+soft_noise*0.35)*attack*tail
		elif kind=="absorb":
			phase+=TAU*(130.0+sin(u*TAU*2.7)*65.0-40.0*u)/SAMPLE_RATE
			value=(sin(phase)*0.54+sin(phase*1.98)*0.16+soft_noise*0.22)*attack*tail*(0.65+0.35*sin(u*PI*5.0))
		elif kind in ["danger","miniboss"]:
			var frequency=83.0 if kind=="danger" else 69.0
			value=(sin(TAU*frequency*t)*0.58+sin(TAU*frequency*1.5*t)*0.12)*pow(sin(u*PI),2.0)
		else:
			phase+=TAU*(185.0+165.0*u)/SAMPLE_RATE
			value=(sin(phase)*0.5+sin(phase*1.5)*0.17)*attack*tail
		pcm.encode_s16(i*2,int(clampf(value*0.67,-0.9,0.9)*32767.0))
	var sample=AudioStreamWAV.new()
	sample.format=AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate=SAMPLE_RATE
	sample.stereo=false
	sample.data=pcm
	return sample
