extends SpaceShip
## Player-controlled fighter.
##
## Control scheme is Everspace-flavoured: the mouse aims the ship's nose
## (pitch + yaw, with roll on Q/E), WASD is Newtonian translation rather than
## turning, and the afterburner on Shift. Everything below just translates
## input into the throttle/rotation commands that `SpaceShip` consumes.

## Radians of rotation per second at full mouse deflection.
@export var look_speed := 0.0022
@export var roll_speed := 2.4
@export var auto_level_rate := 3.0
@export var mouse_sensitivity := 1.0

## Wrapped input angles in radians. Direct assignments can also set an initial
## YXZ attitude for capture tools; flight itself uses local quaternion turns.
var yaw := 0.0
var pitch := 0.0
var roll := 0.0
var _aim_orientation := Quaternion.IDENTITY
var _last_aim_angles := Vector3.ZERO

var _look_input := Vector2.ZERO
var _mouse_captured := true
var _camera_toggle_requested := false
var _banking := 0.0
## Set by the screenshot harness so captures can show the guns firing.
var _autofire := false
var aim_camera: Camera3D
## Clean follow pose; cosmetic camera feedback must not steer the guns.
var aim_source: Node3D
## The HUD supplies a preferred contact; the guns still require a close sight,
## a reachable intercept and a clear path from the active muzzle.
var preferred_aim_target: SpaceShip
var aim_assist_target: SpaceShip


func _ready() -> void:
	super()
	is_player = true
	set_process_unhandled_input(true)
	capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		var mm := event as InputEventMouseMotion
		_look_input += Vector2(mm.relative.x, mm.relative.y) * mouse_sensitivity

	if event.is_action_pressed("toggle_mouse"):
		capture_mouse(not _mouse_captured)
	elif event.is_action_pressed("toggle_camera"):
		_camera_toggle_requested = true


func capture_mouse(on: bool) -> void:
	_mouse_captured = on
	_look_input = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func respawn_at(position: Vector3, look_at_point: Vector3) -> void:
	super(position, look_at_point)
	var angles := global_basis.get_euler()
	pitch = angles.x
	yaw = angles.y
	roll = angles.z
	_aim_orientation = global_basis.orthonormalized().get_rotation_quaternion().normalized()
	_last_aim_angles = Vector3(pitch, yaw, roll)
	_look_input = Vector2.ZERO
	_camera_toggle_requested = false


func reset_for_spawn() -> void:
	super()
	preferred_aim_target = null
	aim_assist_target = null


func _physics_process(delta: float) -> void:
	if dead:
		_look_input = Vector2.ZERO
		aim_assist_target = null
		super(delta)
		return

	_aim(delta)
	_read_translation(delta)
	super(delta)


func _aim(delta: float) -> void:
	# Respawns synchronize directly from the hull. A tool may also assign its
	# initial angles; consume that pose once, rather than rebuilding Euler angles
	# every tick (which would reverse controls beyond the vertical poles).
	var supplied_angles := Vector3(pitch, yaw, roll)
	if supplied_angles != _last_aim_angles:
		_aim_orientation = Quaternion.from_euler(supplied_angles).normalized()
	var pad := Vector2(
		Input.get_axis("steer_left", "steer_right"),
		Input.get_axis("steer_up", "steer_down")
	)
	# Mouse displacement is already integrated over the frame; only the stick
	# needs delta. Keeping both in radians avoids frame-rate-dependent steering.
	var turn := pad * 2.6 * delta
	if _mouse_captured:
		turn += _look_input * look_speed * float(GameSettings.get_value("mouse_sensitivity"))
	if bool(GameSettings.get_value("invert_y")):
		turn.y *= -1.0
	_look_input = Vector2.ZERO

	var roll_cmd := 0.0
	roll_cmd += Input.get_action_strength("roll_right")
	roll_cmd -= Input.get_action_strength("roll_left")
	if bool(GameSettings.get_value("invert_roll")):
		roll_cmd *= -1.0
	if Input.is_action_pressed("recenter"):
		# Level the actual attitude, keeping its current horizontal heading.
		# Euler decomposition is only used by this explicit auto-level command.
		_aim_orientation = (_aim_orientation * Quaternion(Vector3.UP, -turn.x)).normalized()
		var level_angles := _aim_orientation.get_euler()
		yaw = level_angles.y
		pitch = move_toward(level_angles.x, 0.0, auto_level_rate * 0.5 * delta)
		roll = move_toward(level_angles.z, 0.0, auto_level_rate * delta)
		_aim_orientation = Quaternion.from_euler(Vector3(pitch, yaw, roll)).normalized()
	else:
		yaw = wrapf(yaw - turn.x, -PI, PI)
		pitch = wrapf(pitch - turn.y, -PI, PI)
		roll = wrapf(roll + roll_cmd * roll_speed * delta, -PI, PI)
		# Turn around the ship's own axes, so mouse up/right still means up/right
		# on screen while inverted, banked, or looking straight up or down.
		_aim_orientation = (_aim_orientation
			* Quaternion(Vector3.UP, -turn.x)
			* Quaternion(Vector3.RIGHT, -turn.y)
			* Quaternion(Vector3.BACK, roll_cmd * roll_speed * delta)).normalized()
	_last_aim_angles = Vector3(pitch, yaw, roll)

	var target_basis := Basis(_aim_orientation)
	var basis_now := global_transform.basis
	basis_now = basis_now.slerp(target_basis, clampf(delta * 26.0, 0.0, 1.0))
	global_transform.basis = basis_now.orthonormalized()

	# Smoothed bank value, used by the camera and HUD for readability.
	_banking = lerpf(_banking, clampf(turn.x * 12.0, -0.6, 0.6), clampf(delta * 5.0, 0.0, 1.0))


func _read_translation(delta: float) -> void:
	var fwd := Input.get_action_strength("thrust_forward") - Input.get_action_strength("thrust_back")
	var strafe := Input.get_action_strength("thrust_right") - Input.get_action_strength("thrust_left")
	var vert := Input.get_action_strength("thrust_up") - Input.get_action_strength("thrust_down")

	cmd_forward = clampf(fwd, -1.0, 1.0)
	cmd_right = clampf(strafe, -1.0, 1.0)
	cmd_up = clampf(vert, -1.0, 1.0)
	wants_boost = Input.is_action_pressed("boost") and cmd_forward > 0.1

	if Input.is_action_pressed("dampeners"):
		velocity = velocity.move_toward(Vector3.ZERO, 60.0 * delta)

	refresh_aim_assist()
	if _autofire or Input.is_action_pressed("fire"):
		fire()


## A small amount of gun tracking, not homing ammunition. Once launched, each
## round keeps its velocity and can miss if a contact changes course.
func refresh_aim_assist(preferred_target: SpaceShip = null) -> void:
	var previous := aim_assist_target
	aim_assist_target = null
	aim_point = Vector3.ZERO
	if dead or not is_instance_valid(aim_camera):
		return
	if is_instance_valid(preferred_target):
		preferred_aim_target = preferred_target
	var aim_pose := aim_source.global_transform if is_instance_valid(aim_source) else aim_camera.global_transform
	var endpoint := aim_pose.origin - aim_pose.basis.z * bolt_speed * GameConfig.BOLT_LIFETIME
	var ray := PhysicsRayQueryParameters3D.create(aim_pose.origin, endpoint, GameConfig.WEAPON_MASK)
	ray.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	aim_point = hit.get("position", endpoint)
	var muzzle := muzzle_points[_muzzle_index % muzzle_points.size()]
	if is_instance_valid(preferred_aim_target):
		var preferred_point := _assisted_point(preferred_aim_target, aim_pose, muzzle)
		if preferred_point != Vector3.ZERO:
			aim_assist_target = preferred_aim_target
			aim_point = preferred_point
			return
	var best_score := INF
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var contact := node as SpaceShip
		var point := _assisted_point(contact, aim_pose, muzzle)
		if point == Vector3.ZERO:
			continue
		var angle := (-aim_pose.basis.z).angle_to(contact.global_position - aim_pose.origin)
		# A little preference for the previous contact prevents chatter when
		# two ships pass through the sight. It never expands the assist cone.
		var score := angle - (deg_to_rad(0.3) if contact == previous else 0.0)
		if score < best_score:
			best_score = score
			aim_assist_target = contact
			aim_point = point


func _assisted_point(contact: SpaceShip, aim_pose: Transform3D, muzzle: Node3D) -> Vector3:
	if not is_instance_valid(contact) or contact == self or contact.dead or contact.team == team \
			or (contact.collision_layer & GameConfig.WEAPON_MASK) == 0:
		return Vector3.ZERO
	var from := muzzle.global_position
	var relative_velocity := contact.velocity - velocity * 0.2
	var flight := Gunnery.intercept_time(contact.global_position - from, relative_velocity, bolt_speed)
	if not is_finite(flight) or flight <= 0.0 or flight >= GameConfig.BOLT_LIFETIME:
		return Vector3.ZERO
	var point := contact.global_position + relative_velocity * flight
	var view_forward := -aim_pose.basis.z
	var contact_angle := view_forward.angle_to(contact.global_position - aim_pose.origin)
	var lead_angle := view_forward.angle_to(point - aim_pose.origin)
	if minf(contact_angle, lead_angle) > deg_to_rad(GameConfig.PLAYER_AIM_CONE_DEG):
		return Vector3.ZERO
	if (-muzzle.global_basis.z).angle_to(point - from) > deg_to_rad(GameConfig.PLAYER_GUN_CONE_DEG):
		return Vector3.ZERO
	# The contact must be visible too: a lead path around cover is not a
	# reason to acquire a ship that the pilot cannot see.
	var sight := PhysicsRayQueryParameters3D.create(aim_pose.origin, contact.global_position, GameConfig.WEAPON_MASK)
	sight.exclude = [get_rid(), contact.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
		return Vector3.ZERO
	if not Gunnery.has_clear_path(self, contact, from, point, flight):
		return Vector3.ZERO
	return point


## How far the hull is banked into the current turn, roughly -1..1.
func banking() -> float:
	return _banking


func consumes_camera_toggle() -> bool:
	var t := _camera_toggle_requested
	_camera_toggle_requested = false
	return t
