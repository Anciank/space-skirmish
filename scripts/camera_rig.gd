class_name CameraRig
extends Node3D
## Third-person chase camera (with a cockpit view on V).
##
## Sits behind and above the ship, follows the ship's orientation with a little
## lag, widens the FOV under boost, punches on recoil, and pulls in when
## something solid would otherwise clip the lens.

@export var chase_offset := Vector3(0.0, 2.9, 11.0)
@export var cockpit_offset := Vector3(0.0, 0.9, -0.6)
@export var position_stiffness := 11.0
@export var rotation_stiffness := 14.0
@export var base_fov := 84.0
@export var boost_fov := 100.0
@export var speed_fov_gain := 22.0
## Beyond this distance from the ship the rig teleports instead of easing.
## A respawn can move a ship hundreds of metres in one frame, and lerping from
## there flies the camera through the arena — and back out again — before the
## view settles anywhere useful.
@export var max_follow_distance := 40.0

var target: SpaceShip = null
var mode_chase := true

@onready var camera: Camera3D = $Camera3D
@onready var stars: Starfield = $Starfield

var _shake := 0.0
var _shake_seed := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_shake_seed = _rng.randf() * 100.0
	GameSettings.changed.connect(_on_settings_changed)
	_on_settings_changed("field_of_view")
	camera.fov = base_fov


func _on_settings_changed(_key: String) -> void:
	base_fov = float(GameSettings.get_value("field_of_view"))
	boost_fov = minf(base_fov + 16.0, 115.0)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		if stars != null:
			stars.global_position = camera.global_position
		return

	var offset := chase_offset if mode_chase else cockpit_offset
	var ship_basis := target.global_transform.basis
	var desired := target.global_position + ship_basis * offset

	# Pull the camera in if a planet or rock is between it and the ship.
	if mode_chase:
		desired = _avoid_obstacles(target.global_position, desired)

	var t: float = clampf(position_stiffness * delta, 0.0, 1.0)
	if global_position.distance_to(target.global_position) > max_follow_distance:
		t = 1.0
	global_position = global_position.lerp(desired, t)

	# Chase view: follow the ship's full aim (pitch + yaw) but only carry ~35% of
	# its roll, so hard rolls bank the camera without disorienting the horizon.
	# Cockpit view: rigidly match the hull.
	var want_basis: Basis
	if mode_chase:
		var fwd := -ship_basis.z
		var up := ship_basis.y.lerp(Vector3.UP, 0.65)
		if absf(up.normalized().dot(fwd.normalized())) > 0.985:
			up = ship_basis.y
		# Basis.looking_at() aims -Z at the direction we hand it.
		want_basis = Basis.looking_at(fwd, up)
	else:
		want_basis = ship_basis
	var r: float = clampf(rotation_stiffness * delta, 0.0, 1.0)
	# Fast render rates accumulate rounding error through thousands of tiny
	# slerps and shake rotations. Restore a pure rotation before interpolation.
	var blended := global_transform.basis.orthonormalized().slerp(want_basis.orthonormalized(), r)

	# Recoil + explosion shake.
	_shake = maxf(_shake - delta * 2.4, 0.0)
	var shake_amt := _shake * 0.55 + target.recoil * 0.9
	if shake_amt > 0.001 and bool(GameSettings.get_value("camera_shake")):
		var t2 := float(Time.get_ticks_msec()) * 0.02 + _shake_seed
		blended = blended.rotated(Vector3.RIGHT, sin(t2 * 1.7) * 0.01 * shake_amt)
		blended = blended.rotated(Vector3.UP, cos(t2 * 2.3) * 0.01 * shake_amt)
		blended = blended.rotated(Vector3.BACK, sin(t2 * 3.1) * 0.014 * shake_amt)

	global_transform.basis = blended.orthonormalized()

	# FOV: boost + speed stretch.
	var speed_t: float = clampf(target.speed / GameConfig.SPEED_BOOST, 0.0, 1.0)
	var want_fov := base_fov + speed_t * speed_fov_gain
	if target.boosting:
		want_fov = boost_fov + speed_t * 8.0
	camera.fov = lerpf(camera.fov, want_fov, clampf(delta * 6.0, 0.0, 1.0))

	# Stars ride with the camera so the field has zero parallax.
	if stars != null:
		stars.global_position = camera.global_position

	# Hide our own hull in cockpit view.
	var model := target.get_node_or_null("ShipModel") as Node3D
	if model != null:
		model.visible = mode_chase


func _avoid_obstacles(origin: Vector3, desired: Vector3) -> Vector3:
	var to_cam := desired - origin
	var dist := to_cam.length()
	if dist < 0.05:
		return desired
	var query := PhysicsRayQueryParameters3D.create(origin, desired, GameConfig.LAYER_WORLD | GameConfig.LAYER_ROCK)
	query.exclude = [target.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	# Stop a little short of the surface so we never end up inside a planet.
	var point: Vector3 = hit.get("position", origin)
	var clear: float = maxf(point.distance_to(origin) - 1.4, 1.6)
	return origin + to_cam.normalized() * minf(clear, dist)


## Jumps the camera straight to its ideal follow pose, skipping the lerp. Used
## after teleporting the ship (respawn, tooling) so the view does not sweep
## across the arena to catch up.
func snap_to_target() -> void:
	if target == null or not is_instance_valid(target):
		return
	var offset := chase_offset if mode_chase else cockpit_offset
	global_position = target.global_position + target.global_transform.basis * offset
	_apply_basis_immediately()
	camera.fov = base_fov


func _apply_basis_immediately() -> void:
	var ship_basis := target.global_transform.basis
	var want: Basis
	if mode_chase:
		var fwd := -ship_basis.z
		var up := ship_basis.y.lerp(Vector3.UP, 0.65)
		if absf(up.normalized().dot(fwd.normalized())) > 0.985:
			up = ship_basis.y
		want = Basis.looking_at(fwd, up)
	else:
		want = ship_basis
	global_transform.basis = want


func add_shake(amount: float) -> void:
	_shake = minf(2.5, _shake + amount)


func toggle_mode() -> void:
	mode_chase = not mode_chase
	# Snap so the view does not sweep through the ship on toggle.
	if target != null and is_instance_valid(target):
		var offset := chase_offset if mode_chase else cockpit_offset
		global_position = target.global_position + target.global_transform.basis * offset
