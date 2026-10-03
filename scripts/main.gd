extends Node3D
## Match bootstrap and lifecycle.
##
## Spawns the roster (player + allies + hostiles), rebuilds destroyed ships
## after a delay, owns the pause / restart flow, and wires the HUD and camera
## rig to the player ship.

const PLAYER_SCENE := preload("res://scenes/ships/player_ship.tscn")
const AI_SCENE := preload("res://scenes/ships/ai_ship.tscn")
const MENU_SCRIPT := preload("res://scripts/flight_menu.gd")
const DISPLAY_MODEL := preload("res://scenes/ships/ship_model.tscn")

enum State { TITLE, PLAYING, PAUSED, RESULTS }

@export_range(0, 31, 1) var ally_count := 31
@export_range(0, 32, 1) var enemy_count := 32
@export var start_in_menu := true
## Base AI competence; each pilot rolls a small offset around it.
@export_range(0.4, 1.8) var ai_skill := 1.0

@onready var arena: Node3D = $Arena
@onready var ships_root: Node3D = $Ships
@onready var effects_root: Node3D = $Effects
@onready var rig: CameraRig = $CameraRig
@onready var hud: Control = $UI/HUD

var player: SpaceShip = null
var paused := false
## Native review tools can opt out without changing normal focus-loss pausing.
var pause_on_focus_loss := true
var state := State.TITLE
var menu: FlightMenu
var _preview: ShipVisual
var _preview_time := 0.0
var _requested_transition := ""
var _quitting := false

var _rng := RandomNumberGenerator.new()
## One entry per live ship: {ship, scene, team, name, skill}
var _roster: Array[Dictionary] = []
## Ships awaiting redeployment: roster entry + `left` countdown.
var _pending: Array[Dictionary] = []
var _match_active := false
var _minute_warning := false


func _ready() -> void:
	# Only the controller and menus continue through pause; gameplay children
	# explicitly use PAUSABLE in the scene, so physics and the clock truly stop.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().auto_accept_quit = false
	_rng.randomize()
	GameMatch.match_finished.connect(_on_match_finished)
	menu = MENU_SCRIPT.new()
	$UI.add_child(menu)
	menu.launch_requested.connect(_request_transition.bind("start"))
	menu.restart_requested.connect(_request_transition.bind("start"))
	menu.resume_requested.connect(_set_paused.bind(false))
	menu.title_requested.connect(_request_transition.bind("title"))
	menu.quit_requested.connect(_quit)
	_preview = DISPLAY_MODEL.instantiate()
	_preview.name = "HangarPreview"
	_preview.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_preview)
	_preview.set_livery(GameConfig.team_color(GameConfig.TEAM_BLUE))
	# The command display is an isolated ship inspection, clear of field shadows.
	# Layer 2 keeps its unshadowed key from changing the live battle lighting.
	for part: Node in _preview.find_children("*", "MeshInstance3D", true, false):
		(part as MeshInstance3D).layers = 2
	var inspection_key := (arena.get_node("Sun") as DirectionalLight3D).duplicate() as DirectionalLight3D
	inspection_key.name = "InspectionKey"
	inspection_key.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	inspection_key.light_cull_mask = 2
	inspection_key.shadow_enabled = false
	inspection_key.light_energy = 1.85
	add_child(inspection_key)
	inspection_key.global_basis = (arena.get_node("Sun") as DirectionalLight3D).global_basis
	if start_in_menu:
		_show_title()
	else:
		_start_match()


# ================================================================== setup ==

func _start_match(use_preferences := true) -> void:
	# Menu deployments share the persisted selection. Direct-start scenes
	# keep their explicit fixture counts for duels, captures and simulations.
	if start_in_menu and use_preferences:
		ally_count = int(GameSettings.get_value("ally_count"))
		enemy_count = int(GameSettings.get_value("enemy_count"))
	ally_count = clampi(ally_count, GameSettings.MIN_ALLY_COUNT, GameSettings.MAX_ALLY_COUNT)
	enemy_count = clampi(enemy_count, GameSettings.MIN_ENEMY_COUNT, GameSettings.MAX_ENEMY_COUNT)
	get_tree().paused = false
	paused = false
	state = State.PLAYING
	menu.hide()
	_preview.hide()
	_clear_fleet()
	_clear_effects()
	GameMatch.reset_match()
	_match_active = true
	_minute_warning = false
	Sfx.set_context("flight")
	Sfx.play_ui("deploy", -12.0)
	ai_skill = float(GameSettings.AI_SKILLS[int(GameSettings.get_value("difficulty"))])
	hud.show()

	_spawn_player()
	for i in ally_count:
		_spawn_ai(GameConfig.TEAM_BLUE, "AZ-%02d" % (i + 1), _roll_skill())
	for i in enemy_count:
		_spawn_ai(GameConfig.TEAM_RED, "CR-%02d" % (i + 1), _roll_skill())

	_bind_player(player)
	rig.snap_to_target()
	rig.add_shake(0.4)


func _clear_fleet() -> void:
	for entry: Dictionary in _roster:
		var ship := entry.ship as Node
		if is_instance_valid(ship):
			ship.get_parent().remove_child(ship)
			ship.queue_free()
	_roster.clear()
	_pending.clear()
	player = null
	hud.player = null
	hud.locked = null
	rig.target = null


func _clear_effects() -> void:
	for child in effects_root.get_children():
		effects_root.remove_child(child)
		child.queue_free()
	Sfx.stop_combat_audio()


func _show_title() -> void:
	get_tree().paused = false
	paused = false
	state = State.TITLE
	_match_active = false
	GameMatch.running = false
	_clear_fleet()
	_clear_effects()
	Sfx.set_context("command")
	hud.hide()
	_preview.show()
	rig.global_position = Vector3(0, 100, 360)
	rig.look_at(Vector3(0, 60, 0))
	rig.camera.fov = 68.0
	menu.show_title()


func _animate_preview(delta: float) -> void:
	_preview_time += delta
	(get_node("InspectionKey") as DirectionalLight3D).global_basis = rig.camera.global_basis * Basis.looking_at(Vector3(-0.35, -0.5, -1).normalized(), Vector3.UP)
	_preview.update_motion(0.0, false, delta)
	var offset := Vector3(6.8, 3.25 + sin(_preview_time * 0.5) * 0.12, -18.0)
	var inspection_angle := Vector3(8.0 + sin(_preview_time * 0.18) * 0.6, 4.5, -9.0)
	var pose := Basis.looking_at(offset.normalized(), Vector3.UP) * Basis.looking_at(-inspection_angle.normalized(), Vector3.UP).inverse()
	_preview.global_transform = rig.camera.global_transform * Transform3D(pose.scaled(Vector3.ONE * 1.6), offset)


func _request_transition(destination: String) -> void:
	if not _quitting:
		_requested_transition = destination


func _roll_skill() -> float:
	return clampf(ai_skill + _rng.randf_range(-0.14, 0.14), 0.4, 1.8)


func _spawn_player() -> void:
	var ship: SpaceShip = PLAYER_SCENE.instantiate()
	ship.is_player = true
	ship.team = GameConfig.TEAM_BLUE
	ship.display_name = "YOU"
	ships_root.add_child(ship)
	_place_ship(ship)
	player = ship
	_register(ship, PLAYER_SCENE, ship.team, ship.display_name, 1.0)


func _spawn_ai(team: int, ship_name: String, skill: float) -> void:
	var ship: SpaceShip = AI_SCENE.instantiate()
	ship.team = team
	ship.display_name = ship_name
	ship.skill = clampf(skill, 0.4, 1.8)
	ships_root.add_child(ship)
	_place_ship(ship)
	_register(ship, AI_SCENE, team, ship_name, skill)


func _register(ship: SpaceShip, scene_res: PackedScene, team: int, ship_name: String, skill: float) -> void:
	_roster.append({
		"ship": ship, "scene": scene_res, "team": team,
		"name": ship_name, "skill": skill,
	})
	ship.destroyed.connect(_on_ship_destroyed.bind(ship))
	ship.took_damage.connect(_on_ship_damaged.bind(ship))
	ship.weapon_fired.connect(GameMatch.record_shot.bind(ship_name))
	GameMatch.register_pilot(ship_name, team)


func _place_ship(ship: SpaceShip) -> void:
	var others: Array = []
	for entry: Dictionary in _roster:
		var other := entry.ship as Node3D
		if other != null and other != ship and is_instance_valid(other):
			others.append(other.global_position)
	var pos: Vector3 = arena.spawn_position(others, 300.0)
	ship.respawn_at(pos, Vector3.ZERO)


func _bind_player(ship: SpaceShip) -> void:
	player = ship
	ship.aim_camera = rig.camera
	ship.aim_source = rig
	hud.setup(ship, rig)
	rig.target = ship


# ================================================================= runtime =

func _process(delta: float) -> void:
	if _quitting:
		return
	# Resume at a process boundary. Resuming physics from call_deferred can
	# execute a step without flushing body queries in Godot 4.x.
	var destination := _requested_transition
	_requested_transition = ""
	if destination == "start":
		_start_match()
	elif destination == "title":
		_show_title()
	if state == State.TITLE:
		_animate_preview(delta)
	if state != State.PLAYING:
		return
	_update_respawns(delta)
	if not _minute_warning and GameMatch.remaining <= 60.0:
		_minute_warning = true
		Sfx.play_local("minute", -13.0)
	if Input.is_action_just_pressed("next_target"):
		hud.cycle_target()
	if player != null and is_instance_valid(player):
		player.set_meta("respawn_in", _respawn_left_for(player))
		player.update_engine_audio()
		if player.consumes_camera_toggle():
			rig.toggle_mode()
	else:
		Sfx.set_engine(0.0, 0.0, false)


func _update_respawns(delta: float) -> void:
	if not _match_active:
		return
	# Drop roster entries whose node has gone away (defensive: a ship can be
	# freed by a scene change or a future gameplay system).
	var i := _roster.size() - 1
	while i >= 0:
		var entry: Dictionary = _roster[i]
		if not is_instance_valid(entry.ship):
			_roster.remove_at(i)
		i -= 1

	i = _pending.size() - 1
	while i >= 0:
		var entry: Dictionary = _pending[i]
		entry.left = maxf(0.0, float(entry.left) - delta)
		if float(entry.left) <= 0.0:
			_pending.remove_at(i)
			_rebuild(entry)
		i -= 1


func _respawn_left_for(ship: SpaceShip) -> float:
	for entry: Dictionary in _pending:
		if entry.ship == ship:
			return float(entry.left)
	return 0.0


# ================================================================ lifecycle =

func _on_ship_damaged(amount: float, _pos: Vector3, _attacker: Node, victim: SpaceShip) -> void:
	if not victim.last_damage_pilot.is_empty():
		GameMatch.record_damage(victim.last_damage_pilot, amount)
		if victim.last_damage_pilot == "YOU":
			hud.register_hit()

func _on_ship_destroyed(killer: Node, ship: SpaceShip) -> void:
	if not _match_active:
		return
	var killer_name := ship.last_damage_pilot
	var killer_team := ship.last_damage_team
	if is_instance_valid(killer) and killer is SpaceShip:
		killer_name = (killer as SpaceShip).display_name
		killer_team = (killer as SpaceShip).team
	if killer_name == "YOU":
		hud.register_hit_kill()

	GameMatch.log_kill(killer_name, killer_team, ship.display_name, ship.team, ship.last_damage_cause)

	_explode(ship.global_position, ship.forward().lerp(Vector3.UP, 0.35).normalized())

	if ship == player:
		Sfx.set_engine(0.0, 0.0, false)
		Sfx.play_ui("death", -10.0)
		rig.add_shake(2.2)
		player.set_meta("respawn_in", GameConfig.RESPAWN_DELAY)
		player.capture_mouse(false)

	var idx := _roster.find_custom(func(e: Dictionary) -> bool: return e.ship == ship)
	if idx == -1:
		return
	var entry: Dictionary = _roster[idx]
	_pending.append({
		"ship": ship,
		"scene": entry.scene,
		"team": entry.team,
		"name": entry.name,
		"skill": entry.skill,
		"left": GameConfig.RESPAWN_DELAY,
	})


func _rebuild(entry: Dictionary) -> void:
	var old_ship := entry.ship as SpaceShip
	var scene_res: PackedScene = entry.scene
	# Pending entries also have a countdown. Remove by ship identity instead of
	# comparing the two different dictionaries, which leaked old roster entries.
	var old_index := _roster.find_custom(func(row: Dictionary) -> bool: return row.ship == old_ship)
	if old_index >= 0:
		_roster.remove_at(old_index)
	if old_ship != null and is_instance_valid(old_ship):
		old_ship.queue_free()

	var ship: SpaceShip = scene_res.instantiate()
	ship.team = int(entry.team)
	ship.display_name = String(entry.name)
	ship.is_player = scene_res == PLAYER_SCENE
	if ship is AIShip:
		(ship as AIShip).skill = clampf(float(entry.skill), 0.4, 1.8)
	ships_root.add_child(ship)
	_place_ship(ship)
	_register(ship, scene_res, int(entry.team), String(entry.name), float(entry.skill))

	if ship.is_player:
		_bind_player(ship)
		rig.snap_to_target()
		rig.add_shake(0.5)
		ship.capture_mouse(not paused)
		Sfx.play_ui("deploy", -12.0)


func _explode(position: Vector3, direction: Vector3) -> void:
	var fx := ExplosionFx.new()
	fx.radius = 7.0
	fx.tint = Color(1.0, 0.74, 0.36)
	effects_root.add_child(fx)
	fx.global_position = position
	Sfx.play_at("explosion_big", position, 0.0, _rng.randf_range(-0.3, 0.3), 2400.0)
	for i in 6:
		var spark := Spark.new()
		effects_root.add_child(spark)
		spark.setup(position + direction * _rng.randf_range(1.0, 7.0), direction, Color(1.0, 0.66, 0.3))
		spark.life = 0.28
		spark.start_scale = 0.3
		spark.end_scale = 0.9


# =================================================================== input =

func _unhandled_input(event: InputEvent) -> void:
	if _quitting:
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("pause"):
		if menu.visible:
			menu.go_back()
		elif state == State.PLAYING:
			_set_paused(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart") and state != State.TITLE:
		_request_transition("start")
		get_viewport().set_input_as_handled()


func _set_paused(on: bool) -> void:
	if state != State.PLAYING and state != State.PAUSED:
		return
	paused = on
	state = State.PAUSED if on else State.PLAYING
	get_tree().paused = on
	if on:
		Sfx.stop_combat_audio()
		Sfx.set_context("pause")
		Sfx.play_ui("ui_back")
		hud.hide()
		menu.show_pause()
	else:
		Sfx.set_context("flight")
		menu.hide()
		hud.show()
	if player != null and is_instance_valid(player):
		player.set_process_unhandled_input(not on)
		player.capture_mouse(not on and not player.dead)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT and pause_on_focus_loss and state == State.PLAYING:
		_set_paused(true)


func _quit() -> void:
	if _quitting:
		return
	_quitting = true
	_requested_transition = ""
	_match_active = false
	menu.hide()
	get_tree().paused = false
	GameMatch.running = false
	state = State.TITLE
	_clear_fleet()
	_clear_effects()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await Sfx.finish_audio()
	get_tree().quit()


func _on_match_finished(_winner: int) -> void:
	if not _match_active:
		return
	_match_active = false
	state = State.RESULTS
	hud.hide()
	_pending.clear()
	get_tree().paused = true
	Sfx.stop_combat_audio()
	Sfx.set_context("results")
	Sfx.play_ui("victory" if _winner == GameConfig.TEAM_BLUE else ("ui_select" if _winner == GameMatch.DRAW else "defeat"), -10.0)
	if player != null and is_instance_valid(player):
		player.set_process_unhandled_input(false)
		player.capture_mouse(false)
	menu.show_results()
