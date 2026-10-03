extends Node3D
## Real player rounds against a crossing hull, plus acquisition and fire safety.
## The controller tracks the hull center; it never calculates its own lead.

const PLAYER_SCENE := preload("res://scenes/ships/player_ship.tscn")
const TARGET_SCENE := preload("res://tests/dummy_target.tscn")
const RIG_SCENE := preload("res://scenes/ui/camera_rig.tscn")

var _player
var _target: SpaceShip
var _friend: SpaceShip
var _rig: CameraRig
var _rock: StaticBody3D
var _effects: Node3D
var _preferences: Dictionary
var _checks := 0
var _failures := 0
var _shot_times: Array[float] = []
var _clock := 0.0
var _damage := 0.0
var _moving := false
var _sim_frame := 0
var _sim_total := 0
var _sim_fire_frames := 180


func _ready() -> void:
	_preferences = GameSettings.values.duplicate()
	GameSettings.reset_to_defaults(false)
	GameSettings.set_value("camera_shake", false, false)
	_fixture()
	await _reset()
	await _acquisition()
	await _obstructions()
	await _ballistics()
	for rate: int in [30, 60, 120]:
		await _cadence(rate)
	var assisted := await _crossing_target(true)
	var unaided := await _crossing_target(false)
	_check("tracking a 95 m/s crossing hull lands most assisted rounds", assisted >= 0.65,
		"assisted hit rate %.1f%%" % (assisted * 100.0))
	_check("bounded lead assistance improves real hits over center-only fire", assisted > unaided + 0.5,
		"assisted %.1f%%, unaided %.1f%%" % [assisted * 100.0, unaided * 100.0])
	Input.action_release("fire")
	_cleanup_effects()
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	print("--- player gunnery: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _fixture() -> void:
	var ships := Node3D.new()
	ships.name = "Ships"
	add_child(ships)
	_effects = Node3D.new()
	_effects.name = "Effects"
	add_child(_effects)
	_player = PLAYER_SCENE.instantiate()
	ships.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player.weapon_fired.connect(func(): _shot_times.append(_clock))
	_target = TARGET_SCENE.instantiate() as SpaceShip
	_target.hull_max = 1000.0
	_target.shield_max = 1000.0
	_target.shield_regen_rate = 0.0
	ships.add_child(_target)
	_target.set_physics_process(false)
	_target.took_damage.connect(func(amount: float, _where: Vector3, _source: Node): _damage += amount)
	_friend = TARGET_SCENE.instantiate() as SpaceShip
	_friend.team = GameConfig.TEAM_BLUE
	ships.add_child(_friend)
	_friend.set_physics_process(false)
	_rig = RIG_SCENE.instantiate() as CameraRig
	add_child(_rig)
	_rig.set_process(false)
	_rig.target = _player
	_player.aim_camera = _rig.camera
	_player.aim_source = _rig
	_rock = StaticBody3D.new()
	_rock.collision_layer = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 16.0
	shape.shape = box
	_rock.add_child(shape)
	add_child(_rock)


func _reset() -> void:
	Input.action_release("fire")
	_cleanup_effects()
	_player.respawn_at(Vector3(0, 500, 0), Vector3(0, 500, -200))
	_player.weapon_spread_deg = GameConfig.WEAPON_SPREAD
	_player._rng.seed = 73019
	_player.preferred_aim_target = null
	_friend.respawn_at(Vector3(600, 700, 0), Vector3(600, 700, -200))
	_target.respawn_at(Vector3(0, 500, -200), Vector3(0, 500, 0))
	if not _target.is_in_group("ships"):
		_target.add_to_group("ships")
	_rock.collision_layer = 0
	_rig.snap_to_target()
	_sight_target(0.0)
	_shot_times.clear()
	_damage = 0.0
	_clock = 0.0
	await get_tree().physics_frame
	await get_tree().physics_frame


func _sight_target(angle_deg: float, distance := 200.0) -> void:
	_target.global_position = _rig.global_position - _rig.global_basis.z * distance \
		+ _rig.global_basis.x * distance * tan(deg_to_rad(angle_deg))
	_target.velocity = Vector3.ZERO


func _acquisition() -> void:
	_sight_target(3.0)
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("a hostile near the reticle can receive bounded assistance", _player.aim_assist_target == _target)
	_sight_target(9.0)
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("a preferred hostile far from the reticle cannot attract the guns", _player.aim_assist_target == null)
	_sight_target(0.0)
	_target.velocity = Vector3(235, 0, 0)
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("a fast crossing target beyond gun tracking requires manual lead", _player.aim_assist_target == null)
	_sight_target(7.0)
	_target.velocity = Vector3(-60, 0, 0)
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("aiming near a reachable lead point also acquires the hostile", _player.aim_assist_target == _target)
	_sight_target(0.0, 1100.0)
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("a hull outside round lifetime cannot receive assistance", _player.aim_assist_target == null)
	_sight_target(0.0)
	_target.velocity = Vector3(0, 0, -900)
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("an unreachable receding hull cannot receive assistance", _player.aim_assist_target == null)
	_sight_target(0.0)
	_target.dead = true
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	var dead_rejected: bool = _player.aim_assist_target == null
	_friend.global_position = _rig.global_position - _rig.global_basis.z * 200.0
	await get_tree().physics_frame
	_player.refresh_aim_assist(_friend)
	_check("friendly and destroyed contacts never become assisted targets", dead_rejected and _player.aim_assist_target == null)
	await _reset()
	_player.aim_camera = null
	_player.refresh_aim_assist(_target)
	_check("no view camera leaves assistance safely disabled", _player.aim_assist_target == null)
	_player.aim_camera = _rig.camera


func _obstructions() -> void:
	await _reset()
	_player.refresh_aim_assist(_target)
	_check("an unobstructed hostile can be acquired", _player.aim_assist_target == _target)
	var muzzle: Vector3 = _player.muzzle_points[0].global_position
	var midpoint: Vector3 = muzzle.lerp(_player.aim_point, 0.5)
	_rock.global_position = midpoint
	_rock.collision_layer = GameConfig.LAYER_ROCK
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("solid cover prevents acquiring a hidden hostile", _player.aim_assist_target == null)
	_rock.collision_layer = 0
	_friend.global_position = midpoint
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("a friendly hull blocking the ballistic corridor prevents assistance", _player.aim_assist_target == null)
	# This friend is visible beside the shot now, but reaches the midpoint
	# when the round does. It must be considered before launching the round.
	_friend.global_position = midpoint + Vector3.RIGHT * 30.0
	_friend.velocity = Vector3.LEFT * (30.0 / (muzzle.distance_to(midpoint) / _player.bolt_speed))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("a friendly crossing the future shot path prevents assistance", _player.aim_assist_target == null)
	_friend.global_position = Vector3(600, 700, 0)
	_friend.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.refresh_aim_assist(_target)
	_check("assistance recovers when the corridor clears", _player.aim_assist_target == _target)


func _ballistics() -> void:
	await _reset()
	_player.weapon_spread_deg = 0.0
	_player.velocity = Vector3(160, 0, 0)
	_target.velocity = Vector3(30, 20, 0)
	# A deliberately large cosmetic camera yaw makes accidental use of the
	# child camera obvious. Neither acquisition nor live rounds should use it.
	_rig.camera.transform = Transform3D(Basis.from_euler(Vector3(0, 0.3, 0)), Vector3(0, 0, 0.03))
	_player.refresh_aim_assist(_target)
	_check("camera feedback does not move the assistance acquisition axis", _player.aim_assist_target == _target)
	var muzzle: Vector3 = _player.muzzle_points[0].global_position
	Input.action_press("fire")
	_player._read_translation(1.0 / 60.0)
	Input.action_release("fire")
	var bolts := _bolts()
	var miss := INF
	var flight := INF
	var actual_muzzle := false
	if bolts.size() == 1:
		var bolt := bolts[0]
		actual_muzzle = bolt.global_position.distance_to(muzzle) < 0.001
		# Independently evaluate closest approach of the emitted round and hull.
		# This tests the solution without calling the production intercept solver.
		var offset := _target.global_position - bolt.global_position
		var relative := _target.velocity - bolt.velocity
		flight = -offset.dot(relative) / relative.length_squared()
		miss = (offset + relative * flight).length()
	_check("real rounds intercept from the active muzzle with inherited ship velocity",
		actual_muzzle and flight > 0.0 and flight < 1.4 and miss < 0.02,
		"rounds %d, closest pass %.4f m at %.3f s" % [bolts.size(), miss, flight])


func _cadence(rate: int) -> void:
	await _reset()
	_target.dead = true
	var delta := 1.0 / rate
	var payload := 0.0
	var valid_rounds := true
	Input.action_press("fire")
	for frame in rate * 2:
		_clock = frame * delta
		_player.velocity = Vector3.ZERO
		_player._read_translation(delta)
		# Repeated input polling without a weapon clock step cannot double-fire.
		_player._read_translation(delta)
		for bolt: LaserBolt in _bolts():
			payload += bolt.damage
			valid_rounds = valid_rounds and is_equal_approx(bolt.damage, 3.0) \
				and is_equal_approx(bolt.velocity.length(), 620.0) and is_equal_approx(bolt.lifetime, 1.4)
			bolt.free()
		_player._update_weapon(delta)
	Input.action_release("fire")
	var shots := _shot_times.size()
	var rhythm := true
	for index in range(1, shots):
		var spacing := _shot_times[index] - _shot_times[index - 1]
		rhythm = rhythm and absf(spacing - 0.05) <= delta + 0.00001
	_check("%d TPS sustains 20 Hz without duplicate polling shots" % rate,
		shots == 40 and rhythm, "%d rounds in 2 seconds" % shots)
	_check("%d TPS uses shared 3-damage rounds and 60 nominal damage per second" % rate,
		valid_rounds and is_equal_approx(payload / 2.0, 60.0) \
			and is_equal_approx(_player.bolt_damage, _target.bolt_damage) \
			and is_equal_approx(_player.fire_interval, _target.fire_interval))
	for _frame in rate:
		_player._read_translation(delta)
		_player._update_weapon(delta)
	_check("%d TPS releasing the trigger stops firing immediately" % rate, _shot_times.size() == shots)


func _crossing_target(assistance: bool) -> float:
	await _reset()
	if not assistance:
		_target.remove_from_group("ships")
		_player.preferred_aim_target = null
	_sim_frame = 0
	_sim_total = _sim_fire_frames + 90
	_moving = true
	Input.action_press("fire")
	while _sim_frame < _sim_total:
		await get_tree().physics_frame
	_moving = false
	Input.action_release("fire")
	var fired := _shot_times.size()
	var hits := _damage / 3.0
	print("    95 m/s crossing / %s: %d rounds, %.0f hits (%.1f%%)" % [
		"assisted" if assistance else "unaided", fired, hits, hits / maxf(fired, 1) * 100.0])
	_check("%s moving-target run fires a full three-second burst" % ("assisted" if assistance else "unaided"),
		fired == 60 and not _target.dead and is_equal_approx(hits, roundf(hits)))
	return hits / maxf(fired, 1)


func _physics_process(delta: float) -> void:
	if not _moving:
		return
	_target.velocity = Vector3(95, 0, 0)
	# Manual pilot follows the current hull center, not its future position.
	_player.global_basis = Basis.looking_at(_target.global_position - _player.global_position)
	_player.velocity = Vector3.ZERO
	_rig.snap_to_target()
	# Chase-camera height otherwise puts its reticle above the body center.
	# Both runs put the clean sight on the same hull; only assistance differs.
	_rig.global_basis = Basis.looking_at(_target.global_position - _rig.global_position)
	_clock = _sim_frame * delta
	if _sim_frame >= _sim_fire_frames:
		Input.action_release("fire")
	_player._read_translation(delta)
	_player._update_weapon(delta)
	# Match the live tree's Ships/player -> Ships/enemy -> Effects/round order:
	# acquire/fire at the current pose, then advance both hull and projectile.
	_target.move_and_slide()
	for bolt: LaserBolt in _bolts():
		if not bolt.is_queued_for_deletion():
			bolt._physics_process(delta)
	_sim_frame += 1


func _bolts() -> Array[LaserBolt]:
	var result: Array[LaserBolt] = []
	for child: Node in _effects.get_children():
		if child is LaserBolt and not child.is_queued_for_deletion():
			child.set_physics_process(false)
			result.append(child as LaserBolt)
	return result


func _cleanup_effects() -> void:
	for child: Node in _effects.get_children():
		child.free()


func _check(caption: String, ok: bool, detail := "") -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", caption, " / " + detail if not ok and not detail.is_empty() else ""])
