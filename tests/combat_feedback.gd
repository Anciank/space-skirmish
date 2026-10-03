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
	enemy.global_position = player.global_position + Vector3.FORWARD * (player.bolt_speed * GameConfig.BOLT_LIFETIME + 50.0)
	await _step()
	_check("beyond projectile lifetime is explicitly out of range", hud._solution_status == "OUT OF RANGE" and hud._lead_screen_point() == Vector2.INF)
	enemy.global_position = player.global_position + Vector3.FORWARD * 100.0
	enemy.velocity = Vector3.FORWARD * player.bolt_speed * 2.0
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
	ally.global_position = player.global_position + Vector3(30, 0, -90)
	ally.velocity = Vector3(-200, 0, 0)
	await _step()
	_check("a friendly crossing the future ballistic path hides guidance", hud._solution_status == "LINE OF FIRE BLOCKED" and hud._lead_screen_point() == Vector2.INF)
	ally.global_position = Vector3(200, 500, 0)
	ally.velocity = Vector3.ZERO
	player.velocity = Vector3(75, 0, 0)
	enemy.velocity = Vector3(0, 40, 0)
	await _step()
	var muzzle: Node3D = player.muzzle_points[player._muzzle_index % player.muzzle_points.size()]
	var time := Gunnery.intercept_time(enemy.global_position - muzzle.global_position, enemy.velocity - player.velocity * 0.2, player.bolt_speed)
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
	await _large_scoreboard(hud)
	_main._show_title()
	_main.queue_free()
	rock.queue_free()
	await get_tree().process_frame
	await Sfx.finish_audio()
	print("--- combat feedback: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _large_scoreboard(hud: Control) -> void:
	var window_size := get_window().size
	var locale := L10n.locale
	L10n.set_language("en")
	get_window().size = Vector2i(1280, 720)
	_scoreboard_roster(3, 3)
	await _render_frames(3)
	var small: Dictionary = hud._scoreboard_layout()
	_check("the familiar six-pilot scoreboard retains its full-size single panel",
		small.rows.size() == 6 and small.pages == 1 and small.font_size == 16 and small.height == 408.0)
	_scoreboard_roster(32, 32)
	Input.action_press("scoreboard")
	for pixels: Vector2i in [Vector2i(1280, 720), Vector2i(800, 450)]:
		L10n.set_language("en")
		get_window().size = pixels
		await _render_frames(3)
		await _score_key(KEY_HOME)
		var first: Dictionary = hud._scoreboard_layout()
		var seen: Dictionary = {}
		var readable := true
		for page in first.pages:
			var layout: Dictionary = hud._scoreboard_layout()
			readable = readable and _scoreboard_fits(hud, layout, pixels)
			for row: Dictionary in layout.rows:
				seen[row.name] = true
			if page < first.pages - 1:
				await _score_key(KEY_PAGEDOWN)
		var all_records := seen.size() == 64
		for name: String in GameMatch.pilots:
			all_records = all_records and seen.has(name)
		_check("%dx%d real page navigation reaches every one of 64 pilot records" % [pixels.x, pixels.y], all_records)
		_check("%dx%d paged scoreboard fits with readable native-pixel rows" % [pixels.x, pixels.y], readable)
		var layout: Dictionary = hud._scoreboard_layout()
		var end_page: int = layout.page
		await _score_key(KEY_PAGEDOWN)
		_check("%dx%d last-page navigation clamps safely" % [pixels.x, pixels.y], hud._scoreboard_page == end_page)
		await _score_key(KEY_HOME)
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		Input.parse_input_event(wheel)
		await _render_frames(2)
		var wheel_worked: bool = hud._scoreboard_page == 1
		var pad := InputEventJoypadButton.new()
		pad.button_index = JOY_BUTTON_DPAD_RIGHT
		pad.pressed = true
		Input.parse_input_event(pad)
		await _render_frames(2)
		_check("%dx%d wheel and unbound horizontal D-pad both page the records" % [pixels.x, pixels.y],
			wheel_worked and hud._scoreboard_page == 2)
		pad.pressed = false
		Input.parse_input_event(pad)
		var languages_fit := true
		for code: String in L10n.language_codes():
			L10n.set_language(code)
			await _render_frames(1)
			layout = hud._scoreboard_layout()
			var language_fit := _scoreboard_fits(hud, layout, pixels)
			for source: String in ["PAGE %d / %d", "PAGE UP / DOWN · WHEEL · D-PAD LEFT / RIGHT"]:
				language_fit = language_fit and L10n.catalogue(code).has(source)
			var page_width: float = hud._measure(L10n.text("PAGE %d / %d") % [layout.page + 1, layout.pages], 12)
			var hint_width: float = hud._measure(L10n.text("PAGE UP / DOWN · WHEEL · D-PAD LEFT / RIGHT"), 11)
			language_fit = language_fit and page_width <= 206.0 and hint_width <= 592.0
			var own: TextLine = hud._shaped_text(L10n.pilot_name("YOU"), layout.font_size)
			language_fit = language_fit and own.get_size().y <= layout.row_height
			if not language_fit:
				print("    %s scoreboard font bounds: pilot height %.1f / row %.1f, page %.1f / 206, hint %.1f / 592" % [
					code, own.get_size().y, layout.row_height, page_width, hint_width])
			languages_fit = languages_fit and language_fit
		_check("%dx%d page captions and pilot rows fit in all twelve languages" % [pixels.x, pixels.y], languages_fit)
	# Paging must not steal keys/buttons already bound to flying the ship.
	await _score_key(KEY_HOME)
	var arrow := InputEventKey.new()
	arrow.keycode = KEY_UP
	arrow.physical_keycode = KEY_UP
	arrow.pressed = true
	Input.parse_input_event(arrow)
	await _render_frames(1)
	var flight_keys: bool = Input.is_action_pressed("thrust_forward") and hud._scoreboard_page == 0
	arrow.pressed = false
	Input.parse_input_event(arrow)
	var vertical := InputEventJoypadButton.new()
	vertical.button_index = JOY_BUTTON_DPAD_UP
	vertical.pressed = true
	Input.parse_input_event(vertical)
	await _render_frames(1)
	_check("scoreboard paging preserves arrow and vertical D-pad flight controls",
		flight_keys and Input.is_action_pressed("thrust_up") and hud._scoreboard_page == 0)
	vertical.pressed = false
	Input.parse_input_event(vertical)
	await _score_key(KEY_END)
	Input.action_release("scoreboard")
	await _render_frames(2)
	await _score_key(KEY_PAGEDOWN)
	Input.action_press("scoreboard")
	await _render_frames(2)
	_check("closing and reopening the scoreboard returns to its first page", hud._scoreboard_page == 0)
	Input.action_release("scoreboard")
	get_window().size = window_size
	L10n.set_language(locale)
	await _render_frames(2)


func _scoreboard_roster(blue: int, red: int) -> void:
	GameMatch.reset_match()
	GameMatch.register_pilot("YOU", GameConfig.TEAM_BLUE)
	for index in range(1, blue):
		GameMatch.register_pilot("AZ-%02d" % index, GameConfig.TEAM_BLUE)
	for index in range(1, red + 1):
		GameMatch.register_pilot("CR-%02d" % index, GameConfig.TEAM_RED)


func _scoreboard_fits(hud: Control, layout: Dictionary, pixels: Vector2i) -> bool:
	var actual_scale := minf(float(pixels.x) / hud.size.x, float(pixels.y) / hud.size.y)
	var painted := Rect2(layout.origin, Vector2(640.0, layout.height) * layout.factor)
	var readable: bool = layout.font_size * layout.factor * actual_scale >= 13.0 \
		and Rect2(Vector2.ZERO, hud.size).encloses(painted)
	var baseline := 103.0
	var team := -1
	for row: Dictionary in layout.rows:
		if row.team != team:
			team = row.team
			baseline += layout.team_height
		var line: TextLine = hud._shaped_text(L10n.pilot_name(String(row.name)), layout.font_size)
		readable = readable and line.get_size().y <= layout.row_height \
			and baseline + line.get_line_descent() < layout.height - 54.0
		baseline += layout.row_height
	return readable


func _score_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await _render_frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _render_frames(1)


func _render_frames(count: int) -> void:
	for _frame in count:
		await get_tree().process_frame


func _step() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
