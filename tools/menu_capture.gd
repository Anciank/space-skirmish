extends Node
## Render the real front end and round transitions for visual review.
## godot --path . res://tools/menu_capture.tscn -- /tmp/star-skirmish-menu

var _main: Node3D
var _out := "/tmp/star-skirmish-menu"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.get_cmdline_user_args().is_empty():
		_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _capture("title")
	_main.menu.show_credits()
	await _capture("credits")
	_main.menu.go_back()
	_main.menu.show_controls()
	await _capture("handbook")
	_main.menu.go_back()
	_main.menu.show_settings()
	await _capture("settings")
	_main.menu.go_back()
	_main.menu.launch_requested.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await _capture("flight")
	Input.action_press("scoreboard")
	await _capture("scoreboard")
	Input.action_release("scoreboard")
	_main.player.take_damage(200)
	await _capture("destroyed")
	for pending: Dictionary in _main._pending:
		if pending.name == "YOU":
			pending.left = 0.01
	await _capture("redeploy")
	await _key()
	await _capture("pause")
	_main.menu.show_settings()
	await _capture("pause-settings")
	await _key()
	await _key()
	# Generate a debrief through the real damage/scoring path.
	var victim: SpaceShip = null
	for entry: Dictionary in _main._roster:
		var ship: SpaceShip = entry.ship
		if ship.team == GameConfig.TEAM_RED and not ship.dead:
			victim = ship
			break
	if victim != null:
		victim.take_damage(200, _main.player)
	GameMatch.remaining = 0.01
	await _capture("debrief")
	_main.menu.restart_requested.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	GameMatch.finish_match()
	await _capture("draw")
	_main._show_title()
	await get_tree().process_frame
	_main.menu._frame.get_node("Quit").grab_focus()
	await _key(KEY_ENTER)


func _capture(caption: String) -> void:
	for _i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, caption]
	var error := texture.save_png(path)
	print("capture %s: %dx%d, error=%d" % [path, texture.get_width(), texture.get_height(), error])


func _key(code: Key = KEY_ESCAPE) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = code
	key.keycode = code
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	await get_tree().process_frame
