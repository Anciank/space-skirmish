extends Node
## Record the actual native mix with --write-movie review.avi --fixed-fps 60.

var _main: Node3D
var _out := "/tmp/star-skirmish-audio"
var _preferences: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preferences = GameSettings.values.duplicate()
	GameSettings.reset_to_defaults(false)
	if not OS.get_cmdline_user_args().is_empty():
		_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out.path_join("clips"))
	for cue: String in Sfx._bank:
		var wav: AudioStreamWAV = Sfx._bank[cue]
		if wav.save_to_wav(_out.path_join("clips").path_join(cue + ".wav")) != OK:
			push_error("Cannot save audio review clip: " + cue)
	for pair: Array in [["engine", Sfx._engine_player], ["score", Sfx._music_player], ["pulse", Sfx._pulse_player]]:
		(pair[1].stream as AudioStreamWAV).save_to_wav(_out.path_join("clips").path_join(pair[0] + ".wav"))
	_main = load("res://scenes/main.tscn").instantiate()
	_main.ally_count = 0
	_main.enemy_count = 1
	add_child(_main)
	await _seconds(3.0)
	_main.menu.show_controls()
	Sfx.play_ui()
	await _seconds(1.0)
	_main.menu.go_back()
	_main.menu.show_settings()
	Sfx.play_ui()
	await _seconds(1.0)
	_main._start_match()
	_main.arena.process_mode = Node.PROCESS_MODE_DISABLED
	for rock: Node in get_tree().get_nodes_in_group("rocks"):
		rock.freeze = true
		rock.collision_layer = 0
	for body: Node in get_tree().get_nodes_in_group("bodies"):
		body.collision_layer = 0
	var player: SpaceShip = _main.player
	var enemy: SpaceShip = _main._roster[1].ship
	player.respawn_at(Vector3(0, 430, 0), Vector3(0, 430, -150))
	enemy.global_position = Vector3(0, 430, -150)
	enemy.set_physics_process(false)
	_main.hud.locked = enemy
	_main.rig.snap_to_target()
	_main.hud.cycle_target()
	Input.action_press("fire")
	await _seconds(4.0)
	Input.action_release("fire")
	Input.action_press("thrust_forward")
	Input.action_press("boost")
	await _seconds(2.0)
	Input.action_release("boost")
	Input.action_release("thrust_forward")
	player.velocity = Vector3.ZERO
	player.take_damage(12, null, player.global_position + Vector3.RIGHT)
	await _seconds(1.0)
	player.take_damage(player.shield + 80.0, null, player.global_position + Vector3.RIGHT)
	await _seconds(1.0)
	_main._set_paused(true)
	await _seconds(1.0)
	_main._set_paused(false)
	await _seconds(1.0)
	player.take_damage(200, null, player.global_position + Vector3.RIGHT)
	await _seconds(6.0)
	GameMatch.add_score(GameConfig.TEAM_BLUE)
	GameMatch.finish_match()
	await _seconds(1.0)
	GameSettings.values = _preferences
	GameSettings._apply()
	print("Audio review complete: command, combat, boost, damage, pause, death, redeploy and debrief.")
	await _main._quit()


func _seconds(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
