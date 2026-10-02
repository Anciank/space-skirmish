class_name LaserBolt
extends Node3D
## Laser autocannon projectile.
##
## Movement is a per-frame raycast from the previous position to the next one,
## so a fast bolt can never tunnel through a hull. On a hit it spawns an
## impact flash and hands the damage over to whatever it struck.
##
## The bolt deliberately has no physics body: its "collision" is the raycast
## below. That keeps a few hundred simultaneous bolts cheap.

const HIT_MASK := GameConfig.WEAPON_MASK

var velocity := Vector3.ZERO
var damage := 6.0
var lifetime := 1.7
var attacker: Node = null
var bolt_color := Color(1.0, 0.62, 0.25)
var radius := GameConfig.BOLT_RADIUS

var _age := 0.0
var _mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("bolts")
	_mesh = get_node_or_null("Tracer") as MeshInstance3D
	if _mesh != null:
		# Stretch the tracer along its flight axis.
		_mesh.scale = Vector3(radius * 1.5, radius * 1.5, radius * 30.0)
		_apply_look()


## Configures and launches the bolt. Call this immediately after adding the node
## to the tree — doing it in one place keeps the tracer material and its
## orientation in sync with the actual shot.
func launch(origin: Vector3, direction: Vector3, shooter: Node, dmg: float, life: float, tint: Color) -> void:
	attacker = shooter
	damage = dmg
	lifetime = life
	bolt_color = tint
	velocity = direction
	global_position = origin
	_apply_look()
	if _mesh != null:
		_mesh.material_override = MeshFactory.make_bolt_material(tint)


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
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		global_position = to
		return

	var point: Vector3 = hit.get("position", to)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	var collider: Object = hit.get("collider")
	_impact(point, normal, collider)


func _impact(point: Vector3, normal: Vector3, collider: Object) -> void:
	_spawn_flash(point, normal, bolt_color)
	if collider != null and collider.has_method("take_damage"):
		# A small kick along the shot so hits feel like they land.
		collider.take_damage(damage, attacker, point, velocity.normalized() * damage * 0.35)
	queue_free()


func _spawn_flash(point: Vector3, normal: Vector3, tint: Color) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var spark := Spark.new()
	parent.add_child(spark)
	spark.setup(point, normal, tint)
