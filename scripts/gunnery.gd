class_name Gunnery
extends RefCounted
## Shared constant-velocity intercept, including velocity inherited by the bolt.

static func intercept_time(offset: Vector3, relative_velocity: Vector3, speed: float) -> float:
	var a := relative_velocity.length_squared() - speed * speed
	var b := 2.0 * offset.dot(relative_velocity)
	var c := offset.length_squared()
	if c < 0.0001:
		return 0.0
	if absf(a) < 0.0001:
		return -c / b if b < -0.0001 else INF
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0.0:
		return INF
	var root := sqrt(discriminant)
	var first := (-b - root) / (2.0 * a)
	var second := (-b + root) / (2.0 * a)
	var result := INF
	if first > 0.0:
		result = first
	if second > 0.0:
		result = minf(result, second)
	return result


## Test the actual ballistic corridor, including shooter momentum and friends
## moving across it before the round arrives. Shared by human and AI pilots.
static func has_clear_path(shooter: SpaceShip, contact: SpaceShip, from: Vector3, point: Vector3, flight: float) -> bool:
	var shot_velocity := (point - from).normalized() * shooter.bolt_speed + shooter.velocity * 0.2
	var to := from + shot_velocity * flight
	var query := PhysicsRayQueryParameters3D.create(from, to, GameConfig.WEAPON_MASK)
	query.exclude = [shooter.get_rid(), contact.get_rid()]
	if not shooter.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return false
	for node: Node in shooter.get_tree().get_nodes_in_group("ships"):
		var friend := node as SpaceShip
		if friend == null or friend == shooter or friend.dead or friend.team != shooter.team:
			continue
		var offset := friend.global_position - from
		var relative := friend.velocity - shot_velocity
		var time := clampf(-offset.dot(relative) / maxf(relative.length_squared(), 0.001), 0.0, flight)
		var closest := (offset + relative * time).length()
		var spread := shot_velocity.length() * time * tan(deg_to_rad(shooter.weapon_spread_deg))
		if closest < friend.collision_radius + GameConfig.BOLT_RADIUS + 1.0 + spread:
			return false
	return true
