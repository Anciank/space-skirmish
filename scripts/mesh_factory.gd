class_name MeshFactory
extends RefCounted
## Builds lumpy rock / planet meshes procedurally at runtime.
##
## Takes a sphere, displaces vertices with layered noise, then regenerates
## normals. Unit directions need noise frequencies measured across a unit
## sphere; rocks are faceted, while moons and planets have smooth normals.

const SPHERE_SEGMENTS := 24
const SPHERE_RINGS := 14
const ROCK_SHADER := preload("res://shaders/rock_surface.gdshader")
static var _bolt_material: StandardMaterial3D


## `shape` picks the noise profile:
##   0 = asteroid (chunky, lots of craters)
##   1 = moon (smooth sphere; craters live in the surface material)
##   2 = planet (smooth sphere with fine surface relief)
static func make_rock(radius: float, seed_value: int, shape := 0) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 2.8
	noise.fractal_octaves = 4 if shape == 0 else 3
	noise.fractal_gain = 0.52

	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 977
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = 10.0
	detail.fractal_octaves = 2

	var squash := 1.0
	var amp := 0.30
	var amp_detail := 0.10
	match shape:
		0:
			amp = 0.38
			amp_detail = 0.07
			squash = 0.94
		1:
			amp = 0.005
			amp_detail = 0.002
			squash = 1.0
		_:
			amp = 0.002
			amp_detail = 0.001
			squash = 1.0

	var source := SphereMesh.new()
	source.radius = 1.0
	source.height = 2.0
	source.radial_segments = SPHERE_SEGMENTS if shape == 0 else 64
	source.rings = SPHERE_RINGS if shape == 0 else 32
	var arrays := source.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in verts:
		var d: Vector3 = v.normalized()
		var n: float = noise.get_noise_3d(d.x, d.y, d.z) * amp
		var n2: float = detail.get_noise_3d(d.x, d.y, d.z) * amp_detail
		# Bias inward in a couple of spots so the silhouette gets real craters.
		var cdir := d * 2.7 + Vector3(11.0, 5.0, 3.0)
		var crater: float = detail.get_noise_3d(cdir.x, cdir.y, cdir.z)
		var r: float = 1.0 + n + n2 - maxf(crater, 0.0) * amp_detail * 1.4
		var p := d * (radius * r)
		p.y *= squash
		st.set_smooth_group(-1 if shape == 0 else 0)
		st.add_vertex(p)
	for idx: int in indices:
		st.add_index(idx)

	st.generate_normals()
	return st.commit()


## Detail in object coordinates avoids seams and stretches on displaced rocks.
static func make_rock_material(base: Color, seed_value: int, radius := 1.0, shape := 0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("body_radius", radius)
	mat.set_shader_parameter("seed_offset", float(posmod(seed_value, 1024)) * 0.037)
	mat.set_shader_parameter("body_type", shape)
	return mat


## Incandescent kinetic tracer. Ammunition has the same finish for both teams.
static func make_bolt_material(_tint: Color) -> StandardMaterial3D:
	# Hundreds of live rounds use this same immutable finish. Sharing it
	# avoids allocating and uploading a new material for every shot.
	if _bolt_material != null:
		return _bolt_material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color("ffd4a0")
	mat.emission_enabled = true
	mat.emission = Color("ffd4a0")
	mat.emission_energy_multiplier = 2.0
	mat.disable_receive_shadows = true
	_bolt_material = mat
	return mat


## Soft additive glow disc used for engine bells, muzzle flashes and shockwaves.
static func make_glow_material(tint: Color, energy := 5.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(tint.r, tint.g, tint.b, tint.a)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = energy
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	return mat
