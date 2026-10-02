extends Node3D
## Builds and owns the play space: rock fields, small planets with gravity
## wells, an orbiting moon, the enclosing boundary shell and the distant sun.
##
## Everything is generated from `seed_value`, so a run is reproducible.

const STARFIELD := preload("res://scripts/starfield.gd")
const STAR_BODY := preload("res://scripts/star_body.gd")
const ASTEROID := preload("res://scenes/world/asteroid.tscn")

const BOUNDARY_SHADER := preload("res://shaders/boundary.gdshader")

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
	_boundary_mat.set_shader_parameter("grid_density", 18.0)
	_boundary_mat.set_shader_parameter("fade_distance", 340.0)

	_boundary = MeshInstance3D.new()
	_boundary.name = "Boundary"
	_boundary.mesh = shell
	_boundary.material_override = _boundary_mat
	_boundary.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_boundary.extra_cull_margin = 2000.0
	add_child(_boundary)

	# Three faint great-circle rings give the eye a sense of the sphere's shape
	# even where the grid is thin. Very dim on purpose: at full brightness they
	# read as bright wires strung across the play space.
	var ring_mat := MeshFactory.make_glow_material(Color(0.22, 0.58, 0.98), 0.16)
	ring_mat.albedo_color = Color(0.22, 0.58, 0.98, 0.22)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.FORWARD]:
		var ring := ImmediateMesh.new()
		ring.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var helper := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u := axis.cross(helper).normalized()
		var v := axis.cross(u).normalized()
		var r := GameConfig.ARENA_RADIUS * 0.995
		var steps := 200
		for i in steps:
			var t := TAU * float(i) / float(steps)
			ring.surface_set_color(Color(0.22, 0.58, 0.98, 1.0))
			ring.surface_add_vertex((u * cos(t) + v * sin(t)) * r)
		ring.surface_end()
		var mi := MeshInstance3D.new()
		mi.name = "Ring"
		mi.mesh = ring
		mi.material_override = ring_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 2000.0
		add_child(mi)


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
		body.name = "Body%d" % i
		body.radius = radius
		body.gravity_strength = 20.0 + radius * 0.45
		body.well_radius = radius * 6.5
		body.spin_speed = rng.randf_range(0.015, 0.06) * (1.0 if rng.randf() < 0.5 else -1.0)
		body.body_seed = rng.randi()
		body.body_kind = 1 if rng.randf() < 0.7 else 0
		root.add_child(body)
		body.global_position = dir
		bodies.append(body)

		# Give roughly half of the bodies a moon on a tilted orbit.
		if rng.randf() < 0.6:
			var moon: StarBody = STAR_BODY.new()
			moon.name = "Moon%d" % i
			moon.radius = radius * rng.randf_range(0.22, 0.34)
			moon.gravity_strength = 0.0
			moon.well_radius = 0.0
			moon.spin_speed = rng.randf_range(0.05, 0.12)
			moon.body_seed = rng.randi()
			moon.body_kind = 0
			moon.orbit_speed = rng.randf_range(0.06, 0.16)
			moon.orbit_radius = radius * rng.randf_range(3.2, 4.6)
			moon.orbit_center = dir
			moon.orbit_tilt = rng.randf_range(-0.5, 0.5)
			root.add_child(moon)
			moon.global_position = dir + Vector3(moon.orbit_radius, 0.0, 0.0)
			bodies.append(moon)

	# Bodies were placed after the rock field, so clear any rock that ended up
	# inside a planet or moon.
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
	_sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(41.0), 0.0)
	_sun.light_color = Color(1.0, 0.95, 0.88)
	_sun.light_energy = 1.8
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 900.0
	_sun.shadow_bias = 0.04

	var fill := get_node_or_null("FillLight") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "FillLight"
		add_child(fill)
	fill.rotation = Vector3(deg_to_rad(24.0), deg_to_rad(-135.0), 0.0)
	fill.light_color = Color(0.42, 0.55, 1.0)
	fill.light_energy = 0.5
	fill.shadow_enabled = false


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
	for _attempt in 220:
		var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0))
		if dir.length_squared() < 0.01:
			continue
		dir = dir.normalized()
		dir.y *= 0.6
		dir = dir.normalized()
		var candidate := dir * rng.randf_range(GameConfig.ARENA_RADIUS * 0.35, GameConfig.ARENA_RADIUS * 0.72)

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
		for other: Vector3 in avoid:
			if candidate.distance_to(other) < min_ship_dist:
				ok = false
				break
		if ok:
			return candidate
	return Vector3(0, 0, GameConfig.ARENA_RADIUS * 0.6)
