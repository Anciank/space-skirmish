class_name Spark
extends Node3D
## Tiny pooled effect: an expanding additive disc + point light that lives for a
## fraction of a second. Used for bolt impacts and shield hits.

var life := 0.22
var start_scale := 0.6
var end_scale := 2.4
var color := Color(1, 0.7, 0.3)

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _elapsed := 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mesh.mesh = quad
	var mat := MeshFactory.make_glow_material(color, 4.0)
	# Billboarding lives on the material, not the mesh instance.
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 3.0
	_light.omni_range = 12.0
	_light.shadow_enabled = false
	add_child(_light)


func setup(point: Vector3, normal: Vector3, tint: Color) -> void:
	global_position = point + normal * 0.15
	color = tint
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		(_mesh.material_override as StandardMaterial3D).emission = tint
	# Face the disc away from whatever it struck.
	if normal.length_squared() > 0.001:
		look_at(global_position + normal, Vector3.UP)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / life, 0.0, 1.0)
	var eased := t * t
	if _mesh != null:
		_mesh.scale = Vector3.ONE * lerpf(start_scale, end_scale, eased)
		var mat := _mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = lerpf(5.0, 0.2, eased)
			mat.albedo_color = Color(color.r, color.g, color.b, 1.0 - eased)
	if _light != null:
		_light.light_energy = lerpf(4.0, 0.0, eased)
	if t >= 1.0:
		queue_free()
