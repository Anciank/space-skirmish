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

## Smoothed aim angles (degrees) so the HUD can draw a predictive reticle.
var yaw := 0.0
var pitch := 0.0
var roll := 0.0

var _look_input := Vector2.ZERO
var _mouse_captured := true
var _camera_toggle_requested := false
var _banking := 0.0
## Set by the screenshot harness so captures can show the guns firing.
var _autofire := false


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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


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
		Input.get_action_strength("steer_x"),
		Input.get_action_strength("steer_y")
	)
	# Mouse delta is in pixels; the pad stick is already 0..1.
	var turn := Vector2.ZERO
	if _mouse_captured:
		turn.x = _look_input.x * look_speed * 60.0
		turn.y = _look_input.y * look_speed * 60.0
	if pad.length_squared() > 0.0:
		turn.x += pad.x * look_speed * 60.0 * 2.6
		turn.y += pad.y * look_speed * 60.0 * 2.6
	_look_input = Vector2.ZERO

	yaw = wrapf(yaw - deg_to_rad(turn.x), -180.0, 180.0)
	pitch = clampf(pitch - deg_to_rad(turn.y), -89.0, 89.0)

	var roll_cmd := 0.0
	roll_cmd += Input.get_action_strength("roll_right")
	roll_cmd -= Input.get_action_strength("roll_left")
	if Input.is_action_pressed("recenter"):
		roll = move_toward(roll, 0.0, deg_to_rad(auto_level_rate * 110.0) * delta)
		pitch = move_toward(pitch, 0.0, deg_to_rad(auto_level_rate * 55.0) * delta)
	else:
		roll = wrapf(roll + deg_to_rad(roll_cmd * roll_speed * 95.0) * delta, -180.0, 180.0)

	var q := Quaternion.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), deg_to_rad(roll)))
	var target_basis := Basis(q)
	var basis_now := global_transform.basis
	basis_now = basis_now.slerp(target_basis, clampf(delta * 26.0, 0.0, 1.0))
	global_transform.basis = basis_now.orthonormalized()

	# Smoothed bank value, used by the camera and HUD for readability.
	_banking = lerpf(_banking, clampf(turn.x * 0.03, -0.6, 0.6), clampf(delta * 5.0, 0.0, 1.0))


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
		fire()


## How far the hull is banked into the current turn, roughly -1..1.
func banking() -> float:
	return _banking


func consumes_camera_toggle() -> bool:
	var t := _camera_toggle_requested
	_camera_toggle_requested = false
	return t
