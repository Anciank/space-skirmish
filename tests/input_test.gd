extends Node
## Input-path test.
##
##   godot --headless res://tests/input_test.tscn
##
## The smoke test drives the game with `Input.action_press()`, which bypasses the
## keyboard bindings entirely — it proves a controller *reads* actions but says
## nothing about whether W/S/mouse are actually bound to them. This suite closes
## that gap by pushing real `InputEventKey` / `InputEventMouseMotion` events
## through `Input.parse_input_event()`, which is the same entry point the OS uses.

const KEY_BINDINGS := {
	"thrust_forward": KEY_W,
	"thrust_back": KEY_S,
	"thrust_left": KEY_A,
	"thrust_right": KEY_D,
	"thrust_up": KEY_R,
	"thrust_down": KEY_F,
	"roll_left": KEY_Q,
	"roll_right": KEY_E,
	"boost": KEY_SHIFT,
	"fire": KEY_SPACE,
	"dampeners": KEY_X,
	"recenter": KEY_C,
	"next_target": KEY_TAB,
	"toggle_camera": KEY_V,
	"pause": KEY_ESCAPE,
	"restart": KEY_F5,
	"scoreboard": KEY_BACKSLASH,
}

var _failures := 0
var _checks := 0
var _main: Node3D
var _preferences: Dictionary


func _ready() -> void:
	_preferences = GameSettings.values.duplicate(true)
	GameSettings.reset_to_defaults(false)
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_main.start_in_menu = false
	_main.ally_count = 2
	_main.enemy_count = 3
	add_child(_main)
	await get_tree().physics_frame
	_run()


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("  %s  %s %s" % ["PASS" if ok else "FAIL", label, detail])


## A synthetic key-down that also *stays* down, so action state can be sampled
## mid-hold. `_tap()` above releases immediately, which is why it can only prove
## "no phantom press" and not "actually pressed".
func _press(action: String, keycode: Key, hold_frames := 3) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	await _step(hold_frames)


func _release(action: String, keycode: Key) -> void:
	Input.parse_input_event(_release_for(keycode))
	await _step(2)


func _section(t: String) -> void:
	print("")
	print("=== %s ===" % t)


## Presses and releases a physical key, letting the input system settle between.
func _tap(action: String, keycode: Key, frames := 3) -> void:
	var down := InputEventKey.new()
	down.physical_keycode = keycode
	down.keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	await _step(frames)
	await _release(action, keycode)


func _held(action: String) -> bool:
	return Input.is_action_pressed(action)


func _run() -> void:
	print("")
	print("--- input path: real key events through Input.parse_input_event ---")

	# ------------------------------------------------------------ bindings --
	_section("key bindings fire their actions")
	for action: String in KEY_BINDINGS:
		var before := _held(action)
		await _tap(action, KEY_BINDINGS[action], 2)
		_check("%s responds to its key" % action, _held(action) == before,
			("(no phantom press)" if before else ""))

	# The sweep presses keys that have side effects — ESC pauses the tree and V
	# swaps the camera. Left in place, every check below runs against a frozen
	# scene and reports the pause as a broken controller.
	await _reset_state()

	# Confirm the action is genuinely pressed *while* the key is held. This is the
	# check that fails when the action exists but has no events bound to it.
	_section("actions report pressed while held")
	for action: String in ["thrust_forward", "thrust_back", "fire", "boost", "dampeners", "scoreboard"]:
		await _press(action, KEY_BINDINGS[action])
		var pressed := _held(action)
		var strength := Input.get_action_strength(action)
		# Also ask the low-level question, so a failure tells us whether the key
		# reached the engine at all or whether only the action mapping broke.
		var raw := Input.is_physical_key_pressed(KEY_BINDINGS[action])
		await _release(action, KEY_BINDINGS[action])
		_check("%s is pressed while the key is down" % action, pressed,
			("(strength %.2f, raw_key %s)" % [strength, str(raw)]))

	# The underlying reason, stated directly so a failure is self-explanatory.
	# Counts only *keyboard* events: "has at least one event" is not enough,
	# because a gamepad axis counts too. That is exactly how the original bug
	# slipped through — every action looked populated while no key was bound.
	_section("every action has a keyboard binding")
	var no_key := []
	for action: String in KEY_BINDINGS:
		var keys := 0
		for e: InputEvent in InputMap.action_get_events(action):
			if e is InputEventKey:
				keys += 1
		if keys == 0:
			no_key.append(action)
	_check("every action has at least one key event", no_key.size() == 0,
		("(%d with no keyboard binding)" % no_key.size() if no_key.size() > 0 else ""))
	for action: String in no_key:
		print("      no keyboard binding: %s" % action)

	# ------------------------------------------------------------- player ---
	_section("player ship responds to input")
	var p: SpaceShip = _main.player

	# Mouse capture cannot be honoured in --headless: there is no real display,
	# so the DisplayServer reports the mouse as visible no matter what we ask.
	# Assert the ship's own intent instead, and note why the mode is unreliable.
	_check("player ship requests mouse capture",
		bool(p.get("_mouse_captured")), "(headless forces mode %d)" % Input.mouse_mode)

	var start := p.global_position
	await _press("thrust_forward", KEY_W, 40)
	var moved := p.global_position.distance_to(start)
	var speed := p.velocity.length()
	await _release("thrust_forward", KEY_W)
	_check("W moves the ship", moved > 10.0 and speed > 15.0,
		"(%.0f m, %.0f m/s)" % [moved, speed])

	await _press("dampeners", KEY_X, 90)
	await _release("dampeners", KEY_X)
	_check("X dampeners arrest drift", p.velocity.length() < 6.0,
		("(%.1f m/s)" % p.velocity.length()))

	# Mouse look. Held capture cannot be granted headless, so the ship's handler is
	# fed a real InputEventMouseMotion directly — the same call an OS event makes.
	var yaw_before: float = p.yaw
	await _move_mouse(p, Vector2(220, 0))
	var yaw_after: float = p.yaw
	_check("mouse motion yaws the ship", absf(yaw_after - yaw_before) > 0.02,
		("(%.3f -> %.3f rad)" % [yaw_before, yaw_after]))

	var pitch_before: float = p.pitch
	await _move_mouse(p, Vector2(0, 150))
	_check("mouse motion pitches the ship", absf(p.pitch - pitch_before) > 0.01,
		("(%.3f -> %.3f rad)" % [pitch_before, p.pitch]))

	var roll_before: float = p.roll
	await _press("roll_right", KEY_E, 30)
	await _release("roll_right", KEY_E)
	_check("E rolls the hull", absf(p.roll - roll_before) > 0.05,
		"(%.3f -> %.3f rad)" % [roll_before, p.roll])

	var shots_before: int = GameMatch.pilots.YOU.shots
	await _press("fire", KEY_SPACE, 12)
	await _release("fire", KEY_SPACE)
	_check("SPACE fires the autocannon",
		GameMatch.pilots.YOU.shots > shots_before,
		"(shots %d -> %d)" % [shots_before, GameMatch.pilots.YOU.shots])

	await _press("boost", KEY_SHIFT, 4)
	await _press("thrust_forward", KEY_W, 70)
	var boosted := p.boosting
	var boost_speed := p.velocity.length()
	await _release("thrust_forward", KEY_W)
	await _release("boost", KEY_SHIFT)
	_check("SHIFT engages the afterburner", boosted, "(%.0f m/s)" % boost_speed)
	await _inverted_controls()

	# ------------------------------------------------------------- pause ----
	# Pause is handled in `_unhandled_input`, so it needs real frames to land.
	_section("pause and restart")
	await _press("pause", KEY_ESCAPE)
	await _step(6)
	var paused_ok: bool = _main.paused
	_check("ESC pauses", paused_ok, "(paused=%s)" % str(paused_ok))

	if paused_ok:
		await _release("pause", KEY_ESCAPE)
		await _step(2)
		# Exercise the actual release-and-second-press path while the tree is paused.
		await _tap("pause", KEY_ESCAPE)
		await _step(6)
		_check("second ESC resumes through real input", not _main.paused, "(paused=%s)" % str(_main.paused))
		_check("physics resumes with the tree",
			get_tree().paused == false, "(tree paused=%s)" % str(get_tree().paused))
	else:
		print("      (skipped resume check: not paused)")

	print("")
	print("--- %d checks, %d failures ---" % [_checks, _failures])
	_main._show_title()
	_main.queue_free()
	await get_tree().process_frame
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	get_tree().quit(1 if _failures > 0 else 0)


func _inverted_controls() -> void:
	_section("physical roll keys and mouse inversion")
	var p: SpaceShip = _main.player
	var arena_mode: int = _main.arena.process_mode
	var main_processing := _main.is_processing()
	var collision_mask := p.collision_mask
	var active_bots: Array[SpaceShip] = []
	# Isolate the controls from gravity and combat while keeping the player's
	# normal physics/input callback active. This fixture still uses real keys.
	_main.arena.process_mode = Node.PROCESS_MODE_DISABLED
	_main.set_process(false)
	p.collision_mask = 0
	for row: Dictionary in _main._roster:
		var ship := row.ship as SpaceShip
		if ship != p and ship.is_physics_processing():
			active_bots.append(ship)
			ship.set_physics_process(false)
	for bolt: Node in get_tree().get_nodes_in_group("bolts"):
		bolt.queue_free()
	await _step(2)
	for inverted: bool in [false, true]:
		GameSettings.set_value("invert_roll", inverted, false)
		for pair: Array in [["roll_left", KEY_Q, -1.0], ["roll_right", KEY_E, 1.0]]:
			_control_pose(p)
			await _press(pair[0], pair[1], 24)
			var turned: float = p.roll
			var hull_roll := p.global_basis.get_rotation_quaternion().z
			await _release(pair[0], pair[1])
			var expected: float = pair[2] * (-1.0 if inverted else 1.0)
			_check("physical %s reverses only when roll inversion is %s" % ["Q" if pair[1] == KEY_Q else "E", inverted], turned * expected > 0.5 and hull_roll * expected > 0.2 and _rigid(p.global_basis))
		_control_pose(p)
		_key_down(KEY_Q)
		_key_down(KEY_E)
		Input.flush_buffered_events()
		await _step(24)
		_check("physical Q and E cancel with roll inversion %s" % inverted, absf(p.roll) < 0.00001 and p.global_basis.x.dot(Vector3.RIGHT) > 0.9999)
		await _release("roll_left", KEY_Q)
		await _release("roll_right", KEY_E)
	# Changing the preference takes effect on a key already held down; it must
	# not require releasing/repressing the key or produce a phantom input.
	GameSettings.set_value("invert_roll", false, false)
	_control_pose(p)
	await _press("roll_right", KEY_E, 18)
	var first: float = p.roll
	var before_switch := p.global_basis
	GameSettings.set_value("invert_roll", true, false)
	await _step(18)
	var reversed: float = wrapf(p.roll - first, -PI, PI)
	var hull_reversed := (before_switch.inverse() * p.global_basis).get_rotation_quaternion().z
	await _release("roll_right", KEY_E)
	_check("a held physical E responds immediately to changed roll inversion", first > 0.5 and reversed < -0.5 and hull_reversed < -0.2)
	for invert_pitch: bool in [false, true]:
		for invert_roll: bool in [false, true]:
			GameSettings.set_value("invert_y", invert_pitch, false)
			GameSettings.set_value("invert_roll", invert_roll, false)
			for mouse_direction: int in [-1, 1]:
				_control_pose(p)
				await _move_mouse(p, Vector2(0, mouse_direction * 120.0))
				var expected_pitch := float(mouse_direction) * (1.0 if invert_pitch else -1.0)
				_check("mouse pitch %s / invert Y %s / invert roll %s" % [mouse_direction, invert_pitch, invert_roll], p.pitch * expected_pitch > 0.2 and p.forward().y * expected_pitch > 0.2 and absf(p.yaw) < 0.00001 and absf(p.roll) < 0.00001)
			_control_pose(p)
			_key_down(KEY_E)
			Input.flush_buffered_events()
			await _move_mouse(p, Vector2(0, 120))
			await _step(18)
			var expected_pitch := 1.0 if invert_pitch else -1.0
			var expected_roll := -1.0 if invert_roll else 1.0
			_check("mixed physical E and mouse input keeps inversions independent %s/%s" % [invert_pitch, invert_roll], p.pitch * expected_pitch > 0.2 and p.forward().y * expected_pitch > 0.2 and p.roll * expected_roll > 0.5 and p.global_basis.get_rotation_quaternion().z * expected_roll > 0.2 and _rigid(p.global_basis))
			await _release("roll_right", KEY_E)
	GameSettings.set_value("invert_y", false, false)
	GameSettings.set_value("invert_roll", false, false)
	_control_pose(p)
	p.collision_mask = collision_mask
	_main.arena.process_mode = arena_mode
	_main.set_process(main_processing)
	for ship: SpaceShip in active_bots:
		if is_instance_valid(ship):
			ship.set_physics_process(true)


func _control_pose(ship: SpaceShip) -> void:
	ship.respawn_at(Vector3(0, 450, 0), Vector3(0, 450, -100))
	ship.collision_mask = 0
	ship.capture_mouse(true)


func _key_down(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)


func _rigid(value: Basis) -> bool:
	return value.is_finite() and absf(value.determinant() - 1.0) < 0.00001


## Undoes anything the binding sweep changed: resume the tree, restore the chase
## camera and re-capture the mouse.
func _reset_state() -> void:
	if _main.paused:
		_main._set_paused(false)
	if _main.rig != null and not _main.rig.mode_chase:
		_main.rig.mode_chase = true
	var p: SpaceShip = _main.player
	if p != null and is_instance_valid(p) and not bool(p.get("_mouse_captured")):
		p.capture_mouse(true)
	await _step(4)


func _step(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _release_for(keycode: Key) -> InputEventKey:
	var up := InputEventKey.new()
	up.physical_keycode = keycode
	up.keycode = keycode
	up.pressed = false
	return up


## Feeds a real mouse-motion delta to the ship.
##
## Headless cannot grant captured mouse mode, and PlayerShip only reads mouse
## motion while captured — so the event is delivered straight to the handler the
## windowed game would call. Everything downstream (angle accumulation, easing)
## is the real code path.
func _move_mouse(ship: Node, relative: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = relative
	ev.screen_relative = relative
	ship._unhandled_input(ev)
	await _step(6)
