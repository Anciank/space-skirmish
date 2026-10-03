class_name ExplosionFx
extends Node3D
## A brief reactor flash and ballistic ejecta. In vacuum there is no visible
## pressure shell, smoke cloud or air drag; the fragments simply drift away.

const SPRITE_SHADER := preload("res://shaders/soft_sprite.gdshader")
const DEBRIS_SHADER := preload("res://shaders/debris_surface.gdshader")
static var _stone_chunk: ArrayMesh

var radius := 6.0
var duration := 1.2
var tint := Color(1.0, 0.72, 0.35)
var rock_debris := false

var _flash: MeshInstance3D
var _light: OmniLight3D
var _elapsed := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_flash = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_flash.mesh = quad
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = SPRITE_SHADER
	flash_mat.set_shader_parameter("tint", tint.lerp(Color.WHITE, 0.55))
	flash_mat.set_shader_parameter("energy", 3.6)
	flash_mat.set_shader_parameter("rays", 0.08)
	_flash.material_override = flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.scale = Vector3.ONE * radius * 0.8
	_flash.visible = not rock_debris
	add_child(_flash)

	_light = OmniLight3D.new()
	_light.light_color = tint.lerp(Color.WHITE, 0.4)
	_light.light_energy = 0.0 if rock_debris else 3.2
	_light.omni_range = radius * 3.0
	_light.shadow_enabled = false
	add_child(_light)
	if not rock_debris:
		_burst(false)
	_burst(true)


func _burst(debris: bool) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 18 if debris else 28
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.lifetime = duration * (0.92 if debris else 0.45)
	particles.local_coords = false
	particles.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	particles.visibility_aabb = AABB(Vector3.ONE * -radius * 7.0, Vector3.ONE * radius * 14.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = radius * 0.13
	process.direction = Vector3.UP
	process.spread = 180.0
	process.initial_velocity_min = radius * (0.9 if debris else 2.5)
	process.initial_velocity_max = radius * (3.7 if debris else 6.0)
	process.gravity = Vector3.ZERO
	process.damping_min = 0.0
	process.damping_max = 0.0
	process.scale_min = radius * (0.09 if debris else 0.025)
	process.scale_max = radius * (0.2 if debris else 0.07)
	process.angle_min = -180.0
	process.angle_max = 180.0
	process.angular_velocity_min = -180.0
	process.angular_velocity_max = 180.0
	var gradient := Gradient.new()
	if debris:
		# The metal remains a dark, lit solid after the hot surface has cooled.
		gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.8, 1.0])
		var first_color := Color.WHITE if rock_debris else Color(1.0, 0.8, 0.58)
		var cold_color := Color.WHITE if rock_debris else Color(0.55, 0.55, 0.54)
		gradient.colors = PackedColorArray([first_color, cold_color, cold_color, Color(cold_color.r, cold_color.g, cold_color.b, 0.0)])
	else:
		gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.5, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1.0, 0.83, 0.56), Color(1.0, 0.4, 0.08, 0.4), Color(0.5, 0.12, 0.02, 0.0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = gradient
	process.color_ramp = ramp
	particles.process_material = process
	if debris:
		var shard: Mesh
		if rock_debris:
			if _stone_chunk == null:
				_stone_chunk = MeshFactory.make_rock(0.45, 73)
			shard = _stone_chunk
		else:
			var plate := BoxMesh.new()
			plate.size = Vector3(0.45, 0.09, 0.85)
			shard = plate
		var material := ShaderMaterial.new()
		material.shader = DEBRIS_SHADER
		material.set_shader_parameter("base_color", Color("514e47") if rock_debris else Color("8e969c"))
		material.set_shader_parameter("metalness", 0.0 if rock_debris else 0.72)
		material.set_shader_parameter("surface_roughness", 0.95 if rock_debris else 0.55)
		particles.material_override = material
		particles.draw_pass_1 = shard
	else:
		var sprite := QuadMesh.new()
		sprite.size = Vector2.ONE
		var material := ShaderMaterial.new()
		material.shader = SPRITE_SHADER
		material.set_shader_parameter("use_vertex_color", true)
		material.set_shader_parameter("tint", tint)
		material.set_shader_parameter("energy", 2.2)
		sprite.material = material
		particles.draw_pass_1 = sprite
	add_child(particles)
	particles.emitting = true


func _process(delta: float) -> void:
	_elapsed += delta
	var flash_time := clampf(_elapsed / 0.18, 0.0, 1.0)
	_flash.scale = Vector3.ONE * radius * lerpf(0.8, 1.15, flash_time)
	(_flash.material_override as ShaderMaterial).set_shader_parameter("opacity", pow(1.0 - flash_time, 3.0))
	_flash.visible = not rock_debris and flash_time < 1.0
	_light.light_energy = 0.0 if rock_debris else 3.2 * pow(maxf(0.0, 1.0 - _elapsed / 0.24), 3.0)
	if _elapsed >= duration:
		queue_free()
