class_name Spark
extends Node3D
## Short soft flash for bolt impacts. The shader fades the edge of the sprite,
## so an impact cannot expose a rectangular quad against the dark sky.

const SPRITE_SHADER := preload("res://shaders/soft_sprite.gdshader")
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
	var mat := ShaderMaterial.new()
	mat.shader = SPRITE_SHADER
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("energy", 2.5)
	mat.set_shader_parameter("rays", 0.4)
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.light_energy = 1.5
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)


func setup(point: Vector3, normal: Vector3, tint: Color) -> void:
	global_position = point + normal * 0.15
	color = tint
	if _light != null:
		_light.light_color = tint
	if _mesh != null:
		(_mesh.material_override as ShaderMaterial).set_shader_parameter("tint", tint)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / life, 0.0, 1.0)
	_mesh.scale = Vector3.ONE * lerpf(start_scale, end_scale, t)
	(_mesh.material_override as ShaderMaterial).set_shader_parameter("opacity", pow(1.0 - t, 2.0))
	_light.light_energy = 1.5 * pow(1.0 - t, 2.0)
	if t >= 1.0:
		queue_free()
