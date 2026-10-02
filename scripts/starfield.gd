class_name Starfield
extends Node3D
## A few thousand emissive points baked into a single ArrayMesh, so the whole
## star field costs one draw call. Parented to the camera rig so it never gets
## closer than the arena wall and effectively reads as infinitely far away.

const COUNT := 2600
const SHELL := 5200.0

@export var radius := SHELL
@export var seed_value := 1337


func _ready() -> void:
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
		var size := lerpf(6.0, 46.0, mag)
		var warm := rng.randf()
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(1.0, 0.78, 0.58), warm * 0.7)
		tint = tint.lerp(Color(0.72, 0.82, 1.0), clampf(rng.randf() - 0.55, 0.0, 0.45))
		tint *= lerpf(0.35, 1.6, mag)

		# Billboard the quad toward the arena centre — good enough at this scale.
		var right := dir.cross(Vector3.UP)
		if right.length_squared() < 0.001:
			right = dir.cross(Vector3.RIGHT)
		right = right.normalized() * size
		var up := right.cross(dir).normalized() * size

		_quad(st, centre - right - up, right, up, tint)
		_quad(st, centre + right - up, right, up, tint)
		_quad(st, centre + right + up, right, up, tint)
		_quad(st, centre - right + up, right, up, tint)
		placed += 1

	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = null
	mat.disable_receive_shadows = true
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "StarMesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8000.0
	add_child(mi)


func _quad(st: SurfaceTool, origin: Vector3, right: Vector3, up: Vector3, tint: Color) -> void:
	st.set_color(tint)
	st.add_vertex(origin)
	st.set_color(tint)
	st.add_vertex(origin + right)
	st.set_color(tint)
	st.add_vertex(origin + right + up)
	st.set_color(tint)
	st.add_vertex(origin)
	st.set_color(tint)
	st.add_vertex(origin + right + up)
	st.set_color(tint)
	st.add_vertex(origin + up)
