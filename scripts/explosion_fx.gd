class_name ExplosionFx
extends Node3D
## A brief hot core, a hollow shock front and fading fragments. All parts have
## finite lifetimes and live under Effects, independently of the destroyed ship.

const SPRITE_SHADER := preload("res://shaders/soft_sprite.gdshader")
const SHELL_SHADER := preload("res://shaders/atmosphere.gdshader")

var radius := 6.0
var duration := 1.2
var tint := Color(1.0, 0.72, 0.35)

var _shell: MeshInstance3D
var _flash: MeshInstance3D
var _light: OmniLight3D
var _elapsed := 0.0


func _ready() -> void:
	_shell = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_shell.mesh = sphere
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = SHELL_SHADER
	shell_mat.set_shader_parameter("tint", tint)
	shell_mat.set_shader_parameter("density", 0.6)
	_shell.material_override = shell_mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.scale = Vector3.ONE * 0.01
	add_child(_shell)

	_flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_flash.mesh = quad
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = SPRITE_SHADER
	flash_mat.set_shader_parameter("tint", tint.lerp(Color.WHITE, 0.3))
	flash_mat.set_shader_parameter("energy", 4.0)
	flash_mat.set_shader_parameter("rays", 0.35)
	_flash.material_override = flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)

	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.light_energy = 4.0
	_light.omni_range = radius * 4.0
	_light.shadow_enabled = false
	add_child(_light)
	_burst(false)
	_burst(true)


func _burst(debris: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 14 if debris else 42
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = duration * 0.9
	particles.local_coords = false
	particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	particles.visibility_aabb = AABB(Vector3.ONE * -radius * 9.0, Vector3.ONE * radius * 18.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.12
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = radius * 1.6
	process.initial_velocity_max = radius * (5.0 if debris else 6.5)
	process.gravity = Vector3.ZERO
	process.damping_min = 0.4
	process.damping_max = 1.2
	process.scale_min = radius * (0.025 if debris else 0.035)
	process.scale_max = radius * (0.065 if debris else 0.12)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -220.0
	process.angular_velocity_max = 220.0
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.65, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 0.8, 0.55), Color(1, 0.35, 0.06, 0.7), Color(0.25, 0.08, 0.02, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	if debris:
		var shard := BoxMesh.new()
		shard.size = Vector3(0.4, 0.1, 1.0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("677583")
		material.vertex_color_use_as_albedo = true
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.7
		material.emission_enabled = true
		material.emission = Color(0.4, 0.13, 0.02)
		material.emission_energy_multiplier = 0.5
		shard.material = material
		particles.draw_pass_1 = shard
	else:
		var sprite := QuadMesh.new()
		sprite.size = Vector2.ONE
		var material := ShaderMaterial.new()
		material.shader = SPRITE_SHADER
		material.set_shader_parameter("use_vertex_color", true)
		material.set_shader_parameter("tint", tint)
		material.set_shader_parameter("energy", 3.0)
		sprite.material = material
		particles.draw_pass_1 = sprite
	add_child(particles)
	particles.emitting = true


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / duration, 0.0, 1.0)
	var front := clampf(_elapsed / 0.48, 0.0, 1.0)
	_shell.scale = Vector3.ONE * maxf(0.01, radius * (1.0 - pow(1.0 - front, 2.0)))
	(_shell.material_override as ShaderMaterial).set_shader_parameter("density", pow(1.0 - front, 2.0) * 0.6)
	_flash.scale = Vector3.ONE * radius * lerpf(0.75, 1.35, minf(_elapsed / 0.2, 1.0))
	(_flash.material_override as ShaderMaterial).set_shader_parameter("opacity", pow(maxf(0.0, 1.0 - _elapsed / 0.35), 2.0))
	_light.light_energy = 4.0 * pow(maxf(0.0, 1.0 - _elapsed / 0.45), 2.0)
	if t >= 1.0:
		queue_free()
