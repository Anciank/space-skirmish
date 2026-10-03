class_name CameraRig
extends Node3D
## Smooth chase/cockpit camera. The rig follows a clean rendered ship pose;
## temporary impact and recoil feedback belongs only to the child camera.

@export var chase_offset := Vector3(0.0, 2.9, 11.0)
@export var cockpit_offset := Vector3(0.0, 0.9, -0.6)
@export var position_stiffness := 11.0
@export var base_fov := 84.0
@export var boost_fov := 100.0
@export var speed_fov_gain := 22.0
## A discontinuity in the target's position indicates a teleport, rather
## than ordinary chase-camera lag at high speed.
@export var max_follow_distance := 40.0

const RECOIL_TRAVEL := 0.035
const RECOIL_RESPONSE := 24.0

var target: SpaceShip = null
var mode_chase := true

@onready var camera: Camera3D = $Camera3D
@onready var stars: Starfield = $Starfield

var _shake := 0.0
var _feedback_time := 0.0
var _recoil_offset := 0.0
var _last_target_position := Vector3.ZERO
var _follow_offset := Vector3.ZERO
var _follow_target_id := 0
var _has_follow_pose := false


func _ready() -> void:
	# This branch is updated once per rendered frame, using the ship's already
	# interpolated pose. Interpolating it again would introduce another delay.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	GameSettings.changed.connect(_on_settings_changed)
	_on_settings_changed("field_of_view")
	camera.fov = base_fov


func _on_settings_changed(_key: String) -> void:
	base_fov = float(GameSettings.get_value("field_of_view"))
	boost_fov = minf(base_fov + 16.0, 115.0)
	if not bool(GameSettings.get_value("camera_shake")):
		_clear_feedback()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		_has_follow_pose = false
		_clear_feedback()
		_update_stars()
		return
	_update_camera(delta, target.get_global_transform_interpolated())


func _update_camera(delta: float, ship_pose: Transform3D) -> void:
	if not is_instance_valid(target):
		return
	var ship_basis := ship_pose.basis.orthonormalized()
	var offset := chase_offset if mode_chase else cockpit_offset
	if mode_chase:
		offset = _clear_follow_offset(ship_pose.origin, ship_basis, offset)

	var ship_motion := ship_pose.origin - _last_target_position
	var snap := not _has_follow_pose or _follow_target_id != target.get_instance_id() \
		or ship_motion.length() > max_follow_distance
	if snap or not mode_chase:
		_follow_offset = offset
		if snap:
			_clear_feedback()
	else:
		# Carry translation AND rotation from the interpolated hull. Keeping
		# the follow offset in ship space avoids orbit lag during a full roll.
		# Only obstacle clearance eases; the ship already supplies smooth turns.
		_follow_offset = _follow_offset.lerp(offset, 1.0 - exp(-position_stiffness * delta))
	global_transform = Transform3D(ship_basis, ship_pose.origin + ship_basis * _follow_offset)
	_last_target_position = ship_pose.origin
	_follow_target_id = target.get_instance_id()
	_has_follow_pose = true

	_update_feedback(delta)
	var speed_t := clampf(target.speed / GameConfig.SPEED_BOOST, 0.0, 1.0)
	var want_fov := base_fov + speed_t * speed_fov_gain
	if target.boosting:
		want_fov = boost_fov + speed_t * 8.0
	camera.fov = lerpf(camera.fov, want_fov, 1.0 - exp(-6.0 * delta))
	_update_stars()
	target.model.visible = mode_chase


func _update_feedback(delta: float) -> void:
	_feedback_time += delta
	if not bool(GameSettings.get_value("camera_shake")):
		_clear_feedback()
		return
	_shake = maxf(_shake - delta * 2.4, 0.0)
	# Gun weight is a tiny, damped backwards movement. Firing does not rotate
	# the view, and feedback is rebuilt from identity instead of accumulating.
	_recoil_offset = lerpf(_recoil_offset, clampf(target.recoil, 0.0, 1.0) * RECOIL_TRAVEL,
		1.0 - exp(-RECOIL_RESPONSE * delta))
	var angles := Vector3(
		sin(_feedback_time * 17.0) * 0.004,
		cos(_feedback_time * 21.0) * 0.004,
		sin(_feedback_time * 25.0) * 0.0055
	) * _shake
	camera.transform = Transform3D(Basis.from_euler(angles), Vector3(0, 0, _recoil_offset))


func _clear_feedback() -> void:
	_shake = 0.0
	_recoil_offset = 0.0
	camera.transform = Transform3D.IDENTITY


func _update_stars() -> void:
	if stars != null:
		stars.global_position = camera.global_position


func _clear_follow_offset(origin: Vector3, ship_basis: Basis, offset: Vector3) -> Vector3:
	var distance := offset.length()
	if distance < 0.05:
		return offset
	var desired := origin + ship_basis * offset
	var query := PhysicsRayQueryParameters3D.create(origin, desired, GameConfig.LAYER_WORLD | GameConfig.LAYER_ROCK)
	query.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return offset
	var point: Vector3 = hit.get("position", origin)
	var clear := maxf(point.distance_to(origin) - 1.4, 1.6)
	return offset * minf(clear / distance, 1.0)


func snap_to_target() -> void:
	if not is_instance_valid(target):
		return
	# Prime the client interpolation history before resetting a teleport or
	# camera-mode switch, so the renderer and camera begin from the same pose.
	target.get_global_transform_interpolated()
	target.reset_physics_interpolation()
	var pose := target.global_transform
	var ship_basis := pose.basis.orthonormalized()
	var offset := chase_offset if mode_chase else cockpit_offset
	if mode_chase:
		offset = _clear_follow_offset(pose.origin, ship_basis, offset)
	_follow_offset = offset
	global_transform = Transform3D(ship_basis, pose.origin + ship_basis * _follow_offset)
	_last_target_position = pose.origin
	_follow_target_id = target.get_instance_id()
	_has_follow_pose = true
	_clear_feedback()
	camera.fov = base_fov
	target.model.visible = mode_chase
	_update_stars()


func add_shake(amount: float) -> void:
	if bool(GameSettings.get_value("camera_shake")):
		_shake = clampf(_shake + amount, 0.0, 2.5)


func toggle_mode() -> void:
	mode_chase = not mode_chase
	snap_to_target()
