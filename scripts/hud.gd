extends Control
## All 2D readouts: reticle, target brackets, radar, hull/shield/boost bars,
## kill feed, score, damage indicators and the pause / match-over overlays.
##
## Instruments share the bundled multilingual font and shape each line using
## the active language, including mixed Arabic text and pilot callsigns.

const RADAR_RANGE := 900.0
const RETICLE_COLOR := Color("aec6ca")
const FRIENDLY_COLOR := Color("7eaab4")
const HOSTILE_COLOR := Color("d1796b")
const WARN_COLOR := Color("cda56d")
const TEXT_COLOR := Color("d2dadd")
const MUTED_COLOR := Color("819095")
const PANEL_COLOR := Color(0.025, 0.035, 0.043, 0.76)
const RULE_COLOR := Color(0.48, 0.57, 0.60, 0.30)

var player: SpaceShip = null
var camera: Camera3D = null
var rig: CameraRig = null


## Enemy the player has explicitly locked (Tab). Cleared when it dies or leaves
## the arena, otherwise the reticle falls back to auto-acquisition.
var locked: SpaceShip = null

var _damage_flash := 0.0
var _zone_flash := 0.0
var _hit_markers: Array[Dictionary] = []
var _time := 0.0
var _font: Font = null
var _text_cache: Dictionary = {}
var _text_locale := ""
var _hint_alpha := 1.0
var _hit_flash := 0.0
var _hit_sound_left := 0.0
var _critical_sound_left := 0.0
var _solution_target: SpaceShip
var _solution_status := ""
var _solution_aim := Vector3.ZERO
var _rendered_ship_poses: Dictionary = {}
var _drawing_contacts := false
var _scoreboard_page := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = L10n.font
	GameMatch.kill_logged.connect(_on_kill_logged)


func setup(player_ship: SpaceShip, camera_rig: CameraRig) -> void:
	player = player_ship
	rig = camera_rig
	camera = camera_rig.camera
	locked = null
	_time = 0.0
	_hint_alpha = 1.0
	_damage_flash = 0.0
	_hit_flash = 0.0
	_hit_sound_left = 0.0
	_critical_sound_left = 0.0
	_solution_target = null
	_solution_status = ""
	_hit_markers.clear()
	_scoreboard_page = 0
	if player != null:
		player.took_damage.connect(_on_player_damaged)


func _process(delta: float) -> void:
	var scoreboard_open := is_visible_in_tree() and Input.is_action_pressed("scoreboard")
	if not scoreboard_open:
		_scoreboard_page = 0
	_time += delta
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.2)
	_hit_flash = maxf(0.0, _hit_flash - delta * 4.0)
	_hit_sound_left = maxf(0.0, _hit_sound_left - delta)
	_critical_sound_left = maxf(0.0, _critical_sound_left - delta)
	if is_instance_valid(player) and not player.dead and player.hull <= player.hull_max * 0.25 and _critical_sound_left <= 0.0:
		Sfx.play_local("critical", -14.0)
		_critical_sound_left = 3.0
	_zone_flash = maxf(0.0, _zone_flash - delta * 0.8)
	_hint_alpha = move_toward(_hint_alpha, 0.0 if _time > 18.0 else 1.0, delta * 0.12)
	for m: Dictionary in _hit_markers:
		m.life -= delta
	while not _hit_markers.is_empty() and _hit_markers[0].life <= 0.0:
		_hit_markers.pop_front()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not Input.is_action_pressed("scoreboard"):
		return
	var layout := _scoreboard_layout()
	if layout.pages <= 1:
		return
	var movement := 0
	var destination := -1
	if event is InputEventKey and event.pressed:
		match event.physical_keycode if event.physical_keycode != 0 else event.keycode:
			KEY_PAGEUP: movement = -1
			KEY_PAGEDOWN: movement = 1
			KEY_HOME: destination = 0
			KEY_END: destination = layout.pages - 1
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			movement = -1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			movement = 1
	elif event is InputEventJoypadButton and event.pressed:
		# Up/down on the pad and all four keyboard arrows are flight controls.
		# The unbound horizontal D-pad pair can page without changing thrust.
		if event.button_index == JOY_BUTTON_DPAD_LEFT:
			movement = -1
		elif event.button_index == JOY_BUTTON_DPAD_RIGHT:
			movement = 1
	if movement == 0 and destination < 0:
		return
	_scoreboard_page = clampi(destination if destination >= 0 else _scoreboard_page + movement, 0, layout.pages - 1)
	get_viewport().set_input_as_handled()
	queue_redraw()


func _on_kill_logged(_text: String, _color: Color) -> void:
	queue_redraw()


func _on_player_damaged(amount: float, _pos: Vector3, _attacker: Node) -> void:
	_damage_flash = minf(1.0, _damage_flash + amount * 0.02)
	if rig != null:
		rig.add_shake(minf(0.9, amount * 0.02))


func register_hit() -> void:
	_hit_flash = 1.0
	if _hit_sound_left <= 0.0:
		Sfx.play_local("hit", -23.0)
		_hit_sound_left = 0.09


func register_hit_kill() -> void:
	Sfx.play_local("kill", -12.0)
	_hit_markers.push_front({"life": 0.9})
	_hit_markers = _hit_markers.slice(0, 6)


# ================================================================ drawing ==

func _draw() -> void:
	_rendered_ship_poses.clear()
	_drawing_contacts = true
	if _font != L10n.font or _text_locale != L10n.locale:
		_font = L10n.font
		_text_locale = L10n.locale
		_text_cache.clear()
	_draw_vignette()
	if player == null or camera == null:
		_draw_waiting()
		_drawing_contacts = false
		return

	_draw_zone_warning()
	_draw_reticle()
	_draw_target_brackets()
	_draw_damage_direction()
	_draw_hull_block()
	_draw_radar()
	_draw_weapon_block()
	_draw_target_panel()
	_draw_kill_feed()
	_draw_score()
	_draw_help()
	_draw_hit_markers()

	if player.dead:
		_draw_death_overlay()
	if Input.is_action_pressed("scoreboard"):
		_draw_scoreboard()
	_drawing_contacts = false


## Query only contacts we actually project, once per draw pass. Physics target
## selection and interception continue to use the real simulation transforms.
func _rendered_ship_pose(ship: SpaceShip) -> Transform3D:
	var identity := ship.get_instance_id()
	if _drawing_contacts and _rendered_ship_poses.has(identity):
		return _rendered_ship_poses[identity]
	var pose := ship.get_global_transform_interpolated()
	if _drawing_contacts:
		_rendered_ship_poses[identity] = pose
	return pose


func _aim_view_pose() -> Transform3D:
	return rig.global_transform if is_instance_valid(rig) else camera.global_transform


func _text(pos: Vector2, s: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var line := _shaped_text(s, font_size, align, width)
	line.draw(get_canvas_item(), pos - Vector2(0, line.get_line_ascent()), color)


func _measure(s: String, font_size: int) -> float:
	return _shaped_text(s, font_size).get_line_width()


## TextLine keeps combining marks and Arabic joining intact when fitting a
## string. Bounded fields follow the locale's writing direction; instruments
## and numeric columns retain their physical positions.
func _shaped_text(s: String, font_size: int, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> TextLine:
	var key := "%s|%d|%d|%s|%s" % [L10n.locale, font_size, align, str(width), s]
	if _text_cache.has(key):
		return _text_cache[key]
	if _text_cache.size() >= 512:
		_text_cache.clear()
	var line := TextLine.new()
	line.direction = TextServer.DIRECTION_RTL if L10n.is_rtl() else TextServer.DIRECTION_LTR
	line.alignment = HORIZONTAL_ALIGNMENT_RIGHT if L10n.is_rtl() and align == HORIZONTAL_ALIGNMENT_LEFT and width >= 0.0 else align
	line.width = width
	line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_string(s, _font, font_size, L10n.locale)
	_text_cache[key] = line
	return line


func _bounded_text(pos: Vector2, s: String, font_size: int, color: Color, width: float,
		align := HORIZONTAL_ALIGNMENT_LEFT, minimum_size := 11) -> void:
	var fitted_size := font_size
	while fitted_size > minimum_size and _measure(s, fitted_size) > width:
		fitted_size -= 1
	_text(pos, s, fitted_size, color, align, width)


## Keep instruments at a readable pixel size using the canvas transform.
## Reading the render texture while drawing can create viewport feedback.
func _instrument_scale() -> float:
	# ViewportTexture metadata can itself be canvas-scaled. The root window
	# reports the actual target size without a render-texture feedback lookup.
	var window_size := Vector2(get_window().size)
	var screen_scale := minf(window_size.x / maxf(size.x, 1.0), window_size.y / maxf(size.y, 1.0))
	return maxf(1.0, 1.0 / maxf(screen_scale, 0.01))


func _instrument_at(origin: Vector2, factor: float) -> void:
	draw_set_transform(origin, 0.0, Vector2.ONE * factor)


func _instrument_end() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _panel(rect: Rect2) -> void:
	draw_rect(rect, PANEL_COLOR)
	draw_line(rect.position, rect.position + Vector2(rect.size.x, 0), RULE_COLOR, 1.0)


func _draw_vignette() -> void:
	if _damage_flash <= 0.001:
		return
	var a := _damage_flash * 0.42
	var steps := 5
	for i in steps:
		var t := float(i) / float(steps)
		var inset := t * size.y * 0.10
		draw_rect(Rect2(0, inset, size.x, 3), Color(1, 0.15, 0.1, a * (1.0 - t) * 0.9))
		draw_rect(Rect2(0, size.y - inset - 3, size.x, 3), Color(1, 0.15, 0.1, a * (1.0 - t) * 0.9))
		draw_rect(Rect2(inset, 0, 3, size.y), Color(1, 0.15, 0.1, a * (1.0 - t) * 0.9))
		draw_rect(Rect2(size.x - inset - 3, 0, 3, size.y), Color(1, 0.15, 0.1, a * (1.0 - t) * 0.9))


func _draw_waiting() -> void:
	_bounded_text(Vector2(size.x * 0.5 - 180, size.y * 0.5), L10n.text("LINKING..."), 20,
		Color(1, 1, 1, 0.5), 360, HORIZONTAL_ALIGNMENT_CENTER, 16)


# ---------------------------------------------------------------- reticle --

func _draw_reticle() -> void:
	var c := size * 0.5
	var col := FRIENDLY_COLOR if _aim_assist_active() else WARN_COLOR
	var factor := _instrument_scale()
	# The sight represents the cannons' angular dispersion. Speed does not
	# change their accuracy, so it must not inflate the sight.
	var spread_point := camera.global_position - camera.global_basis.z * 100.0 \
		+ camera.global_basis.x * tan(deg_to_rad(player.weapon_spread_deg)) * 100.0
	var spread := clampf(camera.unproject_position(spread_point).distance_to(c), 8.0, 22.0)

	# Main cross.
	draw_line(c + Vector2(-spread - 9, 0), c + Vector2(-spread, 0), col, 1.0)
	draw_line(c + Vector2(spread, 0), c + Vector2(spread + 9, 0), col, 1.0)
	draw_line(c + Vector2(0, -spread - 9), c + Vector2(0, -spread), col, 1.0)
	draw_line(c + Vector2(0, spread), c + Vector2(0, spread + 9), col, 1.0)

	# Centre pip + range ticks.
	draw_circle(c, 1.2, Color(col.r, col.g, col.b, 0.85))

	# Predictor pip: where to aim so bolts arrive at the current target.
	var lead := _lead_screen_point()
	if lead != Vector2.INF:
		# Keep the solution legible against a lit hull or a dense tracer stream.
		var radius := 8.0 * factor
		var outline := Color(0.01, 0.02, 0.025, 0.92)
		draw_arc(lead, radius, 0, TAU, 32, outline, 4.0 * factor, true)
		draw_arc(lead, radius, 0, TAU, 32, col, 1.8 * factor, true)
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			var inside := lead + direction * 11.0 * factor
			var outside := lead + direction * 17.0 * factor
			draw_line(inside, outside, outline, 4.0 * factor, true)
			draw_line(inside, outside, col, 1.8 * factor, true)
		draw_circle(lead, 2.7 * factor, outline, true, -1.0, true)
		draw_circle(lead, 1.5 * factor, col, true, -1.0, true)


## Assistance changes the instruments only after the weapon has accepted this
## same live contact. A stale, obstructed or out-of-range solution stays amber.
func _aim_assist_active() -> bool:
	if not is_instance_valid(player) or player.dead:
		return false
	var target := current_target()
	if not is_instance_valid(target) or target.dead or target.team == player.team:
		return false
	var assisted: Variant = player.get("aim_assist_target")
	return target == _solution_target and _solution_status == "FIRING SOLUTION" \
		and is_instance_valid(assisted) and assisted == target


func _lead_screen_point() -> Vector2:
	var t := current_target()
	if t == null or t != _solution_target or _solution_status != "FIRING SOLUTION":
		return Vector2.INF
	# Shift only the displayed solution's starting point to the rendered contact;
	# the cached intercept and all weapon/raycast calculations stay in physics.
	var display_aim := _solution_aim + _rendered_ship_pose(t).origin - t.global_position
	if camera.is_position_behind(display_aim):
		return Vector2.INF
	return camera.unproject_position(display_aim)


func _physics_process(_delta: float) -> void:
	_update_target_solution()


func _update_target_solution() -> void:
	_solution_target = null
	_solution_status = ""
	if is_instance_valid(player):
		player.set("preferred_aim_target", null)
	if not is_instance_valid(player) or player.dead or not is_instance_valid(camera):
		return
	var target := current_target()
	player.set("preferred_aim_target", target)
	if target == null or player.muzzle_points.is_empty():
		return
	_solution_target = target
	var muzzle: Node3D = player.muzzle_points[player._muzzle_index % player.muzzle_points.size()]
	var from := muzzle.global_position
	var relative_velocity := target.velocity - player.velocity * 0.2
	var flight := Gunnery.intercept_time(target.global_position - from, relative_velocity, player.bolt_speed)
	if not is_finite(flight) or flight <= 0.0 or flight >= GameConfig.BOLT_LIFETIME:
		_solution_status = "OUT OF RANGE"
		return
	_solution_aim = target.global_position + relative_velocity * flight
	# Match the next cannon's actual ballistic corridor, including inherited
	# momentum and friends that will cross it before the round arrives.
	var clear := Gunnery.has_clear_path(player, target, from, _solution_aim, flight)
	var aim_view := _aim_view_pose()
	if not clear:
		_solution_status = "LINE OF FIRE BLOCKED"
	elif aim_view.basis.z.dot(_solution_aim - aim_view.origin) > 0.0:
		_solution_status = "TURN TO TARGET"
	else:
		_solution_status = "FIRING SOLUTION"


## Locked contact if we have one, otherwise the hostile nearest the crosshair.
func current_target() -> SpaceShip:
	if not is_instance_valid(player) or not is_instance_valid(camera):
		return null
	if locked != null:
		if not is_instance_valid(locked) or locked.dead or locked.team == player.team:
			locked = null
		else:
			return locked

	var best: SpaceShip = null
	var best_score := -INF
	var aim_view := _aim_view_pose()
	var cam_basis := aim_view.basis
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if other == null or other.dead or other == player or other.team == player.team:
			continue
		var to := other.global_position - aim_view.origin
		var ang := rad_to_deg((-cam_basis.z).angle_to(to.normalized()))
		if ang > 55.0:
			continue
		var score := -absf(ang) - to.length() * 0.002
		if score > best_score:
			best_score = score
			best = other
	return best


## Tab: step through every living hostile, ordered by distance from the reticle.
func cycle_target() -> void:
	var contacts: Array[SpaceShip] = []
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if other == null or other == player or other.dead or other.team == player.team:
			continue
		contacts.append(other)
	if contacts.is_empty():
		locked = null
		return
	contacts.sort_custom(func(a: SpaceShip, b: SpaceShip) -> bool:
		return player.global_position.distance_squared_to(a.global_position) \
			< player.global_position.distance_squared_to(b.global_position)
	)
	var idx := contacts.find(locked)
	locked = contacts[(idx + 1) % contacts.size()]
	Sfx.play_local("lock", -17.0)
	if rig != null:
		rig.add_shake(0.12)


func _draw_target_brackets() -> void:
	var target := current_target()
	if target == null:
		return
	var factor := _instrument_scale()
	var label_size := roundi(12 * factor)
	var target_pose := _rendered_ship_pose(target)
	var behind := camera.is_position_behind(target_pose.origin)
	var point := Vector2.INF if behind else camera.unproject_position(target_pose.origin)
	var distance := player.global_position.distance_to(target.global_position)
	if behind or not Rect2(Vector2(24, 76), size - Vector2(48, 130)).has_point(point):
		var local := camera.global_basis.inverse() * (target_pose.origin - camera.global_position)
		var angle := atan2(-local.y, local.x)
		var direction := Vector2(cos(angle), sin(angle))
		point = size * 0.5 + direction * minf(size.x, size.y) * 0.34
		var wing := direction.orthogonal() * 4.0 * factor
		draw_line(point + direction * 7.0 * factor, point - direction * 3.0 * factor + wing, HOSTILE_COLOR, factor)
		draw_line(point + direction * 7.0 * factor, point - direction * 3.0 * factor - wing, HOSTILE_COLOR, factor)
		_text(point + Vector2(12, 4) * factor, L10n.text("%d m") % int(distance), label_size, HOSTILE_COLOR)
		return

	# Project the solid model bounds, including the prow and radiator banks.
	# The gameplay collider is deliberately simpler than the visible hull.
	var bounds: AABB = target.model.contact_bounds
	var radius := 12.0 * factor
	var maximum_radius := minf(size.x, size.y) * 0.40
	var model_pose := target_pose * target.model.transform
	for i in 8:
		var corner := bounds.position + bounds.size * Vector3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1))
		var world_corner := model_pose * corner
		if camera.is_position_behind(world_corner):
			# A hull crossing the near plane would produce unbounded projection.
			radius = maximum_radius
			break
		radius = maxf(radius, point.distance_to(camera.unproject_position(world_corner)) + 4.0 * factor)
	radius = minf(radius, maximum_radius)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var origin := point + corner * radius
		draw_line(origin, origin - corner * Vector2(7, 0) * factor, HOSTILE_COLOR, factor)
		draw_line(origin, origin - corner * Vector2(0, 7) * factor, HOSTILE_COLOR, factor)
	var caption := L10n.pilot_name(target.display_name)
	_bounded_text(point + Vector2(-60 * factor, -radius - 7 * factor), caption, label_size,
		HOSTILE_COLOR, 120 * factor, HORIZONTAL_ALIGNMENT_CENTER, roundi(11 * factor))
	var range_label := L10n.text("%d m") % int(distance)
	var range_position := point + Vector2(radius + 8 * factor, 4 * factor)
	var lead := _lead_screen_point()
	if lead != Vector2.INF:
		var label_bounds := Rect2(range_position - Vector2(0, label_size),
			Vector2(_measure(range_label, label_size), label_size * 1.4))
		var marker_bounds := Rect2(lead - Vector2.ONE * 19 * factor, Vector2.ONE * 38 * factor)
		if label_bounds.intersects(marker_bounds):
			range_position.y = point.y + radius + 25 * factor
	_text(range_position, range_label, label_size, MUTED_COLOR)
	var bar_width := radius * 2.0
	for i in 2:
		var ratio := target.shield / maxf(target.shield_max, 1.0) if i == 0 else target.hull / maxf(target.hull_max, 1.0)
		var pos := point + Vector2(-radius, radius + (6 + i * 4) * factor)
		draw_line(pos, pos + Vector2(bar_width, 0), RULE_COLOR, factor)
		draw_line(pos, pos + Vector2(bar_width * clampf(ratio, 0.0, 1.0), 0), FRIENDLY_COLOR if i == 0 else HOSTILE_COLOR, factor)


# ------------------------------------------------------------- ship systems --

func _draw_hull_block() -> void:
	var factor := _instrument_scale()
	_instrument_at(Vector2(18 * factor, size.y - 136 * factor), factor)
	var origin := Vector2.ZERO
	_panel(Rect2(origin, Vector2(254, 118)))
	_bounded_text(origin + Vector2(10, 18), L10n.text("AZ-00  /  COMBAT CORVETTE"), 12, MUTED_COLOR, 234)
	_text(origin + Vector2(10, 44), "%03d" % int(player.speed), 22, TEXT_COLOR)
	_bounded_text(origin + Vector2(59, 43), L10n.text("m/s"), 12, MUTED_COLOR, 38)
	var state := "AFTERBURNER" if player.boosting else ("DAMPENERS" if Input.is_action_pressed("dampeners") else "INERTIAL FLIGHT")
	_bounded_text(origin + Vector2(108, 42), L10n.text(state), 12,
		WARN_COLOR if player.boosting else FRIENDLY_COLOR, 136)
	var label_width := 43.0
	for label: String in ["SHIELD", "HULL", "DRIVE"]:
		label_width = maxf(label_width, _measure(L10n.text(label), 12))
	label_width = minf(label_width, 82.0)
	var bar_x := 18.0 + label_width
	# Shield is the outer defence; hull follows it, then propulsion reserve.
	_bar(Rect2(origin + Vector2(bar_x, 58), Vector2(206 - bar_x, 7)), player.shield / maxf(player.shield_max, 1.0),
		FRIENDLY_COLOR, RULE_COLOR, "SHIELD", "%d" % int(ceil(player.shield)), origin.x + 10, origin.y + 56)
	var hull_ratio := player.hull / maxf(player.hull_max, 1.0)
	_bar(Rect2(origin + Vector2(bar_x, 78), Vector2(206 - bar_x, 7)), hull_ratio,
		HOSTILE_COLOR if hull_ratio <= 0.25 else TEXT_COLOR, RULE_COLOR, "HULL", "%d" % int(ceil(player.hull)), origin.x + 10, origin.y + 76)
	var reserve := player.boost / maxf(player.boost_max, 1.0)
	_bar(Rect2(origin + Vector2(bar_x, 98), Vector2(206 - bar_x, 7)), reserve,
		WARN_COLOR if player.boosting else MUTED_COLOR, RULE_COLOR, "DRIVE", "%d" % int(reserve * 100.0), origin.x + 10, origin.y + 96)
	_instrument_end()


func _bar(rect: Rect2, ratio: float, fill: Color, back: Color, label: String, value: String, label_x: float, label_y: float) -> void:
	draw_rect(rect, Color(0.2, 0.25, 0.28, 0.28))
	var amount := clampf(ratio, 0.0, 1.0)
	if amount > 0.0:
		draw_rect(Rect2(rect.position, Vector2(rect.size.x * amount, rect.size.y)), Color(fill.r, fill.g, fill.b, 0.72))
	for i in 5:
		var x := rect.position.x + rect.size.x * float(i) / 5.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), back, 1.0)
	_bounded_text(Vector2(label_x, label_y + rect.size.y), L10n.text(label), 12,
		MUTED_COLOR, rect.position.x - label_x - 8)
	_text(Vector2(rect.end.x + 8, label_y + rect.size.y), value, 12, TEXT_COLOR,
		HORIZONTAL_ALIGNMENT_CENTER, 30)


func _draw_weapon_block() -> void:
	var factor := _instrument_scale()
	_instrument_at(Vector2(size.x * 0.5 - 120 * factor, size.y - 67 * factor), factor)
	var origin := Vector2.ZERO
	_panel(Rect2(origin, Vector2(240, 49)))
	_bounded_text(origin + Vector2(10, 18), L10n.text("TWIN AUTOCANNON"), 12, TEXT_COLOR, 200)
	_bounded_text(origin + Vector2(10, 36), L10n.text("FIXED MOUNTS  /  %d m/s") % int(player.bolt_speed), 11, MUTED_COLOR, 220)
	var lamp := Color(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, 0.7) if player._fire_timer > 0.0 else Color(FRIENDLY_COLOR.r, FRIENDLY_COLOR.g, FRIENDLY_COLOR.b, 0.45)
	draw_rect(Rect2(origin + Vector2(218, 11), Vector2(4, 4)), lamp)
	draw_rect(Rect2(origin + Vector2(224, 11), Vector2(4, 4)), lamp)
	_instrument_end()


# ------------------------------------------------------------------ radar --

func _draw_radar() -> void:
	var factor := _instrument_scale()
	_instrument_at(Vector2(size.x - 102 * factor, size.y - 88 * factor), factor)
	var radius := 54.0
	var centre := Vector2.ZERO
	_panel(Rect2(centre - Vector2(88, 77), Vector2(176, 147)))
	_bounded_text(centre + Vector2(-78, -59), L10n.text("CONTACT SCOPE"), 11, MUTED_COLOR, 156)
	for ratio: float in [1.0, 0.66, 0.33]:
		draw_arc(centre, radius * ratio, 0, TAU, 48, RULE_COLOR, 1.0)
	draw_line(centre - Vector2(radius, 0), centre + Vector2(radius, 0), RULE_COLOR, 1.0)
	draw_line(centre - Vector2(0, radius), centre + Vector2(0, radius), RULE_COLOR, 1.0)
	# Ship axes: forward remains up through yaw, pitch and roll.
	var field := PackedVector2Array([centre])
	for i in 9:
		var angle := -PI * 0.5 - deg_to_rad(32.0) + deg_to_rad(64.0) * float(i) / 8.0
		field.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(field, Color(FRIENDLY_COLOR.r, FRIENDLY_COLOR.g, FRIENDLY_COLOR.b, 0.05))
	var selected := current_target()
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if other == null or other.dead or other == player:
			continue
		var local := player.global_basis.inverse() * (other.global_position - player.global_position)
		var point := centre + _radar_offset(other.global_position, radius)
		var color := FRIENDLY_COLOR if other.team == player.team else HOSTILE_COLOR
		# The small vertical stem carries elevation without hiding range.
		var stem := clampf(local.y / RADAR_RANGE, -0.18, 0.18) * radius
		draw_line(point, point - Vector2(0, stem), Color(color.r, color.g, color.b, 0.4), 1.0)
		if other.team == player.team:
			draw_circle(point, 2.0, color)
		else:
			var diamond := PackedVector2Array([point + Vector2(0, -3), point + Vector2(3, 0), point + Vector2(0, 3), point + Vector2(-3, 0), point + Vector2(0, -3)])
			draw_polyline(diamond, color, 1.0)
		if other == selected:
			draw_arc(point, 6.0, 0, TAU, 16, color, 1.0)
	draw_line(centre + Vector2(-3, 4), centre + Vector2(0, -4), TEXT_COLOR, 1.0)
	draw_line(centre + Vector2(0, -4), centre + Vector2(3, 4), TEXT_COLOR, 1.0)
	_bounded_text(centre + Vector2(-78, 64), L10n.text("900 m  /  SHIP AXES"), 11, MUTED_COLOR, 156)
	_instrument_end()


func _radar_offset(world_position: Vector3, radius := 92.0) -> Vector2:
	var local := player.global_basis.inverse() * (world_position - player.global_position)
	var flat := Vector2(local.x, local.z)
	return flat.normalized() * radius * 0.94 * pow(clampf(flat.length() / RADAR_RANGE, 0.0, 1.0), 0.62)


# ----------------------------------------------------------- target panel --

func _draw_target_panel() -> void:
	var target := current_target()
	var factor := _instrument_scale()
	_instrument_at(Vector2(size.x - 226 * factor, 90 * factor), factor)
	var origin := Vector2.ZERO
	_panel(Rect2(origin, Vector2(208, 142 if target != null else 66)))
	_bounded_text(origin + Vector2(10, 17), L10n.text("SELECTED CONTACT"), 11, MUTED_COLOR, 188)
	if target == null:
		_bounded_text(origin + Vector2(10, 37), L10n.text("NO CONTACT"), 12, TEXT_COLOR, 188)
		_bounded_text(origin + Vector2(10, 54), L10n.text("TAB  /  CYCLE TARGET"), 11, MUTED_COLOR, 188)
		_instrument_end()
		return
	var color := FRIENDLY_COLOR if target.team == player.team else HOSTILE_COLOR
	_bounded_text(origin + Vector2(10, 39), L10n.pilot_name(target.display_name), 14, TEXT_COLOR, 126, HORIZONTAL_ALIGNMENT_LEFT, 12)
	_bounded_text(origin + Vector2(142, 37), L10n.text("LOCK" if locked == target else "AUTO"), 11,
		WARN_COLOR if locked == target else MUTED_COLOR, 56)
	_bounded_text(origin + Vector2(10, 59), L10n.text("%s  /  %d m") % [L10n.text(GameConfig.team_name(target.team)),
		int(player.global_position.distance_to(target.global_position))], 12, color, 188)
	_bounded_text(origin + Vector2(10, 78), L10n.text("SHIELD  %d%%") % int(100.0 * target.shield / maxf(target.shield_max, 1.0)),
		11, FRIENDLY_COLOR, 92)
	_bounded_text(origin + Vector2(108, 78), L10n.text("HULL  %d%%") % int(100.0 * target.hull / maxf(target.hull_max, 1.0)),
		11, TEXT_COLOR, 90)
	_bounded_text(origin + Vector2(10, 96), L10n.text("VELOCITY  /  %d m/s") % int(target.speed), 12, MUTED_COLOR, 188)
	draw_line(origin + Vector2(10, 107), origin + Vector2(198, 107), RULE_COLOR, 1.0)
	if target == _solution_target:
		_bounded_text(origin + Vector2(10, 125), L10n.text(_solution_status), 11,
			FRIENDLY_COLOR if _solution_status == "FIRING SOLUTION" else WARN_COLOR, 188)
	_instrument_end()


# --------------------------------------------------------------- combat log --

func _draw_kill_feed() -> void:
	var entries := GameMatch.get_feed()
	if entries.is_empty():
		return
	var factor := _instrument_scale()
	var width := minf(280, size.x * 0.5 / factor - 198)
	_instrument_at(Vector2(18, 20) * factor, factor)
	var origin := Vector2.ZERO
	_panel(Rect2(origin, Vector2(width, 25 + entries.size() * 17)))
	_bounded_text(origin + Vector2(9, 16), L10n.text("COMBAT LOG"), 11, MUTED_COLOR, width - 18)
	var y := 34.0
	for entry: Dictionary in entries:
		var color: Color = entry.color.lerp(TEXT_COLOR, 0.45)
		color.a = clampf(entry.life / 1.5, 0.0, 1.0) * 0.85
		_bounded_text(origin + Vector2(9, y), _feed_text(entry), 12, color, width - 18)
		y += 17.0
	_instrument_end()


func _feed_text(entry: Dictionary) -> String:
	# The ledger retains English text and stable pilot IDs for tests and stats.
	# Translate structured causes and templates only when the HUD displays them.
	if not entry.has("victim"):
		return String(entry.get("text", ""))
	var victim := L10n.pilot_name(String(entry.victim))
	var killer := String(entry.get("killer", ""))
	if killer.is_empty():
		var cause := "COLLISION" if entry.get("cause", "") == "COLLISION" else "LOST TO HAZARD"
		return L10n.text("%s  /  %s") % [victim, L10n.text(cause)]
	return L10n.text("%s  >>  %s") % [L10n.pilot_name(killer), victim]


func _draw_score() -> void:
	var blue := int(GameMatch.scores.get(GameConfig.TEAM_BLUE, 0))
	var red := int(GameMatch.scores.get(GameConfig.TEAM_RED, 0))
	var factor := _instrument_scale()
	_instrument_at(Vector2(size.x * 0.5 - 174 * factor, 18 * factor), factor)
	var origin := Vector2.ZERO
	_panel(Rect2(origin, Vector2(348, 49)))
	_bounded_text(origin + Vector2(12, 18), L10n.text("AZURE"), 12, FRIENDLY_COLOR, 72)
	_text(origin + Vector2(90, 20), "%02d" % blue, 17, TEXT_COLOR)
	_text(origin + Vector2(235, 20), "%02d" % red, 17, TEXT_COLOR)
	_bounded_text(origin + Vector2(270, 18), L10n.text("CRIMSON"), 12, HOSTILE_COLOR, 66)
	var minutes := int(GameMatch.remaining) / 60
	var seconds := int(GameMatch.remaining) % 60
	_text(origin + Vector2(124, 20), "%02d:%02d" % [minutes, seconds], 16, WARN_COLOR if GameMatch.remaining <= 30 else TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER, 100)
	_bounded_text(origin + Vector2(12, 38), L10n.text("TEAM SKIRMISH  /  HIGHEST SCORE WINS"), 11,
		MUTED_COLOR, 324, HORIZONTAL_ALIGNMENT_CENTER)
	_instrument_end()


func _draw_help() -> void:
	if _hint_alpha <= 0.01 or not bool(GameSettings.get_value("show_hints")):
		return
	var lines := [
		"W/S thrust  ·  A/D strafe  ·  R/F vertical  ·  Q/E roll",
		"SHIFT burner  ·  SPACE fire  ·  X brake  ·  TAB target",
		"V camera  ·  M cursor  ·  ESC menu  ·  BACKSLASH status",
	]
	var factor := _instrument_scale()
	_instrument_at(Vector2(18 * factor, size.y - 205 * factor), factor)
	var origin := Vector2.ZERO
	var color := Color(MUTED_COLOR.r, MUTED_COLOR.g, MUTED_COLOR.b, _hint_alpha * 0.85)
	for i in lines.size():
		_bounded_text(origin + Vector2(0, i * 16), L10n.text(lines[i]), 12, color, size.x / factor - 36)
	_instrument_end()


# --------------------------------------------------------- damage & zones --

func _draw_damage_direction() -> void:
	if player.dead:
		return
	var age := float(Time.get_ticks_msec()) / 1000.0 - player.last_damage_time
	if age > 2.2:
		return
	var fade: float = clampf(1.0 - age / 2.2, 0.0, 1.0)
	# Damage stores the incoming direction; negate it to point to its source,
	# and use camera axes so a rolled hull still gives the right screen bearing.
	var local := camera.global_basis.inverse() * -player.last_damage_dir
	var ang := atan2(local.x, local.y)
	if Vector2(local.x, local.y).length_squared() < 0.0001:
		ang = 0.0 if local.z < 0.0 else PI
	var centre := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.30
	var pts := PackedVector2Array()
	for i in 17:
		var a: float = ang - deg_to_rad(20.0) + deg_to_rad(40.0) * float(i) / 16.0
		pts.append(centre + Vector2(sin(a), -cos(a)) * radius)
	draw_polyline(pts, Color(HOSTILE_COLOR.r, HOSTILE_COLOR.g, HOSTILE_COLOR.b, 0.7 * fade), 2.0)


func _draw_zone_warning() -> void:
	if player.dead:
		return
	var limit := GameConfig.ARENA_RADIUS - GameConfig.ARENA_MARGIN
	var d := player.global_position.length()
	if d <= limit:
		_zone_flash = maxf(_zone_flash - 0.02, 0.0)
		return
	_zone_flash = minf(1.0, _zone_flash + 0.08)
	var pulse := 0.6 + 0.4 * sin(_time * 7.0)
	var factor := _instrument_scale()
	var width := minf(660.0, size.x / factor - 40.0)
	_instrument_at(Vector2(size.x * 0.5 - width * factor * 0.5, 84 * factor), factor)
	_bounded_text(Vector2.ZERO, L10n.text("BOUNDARY ALERT  /  RETURN TO SECTOR"), 12,
		Color(WARN_COLOR.r, WARN_COLOR.g, WARN_COLOR.b, _zone_flash * pulse), width, HORIZONTAL_ALIGNMENT_CENTER)
	_instrument_end()


func _draw_hit_markers() -> void:
	var c := size * 0.5
	if _hit_flash > 0.0:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			draw_line(c + corner * 11, c + corner * 18, Color(0.9, 1, 1, _hit_flash), 1.8)
	for m: Dictionary in _hit_markers:
		var a: float = clampf(m.life / 0.9, 0.0, 1.0)
		var col := Color(1.0, 0.85, 0.4, a)
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var o := c + corner * 26.0
			draw_line(o, o - corner * Vector2(8, 0), col, 2.0)
			draw_line(o, o - corner * Vector2(0, 8), col, 2.0)


# --------------------------------------------------------------- overlays --

func _draw_death_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.035, 0.04, 0.32))
	var factor := _instrument_scale()
	var width := minf(700.0, size.x / factor - 40.0)
	_instrument_at(Vector2(size.x * 0.5 - width * factor * 0.5, size.y * 0.42), factor)
	_bounded_text(Vector2.ZERO, L10n.text("VESSEL LOST"), 28, HOSTILE_COLOR,
		width, HORIZONTAL_ALIGNMENT_CENTER, 22)
	var left: float = float(player.get_meta("respawn_in", 0.0))
	_bounded_text(Vector2(0, 40), L10n.text("Replacement vessel available in %.1f s") % maxf(left, 0.0), 18,
		Color(1, 1, 1, 0.9), width, HORIZONTAL_ALIGNMENT_CENTER, 14)
	_instrument_end()


## Page capacity follows the real window size, while the text keeps its pixel
## size. Reserving both team headings also fits pages spanning the team break.
func _scoreboard_layout() -> Dictionary:
	var rows := GameMatch.standings()
	var crowded := rows.size() > 8
	var row_height := 23.0 if crowded else 30.0
	var team_height := 23.0 if crowded else 25.0
	var font_size := 14 if crowded else 16
	# Arabic's actual shaped line is taller than Latin at the same pixel size.
	# Give translated pilot/team lines their real spacing rather than shrinking.
	var pilot_line := _shaped_text(L10n.pilot_name("YOU"), font_size)
	row_height = maxf(row_height, pilot_line.get_size().y + 3.0)
	for team: int in [GameConfig.TEAM_BLUE, GameConfig.TEAM_RED]:
		var team_line := _shaped_text(L10n.text(GameConfig.team_name(team)), 11)
		team_height = maxf(team_height, team_line.get_line_descent() + pilot_line.get_line_ascent() + 3.0)
	var navigation_line := _shaped_text(L10n.text("PAGE UP / DOWN · WHEEL · D-PAD LEFT / RIGHT"), 11)
	var navigation_spacing := maxf(23.0, navigation_line.get_size().y + 3.0)
	var footer_height := maxf(40.0, navigation_line.get_size().y + 22.0)
	var factor := _instrument_scale()
	var available := size / factor
	var teams: Dictionary = {}
	for row: Dictionary in rows:
		teams[row.team] = true
	var capacity := maxi(1, floori((available.y - 32.0 - 103.0 - teams.size() * team_height - footer_height) / row_height))
	capacity = mini(capacity, 16)
	var pages := maxi(1, ceili(float(rows.size()) / capacity))
	_scoreboard_page = clampi(_scoreboard_page, 0, pages - 1)
	var page_rows := rows.slice(_scoreboard_page * capacity, (_scoreboard_page + 1) * capacity)
	var height := maxf(408.0, 103.0 + mini(rows.size(), capacity) * row_height + teams.size() * team_height + footer_height)
	return {"rows": page_rows, "pages": pages, "page": _scoreboard_page, "capacity": capacity,
		"row_height": row_height, "team_height": team_height, "font_size": font_size,
		"factor": factor, "height": height, "navigation_spacing": navigation_spacing,
		"origin": size * 0.5 - Vector2(320, height * 0.5) * factor}


func _draw_scoreboard() -> void:
	var layout := _scoreboard_layout()
	var height: float = layout.height
	var font_size: int = layout.font_size
	_instrument_at(layout.origin, layout.factor)
	var origin := Vector2.ZERO
	draw_rect(Rect2(origin, Vector2(640, height)), Color(0.025, 0.035, 0.043, 0.95))
	draw_line(origin, origin + Vector2(640, 0), RULE_COLOR, 1)
	_bounded_text(origin + Vector2(24, 34), L10n.text("SQUADRON STATUS"), 16, TEXT_COLOR,
		380 if layout.pages > 1 else 592, HORIZONTAL_ALIGNMENT_LEFT, 14)
	if layout.pages > 1:
		_bounded_text(origin + Vector2(410, 34), L10n.text("PAGE %d / %d") % [layout.page + 1, layout.pages],
			12, TEXT_COLOR, 206, HORIZONTAL_ALIGNMENT_CENTER, 12)
	_bounded_text(origin + Vector2(24, 67), L10n.text("PILOT"), 12, Color(0.6, 0.75, 0.82), 264)
	_bounded_text(origin + Vector2(300, 67), L10n.text("KILLS"), 12, Color(0.6, 0.75, 0.82), 120, HORIZONTAL_ALIGNMENT_CENTER)
	_bounded_text(origin + Vector2(426, 67), L10n.text("DEATHS"), 12, Color(0.6, 0.75, 0.82), 84, HORIZONTAL_ALIGNMENT_CENTER)
	_bounded_text(origin + Vector2(518, 67), L10n.text("DAMAGE"), 12, Color(0.6, 0.75, 0.82), 98, HORIZONTAL_ALIGNMENT_CENTER)
	var y := 103.0
	var last_team := -1
	for row: Dictionary in layout.rows:
		if row.team != last_team:
			last_team = row.team
			_bounded_text(origin + Vector2(24, y), L10n.text(GameConfig.team_name(row.team)), 11,
				FRIENDLY_COLOR if row.team == player.team else HOSTILE_COLOR, 264)
			y += layout.team_height
		var tint := Color.WHITE if row.name == "YOU" else Color(0.68, 0.78, 0.88)
		_bounded_text(origin + Vector2(24, y), L10n.pilot_name(String(row.name)), font_size, tint, 264, HORIZONTAL_ALIGNMENT_LEFT, 13)
		_text(origin + Vector2(300, y), str(row.kills), font_size, tint, HORIZONTAL_ALIGNMENT_CENTER, 120)
		_text(origin + Vector2(426, y), str(row.deaths), font_size, tint, HORIZONTAL_ALIGNMENT_CENTER, 84)
		_bounded_text(origin + Vector2(518, y), "%.0f" % row.damage, font_size, tint, 98, HORIZONTAL_ALIGNMENT_CENTER, 13)
		y += layout.row_height
	if layout.pages > 1:
		_bounded_text(origin + Vector2(24, height - 19 - layout.navigation_spacing), L10n.text("PAGE UP / DOWN · WHEEL · D-PAD LEFT / RIGHT"),
			11, MUTED_COLOR, 592, HORIZONTAL_ALIGNMENT_CENTER, 11)
	_bounded_text(origin + Vector2(24, height - 19), L10n.text("COMBAT CONTINUES  /  RELEASE BACKSLASH TO CLOSE"),
		11, Color(0.6, 0.75, 0.82), 592)
	_instrument_end()
