extends Node3D
## Focused AI gunnery test: one pilot, a stationary and then crossing hostile,
## with no scenery in
## the scene. Isolating the duel makes aim and lead bugs obvious instead of
## hiding behind a live five-ship dogfight.
##
##   godot --headless res://tests/ai_gunnery.tscn

const AI_SCENE := preload("res://scenes/ships/ai_ship.tscn")
const DUMMY_SCENE := preload("res://tests/dummy_target.tscn")

const DISTANCE := 160.0
const FRAMES := 900

var _ai: AIShip
var _dummy: SpaceShip
var _effects: Node3D
var _failures := 0
var _checks := 0
var _moving := false
var _fired := 0
var _total_damage := 0.0


func _count_damage(amount: float, _pos: Vector3, _attacker: Node) -> void:
	_total_damage += amount


func _ready() -> void:
	var ships := Node3D.new()
	ships.name = "Ships"
	add_child(ships)
	_effects = Node3D.new()
	_effects.name = "Effects"
	add_child(_effects)

	_dummy = DUMMY_SCENE.instantiate()
	ships.add_child(_dummy)
	_dummy.respawn_at(Vector3(0, 0, -DISTANCE), Vector3(0, 0, 0))

	_ai = AI_SCENE.instantiate()
	ships.add_child(_ai)
	_ai.weapon_fired.connect(func(): _fired += 1)
	_ai.respawn_at(Vector3.ZERO, Vector3(0, 0, -DISTANCE))

	# Force the duel: no target auto-acquisition, no random patrol waypoints.
	_ai.target = _dummy
	await get_tree().physics_frame
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s %s" % ["PASS" if ok else "FAIL", label, detail])


func _run() -> void:
	print("")
	print("--- AI gunnery: stationary target at %.0f m ---" % DISTANCE)

	# Count damage events, not net HP: shields regenerate, so a start/end HP
	# comparison reports zero even while the target is being hit constantly.
	# The accumulator must be a member — a lambda captures locals by value, so
	# `total_damage += amount` inside a closure would be written to a copy.
	_total_damage = 0.0
	_dummy.took_damage.connect(_count_damage)
	var min_angle := 999.0
	var peak_bolts := 0
	var min_range := 9999.0
	var max_range := 0.0
	var lowest_shield := _dummy.shield_max
	var frames_in_band := 0
	var frames_run := 0
	# Time spent in each AI state, so "why is it out at 320 m" is answerable.
	var state_frames := {0: 0, 1: 0, 2: 0, 3: 0}

	for i in FRAMES:
		await get_tree().physics_frame
		frames_run += 1
		var muzzle: Node3D = _ai.muzzle_points[0]
		var to_target: Vector3 = (_dummy.global_position - muzzle.global_position).normalized()
		var ang := rad_to_deg(_ai.forward().angle_to(to_target))
		var range_m := _ai.global_position.distance_to(_dummy.global_position)
		min_angle = minf(min_angle, ang)
		min_range = minf(min_range, range_m)
		max_range = maxf(max_range, range_m)
		if range_m >= GameConfig.AI_ENGAGE_BAND_MIN and range_m <= GameConfig.AI_ENGAGE_BAND_MAX * 1.35:
			frames_in_band += 1
		state_frames[_ai.state] = int(state_frames.get(_ai.state, 0)) + 1
		lowest_shield = minf(lowest_shield, _dummy.shield)
		peak_bolts = maxi(peak_bolts, get_tree().get_nodes_in_group("bolts").size())

		# Report every 60 frames so a trajectory problem is visible in the log.
		if i % 60 == 0:
			print("    t=%4.1fs  range=%6.1f m  nose=%5.1f deg  speed=%5.1f  state=%d  dmg=%3.0f" % [
				i / 60.0, range_m, ang, _ai.velocity.length(), _ai.state, _total_damage,
			])
		if _dummy.dead:
			break


	_check("ai kept its target", _ai.target == _dummy or _dummy.dead)
	_check("ai never flew into its target", min_range > 40.0,
		"(closest %.0f m)" % min_range)
	var band_pct := 100.0 * frames_in_band / float(frames_run)
	_check("ai spends most of the fight at fighting range", band_pct > 35.0,
		("(%.0f%% of the time between %d-%d m)" % [band_pct,
			GameConfig.AI_ENGAGE_BAND_MIN, int(GameConfig.AI_ENGAGE_BAND_MAX * 1.35)]))
	_check("ai did not run away across the arena", max_range < 700.0,
		"(furthest %.0f m)" % max_range)
	# Where is the momentum actually going? Positive = drifting away from the
	# target, which is the failure mode we are hunting.
	var radial := (_ai.velocity.dot((_ai.global_position - _dummy.global_position).normalized()))
	print("    final: radial drift %+.1f m/s, cmd(f/r/u)=%.2f/%.2f/%.2f, boost=%s, desired_speed=%.0f" % [
		radial, _ai.cmd_forward, _ai.cmd_right, _ai.cmd_up,
		str(_ai.boosting), _ai._desired_speed,
	])
	var names := {0: "PATROL", 1: "ENGAGE", 2: "EVADE", 3: "RETREAT"}
	for s: int in [0, 1, 2, 3]:
		print("    state %-8s %5.1f%% of the fight" % [names[s],
			100.0 * int(state_frames.get(s, 0)) / float(frames_run)])
	_check("ai is not drifting away from its target", radial < 25.0,
		("(radial drift %+.1f m/s)" % radial))
	_check("ai pointed its nose at the target", min_angle < 20.0,
		"(worst snap %.1f deg off)" % min_angle)
	_check("ai fired", peak_bolts > 0, "(peak %d bolts in flight)" % peak_bolts)
	_check("ai fire connected", _total_damage > 0.0,
		("(%.0f total damage)" % _total_damage))
	_check("sustained fire strips shields", lowest_shield < _dummy.shield_max,
		"(shield dipped to %.0f)" % lowest_shield)

	await _moving_regressions()
	_retreat_regressions()
	print("")
	print("--- AI gunnery: %d checks, %d failures ---" % [_checks, _failures])
	for child in get_children():
		child.queue_free()
	await get_tree().process_frame
	await Sfx.finish_audio()
	get_tree().quit(1 if _failures > 0 else 0)


func _moving_regressions() -> void:
	_ai.set_physics_process(false)
	_dummy.set_physics_process(false)
	for child in _effects.get_children():
		child.queue_free()
	await get_tree().process_frame
	_ai.respawn_at(Vector3.ZERO, Vector3.FORWARD * DISTANCE)
	_dummy.respawn_at(Vector3(80, 40, -200), Vector3.ZERO)
	_ai.target = _dummy
	_ai.state = AIShip.State.ENGAGE
	_ai.skill = 1.0
	_ai._aim_noise = Vector3.ZERO
	_ai._roll_bias = 0.35
	_ai._apply_steering(1.0)
	_check("banking preserves the nose's firing direction", _ai.forward().dot((_dummy.global_position - _ai.global_position).normalized()) > 0.9999)
	_ai.global_basis = Basis.IDENTITY
	_ai._roll_bias = 0.0
	_dummy.global_position = Vector3(300, 0, 0)
	_ai._apply_steering(0.02)
	var turn := Vector3.FORWARD.angle_to(_ai.forward())
	var expected := GameConfig.AI_TURN_RATE * 0.02
	_check("turn speed is bounded in radians per second", absf(turn - expected) < 0.0001)
	_dummy.global_position = Vector3(0, 0, -180)
	_dummy.velocity = Vector3.RIGHT * 80.0
	_ai.global_basis = Basis.IDENTITY
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ai.look_at(_ai._predicted_aim_point())
	_ai._burst_len = 0.8
	_ai._burst_timer = 0.0
	_ai._fire_timer = 0.0
	var before := _fired
	var angle := rad_to_deg(_ai.forward().angle_to((_dummy.global_position - _ai.global_position).normalized()))
	_ai._apply_weapons(1.0 / 60.0)
	_check("a crossing target can fire when the nose tracks its lead", _fired > before and angle > GameConfig.AI_FIRE_CONE_DEG + 1.0)
	_dummy.global_position = Vector3.FORWARD * (GameConfig.BOLT_SPEED * GameConfig.BOLT_LIFETIME + 500.0)
	_dummy.velocity = Vector3.ZERO
	_ai.look_at(_ai._predicted_aim_point())
	_ai._burst_len = 0.8
	_ai._burst_timer = 0.0
	_ai._fire_timer = 0.0
	before = _fired
	_ai._apply_weapons(1.0 / 60.0)
	_check("AI conserves fire when bolts cannot reach the target", _fired == before)
	for child in _effects.get_children():
		child.queue_free()
	await get_tree().process_frame
	_dummy.respawn_at(Vector3(0, 0, -180), Vector3.ZERO)
	_ai.respawn_at(Vector3.ZERO, Vector3.FORWARD * 180.0)
	_ai.target = _dummy
	_ai.state = AIShip.State.ENGAGE
	_ai.weapon_spread_deg = 0.0
	_ai._burst_len = 0.8
	_ai._burst_timer = 0.0
	_ai._burst_gap = 0.0
	_total_damage = 0.0
	_moving = true
	for _i in 240:
		await get_tree().physics_frame
	_moving = false
	_check("real bolts intercept a target crossing at 80 m/s", _total_damage >= 18.0, "(%.0f damage)" % _total_damage)


func _physics_process(delta: float) -> void:
	if not _moving:
		return
	_dummy.velocity = Vector3.RIGHT * 80.0
	_dummy.move_and_slide()
	_ai._update_weapon(delta)
	_ai.look_at(_ai._predicted_aim_point())
	_ai._apply_weapons(delta)


func _retreat_regressions() -> void:
	_ai.respawn_at(Vector3.ZERO, Vector3.FORWARD * DISTANCE)
	_dummy.respawn_at(Vector3.FORWARD * DISTANCE, Vector3.ZERO)
	_ai.target = _dummy
	_ai._rng.seed = 0xA11
	_ai.state = AIShip.State.ENGAGE
	_ai.shield = 0.0
	_ai.hull = 68.0
	_ai._think()
	_check("a pilot with 68 percent hull stays in the fight", _ai.state != AIShip.State.RETREAT)
	_ai.hull = GameConfig.AI_PANIC_HULL - 1.0
	_ai._think()
	var away := (_ai.global_position - _dummy.global_position).normalized()
	_check("critical hull immediately commands a boosted breakaway", _ai.state == AIShip.State.RETREAT and _ai.wants_boost and _ai._desired_dir.dot(away) > 0.999 and _ai._retreat_timer > 0.0)
	var held_retreat := true
	for _i in 100:
		_ai._think()
		held_retreat = held_retreat and _ai.state == AIShip.State.RETREAT
	_check("retreat remains stable until shield recovery or timeout", held_retreat)
	_ai.shield = 20.0
	_ai._think()
	_check("recovered shields let a damaged pilot rejoin combat", _ai.state != AIShip.State.RETREAT and not _ai.wants_boost)
	_ai.state = AIShip.State.RETREAT
	_ai.shield = 0.0
	_ai._retreat_timer = 0.0
	_ai._think()
	_check("an unrecovered retreat still respects its time limit", _ai.state != AIShip.State.RETREAT)
	_ai.hull_max = 200.0
	_ai.shield_max = 50.0
	_ai.hull = 70.0
	_ai.state = AIShip.State.ENGAGE
	_ai._retreat_cooldown = 0.0
	_ai._think()
	var stayed := _ai.state != AIShip.State.RETREAT
	_ai.hull = 66.0
	_ai._think()
	_check("panic follows hull percentage with unequal shield capacity", stayed and _ai.state == AIShip.State.RETREAT)
