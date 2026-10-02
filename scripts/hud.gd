extends Control
## All 2D readouts: reticle, target brackets, radar, hull/shield/boost bars,
## kill feed, score, damage indicators and the pause / match-over overlays.
##
## Everything is drawn in `_draw()` so there is no theme or asset dependency and
## the whole HUD is a single node.

const RADAR_RANGE := 900.0
const RETICLE_COLOR := Color(0.55, 0.95, 0.85)
const FRIENDLY_COLOR := Color(0.35, 0.72, 1.0)
const HOSTILE_COLOR := Color(1.0, 0.38, 0.32)
const WARN_COLOR := Color(1.0, 0.78, 0.25)

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
var _hint_alpha := 1.0
var _hit_flash := 0.0
var _hit_sound_left := 0.0
var _critical_sound_left := 0.0
var _solution_target: SpaceShip
var _solution_status := ""
var _solution_aim := Vector3.ZERO


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
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
	if player != null:
		player.took_damage.connect(_on_player_damaged)


func _process(delta: float) -> void:
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
	_draw_vignette()
	if player == null or camera == null:
		_draw_waiting()
		return

	_draw_zone_warning()
	_draw_reticle()
	_draw_target_brackets()
	_draw_damage_direction()
	_draw_hull_block()
	_draw_radar()
	_draw_target_panel()
	_draw_kill_feed()
	_draw_score()
	_draw_help()
	_draw_hit_markers()

	if player.dead:
		_draw_death_overlay()
	if Input.is_action_pressed("scoreboard"):
		_draw_scoreboard()


func _text(pos: Vector2, s: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	draw_string(_font, pos, s, align, width, font_size, color)


func _measure(s: String, font_size: int) -> float:
	return _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


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
	_text(Vector2(size.x * 0.5 - 60, size.y * 0.5), "LINKING...", 20, Color(1, 1, 1, 0.5))


# ---------------------------------------------------------------- reticle --

func _draw_reticle() -> void:
	var c := size * 0.5
	var col := RETICLE_COLOR
	var speed_t: float = clampf(player.speed / GameConfig.SPEED_BOOST, 0.0, 1.0)
	var spread: float = lerpf(14.0, 46.0, speed_t)

	# Main cross.
	draw_line(c + Vector2(-spread - 16, 0), c + Vector2(-spread, 0), col, 1.6)
	draw_line(c + Vector2(spread, 0), c + Vector2(spread + 16, 0), col, 1.6)
	draw_line(c + Vector2(0, -spread - 16), c + Vector2(0, -spread), col, 1.6)
	draw_line(c + Vector2(0, spread), c + Vector2(0, spread + 16), col, 1.6)

	# Centre pip + range ticks.
	draw_circle(c, 2.0, Color(col.r, col.g, col.b, 0.85))
	for i in 4:
		var ang := TAU * float(i) / 4.0 + PI * 0.25
		var d := Vector2(cos(ang), sin(ang)) * (spread + 10.0)
		draw_line(c + d, c + d - Vector2(cos(ang), sin(ang)) * 6.0, Color(col.r, col.g, col.b, 0.5), 1.4)

	# Predictor pip: where to aim so bolts arrive at the current target.
	var lead := _lead_screen_point()
	if lead != Vector2.INF:
		draw_arc(lead, 5.0, 0, TAU, 12, Color(1.0, 0.7, 0.25, 0.9), 1.6)
		draw_line(lead + Vector2(-9, 0), lead + Vector2(-4, 0), Color(1.0, 0.7, 0.25, 0.7), 1.2)
		draw_line(lead + Vector2(4, 0), lead + Vector2(9, 0), Color(1.0, 0.7, 0.25, 0.7), 1.2)


func _lead_screen_point() -> Vector2:
	var t := current_target()
	if t == null or t != _solution_target or _solution_status != "FIRING SOLUTION":
		return Vector2.INF
	if camera.is_position_behind(_solution_aim):
		return Vector2.INF
	return camera.unproject_position(_solution_aim)


func _physics_process(_delta: float) -> void:
	_update_target_solution()


func _update_target_solution() -> void:
	_solution_target = null
	_solution_status = ""
	if not is_instance_valid(player) or player.dead or not is_instance_valid(camera):
		return
	var target := current_target()
	if target == null:
		return
	_solution_target = target
	var relative_velocity := target.velocity - player.velocity * 0.2
	var flight := Gunnery.intercept_time(target.global_position - player.global_position, relative_velocity, player.bolt_speed)
	if not is_finite(flight) or flight > GameConfig.BOLT_LIFETIME:
		_solution_status = "OUT OF RANGE"
		return
	_solution_aim = target.global_position + relative_velocity * flight
	# Query during the physics step; hide the lead pip when geometry blocks it.
	var impact_position := target.global_position + target.velocity * flight
	var query := PhysicsRayQueryParameters3D.create(player.global_position, impact_position,
		GameConfig.WEAPON_MASK)
	query.exclude = [player.get_rid(), target.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		_solution_status = "LINE OF FIRE BLOCKED"
	elif camera.is_position_behind(_solution_aim):
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
	var cam_basis := camera.global_transform.basis
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if other == null or other.dead or other == player or other.team == player.team:
			continue
		if camera.is_position_behind(other.global_position):
			continue
		var to := other.global_position - camera.global_position
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
	var t := current_target()
	if t == null:
		return
	var behind := camera.is_position_behind(t.global_position)
	var p := Vector2.INF if behind else camera.unproject_position(t.global_position)
	if behind or not Rect2(Vector2(24, 24), size - Vector2(48, 48)).has_point(p):
		# Off-screen indicator: arrow on the rim pointing at the contact.
		var c := size * 0.5
		var dir := (t.global_position - camera.global_position)
		var local := camera.global_transform.basis.inverse() * dir
		var ang := atan2(-local.y, local.x)
		var r: float = minf(size.x, size.y) * 0.36
		p = c + Vector2(cos(ang), sin(ang)) * r
		var tri := PackedVector2Array([
			p + Vector2(cos(ang), sin(ang)) * 12.0,
			p + Vector2(cos(ang + 2.4), sin(ang + 2.4)) * 10.0,
			p + Vector2(cos(ang - 2.4), sin(ang - 2.4)) * 10.0,
		])
		draw_colored_polygon(tri, Color(HOSTILE_COLOR.r, HOSTILE_COLOR.g, HOSTILE_COLOR.b, 0.85))
		_text(p + Vector2(18, 5), "%d m" % int(player.global_position.distance_to(t.global_position)), 13, HOSTILE_COLOR)
		return

	var dist := player.global_position.distance_to(t.global_position)
	# Bracket size scales with apparent size, floored so distant ships stay visible.
	var radius: float = clampf(1400.0 / maxf(dist, 12.0), 16.0, 90.0)
	var col := HOSTILE_COLOR
	draw_rect(Rect2(p - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), col, false, 1.5)
	for corner: Vector2 in [
		Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)
	]:
		var o := p + corner * radius
		draw_line(o, o - corner * Vector2(9, 0), col, 2.4)
		draw_line(o, o - corner * Vector2(0, 9), col, 2.4)

	# Health arc around the bracket.
	var hp_ratio: float = t.hull / maxf(t.hull_max, 1.0)
	if hp_ratio < 0.999:
		draw_arc(p, radius + 9.0, -PI * 0.5, -PI * 0.5 + TAU * hp_ratio, 28,
			Color(1.0, 0.35, 0.25, 0.9), 2.6)
	var name_width := maxf(_measure(t.display_name, 13) + 8.0, radius * 2.0)
	_text(p + Vector2(-name_width * 0.5, -radius - 8.0), t.display_name, 13, col, HORIZONTAL_ALIGNMENT_CENTER, name_width)
	_text(p + Vector2(radius + 14.0, 4.0), "%d m" % int(dist), 13, Color(1, 1, 1, 0.65))


# ------------------------------------------------------------- hull block --

func _draw_hull_block() -> void:
	var x := 96.0
	var y := size.y - 116.0
	var w := 214.0
	var h := 12.0
	draw_rect(Rect2(28, size.y - 190, 342, 162), Color(0.025, 0.045, 0.075, 0.86))
	draw_line(Vector2(28, size.y - 190), Vector2(370, size.y - 190), FRIENDLY_COLOR, 2.0)
	_text(Vector2(46, size.y - 164), "AZ-00  /  INTERCEPTOR", 11, Color(0.65, 0.78, 0.88))
	_text(Vector2(46, size.y - 133), "%03d" % int(player.speed), 28, Color(0.93, 0.98, 1.0))
	_text(Vector2(119, size.y - 135), "m/s", 12, Color(0.6, 0.75, 0.82))
	_text(Vector2(237, size.y - 138), "BOOST" if player.boosting else "CRUISE", 12, WARN_COLOR if player.boosting else RETICLE_COLOR)

	_bar(Rect2(x, y, w, h), player.hull / maxf(player.hull_max, 1.0),
		Color(0.35, 0.85, 0.55), Color(0.15, 0.35, 0.25), "HULL",
		"%d" % int(ceil(player.hull)), 46, y)
	_bar(Rect2(x, y + 28.0, w, h), player.shield / maxf(player.shield_max, 1.0),
		Color(0.45, 0.78, 1.0), Color(0.12, 0.28, 0.5), "SHLD",
		"%d" % int(ceil(player.shield)), 46, y + 28.0)

	var boost_ratio := player.boost / maxf(player.boost_max, 1.0)
	var boost_col := Color(1.0, 0.72, 0.3) if not player.boosting else Color(1.0, 0.45, 0.15)
	_bar(Rect2(x, y + 56.0, w, h), boost_ratio,
		boost_col, Color(0.32, 0.22, 0.08), "BOOST",
		"%d" % int(boost_ratio * 100.0), 46, y + 56.0)


func _bar(rect: Rect2, ratio: float, fill: Color, back: Color, label: String, value: String, label_x: float, label_y: float) -> void:
	draw_rect(rect, Color(0.04, 0.06, 0.10, 0.75))
	var r: float = clampf(ratio, 0.0, 1.0)
	if r > 0.0:
		draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2((rect.size.x - 4) * r, rect.size.y - 4)), fill)
		# Bright leading edge.
		draw_rect(Rect2(rect.position + Vector2((rect.size.x - 4) * r, 2), Vector2(2, rect.size.y - 4)),
			Color(1, 1, 1, 0.55))
	draw_rect(rect, back, false, 1.0)
	_text(Vector2(label_x, label_y + rect.size.y - 2.0), label, 11, Color(0.62, 0.72, 0.85))
	_text(Vector2(rect.end.x + 9.0, label_y + rect.size.y - 2.0),
		value, 12, Color(0.92, 0.96, 1.0))


# ------------------------------------------------------------------ radar --

func _draw_radar() -> void:
	var r := 92.0
	var centre := Vector2(size.x - r - 42.0, size.y - r - 42.0)
	draw_circle(centre, r + 8.0, Color(0.025, 0.045, 0.075, 0.96))

	draw_arc(centre, r, 0, TAU, 64, Color(0.35, 0.7, 1.0, 0.35), 1.4)
	draw_arc(centre, r * 0.66, 0, TAU, 48, Color(0.35, 0.7, 1.0, 0.16), 1.0)
	draw_arc(centre, r * 0.33, 0, TAU, 32, Color(0.35, 0.7, 1.0, 0.16), 1.0)
	draw_line(centre - Vector2(r, 0), centre + Vector2(r, 0), Color(0.35, 0.7, 1.0, 0.16), 1.0)
	draw_line(centre - Vector2(0, r), centre + Vector2(0, r), Color(0.35, 0.7, 1.0, 0.16), 1.0)

	# Cockpit coordinates: the nose stays up through yaw, pitch and roll.
	var pts := PackedVector2Array([centre])
	for i in 9:
		var angle := -PI * 0.5 - deg_to_rad(32.0) + deg_to_rad(64.0) * float(i) / 8.0
		pts.append(centre + Vector2(cos(angle), sin(angle)) * r)
	draw_colored_polygon(pts, Color(0.4, 0.85, 0.8, 0.10))

	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if other == null or other.dead or other == player:
			continue
		var rel := other.global_position - player.global_position
		var local := player.global_basis.inverse() * rel
		var flat := Vector2(local.x, local.z)
		var t: float = pow(clampf(flat.length() / RADAR_RANGE, 0.0, 1.0), 0.62)
		var p := centre + _radar_offset(other.global_position, r)
		var col := FRIENDLY_COLOR if other.team == player.team else HOSTILE_COLOR
		# Elevation tints the blip: brighter = above you, dimmer = below.
		var elev: float = clampf(local.y / maxf(flat.length(), 1.0), -1.0, 1.0)
		col = col.lerp(Color(0.6, 0.6, 0.7), clampf(-elev, 0.0, 1.0) * 0.55)
		var size_px := 3.5 if t > 0.98 else 2.6
		if other.team == player.team:
			draw_circle(p, size_px, col)
		else:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -size_px - 1), p + Vector2(size_px + 1, 0), p + Vector2(0, size_px + 1), p + Vector2(-size_px - 1, 0)]), col)
		if other == current_target():
			draw_arc(p, size_px + 4.0, 0, TAU, 16, Color(col.r, col.g, col.b, 0.8), 1.2)

	# Player icon always points up on the scope.
	var up_tri := PackedVector2Array([
		centre + Vector2(0, -6), centre + Vector2(4, 5), centre + Vector2(-4, 5)
	])
	draw_colored_polygon(up_tri, Color(0.9, 1.0, 0.95, 0.95))
	_text(centre + Vector2(-32, r + 24), "RADAR / 900 m", 10, Color(0.5, 0.65, 0.8))


func _radar_offset(world_position: Vector3, radius := 92.0) -> Vector2:
	var local := player.global_basis.inverse() * (world_position - player.global_position)
	var flat := Vector2(local.x, local.z)
	return flat.normalized() * radius * 0.94 * pow(clampf(flat.length() / RADAR_RANGE, 0.0, 1.0), 0.62)


# ----------------------------------------------------------- target panel --

func _draw_target_panel() -> void:
	var t := current_target()
	var x := size.x - 250.0
	var y := 74.0
	var panel := Rect2(x - 14.0, y - 28.0, 236.0, 140.0 if t != null else 72.0)
	draw_rect(panel, Color(0.025, 0.045, 0.075, 0.94))
	draw_line(panel.position, panel.position + Vector2(236, 0), Color(0.30, 0.46, 0.57), 1)
	if t == null:
		_text(Vector2(x, y), "NO TARGET", 15, Color(0.55, 0.62, 0.7))
		_text(Vector2(x, y + 20.0), "TAB — cycle lock", 12, Color(0.4, 0.45, 0.55))
		return
	var col := FRIENDLY_COLOR if t.team == player.team else HOSTILE_COLOR
	_text(Vector2(x, y), t.display_name, 17, col)
	if locked == t:
		_text(Vector2(x + _measure(t.display_name, 17) + 10.0, y), "LOCK", 12, WARN_COLOR)
	_text(Vector2(x, y + 20.0), "%s  ·  %d m" % [GameConfig.team_name(t.team), int(player.global_position.distance_to(t.global_position))], 12, Color(0.7, 0.76, 0.85))
	_text(Vector2(x, y + 38.0), "HULL %d%%" % int(100.0 * t.hull / maxf(t.hull_max, 1.0)), 12, Color(0.8, 0.85, 0.9))
	_text(Vector2(x, y + 54.0), "SHLD %d%%" % int(100.0 * t.shield / maxf(t.shield_max, 1.0)), 12, Color(0.7, 0.85, 1.0))
	_text(Vector2(x, y + 70.0), "%d m/s" % int(t.speed), 12, Color(0.7, 0.75, 0.8))
	if t == _solution_target:
		_text(Vector2(x, y + 96.0), _solution_status, 11, RETICLE_COLOR if _solution_status == "FIRING SOLUTION" else WARN_COLOR)


# --------------------------------------------------------------- killfeed --

func _draw_kill_feed() -> void:
	var y := 46.0
	for entry: Dictionary in GameMatch.get_feed():
		var alpha: float = clampf(entry.life / 1.5, 0.0, 1.0)
		var c: Color = entry.color
		c.a = alpha
		_text(Vector2(28, y), entry.text, 15, c)
		y += 22.0


func _draw_score() -> void:
	var blue := int(GameMatch.scores.get(GameConfig.TEAM_BLUE, 0))
	var red := int(GameMatch.scores.get(GameConfig.TEAM_RED, 0))
	var centre := size.x * 0.5
	var panel := Rect2(centre - 218, 24, 436, 70)
	draw_rect(panel, Color(0.025, 0.045, 0.075, 0.88))
	draw_line(panel.position, panel.position + Vector2(176, 0), FRIENDLY_COLOR, 2)
	draw_line(panel.position + Vector2(260, 0), panel.position + Vector2(436, 0), HOSTILE_COLOR, 2)
	_text(Vector2(centre - 198, 54), "AZURE", 12, FRIENDLY_COLOR)
	_text(Vector2(centre - 108, 58), "%02d" % blue, 26, Color.WHITE)
	_text(Vector2(centre + 74, 58), "%02d" % red, 26, Color.WHITE)
	_text(Vector2(centre + 132, 54), "CRIMSON", 12, HOSTILE_COLOR)

	var mins := int(GameMatch.remaining) / 60
	var secs := int(GameMatch.remaining) % 60
	_text(Vector2(centre - 42, 56), "%d:%02d" % [mins, secs], 20, WARN_COLOR if GameMatch.remaining <= 30 else Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 84)
	_text(Vector2(centre - 184, 80), "TEAM SKIRMISH  /  OUTSCORE CRIMSON", 11, Color(0.55, 0.7, 0.8), HORIZONTAL_ALIGNMENT_CENTER, 368)


func _draw_help() -> void:
	if _hint_alpha <= 0.01 or not bool(GameSettings.get_value("show_hints")):
		return
	var lines := [
		"MOUSE aim   ·   W/S thrust   ·   A/D strafe   ·   Q/E roll   ·   R/F lift",
		"SHIFT boost   ·   SPACE fire   ·   X dampeners   ·   C auto-level   ·   TAB lock",
		"V camera   ·   M cursor   ·   ESC menu   ·   Hold BACKSLASH scoreboard",
	]
	var y := size.y - 259.0
	for line: String in lines:
		_text(Vector2(28, y), line, 13, Color(0.72, 0.82, 0.95, _hint_alpha * 0.8))
		y += 18.0


# --------------------------------------------------------- damage & zones --

func _draw_damage_direction() -> void:
	if player.dead:
		return
	var age := float(Time.get_ticks_msec()) / 1000.0 - player.last_damage_time
	if age > 2.2:
		return
	var fade: float = clampf(1.0 - age / 2.2, 0.0, 1.0)
	var dir := player.last_damage_dir
	var local := player.global_transform.basis.inverse() * dir
	var ang := atan2(-local.x, local.y)   # 0 = straight ahead (top of the arc)
	var centre := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.30
	var pts := PackedVector2Array()
	for i in 17:
		var a: float = ang - deg_to_rad(20.0) + deg_to_rad(40.0) * float(i) / 16.0
		pts.append(centre + Vector2(sin(a), -cos(a)) * (radius + 18.0))
	pts.append(centre + Vector2(sin(ang), -cos(ang)) * radius)
	draw_colored_polygon(pts, Color(1.0, 0.22, 0.16, 0.42 * fade))


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
	_text(Vector2(size.x * 0.5 - 130.0, size.y * 0.5 - 130.0), "▲ RETURN TO COMBAT ZONE ▲", 20,
		Color(1.0, 0.4, 0.3, _zone_flash * pulse))


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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.02, 0.02, 0.22))
	var centre := Vector2(size.x * 0.5, size.y * 0.42)
	_text(centre - Vector2(240, 0), "SHIP DESTROYED", 40, Color(1.0, 0.35, 0.3),
		HORIZONTAL_ALIGNMENT_CENTER, 480.0)
	var left: float = float(player.get_meta("respawn_in", 0.0))
	_text(centre + Vector2(-240, 40.0), "redeploying in %.1f s" % maxf(left, 0.0), 18,
		Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 480.0)


func _draw_scoreboard() -> void:
	var origin := size * 0.5 - Vector2(320, 204)
	draw_rect(Rect2(origin, Vector2(640, 408)), Color(0.025, 0.045, 0.075, 0.95))
	draw_line(origin, origin + Vector2(640, 0), RETICLE_COLOR, 2)
	_text(origin + Vector2(24, 34), "SQUADRON STATUS", 18, RETICLE_COLOR)
	_text(origin + Vector2(24, 67), "PILOT", 12, Color(0.6, 0.75, 0.82))
	_text(origin + Vector2(354, 67), "KILLS", 12, Color(0.6, 0.75, 0.82))
	_text(origin + Vector2(426, 67), "DEATHS", 12, Color(0.6, 0.75, 0.82))
	_text(origin + Vector2(523, 67), "DAMAGE", 12, Color(0.6, 0.75, 0.82))
	var y := 103.0
	var last_team := -1
	for row: Dictionary in GameMatch.standings():
		if row.team != last_team:
			last_team = row.team
			_text(origin + Vector2(24, y), GameConfig.team_name(row.team), 11, GameConfig.team_color(row.team))
			y += 25.0
		var tint := Color.WHITE if row.name == "YOU" else Color(0.68, 0.78, 0.88)
		_text(origin + Vector2(24, y), row.name, 16, tint)
		_text(origin + Vector2(354, y), str(row.kills), 16, tint)
		_text(origin + Vector2(426, y), str(row.deaths), 16, tint)
		_text(origin + Vector2(523, y), "%.0f" % row.damage, 16, tint)
		y += 30.0
	_text(origin + Vector2(24, 389), "COMBAT CONTINUES  /  RELEASE BACKSLASH TO CLOSE", 11, Color(0.6, 0.75, 0.82))
