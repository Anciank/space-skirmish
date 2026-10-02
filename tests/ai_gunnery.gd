extends Node3D
## Focused AI gunnery test: one pilot, one stationary hostile, nothing else in
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
var _traced := 0
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
	_ai.respawn_at(Vector3.ZERO, Vector3(0, 0, -DISTANCE))

	# Force the duel: no target auto-acquisition, no random patrol waypoints.
	_ai.target = _dummy
	await get_tree().physics_frame
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
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
	# Time spent in each AI state, so "why is it out at 320 m" is answerable.
	var state_frames := {0: 0, 1: 0, 2: 0, 3: 0}

	for i in FRAMES:
		await get_tree().physics_frame
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
		# When the AI thinks it is firing, trace a hypothetical bolt so we can see
		# exactly what it would hit.


	_check("ai kept its target", _ai.target == _dummy or _dummy.dead)
	_check("ai never flew into its target", min_range > 40.0,
		"(closest %.0f m)" % min_range)
	var band_pct := 100.0 * frames_in_band / float(FRAMES)
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
			100.0 * int(state_frames.get(s, 0)) / float(FRAMES)])
	_check("ai is not drifting away from its target", radial < 25.0,
		("(radial drift %+.1f m/s)" % radial))
	_check("ai pointed its nose at the target", min_angle < 20.0,
		"(worst snap %.1f deg off)" % min_angle)
	_check("ai fired", peak_bolts > 0, "(peak %d bolts in flight)" % peak_bolts)
	_check("ai fire connected", _total_damage > 0.0,
		("(%.0f total damage)" % _total_damage))
	_check("sustained fire strips shields", lowest_shield < _dummy.shield_max,
		"(shield dipped to %.0f)" % lowest_shield)

	print("")
	print("--- %d failures ---" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
