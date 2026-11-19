extends SceneTree
## Run at the repository root: godot --headless --path . --script prototypes/defold/tools/bake_audio.gd
## Export the original cue PCM directly so both game engines use the same synthesis.

const Audio = preload("res://game/audio_bus.gd")
const CLIPS = ["absorb", "danger", "miniboss", "hurt", "hurt_projectile", "hurt_toxin", "reward", "reward_rare", "movement"]
const OUTPUT = "res://prototypes/defold/main/audio"

func _initialize() -> void:
	var audio = Audio.new()
	for clip in CLIPS:
		var err: Error = audio.samples[clip].save_to_wav(OUTPUT.path_join(clip + ".wav"))
		if err != OK:
			push_error("Could not bake %s: %s" % [clip, error_string(err)])
			audio.free()
			quit(1)
			return
	audio.free()
	quit()
