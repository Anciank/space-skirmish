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

var hud_paused := false
var match_over := false
var match_winner := -1

## Enemy the player has explicitly locked (Tab). Cleared when it dies or leaves
## the arena, otherwise the reticle falls back to auto-acquisition.
var locked: SpaceShip = null

var _damage_flash := 0.0
var _zone_flash := 0.0
var _hit_markers: Array[Dictionary] = []
var _time := 0.0
var _font: Font = null
var _hint_alpha := 1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	GameMatch.kill_logged.connect(_on_kill_logged)


func setup(player_ship: SpaceShip, camera_rig: CameraRig) -> void:
	player = player_ship
	rig = camera_rig
	camera = camera_rig.camera
	if player != null:
		player.took_damage.connect(_on_player_damaged)
		player.weapon_fired.connect(_on_player_fired)


func _process(delta: float) -> void:
	_time += delta
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.2)
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


func _on_player_fired() -> void:
	pass


func register_hit_kill() -> void:
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
	if hud_paused:
		_draw_pause_overlay()
	if match_over:
		_draw_match_over()


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
	if t == null:
		return Vector2.INF
	var dist := player.global_position.distance_to(t.global_position)
	var flight := dist / maxf(player.bolt_speed, 1.0)
	var aim := t.global_position + t.velocity * flight
	if camera.is_position_behind(aim):
		return Vector2.INF
	return camera.unproject_position(aim)


## Locked contact if we have one, otherwise the hostile nearest the crosshair.
func current_target() -> SpaceShip:
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
		var flat := Vector2(to.dot(cam_basis.x), -to.dot(cam_basis.y))
		var ang := rad_to_deg(atan2(flat.y, flat.x))
		if absf(ang) > 55.0:
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
	if rig != null:
		rig.add_shake(0.12)


func _draw_target_brackets() -> void:
	var t := current_target()
	if t == null:
		return
	var behind := camera.is_position_behind(t.global_position)
	if behind:
		# Off-screen indicator: arrow on the rim pointing at the contact.
		var c := size * 0.5
		var dir := (t.global_position - camera.global_position)
		var local := camera.global_transform.basis.inverse() * dir
		var ang := atan2(-local.y, local.x)
		var r: float = minf(size.x, size.y) * 0.36
		var p := c + Vector2(cos(ang), sin(ang)) * r
		var tri := PackedVector2Array([
			p + Vector2(cos(ang), sin(ang)) * 12.0,
			p + Vector2(cos(ang + 2.4), sin(ang + 2.4)) * 10.0,
			p + Vector2(cos(ang - 2.4), sin(ang - 2.4)) * 10.0,
		])
		draw_colored_polygon(tri, Color(HOSTILE_COLOR.r, HOSTILE_COLOR.g, HOSTILE_COLOR.b, 0.85))
		_text(p + Vector2(18, 5), "%d m" % int(player.global_position.distance_to(t.global_position)), 13, HOSTILE_COLOR)
		return

	var p := camera.unproject_position(t.global_position)
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
	_text(p + Vector2(-radius, -radius - 8.0), t.display_name, 13, col, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0)
	_text(p + Vector2(radius + 14.0, 4.0), "%d m" % int(dist), 13, Color(1, 1, 1, 0.65))


# ------------------------------------------------------------- hull block --

func _draw_hull_block() -> void:
	var x := 28.0
	var y := size.y - 118.0
	var w := 268.0
	var h := 15.0

	_bar(Rect2(x, y, w, h), player.hull / maxf(player.hull_max, 1.0),
		Color(0.35, 0.85, 0.55), Color(0.15, 0.35, 0.25), "HULL",
		"%d" % int(ceil(player.hull)), x - 12, y)
	_bar(Rect2(x, y + 21.0, w, h), player.shield / maxf(player.shield_max, 1.0),
		Color(0.45, 0.78, 1.0), Color(0.12, 0.28, 0.5), "SHLD",
		"%d" % int(ceil(player.shield)), x - 12, y + 21.0)

	var boost_ratio := player.boost / maxf(player.boost_max, 1.0)
	var boost_col := Color(1.0, 0.72, 0.3) if not player.boosting else Color(1.0, 0.45, 0.15)
	_bar(Rect2(x, y + 42.0, w, h), boost_ratio,
		boost_col, Color(0.32, 0.22, 0.08), "BOOST",
		"%d%%" % int(boost_ratio * 100.0), x - 12, y + 42.0)

	# Speed readout + throttle ladder.
	var sy := y + 72.0
	_text(Vector2(x - 12, sy), "VEL %4d" % int(player.speed), 17, Color(0.85, 0.95, 1.0))
	_text(Vector2(x + 118, sy), "%3d%%" % int(absf(player.throttle) * 100.0), 15,
		Color(0.6, 0.7, 0.8))
	draw_rect(Rect2(x, sy + 8.0, w, 4.0), Color(0.1, 0.14, 0.2, 0.8))
	draw_rect(Rect2(x, sy + 8.0, w * clampf(absf(player.throttle), 0, 1), 4.0),
		Color(0.5, 0.9, 0.7, 0.9))
	# Speed cap marker.
	var cap_x := x + w * (player.speed_boost / GameConfig.SPEED_BOOST)
	draw_line(Vector2(cap_x, sy + 5.0), Vector2(cap_x, sy + 15.0), Color(1, 1, 1, 0.45), 1.2)


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
	_text(Vector2(rect.position.x + rect.size.x - _measure(value, 12) - 4.0, label_y + rect.size.y - 2.0),
		value, 12, Color(0.92, 0.96, 1.0))


# ------------------------------------------------------------------ radar --

func _draw_radar() -> void:
	var r := 92.0
	var centre := Vector2(size.x - r - 42.0, size.y - r - 42.0)

	draw_arc(centre, r, 0, TAU, 64, Color(0.35, 0.7, 1.0, 0.35), 1.4)
	draw_arc(centre, r * 0.66, 0, TAU, 48, Color(0.35, 0.7, 1.0, 0.16), 1.0)
	draw_arc(centre, r * 0.33, 0, TAU, 32, Color(0.35, 0.7, 1.0, 0.16), 1.0)
	draw_line(centre - Vector2(r, 0), centre + Vector2(r, 0), Color(0.35, 0.7, 1.0, 0.16), 1.0)
	draw_line(centre - Vector2(0, r), centre + Vector2(0, r), Color(0.35, 0.7, 1.0, 0.16), 1.0)

	# Heading cone so you can orient against the radar.
	var fwd := player.forward()
	var flat_fwd := Vector3(fwd.x, 0.0, fwd.z)
	if flat_fwd.length_squared() > 0.0001:
		flat_fwd = flat_fwd.normalized()
		var base := Vector2(flat_fwd.x, -flat_fwd.z).angle()
		var pts := PackedVector2Array()
		for i in 7:
			var a: float = base - deg_to_rad(32.0) + deg_to_rad(64.0) * float(i) / 6.0
			pts.append(centre + Vector2(cos(a), sin(a)) * r)
		pts.append(centre)
		draw_colored_polygon(pts, Color(0.4, 0.85, 0.8, 0.10))

	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if other == null or other.dead or other == player:
			continue
		var rel := other.global_position - player.global_position
		var flat := Vector3(rel.x, 0.0, rel.z)
		if flat.length_squared() < 0.0001:
			continue
		var a := Vector2(flat.x, -flat.z).angle()
		var t: float = pow(clampf(flat.length() / RADAR_RANGE, 0.0, 1.0), 0.62)
		var dist := r * 0.94 * t
		var p := centre + Vector2(cos(a), sin(a)) * dist
		var col := FRIENDLY_COLOR if other.team == player.team else HOSTILE_COLOR
		# Elevation tints the blip: brighter = above you, dimmer = below.
		var elev: float = clampf(rel.y / maxf(flat.length(), 1.0), -1.0, 1.0)
		col = col.lerp(Color(0.6, 0.6, 0.7), clampf(-elev, 0.0, 1.0) * 0.55)
		var size_px := 3.5 if t > 0.98 else 2.6
		draw_circle(p, size_px, col)
		if other == current_target():
			draw_arc(p, size_px + 4.0, 0, TAU, 16, Color(col.r, col.g, col.b, 0.8), 1.2)

	# Player icon always points up on the scope.
	var up_tri := PackedVector2Array([
		centre + Vector2(0, -6), centre + Vector2(4, 5), centre + Vector2(-4, 5)
	])
	draw_colored_polygon(up_tri, Color(0.9, 1.0, 0.95, 0.95))
	_text(centre + Vector2(-r * 0.5 - 14, 4), "%d km" % int(RADAR_RANGE / 1000.0), 10, Color(0.5, 0.65, 0.8))


# ----------------------------------------------------------- target panel --

func _draw_target_panel() -> void:
	var t := current_target()
	var x := size.x - 250.0
	var y := 74.0
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
	var bw := 190.0

	draw_rect(Rect2(centre - bw, 30.0, bw, 8.0), Color(0.1, 0.16, 0.28, 0.9))
	draw_rect(Rect2(centre - bw, 30.0, bw, 8.0), FRIENDLY_COLOR)
	_text(Vector2(centre - bw - 74.0, 39.0), "AZURE", 14, FRIENDLY_COLOR)
	_text(Vector2(centre - bw - 50.0, 39.0), str(blue), 18, Color.WHITE)

	draw_rect(Rect2(centre, 30.0, bw, 8.0), Color(0.28, 0.1, 0.1, 0.9))
	draw_rect(Rect2(centre, 30.0, bw, 8.0), HOSTILE_COLOR)
	_text(Vector2(centre + bw + 10.0, 39.0), str(red), 18, Color.WHITE)
	_text(Vector2(centre + bw + 40.0, 39.0), "CRIMSON", 14, HOSTILE_COLOR)

	var mins := int(GameMatch.remaining) / 60
	var secs := int(GameMatch.remaining) % 60
	_text(Vector2(centre, 66.0), "%d:%02d" % [mins, secs], 18, Color(0.85, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, bw * 2.0)


func _draw_help() -> void:
	if _hint_alpha <= 0.01:
		return
	var lines := [
		"MOUSE aim   ·   W/S thrust   ·   A/D strafe   ·   Q/E roll   ·   R/F lift",
		"SHIFT boost   ·   SPACE fire   ·   X dampeners   ·   C auto-level   ·   TAB lock",
		"V camera   ·   M release mouse   ·   ESC pause   ·   F5 restart",
	]
	var y := size.y - 190.0
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
	var d := Vector3(player.global_position.x, 0.0, player.global_position.z).length()
	if d <= limit:
		_zone_flash = maxf(_zone_flash - 0.02, 0.0)
		return
	_zone_flash = minf(1.0, _zone_flash + 0.08)
	var pulse := 0.6 + 0.4 * sin(_time * 7.0)
	_text(Vector2(size.x * 0.5 - 130.0, size.y * 0.5 - 130.0), "▲ RETURN TO COMBAT ZONE ▲", 20,
		Color(1.0, 0.4, 0.3, _zone_flash * pulse))


func _draw_hit_markers() -> void:
	var c := size * 0.5
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
	var alpha: float = clampf(1.0 - player.get_meta("respawn_in", 0.0) / 1.2, 0.0, 1.0)
	_text(centre - Vector2(160, 0), "SHIP DESTROYED", 40, Color(1.0, 0.35, 0.3, alpha),
		HORIZONTAL_ALIGNMENT_CENTER, 320.0)
	var left: float = float(player.get_meta("respawn_in", 0.0))
	_text(centre + Vector2(0, 40.0), "redeploying in %.1f s" % maxf(left, 0.0), 18,
		Color(1, 1, 1, 0.8 * alpha), HORIZONTAL_ALIGNMENT_CENTER, 320.0)


func _draw_pause_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.72))
	var centre := Vector2(size.x * 0.5, size.y * 0.5)
	_text(Vector2(centre.x - 120.0, centre.y - 60.0), "PAUSED", 44,
		Color(0.9, 0.95, 1.0), HORIZONTAL_ALIGNMENT_CENTER, 240.0)
	var rows := [
		"ESC / click below — resume",
		"R — restart match",
		"F5 — restart match",
		"Q — quit to desktop",
	]
	var y := centre.y + 10.0
	for r: String in rows:
		_text(centre + Vector2(-150, y), r, 18, Color(0.75, 0.85, 0.98), HORIZONTAL_ALIGNMENT_CENTER, 300.0)
		y += 30.0


func _draw_match_over() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.78))
	var centre := Vector2(size.x * 0.5, size.y * 0.44)
	var winner_color := GameConfig.team_color(match_winner)
	_text(centre - Vector2(250, 0), "%s WINS" % GameConfig.team_name(match_winner), 52,
		winner_color, HORIZONTAL_ALIGNMENT_CENTER, 500.0)
	var blue := int(GameMatch.scores.get(GameConfig.TEAM_BLUE, 0))
	var red := int(GameMatch.scores.get(GameConfig.TEAM_RED, 0))
	_text(centre + Vector2(0, 56.0), "AZURE %d  —  %d CRIMSON" % [blue, red], 26,
		Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, 500.0)
	_text(centre + Vector2(0, 110.0), "F5 — fly again", 20, Color(0.8, 0.88, 1.0),
		HORIZONTAL_ALIGNMENT_CENTER, 500.0)
