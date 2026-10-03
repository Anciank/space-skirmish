class_name Asteroid
extends RigidBody3D
## Tumbling destructible rock. Also an obstacle: ramming one hurts whichever
## body is moving faster into the contact. Small rocks shatter quickly, big
## ones soak a lot of fire and the arena respawns them after a while.

signal destroyed(asteroid: Asteroid)

const RESPAWN_DELAY := 14.0
const RESPAWN_RETRY_DELAY := 1.0
const RESPAWN_ATTEMPTS := 96
const SPAWN_RADIUS_FACTOR := 1.3
const SPAWN_CLEARANCE := 12.0

@export var radius := 6.0
@export var respawnable := true
@export var rock_seed := 0

var hp := 60.0
var dead := false

var _spawn_point := Vector3.ZERO
var _respawn_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _home := Vector3.ZERO


func _ready() -> void:
	add_to_group("rocks")
	_rng.seed = rock_seed
	_home = global_position
	_spawn_point = global_position
	hp = radius * radius * 2.2
	_build_visual()
	_ensure_shape()
	# Random tumbling: constant slow spin plus a bit of linear drift.
	angular_velocity = Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0)
	).normalized() * _rng.randf_range(0.05, 0.32)
	linear_damp = 0.0
	angular_damp = 0.05
	gravity_scale = 0.0


func _ensure_shape() -> void:
	var shape := get_node_or_null("RockShape") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new()
		shape.name = "RockShape"
		add_child(shape)
	# Each rock needs its own hull. Mutating the packed scene's shared sphere
	# gave every rock the radius of the last one built, regardless of its mesh.
	var visual := get_node("RockMesh") as MeshInstance3D
	shape.shape = visual.mesh.create_convex_shape(true, false)


func _build_visual() -> void:
	var mesh := get_node_or_null("RockMesh") as MeshInstance3D
	if mesh == null:
		mesh = MeshInstance3D.new()
		mesh.name = "RockMesh"
		add_child(mesh)
	mesh.mesh = make_surface(radius, rock_seed)

	var base := Color(0.23, 0.235, 0.23).lerp(Color(0.37, 0.34, 0.29), _rng.randf())
	var mat := MeshFactory.make_rock_material(base, rock_seed, radius)
	mesh.material_override = mat


## A dense, smoothly shaded geological surface with an irregular outline.
## Local gravity anchors use this same construction, so every local obstacle
## has believable rock scale and its convex collision hull follows the mesh.
static func make_surface(size: float, seed_value: int) -> ArrayMesh:
	var broad := FastNoiseLite.new()
	broad.seed = seed_value
	broad.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.frequency = 1.75
	broad.fractal_octaves = 3
	broad.fractal_gain = 0.52
	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 977
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 6.0
	detail.fractal_octaves = 2
	var shape_rng := RandomNumberGenerator.new()
	shape_rng.seed = seed_value
	var stretch := Vector3(
		shape_rng.randf_range(0.93, 1.08),
		shape_rng.randf_range(0.79, 0.97),
		shape_rng.randf_range(0.93, 1.10))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 56
	sphere.rings = 32
	var arrays := sphere.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	for vertex: Vector3 in vertices:
		var direction := vertex.normalized()
		var relief := broad.get_noise_3dv(direction) * 0.27
		relief += detail.get_noise_3dv(direction) * 0.025
		surface.add_vertex(direction * size * (1.0 + relief) * stretch)
	for index: int in indices:
		surface.add_index(index)
	surface.generate_normals()
	return surface.commit()


func _process(delta: float) -> void:
	if _respawn_timer > 0.0:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_revive()


## Called by ships when they collide with this rock.
func apply_impact(force: float, from_position: Vector3, attacker: Node = null) -> void:
	var dir := (global_position - from_position)
	if dir.length_squared() < 0.0001:
		dir = Vector3.UP
	apply_central_impulse(dir.normalized() * force * 0.9)
	apply_torque_impulse(Vector3(_rng.randfn(-1.0, 1.0), _rng.randfn(-1.0, 1.0), _rng.randfn(-1.0, 1.0)) * force * 0.3)


func take_damage(amount: float, attacker: Node = null, world_pos := Vector3.ZERO, knockback := Vector3.ZERO) -> void:
	if dead:
		return
	hp -= amount
	if knockback.length_squared() > 0.0001:
		apply_central_impulse(knockback * 12.0)
	if world_pos != Vector3.ZERO:
		var effects := GameConfig.effects_parent(self)
		var spark := Spark.new()
		effects.add_child(spark)
		spark.setup(world_pos, (world_pos - global_position).normalized(), Color(0.58, 0.52, 0.43))
	if hp <= 0.0:
		_shatter(attacker)


func _shatter(_attacker: Node) -> void:
	if dead:
		return
	dead = true
	destroyed.emit(self)
	visible = false
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	set_deferred("freeze", true)

	var fx := ExplosionFx.new()
	fx.radius = radius * 2.2
	fx.tint = Color(0.85, 0.62, 0.40)
	fx.rock_debris = true
	GameConfig.effects_parent(self).add_child(fx)
	fx.global_position = global_position
	Sfx.play_at("explosion", global_position, -3.0, randf_range(-0.4, 0.4), 1600.0)

	if respawnable:
		_respawn_timer = RESPAWN_DELAY
	else:
		queue_free()


func _revive() -> void:
	var candidate := _find_respawn_position()
	if not candidate.is_finite():
		# A crowded field can temporarily have no safe site. Stay out of physics
		# and retry later rather than appearing inside another solid or a pilot.
		dead = true
		visible = false
		collision_layer = 0
		collision_mask = 0
		freeze = true
		_respawn_timer = RESPAWN_RETRY_DELAY
		return
	_respawn_timer = 0.0
	dead = false
	hp = radius * radius * 2.2
	global_position = candidate
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3(
		_rng.randfn(-1.0, 1.0), _rng.randfn(-1.0, 1.0), _rng.randfn(-1.0, 1.0)
	).normalized() * _rng.randf_range(0.05, 0.3)
	rotation = Vector3(_rng.randf_range(0, TAU), _rng.randf_range(0, TAU), _rng.randf_range(0, TAU))
	visible = true
	collision_layer = GameConfig.LAYER_ROCK
	collision_mask = GameConfig.ROCK_MASK
	freeze = false
	reset_physics_interpolation()


## Drift to a fresh, clear site using the seeded rock RNG.
func _find_respawn_position() -> Vector3:
	for _attempt in RESPAWN_ATTEMPTS:
		var direction := Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0))
		if direction.length_squared() < 0.01:
			continue
		var candidate := direction.normalized() * _rng.randf_range(GameConfig.ARENA_RADIUS * 0.35, GameConfig.ARENA_RADIUS * 0.78)
		candidate.y *= 0.6
		if _spawn_is_clear(candidate):
			return candidate
	return Vector3.INF


## The 1.3 radius factor encloses irregular stone silhouettes in any rotation.
func _spawn_is_clear(candidate: Vector3) -> bool:
	if not candidate.is_finite():
		return false
	var own_clearance := radius * SPAWN_RADIUS_FACTOR + SPAWN_CLEARANCE
	if candidate.length() + own_clearance > GameConfig.ARENA_RADIUS:
		return false
	for node: Node in get_tree().get_nodes_in_group("bodies"):
		var body := node as StarBody
		if body == null or body.is_queued_for_deletion():
			continue
		if candidate.distance_to(body.global_position) < own_clearance + body.radius * SPAWN_RADIUS_FACTOR:
			return false
	for node: Node in get_tree().get_nodes_in_group("rocks"):
		var rock := node as Asteroid
		if rock == null or rock == self or rock.dead or rock.is_queued_for_deletion():
			continue
		if candidate.distance_to(rock.global_position) < own_clearance + rock.radius * SPAWN_RADIUS_FACTOR:
			return false
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var ship := node as SpaceShip
		if ship == null or ship.dead or ship.is_queued_for_deletion():
			continue
		if candidate.distance_to(ship.global_position) < own_clearance + ship.collision_radius:
			return false
	return true
