class_name Asteroid
extends RigidBody3D
## Tumbling destructible rock. Also an obstacle: ramming one hurts whichever
## body is moving faster into the contact. Small rocks shatter quickly, big
## ones soak a lot of fire and the arena respawns them after a while.

signal destroyed(asteroid: Asteroid)

const RESPAWN_DELAY := 14.0

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
	mesh.mesh = MeshFactory.make_rock(radius, rock_seed, 0)

	var hue := _rng.randf()
	var base := Color.from_hsv(0.07 + hue * 0.06, 0.16 + _rng.randf() * 0.12, 0.34 + _rng.randf() * 0.16)
	var mat := MeshFactory.make_rock_material(base, rock_seed, radius)
	mesh.material_override = mat


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
		spark.setup(world_pos, (global_position - world_pos).normalized(), Color(0.75, 0.62, 0.45))
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
	GameConfig.effects_parent(self).add_child(fx)
	fx.global_position = global_position
	Sfx.play_at("explosion", global_position, -3.0, randf_range(-0.4, 0.4), 1600.0)

	if respawnable:
		_respawn_timer = RESPAWN_DELAY
	else:
		queue_free()


func _revive() -> void:
	_respawn_timer = 0.0
	dead = false
	hp = radius * radius * 2.2
	# Drift to a fresh spot so the field keeps changing between rounds.
	var dir := Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0))
	if dir.length_squared() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized() * _rng.randf_range(GameConfig.ARENA_RADIUS * 0.35, GameConfig.ARENA_RADIUS * 0.78)
	dir.y *= 0.6
	global_position = dir
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3(
		_rng.randfn(-1.0, 1.0), _rng.randfn(-1.0, 1.0), _rng.randfn(-1.0, 1.0)
	).normalized() * _rng.randf_range(0.05, 0.3)
	rotation = Vector3(_rng.randf_range(0, TAU), _rng.randf_range(0, TAU), _rng.randf_range(0, TAU))
	visible = true
	collision_layer = GameConfig.LAYER_ROCK
	collision_mask = GameConfig.ROCK_MASK
	freeze = false
