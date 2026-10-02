extends Node
## Release-template QA main scene. The builder verifies its game payloads match shipping.

var _main: Node3D
var _checks := 0
var _failures := 0
var _preferences: Dictionary
var _settings_path: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preferences = GameSettings.values.duplicate()
	_settings_path = GameSettings.storage_path
	GameSettings.storage_path = "user://release-smoke-test.cfg"
	GameSettings.reset_to_defaults(false)
	var files := _pack_files("res://")
	var clean_pack := true
	for path: String in files:
		if path.begins_with("res://tools/release_smoke."):
			continue
		for prefix: String in ["res://tests/", "res://tools/", "res://captures/", "res://dist/", "res://builds/"]:
			clean_pack = clean_pack and not path.begins_with(prefix)
	_check("QA pack contains only its runner and shipping game resources", clean_pack and files.size() > 20)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(4)
	_check("standalone game boots at deployment", _main.menu.page == "title" and _main.player == null and not GameMatch.running)
	await _activate("Credits")
	_check("credits provide the engine notice in the game", _main.menu.page == "credits" and _main.menu._frame.find_child("EngineLicense", true, false).text.contains("Permission is hereby granted"))
	await _key(KEY_ESCAPE)
	await _activate("Deploy")
	_check("real keyboard input deploys six pilots", _main.state == _main.State.PLAYING and _main._roster.size() == 6 and GameMatch.running)
	Input.action_press("fire")
	Input.action_press("thrust_forward")
	await _frames(60)
	Input.action_release("fire")
	Input.action_release("thrust_forward")
	_check("exported flight and weapons run", GameMatch.pilots.YOU.shots > 0 and GameMatch.remaining < GameConfig.MATCH_SECONDS and _main.player.global_position.is_finite())
	var finite := true
	for entry: Dictionary in _main._roster:
		finite = finite and entry.ship.global_position.is_finite() and entry.ship.global_basis.is_finite()
	_check("all exported pilots retain finite transforms", finite)
	await _screenshot("flight")
	await _key(KEY_ESCAPE)
	var clock := GameMatch.remaining
	var position: Vector3 = _main.player.global_position
	await _frames(10)
	_check("pause freezes the exported battle", get_tree().paused and _main.menu.page == "pause" and GameMatch.remaining == clock and position.is_equal_approx(_main.player.global_position))
	_check("pause stops flight sounds and retains menu audio", not Sfx._engine_player.playing and Sfx._music_player.playing)
	await _activate("Settings")
	(_main.menu._frame.get_node("music_volume") as HSlider).value = 0.35
	GameSettings.load_preferences()
	_check("exported audio preferences save and reload", is_equal_approx(float(GameSettings.get_value("music_volume")), 0.35) and GameSettings.last_save_error == OK)
	await _screenshot("settings")
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	_check("settings returns to live combat", _main.state == _main.State.PLAYING and not get_tree().paused)
	for entry: Dictionary in _main._roster:
		entry.ship.set_physics_process(false)
	var victim: Node3D = _main._roster[-1].ship
	victim.take_damage(200, _main.player)
	_check("exported damage awards score and persistent pilot credit", GameMatch.scores[0] == 1 and GameMatch.pilots.YOU.kills == 1)
	GameMatch.remaining = 0.01
	await _frames(4)
	_check("exported round resolves to victory and freezes", _main.state == _main.State.RESULTS and GameMatch.winner == GameConfig.TEAM_BLUE and get_tree().paused)
	await _screenshot("debrief")
	await _activate("PlayAgain")
	_check("replay clears scores and replaces the fleet", _main.state == _main.State.PLAYING and not get_tree().paused and GameMatch.scores[0] == 0 and _main._roster.size() == 6)
	await _key(KEY_ESCAPE)
	await _activate("ReturnTitle")
	_check("return to command clears the fleet and effects", _main.state == _main.State.TITLE and _main.player == null and _main._roster.is_empty() and _main.effects_root.get_child_count() == 0)
	await _screenshot("title")
	DirAccess.remove_absolute(GameSettings.storage_path)
	GameSettings.storage_path = _settings_path
	GameSettings.values = _preferences
	GameSettings._apply()
	print("--- release smoke: %d checks, %d failures ---" % [_checks, _failures])
	if _failures:
		_main._show_title()
		_main.queue_free()
		await get_tree().process_frame
		await Sfx.finish_audio()
		get_tree().quit(1)
	else:
		await _main._quit()


func _pack_files(directory: String) -> PackedStringArray:
	var files := PackedStringArray()
	for name: String in DirAccess.get_files_at(directory):
		files.append(directory.path_join(name))
	for child: String in DirAccess.get_directories_at(directory):
		files.append_array(_pack_files(directory.path_join(child)))
	return files


func _activate(name: String) -> void:
	(_main.menu._frame.get_node(name) as Control).grab_focus()
	await _key(KEY_ENTER)


func _key(code: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	Input.parse_input_event(key)
	await _frames(2)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await _frames(2)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _screenshot(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png(args[0].path_join(name + ".png"))
	_check("native release capture " + name, result == OK)


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
