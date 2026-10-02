class_name StarBody
extends StaticBody3D
## A small planet / moon that anchors a chunk of the arena.
##
## Gives the play space a sense of scale and adds a gravity well you can (and
## will) fall into, which is what makes dogfights around it interesting. Also
## acts as a hard obstacle that ends a careless boost run.

signal body_entered_well(ship: SpaceShip)

@export var radius := 55.0
## Peak acceleration at the surface. Linear falloff out to `well_radius`.
@export var gravity_strength := 34.0
@export var well_radius := 320.0
@export var orbit_speed := 0.0
@export var orbit_radius := 0.0
@export var orbit_center := Vector3.ZERO
@export var orbit_tilt := 0.0
@export var spin_speed := 0.04
@export var body_seed := 7

## 0 = moon, 1 = planet. Drives the noise profile and colour ramp.
@export var body_kind := 1

var _rng := RandomNumberGenerator.new()
var _orbit_angle := 0.0
var _orbit_axis := Vector3.UP
var _surface: MeshInstance3D
var _atmosphere: MeshInstance3D
const ATMOSPHERE_SHADER := preload("res://shaders/atmosphere.gdshader")


func _ready() -> void:
	add_to_group("bodies")
	_rng.seed = body_seed
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = GameConfig.LAYER_WORLD
	_build_shape()
	_build_visual()
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
		_surface.rotate_object_local(Vector3.UP, spin_speed * delta)


func _physics_process(_delta: float) -> void:
	_pull_ships()


## Newtonian point-mass pull, shaped so the surface pull matches the configured
## strength and falls off smoothly to zero at `well_radius`.
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
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	add_child(shape)


func _build_visual() -> void:
	_surface = get_node_or_null("Surface") as MeshInstance3D
	if _surface == null:
		_surface = MeshInstance3D.new()
		_surface.name = "Surface"
		add_child(_surface)
	_surface.mesh = MeshFactory.make_rock(radius, body_seed, body_kind + 1)

	var base: Color
	if body_kind == 0:
		base = Color.from_hsv(0.58, 0.14, 0.52).lerp(Color(0.62, 0.60, 0.58), _rng.randf() * 0.6)
	else:
		base = Color.from_hsv(0.06 + _rng.randf() * 0.06, 0.30 + _rng.randf() * 0.2, 0.44 + _rng.randf() * 0.18)
	var mat := MeshFactory.make_rock_material(base, body_seed, radius, body_kind + 1)
	_surface.material_override = mat

	# Planets have a thin limb; airless moons retain a clean silhouette.
	if body_kind == 0:
		return
	_atmosphere = get_node_or_null("Atmosphere") as MeshInstance3D
	if _atmosphere == null:
		_atmosphere = MeshInstance3D.new()
		_atmosphere.name = "Atmosphere"
		add_child(_atmosphere)
	var shell := SphereMesh.new()
	shell.radius = radius * 1.025
	shell.height = radius * 2.05
	shell.radial_segments = 64
	shell.rings = 32
	_atmosphere.mesh = shell
	var amat := ShaderMaterial.new()
	amat.shader = ATMOSPHERE_SHADER
	amat.set_shader_parameter("tint", Color(0.56, 0.67, 0.8))
	_atmosphere.material_override = amat
	_atmosphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF



## Solid bodies bounce ships rather than letting them tunnel into the surface.
func apply_impact(_force: float, _from: Vector3, _attacker: Node = null) -> void:
	pass
