extends Node3D
## Match bootstrap and lifecycle.
##
## Spawns the roster (player + allies + hostiles), rebuilds destroyed ships
## after a delay, owns the pause / restart flow, and wires the HUD and camera
## rig to the player ship.

const PLAYER_SCENE := preload("res://scenes/ships/player_ship.tscn")
const AI_SCENE := preload("res://scenes/ships/ai_ship.tscn")

@export var ally_count := 2
@export var enemy_count := 2
## Base AI competence; each pilot rolls a small offset around it.
@export_range(0.4, 1.8) var ai_skill := 1.0

@onready var arena: Node3D = $Arena
@onready var ships_root: Node3D = $Ships
@onready var effects_root: Node3D = $Effects
@onready var rig: CameraRig = $CameraRig
@onready var hud: Control = $UI/HUD

var player: SpaceShip = null
var paused := false

var _rng := RandomNumberGenerator.new()
## One entry per live ship: {ship, scene, team, name, skill}
var _roster: Array[Dictionary] = []
## Ships awaiting redeployment: roster entry + `left` countdown.
var _pending: Array[Dictionary] = []
var _match_active := true


func _ready() -> void:
	_rng.randomize()
	GameMatch.match_finished.connect(_on_match_finished)
	_start_match()


# ================================================================== setup ==

func _start_match() -> void:
	_clear_fleet()
	GameMatch.reset_match()
	_match_active = true
	hud.match_over = false
	hud.match_winner = -1

	_spawn_player()
	for i in ally_count:
		_spawn_ai(GameConfig.TEAM_BLUE, "AZ-%02d" % (i + 1), _roll_skill())
	for i in enemy_count:
		_spawn_ai(GameConfig.TEAM_RED, "CR-%02d" % (i + 1), _roll_skill())

	_bind_player(player)
	rig.add_shake(0.4)


func _clear_fleet() -> void:
	for entry: Dictionary in _roster:
		var ship := entry.ship as Node
		if is_instance_valid(ship):
			ship.queue_free()
	_roster.clear()
	_pending.clear()


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


func _place_ship(ship: SpaceShip) -> void:
	var others: Array = []
	for entry: Dictionary in _roster:
		var other := entry.ship as Node3D
		if other != null and other != ship and is_instance_valid(other):
			others.append(other.global_position)
	var pos: Vector3 = arena.spawn_position(others, 300.0)
	ship.respawn_at(pos, pos + Vector3.FORWARD)


func _bind_player(ship: SpaceShip) -> void:
	player = ship
	hud.setup(ship, rig)
	rig.target = ship


# ================================================================= runtime =

func _process(delta: float) -> void:
	_update_respawns(delta)
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

func _on_ship_destroyed(killer: Node, ship: SpaceShip) -> void:
	var killer_name := ""
	var killer_team := -1
	if killer is SpaceShip and is_instance_valid(killer):
		killer_name = (killer as SpaceShip).display_name
		killer_team = (killer as SpaceShip).team
		if (killer as SpaceShip).is_player:
			hud.register_hit_kill()

	GameMatch.log_kill(killer_name, killer_team, ship.display_name, ship.team)
	if killer_team >= 0:
		GameMatch.add_score(killer_team)

	_explode(ship.global_position, ship.forward().lerp(Vector3.UP, 0.35).normalized())

	if ship == player:
		rig.add_shake(2.2)
		player.capture_mouse(false)

	if not _match_active:
		return

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
	_roster.erase(entry)
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
		rig.add_shake(0.5)
		ship.capture_mouse(not paused)
		Sfx.play_local("impact", -8.0, 7.0)


func _explode(position: Vector3, direction: Vector3) -> void:
	var fx := ExplosionFx.new()
	effects_root.add_child(fx)
	fx.global_position = position
	fx.radius = 7.0
	fx.tint = Color(1.0, 0.74, 0.36)
	Sfx.play_at("explosion_big", position, 0.0, _rng.randf_range(-0.3, 0.3), 2400.0)
	for i in 6:
		var spark := Spark.new()
		effects_root.add_child(spark)
		spark.setup(position + direction * _rng.randf_range(1.0, 7.0), direction, Color(1.0, 0.66, 0.3))
		spark.life = 0.36
		spark.start_scale = 1.0
		spark.end_scale = 6.0


# =================================================================== input =

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if hud.match_over:
			return
		_set_paused(not paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		_set_paused(false)
		_start_match()
		get_viewport().set_input_as_handled()
	elif paused and event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_R:
			_set_paused(false)
			_start_match()
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_Q:
			_set_paused(false)
			get_tree().quit()


func _set_paused(on: bool) -> void:
	paused = on
	get_tree().paused = on
	hud.hud_paused = on
	if player != null and is_instance_valid(player):
		player.set_process_unhandled_input(not on)
		player.capture_mouse(not on)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_set_paused(false)
		get_tree().quit()


func _on_match_finished(winner: int) -> void:
	hud.match_over = true
	hud.match_winner = winner
	_match_active = false
	if player != null and is_instance_valid(player):
		player.capture_mouse(false)
