extends Node
## Compile suite scripts with the project's real autoloads available.

func _ready() -> void:
	var failed := false
	for path: String in OS.get_cmdline_user_args():
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			failed = true
	await Sfx.finish_audio()
	get_tree().quit(1 if failed else 0)
