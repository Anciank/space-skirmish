extends Node
## Run the full five-minute round at the normal physics timestep.
## Use --fixed-fps 60 to advance simulation quickly without changing physics.

var _main: Node3D
var _checks := 0
var _failures := 0
var _preferences: Dictionary
var _seed := 20261002


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preferences = GameSettings.values.duplicate()
	GameSettings.reset_to_defaults(false)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--difficulty="):
			GameSettings.set_value("difficulty", argument.get_slice("=", 1).to_int(), false)
		elif argument.begins_with("--seed="):
			_seed = argument.get_slice("=", 1).to_int()
	_main = load("res://scenes/main.tscn").instantiate()
	_main.start_in_menu = true
	add_child(_main)
	_main._rng.seed = _seed
	_main._start_match()
	for entry: Dictionary in _main._roster:
		entry.ship._rng.seed = _seed ^ hash(entry.name)
	var samples := 0
	var peak_effects := 0
	var invariant_failure := ""
	for frame in 18100:
		await get_tree().physics_frame
		if _main.state == _main.State.RESULTS:
			break
		if frame % 60 != 0:
			continue
		samples += 1
		if _main._roster.size() != 6 or _main._pending.size() > 6:
			invariant_failure = "roster/pending count at frame %d" % frame
			break
		for row: Dictionary in _main._roster:
			var ship: SpaceShip = row.ship
			if not is_instance_valid(ship):
				invariant_failure = "invalid roster ship at frame %d" % frame
				break
			if not ship.global_position.is_finite() or not ship.velocity.is_finite() or not ship.global_basis.is_finite():
				invariant_failure = "non-finite flight state at frame %d" % frame
				break
			if not ship.dead and ship.global_position.length() > GameConfig.ARENA_RADIUS + 8.0:
				invariant_failure = "ship escaped sphere at frame %d" % frame
				break
		peak_effects = maxi(peak_effects, _main.effects_root.get_child_count())
		if not invariant_failure.is_empty():
			break
	_check("full round reaches debrief", _main.state == _main.State.RESULTS and GameMatch.remaining == 0.0)
	_check("fleet remains valid throughout round (%d samples) %s" % [samples, invariant_failure], invariant_failure.is_empty() and samples >= 295)
	_check("transient effects remain bounded (peak %d)" % peak_effects, peak_effects < 500)
	var team_kills := {0: 0, 1: 0}
	var total_shots := 0
	var total_deaths := 0
	var total_hits := 0
	var total_damage := 0.0
	for pilot: Dictionary in GameMatch.pilots.values():
		team_kills[pilot.team] += pilot.kills
		total_shots += pilot.shots
		total_deaths += pilot.deaths
		total_hits += pilot.hits
		total_damage += pilot.damage
	_check("team scores match persistent pilot records", team_kills == GameMatch.scores)
	_check("real combat and redeploys occurred (%d shots, %d deaths)" % [total_shots, total_deaths], total_shots > 100 and total_deaths > 0)
	var final_scores := GameMatch.scores.duplicate()
	var final_roster: int = _main._roster.size()
	for _i in 120:
		await get_tree().process_frame
	_check("debrief stays frozen", GameMatch.scores == final_scores and _main._roster.size() == final_roster and _main._pending.is_empty())
	print("round audit: " + JSON.stringify({"difficulty": GameSettings.DIFFICULTIES[int(GameSettings.get_value("difficulty"))], "deployment_seed": _seed, "scores": GameMatch.scores, "shots": total_shots, "hits": total_hits, "effective_damage": total_damage, "deaths": total_deaths, "peak_effects": peak_effects}))
	_main._show_title()
	_main.queue_free()
	await get_tree().process_frame
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	print("--- match soak: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
