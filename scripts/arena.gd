extends Node3D
## Builds a local debris field around dense, airless gravity anchors.
## The real planet is a distant sky feature; local obstacles share ship scale.
##
## Everything is generated from `seed_value`, so a run is reproducible.

const STARFIELD := preload("res://scripts/starfield.gd")
const STAR_BODY := preload("res://scripts/star_body.gd")
const ASTEROID := preload("res://scenes/world/asteroid.tscn")

const BOUNDARY_SHADER := preload("res://shaders/boundary.gdshader")
const SUN_DIRECTION := Vector3(0.86, 0.32, -0.40)

@export var seed_value := 20260101

@export_group("Rock field")
@export var asteroid_count := 46
@export var asteroid_min_radius := 3.0
@export var asteroid_max_radius := 15.0

@export_group("Bodies")
@export var body_count := 2
@export var body_radius_min := 38.0
@export var body_radius_max := 62.0

var rng := RandomNumberGenerator.new()
var bodies: Array[StarBody] = []
var asteroids: Array[Asteroid] = []

var _boundary_mat: ShaderMaterial
var _boundary: MeshInstance3D
var _sun: DirectionalLight3D


func _ready() -> void:
	rng.seed = seed_value
	_build_boundary()
	_build_asteroids()
	_build_bodies()
	_configure_sun()
	# Placement includes several clearance passes after children enter the tree.
	# Their first rendered pose should already be the final, safe placement.
	reset_physics_interpolation()


# ------------------------------------------------------------ boundary ----

func _build_boundary() -> void:
	var shell := SphereMesh.new()
	shell.radius = GameConfig.ARENA_RADIUS
	shell.height = GameConfig.ARENA_RADIUS * 2.0
	shell.radial_segments = 64
	shell.rings = 32

	_boundary_mat = ShaderMaterial.new()
	_boundary_mat.shader = BOUNDARY_SHADER
	_boundary_mat.set_shader_parameter("danger", 0.0)
	_boundary_mat.set_shader_parameter("fade_distance", GameConfig.ARENA_MARGIN)

	_boundary = MeshInstance3D.new()
	_boundary.name = "Boundary"
	_boundary.mesh = shell
	_boundary.material_override = _boundary_mat
	_boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boundary.extra_cull_margin = 2000.0
	add_child(_boundary)

# --------------------------------------------------------------- bodies ---

func _build_bodies() -> void:
	var root := Node3D.new()
	root.name = "Bodies"
	add_child(root)

	for i in body_count:
		var radius: float = rng.randf_range(body_radius_min, body_radius_max)
		var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0))
		if dir.length_squared() < 0.01:
			dir = Vector3.FORWARD
		dir = dir.normalized() * rng.randf_range(180.0, 420.0)
		dir.y *= 0.55

		var body: StarBody = STAR_BODY.new()
		body.name = "GravityAnchor%d" % i
		body.radius = radius
		body.gravity_strength = 20.0 + radius * 0.45
		body.well_radius = radius * 6.5
		body.spin_speed = rng.randf_range(0.004, 0.012) * (1.0 if rng.randf() < 0.5 else -1.0)
		body.body_seed = rng.randi()
		body.body_kind = 1 if rng.randf() < 0.7 else 0
		root.add_child(body)
		body.global_position = dir
		bodies.append(body)

		# Companion rubble sits nearby. It has no toy moon orbit: visible orbital
		# motion over a few seconds would imply an implausibly small solar system.
		if rng.randf() < 0.6:
			var moon: StarBody = STAR_BODY.new()
			moon.name = "CompanionRock%d" % i
			moon.radius = radius * rng.randf_range(0.22, 0.34)
			moon.gravity_strength = 0.0
			moon.well_radius = 0.0
			moon.spin_speed = rng.randf_range(0.008, 0.025)
			moon.body_seed = rng.randi()
			moon.body_kind = 0
			moon.orbit_speed = 0.0
			moon.orbit_radius = radius * rng.randf_range(3.2, 4.6)
			moon.orbit_center = dir
			moon.orbit_tilt = rng.randf_range(-0.5, 0.5)
			root.add_child(moon)
			moon.global_position = dir + Vector3(moon.orbit_radius, 0.0, 0.0)
			bodies.append(moon)

	# Bodies were placed after the rock field, so clear any rock that ended up
	# inside a gravity anchor or companion rock.
	for a: Asteroid in asteroids:
		_push_out_of_bodies(a, a.radius)


# ------------------------------------------------------------ asteroids ---

func _build_asteroids() -> void:
	var root := Node3D.new()
	root.name = "Asteroids"
	add_child(root)

	for i in asteroid_count:
		# Cube-root distribution: mostly small rocks, a few big ones.
		var t := pow(rng.randf(), 2.1)
		var radius: float = lerpf(asteroid_min_radius, asteroid_max_radius, t)
		var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0))
		if dir.length_squared() < 0.01:
			dir = Vector3.FORWARD
		dir = dir.normalized() * rng.randf_range(GameConfig.ARENA_RADIUS * 0.25, GameConfig.ARENA_RADIUS * 0.88)

		var rock := ASTEROID.instantiate()
		rock.name = "Rock%d" % i
		rock.radius = radius
		rock.rock_seed = rng.randi()
		root.add_child(rock)
		rock.global_position = dir
		asteroids.append(rock)

	# Second pass: shove any rock that overlaps a body out to a safe shell.
	for a: Asteroid in asteroids:
		_push_out_of_bodies(a, a.radius)
	# Third pass: keep rocks from spawning on top of each other.
	for i in asteroids.size():
		for j in range(i + 1, asteroids.size()):
			var a: Asteroid = asteroids[i]
			var b: Asteroid = asteroids[j]
			var min_d: float = (a.radius + b.radius) * 1.15
			var d := a.global_position.distance_to(b.global_position)
			if d < min_d and d > 0.001:
				var push := (a.global_position - b.global_position).normalized() * (min_d - d)
				a.global_position += push * 0.5
				b.global_position -= push * 0.5


func _push_out_of_bodies(node: Node3D, node_radius: float) -> void:
	for body: StarBody in bodies:
		var safe := body.radius + node_radius * 1.5 + 40.0
		var d := node.global_position - body.global_position
		var dist := d.length()
		if dist < safe:
			if dist < 0.001:
				d = Vector3.RIGHT
				dist = 0.001
			node.global_position = body.global_position + d.normalized() * safe


# ------------------------------------------------------------------ sun ---

func _configure_sun() -> void:
	_sun = get_node_or_null("Sun") as DirectionalLight3D
	if _sun == null:
		_sun = DirectionalLight3D.new()
		_sun.name = "Sun"
		add_child(_sun)
	# Light rays travel along -Z; the visible star lies in the opposite direction.
	_sun.rotation = Basis.looking_at(-SUN_DIRECTION.normalized(), Vector3.UP).get_euler()
	_sun.light_color = Color(1.0, 0.91, 0.76)
	_sun.light_energy = 2.25
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 900.0
	_sun.shadow_bias = 0.04

	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "FillLight"
		add_child(fill)
	fill.rotation = Vector3(deg_to_rad(24.0), deg_to_rad(-135.0), 0.0)
	fill.light_color = Color(0.45, 0.53, 0.61)
	fill.light_energy = 0.12
	fill.shadow_enabled = false
	var world_environment := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_environment != null and world_environment.environment != null:
		var sky := world_environment.environment.sky
		if sky != null and sky.sky_material is ShaderMaterial:
			var sky_material := sky.sky_material as ShaderMaterial
			sky_material.set_shader_parameter("compatibility_srgb", RenderingServer.get_current_rendering_method() == "gl_compatibility")
			sky_material.set_shader_parameter("sun_direction", SUN_DIRECTION.normalized())
			sky_material.set_shader_parameter("planet_direction", Starfield.PLANET_DIRECTION.normalized())
			sky_material.set_shader_parameter("planet_angular_radius", Starfield.PLANET_ANGULAR_RADIUS)


# --------------------------------------------------------------- runtime --

## 0..1 — how close the nearest ship is to the wall. Drives the boundary tint.
func danger_level() -> float:
	var limit := GameConfig.ARENA_RADIUS - GameConfig.ARENA_MARGIN
	var worst := 0.0
	for node: Node in get_tree().get_nodes_in_group("ships"):
		var ship := node as SpaceShip
		if ship == null or ship.dead:
			continue
		var d := ship.global_position.length()
		worst = maxf(worst, clampf((d - limit) / GameConfig.ARENA_MARGIN, 0.0, 1.0))
	return worst


func _process(_delta: float) -> void:
	if _boundary_mat != null:
		_boundary_mat.set_shader_parameter("danger", danger_level())


## Safe spot to drop a ship: inside the playfield, away from rocks and bodies.
func spawn_position(avoid: Array = [], min_ship_dist := 260.0) -> Vector3:
	var best := Vector3.ZERO
	var best_distance_squared := -1.0
	var preferred_distance_squared := min_ship_dist * min_ship_dist
	# A small squadron still gets the full requested separation. A large fleet
	# can fill that shell, so search a wider safe shell instead of stacking
	# every remaining pilot at one fixed fallback point.
	for attempt in 1244:
		var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0))
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()
		dir.y *= 0.6
		dir = dir.normalized()
		var outer_fraction := 0.72 if attempt < 220 else 0.84
		var candidate := dir * rng.randf_range(GameConfig.ARENA_RADIUS * 0.35, GameConfig.ARENA_RADIUS * outer_fraction)

		var ok := true
		for body: StarBody in bodies:
			if candidate.distance_to(body.global_position) < body.radius + 220.0:
				ok = false
				break
		if not ok:
			continue
		for rock: Asteroid in asteroids:
			if rock.dead:
				continue
			if candidate.distance_to(rock.global_position) < rock.radius + 120.0:
				ok = false
				break
		if not ok:
			continue
		var nearest_squared := INF
		for other: Vector3 in avoid:
			nearest_squared = minf(nearest_squared, candidate.distance_squared_to(other))
		if nearest_squared >= preferred_distance_squared:
			return candidate
		if nearest_squared > best_distance_squared:
			best_distance_squared = nearest_squared
			best = candidate
	return best
