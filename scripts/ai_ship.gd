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
## Seconds between tactical decisions. Better pilots react sooner.
@export var reaction := 0.14

var state: int = State.PATROL
var target: SpaceShip = null

var _state_timer := 0.0
var _decision_timer := 0.0
var _orbit_dir := 1.0
var _orbit_switch_timer := 4.0
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
var _aim_noise_goal := Vector3.ZERO
var _aim_noise_timer := 0.0
var _target_scan_timer := 0.0
var _evade_cooldown := 0.0
var _retreat_cooldown := 0.0
var _attacker_memory := 0.0
var _recent_attacker: SpaceShip
var _damage_pressure := 0.0
var _travel_priority := false
var _burst_hold_timer := 0.0


func _ready() -> void:
	super()
	took_damage.connect(_on_combat_damage)
	_desired_dir = forward()
	_think()


func reset_for_spawn() -> void:
	super()
	state = State.PATROL
	target = null
	_recent_attacker = null
	_state_timer = 0.0
	_decision_timer = 0.0
	_target_scan_timer = 0.0
	_attacker_memory = 0.0
	_damage_pressure = 0.0
	_retreat_timer = 0.0
	_retreat_cooldown = 0.0
	_evade_timer = 0.0
	_evade_cooldown = 0.0
	_evade_vector = Vector3.ZERO
	_burst_timer = 0.0
	_burst_len = 0.0
	_burst_gap = 0.0
	_burst_hold_timer = 0.0
	_has_waypoint = false
	_waypoint = Vector3.ZERO
	_desired_dir = forward()
	_desired_speed = 0.0
	_cmd_forward = 0.0
	_roll_bias = 0.0
	_aim_noise = Vector3.ZERO
	_aim_noise_goal = Vector3.ZERO
	_aim_noise_timer = 0.0
	_travel_priority = false
	_orbit_dir = -1.0 if _rng.randf() < 0.5 else 1.0
	_orbit_switch_timer = _rng.randf_range(4.0, 7.0)


func _physics_process(delta: float) -> void:
	if dead:
		super(delta)
		return

	_state_timer += delta
	_decision_timer -= delta
	_evade_timer -= delta
	_orbit_switch_timer -= delta
	_target_scan_timer -= delta
	_evade_cooldown -= delta
	_retreat_cooldown -= delta
	_attacker_memory -= delta
	_damage_pressure -= delta
	if state == State.RETREAT:
		_retreat_timer -= delta

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
	_travel_priority = false
	_acquire_target()
	# Effective health: a pilot sitting on full shields is not in danger yet.
	var hp_ratio := (hull + shield) / maxf(hull_max + shield_max, 1.0)

	if target == null or not is_instance_valid(target) or target.dead:
		target = null
		if state == State.RETREAT:
			_retreat_cooldown = GameConfig.AI_RETREAT_COOLDOWN
			_retreat_timer = 0.0
		_set_state(State.PATROL)
		_plan_patrol()
		_avoid_hazards()
		return

	var dist := global_position.distance_to(target.global_position)
	var panic := _panic_threshold()
	if hp_ratio < panic and state != State.RETREAT and _retreat_cooldown <= 0.0:
		_set_state(State.RETREAT)
		_retreat_timer = GameConfig.AI_RETREAT_DURATION
	if state == State.RETREAT:
		# Break off to shake pursuers, then come back around and take pot shots.
		# Time-boxed, because hull damage never heals.
		if hp_ratio > panic * 1.25 or _retreat_timer <= 0.0:
			_set_state(State.ENGAGE)
			_retreat_cooldown = GameConfig.AI_RETREAT_COOLDOWN
	if state == State.EVADE and _evade_timer <= 0.0:
		_set_state(State.ENGAGE)
	if state == State.ENGAGE and _evade_cooldown <= 0.0 \
			and dist > GameConfig.AI_MIN_SEPARATION * 1.2:
		var threat := _incoming_threat()
		if threat != Vector3.ZERO or _damage_pressure > 0.0:
			_pick_evade_vector(dist, threat)

	match state:
		State.RETREAT:
			_desired_dir = (global_position - target.global_position).normalized()
			_desired_speed = speed_boost * 0.92
			wants_boost = true
		State.EVADE:
			_set_desired_velocity(target.velocity + _evade_vector * speed_cruise * 0.8)
			wants_boost = false
		_:
			_set_state(State.ENGAGE)
			_plan_combat(dist)

	_avoid_hazards()


func _panic_threshold() -> float:
	## AI_PANIC_HULL is authored as "percent of max hull"; convert it to the
	## combined hull+shield pool that _think() actually measures against.
	return hull_max * GameConfig.AI_PANIC_HULL / 100.0 / maxf(hull_max + shield_max, 1.0)


func _acquire_target() -> void:
	var retained := _valid_enemy(target) and global_position.distance_to(target.global_position) < GameConfig.AI_MAX_RANGE
	if retained and _target_scan_timer > 0.0:
		return
	_target_scan_timer = GameConfig.AI_TARGET_SCAN_INTERVAL / clampf(skill, 0.5, 1.8)
	var best: SpaceShip = null
	var best_score := INF
	var current_score := _target_score(target) if retained else INF
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var other := node as SpaceShip
		if not _valid_enemy(other):
			continue
		var d := global_position.distance_to(other.global_position)
		if d > GameConfig.AI_AGGRO_RANGE:
			continue
		var score := _target_score(other)
		if score < best_score:
			best_score = score
			best = other
	if retained and (best == null or best_score + GameConfig.AI_TARGET_SWITCH_MARGIN >= current_score):
		return
	if target != best:
		_burst_len = 0.0
		_burst_hold_timer = 0.0
	target = best


func _valid_enemy(other: Variant) -> bool:
	# A target can be freed between reaction ticks during a redeploy. Accept
	# the reference first, then validate it before treating it as a ship.
	return is_instance_valid(other) and other is SpaceShip and other != self and not other.dead and other.team != team


func _target_score(other: SpaceShip) -> float:
	var offset := other.global_position - global_position
	var distance := offset.length()
	var direction := offset.normalized()
	# Nearby contacts in front are easy to engage. An enemy aiming at us or
	# actually hitting us is more urgent than a passive contact at equal range.
	var score := distance - maxf(0.0, forward().dot(direction)) * 70.0
	if distance < 400.0:
		score -= maxf(0.0, other.forward().dot(-direction) - 0.85) / 0.15 * 85.0
	if _attacker_memory > 0.0 and other == _recent_attacker:
		score -= 150.0
	var health := clampf((other.hull + other.shield) / maxf(other.hull_max + other.shield_max, 1.0), 0.0, 1.0)
	score -= (1.0 - health) * 45.0
	return score


func _plan_combat(dist: float) -> void:
	assert(target != null)
	wants_boost = false
	var toward := (target.global_position - global_position).normalized()
	if dist < GameConfig.AI_MIN_SEPARATION:
		# Turn the main drive into the breakaway before spending afterburner.
		_travel_priority = true
		_desired_dir = -toward
		_desired_speed = speed_boost * 0.9
		wants_boost = true
		_roll_bias = 0.0
		return

	# Match the target's motion, then correct range relative to it. Otherwise
	# even a steady sideways target outruns a pilot orbiting a fixed point.
	var preferred_range := (GameConfig.AI_ENGAGE_BAND_MIN + GameConfig.AI_ENGAGE_BAND_MAX) * 0.5
	var radial_speed := clampf((dist - preferred_range) * 0.75, -speed_cruise * 0.7, speed_cruise)
	if dist > GameConfig.AI_ENGAGE_BAND_MAX + 180.0 and boost >= GameConfig.BOOST_MIN_TO_ENGAGE:
		wants_boost = true
		radial_speed = minf((dist - preferred_range) * 0.75, speed_boost * 0.9)
	var orbit_weight := clampf(1.0 - (dist - GameConfig.AI_ENGAGE_BAND_MAX) / 220.0, 0.0, 1.0)
	var orbit_velocity := _side_vector() * _orbit_dir * speed_cruise * 0.38 * orbit_weight
	_set_desired_velocity(target.velocity + toward * radial_speed + orbit_velocity,
		speed_boost if wants_boost else speed_cruise)

	if _orbit_switch_timer <= 0.0:
		_orbit_switch_timer = _rng.randf_range(4.0, 7.0)
		_orbit_dir = -_orbit_dir
	_roll_bias = -_orbit_dir * 0.18


func _set_desired_velocity(value: Vector3, cap := -1.0) -> void:
	var limit := speed_cruise if cap < 0.0 else cap
	var travel := value.limit_length(limit)
	_desired_speed = travel.length()
	_desired_dir = travel.normalized()


func _plan_patrol() -> void:
	if not _has_waypoint or global_position.distance_to(_waypoint) < 220.0:
		_waypoint = GameConfig.random_spawn_point(_rng, [global_position], 400.0)
		_has_waypoint = true
	_desired_dir = (_waypoint - global_position).normalized()
	_desired_speed = GameConfig.AI_IDLE_SPEED
	_roll_bias = 0.0
	wants_boost = false
	_burst_len = 0.0


func _on_combat_damage(_amount: float, _position: Vector3, attacker: Node) -> void:
	var enemy := attacker as SpaceShip
	if _valid_enemy(enemy):
		_recent_attacker = enemy
		_attacker_memory = 3.0
		_damage_pressure = 0.65
		_target_scan_timer = 0.0


## React only to hostile rounds that are approaching and will pass near us.
## This runs at the pilot's reaction rate, with a cooldown between jinks.
func _incoming_threat() -> Vector3:
	var soonest := INF
	var threat := Vector3.ZERO
	for node: Node in get_tree().get_nodes_in_group("bolts"):
		var bolt := node as LaserBolt
		if bolt == null:
			continue
		var shooter := bolt.attacker as SpaceShip if is_instance_valid(bolt.attacker) else null
		var bolt_team: int = shooter.team if shooter != null else int(bolt._credit.get("team", team))
		if bolt_team == team:
			continue
		var relative := bolt.velocity - velocity
		var offset := bolt.global_position - global_position
		if relative.length_squared() < 1.0 or offset.dot(relative) >= 0.0:
			continue
		var time := -offset.dot(relative) / relative.length_squared()
		var horizon := GameConfig.AI_THREAT_LOOKAHEAD * clampf(skill, 0.6, 1.5)
		if time <= 0.0 or time > minf(horizon, bolt.lifetime - bolt._age):
			continue
		if (offset + relative * time).length() > collision_radius + 6.0:
			continue
		if time < soonest:
			soonest = time
			threat = relative
	return threat


func _pick_evade_vector(_dist: float, threat := Vector3.ZERO) -> void:
	var direction := threat.normalized()
	if direction == Vector3.ZERO and is_instance_valid(target):
		direction = (global_position - target.global_position).normalized()
	var side := direction.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)
	if side.length_squared() < 0.001:
		side = right()
	_evade_vector = side.normalized() * _orbit_dir
	_evade_timer = _rng.randf_range(0.5, 0.8)
	_evade_cooldown = _evade_timer + GameConfig.AI_EVADE_COOLDOWN
	_damage_pressure = 0.0
	_set_state(State.EVADE)


func _side_vector() -> Vector3:
	var ref := forward()
	if is_instance_valid(target):
		ref = (target.global_position - global_position).normalized()
	var side := ref.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = ref.cross(Vector3.RIGHT)
	return side.normalized()


## Bias the flight plan around predicted collisions before using the arena's
## physical wall or hull impacts as a brake. Gun tracking remains independent
## unless an imminent collision needs the stronger main drive to escape.
func _avoid_hazards() -> void:
	var travel := _desired_dir * _desired_speed
	var correction := Vector3.ZERO
	var urgent := false
	var horizon := GameConfig.AI_NAV_LOOKAHEAD
	var probe := velocity.lerp(travel, 0.55) + _gravity * horizon * 0.25
	# An intended turn cannot erase existing momentum. Inspect the current
	# path too, plus a gravity-curved estimate near the large anchors.
	var paths: Array[Vector3] = [velocity, velocity + _gravity * horizon * 0.5, probe]
	var max_probe_speed := 0.0
	for path: Vector3 in paths:
		max_probe_speed = maxf(max_probe_speed, path.length())
	var obstacles: Array[Node] = get_tree().get_nodes_in_group("rocks")
	obstacles.append_array(get_tree().get_nodes_in_group("bodies"))
	obstacles.append_array(get_tree().get_nodes_in_group("ships"))
	for node: Node in obstacles:
		if node == self or not node is Node3D:
			continue
		var position: Vector3 = (node as Node3D).global_position
		var obstacle_velocity := Vector3.ZERO
		var obstacle_radius := 0.0
		if node is Asteroid:
			var rock := node as Asteroid
			if rock.dead:
				continue
			obstacle_velocity = rock.linear_velocity
			obstacle_radius = rock.radius * 1.3
		elif node is StarBody:
			obstacle_radius = (node as StarBody).radius * 1.3
		elif node is SpaceShip:
			var ship := node as SpaceShip
			if ship.dead:
				continue
			obstacle_velocity = ship.velocity
			obstacle_radius = ship.collision_radius
		else:
			continue
		var offset := global_position - position
		var safe_radius := obstacle_radius + collision_radius + 8.0
		# Skip distant scenery before doing closest-approach work.
		if offset.length() > safe_radius + (max_probe_speed + obstacle_velocity.length()) * horizon:
			continue
		var time := 0.0
		var nearest := offset
		for path: Vector3 in paths:
			var relative := path - obstacle_velocity
			var pass_time := clampf(-offset.dot(relative) / maxf(relative.length_squared(), 0.001), 0.0, horizon)
			var pass_offset := offset + relative * pass_time
			if pass_offset.length_squared() < nearest.length_squared():
				nearest = pass_offset
				time = pass_time
		if nearest.length() >= safe_radius or (time <= 0.0 and offset.length() >= safe_radius):
			continue
		var escape := nearest.normalized()
		# A head-on approach has no natural side. Use the same orbit direction
		# across decisions so pilots commit to passing one side of the rock.
		if nearest.length() < safe_radius * 0.25:
			escape = (-offset.normalized()).cross(Vector3.UP)
			if escape.length_squared() < 0.001:
				escape = (-offset.normalized()).cross(Vector3.RIGHT)
			escape = escape.normalized() * _orbit_dir
		var strength := clampf((safe_radius - nearest.length()) / maxf(time, 0.3) * 2.0 + 25.0, 25.0, speed_cruise * 1.4)
		correction += escape * strength
		if offset.length() < safe_radius + 12.0:
			correction += offset.normalized() * speed_cruise * 0.8
		if time < 0.7 or offset.length() < safe_radius:
			urgent = true
	if correction.length_squared() > 1.0:
		travel += correction
		wants_boost = false
		travel = travel.limit_length(speed_cruise * (0.7 if urgent else 1.0))
		_travel_priority = _travel_priority or urgent

	var distance := global_position.length()
	var outward := global_position / maxf(distance, 0.001)
	var safe_edge := GameConfig.ARENA_RADIUS - GameConfig.ARENA_MARGIN - 25.0
	var outward_speed := maxf(velocity.dot(outward), 0.0)
	var stopping_distance := outward_speed * outward_speed / (2.0 * maxf(thrust_lateral, 1.0))
	if distance + maxf(stopping_distance, outward_speed * horizon) > safe_edge:
		var allowed := clampf((safe_edge - distance) / horizon, -speed_cruise * 0.7, speed_cruise)
		travel -= outward * maxf(0.0, travel.dot(outward) - allowed)
		wants_boost = false
		if distance > GameConfig.ARENA_RADIUS - GameConfig.ARENA_MARGIN:
			_travel_priority = true
	_set_desired_velocity(travel, speed_boost if wants_boost else speed_cruise)


func _predicted_aim_point(from := Vector3.INF) -> Vector3:
	var t := target
	# Aim from the gun, not the hull centre, so the muzzle offset is accounted
	# for instead of throwing every shot wide.
	if from == Vector3.INF:
		from = muzzle_points[_muzzle_index % muzzle_points.size()].global_position
	var dist := from.distance_to(t.global_position)
	var relative_velocity := t.velocity - velocity * 0.2
	var flight := Gunnery.intercept_time(t.global_position - from, relative_velocity, bolt_speed)
	if not is_finite(flight):
		flight = dist / maxf(bolt_speed, 1.0)
	# Less skilled pilots lead less, so they whiff more.
	var lead := flight * clampf(skill, 0.4, 1.0)
	# Aim scatter is expressed as an angle: a fixed metre offset would be
	# wild at long range and useless up close.
	var spread_m: float = clampf(dist * 0.016, 0.35, 4.0) / clampf(skill, 0.4, 1.8)
	return t.global_position + relative_velocity * lead + _aim_noise.normalized() * spread_m


func _aim_offset_update(delta: float) -> void:
	# Slowly wandering aim error keeps the AI from being a perfect turret.
	_aim_noise_timer -= delta
	if _aim_noise_timer <= 0.0:
		_aim_noise_timer = reaction / maxf(skill, 0.2)
		_aim_noise_goal = Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn())
	_aim_noise = _aim_noise.lerp(_aim_noise_goal, 1.0 - exp(-delta * 1.1))


func _set_state(s: int) -> void:
	if state != s:
		state = s
		_state_timer = 0.0
		if s != State.RETREAT:
			_burst_timer = 0.0
		else:
			_burst_len = 0.0
			_burst_hold_timer = 0.0


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
		# Roll around the ship's nose. A world-Z rotation also deflects aim.
		target_basis = target_basis * Basis(Vector3.BACK, -_roll_bias)

	var rate := GameConfig.AI_TURN_RATE * clampf(skill, 0.4, 1.8)
	if state == State.EVADE:
		rate = GameConfig.AI_TURN_RATE_FAST
	elif state == State.RETREAT:
		rate *= 1.2
	var current := global_transform.basis.orthonormalized()
	var angle := current.get_rotation_quaternion().angle_to(target_basis.get_rotation_quaternion())
	# Rate is radians per second. Exponential interpolation leaves a persistent
	# angle error while orbiting, so the nose never enters its own firing cone.
	var t := clampf(rate * delta / maxf(angle, 0.000001), 0.0, 1.0)
	current = current.slerp(target_basis, t)
	global_transform.basis = current.orthonormalized()


## Where the nose should point right now: the lead solution in a fight, the
## travel direction while patrolling.
func _aim_solution() -> Vector3:
	if state == State.PATROL or state == State.RETREAT or _travel_priority:
		return Vector3.ZERO
	if target == null or not is_instance_valid(target) or target.dead:
		return Vector3.ZERO
	return _predicted_aim_point()


## Resolve the desired world velocity into the ship's real thrust axes.
## Guns can track an opponent while lateral and reverse thrust control range.
func _apply_translation(delta: float) -> void:
	var travel := _desired_dir
	travel = travel.normalized()

	# Compensate for the shared flight model's drag and gravity using real
	# thruster authority. Desired velocity can then match a moving opponent.
	var error := (travel * _desired_speed - velocity) * GameConfig.AI_VELOCITY_GAIN
	error += velocity * drift_damping - _gravity
	# The afterburner supplies forward thrust only. Save energy while turning,
	# reversing, or holding position instead of burning it for lateral motion.
	wants_boost = wants_boost and forward().dot(travel) > 0.88 and error.dot(forward()) > 5.0
	# Per-axis limits mirror the real thruster strengths, so a sideways demand
	# never gets met by cheating with the (much stronger) main drive.
	var forward_authority := thrust_main
	if wants_boost and (boosting or boost >= GameConfig.BOOST_MIN_TO_ENGAGE):
		forward_authority += GameConfig.THRUST_AFTERBURNER
	var fwd_cmd := clampf(error.dot(forward()) / maxf(forward_authority, 1.0), -1.0, 1.0)
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
	if not _valid_enemy(target):
		_burst_timer = 0.0
		_burst_len = 0.0
		_burst_hold_timer = 0.0
		return
	if state == State.RETREAT or state == State.PATROL or _travel_priority:
		return

	_burst_timer -= delta
	if _burst_len <= 0.0:
		_burst_gap -= delta
		if _burst_gap > 0.0:
			return
		# One deliberate burst decision, rather than a probability per frame.
		_burst_len = _rng.randf_range(GameConfig.AI_BURST_LEN * 0.4, GameConfig.AI_BURST_LEN)
		_burst_timer = 0.0
		_burst_hold_timer = 0.0
	_burst_hold_timer += delta
	if _burst_hold_timer > 1.6:
		_finish_burst()
		return
	if _burst_timer > 0.0 or not can_fire():
		return

	var muzzle: Node3D = muzzle_points[_muzzle_index % muzzle_points.size()]
	var prediction := _predicted_aim_point(muzzle.global_position)
	var flight := Gunnery.intercept_time(target.global_position - muzzle.global_position,
		target.velocity - velocity * 0.2, bolt_speed)
	var to_aim := prediction - muzzle.global_position
	var angle := rad_to_deg(forward().angle_to(to_aim.normalized()))
	if is_finite(flight) and flight < GameConfig.BOLT_LIFETIME \
			and angle <= GameConfig.AI_FIRE_CONE_DEG \
			and _has_line_of_sight(muzzle.global_position, prediction, flight):
		aim_point = prediction
		fire(1)
		_burst_len = maxf(0.0, _burst_len - fire_interval)
		_burst_timer = fire_interval * _rng.randf_range(1.0, 1.15)
		if _burst_len <= 0.0:
			_finish_burst()
	else:
		_burst_timer = reaction / maxf(skill, 0.2)


func _finish_burst() -> void:
	_burst_len = 0.0
	_burst_hold_timer = 0.0
	_burst_gap = GameConfig.AI_BURST_GAP * _rng.randf_range(0.8, 1.3) / clampf(skill, 0.5, 1.8)


## Check where the bolt will actually travel, including inherited shooter
## motion. A clear ray to the target's current position is insufficient for
## lead shots, and a teammate can cross the path before the round arrives.
func _has_line_of_sight(from: Vector3, prediction := Vector3.ZERO, flight := -1.0) -> bool:
	if not _valid_enemy(target):
		return false
	if prediction == Vector3.ZERO:
		prediction = _predicted_aim_point(from)
	if flight < 0.0:
		flight = Gunnery.intercept_time(target.global_position - from,
			target.velocity - velocity * 0.2, bolt_speed)
	if not is_finite(flight) or flight <= 0.0 or flight >= GameConfig.BOLT_LIFETIME:
		return false
	return Gunnery.has_clear_path(self, target, from, prediction, flight)
