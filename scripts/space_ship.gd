class_name SpaceShip
extends CharacterBody3D
## Shared Newtonian flight model, damage model and kinetic autocannon.
##
## Ships are CharacterBody3Ds in FLOATING motion mode: no gravity, no floor
## logic, just `velocity` plus light drag, so you coast like you would in
## vacuum. Subclasses (player / AI) only decide *where* to point and *how much*
## thrust to request; all the physics, shields and shooting live here.

signal hull_changed(current: float, maximum: float)
signal shield_changed(current: float, maximum: float)
signal boost_changed(current: float, maximum: float)
signal speed_changed(current: float)
signal weapon_fired()
signal took_damage(amount: float, world_pos: Vector3, attacker: Node)
signal destroyed(killer: Node)
signal respawned()

const BOLT_SCENE := preload("res://scenes/weapons/laser_bolt.tscn")

@export var team: int = GameConfig.TEAM_BLUE
@export var display_name: String = "PILOT"
@export var is_player := false

@export_group("Hull")
@export var hull_max := GameConfig.HULL_MAX
@export var shield_max := GameConfig.SHIELD_MAX
@export var shield_regen_rate := GameConfig.SHIELD_REGEN_RATE
@export var shield_regen_delay := GameConfig.SHIELD_REGEN_DELAY

@export_group("Flight")
@export var thrust_main := GameConfig.THRUST_MAIN
@export var thrust_reverse := GameConfig.THRUST_REVERSE
@export var thrust_lateral := GameConfig.THRUST_LATERAL
@export var thrust_vertical := GameConfig.THRUST_VERTICAL
@export var speed_cruise := GameConfig.SPEED_CRUISE
@export var speed_boost := GameConfig.SPEED_BOOST
@export var drift_damping := GameConfig.DRIFT_DAMPING

@export_group("Booster")
@export var boost_max := GameConfig.BOOST_MAX
@export var boost_drain := GameConfig.BOOST_DRAIN
@export var boost_regen := GameConfig.BOOST_REGEN

@export_group("Weapons")
@export var fire_interval := GameConfig.FIRE_INTERVAL
@export var bolt_damage := GameConfig.BOLT_DAMAGE
@export var bolt_speed := GameConfig.BOLT_SPEED
@export var weapon_spread_deg := GameConfig.WEAPON_SPREAD

@export_group("Collision")
@export var collision_damage_scale := GameConfig.COLLISION_DAMAGE
@export var collision_radius := 2.2

# --- runtime state ---
var hull := 100.0
var shield := 100.0
var boost := 100.0
var boosting := false
var dead := true

## Controller output, written every physics frame.
var cmd_forward := 0.0
var cmd_right := 0.0
var cmd_up := 0.0
var wants_boost := false

var throttle := 0.0
var speed := 0.0
## Bumped by every shot; the camera rig reads it to add recoil kick.
var recoil := 0.0

var last_attacker: Node = null
var last_damage_pilot := ""
var last_damage_team := -1
var last_damage_cause := "HAZARD"
var last_damage_dir := Vector3.FORWARD
var last_damage_time := -999.0

## Optional world-space convergence point, set by the player's sight or an AI
## intercept solution. Zero leaves the cannons firing along their local axes.
var aim_point := Vector3.ZERO

var _shield_timer := 0.0
var _boost_timer := 0.0
var _fire_timer := 0.0
var _muzzle_index := 0
var _gravity := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _flash_cooldown := 0.0
var _damage_material: ShaderMaterial

@onready var model: ShipVisual = $ShipModel
@onready var hull_mesh: MeshInstance3D = $ShipModel/HullBody
@onready var muzzle_points: Array[Node3D] = [$ShipModel/MuzzleLeft, $ShipModel/MuzzleRight]


func _ready() -> void:
	add_to_group("ships")
	_rng.seed = int(hash(name) ^ Time.get_ticks_usec())
	reset_for_spawn()
	apply_team_paint(GameConfig.team_color(team))


# =========================================================== lifecycle ====

func reset_for_spawn() -> void:
	hull = hull_max
	shield = shield_max
	boost = boost_max
	throttle = 0.0
	speed = 0.0
	recoil = 0.0
	boosting = false
	dead = false
	cmd_forward = 0.0
	cmd_right = 0.0
	cmd_up = 0.0
	wants_boost = false
	_shield_timer = 0.0
	_boost_timer = 0.0
	_fire_timer = 0.0
	_muzzle_index = 0
	_flash_cooldown = 0.0
	hull_mesh.material_override = null
	model.reset_feedback()
	_gravity = Vector3.ZERO
	last_attacker = null
	last_damage_pilot = ""
	last_damage_team = -1
	last_damage_cause = "HAZARD"
	last_damage_time = -999.0
	aim_point = Vector3.ZERO
	visible = true
	collision_layer = GameConfig.LAYER_SHIP
	collision_mask = GameConfig.SHIP_MASK
	_emit_all()


func respawn_at(position: Vector3, look_at_point: Vector3) -> void:
	global_position = position
	var to_look := look_at_point - position
	if to_look.length_squared() > 1.0:
		# Avoid the degenerate "looking straight up" case, which makes the
		# resulting basis undefined around the roll axis.
		var up := Vector3.UP
		if absf(to_look.normalized().dot(up)) > 0.98:
			up = Vector3.FORWARD
		look_at(look_at_point, up)
	velocity = Vector3.ZERO
	reset_for_spawn()
	# Teleports must start a fresh display history. Prime the camera/HUD's
	# interpolated-pose pump before clearing the previous spawn position.
	get_global_transform_interpolated()
	reset_physics_interpolation()
	respawned.emit()


# ============================================================== helpers ====

func forward() -> Vector3:
	return -global_transform.basis.z.normalized()


func right() -> Vector3:
	return global_transform.basis.x.normalized()


func up() -> Vector3:
	return global_transform.basis.y.normalized()


## Gravity wells push into this; folded into the next integration step.
func add_gravity(accel: Vector3) -> void:
	_gravity += accel


## Applies squadron identification paint to the shared corvette.
func apply_team_paint(color: Color) -> void:
	model.set_livery(color)


# ============================================================== physics ====

func _physics_process(delta: float) -> void:
	if _flash_cooldown > 0.0:
		_flash_cooldown = maxf(0.0, _flash_cooldown - delta)
		if _flash_cooldown <= 0.0:
			hull_mesh.material_override = null
	recoil = move_toward(recoil, 0.0, delta * 6.0)

	if dead:
		velocity = velocity.move_toward(Vector3.ZERO, 80.0 * delta)
		move_and_slide()
		return

	_integrate_velocity(delta)
	_consume_gravity(delta)
	_contain_in_arena(delta)

	var incoming_velocity := velocity
	move_and_slide()
	_resolve_collisions(incoming_velocity)

	_update_resources(delta)
	_update_weapon(delta)
	_update_visuals(delta)


func _integrate_velocity(delta: float) -> void:
	# A bad frame anywhere upstream (NaN command, a zero-length basis) must not
	# be allowed to poison velocity and transform permanently.
	if not _commands_are_finite():
		cmd_forward = 0.0
		cmd_right = 0.0
		cmd_up = 0.0
		velocity = Vector3.ZERO
		return

	var b := global_transform.basis
	var accel := -b.z * cmd_forward * thrust_main
	accel += b.x * cmd_right * thrust_lateral
	accel += b.y * cmd_up * thrust_vertical

	var cap := speed_cruise
	if wants_boost and (boosting or boost >= GameConfig.BOOST_MIN_TO_ENGAGE) and boost > 0.0:
		boosting = true
		boost = maxf(0.0, boost - boost_drain * delta)
		_boost_timer = GameConfig.BOOST_REGEN_DELAY
		cap = speed_boost
		accel += -b.z * maxf(cmd_forward, 0.0) * GameConfig.THRUST_AFTERBURNER
		if boost <= 0.0:
			wants_boost = false
	else:
		boosting = false

	velocity += accel * delta

	# Always bleed a little speed (vacuum drift), but only lightly when we are
	# above the cap so a released afterburner keeps its momentum.
	var damp := drift_damping if velocity.length() <= cap else GameConfig.OVERSPEED_DAMPING
	velocity -= velocity * clampf(damp * delta, 0.0, 1.0)

	var limit := cap * 1.15
	if velocity.length() > limit:
		velocity = velocity.normalized() * limit


func _commands_are_finite() -> bool:
	var checks := [cmd_forward, cmd_right, cmd_up, 1.0 if wants_boost else 0.0]
	for v: float in checks:
		if not is_finite(v):
			return false
	var b := global_transform.basis
	for axis: Vector3 in [b.x, b.y, b.z]:
		if not (is_finite(axis.x) and is_finite(axis.y) and is_finite(axis.z)):
			return false
	return true


func _consume_gravity(delta: float) -> void:
	if _gravity.length_squared() > 0.000001:
		velocity += _gravity * delta
	_gravity = Vector3.ZERO


## Soft boundary: inside ARENA_RADIUS - MARGIN nothing happens; past that a
## restoring acceleration shoves you back, and past the wall a hard clamp.
func _contain_in_arena(delta: float) -> void:
	var limit := GameConfig.ARENA_RADIUS - GameConfig.ARENA_MARGIN
	var offset := global_position
	var dist := offset.length()
	if dist <= limit:
		return

	var outward := offset / maxf(dist, 0.001)
	var over := clampf((dist - limit) / GameConfig.ARENA_MARGIN, 0.0, 1.0)
	velocity -= outward * GameConfig.ARENA_PUSH * (0.5 + over * 2.5) * delta

	if dist > GameConfig.ARENA_RADIUS:
		global_position = outward * GameConfig.ARENA_RADIUS
		var outward_speed := maxf(0.0, velocity.dot(outward))
		if outward_speed > GameConfig.ARENA_HARD_SPEED:
			velocity -= outward * (outward_speed - GameConfig.ARENA_HARD_SPEED)


func _resolve_collisions(incoming_velocity: Vector3) -> void:
	var count := get_slide_collision_count()
	if count == 0:
		return

	var worst := 0.0
	var worst_point := Vector3.ZERO
	var i := 0
	while i < count:
		var col := get_slide_collision(i)
		i += 1
		var normal: Vector3 = col.get_normal()
		var other: Object = col.get_collider()
		# move_and_slide() has already removed the inward velocity. Damage must
		# use the incoming speed or a direct impact can look harmless afterwards.
		var rel_v: Vector3 = incoming_velocity - _velocity_of(other)
		var closing: float = maxf(0.0, -rel_v.dot(normal))

		# Slide instead of sticking, and bounce off hard hits.
		velocity = velocity.slide(normal)
		if velocity.length() < 3.0 and closing > 1.0:
			velocity += normal * closing * 0.4

		var force := closing
		if force > worst:
			worst = force
			worst_point = col.get_position()

		if other != null and other.has_method("apply_impact"):
			other.apply_impact(force, global_position, self)

	if worst >= GameConfig.COLLISION_MIN_SPEED:
		# Momentum split: the faster body takes most of the damage.
		var mine: float = clampf(worst / 45.0, 0.0, 1.0)
		take_damage(worst * collision_damage_scale * (0.35 + 0.65 * mine), null, worst_point, Vector3.ZERO, {}, "COLLISION")


func _velocity_of(other: Object) -> Vector3:
	if other is CharacterBody3D:
		return (other as CharacterBody3D).velocity
	if other is RigidBody3D:
		return (other as RigidBody3D).linear_velocity
	return Vector3.ZERO


func _update_resources(delta: float) -> void:
	throttle = move_toward(throttle, cmd_forward, delta * 3.0)
	speed = velocity.length()
	speed_changed.emit(speed)

	if not boosting:
		_boost_timer = maxf(0.0, _boost_timer - delta)
		if _boost_timer <= 0.0 and boost < boost_max:
			boost = minf(boost_max, boost + boost_regen * delta)
			boost_changed.emit(boost, boost_max)

	if _shield_timer > 0.0:
		_shield_timer -= delta
	elif shield < shield_max:
		shield = minf(shield_max, shield + shield_regen_rate * delta)
		shield_changed.emit(shield, shield_max)


# ================================================================ damage ===

func take_damage(amount: float, attacker: Node = null, world_pos := Vector3.ZERO, knockback := Vector3.ZERO, credit: Dictionary = {}, cause := "") -> void:
	if dead or amount <= 0.0:
		return
	var source_name := String(credit.get("name", ""))
	var source_team := int(credit.get("team", -1))
	if is_instance_valid(attacker) and attacker is SpaceShip:
		var a := attacker as SpaceShip
		if a == self or a.team == team:
			return
		last_attacker = a
		source_name = a.display_name
		source_team = a.team
	if source_team == team:
		return
	last_damage_pilot = source_name
	last_damage_team = source_team
	last_damage_cause = cause if not cause.is_empty() else ("AUTOCANNON" if not source_name.is_empty() else "HAZARD")

	var shielded_before := shield
	var hull_before := hull
	shield = maxf(0.0, shield - amount)
	var absorbed := shielded_before - shield
	var overflow := amount - absorbed

	# Shields and hull are damaged independently: a big enough hit eats through
	# the shield and still carries the remainder into the hull.
	if absorbed > 0.0:
		var impact := world_pos if world_pos != Vector3.ZERO else global_position + forward() * 2.0
		model.flash_shield(model.to_local(impact))
		shield_changed.emit(shield, shield_max)
		if world_pos != Vector3.ZERO:
			record_hit(world_pos)
			if is_player:
				Sfx.play_local("shield", -13.0)
			else:
				Sfx.play_at("shield", world_pos, -13.0)
	if overflow > 0.0:
		hull = maxf(0.0, hull - overflow)
		hull_changed.emit(hull, hull_max)
		if world_pos != Vector3.ZERO:
			record_hit(world_pos)
			if is_player:
				Sfx.play_local("impact", -8.0, _rng.randf_range(-1.0, 1.0))
			else:
				Sfx.play_at("impact", world_pos, -8.0, _rng.randf_range(-1.0, 1.0))
		_flash_damage(world_pos)

	if world_pos == Vector3.ZERO:
		record_hit(global_position + forward() * 2.0)

	if knockback.length_squared() > 0.001:
		velocity += knockback

	_shield_timer = shield_regen_delay
	took_damage.emit(absorbed + hull_before - hull, world_pos, attacker)

	if hull <= 0.0:
		_die(attacker)


func record_hit(world_pos: Vector3) -> void:
	last_damage_dir = (global_position - world_pos).normalized()
	last_damage_time = float(Time.get_ticks_msec()) / 1000.0


func heal(amount: float) -> void:
	hull = minf(hull_max, hull + amount)
	hull_changed.emit(hull, hull_max)


func _die(killer: Node) -> void:
	if dead:
		return
	dead = true
	boosting = false
	velocity *= 0.25
	destroyed.emit(killer)
	set_deferred("visible", false)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)


func _emit_all() -> void:
	hull_changed.emit(hull, hull_max)
	shield_changed.emit(shield, shield_max)
	boost_changed.emit(boost, boost_max)


func _flash_damage(world_pos: Vector3) -> void:
	if _flash_cooldown > 0.0 or hull_mesh == null:
		return
	_flash_cooldown = 0.12
	if _damage_material == null:
		_damage_material = (hull_mesh.mesh.surface_get_material(0) as ShaderMaterial).duplicate()
	var local_hit := model.to_local(world_pos) if world_pos != Vector3.ZERO else Vector3(0, 0, -2.5)
	_damage_material.set_shader_parameter("impact_position", local_hit)
	_damage_material.set_shader_parameter("impact_heat", 0.65)
	hull_mesh.material_override = _damage_material


# =============================================================== weapons ===

func _update_weapon(delta: float) -> void:
	# Carry one step's overshoot into the next shot so 20 Hz stays 20 Hz even
	# at 30/120 physics ticks. An idle weapon clears that remainder next step.
	_fire_timer = _fire_timer - delta if _fire_timer > 0.000001 else 0.0


func can_fire() -> bool:
	return not dead and _fire_timer <= 0.000001


func fire(shots := 1) -> void:
	if dead:
		return
	var fired := false
	for _i in shots:
		if _fire_timer > 0.000001:
			break
		_fire_timer = maxf(_fire_timer, -fire_interval) + fire_interval
		_spawn_bolt()
		fired = true
	if fired:
		# A whisper of kick backwards plus a camera punch, for weight. Kept
		# small on purpose — see GameConfig.WEAPON_RECOIL.
		velocity -= forward() * bolt_speed * GameConfig.WEAPON_RECOIL
		recoil = minf(1.0, recoil + 0.55)
		weapon_fired.emit()
		if is_player:
			Sfx.play_local("laser", -7.0, _rng.randf_range(-0.25, 0.25))
		else:
			Sfx.play_at("laser", global_position, -10.0, _rng.randf_range(-0.25, 0.25))


func _spawn_bolt() -> void:
	var muzzle: Node3D = muzzle_points[_muzzle_index % muzzle_points.size()]
	model.flash_muzzle(_muzzle_index)
	_muzzle_index += 1
	var bolt := BOLT_SCENE.instantiate()
	_effects_parent().add_child(bolt)

	var dir := -muzzle.global_transform.basis.z.normalized()
	if aim_point != Vector3.ZERO:
		# Tracking fire: converge both cannons on the aim point.
		var to_aim := (aim_point - muzzle.global_position)
		if to_aim.length_squared() > 1.0:
			dir = to_aim.normalized()
	var spread := deg_to_rad(weapon_spread_deg)
	dir = dir.rotated(muzzle.global_transform.basis.y.normalized(), _rng.randfn(0.0, spread))
	dir = dir.rotated(muzzle.global_transform.basis.x.normalized(), _rng.randfn(0.0, spread))
	bolt.launch(muzzle.global_position, dir * bolt_speed + velocity * 0.2,
		self, bolt_damage, GameConfig.BOLT_LIFETIME, GameConfig.team_color(team))
	aim_point = Vector3.ZERO


## Where transient effects should live. Walks up the tree looking for an
## "Effects" container so bolts and explosions never end up parented to a ship
## (which would make them inherit its motion and rotation).
func _effects_parent() -> Node:
	return GameConfig.effects_parent(self)


# ============================================================== visuals ===

func _update_visuals(delta: float) -> void:
	model.update_motion(throttle, boosting, delta, Vector2(cmd_right, cmd_up))


## Engine drone volume for the locally-controlled ship.
func update_engine_audio() -> void:
	Sfx.set_engine(absf(throttle) * 0.8 + 0.2, 1.0 if boosting else 0.0, not dead)
