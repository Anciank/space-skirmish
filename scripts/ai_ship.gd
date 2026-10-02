class_name AIShip
extends SpaceShip
## Enemy / ally fighter brain.
##
## A compact state machine (PATROL → ENGAGE → EVADE → RETREAT) that only ever
## decides three things: which way to point, how fast to travel, and when to
## pull the trigger. The flight model itself is inherited from `SpaceShip`, so
## AI ships obey the same inertia, speed caps and shields the player does.

enum State { PATROL, ENGAGE, EVADE, RETREAT }

## Multiplier on reaction speed / accuracy. 1.0 = baseline.
@export var skill := 1.0
## Seconds between AI firing decisions.
@export var reaction := 0.14

var state: int = State.PATROL
var target: SpaceShip = null

var _state_timer := 0.0
var _decision_timer := 0.0
var _orbit_dir := 1.0
var _waypoint := Vector3.ZERO
var _has_waypoint := false
var _burst_timer := 0.0
var _burst_len := 0.0
var _burst_gap := 0.0
var _retreat_timer := 0.0
var _evade_vector := Vector3.ZERO
var _evade_timer := 0.0
var _desired_dir := Vector3.FORWARD
var _desired_speed := 0.0
## Travel component resolved into the ship's own axes by _apply_translation.
var _cmd_forward := 0.0
var _roll_bias := 0.0
var _aim_noise := Vector3.ZERO


func _ready() -> void:
	super()
	_desired_dir = forward()
	_think()


func _physics_process(delta: float) -> void:
	if dead:
		super(delta)
		return

	_state_timer += delta
	_decision_timer -= delta
	_evade_timer -= delta

	if _decision_timer <= 0.0:
		_decision_timer = reaction / maxf(skill, 0.2)
		_think()

	_aim_offset_update(delta)
	_apply_steering(delta)
	_apply_translation(delta)
	_apply_weapons(delta)

	super(delta)


# ============================================================== decisions ==

func _think() -> void:
	_acquire_target()
	# Effective health: a pilot sitting on full shields is not in danger yet.
	var hp_ratio := (hull + shield) / maxf(hull_max + shield_max, 1.0)

	if target == null or not is_instance_valid(target) or target.dead:
		target = null
		_set_state(State.PATROL)
		_plan_patrol()
		return

	var dist := global_position.distance_to(target.global_position)
	var panic := _panic_threshold()
	if hp_ratio < panic and state != State.RETREAT:
		_set_state(State.RETREAT)
		_retreat_timer = GameConfig.AI_RETREAT_DURATION
		return
	if state == State.RETREAT:
		_retreat_timer -= reaction
		# Break off to shake pursuers, then come back around and take pot shots.
		# Time-boxed, because hull damage never heals.
		if hp_ratio > panic * 1.25 or _retreat_timer <= 0.0:
			_set_state(State.ENGAGE)

	match state:
		State.RETREAT:
			_desired_dir = (global_position - target.global_position).normalized()
			_desired_speed = speed_boost * 0.92
			wants_boost = true
			_pick_evade_vector(dist)
		State.EVADE:
			# A jink, not a retreat: perpendicular to the threat line and short.
			# Treating this as "fly away fast" made the AI burn most of the fight
			# in EVADE, sailing steadily out of its own engagement band.
			_desired_dir = _evade_vector
			_desired_speed = speed_cruise * 0.8
			wants_boost = false
			if _evade_timer <= 0.0:
				_set_state(State.ENGAGE)
		_:
			_set_state(State.ENGAGE)
			_plan_combat(dist)

	_plan_patrol_if_idle()


func _panic_threshold() -> float:
	## AI_PANIC_HULL is authored as "percent of max hull"; convert it to the
	## combined hull+shield pool that _think() actually measures against.
	return GameConfig.AI_PANIC_HULL / 100.0


func _acquire_target() -> void:
	if target != null and is_instance_valid(target) and not target.dead:
		if global_position.distance_to(target.global_position) < GameConfig.AI_MAX_RANGE:
			return
	target = null

	var best: SpaceShip = null
	var best_dist := INF
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if other == null or other == self or other.dead or other.team == team:
			continue
		var d := global_position.distance_to(other.global_position)
		if d > GameConfig.AI_AGGRO_RANGE:
			continue
		# Prefer whoever is already looking at us, then whoever is closest.
		var facing := absf(forward().dot((other.global_position - global_position).normalized()))
		var score := d - facing * 160.0
		if score < best_dist:
			best_dist = score
			best = other
	target = best


func _plan_combat(dist: float) -> void:
	assert(target != null)
	var away := (global_position - target.global_position).normalized()
	var toward := -away

	# Inside the hard separation floor: forget dogfighting, just get out. This
	# has to win over every other consideration or the AI ends up nose-to-nose
	# with a target, where the aim cone is meaningless.
	if dist < GameConfig.AI_MIN_SEPARATION:
		# Full authority, straight out. Nose still points at the target (see
		# _aim_solution) so the guns stay live while separating.
		_desired_dir = away
		_desired_speed = speed_boost
		wants_boost = true
		_roll_bias = 0.0
		return

	# Hold a stand-off band. Approach speed tapers as the gap closes so the AI
	# settles into the band instead of overshooting into the separation floor.
	# The station-keeping term is deliberately gentle: the hull is aimed at the
	# target, so any inward component here becomes reverse thrust.
	var orbit := _side_vector() * _orbit_dir

	if dist > GameConfig.AI_ENGAGE_BAND_MAX:
		# Close the gap, but only as fast as the excess range allows. Arriving at
		# the band with 200 m/s of momentum means sailing straight back out of it,
		# because coasting drag is far too weak to shed that in time.
		_desired_dir = toward
		_desired_speed = clampf(
			(dist - GameConfig.AI_ENGAGE_BAND_MAX) / 220.0 * speed_cruise,
			0.0, speed_cruise)
	elif dist < GameConfig.AI_ENGAGE_BAND_MIN:
		# Inside the band: bleed off approach speed while drifting outward and
		# sideways, so the next pass starts from a stable orbit.
		_desired_dir = (away * 0.7 + orbit * 0.6).normalized()
		_desired_speed = speed_cruise * 0.55
	else:
		# In the sweet spot: station-keep and orbit. A small constant inward bias
		# cancels whatever outward drift the approach left behind, which the
		# velocity controller alone cannot shed at this thrust authority.
		_desired_dir = (toward * 0.4 + orbit * 0.8).normalized()
		_desired_speed = speed_cruise * 0.5

	# The nose is handled by _apply_steering; _desired_dir is only the direction
	# we want to travel in, so it stays purely a manoeuvring input.

	# Random jinks make dogfights readable. Skipped at close range, where there
	# is no room to jink and the priority is simply not colliding.
	if dist > GameConfig.AI_ENGAGE_BAND_MIN \
			and _rng.randf() < GameConfig.AI_DODGE_CHANCE * reaction * skill * 2.0:
		_pick_evade_vector(dist)

	if _rng.randf() < 0.25:
		_orbit_dir = -_orbit_dir
	_roll_bias = _rng.randf_range(-0.35, 0.35)


func _plan_patrol() -> void:
	if not _has_waypoint or global_position.distance_to(_waypoint) < 220.0:
		_waypoint = GameConfig.random_spawn_point(_rng, [global_position], 400.0)
		_has_waypoint = true
	var dir := (_waypoint - global_position).normalized()
	_desired_dir = (dir + _side_vector() * 0.25 * sin(float(Time.get_ticks_msec()) * 0.0002)).normalized()
	_desired_speed = GameConfig.AI_IDLE_SPEED
	_roll_bias = 0.0
	_burst_timer = 0.0


func _plan_patrol_if_idle() -> void:
	if state == State.PATROL:
		_plan_patrol()


## Picks a short lateral dodge: mostly sideways, only slightly away, so the AI
## breaks the enemy's firing solution without abandoning the fight.
func _pick_evade_vector(dist: float) -> void:
	var away := Vector3.UP
	if target != null and is_instance_valid(target):
		away = (global_position - target.global_position).normalized()
	var side := _side_vector()
	if side.length_squared() < 0.001:
		side = right()
	_evade_vector = (side * _orbit_dir - away * 0.25).normalized()
	_evade_timer = _rng.randf_range(0.35, 0.7)
	# Breaking off only makes sense with room to manoeuvre.
	if dist > GameConfig.AI_ENGAGE_BAND_MIN * 0.8 and _rng.randf() < 0.5:
		_set_state(State.EVADE)


func _side_vector() -> Vector3:
	var ref := Vector3.UP
	if target != null and is_instance_valid(target):
		ref = target.global_position - global_position
	if absf(ref.normalized().dot(forward())) > 0.95:
		ref = right()
	var side := forward().cross(ref.normalized())
	if side.length_squared() < 0.0001:
		side = right()
	return side.normalized()


func _predicted_aim_point() -> Vector3:
	var t := target
	# Aim from the gun, not the hull centre, so the muzzle offset is accounted
	# for instead of throwing every shot wide.
	var muzzle: Node3D = muzzle_points[0]
	var from := muzzle.global_position
	var dist := from.distance_to(t.global_position)
	var flight := dist / maxf(bolt_speed, 1.0)
	# Less skilled pilots lead less, so they whiff more.
	var lead := flight * clampf(skill, 0.4, 1.8)
	# Aim scatter is expressed as an angle: a fixed metre offset would be
	# wild at long range and useless up close.
	var spread_m: float = clampf(dist * 0.016, 0.35, 4.0) / clampf(skill, 0.4, 1.8)
	return t.global_position + t.velocity * lead + _aim_noise.normalized() * spread_m


func _aim_offset_update(delta: float) -> void:
	# Slowly wandering aim error keeps the AI from being a perfect turret.
	var amount := 3.0 / clampf(skill, 0.3, 2.0)
	_aim_noise = _aim_noise.lerp(Vector3(
		_rng.randfn(0.0, amount),
		_rng.randfn(0.0, amount),
		_rng.randfn(0.0, amount)
	), delta * 1.1)


func _set_state(s: int) -> void:
	if state != s:
		state = s
		_state_timer = 0.0
		if s != State.RETREAT:
			_burst_timer = 0.0


# =============================================================== steering ==

## Aiming and manoeuvring are deliberately separated, exactly as they are for a
## human pilot: the nose tracks the lead solution so the guns stay on target,
## while lateral thrust and reverse do the orbiting. Blending the travel
## direction into the nose direction (the obvious approach) points the ship
## sideways through its own dogfight and every shot misses.
func _apply_steering(delta: float) -> void:
	var dir := forward()
	var aim: Vector3 = _aim_solution()

	if aim != Vector3.ZERO:
		var to_aim := aim - global_position
		if to_aim.length_squared() > 1.0:
			dir = to_aim.normalized()
	elif _desired_dir.length_squared() > 0.001:
		dir = _desired_dir.normalized()

	if not is_finite(dir.x) or not is_finite(dir.y) or not is_finite(dir.z):
		dir = forward()

	# Keep "up" roughly world-aligned so the arena stays readable through rolls.
	var world_up := Vector3.UP
	if absf(dir.dot(world_up)) > 0.97:
		world_up = right()
	var target_basis := Basis.looking_at(dir, world_up)
	if absf(_roll_bias) > 0.01:
		target_basis = target_basis.rotated(Vector3.BACK, -_roll_bias)

	var rate := GameConfig.AI_TURN_RATE * clampf(skill, 0.4, 1.8)
	if state == State.EVADE:
		rate = GameConfig.AI_TURN_RATE_FAST
	elif state == State.RETREAT:
		rate *= 1.2
	var t: float = clampf(rate * delta, 0.0, 1.0)

	var current := global_transform.basis
	current = current.slerp(target_basis, t)
	global_transform.basis = current.orthonormalized()


## Where the nose should point right now: the lead solution in a fight, the
## travel direction while patrolling.
func _aim_solution() -> Vector3:
	if state == State.PATROL or state == State.RETREAT:
		return Vector3.ZERO
	if target == null or not is_instance_valid(target) or target.dead:
		return Vector3.ZERO
	return _predicted_aim_point()


## Converts the intended travel direction into thrust commands, given that the
## nose is already pointing at (or away from) the target.
## Translates the intended travel vector into thrust commands.
##
## This is a velocity controller, not a "point at where I want to go" scheme.
## The hull is aimed at the target while it manoeuvres, so projecting the
## travel direction onto the ship's axes and treating that as throttle is what
## made earlier versions fly backwards or flee the arena: a nose-on-target ship
## sees "travel away" as a negative nose component, which the code then read as
## a throttle reduction instead of reverse thrust, and any error fed itself.
##
## Instead: compute the desired world velocity, subtract the actual one, and
## convert that error vector into per-axis thrust. Sign, braking and reversing
## all fall out of the arithmetic instead of being special-cased.
func _apply_translation(delta: float) -> void:
	var travel := _desired_dir
	if travel.length_squared() < 0.0001:
		cmd_forward = move_toward(cmd_forward, 0.0, delta * 3.0)
		cmd_right = move_toward(cmd_right, 0.0, delta * 3.0)
		cmd_up = move_toward(cmd_up, 0.0, delta * 3.0)
		return
	travel = travel.normalized()

	var error := travel * _desired_speed - velocity
	# Per-axis limits mirror the real thruster strengths, so a sideways demand
	# never gets met by cheating with the (much stronger) main drive.
	var fwd_cmd := clampf(error.dot(forward()) / maxf(thrust_main, 1.0), -1.0, 1.0)
	var right_cmd := clampf(error.dot(right()) / maxf(thrust_lateral, 1.0), -1.0, 1.0)
	var up_cmd := clampf(error.dot(up()) / maxf(thrust_vertical, 1.0), -1.0, 1.0)

	_cmd_forward = fwd_cmd
	cmd_forward = move_toward(cmd_forward, fwd_cmd, delta * 8.0)
	cmd_right = move_toward(cmd_right, right_cmd, delta * 8.0)
	cmd_up = move_toward(cmd_up, up_cmd, delta * 8.0)

	if state == State.PATROL:
		wants_boost = false


# =============================================================== weapons ==

func _apply_weapons(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		_burst_timer = 0.0
		_burst_len = 0.0
		return
	if state == State.RETREAT:
		return

	_burst_timer -= delta
	if _burst_len <= 0.0:
		# Cooldown between bursts, then a chance to open one.
		_burst_gap -= delta
		if _burst_gap <= 0.0 and _rng.randf() < 0.35 * skill:
			_burst_len = _rng.randf_range(GameConfig.AI_BURST_LEN * 0.4, GameConfig.AI_BURST_LEN)
			_burst_timer = 0.0
		return

	if _burst_timer <= 0.0:
		# Fire a single bolt if the target is roughly in front and in sight.
		var muzzle: Node3D = muzzle_points[0]
		var to_target: Vector3 = target.global_position - muzzle.global_position
		var ang := rad_to_deg(forward().angle_to(to_target.normalized()))
		if ang <= GameConfig.AI_FIRE_CONE_DEG and _has_line_of_sight(muzzle.global_position):
			# Point the cannons at the lead solution so bursts actually connect.
			aim_point = _predicted_aim_point()
			fire(1)
			_burst_len = maxf(0.0, _burst_len - fire_interval)
			_burst_timer = fire_interval * _rng.randf_range(0.9, 1.1)
		else:
			_burst_timer = 0.08
		if _burst_len <= 0.0:
			_burst_gap = GameConfig.AI_BURST_GAP * _rng.randf_range(0.7, 1.4)


func _has_line_of_sight(from: Vector3) -> bool:
	var to: Vector3 = target.global_position
	var query := PhysicsRayQueryParameters3D.create(from, to, GameConfig.WEAPON_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	return collider == target
