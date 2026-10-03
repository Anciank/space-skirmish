extends Node
## Capture real translated menus and HUDs without saving test preferences.
## godot res://tools/localization_review.tscn -- /tmp/skirmish-languages

var _main: Node3D
var _out := "/tmp/skirmish-languages"
var _preferences: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preferences = GameSettings.values.duplicate()
	GameSettings.reset_to_defaults(false)
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_out = arguments[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.pause_on_focus_loss = false
	add_child(_main)
	var codes := L10n.language_codes()
	if arguments.size() > 1:
		codes.clear()
		for code: String in arguments[1].split(","):
			codes.append(code)
	for code: String in codes:
		GameSettings.set_value("language", code, false)
		_main.menu.show_title()
		await _capture(code + "-title")
		_main.menu.show_settings()
		await _capture(code + "-settings")
		if arguments.size() > 2 and arguments[2] == "popup":
			var picker := _main.menu._frame.get_node("language") as OptionButton
			picker.show_popup()
			await _capture(code + "-languages")
			picker.get_popup().hide()
			await get_tree().process_frame
		_main.menu.show_controls()
		await _capture(code + "-handbook")
		# Keep these language/font captures focused on a familiar six-ship HUD.
		_main.ally_count = 2
		_main.enemy_count = 3
		_main._start_match(false)
		# Freeze the scene without covering the flight instruments.
		_main._set_paused(true)
		_main.menu.hide()
		_main.hud.show()
		_main.hud.process_mode = Node.PROCESS_MODE_ALWAYS
		GameMatch.log_kill("CR-01", GameConfig.TEAM_RED, "YOU", GameConfig.TEAM_BLUE)
		GameMatch.log_kill("", -1, "AZ-01", GameConfig.TEAM_BLUE, "COLLISION")
		await _capture(code + "-flight")
		Input.action_press("scoreboard")
		await _capture(code + "-scoreboard")
		Input.action_release("scoreboard")
		_main.menu.show_pause()
		await _capture(code + "-pause")
		GameMatch.finish_match()
		await _capture(code + "-results")
		_main._show_title()
		await get_tree().process_frame
	_main.queue_free()
	await get_tree().process_frame
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	get_tree().quit()


func _capture(caption: String) -> void:
	DisplayServer.window_move_to_foreground()
	for _index in 3:
		await get_tree().process_frame
	RenderingServer.force_draw(true)
	var path := _out.path_join(caption + ".png")
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("capture " + caption + ": " + str(result))
