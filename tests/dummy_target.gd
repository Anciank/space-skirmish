class_name DummyTarget
extends SpaceShip
## Minimal stand-in for a hostile ship, used by the focused tests.
## It inherits the real damage/shield model but never flies or shoots.

func _physics_process(delta: float) -> void:
	# Hold still and do nothing; the parent SpaceShip step still runs so that
	# collisions, gravity and resource regen behave exactly as in a real match.
	velocity = velocity.move_toward(Vector3.ZERO, 40.0 * delta)
	super(delta)
