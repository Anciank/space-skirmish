extends Node
## Write notices from the exact engine used to make a release, without network access.


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.is_empty():
		push_error("Pass an output directory for engine license notices.")
		await Sfx.finish_audio()
		get_tree().quit(1)
		return
	var output := arguments[0]
	DirAccess.make_dir_recursive_absolute(output)
	var notices := "Star Skirmish uses Godot Engine and the following engine components.\n\n"
	var licenses := Engine.get_license_info()
	for item: Dictionary in Engine.get_copyright_info():
		notices += "=== %s ===\n" % item.name
		for part: Dictionary in item.parts:
			for copyright_line: String in part.copyright:
				notices += copyright_line + "\n"
			notices += "License: %s\n" % part.license
			for file: String in part.files:
				notices += "  " + file + "\n"
			notices += "\n"
	for name: String in licenses:
		notices += "\n=== License: %s ===\n%s\n" % [name, licenses[name]]
	var ok := _write(output.path_join("GODOT_LICENSE.txt"), Engine.get_license_text())
	ok = _write(output.path_join("GODOT_COMPONENTS.txt"), notices) and ok
	for path: String in L10n.FONT_NOTICES:
		ok = _write(output.path_join(path.get_file()), FileAccess.get_file_as_string(path)) and ok
	await Sfx.finish_audio()
	get_tree().quit(0 if ok else 1)


func _write(path: String, content: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write engine notices: " + path)
		return false
	file.store_string(content)
	return true
