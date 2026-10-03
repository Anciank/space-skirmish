extends Node3D
## Camera motion and feedback at independent render rates, using the real rig.

const SHIP_SCENE := preload("res://scenes/ships/player_ship.tscn")
const RIG_SCENE := preload("res://scenes/ui/camera_rig.tscn")
const RATES := [30, 60, 144]

var _checks := 0
var _failures := 0
var _preferences: Dictionary
var _fixtures: Array[Node3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preferences = GameSettings.values.duplicate()
	GameSettings.reset_to_defaults(false)
	await get_tree().physics_frame
	GameSettings.set_value("camera_shake", false, false)
	var turns: Array[Dictionary] = []
	var shots: Array[Dictionary] = []
	for fps: int in RATES:
		_steady_follow(fps, GameConfig.SPEED_BOOST)
		# Faster than the current drive cap: this exposes the old distance-based
		# snap that ordinary translation lag can trigger at high speed.
		_steady_follow(fps, 420.0)
		turns.append(_turning_follow(fps))
		for pitch_degrees: float in [0.0, -89.0, 89.0]:
			for direction: int in [-1, 1]:
				_continuous_roll(fps, pitch_degrees, direction)
		_compound_roll(fps)
		_auto_level_poles(fps)
		_cockpit_follow(fps)
		GameSettings.set_value("camera_shake", true, false)
		shots.append(_sustained_recoil(fps))
		GameSettings.set_value("camera_shake", false, false)
	_frame_rate_comparison(turns, shots)
	_render_pose()
	_lifecycle()
	_damage_feedback()
	_settings_feedback()
	_real_fire()
	await _freed_target()
	for fixture: Node3D in _fixtures:
		fixture.queue_free()
	await get_tree().process_frame
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	print("--- camera stability: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _fixture() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	_fixtures.append(root)
	var ship := SHIP_SCENE.instantiate() as SpaceShip
	ship.set_physics_process(false)
	root.add_child(ship)
	ship.set_process_unhandled_input(false)
	var rig := RIG_SCENE.instantiate() as CameraRig
	rig.set_process(false)
	root.add_child(rig)
	rig.target = ship
	rig.snap_to_target()
	return {"ship": ship, "rig": rig}


func _pose(ship: SpaceShip, basis: Basis, position: Vector3, velocity := Vector3.ZERO) -> Transform3D:
	var transform := Transform3D(basis, position)
	ship.global_transform = transform
	ship.velocity = velocity
	ship.speed = velocity.length()
	return transform


func _steady_follow(fps: int, speed: float) -> void:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	var delta := 1.0 / fps
	ship.boosting = true
	var previous := rig.global_position
	var previous_relative := rig.global_position - ship.global_position
	var maximum_error := 0.0
	var maximum_step := 0.0
	var maximum_speed_error := 0.0
	var valid := true
	for frame in fps * 6:
		var elapsed := (frame + 1) * delta
		var pose := _pose(ship, Basis.IDENTITY, Vector3(0, 0, -speed * elapsed), Vector3(0, 0, -speed))
		rig._update_camera(delta, pose)
		var relative := rig.global_position - pose.origin
		if elapsed > 2.0:
			maximum_error = maxf(maximum_error, relative.distance_to(rig.chase_offset))
			maximum_step = maxf(maximum_step, relative.distance_to(previous_relative))
			maximum_speed_error = maxf(maximum_speed_error, ((rig.global_position - previous) / delta - ship.velocity).length())
		valid = valid and rig.global_transform.is_finite() and _pure_rotation(rig.global_basis)
		previous = rig.global_position
		previous_relative = relative
	var label := "%d FPS / %.0f m/s" % [fps, speed]
	_check(label + " follows cruise/boost without accumulating translation lag", maximum_error < 0.15,
		"maximum offset error %.4f m" % maximum_error)
	_check(label + " has no recurring follow snap", maximum_step < 0.05 and maximum_speed_error < 2.0,
		"offset jump %.4f m, velocity error %.3f m/s" % [maximum_step, maximum_speed_error])
	_check(label + " keeps a finite rigid camera transform", valid)


func _turning_follow(fps: int) -> Dictionary:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	var delta := 1.0 / fps
	var maximum_step := 0.0
	var previous := rig.global_basis
	var valid := true
	for frame in fps * 8:
		var elapsed := (frame + 1) * delta
		var basis := Basis.from_euler(Vector3(0.18 * sin(0.7 * elapsed), 0.5 * elapsed, 0.5 * sin(0.9 * elapsed)))
		var position := Vector3(80 * sin(0.2 * elapsed), 20 * sin(0.4 * elapsed), -90 * elapsed)
		var velocity := Vector3(16 * cos(0.2 * elapsed), 8 * cos(0.4 * elapsed), -90)
		var pose := _pose(ship, basis, position, velocity)
		rig._update_camera(delta, pose)
		if elapsed > 1.0:
			maximum_step = maxf(maximum_step, _angle(previous, rig.global_basis) / delta)
		valid = valid and _pure_rotation(rig.global_basis)
		previous = rig.global_basis
	_check("%d FPS smooth pitch/yaw/roll follow has no angular jumps" % fps, maximum_step < 1.5,
		"maximum angular speed %.4f rad/s" % maximum_step)
	_check("%d FPS turning preserves camera axes" % fps, valid)
	return {"basis": rig.global_basis, "offset": rig.global_position - ship.global_position, "fov": rig.camera.fov}


func _cockpit_follow(fps: int) -> void:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	rig.toggle_mode()
	var delta := 1.0 / fps
	var maximum_position_error := 0.0
	var maximum_angle := 0.0
	for frame in fps * 3:
		var elapsed := (frame + 1) * delta
		var basis := Basis.from_euler(Vector3(0.3 * sin(elapsed), 0.8 * elapsed, 0.6 * sin(elapsed * 1.3)))
		var pose := _pose(ship, basis, Vector3(30 * elapsed, 8 * sin(elapsed), -235 * elapsed))
		rig._update_camera(delta, pose)
		var expected := pose * Transform3D(Basis.IDENTITY, rig.cockpit_offset)
		maximum_position_error = maxf(maximum_position_error, rig.camera.global_position.distance_to(expected.origin))
		maximum_angle = maxf(maximum_angle, _angle(rig.camera.global_basis, expected.basis))
	_check("%d FPS cockpit remains attached during turns and thrust" % fps,
		maximum_position_error < 0.002 and maximum_angle < 0.001,
		"attachment error %.5f m, angle %.6f rad" % [maximum_position_error, maximum_angle])
	_check("%d FPS cockpit hides the player's hull" % fps, not ship.model.visible)


func _continuous_roll(fps: int, pitch_degrees: float, direction: int) -> void:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	var delta := 1.0 / fps
	ship.pitch = deg_to_rad(pitch_degrees)
	ship.yaw = 0.7
	_pose(ship, Basis.from_euler(Vector3(ship.pitch, ship.yaw, 0.0)), Vector3(10000, 10000, 10000))
	rig.snap_to_target()
	var action := "roll_left" if direction < 0 else "roll_right"
	Input.action_press(action)
	var previous_roll: float = ship.roll
	var previous_ship := ship.global_basis
	var previous_camera := rig.global_basis
	var maximum_lag := 0.0
	var maximum_offset_error := 0.0
	var maximum_step_error := 0.0
	var maximum_speed := 0.0
	var wraps := 0
	var valid := true
	for frame in fps * 8:
		# Exercise the player's real Q/E input, including wrap at +/- PI.
		ship._aim(delta)
		var pose := _pose(ship, ship.global_basis,
			Vector3(10000 + frame * delta * 70.0, 10000, 10000 - frame * delta * 235.0))
		rig._update_camera(delta, pose)
		if absf(ship.roll - previous_roll) > PI:
			wraps += 1
		maximum_lag = maxf(maximum_lag, _angle(pose.basis, rig.global_basis))
		var local_offset := pose.basis.transposed() * (rig.global_position - pose.origin)
		maximum_offset_error = maxf(maximum_offset_error, local_offset.distance_to(rig.chase_offset))
		var ship_step := pose.basis * previous_ship.transposed()
		var camera_step := rig.global_basis * previous_camera.transposed()
		maximum_step_error = maxf(maximum_step_error, _angle(ship_step, camera_step))
		maximum_speed = maxf(maximum_speed, _angle(previous_camera, rig.global_basis) / delta)
		valid = valid and rig.global_transform.is_finite() and _pure_rotation(rig.global_basis)
		previous_roll = ship.roll
		previous_ship = pose.basis
		previous_camera = rig.global_basis
	Input.action_release(action)
	var label := "%d FPS %s / pitch %.0f degrees" % [fps, action, pitch_degrees]
	_check(label + " fully follows three complete rolls", wraps >= 3 and maximum_lag < 0.001,
		"wraps %d, roll lag %.4f degrees" % [wraps, rad_to_deg(maximum_lag)])
	_check(label + " keeps the hull at the same camera offset", maximum_offset_error < 0.008,
		"maximum offset error %.5f m" % maximum_offset_error)
	_check(label + " has no reversal or jump across inverted and vertical attitudes",
		maximum_step_error < 0.001 and maximum_speed < ship.roll_speed + 0.05,
		"step mismatch %.4f degrees, speed %.3f rad/s" % [rad_to_deg(maximum_step_error), maximum_speed])
	_check(label + " retains finite orthonormal camera axes", valid)


func _compound_roll(fps: int) -> void:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	var delta := 1.0 / fps
	Input.action_press("roll_right")
	Input.action_press("steer_right")
	Input.action_press("steer_up")
	var maximum_lag := 0.0
	var maximum_offset_error := 0.0
	for frame in fps * 6:
		ship._aim(delta)
		var pose := _pose(ship, ship.global_basis, Vector3(0, 0, -frame * delta * 235.0))
		rig._update_camera(delta, pose)
		maximum_lag = maxf(maximum_lag, _angle(pose.basis, rig.global_basis))
		var local_offset := pose.basis.transposed() * (rig.global_position - pose.origin)
		maximum_offset_error = maxf(maximum_offset_error, local_offset.distance_to(rig.chase_offset))
	Input.action_release("roll_right")
	Input.action_release("steer_right")
	Input.action_release("steer_up")
	_check("%d FPS simultaneous roll, yaw and pitch follow without an up-vector switch" % fps,
		maximum_lag < 0.001 and maximum_offset_error < 0.002,
		"lag %.4f degrees, offset %.5f m" % [rad_to_deg(maximum_lag), maximum_offset_error])


func _auto_level_poles(fps: int) -> void:
	for pitch_degrees: float in [89.9, 90.0, 90.1]:
		for roll_degrees: float in [179.9, 180.0, 180.1]:
			var fixture := _fixture()
			var ship: SpaceShip = fixture.ship
			var rig: CameraRig = fixture.rig
			ship.pitch = deg_to_rad(pitch_degrees)
			ship.yaw = 0.6
			ship.roll = deg_to_rad(roll_degrees)
			_pose(ship, Basis.from_euler(Vector3(ship.pitch, ship.yaw, ship.roll)), Vector3(10000, 10000, 10000))
			rig.snap_to_target()
			var delta := 1.0 / fps
			var previous := ship.global_basis
			var maximum_speed := 0.0
			var maximum_camera_lag := 0.0
			var valid := true
			Input.action_press("recenter")
			for _frame in fps * 4:
				ship._aim(delta)
				rig._update_camera(delta, ship.global_transform)
				maximum_speed = maxf(maximum_speed, _angle(previous, ship.global_basis) / delta)
				maximum_camera_lag = maxf(maximum_camera_lag, _angle(ship.global_basis, rig.global_basis))
				valid = valid and _pure_rotation(ship.global_basis) and _pure_rotation(rig.global_basis)
				previous = ship.global_basis
			Input.action_release("recenter")
			var label := "%d FPS auto-level / pitch %.1f / roll %.1f" % [fps, pitch_degrees, roll_degrees]
			_check(label + " stays continuous through pole and inverted branches",
				valid and maximum_speed < 4.6 and maximum_camera_lag < 0.001,
				"peak speed %.4f rad/s, camera lag %.6f rad" % [maximum_speed, maximum_camera_lag])
			_check(label + " reaches an upright horizontal attitude",
				ship.global_basis.y.dot(Vector3.UP) > 0.9999 and absf(ship.forward().y) < 0.001)


func _sustained_recoil(fps: int) -> Dictionary:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	var delta := 1.0 / fps
	ship.recoil = 0.8
	var maximum_displacement := 0.0
	var maximum_angle := 0.0
	var maximum_rig_angle := 0.0
	var mean_angle := Vector3.ZERO
	var previous := rig.camera.position
	var maximum_step := 0.0
	var valid := true
	for _frame in fps * 12:
		rig._update_camera(delta, ship.global_transform)
		maximum_displacement = maxf(maximum_displacement, rig.camera.position.length())
		maximum_angle = maxf(maximum_angle, _angle(Basis.IDENTITY, rig.camera.basis))
		maximum_rig_angle = maxf(maximum_rig_angle, _angle(Basis.IDENTITY, rig.global_basis))
		mean_angle += rig.camera.rotation
		maximum_step = maxf(maximum_step, rig.camera.position.distance_to(previous))
		previous = rig.camera.position
		valid = valid and _pure_rotation(rig.camera.global_basis)
	mean_angle /= fps * 12.0
	_check("%d FPS sustained fire leaves the follow orientation clean" % fps, maximum_rig_angle < 0.0001)
	_check("%d FPS firing kick is visible, gentle and continuous" % fps,
		maximum_displacement > 0.005 and maximum_displacement <= 0.0351 and maximum_step < 0.02,
		"peak %.5f m, step %.5f m" % [maximum_displacement, maximum_step])
	_check("%d FPS sustained fire has no angular drift or mean aim bias" % fps,
		maximum_angle < 0.0001 and mean_angle.length() < 0.0001)
	_check("%d FPS recoil preserves a pure camera rotation" % fps, valid)
	var sustained_position := rig.camera.position
	ship.recoil = 0.0
	for _frame in fps * 2:
		rig._update_camera(delta, ship.global_transform)
	_check("%d FPS camera returns to neutral after firing stops" % fps, _neutral(rig.camera.transform, 0.0001))
	return {"position": sustained_position, "peak": maximum_displacement}


func _frame_rate_comparison(turns: Array[Dictionary], shots: Array[Dictionary]) -> void:
	var orientation_error := 0.0
	var position_error := 0.0
	var fov_error := 0.0
	var kick_error := 0.0
	for index in range(1, RATES.size()):
		orientation_error = maxf(orientation_error, _angle(turns[0].basis, turns[index].basis))
		position_error = maxf(position_error, (turns[0].offset as Vector3).distance_to(turns[index].offset))
		fov_error = maxf(fov_error, absf(turns[0].fov - turns[index].fov))
		kick_error = maxf(kick_error, (shots[0].position as Vector3).distance_to(shots[index].position))
	_check("30/60/144 FPS converge on the same turning camera pose", orientation_error < 0.015 and position_error < 0.15,
		"angle %.6f rad, offset %.5f m" % [orientation_error, position_error])
	_check("30/60/144 FPS produce the same speed FOV", fov_error < 0.03, "FOV difference %.5f degrees" % fov_error)
	_check("30/60/144 FPS produce the same sustained recoil offset", kick_error < 0.0001)


func _render_pose() -> void:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	# Physics is already at the next tick. The supplied render pose is between
	# ticks; following the raw hull transform would visibly advance the lens.
	_pose(ship, Basis.from_euler(Vector3(0.2, 0.3, 0.8)), Vector3(0, 0, -7))
	var render_pose := Transform3D(Basis.from_euler(Vector3(0.1, 0.15, 0.4)), Vector3(0, 0, -3.5))
	rig._update_camera(1.0 / 120.0, render_pose)
	_check("camera follows the rendered hull pose rather than the latest physics tick",
		rig.global_position.distance_to(render_pose.origin + render_pose.basis * rig.chase_offset) < 0.002)
	_check("roll follows the interpolated rotation rather than advancing to the physics tick",
		_angle(rig.global_basis, render_pose.basis) < 0.001 and _angle(rig.global_basis, ship.global_basis) > 0.2)


func _lifecycle() -> void:
	GameSettings.set_value("camera_shake", true, false)
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	var pose := _pose(ship, Basis.from_euler(Vector3(0.25, 0.6, 0.9)), Vector3(120, 45, -80))
	rig.snap_to_target()
	ship.recoil = 0.8
	rig.add_shake(2.2)
	rig._update_camera(1.0 / 30.0, pose)
	rig.toggle_mode()
	var cockpit := pose * Transform3D(Basis.IDENTITY, rig.cockpit_offset)
	_check("toggling into cockpit immediately matches position and full hull rotation",
		rig.global_position.distance_to(cockpit.origin) < 0.002 and _angle(rig.global_basis, cockpit.basis) < 0.001)
	_check("camera mode toggle clears active firing and impact feedback", _neutral(rig.camera.transform))
	rig.toggle_mode()
	_check("toggling back to chase immediately restores its offset",
		rig.global_position.distance_to(pose.origin + pose.basis * rig.chase_offset) < 0.002)
	rig.camera.fov = rig.boost_fov
	rig.add_shake(2.2)
	rig._update_camera(1.0 / 30.0, pose)
	pose = _pose(ship, Basis.from_euler(Vector3(-0.15, -0.8, 0.35)), Vector3(-500, 240, 600))
	rig.snap_to_target()
	_check("respawn snap immediately lands at the new hull",
		rig.global_position.distance_to(pose.origin + pose.basis * rig.chase_offset) < 0.002)
	_check("respawn snap clears lens feedback and boost FOV",
		_neutral(rig.camera.transform) and is_equal_approx(rig.camera.fov, rig.base_fov))
	pose.origin += Vector3(200, 80, -180)
	ship.global_transform = pose
	rig._update_camera(1.0 / 144.0, pose)
	_check("a true hull teleport snaps without flying across the arena",
		rig.global_position.distance_to(pose.origin + pose.basis * rig.chase_offset) < 0.002)
	var replacement := SHIP_SCENE.instantiate() as SpaceShip
	replacement.set_physics_process(false)
	(fixture.rig as Node).get_parent().add_child(replacement)
	replacement.set_process_unhandled_input(false)
	var replacement_pose := _pose(replacement, Basis.from_euler(Vector3(0.1, 1.2, -0.3)), Vector3(800, -160, -500))
	rig.target = replacement
	rig.snap_to_target()
	_check("a replacement ship receives an immediate fresh follow pose",
		rig.global_position.distance_to(replacement_pose.origin + replacement_pose.basis * rig.chase_offset) < 0.002)


func _damage_feedback() -> void:
	GameSettings.set_value("camera_shake", true, false)
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	rig.add_shake(2.2)
	var maximum_angle := 0.0
	var mean_angle := Vector3.ZERO
	var clean := true
	for _frame in 240:
		rig._update_camera(1.0 / 120.0, ship.global_transform)
		maximum_angle = maxf(maximum_angle, _angle(Basis.IDENTITY, rig.camera.basis))
		mean_angle += rig.camera.rotation
		clean = clean and _angle(Basis.IDENTITY, rig.global_basis) < 0.0001
	mean_angle /= 240.0
	_check("damage feedback is visible, bounded and outside the follow transform",
		clean and maximum_angle > 0.001 and maximum_angle < 0.021)
	_check("damage feedback has a small mean angular displacement", mean_angle.length() < 0.007)
	_check("damage feedback decays to a neutral lens", _neutral(rig.camera.transform, 0.0001))


func _settings_feedback() -> void:
	GameSettings.set_value("camera_shake", true, false)
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	ship.recoil = 0.8
	rig.add_shake(2.2)
	rig._update_camera(1.0 / 30.0, ship.global_transform)
	_check("feedback setting fixture exercises an active lens offset", not _neutral(rig.camera.transform, 0.001))
	GameSettings.set_value("camera_shake", false, false)
	_check("turning camera shake off immediately neutralizes the lens", _neutral(rig.camera.transform, 0.0001))
	ship.recoil = 0.0
	GameSettings.set_value("camera_shake", true, false)
	rig._update_camera(1.0 / 60.0, ship.global_transform)
	_check("reenabling camera shake does not revive old feedback", _neutral(rig.camera.transform, 0.0001))
	GameSettings.set_value("camera_shake", false, false)


func _real_fire() -> void:
	# Earlier motion fixtures leave hulls around the arena. Disable their
	# collision layers and fire from a remote, empty position so neither aim
	# ray can be shortened by an unrelated test hull.
	for root: Node3D in _fixtures:
		for child: Node in root.get_children():
			if child is SpaceShip:
				child.collision_layer = 0
	var fixture := _fixture()
	var ship = fixture.ship
	var rig: CameraRig = fixture.rig
	var incoming_velocity := Vector3(12, 4, -45)
	_pose(ship, Basis.from_euler(Vector3(0.1, 0.6, 0.2)), Vector3(10000, 10000, 10000), incoming_velocity)
	rig.snap_to_target()
	ship.aim_camera = rig.camera
	ship.aim_source = rig
	ship.weapon_spread_deg = 0.0
	ship._fire_timer = 0.0
	ship._muzzle_index = 0
	rig.camera.transform = Transform3D(Basis.from_euler(Vector3(0, 0.3, 0)), Vector3(0, 0, 0.03))
	var muzzle: Vector3 = ship.muzzle_points[0].global_position
	var reach: float = ship.bolt_speed * GameConfig.BOLT_LIFETIME
	var endpoint := rig.global_position - rig.global_basis.z * reach
	var expected_direction := (endpoint - muzzle).normalized()
	var rendered_endpoint := rig.camera.global_position - rig.camera.global_basis.z * reach
	var rendered_direction := (rendered_endpoint - muzzle).normalized()
	var existing := get_tree().get_nodes_in_group("bolts")
	Input.action_press("fire")
	ship._read_translation(1.0 / 60.0)
	Input.action_release("fire")
	var emitted: Array[LaserBolt] = []
	for node: Node in get_tree().get_nodes_in_group("bolts"):
		if node is LaserBolt and not node in existing and node.attacker == ship:
			node.set_physics_process(false)
			emitted.append(node)
	if emitted.size() != 1:
		_check("real player fire ignores cosmetic camera rotation and movement", false,
			"expected one emitted projectile, got %d" % emitted.size())
	else:
		var bolt := emitted[0]
		var expected_velocity: Vector3 = expected_direction * ship.bolt_speed + incoming_velocity * 0.2
		var velocity_error := bolt.velocity.distance_to(expected_velocity)
		_check("real player fire ignores cosmetic camera rotation and movement",
			bolt.global_position.distance_to(muzzle) < 0.001 and velocity_error < 0.005 \
				and expected_direction.dot(rendered_direction) < 0.97,
			"velocity error %.6f m/s; clean/rendered aim agreement %.6f" % [velocity_error, expected_direction.dot(rendered_direction)])
	for bolt: LaserBolt in emitted:
		bolt.queue_free()


func _freed_target() -> void:
	var fixture := _fixture()
	var ship: SpaceShip = fixture.ship
	var rig: CameraRig = fixture.rig
	ship.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	rig._process(1.0 / 60.0)
	_check("a retired target leaves the camera finite without stale access",
		rig.global_transform.is_finite() and rig.camera.global_transform.is_finite())


func _neutral(transform: Transform3D, tolerance := 0.00001) -> bool:
	return transform.origin.length() < tolerance and _angle(Basis.IDENTITY, transform.basis) < tolerance


func _angle(first: Basis, second: Basis) -> float:
	# acos(dot) loses precision for almost identical float32 rotations. The
	# relative quaternion's vector part measures small camera errors directly.
	var relative := first.orthonormalized().get_rotation_quaternion().normalized().inverse() \
		* second.orthonormalized().get_rotation_quaternion().normalized()
	return 2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w))


func _pure_rotation(basis: Basis) -> bool:
	return basis.is_finite() and absf(basis.determinant() - 1.0) < 0.00001 \
		and absf(basis.x.dot(basis.y)) < 0.00001 and absf(basis.y.dot(basis.z)) < 0.00001 \
		and absf(basis.z.dot(basis.x)) < 0.00001


func _check(caption: String, ok: bool, detail := "") -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", caption, " / " + detail if not ok and not detail.is_empty() else ""])
