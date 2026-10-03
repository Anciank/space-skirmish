extends Node
## Native rendered-frame camera probe. Use the same scene for both camera versions.
## godot --audio-driver Dummy res://tools/camera_review.tscn -- /tmp/camera-review

const WARMUP_SECONDS := 1.0
const SAMPLE_SECONDS := 3.0
const ROLL_SAMPLE_SECONDS := 6.0
const FLIGHT_VELOCITY := Vector3(45.0, 0.0, -65.0)
const PHASES := ["constant_speed", "sustained_fire", "roll_left_vertical", "roll_right_vertical_fire",
	"pitch_up_loop", "pitch_down_loop_inverted"]

var _main: Node3D
var _player: SpaceShip
var _out := "/tmp/camera-review"
var _preferences: Dictionary
var _physics_tps := 60
var _fps_cap := 0
var _phase := ""
var _phase_started := 0
var _started := 0
var _pending: Dictionary = {}
var _samples: Array[Dictionary] = []
var _report: Dictionary = {}
var _finished := false
var _shots := 0
var _settings_file := ""
var _settings_hash := ""
var _settings_existed := false
var _phase_index := 0


func _ready() -> void:
	process_priority = 100
	if DisplayServer.get_name() == "headless":
		push_error("Camera review requires a native rendered window.")
		await Sfx.finish_audio()
		get_tree().quit(1)
		return
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_out = arguments[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_preferences = GameSettings.values.duplicate(true)
	_settings_file = ProjectSettings.globalize_path(GameSettings.storage_path)
	_settings_existed = FileAccess.file_exists(_settings_file)
	_settings_hash = FileAccess.get_sha256(_settings_file) if _settings_existed else ""
	GameSettings.reset_to_defaults(false)
	_physics_tps = Engine.physics_ticks_per_second
	_fps_cap = Engine.max_fps
	Engine.physics_ticks_per_second = 20
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.ally_count = 0
	_main.enemy_count = 0
	_main.start_in_menu = false
	_main.pause_on_focus_loss = false
	add_child(_main)
	_main.set_process(false)
	_main.hud.hide()
	GameMatch.running = false
	_player = _main.player
	_player.set_physics_process(false)
	_player.capture_mouse(false)
	_player.collision_layer = 0
	_player.collision_mask = 0
	_player.weapon_fired.connect(func(): _shots += 1)
	# Keep lighting and scenery visible while disabling their forces and contact.
	for node: Node in _main.arena.find_children("*", "", true, false):
		node.set_process(false)
		node.set_physics_process(false)
		if node is CollisionObject3D:
			(node as CollisionObject3D).collision_layer = 0
			(node as CollisionObject3D).collision_mask = 0
		if node is RigidBody3D:
			(node as RigidBody3D).freeze = true
	_main.arena.set_process(false)
	_main.arena.set_physics_process(false)
	RenderingServer.frame_post_draw.connect(_on_rendered_frame)
	_started = Time.get_ticks_usec()
	_set_phase(PHASES[0])
	DisplayServer.window_move_to_foreground()


func _set_phase(caption: String) -> void:
	_phase = caption
	_phase_started = Time.get_ticks_usec()
	_samples.clear()
	_pending.clear()
	_shots = 0
	_main._clear_effects()
	for action: String in ["roll_left", "roll_right", "steer_right", "steer_up"]:
		Input.action_release(action)
	GameSettings.set_value("camera_shake", "fire" in caption, false)
	GameSettings.set_value("invert_y", caption == "pitch_down_loop_inverted", false)
	_player.pitch = 0.0
	_player.yaw = 0.0
	_player.roll = 0.0
	if caption.begins_with("roll_"):
		_player.pitch = deg_to_rad(89.0 if caption == "roll_left_vertical" else -89.0)
		_player.yaw = 0.7
		Input.action_press("roll_left" if caption == "roll_left_vertical" else "roll_right")
		if caption == "roll_right_vertical_fire":
			Input.action_press("steer_right")
	elif caption.begins_with("pitch_"):
		_player.yaw = 0.7
		_player.roll = 0.9
		Input.action_press("steer_up")
	_player.global_transform = Transform3D(
		Basis.from_euler(Vector3(_player.pitch, _player.yaw, _player.roll)), Vector3(0, 430, 0))
	_player.velocity = FLIGHT_VELOCITY if caption == "constant_speed" else Vector3.ZERO
	_player.speed = _player.velocity.length()
	_player.recoil = 0.0
	_player._fire_timer = 0.0
	_player.cmd_forward = 0.0
	_player.cmd_right = 0.0
	_player.cmd_up = 0.0
	_player.throttle = 0.0
	_player.boosting = false
	_player.reset_physics_interpolation()
	_main.rig._shake = 0.0
	_main.rig.camera.transform = Transform3D.IDENTITY
	_main.rig.snap_to_target()
	print("camera phase: " + caption)


func _physics_process(delta: float) -> void:
	if _phase.is_empty() or _finished:
		return
	_player.recoil = move_toward(_player.recoil, 0.0, delta * 6.0)
	_player._update_weapon(delta)
	if _phase == "constant_speed":
		_player.velocity = FLIGHT_VELOCITY
		_player.global_position += FLIGHT_VELOCITY * delta
	elif _phase == "sustained_fire":
		# Actual rounds and muzzle effects; hold the hull still to isolate feedback.
		_player.fire()
		_player.velocity = Vector3.ZERO
	else:
		_player._aim(delta)
		if "fire" in _phase:
			_player.fire()
		_player.velocity = Vector3.ZERO
	_player.speed = _player.velocity.length()
	_player._update_visuals(delta)


func _process(_delta: float) -> void:
	if _phase.is_empty() or _finished:
		return
	var now := Time.get_ticks_usec()
	if now - _started > 45000000:
		push_error("Native camera review timed out waiting for rendered frames.")
		_finish(1)
		return
	var hull_pose := _player.hull_mesh.get_global_transform_interpolated()
	var ship_pose := _player.get_global_transform_interpolated()
	var camera: Camera3D = _main.rig.camera
	var center := hull_pose * _player.hull_mesh.get_aabb().get_center()
	var pixel := camera.unproject_position(center)
	var hull_rotation := ship_pose.basis.orthonormalized().get_rotation_quaternion()
	var camera_rotation := camera.global_basis.orthonormalized().get_rotation_quaternion()
	_pending = {
		"time_usec": now,
		"pixel": [pixel.x, pixel.y],
		"orientation_deg": rad_to_deg(_rotation_distance(hull_rotation, camera_rotation)),
		"forward_deg": rad_to_deg((-ship_pose.basis.z).angle_to(-camera.global_basis.z)),
		"fov": camera.fov,
		"ship_position": [ship_pose.origin.x, ship_pose.origin.y, ship_pose.origin.z],
		"recoil": _player.recoil,
		"ship_quaternion": [hull_rotation.x, hull_rotation.y, hull_rotation.z, hull_rotation.w],
		"camera_quaternion": [camera_rotation.x, camera_rotation.y, camera_rotation.z, camera_rotation.w],
	}


func _on_rendered_frame() -> void:
	if _finished or _pending.is_empty():
		return
	var elapsed := float(int(_pending.time_usec) - _phase_started) / 1000000.0
	if elapsed < WARMUP_SECONDS:
		return
	var looping := _phase.begins_with("roll_") or _phase.begins_with("pitch_")
	var duration := ROLL_SAMPLE_SECONDS if looping else SAMPLE_SECONDS
	if elapsed < WARMUP_SECONDS + duration:
		_samples.append(_pending.duplicate(true))
		return
	_report[_phase] = _summarize()
	var picture := get_viewport().get_texture().get_image()
	var error := picture.save_png(_out.path_join(_phase + ".png"))
	_report[_phase]["screenshot_error"] = error
	_report[_phase]["resolution"] = [picture.get_width(), picture.get_height()]
	var brief: Dictionary = _report[_phase].duplicate()
	brief.erase("samples")
	print("camera sample " + _phase + ": " + JSON.stringify(brief))
	_phase_index += 1
	if _phase_index < PHASES.size():
		_set_phase(PHASES[_phase_index])
	else:
		_report["renderer"] = RenderingServer.get_current_rendering_method()
		_report["adapter"] = RenderingServer.get_video_adapter_name()
		_report["physics_tps"] = Engine.physics_ticks_per_second
		_report["render_fps_cap"] = Engine.max_fps
		_report["physics_interpolation"] = ProjectSettings.get_setting("physics/common/physics_interpolation", false)
		_report["ship_physics_interpolation_enabled"] = _player.is_physics_interpolated_and_enabled()
		_report["hull_physics_interpolation_enabled"] = _player.hull_mesh.is_physics_interpolated_and_enabled()
		_report["camera_rig_physics_interpolation_enabled"] = _main.rig.is_physics_interpolated_and_enabled()
		_report["warmup_seconds"] = WARMUP_SECONDS
		_report["sample_seconds"] = SAMPLE_SECONDS
		_report["roll_sample_seconds"] = ROLL_SAMPLE_SECONDS
		var ok: bool = _report.constant_speed.frames >= 60 and _report.sustained_fire.frames >= 60 \
			and _report.sustained_fire.shots >= 20 and error == OK \
			and _report.constant_speed.screenshot_error == OK \
			and _report.ship_physics_interpolation_enabled == _report.physics_interpolation \
			and _report.hull_physics_interpolation_enabled == _report.physics_interpolation
		for phase: String in PHASES:
			var sample: Dictionary = _report[phase]
			ok = ok and sample.frames >= 60 and sample.screenshot_error == OK \
				and sample.camera_hull_orientation_deg.max < 0.1 \
				and sample.relative_rotation_step_deg.max < 0.1
			if phase.begins_with("roll_") or phase.begins_with("pitch_"):
				ok = ok and sample.center_stddev_px < 1.0 \
					and sample.successive_step_px.max < 1.0
		_finish(0 if ok else 1)


func _summarize() -> Dictionary:
	var positions: Array[Vector2] = []
	var steps: Array[float] = []
	var frame_ms: Array[float] = []
	var angles: Array[float] = []
	var forward_angles: Array[float] = []
	var relative_steps: Array[float] = []
	var previous_relative := Quaternion.IDENTITY
	var center := Vector2.ZERO
	for sample: Dictionary in _samples:
		var pixel := Vector2(sample.pixel[0], sample.pixel[1])
		if not positions.is_empty():
			steps.append(pixel.distance_to(positions[-1]))
			frame_ms.append(float(int(sample.time_usec) - int(_samples[positions.size() - 1].time_usec)) / 1000.0)
		positions.append(pixel)
		center += pixel
		angles.append(float(sample.orientation_deg))
		forward_angles.append(float(sample.forward_deg))
		var ship_q := Quaternion(sample.ship_quaternion[0], sample.ship_quaternion[1],
			sample.ship_quaternion[2], sample.ship_quaternion[3])
		var camera_q := Quaternion(sample.camera_quaternion[0], sample.camera_quaternion[1],
			sample.camera_quaternion[2], sample.camera_quaternion[3])
		var relative := ship_q.inverse() * camera_q
		if positions.size() > 1:
			relative_steps.append(rad_to_deg(_rotation_distance(previous_relative, relative)))
		previous_relative = relative
	center /= maxf(1.0, positions.size())
	var variance := Vector2.ZERO
	for position: Vector2 in positions:
		var offset := position - center
		variance += Vector2(offset.x * offset.x, offset.y * offset.y)
	variance /= maxf(1.0, positions.size())
	return {
		"frames": positions.size(),
		"shots": _shots,
		"center_mean_px": [center.x, center.y],
		"center_variance_px2": [variance.x, variance.y],
		"center_stddev_px": sqrt(variance.x + variance.y),
		"successive_step_px": _statistics(steps),
		"frame_ms": _statistics(frame_ms),
		"camera_hull_orientation_deg": _statistics(angles),
		"camera_hull_forward_deg": _statistics(forward_angles),
		"relative_rotation_step_deg": _statistics(relative_steps),
		"samples": _samples.duplicate(true),
	}


func _rotation_distance(first: Quaternion, second: Quaternion) -> float:
	var relative := first.normalized().inverse() * second.normalized()
	return 2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w))


func _statistics(values: Array[float]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var mean := 0.0
	var squares := 0.0
	for value: float in values:
		mean += value
		squares += value * value
	var count := maxf(1.0, values.size())
	mean /= count
	var variance := maxf(0.0, squares / count - mean * mean)
	return {
		"mean": mean, "variance": variance, "stddev": sqrt(variance),
		"rms": sqrt(squares / count),
		"p95": sorted[clampi(int(ceil(values.size() * 0.95)) - 1, 0, sorted.size() - 1)] if not sorted.is_empty() else 0.0,
		"max": sorted[-1] if not sorted.is_empty() else 0.0,
	}


func _finish(exit_code: int) -> void:
	if _finished:
		return
	_finished = true
	_phase = ""
	for action: String in ["roll_left", "roll_right", "steer_right", "steer_up"]:
		Input.action_release(action)
	GameSettings.values = _preferences
	GameSettings._apply()
	_report["settings_unchanged"] = FileAccess.file_exists(_settings_file) == _settings_existed \
		and (not _settings_existed or FileAccess.get_sha256(_settings_file) == _settings_hash)
	var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "\t") + "\n")
		file.close()
	else:
		push_error("Cannot write camera review report: " + _out)
		exit_code = 1
	if not _report.settings_unchanged:
		push_error("Camera review changed the saved preferences.")
		exit_code = 1
	_main._show_title()
	_main.queue_free()
	await get_tree().process_frame
	Engine.physics_ticks_per_second = _physics_tps
	Engine.max_fps = _fps_cap
	await Sfx.finish_audio()
	print("--- camera review: exit " + str(exit_code) + " ---")
	get_tree().quit(exit_code)
