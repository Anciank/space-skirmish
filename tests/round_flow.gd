extends Node
## Real-menu integration: boot, deploy, pause, settings, respawn, debrief and replay.

var _main: Node3D
var _checks := 0
var _failures := 0
var _original_settings: Dictionary
var _original_path: String


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_original_settings = GameSettings.values.duplicate()
	_original_path = GameSettings.storage_path
	GameSettings.storage_path = "user://round-flow-test.cfg"
	GameSettings.reset_to_defaults(false)
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	await _run()
	_main._show_title()
	_main.queue_free()
	await _frames(3)
	GameSettings.values = _original_settings
	GameSettings.storage_path = _original_path
	GameSettings._apply()
	DirAccess.remove_absolute("user://round-flow-test.cfg")
	await Sfx.finish_audio()
	print("--- round flow: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _run() -> void:
	print("--- round flow ---")
	_check("boot waits at command screen", _main.menu.page == "title" and _main.player == null)
	_check("clock waits for deployment", not GameMatch.running)
	var full_time := GameMatch.remaining
	await _frames(5)
	_check("no battle runs behind title", GameMatch.remaining == full_time and _main._roster.is_empty())
	await _activate("Settings")
	_check("keyboard opens settings", _main.menu.page == "settings")
	var sensitivity := _main.menu._frame.get_node("mouse_sensitivity") as HSlider
	sensitivity.value = 1.75
	GameSettings.set_value("invert_y", true)
	_check("settings changes persist", GameSettings.last_save_error == OK)
	GameSettings.values = GameSettings.DEFAULTS.duplicate()
	GameSettings.load_preferences()
	_check("preferences survive reload", is_equal_approx(float(GameSettings.get_value("mouse_sensitivity")), 1.75) and bool(GameSettings.get_value("invert_y")))
	# A damaged or hand-edited preference file must not poison flight transforms.
	var malformed := ConfigFile.new()
	malformed.set_value("player", "mouse_sensitivity", "bad")
	malformed.set_value("player", "field_of_view", 500.0)
	malformed.set_value("player", "invert_y", "yes")
	malformed.save(GameSettings.storage_path)
	GameSettings.load_preferences()
	_check("invalid preferences recover safely", GameSettings.get_value("mouse_sensitivity") == 1.0 and GameSettings.get_value("field_of_view") == 100.0 and GameSettings.get_value("invert_y") == false)
	GameSettings.reset_to_defaults(false)
	await _key(KEY_ESCAPE)
	_check("escape returns from settings", _main.menu.page == "title")
	await _activate("Deploy")
	_check("keyboard deploys the real roster", _main.state == _main.State.PLAYING and _main._roster.size() == 6)
	_check("balanced three-on-three battle", GameMatch.pilots.size() == 6 and _main.enemy_count == _main.ally_count + 1)
	_check("deployment captures aim and hides menu", bool(_main.player._mouse_captured) and not _main.menu.visible)
	_check("camera starts on ship", _main.rig.global_position.distance_to(_main.player.global_position) < 15.0)
	await _key(KEY_ESCAPE)
	_check("escape opens interactive pause", _main.paused and get_tree().paused and _main.menu.page == "pause")
	var clock := GameMatch.remaining
	var positions: Array[Vector3] = []
	for row: Dictionary in _main._roster:
		positions.append(row.ship.global_position)
	await _frames(10)
	_check("pause freezes the clock", GameMatch.remaining == clock)
	var stationary := true
	for i in _main._roster.size():
		stationary = stationary and positions[i].is_equal_approx(_main._roster[i].ship.global_position)
	_check("pause freezes all ship physics", stationary)
	await _activate("Settings")
	_check("settings work during pause", _main.menu.page == "settings" and get_tree().paused)
	GameSettings.set_value("field_of_view", 92.0, false)
	_check("field of view applies to live camera", is_equal_approx(_main.rig.base_fov, 92.0))
	await _key(KEY_ESCAPE)
	_check("settings back preserves pause", _main.menu.page == "pause" and _main.paused)
	await _key(KEY_ESCAPE)
	_check("second escape resumes real gameplay", not get_tree().paused and not _main.paused and not _main.menu.visible)
	# Repeated deaths must replace a roster entry instead of accumulating corpses.
	for iteration in 3:
		var player: SpaceShip = _main.player
		var killer: SpaceShip = _enemy()
		player.take_damage(10000, killer)
		_check("death queues exactly one player redeploy %d" % iteration, _main._pending.filter(func(row: Dictionary): return row.name == "YOU").size() == 1)
		await _frames(2)
		for pending: Dictionary in _main._pending:
			if pending.name == "YOU":
				pending.left = 0.0
		_main._update_respawns(0.0)
		await _frames(2)
		_check("respawn retains six roster slots %d" % iteration, _main._roster.size() == 6 and _main.ships_root.get_child_count() == 6)
		_check("respawn gives a fresh live player %d" % iteration, is_instance_valid(_main.player) and _main.player != player and not _main.player.dead and _main.hud.player == _main.player)
	_check("pilot deaths persist across ships", GameMatch.pilots.YOU.deaths == 3)
	# Scores, damage and shots are recorded through the actual ship signals.
	var victim: SpaceShip = _enemy()
	_main.player._fire_timer = 0.0
	_main.player.fire()
	victim.take_damage(10000, _main.player)
	_check("enemy destruction awards one point", GameMatch.scores[0] == 1 and GameMatch.pilots.YOU.kills == 1)
	_check("debrief records effective damage and shots", is_equal_approx(GameMatch.pilots.YOU.damage, 200.0) and GameMatch.pilots.YOU.shots == 1)
	GameMatch.remaining = 0.01
	await _frames(4)
	_check("time expiry opens debrief and freezes combat", _main.state == _main.State.RESULTS and _main.menu.page == "results" and get_tree().paused)
	_check("higher-scoring team wins", GameMatch.winner == GameConfig.TEAM_RED)
	_check("pending redeploys are cleared at round end", _main._pending.is_empty())
	var scores := GameMatch.scores.duplicate()
	var ledger := GameMatch.pilots.duplicate(true)
	GameMatch.add_score(0)
	GameMatch.log_kill("YOU", 0, "CR-01", 1)
	GameMatch.record_damage("YOU", 1000.0)
	await _frames(6)
	_check("finished scores and stats remain immutable", scores == GameMatch.scores and ledger == GameMatch.pilots)
	await _activate("PlayAgain")
	_check("replay resumes a fresh round", _main.state == _main.State.PLAYING and not get_tree().paused and GameMatch.running)
	_check("replay resets every pilot statistic", GameMatch.pilots.YOU.kills == 0 and GameMatch.pilots.YOU.deaths == 0 and GameMatch.pilots.YOU.damage == 0.0)
	_check("replay clears old projectiles", _main.effects_root.get_child_count() == 0)
	GameMatch.remaining = 0.01
	await _frames(4)
	_check("equal scores produce a draw", GameMatch.winner == GameMatch.DRAW)
	await _activate("ReturnTitle")
	_check("debrief returns to a clean command screen", _main.state == _main.State.TITLE and _main.player == null and _main._roster.is_empty() and not GameMatch.running)
	await _activate("Deploy")
	await _key(KEY_ESCAPE)
	await _activate("Restart")
	_check("pause restart resumes safely", not get_tree().paused and _main._roster.size() == 6 and _main.state == _main.State.PLAYING)


func _enemy() -> SpaceShip:
	for row: Dictionary in _main._roster:
		var ship: SpaceShip = row.ship
		if ship.team == GameConfig.TEAM_RED and not ship.dead:
			return ship
	return null


func _activate(node_name: String) -> void:
	(_main.menu._frame.get_node(node_name) as Control).grab_focus()
	await _key(KEY_ENTER)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
