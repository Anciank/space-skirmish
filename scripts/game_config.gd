extends Node
## Central tuning table for the whole demo.
##
## Everything balance related lives here so the numbers can be tweaked in one
## place instead of being scattered across the ship / AI / weapon scripts.

# ---------------------------------------------------------------- arena ----
const ARENA_RADIUS := 900.0
## Distance from the wall where the soft "return to combat zone" force kicks in.
const ARENA_MARGIN := 140.0
## Extra acceleration applied when a ship drifts past the wall.
const ARENA_PUSH := 90.0
## Maximum speed a ship may reach while outside the playfield.
const ARENA_HARD_SPEED := 60.0

# --------------------------------------------------------- physics layers -
# 1 = world (planets, boundaries)   2 = ships   3 = weapons   4 = asteroids
const LAYER_WORLD := 1
const LAYER_SHIP := 2
const LAYER_WEAPON := 4
const LAYER_ROCK := 8

## Ships collide with the world, rocks and each other — never with bolts
## (bolts are raycasts, so this only matters for physical contacts).
const SHIP_MASK := LAYER_WORLD | LAYER_SHIP | LAYER_ROCK
const WEAPON_MASK := LAYER_WORLD | LAYER_SHIP | LAYER_ROCK
const ROCK_MASK := LAYER_WORLD | LAYER_ROCK

# ---------------------------------------------------------------- teams ----
const TEAM_BLUE := 0
const TEAM_RED := 1
const TEAM_NAMES := {TEAM_BLUE: "AZURE", TEAM_RED: "CRIMSON"}
const TEAM_COLORS := {
	TEAM_BLUE: Color(0.30, 0.66, 1.0),
	TEAM_RED: Color(1.0, 0.33, 0.30),
}

# ------------------------------------------------------------ ship stats ---
## Base hull / shield / speed numbers. Every ship class derives from these.
const HULL_MAX := 100.0
const SHIELD_MAX := 100.0
const SHIELD_REGEN_DELAY := 3.2
const SHIELD_REGEN_RATE := 22.0

const SPEED_CRUISE := 95.0
const SPEED_BOOST := 235.0
const THRUST_MAIN := 78.0
## Additional forward acceleration while the afterburner is engaged.
const THRUST_AFTERBURNER := 150.0
const THRUST_REVERSE := 42.0
const THRUST_LATERAL := 46.0
const THRUST_VERTICAL := 36.0
## Linear drag per second while coasting (higher = floatier stop).
const DRIFT_DAMPING := 0.55
## Drag applied to velocity that exceeds the current speed cap. This is what
## makes the afterburner feel strong: you keep your momentum when you release it.
const OVERSPEED_DAMPING := 2.6

const BOOST_MAX := 100.0
const BOOST_DRAIN := 26.0
const BOOST_REGEN := 15.0
const BOOST_REGEN_DELAY := 1.1
## Minimum energy needed before the burner will re-engage (prevents stuttering).
const BOOST_MIN_TO_ENGAGE := 12.0

const COLLISION_DAMAGE := 2.6
## Impacts slower than this are harmless nudges.
const COLLISION_MIN_SPEED := 12.0

# ------------------------------------------------------------- weapons ----
const FIRE_INTERVAL := 0.05
const BOLT_SPEED := 620.0
const BOLT_DAMAGE := 3.0
const BOLT_LIFETIME := 1.4
const BOLT_RADIUS := 0.18
## Standard deviation of the cannons' angular dispersion, in degrees.
const WEAPON_SPREAD := 0.3
## Assist needs a contact near the sight and a physically reachable gun angle.
const PLAYER_AIM_CONE_DEG := 4.0
const PLAYER_GUN_CONE_DEG := 12.0
## Muzzle velocity kick applied to the shooter, as a fraction of BOLT_SPEED per
## shot. Deliberately tiny: at the autocannon's 20 shots/sec anything larger
## becomes a continuous shove that measurably pushes the ship backwards, which
## is most of the reason a naive AI can never close on a target.
const WEAPON_RECOIL := 0.000085
const WEAPON_HEAT_PER_SHOT := 0.6

# ------------------------------------------------------------------ AI ----
const AI_TURN_RATE := 1.7
const AI_TURN_RATE_FAST := 3.1
const AI_ROLL_RATE := 2.4
const AI_AGGRO_RANGE := 620.0
const AI_IDLE_SPEED := 55.0
## Dogfight stand-off band, in metres. Pilots try to sit inside this window:
## close enough to shoot, far enough to keep turning room.
const AI_ENGAGE_BAND_MIN := 90.0
const AI_ENGAGE_BAND_MAX := 200.0
## Hard floor: below this the AI stops dogfighting and just separates.
const AI_MIN_SEPARATION := 55.0
## Beyond this the target is considered lost.
const AI_MAX_RANGE := 700.0
const AI_FIRE_CONE_DEG := 4.0
const AI_BURST_GAP := 0.55
const AI_BURST_LEN := 0.85
## A pilot who breaks off comes back around after this long even if they are
## still hurt — hull never regenerates, so RETREAT has to be time-boxed.
const AI_RETREAT_DURATION := 7.0
## Give a pilot time to fight again before another emergency breakaway.
const AI_RETREAT_COOLDOWN := 10.0
const AI_TARGET_SCAN_INTERVAL := 0.55
## A new contact must be meaningfully better to interrupt the current fight.
const AI_TARGET_SWITCH_MARGIN := 65.0
const AI_THREAT_LOOKAHEAD := 0.85
const AI_EVADE_COOLDOWN := 1.25
const AI_NAV_LOOKAHEAD := 2.2
const AI_VELOCITY_GAIN := 1.8
## Remaining hull percentage with shields depleted; full shields defer panic.
const AI_PANIC_HULL := 34.0

# ---------------------------------------------------------------- match ---
const MATCH_SECONDS := 300.0
const RESPAWN_DELAY := 4.0
const KILLFEED_MAX := 6
const KILLFEED_TIME := 7.0


static func team_color(team: int) -> Color:
	return TEAM_COLORS.get(team, Color.WHITE)


static func team_name(team: int) -> String:
	return TEAM_NAMES.get(team, "NEUTRAL")


static func is_enemy(a: int, b: int) -> bool:
	return a != b


static func effects_parent(source: Node) -> Node:
	var cursor := source
	while cursor != null:
		if cursor.has_node("Effects"):
			return cursor.get_node("Effects")
		cursor = cursor.get_parent()
	var scene := source.get_tree().current_scene
	return scene if scene != null else source.get_tree().root


## Evenly spread spawn points on a shell inside the arena, biased away from the
## centre so ships never start inside a planet.
static func spawn_points(count: int, rng: RandomNumberGenerator) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var radius := ARENA_RADIUS * 0.66
	var guard := 0
	while points.size() < count and guard < 400:
		guard += 1
		var dir := Vector3(
			rng.randfn(0.0, 1.0),
			rng.randfn(0.0, 1.0),
			rng.randfn(0.0, 1.0)
		)
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()
		# Nudge the latitude away from the poles so the ring reads as a ring.
		dir.y *= 0.55
		dir = dir.normalized()
		var candidate := dir * radius
		var ok := true
		for p: Vector3 in points:
			if p.distance_to(candidate) < 260.0:
				ok = false
				break
		if ok:
			points.append(candidate)
	return points


static func random_spawn_point(rng: RandomNumberGenerator, avoid: Array = [], min_dist := 220.0) -> Vector3:
	var radius := ARENA_RADIUS * 0.7
	for _i in 200:
		var dir := Vector3(
			rng.randfn(0.0, 1.0),
			rng.randfn(0.0, 1.0),
			rng.randfn(0.0, 1.0)
		)
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()
		dir.y *= 0.6
		dir = dir.normalized()
		var candidate := dir * radius
		var ok := true
		for other in avoid:
			var p: Vector3 = other
			if candidate.distance_to(p) < min_dist:
				ok = false
				break
		if ok:
			return candidate
	return Vector3(0, 0, ARENA_RADIUS * 0.7)
