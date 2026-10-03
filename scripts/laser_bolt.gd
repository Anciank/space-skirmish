class_name LaserBolt
extends Node3D
## Autocannon projectile. The class name is kept for scene compatibility.
##
## Movement is a per-frame raycast from the previous position to the next one,
## so a fast bolt can never tunnel through a hull. On a hit it spawns an
## impact flash and hands the damage over to whatever it struck.
##
## The bolt deliberately has no physics body: its "collision" is the raycast
## below. That keeps a few hundred simultaneous bolts cheap.

const HIT_MASK := GameConfig.WEAPON_MASK
const TRACER_COLOR := Color("ffd4a0")

var velocity := Vector3.ZERO
var damage := GameConfig.BOLT_DAMAGE
var lifetime := GameConfig.BOLT_LIFETIME
var attacker: Node = null
var bolt_color := TRACER_COLOR
var radius := GameConfig.BOLT_RADIUS

var _age := 0.0
var _mesh: MeshInstance3D
var _credit: Dictionary = {}
var _ray_query := PhysicsRayQueryParameters3D.new()
var _excluded_attacker := RID()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_to_group("bolts")
	_ray_query.collision_mask = HIT_MASK
	_ray_query.collide_with_areas = false
	_ray_query.collide_with_bodies = true
	_mesh = get_node_or_null("Tracer") as MeshInstance3D
	if _mesh != null:
		# A thin incandescent trail behind the projectile, aligned to flight.
		_mesh.scale = Vector3(radius * 0.24, radius * 15.0, radius * 0.24)
		_mesh.position.z = radius * 7.5
		_apply_look()


## Configures and launches the bolt. Call this immediately after adding the node
## to the tree — doing it in one place keeps the tracer material and its
## orientation in sync with the actual shot.
func launch(origin: Vector3, direction: Vector3, shooter: Node, dmg: float, life: float, _tint: Color) -> void:
	attacker = shooter
	if shooter is SpaceShip:
		_credit = {"name": (shooter as SpaceShip).display_name, "team": (shooter as SpaceShip).team}
	damage = dmg
	lifetime = life
	# Ammo burns the same color on both teams; HUD markers identify allegiance.
	bolt_color = TRACER_COLOR
	velocity = direction
	global_position = origin
	_apply_look()
	if _mesh != null:
		_mesh.material_override = MeshFactory.make_bolt_material(bolt_color)
	# The effect is inserted before its launch pose is known. Prevent a first
	# rendered frame from interpolating out of the scene's default origin.
	reset_physics_interpolation()


func _apply_look() -> void:
	if _mesh == null or velocity.length_squared() < 0.0001:
		return
	var dir := velocity.normalized()
	# Guard the degenerate case where the flight path is parallel to world up.
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.995:
		up = Vector3.FORWARD
	look_at(global_position + dir, up)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return

	var from := global_position
	var to := from + velocity * delta
	# Each round keeps its own query; the ray still runs on every physics tick.
	# Reuse avoids thousands of temporary query objects in a large firefight.
	_ray_query.from = from
	_ray_query.to = to
	var attacker_rid := RID()
	if is_instance_valid(attacker) and attacker is CollisionObject3D:
		attacker_rid = (attacker as CollisionObject3D).get_rid()
	if attacker_rid != _excluded_attacker:
		_ray_query.exclude = [attacker_rid] if attacker_rid.is_valid() else []
		_excluded_attacker = attacker_rid
	var hit := get_world_3d().direct_space_state.intersect_ray(_ray_query)

	if hit.is_empty():
		global_position = to
		return

	var point: Vector3 = hit.get("position", to)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var collider: Object = hit.get("collider")
	_impact(point, normal, collider)


func _impact(point: Vector3, normal: Vector3, collider: Object) -> void:
	if not collider is Asteroid:
		var tint := bolt_color
		var shielded := false
		if collider is SpaceShip:
			shielded = (collider as SpaceShip).shield > 0.0
			tint = Color("91c8e2") if shielded else Color("ffd4a0")
		_spawn_flash(point, normal, tint, shielded)
	if collider != null and collider.has_method("take_damage"):
		# A small kick along the shot so hits feel like they land.
		var source: Node = attacker if is_instance_valid(attacker) else null
		var kick := velocity.normalized() * damage * 0.35
		if collider is SpaceShip:
			(collider as SpaceShip).take_damage(damage, source, point, kick, _credit)
		else:
			collider.take_damage(damage, source, point, kick)
	queue_free()


func _spawn_flash(point: Vector3, normal: Vector3, tint: Color, shielded := false) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spark := Spark.new()
	spark.ejecta = not shielded
	parent.add_child(spark)
	spark.setup(point, normal, tint)
