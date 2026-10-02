extends Node
## Weapon reach, obstructed firing solutions, cockpit radar and environmental kills.

var _main: Node3D
var _checks := 0
var _failures := 0


func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	_main.start_in_menu = false
	_main.ally_count = 1
	_main.enemy_count = 1
	add_child(_main)
	_main.set_process(false)
	_main.arena.process_mode = Node.PROCESS_MODE_DISABLED
	GameMatch.set_process(false)
	for body: Node in get_tree().get_nodes_in_group("rocks") + get_tree().get_nodes_in_group("bodies"):
		body.collision_layer = 0
	for entry: Dictionary in _main._roster:
		entry.ship.set_physics_process(false)
	var player: SpaceShip = _main.player
	var enemy: SpaceShip = _main._roster[2].ship
	var ally: SpaceShip = _main._roster[1].ship
	var hud: Control = _main.hud
	player.global_position = Vector3(0, 500, 0)
	player.global_basis = Basis.IDENTITY
	player.velocity = Vector3.ZERO
	enemy.velocity = Vector3.ZERO
	ally.global_position = Vector3(200, 500, 0)
	hud.locked = enemy
	_main.rig.snap_to_target()
	enemy.global_position = player.global_position + Vector3.FORWARD * 180.0
	await _step()
	_check("reachable contact has a visible intercept pip", hud._solution_status == "FIRING SOLUTION" and hud._lead_screen_point() != Vector2.INF)
	enemy.global_position = player.global_position + Vector3.FORWARD * 600.0
	await _step()
	_check("beyond projectile lifetime is explicitly out of range", hud._solution_status == "OUT OF RANGE" and hud._lead_screen_point() == Vector2.INF)
	enemy.global_position = player.global_position + Vector3.FORWARD * 100.0
	enemy.velocity = Vector3.FORWARD * 650.0
	await _step()
	_check("unreachable moving target has no false firing solution", hud._solution_status == "OUT OF RANGE")
	enemy.velocity = Vector3.ZERO
	enemy.global_position = player.global_position + Vector3.BACK * 100.0
	await _step()
	_check("behind-the-nose lock asks the pilot to turn", hud._solution_status == "TURN TO TARGET" and hud._lead_screen_point() == Vector2.INF)
	enemy.global_position = player.global_position + Vector3.FORWARD * 180.0
	var rock := StaticBody3D.new()
	rock.collision_layer = GameConfig.LAYER_ROCK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 20.0
	shape.shape = box
	rock.add_child(shape)
	add_child(rock)
	rock.global_position = player.global_position + Vector3.FORWARD * 90.0
	await _step()
	_check("a rock blocks the solution and hides the lead pip", hud._solution_status == "LINE OF FIRE BLOCKED" and hud._lead_screen_point() == Vector2.INF)
	rock.collision_layer = 0
	ally.global_position = rock.global_position
	await _step()
	_check("a friendly ship also blocks the line of fire", hud._solution_status == "LINE OF FIRE BLOCKED")
	ally.global_position = Vector3(200, 500, 0)
	await _step()
	_check("clearing the obstruction restores guidance", hud._solution_status == "FIRING SOLUTION")
	player.velocity = Vector3(75, 0, 0)
	enemy.velocity = Vector3(0, 40, 0)
	await _step()
	var time := Gunnery.intercept_time(enemy.global_position - player.global_position, enemy.velocity - player.velocity * 0.2, player.bolt_speed)
	_check("guidance compensates for inherited bolt motion", hud._solution_aim.is_equal_approx(enemy.global_position + (enemy.velocity - player.velocity * 0.2) * time))
	var orientation_valid := true
	for rotation: Vector3 in [Vector3.ZERO, Vector3(0, PI * 0.5, 0), Vector3(0.8, -1.1, 1.4)]:
		player.global_basis = Basis.from_euler(rotation)
		var ahead: Vector2 = hud._radar_offset(player.global_position + player.forward() * 200.0)
		var right: Vector2 = hud._radar_offset(player.global_position + player.global_basis.x * 200.0)
		orientation_valid = orientation_valid and absf(ahead.x) < 0.001 and ahead.y < -1.0 and right.x > 1.0 and absf(right.y) < 0.001
	_check("radar nose and right agree through yaw, pitch and roll", orientation_valid)
	_check("distant radar contacts remain inside the instrument", hud._radar_offset(player.global_position + player.forward() * 10000.0).length() < 92.0)
	# Damage from a later collision must clear prior hostile credit.
	enemy.take_damage(6.0, player)
	enemy.take_damage(250.0, null, enemy.global_position + Vector3.RIGHT, Vector3.ZERO, {}, "COLLISION")
	_check("collision death clears prior hostile attribution", enemy.last_damage_pilot.is_empty() and GameMatch.pilots.YOU.kills == 0 and GameMatch.scores[0] == 0 and GameMatch.pilots[enemy.display_name].deaths == 1)
	_check("kill feed reports the actual environmental cause", GameMatch.get_feed()[0].text.contains("COLLISION") and not GameMatch.get_feed()[0].text.contains("LASER"))
	_main._show_title()
	_main.queue_free()
	rock.queue_free()
	await get_tree().process_frame
	await Sfx.finish_audio()
	print("--- combat feedback: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _step() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
