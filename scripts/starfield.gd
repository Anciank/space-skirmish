class_name Starfield
extends Node3D
## A few thousand emissive points baked into a single ArrayMesh, so the whole
## star field costs one draw call. Parented to the camera rig so it never gets
## closer than the arena wall and effectively reads as infinitely far away.

const COUNT := 2600
const SHELL := 5200.0
const STAR_SHADER := preload("res://shaders/soft_sprite.gdshader")

@export var radius := SHELL
@export var seed_value := 1337


func _ready() -> void:
	# Follow camera translation without inheriting its rotation: stars must
	# cross the view when the pilot turns, while retaining zero parallax.
	top_level = true
	global_basis = Basis.IDENTITY
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_mesh_points(rng)


func _mesh_points(rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var placed := 0
	var guard := 0

	while placed < COUNT and guard < COUNT * 20:
		guard += 1
		var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0))
		if dir.length_squared() < 0.02:
			continue
		dir = dir.normalized()
		var centre := dir * radius
		# Brightness distribution: many faint, few blazing.
		var mag := pow(rng.randf(), 3.2)
		var size := lerpf(5.0, 21.0, mag)
		var warm := rng.randf()
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.78, 0.58), warm * 0.7)
		tint = tint.lerp(Color(0.72, 0.82, 1.0), clampf(rng.randf() - 0.55, 0.0, 0.45))
		tint *= lerpf(0.35, 1.35, mag)
		tint.a = 1.0

		# Billboard the quad toward the arena centre — good enough at this scale.
		var right := dir.cross(Vector3.UP)
		if right.length_squared() < 0.001:
			right = dir.cross(Vector3.RIGHT)
		right = right.normalized() * size
		var up := right.cross(dir).normalized() * size

		_quad(st, centre, right, up, tint)
		placed += 1

	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	# Stars are already oriented toward the centre. Keep their world-space
	# positions rather than billboarding the whole baked mesh at its origin.
	mat.shader = STAR_SHADER
	mat.set_shader_parameter("billboard", false)
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("tint", Color.WHITE)
	mat.set_shader_parameter("energy", 1.6)
	mat.set_shader_parameter("rays", 0.1)
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "StarMesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8000.0
	add_child(mi)


func _quad(st: SurfaceTool, centre: Vector3, right: Vector3, up: Vector3, tint: Color) -> void:
	var corners := [centre - right - up, centre + right - up, centre + right + up, centre - right + up]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for index: int in [0, 1, 2, 0, 2, 3]:
		st.set_color(tint)
		st.set_uv(uvs[index])
		st.add_vertex(corners[index])
