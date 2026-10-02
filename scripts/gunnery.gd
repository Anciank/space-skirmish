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
