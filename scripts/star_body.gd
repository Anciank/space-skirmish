class_name StarBody
extends StaticBody3D
## A dense, airless asteroid remnant used as a gravity anchor and obstacle.
## The exaggerated gravity well supports manoeuvring in the compact combat
## field. Actual planets are distant sky features, never ship-sized obstacles.

signal body_entered_well(ship: SpaceShip)

@export var radius := 55.0
## Acceleration scale for the smooth, bounded gameplay gravity field.
@export var gravity_strength := 34.0
@export var well_radius := 320.0
@export var orbit_speed := 0.0
@export var orbit_radius := 0.0
@export var orbit_center := Vector3.ZERO
@export var orbit_tilt := 0.0
@export var spin_speed := 0.04
@export var body_seed := 7

## 0 = carbonaceous companion, 1 = silicate gravity anchor.
## The two values remain compatible with saved scenes and capture tools.
@export var body_kind := 1

var _rng := RandomNumberGenerator.new()
var _orbit_angle := 0.0
var _orbit_axis := Vector3.UP
var _surface: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("bodies")
	_rng.seed = body_seed
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = GameConfig.LAYER_WORLD
	_build_visual()
	_build_shape()
	_orbit_angle = _rng.randf_range(0.0, TAU)
	if orbit_speed != 0.0 and orbit_radius > 0.0:
		# Tilt the orbital plane, then park the body on it.
		_orbit_axis = Vector3.UP.rotated(Vector3.RIGHT, orbit_tilt)
		global_position = orbit_center + Vector3(cos(_orbit_angle), 0.0, sin(_orbit_angle)).rotated(_orbit_axis, 0.0) * orbit_radius


func _process(delta: float) -> void:
	if orbit_speed != 0.0 and orbit_radius > 0.0:
		_orbit_angle = fposmod(_orbit_angle + orbit_speed * delta, TAU)
		global_position = orbit_center + Vector3.RIGHT.rotated(_orbit_axis, _orbit_angle) * orbit_radius
	if _surface != null and spin_speed != 0.0:
		# The collider turns with its visible, irregular silhouette.
		rotate_object_local(Vector3.UP, spin_speed * delta)


func _physics_process(_delta: float) -> void:
	_pull_ships()


## Radial gameplay pull, smoothly reduced to zero at `well_radius`.
func _pull_ships() -> void:
	if gravity_strength <= 0.0:
		return
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var ship := node as SpaceShip
		if ship == null or ship.dead:
			continue
		var to_body := global_position - ship.global_position
		var dist := to_body.length()
		if dist > well_radius or dist < radius * 0.9:
			continue
		var dir := to_body / dist
		var t: float = clampf(dist / well_radius, 0.0, 1.0)
		var falloff := (1.0 - t) * (1.0 - t) * (1.0 + 2.0 * t)
		ship.add_gravity(dir * gravity_strength * falloff)


func _build_shape() -> void:
	var shape := CollisionShape3D.new()
	shape.name = "BodyShape"
	shape.shape = _surface.mesh.create_convex_shape(true, false)
	add_child(shape)


func _build_visual() -> void:
	_surface = get_node_or_null("Surface") as MeshInstance3D
	if _surface == null:
		_surface = MeshInstance3D.new()
		_surface.name = "Surface"
		add_child(_surface)
	_surface.mesh = Asteroid.make_surface(radius, body_seed)

	var base: Color
	if body_kind == 0:
		base = Color(0.22, 0.235, 0.24).lerp(Color(0.31, 0.30, 0.28), _rng.randf() * 0.6)
	else:
		base = Color(0.31, 0.295, 0.26).lerp(Color(0.40, 0.37, 0.31), _rng.randf() * 0.6)
	var mat := MeshFactory.make_rock_material(base, body_seed, radius, body_kind)
	_surface.material_override = mat



## Solid bodies bounce ships rather than letting them tunnel into the surface.
func apply_impact(_force: float, _from: Vector3, _attacker: Node = null) -> void:
	pass
