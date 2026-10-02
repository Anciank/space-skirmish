class_name SpaceShip
extends CharacterBody3D
## Shared Newtonian flight model, damage model and laser autocannon.
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

const PAINT_PATHS := [
	"ShipModel/HullSpine",
	"ShipModel/WingPivotLeft/WingLeft",
	"ShipModel/WingPivotRight/WingRight",
	"ShipModel/FinLeft",
	"ShipModel/FinRight",
]

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
var last_damage_dir := Vector3.FORWARD
var last_damage_time := -999.0

## Optional world-space point the guns should converge on. Left at zero for the
## player (bolts fly straight down the nose); the AI sets it so its cannons
## actually track a moving target instead of spraying wide.
var aim_point := Vector3.ZERO

var _shield_timer := 0.0
var _boost_timer := 0.0
var _fire_timer := 0.0
var _muzzle_index := 0
var _gravity := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _flash_cooldown := 0.0

@onready var model: Node3D = $ShipModel
@onready var hull_mesh: MeshInstance3D = $ShipModel/HullBody
@onready var muzzle_points: Array[Node3D] = [$ShipModel/MuzzleLeft, $ShipModel/MuzzleRight]
@onready var engine_lights: Array[OmniLight3D] = [$ShipModel/EngineLightLeft, $ShipModel/EngineLightRight]
@onready var engine_glows: Array[MeshInstance3D] = [$ShipModel/EngineGlowLeft, $ShipModel/EngineGlowRight]
@onready var burners: Array[MeshInstance3D] = [$ShipModel/BurnerLeft, $ShipModel/BurnerRight]


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


## Recolours paint + engine materials so a single scene serves both teams.
func apply_team_paint(color: Color) -> void:
	for path: String in PAINT_PATHS:
		var mi := get_node_or_null(path) as MeshInstance3D
		if mi == null:
			continue
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = 0.7
		mat.roughness = 0.34
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.22
		mi.material_override = mat

	var engine := color.lerp(Color(1, 1, 1), 0.5)
	for glow: MeshInstance3D in engine_glows:
		glow.material_override = MeshFactory.make_glow_material(engine, 5.0)
	for burner: MeshInstance3D in burners:
		burner.material_override = MeshFactory.make_glow_material(engine, 3.0)
	for light: OmniLight3D in engine_lights:
		light.light_color = engine


# ============================================================== physics ====

func _physics_process(delta: float) -> void:
	_flash_cooldown = maxf(0.0, _flash_cooldown - delta)
	recoil = move_toward(recoil, 0.0, delta * 6.0)

	if dead:
		velocity = velocity.move_toward(Vector3.ZERO, 80.0 * delta)
		move_and_slide()
		return

	_integrate_velocity(delta)
	_consume_gravity(delta)
	_contain_in_arena(delta)

	var collision := move_and_slide()
	_resolve_collisions()

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
	if wants_boost and boost > 0.0:
		boosting = true
		boost = maxf(0.0, boost - boost_drain * delta)
		_boost_timer = GameConfig.BOOST_REGEN_DELAY
		cap = speed_boost
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
	var offset := Vector3(global_position.x, 0.0, global_position.z)
	var dist := offset.length()
	if dist <= limit:
		return

	var outward := offset / maxf(dist, 0.001)
	var over := clampf((dist - limit) / GameConfig.ARENA_MARGIN, 0.0, 1.0)
	velocity -= outward * GameConfig.ARENA_PUSH * (0.5 + over * 2.5) * delta

	if dist > GameConfig.ARENA_RADIUS:
		global_position = Vector3(outward.x, global_position.y, outward.z) * GameConfig.ARENA_RADIUS
		var outward_speed := maxf(0.0, velocity.dot(outward))
		if outward_speed > GameConfig.ARENA_HARD_SPEED:
			velocity -= outward * (outward_speed - GameConfig.ARENA_HARD_SPEED)


func _resolve_collisions() -> void:
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
		var rel_v: Vector3 = velocity - _velocity_of(other)
		var closing: float = maxf(0.0, -rel_v.dot(normal))

		# Slide instead of sticking, and bounce off hard hits.
		velocity = velocity.slide(normal)
		if velocity.length() < 3.0 and closing > 1.0:
			velocity += normal * closing * 0.4

		var force := rel_v.length()
		if force > worst:
			worst = force
			worst_point = col.get_position()

		if other != null and other.has_method("apply_impact"):
			other.apply_impact(force, global_position, self)

	if worst >= GameConfig.COLLISION_MIN_SPEED:
		# Momentum split: the faster body takes most of the damage.
		var mine: float = clampf(worst / 45.0, 0.0, 1.0)
		take_damage(worst * collision_damage_scale * (0.35 + 0.65 * mine), null, worst_point)


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
			boost_changed.emit(boost)

	if _shield_timer > 0.0:
		_shield_timer -= delta
	elif shield < shield_max:
		shield = minf(shield_max, shield + shield_regen_rate * delta)
		shield_changed.emit(shield)


# ================================================================ damage ===

func take_damage(amount: float, attacker: Node = null, world_pos := Vector3.ZERO, knockback := Vector3.ZERO) -> void:
	if dead or amount <= 0.0:
		return
	if attacker is SpaceShip:
		var a := attacker as SpaceShip
		if a == self or a.team == team:
			return
		last_attacker = a

	var shielded_before := shield
	shield = maxf(0.0, shield - amount)
	var absorbed := shielded_before - shield
	var overflow := amount - absorbed

	# Shields and hull are damaged independently: a big enough hit eats through
	# the shield and still carries the remainder into the hull.
	if absorbed > 0.0:
		shield_changed.emit(shield)
		if world_pos != Vector3.ZERO:
			record_hit(world_pos)
			Sfx.play_at("shield", world_pos, -10.0)
	if overflow > 0.0:
		hull = maxf(0.0, hull - overflow)
		hull_changed.emit(hull)
		if world_pos != Vector3.ZERO:
			record_hit(world_pos)
			Sfx.play_at("impact", world_pos, -4.0, _rng.randf_range(-1.0, 1.0))
		_flash_damage()

	if world_pos == Vector3.ZERO:
		record_hit(global_position + forward() * 2.0)

	if knockback.length_squared() > 0.001:
		velocity += knockback

	if shield <= 0.0:
		_shield_timer = shield_regen_delay
	took_damage.emit(amount, world_pos, attacker)

	if hull <= 0.0:
		_die(attacker)


func record_hit(world_pos: Vector3) -> void:
	last_damage_dir = (global_position - world_pos).normalized()
	last_damage_time = float(Time.get_ticks_msec()) / 1000.0


func heal(amount: float) -> void:
	hull = minf(hull_max, hull + amount)
	hull_changed.emit(hull)


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


func _flash_damage() -> void:
	if _flash_cooldown > 0.0 or hull_mesh == null:
		return
	_flash_cooldown = 0.12
	var mesh := hull_mesh
	_flash_task(mesh)


func _flash_task(mesh: MeshInstance3D) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.15)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	await get_tree().create_timer(0.12).timeout
	if is_instance_valid(mesh):
		mesh.material_override = null


# =============================================================== weapons ===

func _update_weapon(delta: float) -> void:
	_fire_timer = maxf(0.0, _fire_timer - delta)


func can_fire() -> bool:
	return not dead and _fire_timer <= 0.0


func fire(shots := 1) -> void:
	if dead:
		return
	var parent := _effects_parent()
	var fired := false
	for _i in shots:
		if _fire_timer > 0.0:
			break
		_fire_timer = fire_interval
		_spawn_bolt()
		fired = true
	if fired:
		# A whisper of kick backwards plus a camera punch, for weight. Kept
		# small on purpose — see GameConfig.WEAPON_RECOIL.
		velocity -= forward() * bolt_speed * GameConfig.WEAPON_RECOIL
		recoil = minf(1.0, recoil + 0.55)
		weapon_fired.emit()
		Sfx.play_local("laser", -13.0, _rng.randf_range(-1.2, 1.2))


func _spawn_bolt() -> void:
	var muzzle: Node3D = muzzle_points[_muzzle_index % muzzle_points.size()]
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
	var node: Node = self
	while node != null:
		if node.has_node("Effects"):
			return node.get_node("Effects")
		node = node.get_parent()
	var scene := get_tree().current_scene
	if scene != null and scene.has_node("Effects"):
		return scene.get_node("Effects")
	return get_tree().root


# ============================================================== visuals ===

func _update_visuals(delta: float) -> void:
	var load := 0.35 + absf(throttle) * 0.65
	var boost_extra := 4.0 if boosting else 0.0
	var energy := 2.0 + load * 3.5 + boost_extra
	var glow_scale := 0.85 + load * 0.35 + (0.45 if boosting else 0.0)
	var tint := GameConfig.team_color(team).lerp(Color(1, 1, 1), 0.5)

	var k: float = clampf(delta * 7.0, 0.0, 1.0)
	for glow: MeshInstance3D in engine_glows:
		if not is_instance_valid(glow):
			continue
		var mat := glow.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, energy, k)
			mat.emission = tint
		glow.scale = glow.scale.lerp(Vector3.ONE * glow_scale, k)

	for light: OmniLight3D in engine_lights:
		if not is_instance_valid(light):
			continue
		light.light_energy = lerpf(light.light_energy, 0.9 + load * 1.8 + boost_extra * 0.6, k)
		light.light_color = tint

	var kb: float = clampf(delta * 12.0, 0.0, 1.0)
	for burner: MeshInstance3D in burners:
		if not is_instance_valid(burner):
			continue
		var target_z := 0.0
		if boosting:
			target_z = _rng.randf_range(1.1, 2.0)
		burner.scale = burner.scale.lerp(Vector3(1.0, 1.0, maxf(target_z, 0.001)), kb)
		burner.visible = burner.scale.z > 0.06


## Engine drone volume for the locally-controlled ship.
func update_engine_audio() -> void:
	Sfx.set_engine(absf(throttle) * 0.8 + 0.2, 1.0 if boosting else 0.0, not dead)
