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

## Aim angles in radians, matching Basis.get_euler() and Quaternion.from_euler().
var yaw := 0.0
var pitch := 0.0
var roll := 0.0

var _look_input := Vector2.ZERO
var _mouse_captured := true
var _camera_toggle_requested := false
var _banking := 0.0
## Set by the screenshot harness so captures can show the guns firing.
var _autofire := false
var aim_camera: Camera3D


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
	_look_input = Vector2.ZERO
	_camera_toggle_requested = false


func _physics_process(delta: float) -> void:
	if dead:
		_look_input = Vector2.ZERO
		super(delta)
		return

	_aim(delta)
	_read_translation(delta)
	super(delta)


func _aim(delta: float) -> void:
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

	yaw = wrapf(yaw - turn.x, -PI, PI)
	pitch = clampf(pitch - turn.y, deg_to_rad(-89.0), deg_to_rad(89.0))

	var roll_cmd := 0.0
	roll_cmd += Input.get_action_strength("roll_right")
	roll_cmd -= Input.get_action_strength("roll_left")
	if Input.is_action_pressed("recenter"):
		roll = move_toward(roll, 0.0, auto_level_rate * delta)
		pitch = move_toward(pitch, 0.0, auto_level_rate * 0.5 * delta)
	else:
		roll = wrapf(roll + roll_cmd * roll_speed * delta, -PI, PI)

	var q := Quaternion.from_euler(Vector3(pitch, yaw, roll))
	var target_basis := Basis(q)
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

	if _autofire or Input.is_action_pressed("fire"):
		if is_instance_valid(aim_camera):
			var origin := aim_camera.global_position
			var endpoint := origin - aim_camera.global_basis.z * bolt_speed * GameConfig.BOLT_LIFETIME
			var ray := PhysicsRayQueryParameters3D.create(origin, endpoint, GameConfig.WEAPON_MASK)
			ray.exclude = [get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			aim_point = hit.get("position", endpoint)
		fire()


## How far the hull is banked into the current turn, roughly -1..1.
func banking() -> float:
	return _banking


func consumes_camera_toggle() -> bool:
	var t := _camera_toggle_requested
	_camera_toggle_requested = false
	return t
