class_name ExplosionFx
extends Node3D
## Death effect for ships and large asteroids: an expanding shockwave shell, a
## quick flash light and a burst of GPU particles. Self-frees when done.

var radius := 6.0
var duration := 0.95
var tint := Color(1.0, 0.72, 0.35)

var _shell: MeshInstance3D
var _light: OmniLight3D
var _particles: GPUParticles3D
var _elapsed := 0.0


func _ready() -> void:
	_shell = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	_shell.mesh = sphere
	var mat := MeshFactory.make_glow_material(tint, 6.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shell.mesh.material = mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shell)

	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.light_energy = 8.0
	_light.omni_range = radius * 6.0
	_light.shadow_enabled = false
	add_child(_light)

	_particles = GPUParticles3D.new()
	_particles.amount = 56
	_particles.one_shot = true
	_particles.explosiveness = 0.95
	_particles.lifetime = 1.1
	_particles.local_coords = false
	_particles.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pmat.emission_sphere_radius = radius * 0.4
	pmat.direction = Vector3(0, 0, 0)
	pmat.spread = 180.0
	pmat.initial_velocity_min = radius * 3.0
	pmat.initial_velocity_max = radius * 9.0
	pmat.gravity = Vector3.ZERO
	pmat.damping_min = 1.0
	pmat.damping_max = 3.0
	pmat.scale_min = radius * 0.06
	pmat.scale_max = radius * 0.22
	pmat.color = tint
	_particles.process_material = pmat

	var pmesh := SphereMesh.new()
	pmesh.radius = 1.0
	pmesh.height = 2.0
	pmesh.radial_segments = 6
	pmesh.rings = 3
	var pmat_out := MeshFactory.make_glow_material(tint.lerp(Color(1, 1, 1), 0.35), 3.0)
	pmesh.material = pmat_out
	_particles.draw_pass_1 = pmesh
	add_child(_particles)
	_particles.emitting = true


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 2.4)
	if _shell != null:
		_shell.scale = Vector3.ONE * maxf(0.001, eased * radius)
		var mat := _shell.mesh.material as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = lerpf(7.0, 0.0, t)
			mat.albedo_color = Color(tint.r, tint.g, tint.b, 1.0 - t)
	if _light != null:
		_light.light_energy = lerpf(9.0, 0.0, t * t)
	if t >= 1.0:
		queue_free()
