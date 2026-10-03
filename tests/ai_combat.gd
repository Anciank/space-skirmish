extends Node3D
## Deterministic combat decisions, real projectile paths and safe flight.
## godot --headless --fixed-fps 60 res://tests/ai_combat.tscn

const AI_SCENE := preload("res://scenes/ships/ai_ship.tscn")
const TARGET_SCENE := preload("res://tests/dummy_target.tscn")
const BOLT_SCENE := preload("res://scenes/weapons/laser_bolt.tscn")
const ROCK_SCENE := preload("res://scenes/world/asteroid.tscn")

var _ai: AIShip
var _first: SpaceShip
var _second: SpaceShip
var _ally: SpaceShip
var _rock: Asteroid
var _effects: Node3D
var _checks := 0
var _failures := 0
var _shots := 0


func _ready() -> void:
	var ships := Node3D.new()
	ships.name = "Ships"
	add_child(ships)
	_effects = Node3D.new()
	_effects.name = "Effects"
	add_child(_effects)
	_ai = AI_SCENE.instantiate()
	_ai.team = GameConfig.TEAM_BLUE
	ships.add_child(_ai)
	_ai.set_physics_process(false)
	_ai.weapon_fired.connect(func(): _shots += 1)
	_first = _make_target(ships, "CR-FIRST", GameConfig.TEAM_RED)
	_second = _make_target(ships, "CR-SECOND", GameConfig.TEAM_RED)
	_ally = _make_target(ships, "AZ-FRIEND", GameConfig.TEAM_BLUE)
	_rock = ROCK_SCENE.instantiate()
	_rock.radius = 12.0
	_rock.rock_seed = 7341
	_rock.respawnable = false
	add_child(_rock)
	_rock.freeze = true
	_rock.linear_velocity = Vector3.ZERO
	await _reset()
	await _target_choices()
	await _velocity_matching()
	await _incoming_fire()
	await _safe_fire()
	await _thrust_control()
	await _safe_flight()
	await _retreat_recovery()
	await _spawn_reset()
	await _freed_target()
	for child: Node in get_children():
		child.queue_free()
	await get_tree().process_frame
	await Sfx.finish_audio()
	print("--- AI combat: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _make_target(parent: Node, label: String, team: int) -> SpaceShip:
	var ship: SpaceShip = TARGET_SCENE.instantiate()
	ship.display_name = label
	ship.team = team
	parent.add_child(ship)
	ship.set_physics_process(false)
	return ship


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _sync() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _reset() -> void:
	_ai.set_physics_process(false)
	for child: Node in _effects.get_children():
		child.queue_free()
	for i in 3:
		var ship: SpaceShip = [_first, _second, _ally][i]
		ship.respawn_at(Vector3(3000.0 + i * 50.0, 0, 0), Vector3(3000.0 + i * 50.0, 0, -1))
		ship.set_physics_process(false)
		ship.hull = 10000.0
	_rock.global_position = Vector3(1500, 0, 0)
	_ai.respawn_at(Vector3.ZERO, Vector3.FORWARD * 160.0)
	_ai.skill = 1.0
	_ai._rng.seed = 20261003
	_ai.weapon_spread_deg = 0.0
	await _sync()


func _target_choices() -> void:
	_first.global_position = Vector3(0, 0, -480)
	_second.global_position = Vector3(0, 0, -140)
	_ai.target = _first
	_ai._target_scan_timer = 0.0
	_ai._acquire_target()
	_check("pilot reassesses a distant lock when a much closer hostile appears", _ai.target == _second)
	_first.global_position = Vector3(0, 0, -195)
	_second.global_position = Vector3(0, 0, -200)
	_ai.target = _second
	for _i in 20:
		_ai._target_scan_timer = 0.0
		_ai._acquire_target()
	_check("small range differences do not make the lock oscillate", _ai.target == _second)
	_first.global_position = Vector3(0, 0, -190)
	_first.global_basis = Basis.IDENTITY
	_second.global_position = Vector3(90, 0, -205)
	_second.look_at(_ai.global_position)
	_ai.target = _first
	_ai.take_damage(6.0, _second, Vector3.RIGHT)
	_ai._target_scan_timer = 0.0
	_ai._acquire_target()
	_check("a nearby hostile attacking the pilot can replace a passive lock", _ai.target == _second)


func _velocity_matching() -> void:
	await _reset()
	_first.global_position = Vector3(0, 0, -160)
	_ai.target = _first
	_ai.state = AIShip.State.ENGAGE
	_ai._plan_combat(160.0)
	var stationary := _ai._desired_dir * _ai._desired_speed
	_first.velocity = Vector3.RIGHT * 60.0
	_ai._plan_combat(160.0)
	var moving := _ai._desired_dir * _ai._desired_speed
	_check("movement plan carries the crossing target's velocity", (moving - stationary).dot(Vector3.RIGHT) > 30.0,
		"(added %.1f m/s along target motion)" % (moving - stationary).dot(Vector3.RIGHT))
	_ai._burst_gap = 100.0
	_ai.set_physics_process(true)
	var max_range := 0.0
	for _i in 360:
		await get_tree().physics_frame
		_first.global_position += Vector3.RIGHT
		_first.velocity = Vector3.RIGHT * 60.0
		max_range = maxf(max_range, _ai.global_position.distance_to(_first.global_position))
	_ai.set_physics_process(false)
	_check("real flight catches a 60 m/s crossing contact without losing its fighting range",
		_ai.velocity.x > 35.0 and max_range < 320.0,
		"(pilot %.1f m/s across, widest range %.1f m)" % [_ai.velocity.x, max_range])


func _bolt(position: Vector3, velocity: Vector3, shooter: SpaceShip, life := 1.7) -> LaserBolt:
	var bolt: LaserBolt = BOLT_SCENE.instantiate()
	_effects.add_child(bolt)
	bolt.launch(position, velocity, shooter, 6.0, life, Color.WHITE)
	bolt.set_physics_process(false)
	return bolt


func _incoming_fire() -> void:
	await _reset()
	_first.global_position = Vector3(0, 0, -160)
	_ai.target = _first
	_ai.state = AIShip.State.ENGAGE
	var incoming := _bolt(Vector3(0, 0, -70), Vector3.BACK * 320.0, _first)
	_check("hostile bolt on an imminent collision course is detected", _ai._incoming_threat().length_squared() > 1.0)
	_ai._think()
	_check("incoming fire produces a deliberate sideways dodge", _ai.state == AIShip.State.EVADE
		and absf(_ai._desired_dir.dot(Vector3.BACK)) < 0.5 and _ai._desired_speed > 0.0)
	_ai._evade_timer = 0.05
	for _i in 10:
		_ai._think()
	_check("a sustained threat does not keep extending the same dodge", _ai._evade_timer <= 0.05)
	_ai._evade_timer = 0.0
	_ai._think()
	_ai._think()
	_check("dodge cooldown gives the pilot time to rejoin the fight", _ai.state == AIShip.State.ENGAGE
		and _ai._evade_cooldown > 0.0)
	incoming.queue_free()
	await _sync()
	var harmless := _bolt(Vector3(30, 0, -70), Vector3.BACK * 320.0, _first)
	_check("a hostile shot passing well clear does not trigger a dodge", _ai._incoming_threat() == Vector3.ZERO)
	harmless.global_position = Vector3(0, 0, -70)
	harmless.velocity = Vector3.FORWARD * 320.0
	_check("a receding shot does not trigger a dodge", _ai._incoming_threat() == Vector3.ZERO)
	harmless.velocity = Vector3.BACK * 320.0
	harmless.attacker = _ally
	_check("friendly projectiles are ignored by the threat response", _ai._incoming_threat() == Vector3.ZERO)
	harmless.attacker = null
	harmless._credit = {"name": "AZ-FRIEND", "team": GameConfig.TEAM_BLUE}
	_check("friendly shot credit still prevents evasion after its shooter is gone", _ai._incoming_threat() == Vector3.ZERO)
	harmless.attacker = _first
	harmless._credit = {"name": "CR-FIRST", "team": GameConfig.TEAM_RED}
	harmless.velocity = Vector3.ZERO
	_check("a stationary projectile cannot be an approaching shot", _ai._incoming_threat() == Vector3.ZERO)
	harmless.velocity = Vector3.BACK * 320.0
	harmless.lifetime = 0.05
	_check("a bolt that expires before arrival is not a collision threat", _ai._incoming_threat() == Vector3.ZERO)
	await _reset()
	_first.global_position = Vector3(0, 0, -160)
	_ai.target = _first
	_ai.state = AIShip.State.ENGAGE
	var stayed_engaged := true
	for _i in 100:
		_ai._think()
		stayed_engaged = stayed_engaged and _ai.state == AIShip.State.ENGAGE
	_check("clear combat decisions do not invent random evasions", stayed_engaged)


func _ready_burst() -> void:
	_ai.look_at(_ai._predicted_aim_point())
	_ai._burst_len = 0.8
	_ai._burst_timer = 0.0
	_ai._fire_timer = 0.0


func _fire_count() -> int:
	_ready_burst()
	var before := _shots
	_ai._apply_weapons(1.0 / 60.0)
	return _shots - before


func _safe_fire() -> void:
	await _reset()
	_first.global_position = Vector3(0, 0, -180)
	# Keep the lead corridor separate from the current-centre ray as muzzle
	# velocity changes; otherwise this large rock blocks both fixture paths.
	_first.velocity = Vector3.RIGHT * _ai.bolt_speed * 0.25
	_ai.target = _first
	_ai.state = AIShip.State.ENGAGE
	var muzzle := _ai.muzzle_points[0].global_position
	var prediction := _ai._predicted_aim_point()
	var middle := muzzle.lerp(prediction, 0.5)
	_rock.global_position = middle
	await _sync()
	var query := PhysicsRayQueryParameters3D.create(muzzle, _first.global_position, GameConfig.WEAPON_MASK)
	query.exclude = [_ai.get_rid(), _first.get_rid()]
	_check("lead-path obstacle fixture leaves the current target-center ray clear",
		get_world_3d().direct_space_state.intersect_ray(query).is_empty())
	_check("a rock on the predicted shot path suppresses the burst", _fire_count() == 0)
	_rock.global_position = Vector3(1500, 0, 0)
	_ally.global_position = middle
	await _sync()
	_check("a friendly hull on the predicted shot path suppresses the burst", _fire_count() == 0)
	var flight := Gunnery.intercept_time(_first.global_position - muzzle, _first.velocity, _ai.bolt_speed)
	_ally.global_position = middle + Vector3.RIGHT * 40.0
	_ally.velocity = Vector3.LEFT * (40.0 / (flight * 0.5))
	await _sync()
	_check("a friendly crossing the future shot corridor suppresses the burst", _fire_count() == 0)
	_ally.global_position = Vector3(1500, 0, 0)
	_ally.velocity = Vector3.ZERO
	await _sync()
	_check("a clear crossing-target solution opens the burst", _fire_count() > 0)
	_ready_burst()
	_ai._fire_timer = 0.1
	var remaining := _ai._burst_len
	var before := _shots
	_ai._apply_weapons(1.0 / 60.0)
	_check("gun cooldown does not consume shots from an unfired burst", _shots == before and is_equal_approx(_ai._burst_len, remaining))
	await _reset()
	_first.global_position = Vector3(0, 0, -180)
	_ai.target = _first
	_ai.state = AIShip.State.ENGAGE
	_ally.global_position = _ai.muzzle_points[1].global_position + Vector3.FORWARD * 15.0
	await _sync()
	_ai._muzzle_index = 1
	_check("the blocked active barrel cannot fire through a nearby friendly", _fire_count() == 0)
	_ai._muzzle_index = 0
	_check("the other barrel can fire when its own corridor is clear", _fire_count() > 0)


func _thrust_control() -> void:
	await _reset()
	_ai.velocity = Vector3.FORWARD * 80.0
	_ai._desired_dir = Vector3.ZERO
	_ai._desired_speed = 0.0
	_ai._apply_translation(0.1)
	_check("zero requested velocity still applies opposing thrust to a drifting ship", _ai.cmd_forward < -0.1,
		"(forward command %.2f)" % _ai.cmd_forward)
	await _reset()
	_first.global_position = Vector3.FORWARD * 40.0
	_ai.target = _first
	_ai.state = AIShip.State.ENGAGE
	_ai._plan_combat(40.0)
	_ai._apply_translation(0.1)
	_check("close breakaway saves afterburner while the main drive faces the wrong way",
		not _ai.wants_boost and _ai._travel_priority and _ai._desired_dir.dot(Vector3.BACK) > 0.95)
	_ai._plan_combat(40.0)
	_ai._apply_steering(2.0)
	# The reverse-thrust command must pass through zero at its normal slew rate.
	_ai._apply_translation(0.2)
	_check("close breakaway can use afterburner once the ship turns into its escape",
		_ai.wants_boost and _ai.forward().dot(_ai._desired_dir) > 0.95 and _ai.cmd_forward > 0.0)


func _safe_flight() -> void:
	await _reset()
	_first.global_position = Vector3(0, 0, -350)
	_ai.target = _first
	_ai.state = AIShip.State.ENGAGE
	_ai.velocity = Vector3.FORWARD * 65.0
	_rock.global_position = Vector3(0, 0, -80)
	await _sync()
	_ai._think()
	var planned := _ai._desired_dir * _ai._desired_speed
	_check("an obstacle in the braking horizon changes the approach course",
		planned.length() < 35.0 or planned.slide(Vector3.FORWARD).length() > 15.0,
		"(planned velocity %s)" % str(planned))
	_ai._burst_gap = 100.0
	_ai.set_physics_process(true)
	var closest := INF
	for _i in 360:
		await get_tree().physics_frame
		closest = minf(closest, _ai.global_position.distance_to(_rock.global_position))
	_ai.set_physics_process(false)
	_check("real approach stays clear of the rock without collision damage",
		closest > _rock.radius + _ai.collision_radius and _ai.hull == _ai.hull_max
		and _ai.shield == _ai.shield_max,
		"(closest %.1f m, hull %.0f, shield %.0f)" % [closest, _ai.hull, _ai.shield])
	_check("obstacle avoidance still makes progress toward the contact", _ai.global_position.z < -95.0,
		"(forward progress %.1f m)" % -_ai.global_position.z)
	await _reset()
	_rock.radius = 20.0
	_rock._build_visual()
	_rock._ensure_shape()
	_rock.global_position = Vector3(0, 0, -90)
	_ai.velocity = Vector3.FORWARD * 100.0
	_ai._desired_dir = Vector3.RIGHT
	_ai._desired_speed = 95.0
	_ai._orbit_dir = -1.0
	_ai.wants_boost = true
	await _sync()
	_ai._avoid_hazards()
	_check("obstacle detection follows actual momentum while the requested course turns sideways",
		not _ai.wants_boost and _ai._desired_speed < 90.0,
		"(corrected speed %.1f m/s, boost %s)" % [_ai._desired_speed, str(_ai.wants_boost)])
	await _reset()
	_ai.global_position = Vector3(GameConfig.ARENA_RADIUS - 100.0, 0, 0)
	_ai.velocity = Vector3.RIGHT * 75.0
	_ai._desired_dir = Vector3.RIGHT
	_ai._desired_speed = 75.0
	_ai.wants_boost = true
	_ai._avoid_hazards()
	var corrected := _ai._desired_dir * _ai._desired_speed
	_check("boundary planning removes outward motion before the wall", corrected.x < 0.0,
		"(outward planned speed %.1f m/s)" % corrected.x)
	_check("boundary recovery cancels outward afterburner", not _ai.wants_boost)
	_ai.set_physics_process(true)
	var furthest := _ai.global_position.length()
	var inward_speed := 0.0
	for _i in 180:
		await get_tree().physics_frame
		furthest = maxf(furthest, _ai.global_position.length())
		inward_speed = minf(inward_speed, _ai.velocity.dot(_ai.global_position.normalized()))
	_ai.set_physics_process(false)
	_check("real boundary recovery brakes before contacting the hard wall",
		furthest < GameConfig.ARENA_RADIUS - 5.0 and inward_speed < -5.0,
		"(furthest %.1f m, inward recovery %.1f m/s)" % [furthest, inward_speed])


func _retreat_recovery() -> void:
	await _reset()
	_first.global_position = Vector3(0, 0, -160)
	_ai.target = _first
	_ai.hull = _ai.hull_max * 0.2
	_ai.shield = 0.0
	_ai._think()
	_check("critical hull still causes a retreat", _ai.state == AIShip.State.RETREAT and _ai.wants_boost)
	_ai._retreat_timer = 0.0
	_ai._think()
	_check("a timed retreat returns the pilot to combat", _ai.state == AIShip.State.ENGAGE)
	_ai._think()
	_check("persistent hull damage does not immediately restart the same retreat",
		_ai.state == AIShip.State.ENGAGE and _ai._retreat_cooldown > 0.0)
	_ai._retreat_cooldown = 0.0
	_ai._think()
	_first.global_position = Vector3.FORWARD * (GameConfig.AI_MAX_RANGE + 120.0)
	_ai._think()
	_check("losing the retreat contact returns to patrol with a re-entry cooldown",
		_ai.state == AIShip.State.PATROL and _ai.target == null
		and _ai._retreat_cooldown > 0.0 and _ai._retreat_timer == 0.0)
	_first.global_position = Vector3.FORWARD * 160.0
	_ai._think()
	_check("reacquiring a contact during retreat cooldown resumes combat",
		_ai.target == _first and _ai.state == AIShip.State.ENGAGE)


func _spawn_reset() -> void:
	_ai.target = _first
	_ai.state = AIShip.State.RETREAT
	_ai._evade_vector = Vector3.ONE
	_ai._evade_timer = 2.0
	_ai._evade_cooldown = 2.0
	_ai._retreat_timer = 3.0
	_ai._retreat_cooldown = 4.0
	_ai._target_scan_timer = 0.4
	_ai._has_waypoint = true
	_ai._aim_noise = Vector3.ONE
	_ai._aim_noise_goal = Vector3.ONE
	_ai._recent_attacker = _first
	_ai._attacker_memory = 5.0
	_ai._damage_pressure = 1.0
	_ai._travel_priority = true
	_ai._burst_timer = 1.0
	_ai._burst_len = 0.8
	_ai._burst_gap = 1.0
	_ai._burst_hold_timer = 1.0
	_ai.respawn_at(Vector3.ZERO, Vector3.FORWARD * 100.0)
	_check("respawn discards the old target and retreat state", _ai.target == null and _ai.state == AIShip.State.PATROL)
	_check("respawn clears stale evasion and retreat cooldowns", _ai._evade_timer == 0.0
		and _ai._evade_cooldown == 0.0 and _ai._retreat_timer == 0.0 and _ai._retreat_cooldown == 0.0)
	_check("respawn clears patrol, aim and burst leftovers", not _ai._has_waypoint and _ai._aim_noise == Vector3.ZERO
		and _ai._aim_noise_goal == Vector3.ZERO and _ai._burst_timer == 0.0 and _ai._burst_len == 0.0
		and _ai._burst_gap == 0.0 and _ai._burst_hold_timer == 0.0 and _ai._target_scan_timer == 0.0)
	_check("respawn clears attacker pressure and forced navigation", _ai._recent_attacker == null
		and _ai._attacker_memory == 0.0 and _ai._damage_pressure == 0.0 and not _ai._travel_priority)


func _freed_target() -> void:
	await _reset()
	_first.global_position = Vector3.FORWARD * 160.0
	var doomed := _make_target(_first.get_parent(), "CR-OLD", GameConfig.TEAM_RED)
	doomed.global_position = Vector3.FORWARD * 180.0
	_ai.target = doomed
	_ai.state = AIShip.State.ENGAGE
	_ai._recent_attacker = doomed
	_ai._attacker_memory = 1.0
	_ai._burst_len = 0.8
	_ai._burst_timer = 0.0
	doomed.queue_free()
	await _sync()
	var before := _shots
	_ai._apply_weapons(1.0 / 60.0)
	_check("a freed target cannot produce a stale shot", _shots == before and _ai._burst_len == 0.0)
	_ai._think()
	_check("a freed lock is safely replaced by a live hostile", _ai.target == _first)
