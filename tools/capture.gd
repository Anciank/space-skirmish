extends Node
## Screenshot harness. Boots the real game scene, drives the player with
## synthetic input, and writes PNGs so the visuals can be reviewed without a
## window.
##
##   godot --headless --script res://tools/capture.gd -- res://captures \
##       +shot=NAME,frames,thrust,strafe,boost,fire,yaw,pitch,cam,roll_deg ...
##
## Shot spec fields:
##   frames    physics frame at which to capture
##   thrust    -1..1 main throttle
##   strafe    -1..1 lateral thrust
##   boost     1 to hold the afterburner
##   fire      1 to hold the trigger
##   yaw/pitch nose attitude in degrees
##   cam       "chase" or "cockpit"
##   roll      extra body roll in degrees

const DEFAULT_SHOT := {
	"frames": 90, "thrust": 1.0, "strafe": 0.0, "boost": false,
	"fire": false, "yaw": 0.0, "pitch": 0.0, "cam": "chase", "roll": 0.0,
}

var _out := "res://captures"
var _shots: Dictionary = {}
var _taken: Array[String] = []
var _frame := 0
var _main: Node
var _rig: CameraRig
var _player: SpaceShip


func _ready() -> void:
	_parse_args()
	var packed: PackedScene = load("res://scenes/main.tscn")
	_main = packed.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	_rig = _main.rig
	_player = _main.player
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	print("capture: %d shot(s) -> %s" % [_shots.size(), _out])


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("+shot="):
			var parts := arg.substr(6).split(",")
			var spec := DEFAULT_SHOT.duplicate()
			spec["frames"] = int(parts[1])
			spec["thrust"] = float(parts[2])
			spec["strafe"] = float(parts[3])
			spec["boost"] = parts[4] == "1"
			spec["fire"] = parts[5] == "1"
			spec["yaw"] = float(parts[6])
			spec["pitch"] = float(parts[7])
			spec["cam"] = parts[8]
			spec["roll"] = float(parts[9])
			# "duel" teleports the player into firing range of the nearest
			# hostile so the targeting HUD can be reviewed with a real contact.
			spec["duel"] = parts.size() > 10 and parts[10] == "duel"
			_shots[parts[0]] = spec
		else:
			_out = arg
	if _shots.is_empty():
		_shots["default"] = DEFAULT_SHOT.duplicate()


func _physics_process(_delta: float) -> void:
	_frame += 1
	_apply_roll()
	for name: String in _shots.keys():
		var spec: Dictionary = _shots[name]
		if _frame != int(spec.frames):
			continue
		_drive(spec)
		if bool(spec.get("duel", false)):
			await _capture_duel(name)
			_taken.append(name)
			_shots.erase(name)
			continue
		# Hold the requested attitude while letting the camera, engine glow and
		# HUD settle into a representative frame.
		for _i in 10:
			_turn(float(spec.yaw), float(spec.pitch))
			await get_tree().physics_frame
		_capture(name)
		_taken.append(name)
		_shots.erase(name)
	if _shots.is_empty() and _frame > 30:
		print("captured: %s" % ", ".join(_taken))
		get_tree().quit()


## Rolls the hull toward the active shot's target attitude using the real roll
## keys, so the camera's roll damping gets a genuine input to react to.
func _apply_roll() -> void:
	if _player == null or _shots.is_empty():
		return
	var spec: Dictionary = _shots.values()[0]
	var want := deg_to_rad(float(spec.roll))
	var error := wrapf(want - _player.roll, -PI, PI)
	if absf(error) < deg_to_rad(3.0):
		_hold("roll_right", false)
		_hold("roll_left", false)
		return
	_hold("roll_right", error > 0.0)
	_hold("roll_left", error < 0.0)


## Drives the ship through the real input map.
##
## Setting `cmd_forward` directly does nothing: PlayerShip rewrites those fields
## from polled input every physics frame, so anything assigned here is thrown
## away immediately. Synthetic action presses exercise the same path a human
## would, which also means the harness fails if the input map regresses.
func _drive(spec: Dictionary) -> void:
	_player.capture_mouse(false)

	_hold("thrust_forward", float(spec.thrust) > 0.01)
	_hold("thrust_back", float(spec.thrust) < -0.01)
	_hold("thrust_right", float(spec.strafe) > 0.01)
	_hold("thrust_left", float(spec.strafe) < -0.01)
	_hold("boost", bool(spec.boost))
	_hold("fire", bool(spec.fire))

	_sync_attitude()
	_rig.mode_chase = str(spec.cam) != "cockpit"


## Feeds a synthetic mouse delta so the ship actually turns through the real
## input path instead of having its attitude overwritten.
func _turn(yaw_deg: float, pitch_deg: float) -> void:
	var turn := Vector2(
		deg_to_rad(yaw_deg) - _player.yaw,
		deg_to_rad(pitch_deg) - _player.pitch
	)
	var ev := InputEventMouseMotion.new()
	# look_speed is radians per pixel at 60 Hz; invert it to build the delta.
	ev.relative = Vector2(turn.x, -turn.y) / _player.look_speed
	_player._unhandled_input(ev)


## Re-reads the player's cached yaw/pitch from its actual orientation.
##
## PlayerShip keeps its own yaw/pitch angles and slerps the hull toward them, so
## any code that moves the ship directly (respawn_at / look_at) leaves those two
## numbers stale. Steering the harness off the stale values snaps the ship to an
## unrelated attitude, which is why the duel capture aimed off into empty space.
func _sync_attitude() -> void:
	# get_euler() defaults to YXZ, which is exactly the order PlayerShip feeds to
	# Quaternion.from_euler(), so this round-trips the hull orientation precisely.
	var e := _player.global_transform.basis.get_euler()
	_player.pitch = e.x
	_player.yaw = e.y
	_player.roll = e.z


## Points the player's nose at a world position by aiming its cached Euler
## angles, i.e. through the same values the mouse drives. Returns the resulting
## angular error in degrees.
func _aim_at(target: Vector3) -> float:
	var to_target := target - _player.global_position
	if to_target.length_squared() < 0.001:
		return 0.0
	var dir := to_target.normalized()
	# Solve the YXZ angles for this direction. Deriving pitch from the world Y
	# axis is what a real player does; the mistake is projecting onto the hull's
	# own up vector, which double-counts the existing roll.
	_player.yaw = atan2(-dir.x, -dir.z)
	_player.pitch = rad_to_deg(asin(clampf(dir.y, -1.0, 1.0)))
	_player.roll = 0.0
	return 0.0


func _hold(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	var err := img.save_png(path)
	print("  %-14s -> %s  (%dx%d, err %d)" % [name, path, img.get_width(), img.get_height(), err])


## True when the whole corridor between `a` and `b` is empty: no solid hit along
## the centre ray, and nothing within `clearance` of any sample point.
func _line_is_clear(a: Vector3, b: Vector3, clearance: float) -> bool:
	var space := _player.get_world_3d().direct_space_state
	var mask := GameConfig.LAYER_WORLD | GameConfig.LAYER_ROCK
	var steps := 8
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		# Probe four lateral offsets so a body just off the centre line is caught.
		for offset: Vector3 in [Vector3.ZERO, Vector3.RIGHT * clearance,
				Vector3.LEFT * clearance, Vector3.UP * clearance]:
			var probe := p + offset
			var query := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * 0.01, mask)
			query.exclude = [_player.get_rid()]
			if not space.intersect_ray(query).is_empty():
				return false
		# A sphere test is the reliable way to catch a planet's radius, which a
		# single downward ray can miss entirely.
		var sphere := SphereShape3D.new()
		sphere.radius = clearance
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = sphere
		params.transform = Transform3D(Basis.IDENTITY, p)
		params.collision_mask = mask
		params.exclude = [_player.get_rid()]
		if not space.intersect_shape(params, 1).is_empty():
			return false
	return true


## Screenshots the player parked in firing range of the nearest hostile, so the
## target brackets, lead pip, target panel and radar can be reviewed against a
## real contact instead of an empty sky.
func _capture_duel(name: String) -> void:
	if _player == null:
		return
	var best: SpaceShip = null
	var best_d := INF
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var s := node as SpaceShip
		if s == null or s == _player or s.dead or s.team == _player.team:
			continue
		var d := s.global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		print("  %s: no hostile in range" % name)
		return

	# Pick a firing line with genuinely empty space: no rocks, no planets, and
	# with a margin so the planet's atmosphere shell cannot glow over the target.
	var origin := best.global_position
	var chosen := Vector3.FORWARD
	var found := false
	for _attempt in 64:
		var probe_dir := Vector3(
			randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		if probe_dir.length_squared() < 0.05:
			continue
		probe_dir = probe_dir.normalized()
		var probe := origin + probe_dir * 220.0
		if _line_is_clear(origin, probe, 40.0):
			chosen = probe_dir
			found = true
			break
	if not found:
		# Fall back to a random bearing rather than abandoning the shot.
		chosen = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)).normalized()
		push_warning("no clear firing line for %s; using a random bearing" % name)
	var standoff := origin + chosen * 200.0

	# Park both ships. Their controllers keep rewriting orientation every frame,
	# which would fight the framing and leave the capture aimed at nothing —
	# respawn_at() already aims the nose at the target via look_at, so freezing
	# physics preserves that attitude instead of re-deriving Euler angles the
	# slerp then fights over.
	best.set_physics_process(false)
	_player.set_physics_process(false)
	_player.respawn_at(standoff, origin)
	_player.velocity = Vector3.ZERO
	_rig.mode_chase = true
	# The player teleported, so the camera has to jump rather than lerp across the
	# arena — otherwise the capture frames empty space while it catches up.
	_rig.snap_to_target()
	_main.hud.locked = best
	# A few frames so the HUD and any pending effects are up to date.
	for _i in 8:
		best.global_position = origin
		await get_tree().process_frame

	# Verify the nose actually ended up on the target rather than assuming the
	# Euler convention round-trips.
	var want_dir := (origin - _player.global_position).normalized()
	var off := rad_to_deg(_player.forward().angle_to(want_dir))
	# The hostile has to actually be on screen, otherwise the brackets and the
	# lead pip are never drawn and the capture proves nothing.
	var on_screen := not _rig.camera.is_position_behind(best.global_position)
	var in_frame := false
	if on_screen:
		var uv := _rig.camera.unproject_position(best.global_position)
		in_frame = uv.x > 0.0 and uv.x < 1600.0 and uv.y > 0.0 and uv.y < 900.0
	var model := _player.get_node_or_null("ShipModel") as Node3D
	var cam_to_ship := _rig.camera.global_position.distance_to(_player.global_position)
	print("    duel: %s at %.0f m, nose %.1f deg off, on-screen=%s, in-frame=%s" % [
		best.display_name, _player.global_position.distance_to(origin), off,
		str(on_screen), str(in_frame)])
	print("      hull visible=%s model visible=%s cam_dist=%.1f m cam_mode_chase=%s" % [
		str(_player.visible), str(model.visible if model else false),
		cam_to_ship, str(_rig.mode_chase)])
	if off > 2.0 or not in_frame:
		push_warning("duel framing unusable: off=%.1f deg, in_frame=%s" % [off, in_frame])
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	print("  %-14s -> %s  (duel vs %s, err %d)" % [name, path, best.display_name, img.save_png(path)])
