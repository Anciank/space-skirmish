class_name MeshFactory
extends RefCounted
## Builds lumpy rock / planet meshes procedurally at runtime.
##
## Takes a UV sphere, pushes every vertex along its normal by layered value
## noise, then regenerates normals. Rocks get deep, high-frequency displacement;
## planets get gentle, low-frequency lobes so they read as smooth spheres.

const SPHERE_SEGMENTS := 24
const SPHERE_RINGS := 14


## `shape` picks the noise profile:
##   0 = asteroid (chunky, lots of craters)
##   1 = small moon (medium lumps)
##   2 = planet (very smooth, slight oblateness)
static func make_rock(radius: float, seed_value: int, shape := 0) -> ArrayMesh:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.06
	noise.fractal_octaves = 4 if shape == 0 else 3
	noise.fractal_gain = 0.52

	var detail := FastNoiseLite.new()
	detail.seed = seed_value + 977
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = 0.22
	detail.fractal_octaves = 2

	var squash := 1.0
	var amp := 0.30
	var amp_detail := 0.10
	match shape:
		0:
			amp = 0.34
			amp_detail = 0.13
			squash = 0.94
		1:
			amp = 0.14
			amp_detail = 0.05
			squash = 0.97
		_:
			amp = 0.055
			amp_detail = 0.018
			squash = 0.985

	var source := SphereMesh.new()
	source.radius = 1.0
	source.height = 2.0
	source.radial_segments = SPHERE_SEGMENTS
	source.rings = SPHERE_RINGS
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
		st.set_smooth_group(-1)
		st.add_vertex(p)
	for idx: int in indices:
		st.add_index(idx)

	st.generate_normals()
	return st.commit()


## Tinted rocky albedo with a subtle noise breakup baked into vertex colors.
static func make_rock_material(base: Color, seed_value: int, glow := Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = 0.92
	mat.metallic = 0.04
	mat.vertex_color_use_as_albedo = false
	if glow.a > 0.0:
		mat.emission_enabled = true
		mat.emission = glow
		mat.emission_energy_multiplier = 1.6
	return mat


## Emissive tracer bolt material. `tint` is the team colour.
static func make_bolt_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0)
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 7.0
	mat.disable_receive_shadows = true
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
