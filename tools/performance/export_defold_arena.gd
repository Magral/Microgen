extends SceneTree

const Fixture = preload("res://tools/performance/defold_fixture.gd")

func _initialize():
	var output = FileAccess.open("res://prototypes/defold/main/arena.json", FileAccess.WRITE)
	if output == null:
		push_error("Unable to write the shared fixture")
		quit(1)
		return
	var data = Fixture.describe(Fixture.make())
	output.store_string(JSON.stringify(data, "\t") + "\n")
	print("Arena seed %s: %d actors, %d fields, %d wall tiles" % [data.seed,data.actors.size(),data.fields.size(),data.walls.size()])
	quit()
