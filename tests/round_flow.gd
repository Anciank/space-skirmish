extends Node
## Real-menu integration: boot, deploy, pause, settings, respawn, debrief and replay.

var _main: Node3D
var _checks := 0
var _failures := 0
var _original_settings: Dictionary
var _original_path: String
var _test_path: String
var _capture_spawn := false
var _spawn_snapshot: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_original_settings = GameSettings.values.duplicate()
	_original_path = GameSettings.storage_path
	_test_path = "user://round-flow-test-%d.cfg" % Time.get_ticks_usec()
	GameSettings.storage_path = _test_path
	GameSettings.reset_to_defaults(false)
	_small_fleet_preferences()
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _frames(3)
	await _run()
	await _npc_flow()
	_main._show_title()
	_main.queue_free()
	await _frames(3)
	GameSettings.values = _original_settings
	GameSettings.storage_path = _original_path
	GameSettings._apply()
	DirAccess.remove_absolute(_test_path)
	DirAccess.remove_absolute(_test_path + ".tmp")
	await Sfx.finish_audio()
	print("--- round flow: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _run() -> void:
	print("--- round flow ---")
	_check("boot waits at command screen", _main.menu.page == "title" and _main.player == null)
	_check("clock waits for deployment", not GameMatch.running)
	var full_time := GameMatch.remaining
	await _frames(5)
	_check("no battle runs behind title", GameMatch.remaining == full_time and _main._roster.is_empty())
	await _activate("Settings")
	_check("keyboard opens settings", _main.menu.page == "settings")
	var sensitivity := _main.menu._frame.get_node("mouse_sensitivity") as HSlider
	sensitivity.value = 1.75
	GameSettings.set_value("invert_y", true)
	_check("settings changes persist", GameSettings.last_save_error == OK)
	GameSettings.values = GameSettings.DEFAULTS.duplicate()
	GameSettings.load_preferences()
	_check("preferences survive reload", is_equal_approx(float(GameSettings.get_value("mouse_sensitivity")), 1.75) and bool(GameSettings.get_value("invert_y")))
	# A damaged or hand-edited preference file must not poison flight transforms.
	var malformed := ConfigFile.new()
	malformed.set_value("player", "mouse_sensitivity", "bad")
	malformed.set_value("player", "field_of_view", 500.0)
	malformed.set_value("player", "invert_y", "yes")
	malformed.save(GameSettings.storage_path)
	GameSettings.load_preferences()
	_check("invalid preferences recover safely", GameSettings.get_value("mouse_sensitivity") == 1.0 and GameSettings.get_value("field_of_view") == 100.0 and GameSettings.get_value("invert_y") == false)
	GameSettings.reset_to_defaults(false)
	_small_fleet_preferences()
	await _key(KEY_ESCAPE)
	_check("escape returns from settings", _main.menu.page == "title")
	await _activate("Deploy")
	_check("keyboard deploys the real roster", _main.state == _main.State.PLAYING and _main._roster.size() == 6)
	_check("balanced three-on-three battle", GameMatch.pilots.size() == 6 and _main.enemy_count == _main.ally_count + 1)
	_check("deployment captures aim and hides menu", bool(_main.player._mouse_captured) and not _main.menu.visible)
	_check("camera starts on ship", _main.rig.global_position.distance_to(_main.player.global_position) < 15.0)
	await _key(KEY_ESCAPE)
	_check("escape opens interactive pause", _main.paused and get_tree().paused and _main.menu.page == "pause")
	var clock := GameMatch.remaining
	var positions: Array[Vector3] = []
	for row: Dictionary in _main._roster:
		positions.append(row.ship.global_position)
	await _frames(10)
	_check("pause freezes the clock", GameMatch.remaining == clock)
	var stationary := true
	for i in _main._roster.size():
		stationary = stationary and positions[i].is_equal_approx(_main._roster[i].ship.global_position)
	_check("pause freezes all ship physics", stationary)
	await _activate("Settings")
	_check("settings work during pause", _main.menu.page == "settings" and get_tree().paused)
	GameSettings.set_value("field_of_view", 92.0, false)
	_check("field of view applies to live camera", is_equal_approx(_main.rig.base_fov, 92.0))
	await _key(KEY_ESCAPE)
	_check("settings back preserves pause", _main.menu.page == "pause" and _main.paused)
	await _key(KEY_ESCAPE)
	_check("second escape resumes real gameplay", not get_tree().paused and not _main.paused and not _main.menu.visible)
	# Repeated deaths must replace a roster entry instead of accumulating corpses.
	for iteration in 3:
		var player: SpaceShip = _main.player
		var killer: SpaceShip = _enemy()
		player.take_damage(10000, killer)
		_check("death queues exactly one player redeploy %d" % iteration, _main._pending.filter(func(row: Dictionary): return row.name == "YOU").size() == 1)
		await _frames(2)
		for pending: Dictionary in _main._pending:
			if pending.name == "YOU":
				pending.left = 0.0
		_main._update_respawns(0.0)
		await _frames(2)
		_check("respawn retains six roster slots %d" % iteration, _main._roster.size() == 6 and _main.ships_root.get_child_count() == 6)
		_check("respawn gives a fresh live player %d" % iteration, is_instance_valid(_main.player) and _main.player != player and not _main.player.dead and _main.hud.player == _main.player)
	_check("pilot deaths persist across ships", GameMatch.pilots.YOU.deaths == 3)
	# Scores, damage and shots are recorded through the actual ship signals.
	var victim: SpaceShip = _enemy()
	_main.player._fire_timer = 0.0
	_main.player.fire()
	victim.take_damage(10000, _main.player)
	_check("enemy destruction awards one point", GameMatch.scores[0] == 1 and GameMatch.pilots.YOU.kills == 1)
	_check("debrief records effective damage and shots", is_equal_approx(GameMatch.pilots.YOU.damage, 200.0) and GameMatch.pilots.YOU.shots == 1)
	GameMatch.remaining = 0.01
	await _frames(4)
	_check("time expiry opens debrief and freezes combat", _main.state == _main.State.RESULTS and _main.menu.page == "results" and get_tree().paused)
	_check("higher-scoring team wins", GameMatch.winner == GameConfig.TEAM_RED)
	_check("pending redeploys are cleared at round end", _main._pending.is_empty())
	var scores := GameMatch.scores.duplicate()
	var ledger := GameMatch.pilots.duplicate(true)
	GameMatch.add_score(0)
	GameMatch.log_kill("YOU", 0, "CR-01", 1)
	GameMatch.record_damage("YOU", 1000.0)
	await _frames(6)
	_check("finished scores and stats remain immutable", scores == GameMatch.scores and ledger == GameMatch.pilots)
	await _activate("PlayAgain")
	_check("replay resumes a fresh round", _main.state == _main.State.PLAYING and not get_tree().paused and GameMatch.running)
	_check("replay resets every pilot statistic", GameMatch.pilots.YOU.kills == 0 and GameMatch.pilots.YOU.deaths == 0 and GameMatch.pilots.YOU.damage == 0.0)
	_check("replay clears old projectiles", _main.effects_root.get_child_count() == 0)
	GameMatch.remaining = 0.01
	await _frames(4)
	_check("equal scores produce a draw", GameMatch.winner == GameMatch.DRAW)
	await _activate("ReturnTitle")
	_check("debrief returns to a clean command screen", _main.state == _main.State.TITLE and _main.player == null and _main._roster.is_empty() and not GameMatch.running)
	await _activate("Deploy")
	await _key(KEY_ESCAPE)
	await _activate("Restart")
	_check("pause restart resumes safely", not get_tree().paused and _main._roster.size() == 6 and _main.state == _main.State.PLAYING)


func _npc_flow() -> void:
	GameSettings.reset_to_defaults(false)
	_main._show_title()
	await _frames(3)
	var allies := _main.menu._frame.get_node_or_null("AllyCount") as SpinBox
	var enemies := _main.menu._frame.get_node_or_null("EnemyCount") as SpinBox
	_check("command exposes bounded integer ally and enemy selectors", allies != null and enemies != null)
	if allies == null or enemies == null:
		return
	_check("default selectors offer the full thirty-two-versus-thirty-two fleet",
		allies.value == 31 and enemies.value == 32 and allies.min_value == 0 and allies.max_value == 31 \
		and enemies.min_value == 0 and enemies.max_value == 32 and allies.step == 1 and enemies.step == 1)
	var ratio := _main.menu._frame.get_node("SquadronRatio") as Label
	_check("command ratio includes the player and fits two-digit team sizes",
		ratio.text == "32 : 32" and ratio.get_theme_font("font").get_string_size(ratio.text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, ratio.get_theme_font_size("font_size")).x <= ratio.size.x)
	_check("deployment remains the first command keyboard focus",
		get_viewport().gui_get_focus_owner() == _main.menu._frame.get_node("Deploy"))
	_prepare_spawn_snapshot()
	await _activate("Deploy")
	_check("default command deployment creates all sixty-four live pilots", _fleet_matches(31, 32))
	_check_spawn_clearance("default fleet")
	_main._show_title()
	await _frames(3)
	allies = _main.menu._frame.get_node("AllyCount") as SpinBox
	enemies = _main.menu._frame.get_node("EnemyCount") as SpinBox
	allies.value = 2
	enemies.value = 3
	allies.grab_focus()
	await _key(KEY_UP)
	enemies.grab_focus()
	await _key(KEY_DOWN)
	_check("keyboard changes both NPC selectors through their real input handlers",
		allies.value == 3 and enemies.value == 2 \
		and GameSettings.get_value("ally_count") == 3 and GameSettings.get_value("enemy_count") == 2)
	allies.value = 4
	enemies = _main.menu._frame.get_node("EnemyCount") as SpinBox
	enemies.value = 5
	_check("changing selectors saves the requested NPC counts",
		GameSettings.get_value("ally_count") == 4 and GameSettings.get_value("enemy_count") == 5 \
		and GameSettings.last_save_error == OK)
	GameSettings.values = GameSettings.DEFAULTS.duplicate()
	GameSettings.load_preferences()
	_main.menu.show_title()
	await _frames(3)
	_check("NPC counts survive disk reload and rebuild the selectors",
		GameSettings.get_value("ally_count") == 4 and GameSettings.get_value("enemy_count") == 5 \
		and _main.menu._frame.get_node("AllyCount").value == 4 \
		and _main.menu._frame.get_node("EnemyCount").value == 5)
	GameSettings.set_value("ally_count", 1.0e30, false)
	GameSettings.set_value("enemy_count", -1.0e30, false)
	var upper_lower: bool = GameSettings.get_value("ally_count") == 31 and GameSettings.get_value("enemy_count") == 0
	GameSettings.set_value("ally_count", -1.0e30, false)
	GameSettings.set_value("enemy_count", 1.0e30, false)
	_check("NPC preferences clamp both ends of their supported range",
		upper_lower and GameSettings.get_value("ally_count") == 0 and GameSettings.get_value("enemy_count") == 32)
	var valid := true
	for invalid: Variant in ["four", true, NAN, INF, [], {}]:
		GameSettings.set_value("ally_count", invalid, false)
		GameSettings.set_value("enemy_count", invalid, false)
		valid = valid and GameSettings.get_value("ally_count") == 31 and GameSettings.get_value("enemy_count") == 32
	_check("invalid NPC inputs recover to safe defaults", valid)
	var malformed := ConfigFile.new()
	malformed.set_value("player", "ally_count", "many")
	malformed.set_value("player", "enemy_count", INF)
	malformed.save(GameSettings.storage_path)
	GameSettings.load_preferences()
	_check("hand-edited invalid NPC preferences load safely",
		GameSettings.get_value("ally_count") == 31 and GameSettings.get_value("enemy_count") == 32)
	await _deploy_counts(0, 1)
	_check("solo pilot versus one enemy deploys the actual two-ship roster", _fleet_matches(0, 1))
	await _deploy_counts(4, 5)
	_check("four allies and five enemies deploy as ten distinct pilots", _fleet_matches(4, 5))
	var old_fleet: Array = _main.ships_root.get_children()
	_enemy().take_damage(10000.0, _main.player)
	await _frames(2)
	var had_redeploys: bool = not _main._pending.is_empty()
	await _deploy_counts(31, 32)
	_check("maximum NPC settings deploy all sixty-four distinct pilots", _fleet_matches(31, 32))
	_check_spawn_clearance("maximum fleet")
	_check("changing fleet size retires old hulls and pending redeploys",
		had_redeploys and _retired(old_fleet) and _main._pending.is_empty())
	await _key(KEY_ESCAPE)
	await _standings_scroll("pause")
	old_fleet = _main.ships_root.get_children()
	_prepare_spawn_snapshot()
	await _activate("Restart")
	_check("restart rebuilds the selected sixty-four-pilot fleet without leftovers",
		_fleet_matches(31, 32) and _retired(old_fleet) and _main._pending.is_empty())
	_check_spawn_clearance("restarted fleet")
	GameMatch.remaining = 0.01
	await _frames(4)
	await _standings_scroll("results")
	await _activate("ReturnTitle")
	_check("returning from the large fleet clears ships and pending redeploys",
		_main.player == null and _main._roster.is_empty() and _main.ships_root.get_child_count() == 0 \
		and _main._pending.is_empty())
	await _deploy_counts(0, 0)
	var clock := GameMatch.remaining
	await _frames(12)
	_check("zero-enemy practice keeps its player and the ordinary round clock",
		_fleet_matches(0, 0) and GameMatch.running and _main.state == _main.State.PLAYING \
		and GameMatch.remaining < clock and GameMatch.remaining > 0.0)
	old_fleet = _main.ships_root.get_children()
	await _deploy_counts(0, 1)
	_check("changing counts at command replaces the practice fleet and pilot ledger",
		_fleet_matches(0, 1) and _retired(old_fleet) and not GameMatch.pilots.has("AZ-01") \
		and not GameMatch.pilots.has("CR-32"))
	_main._show_title()
	await _frames(2)
	GameSettings.set_value("ally_count", 31, false)
	GameSettings.set_value("enemy_count", 32, false)
	var fixture := load("res://scenes/main.tscn").instantiate() as Node3D
	fixture.start_in_menu = false
	fixture.ally_count = 1
	fixture.enemy_count = 2
	add_child(fixture)
	await _frames(4)
	_check("direct-start tools preserve explicit export counts over saved preferences",
		fixture.ally_count == 1 and fixture.enemy_count == 2 and fixture._roster.size() == 4 \
		and fixture.ships_root.get_child_count() == 4 and GameMatch.pilots.size() == 4)
	fixture._show_title()
	fixture.queue_free()
	await _frames(3)


func _deploy_counts(allies: int, enemies: int) -> void:
	_main._show_title()
	await _frames(2)
	(_main.menu._frame.get_node("AllyCount") as SpinBox).value = allies
	(_main.menu._frame.get_node("EnemyCount") as SpinBox).value = enemies
	if allies == 31 and enemies == 32:
		_prepare_spawn_snapshot()
	await _activate("Deploy")


func _prepare_spawn_snapshot() -> void:
	_spawn_snapshot.clear()
	_capture_spawn = true


func _measure_spawn_clearance() -> Dictionary:
	var positions: Array[Vector3] = []
	var nearest_ship := INF
	var nearest_rock := INF
	var nearest_body := INF
	var nearest_wall := INF
	for entry: Dictionary in _main._roster:
		var ship := entry.ship as SpaceShip
		var pos := ship.global_position
		for other: Vector3 in positions:
			nearest_ship = minf(nearest_ship, pos.distance_to(other))
		positions.append(pos)
		# The irregular visible/collision surfaces can extend past nominal radii.
		for rock: Asteroid in _main.arena.asteroids:
			if not rock.dead:
				nearest_rock = minf(nearest_rock,
					pos.distance_to(rock.global_position) - rock.radius * 1.3 - ship.collision_radius)
		for body: StarBody in _main.arena.bodies:
			nearest_body = minf(nearest_body,
				pos.distance_to(body.global_position) - body.radius * 1.3 - ship.collision_radius)
		nearest_wall = minf(nearest_wall, GameConfig.ARENA_RADIUS - pos.length() - ship.collision_radius)
	return {"count": positions.size(), "ship": nearest_ship, "rock": nearest_rock,
		"body": nearest_body, "wall": nearest_wall}


func _check_spawn_clearance(caption: String) -> void:
	var ship_gap := float(_spawn_snapshot.get("ship", -INF))
	var rock_gap := float(_spawn_snapshot.get("rock", -INF))
	var body_gap := float(_spawn_snapshot.get("body", -INF))
	var wall_gap := float(_spawn_snapshot.get("wall", -INF))
	_check("%s births have no duplicate or nearby hulls (minimum %.1f m)" % [caption, ship_gap],
		_spawn_snapshot.get("count", 0) == 64 and ship_gap > 100.0)
	_check("%s births clear rock/body/wall surfaces (%.1f / %.1f / %.1f m)" % [caption, rock_gap, body_gap, wall_gap],
		rock_gap > 100.0 and body_gap > 100.0 and wall_gap > 100.0)


func _small_fleet_preferences() -> void:
	# Lifecycle checks use six pilots; the count flow separately deploys all 64.
	GameSettings.set_value("ally_count", 2, false)
	GameSettings.set_value("enemy_count", 3, false)


func _fleet_matches(allies: int, enemies: int) -> bool:
	var blue := 0
	var red := 0
	var names: Dictionary = {}
	var total := allies + enemies + 1
	for entry: Dictionary in _main._roster:
		var ship := entry.ship as SpaceShip
		if not is_instance_valid(ship) or ship.get_parent() != _main.ships_root or ship.dead:
			return false
		if not ship.global_position.is_finite() or not ship.global_basis.is_finite() \
				or ship.global_position.length() > GameConfig.ARENA_RADIUS:
			return false
		blue += 1 if ship.team == GameConfig.TEAM_BLUE else 0
		red += 1 if ship.team == GameConfig.TEAM_RED else 0
		names[ship.display_name] = true
	return blue == allies + 1 and red == enemies and names.size() == total \
		and _main.ally_count == allies and _main.enemy_count == enemies \
		and _main.ships_root.get_child_count() == total and GameMatch.pilots.size() == total \
		and names.has("YOU") and _main.state == _main.State.PLAYING


func _retired(fleet: Array) -> bool:
	for ship: Variant in fleet:
		if is_instance_valid(ship):
			return false
	return true


func _standings_scroll(page: String) -> void:
	var scroll := _main.menu._frame.get_node_or_null("StandingsScroll") as ScrollContainer
	_check(page + " exposes a scrollable large-fleet standings panel", scroll != null)
	if scroll == null:
		return
	await _frames(3)
	var rows := scroll.get_node("Rows") as Control
	var pilot_rows := 0
	var all_names := true
	for child: Node in rows.get_children():
		if String(child.name).begins_with("Pilot_"):
			pilot_rows += 1
	for pilot: String in GameMatch.pilots:
		for prefix: String in ["Pilot_", "K_", "D_", "Damage_"]:
			all_names = all_names and rows.has_node(prefix + pilot)
	var bar := scroll.get_v_scroll_bar()
	_check(page + " retains all four columns for every pilot in the sixty-four-person ledger",
		pilot_rows == 64 and all_names and bar.max_value > bar.page)
	var first := rows.get_node("Pilot_AZ-01") as Label
	var last := rows.get_node("Pilot_CR-32") as Label
	var initially_visible := scroll.get_global_rect().intersects(first.get_global_rect())
	var fixed_labels: Dictionary = {}
	for child: Node in _main.menu._frame.get_children():
		if child is Label:
			fixed_labels[child] = child.global_position
	scroll.grab_focus()
	await _key(KEY_PAGEDOWN)
	_check(page + " standings respond to keyboard paging", scroll.scroll_vertical > 0)
	await _key(KEY_END)
	await _frames(3)
	var complete := initially_visible and scroll.scroll_vertical > 0 \
		and absf(float(scroll.scroll_vertical) - (bar.max_value - bar.page)) <= 1.0
	var fixed := true
	for label: Label in fixed_labels:
		fixed = fixed and label.global_position.is_equal_approx(fixed_labels[label])
	for prefix: String in ["Pilot_", "K_", "D_", "Damage_"]:
		var cell := rows.get_node(prefix + "CR-32") as Label
		var rect := cell.get_global_rect()
		var viewport := scroll.get_global_rect().grow(0.5)
		complete = complete and viewport.encloses(rect) and cell.get_visible_line_count() == cell.get_line_count() \
			and cell.get_theme_font_size("font_size") >= 13
	_check(page + " scrolling makes the last pilot and all statistic columns fully readable",
		complete and fixed and last.is_visible_in_tree())
	var player_row := rows.get_node("Pilot_YOU") as Label
	scroll.ensure_control_visible(player_row)
	await _frames(3)
	_check(page + " scrolling can reveal the player among thirty-two friendly pilots",
		scroll.get_global_rect().grow(0.5).encloses(player_row.get_global_rect()))


func _enemy() -> SpaceShip:
	for row: Dictionary in _main._roster:
		var ship: SpaceShip = row.ship
		if ship.team == GameConfig.TEAM_RED and not ship.dead:
			return ship
	return null


func _activate(node_name: String) -> void:
	(_main.menu._frame.get_node(node_name) as Control).grab_focus()
	await _key(KEY_ENTER)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame
		# Snapshot as soon as the real menu transition finishes, before the rest
		# of the key-release waits can advance the fleet. The 100 m limits allow
		# a physics tick while still catching the old fixed-point spawn fallback.
		if _capture_spawn and _main.state == _main.State.PLAYING and _main._roster.size() == 64:
			_spawn_snapshot = _measure_spawn_clearance()
			_capture_spawn = false


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
