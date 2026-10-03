extends Node3D
## Regression checks for steering, resources, spherical containment and gunnery.

const AI_SCENE := preload("res://scenes/ships/ai_ship.tscn")
const BOLT_SCENE := preload("res://scenes/weapons/laser_bolt.tscn")

var _main: Node3D
var _player: SpaceShip
var _checks := 0
var _failures := 0
var _preferences: Dictionary


func _ready() -> void:
	_preferences = GameSettings.values.duplicate()
	GameSettings.reset_to_defaults(false)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.start_in_menu = false
	_main.ally_count = 2
	_main.enemy_count = 3
	add_child(_main)
	_main.arena.process_mode = Node.PROCESS_MODE_DISABLED
	for entry: Dictionary in _main._roster:
		entry.ship.set_physics_process(false)
	_player = _main.player
	await get_tree().physics_frame
	_steering()
	_camera_stability()
	_resources()
	_visual_systems()
	await _collision()
	await _rock_surfaces()
	_rock_respawns()
	_containment()
	_intercepts()
	await _orphaned_bolts()
	_main._show_title()
	_main.queue_free()
	await get_tree().process_frame
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	print("--- flight systems: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _steering() -> void:
	_player.respawn_at(Vector3.ZERO, Vector3.FORWARD * 100.0)
	_mouse(Vector2(100, 50), 1.0 / 60.0)
	_check("mouse yaw and pitch use radians", is_equal_approx(_player.yaw, -0.22) and is_equal_approx(_player.pitch, -0.11))
	_player.yaw = 0.0
	_player.pitch = 0.0
	_mouse(Vector2(100, 50), 1.0 / 30.0)
	var slow := Vector2(_player.yaw, _player.pitch)
	_player.yaw = 0.0
	_player.pitch = 0.0
	_mouse(Vector2(100, 50), 1.0 / 120.0)
	_check("mouse sensitivity is independent of frame rate", slow.is_equal_approx(Vector2(_player.yaw, _player.pitch)))
	GameSettings.set_value("invert_y", true, false)
	_player.pitch = 0.0
	_mouse(Vector2(0, 50), 1.0 / 60.0)
	_check("invert pitch applies in flight", _player.pitch > 0.0)
	GameSettings.set_value("invert_y", false, false)
	for pair: Array in [[JOY_AXIS_RIGHT_X, -0.8], [JOY_AXIS_RIGHT_X, 0.8], [JOY_AXIS_RIGHT_Y, -0.8], [JOY_AXIS_RIGHT_Y, 0.8]]:
		_player.yaw = 0.0
		_player.pitch = 0.0
		var stick := InputEventJoypadMotion.new()
		stick.device = 0
		stick.axis = pair[0]
		stick.axis_value = pair[1]
		Input.parse_input_event(stick)
		Input.flush_buffered_events()
		_player._aim(0.1)
		var angle: float = _player.yaw if pair[0] == JOY_AXIS_RIGHT_X else _player.pitch
		_check("gamepad axis %d direction %+.1f steers" % pair, angle * float(pair[1]) < 0.0)
		stick = stick.duplicate()
		stick.axis_value = 0.0
		Input.parse_input_event(stick)
		Input.flush_buffered_events()
	_mouse(Vector2(100000, 100000), 1.0 / 60.0)
	_check("extreme mouse input keeps full-turn angles and a finite hull", absf(_player.yaw) <= PI and absf(_player.pitch) <= PI and _pure_rotation(_player.global_basis))
	_player.respawn_at(Vector3(80, 20, 40), Vector3.ZERO)
	var direction := _player.forward()
	_player._aim(1.0 / 60.0)
	_check("spawn orientation survives the first aim update", _player.forward().dot(direction) > 0.999)
	_player.roll = PI - 0.01
	Input.action_press("roll_right")
	_player._aim(0.1)
	Input.action_release("roll_right")
	_check("roll wraps safely through a full turn", _player.roll < 0.0 and absf(_player.roll) <= PI)
	for render_fps: int in [30, 60, 144]:
		for pitch_direction: int in [-1, 1]:
			_pitch_loops(render_fps, pitch_direction)
	_local_control_axes()


func _local_control_axes() -> void:
	var attitudes: Array[Vector3] = [Vector3.ZERO,
		Vector3(PI * 0.5, 0.7, 0.4), Vector3(-PI * 0.5, -0.4, -0.3),
		Vector3(deg_to_rad(100.0), 0.8, deg_to_rad(60.0)),
		Vector3(deg_to_rad(-170.0), -0.6, deg_to_rad(-100.0)),
		Vector3(0.0, 0.6, PI)]
	for index in attitudes.size():
		var angles := attitudes[index]
		var inverse := index % 2 == 1
		GameSettings.set_value("invert_y", inverse, false)
		GameSettings.set_value("invert_roll", inverse, false)
		for control: String in ["mouse yaw", "mouse pitch", "Q", "E"]:
			_set_control_attitude(angles)
			var before := _player.global_basis
			var expected_axis := Vector3.UP
			if control == "mouse yaw":
				_mouse(Vector2(-20, 0), 1.0 / 60.0)
			elif control == "mouse pitch":
				expected_axis = Vector3.RIGHT * (-1.0 if inverse else 1.0)
				_mouse(Vector2(0, -20), 1.0 / 60.0)
			else:
				var key := KEY_Q if control == "Q" else KEY_E
				var direction := -1.0 if control == "Q" else 1.0
				expected_axis = Vector3.BACK * direction * (-1.0 if inverse else 1.0)
				_physical_key(key, true)
				_player._aim(1.0 / 60.0)
				_physical_key(key, false)
			var relative := (before.inverse() * _player.global_basis).get_rotation_quaternion()
			var rotation_vector := Vector3(relative.x, relative.y, relative.z)
			_check("%s follows the hull axis at attitude %d / inversion %s" % [control, index, inverse], rotation_vector.length() > 0.002 and rotation_vector.normalized().dot(expected_axis) > 0.999 and _pure_rotation(_player.global_basis))
		_set_control_attitude(angles)
		var before := _player.global_basis
		_physical_key(KEY_E, true)
		_mouse(Vector2(-12, -10), 1.0 / 60.0)
		_physical_key(KEY_E, false)
		var relative := (before.inverse() * _player.global_basis).get_rotation_quaternion()
		var sign := -1.0 if inverse else 1.0
		_check("combined mouse and physical E keep their local directions at attitude %d" % index, relative.x * sign > 0.002 and relative.y > 0.002 and relative.z * sign > 0.002 and _pure_rotation(_player.global_basis))
	GameSettings.set_value("invert_y", false, false)
	GameSettings.set_value("invert_roll", false, false)


func _set_control_attitude(angles: Vector3) -> void:
	_player.respawn_at(Vector3.ZERO, Vector3.FORWARD * 100.0)
	_player.pitch = angles.x
	_player.yaw = angles.y
	_player.roll = angles.z
	_player.global_basis = Basis.from_euler(angles)
	_player.capture_mouse(true)


func _physical_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _pitch_loops(render_fps: int, direction: int) -> void:
	_player.respawn_at(Vector3.ZERO, Vector3.FORWARD * 100.0)
	_player.capture_mouse(true)
	var physics_delta := 1.0 / 60.0
	var render_delta := 1.0 / render_fps
	var angular_speed := deg_to_rad(120.0) * direction
	var render_clock := 0.0
	var command_turn := 0.0
	var hull_turn := 0.0
	var previous_pitch: float = _player.pitch
	var previous_basis := _player.global_basis
	var wraps := 0
	var ticks := 0
	var maximum_step := 0.0
	var maximum_lag := 0.0
	var forward_only := true
	var rigid := true
	# Ten seconds of real mouse deltas at independent render rates: the ship
	# consumes accumulated events at sixty physics ticks, just as in flight.
	for frame in render_fps * 10:
		_queue_mouse(Vector2(0.0, -angular_speed * render_delta / _player.look_speed))
		render_clock += render_delta
		while render_clock + 0.0000001 >= physics_delta:
			_player._aim(physics_delta)
			render_clock -= physics_delta
			ticks += 1
			var pitch_now: float = _player.pitch
			if absf(pitch_now - previous_pitch) > PI:
				wraps += 1
			command_turn += wrapf(pitch_now - previous_pitch, -PI, PI)
			var basis_now := _player.global_basis
			var relative := previous_basis.inverse() * basis_now
			var step := atan2(relative.y.z, relative.y.y)
			hull_turn += step
			maximum_step = maxf(maximum_step, absf(step))
			maximum_lag = maxf(maximum_lag, absf(command_turn - hull_turn))
			forward_only = forward_only and step * direction >= -0.00001
			rigid = rigid and _pure_rotation(basis_now) and basis_now.x.dot(Vector3.RIGHT) > 0.9999
			previous_pitch = pitch_now
			previous_basis = basis_now
	var label := "%d render FPS / 60 physics TPS / pitch %s" % [render_fps, "up" if direction > 0 else "down"]
	_check(label + " passes both poles and three complete turns", ticks == 600 and wraps >= 3 and absf(command_turn - angular_speed * 10.0) < 0.0005)
	_check(label + " hull keeps turning without reversal or snap", forward_only and maximum_step < deg_to_rad(7.0) and maximum_lag < deg_to_rad(8.0))
	_check(label + " keeps a finite rigid orientation", rigid)


func _pure_rotation(value: Basis) -> bool:
	return value.is_finite() and absf(value.determinant() - 1.0) < 0.00001 and absf(value.x.dot(value.y)) < 0.00001 and absf(value.y.dot(value.z)) < 0.00001 and absf(value.z.dot(value.x)) < 0.00001


func _camera_stability() -> void:
	var rig: CameraRig = _main.rig
	_player.respawn_at(Vector3(0, 450, 0), Vector3(0, 450, -100))
	rig.snap_to_target()
	_player.recoil = 0.8
	rig.add_shake(0.5)
	for _i in 16000:
		rig._process(1.0 / 1500.0)
	var basis := rig.global_basis
	_check("camera remains a pure rotation at uncapped frame rates", basis.is_finite() and absf(basis.determinant() - 1.0) < 0.00001 and absf(basis.x.dot(basis.y)) < 0.00001)
	_player.recoil = 0.0
	for _i in 240:
		rig._process(1.0 / 120.0)
	_check("camera settles on the nose after sustained recoil", (-rig.global_basis.z).dot(_player.forward()) > 0.999)


func _visual_systems() -> void:
	_player.reset_for_spawn()
	var visual: ShipVisual = _player.model
	visual.set_livery(GameConfig.team_color(GameConfig.TEAM_BLUE))
	var blue_drive := (visual.get_node("EngineGlowLeft") as MeshInstance3D).material_override as StandardMaterial3D
	var blue_tint := blue_drive.emission
	visual.set_livery(GameConfig.team_color(GameConfig.TEAM_RED))
	var red_drive := (visual.get_node("EngineGlowLeft") as MeshInstance3D).material_override as StandardMaterial3D
	_check("changing squadron paint leaves drive plasma unchanged", blue_tint.is_equal_approx(red_drive.emission))
	visual.set_livery(GameConfig.team_color(_player.team))
	_player.cmd_right = 1.0
	_player.cmd_up = 1.0
	_player.throttle = -1.0
	_player._update_visuals(0.2)
	var exhaust_opposes_force := true
	var active_ports := 0
	for port: Node in visual.get_children():
		if not String(port.name).begins_with("RCSJet") or not (port as MeshInstance3D).visible:
			continue
		active_ports += 1
		exhaust_opposes_force = exhaust_opposes_force and (port as Node3D).basis.y.dot(Vector3(1, 1, 1)) < -0.9
	_check("visible maneuver exhaust opposes the commanded force", active_ports == 8 and exhaust_opposes_force)
	_check("reverse thrust does not light the forward drive", not (visual.get_node("BurnerLeft") as MeshInstance3D).visible)
	_player.reset_for_spawn()
	_player.boosting = true
	_player._update_visuals(0.2)
	_check("arming the booster at zero throttle produces no forward exhaust", not (visual.get_node("BurnerLeft") as MeshInstance3D).visible)
	_player.reset_for_spawn()
	_check("hull keeps its metal surface after a damage override clears", _player.hull_mesh.mesh.surface_get_material(0) is ShaderMaterial)


func _resources() -> void:
	_player.reset_for_spawn()
	_player.take_damage(_player.shield + 20.0, null, _player.global_position + Vector3.RIGHT * 3.0)
	_player.boosting = true
	_player._update_visuals(0.1)
	_player.reset_for_spawn()
	_check("redeployment clears prior hull flash, shield impact and exhaust", _player.hull_mesh.material_override == null and not _player.model.get_node("ShieldImpact").visible and not _player.model.get_node("BurnerLeft").visible)
	_player.take_damage(20)
	var shield := _player.shield
	_player._update_resources(1.0)
	_player._update_resources(1.0)
	_check("partial shields wait before regenerating", _player.shield == shield)
	_player.take_damage(10)
	shield = _player.shield
	_player._update_resources(2.0)
	_check("another hit resets regeneration delay", _player.shield == shield)
	_player._update_resources(1.3)
	_player._update_resources(0.1)
	_check("shields regenerate after a clear window", _player.shield > shield)
	_player.reset_for_spawn()
	_player.global_basis = Basis.IDENTITY
	_player.velocity = Vector3.ZERO
	_player.cmd_forward = 1.0
	for _i in 120:
		_player._integrate_velocity(1.0 / 60.0)
	var cruise := _player.velocity.length()
	_player.velocity = Vector3.ZERO
	_player.wants_boost = true
	for _i in 120:
		_player._integrate_velocity(1.0 / 60.0)
	_check("afterburner adds substantial acceleration", _player.velocity.length() > cruise * 1.6 and _player.boost < _player.boost_max)
	_player.boost = 1.0
	_player.boosting = false
	_player.wants_boost = true
	_player._integrate_velocity(1.0 / 60.0)
	_check("empty booster cannot stutter on tiny energy", not _player.boosting)
	_player.boost = GameConfig.BOOST_MIN_TO_ENGAGE
	_player._integrate_velocity(1.0 / 60.0)
	_check("booster re-engages after sufficient recharge", _player.boosting)


func _rock_surfaces() -> void:
	var scene := load("res://scenes/world/asteroid.tscn") as PackedScene
	var small := scene.instantiate() as Asteroid
	small.radius = 3.0
	small.rock_seed = 712
	small.position = Vector3(0, 650, 0)
	add_child(small)
	small.freeze = true
	var large := scene.instantiate() as Asteroid
	large.radius = 13.0
	large.rock_seed = 182
	large.position = Vector3(50, 650, 0)
	add_child(large)
	large.freeze = true
	await get_tree().physics_frame
	var independent: bool = small.get_node("RockShape").shape != large.get_node("RockShape").shape
	_check("different rock sizes own independent collision hulls", independent)
	for rock: Asteroid in [small, large]:
		var mesh := rock.get_node("RockMesh").mesh as Mesh
		var vertices := mesh.get_faces()
		var support := vertices[0]
		for vertex: Vector3 in vertices:
			if vertex.x > support.x:
				support = vertex
		var point := rock.to_global(support)
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.RIGHT * 5.0, point - Vector3.RIGHT * 5.0, GameConfig.LAYER_ROCK)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		_check("bolt contact meets visible rock silhouette at radius %.0f" % rock.radius, not hit.is_empty() and hit.collider == rock and (hit.position as Vector3).distance_to(point) < rock.radius * 0.03)
	small.queue_free()
	large.queue_free()
	await get_tree().physics_frame


func _collision() -> void:
	var obstacle := StaticBody3D.new()
	obstacle.collision_layer = GameConfig.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 8.0
	shape.shape = sphere
	obstacle.add_child(shape)
	add_child(obstacle)
	obstacle.global_position = Vector3(0, 0, -18)
	_player.respawn_at(Vector3.ZERO, Vector3.FORWARD * 100)
	_player.velocity = Vector3.FORWARD * 40.0
	await get_tree().physics_frame
	var hp := _player.hull + _player.shield
	for _i in 24:
		_player._physics_process(1.0 / 60.0)
		await get_tree().physics_frame
	_check("physical impact damages shields using incoming speed", _player.hull + _player.shield < hp - 10.0)
	obstacle.queue_free()
	_player.reset_for_spawn()
	await get_tree().physics_frame


func _rock_respawns() -> void:
	var rock: Asteroid = _main.arena.asteroids[0]
	var anchor: StarBody = _main.arena.bodies[0]
	var other: Asteroid = _main.arena.asteroids[1]
	_check("rock respawn rejects live solids and pilots", not rock._spawn_is_clear(anchor.global_position) and not rock._spawn_is_clear(other.global_position) and not rock._spawn_is_clear(_player.global_position))
	_check("rock respawn keeps its full silhouette inside the arena", not rock._spawn_is_clear(Vector3(GameConfig.ARENA_RADIUS - rock.radius, 0, 0)))
	rock._revive()
	_check("revived rock occupies a validated clear site", not rock.dead and rock.visible and rock._spawn_is_clear(rock.global_position))
	# An anchor covering the arena exercises the failed-search path. Restore
	# its tuning immediately; no mesh or permanent game balance is changed.
	var original_radius := anchor.radius
	anchor.radius = GameConfig.ARENA_RADIUS * 4.0
	rock._revive()
	_check("a crowded field delays revival without enabling collision", rock.dead and not rock.visible and rock.freeze and rock.collision_layer == 0 and rock.collision_mask == 0 and rock._respawn_timer > 0.0)
	anchor.radius = original_radius
	rock._revive()
	_check("a delayed rock returns once a clear site becomes available", not rock.dead and rock.visible and rock.collision_layer == GameConfig.LAYER_ROCK)
	rock.freeze = true


func _containment() -> void:
	for position: Vector3 in [Vector3(0, 950, 0), Vector3(920, 350, -100), Vector3(-950, -950, 0)]:
		_player.global_position = position
		_player.velocity = position.normalized() * 200.0
		_player._contain_in_arena(1.0 / 60.0)
		_check("boundary contains a ship at %s" % str(position), _player.global_position.length() <= GameConfig.ARENA_RADIUS + 0.01 and _player.global_position.normalized().dot(position.normalized()) > 0.999)
	_player.respawn_at(Vector3.ZERO, Vector3.FORWARD * 100)


func _intercepts() -> void:
	for relative_velocity: Vector3 in [Vector3.ZERO, Vector3(100, 0, 0), Vector3(0, 0, 100), Vector3(60, 35, -200)]:
		var offset := Vector3(0, 0, -200)
		var time := Gunnery.intercept_time(offset, relative_velocity, 320.0)
		_check("lead solution intersects target at %s" % str(relative_velocity), is_finite(time) and absf((offset + relative_velocity * time).length() - time * 320.0) < 0.001)
	_check("unreachable target has no false lead", not is_finite(Gunnery.intercept_time(Vector3(0, 0, -200), Vector3(0, 0, -400), 320.0)))
	var target_velocity := Vector3(100, 30, 0)
	var inherited_velocity := Vector3(40, 0, 0)
	var offset := Vector3(0, 0, -220)
	var time := Gunnery.intercept_time(offset, target_velocity - inherited_velocity, 320.0)
	var direction := (offset + (target_velocity - inherited_velocity) * time).normalized()
	_check("lead includes shooter momentum", ((direction * 320.0 + inherited_velocity) * time).distance_to(offset + target_velocity * time) < 0.001)


func _orphaned_bolts() -> void:
	var shooter: SpaceShip = AI_SCENE.instantiate()
	shooter.display_name = "GHOST"
	shooter.team = GameConfig.TEAM_BLUE
	_main.ships_root.add_child(shooter)
	shooter.set_physics_process(false)
	GameMatch.register_pilot(shooter.display_name, shooter.team)
	var hostile: SpaceShip
	for entry: Dictionary in _main._roster:
		if entry.team == GameConfig.TEAM_RED:
			hostile = entry.ship
			break
	var enemy_bolt: LaserBolt = BOLT_SCENE.instantiate()
	var friendly_bolt: LaserBolt = BOLT_SCENE.instantiate()
	for bolt in [enemy_bolt, friendly_bolt]:
		_main.effects_root.add_child(bolt)
		bolt.launch(Vector3.ZERO, Vector3.FORWARD * 320, shooter, 200, 1.7, Color.WHITE)
		bolt.set_physics_process(false)
	shooter.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	friendly_bolt._impact(_player.global_position, Vector3.UP, _player)
	_check("freed shooter's bolts still reject friendly fire", _player.hull == _player.hull_max and _player.shield == _player.shield_max)
	enemy_bolt._impact(hostile.global_position, Vector3.UP, hostile)
	_check("freed shooter's bolt can finish a hostile", hostile.dead)
	_check("projectile kill credit survives ship destruction", GameMatch.pilots.GHOST.kills == 1 and GameMatch.pilots.GHOST.damage == 200.0 and GameMatch.scores[0] == 1)


func _mouse(relative: Vector2, delta: float) -> void:
	_queue_mouse(relative)
	_player._aim(delta)


func _queue_mouse(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	_player._unhandled_input(event)


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
