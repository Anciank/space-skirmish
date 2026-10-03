class_name Spark
extends Node3D
## Compact impact flash with a few hot chips moving away from the surface.
## Shield impacts use just the flash; hull and rock impacts eject material.

const SPRITE_SHADER := preload("res://shaders/soft_sprite.gdshader")
var life := 0.28
var start_scale := 0.35
var end_scale := 0.9
var color := Color(1.0, 0.76, 0.46)
var ejecta := true

var _mesh: MeshInstance3D
var _light: OmniLight3D
var _elapsed := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_mesh.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = SPRITE_SHADER
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("energy", 2.2)
	mat.set_shader_parameter("rays", 0.05)
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.scale = Vector3.ONE * start_scale
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 0.65
	_light.omni_range = 2.5
	_light.shadow_enabled = false
	add_child(_light)


func setup(point: Vector3, normal: Vector3, tint: Color) -> void:
	var outward := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	global_position = point + outward * 0.035
	color = tint
	if _light != null:
		_light.light_color = tint
	if _mesh != null:
		(_mesh.material_override as ShaderMaterial).set_shader_parameter("tint", tint)
	if ejecta:
		_spawn_ejecta(outward)


func _spawn_ejecta(outward: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 6
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = life * 0.88
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3.ONE * -5.0, Vector3.ONE * 10.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.direction = outward
	process.spread = 60.0
	process.initial_velocity_min = 5.0
	process.initial_velocity_max = 14.0
	process.gravity = Vector3.ZERO
	process.damping_min = 0.0
	process.damping_max = 0.0
	process.scale_min = 0.8
	process.scale_max = 1.8
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -300.0
	process.angular_velocity_max = 300.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, color, Color(color.r, color.g * 0.5, color.b * 0.25, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	var chip := BoxMesh.new()
	chip.size = Vector3(0.018, 0.018, 0.09)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	chip.material = material
	particles.draw_pass_1 = chip
	add_child(particles)
	particles.emitting = true


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / minf(life, 0.095), 0.0, 1.0)
	_mesh.scale = Vector3.ONE * lerpf(start_scale, end_scale, t)
	(_mesh.material_override as ShaderMaterial).set_shader_parameter("opacity", pow(1.0 - t, 3.0))
	_mesh.visible = t < 1.0
	_light.light_energy = 0.65 * pow(1.0 - t, 3.0)
	if _elapsed >= life:
		queue_free()
