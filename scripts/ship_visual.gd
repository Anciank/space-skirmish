@tool
class_name ShipVisual
extends Node3D
## Shared interceptor geometry. Hull panels are opaque; only lamps, brief
## shield impacts and exhaust emit light. Geometry is cached across respawns.

const JET_SHADER := preload("res://shaders/engine_jet.gdshader")
const SPRITE_SHADER := preload("res://shaders/soft_sprite.gdshader")
const SHIELD_SHADER := preload("res://shaders/shield.gdshader")
const PAINT := ["HullSpine", "WingPivotLeft/WingLeft", "WingPivotRight/WingRight", "FinLeft", "FinRight"]

static var _geometry: Dictionary = {}
static var _materials: Dictionary = {}
var _jets: Array[MeshInstance3D] = []
var _cores: Array[MeshInstance3D] = []
var _lights: Array[OmniLight3D] = []
var _flashes: Array[MeshInstance3D] = []
var _flash_timers := [0.0, 0.0]
var _fresh_flash := [false, false]
var _jet_material: ShaderMaterial
var _core_material: StandardMaterial3D
var _shield: MeshInstance3D
var _shield_material: ShaderMaterial
var _shield_timer := 0.0
var _load := 0.0
var _jet_length := 0.001


func _ready() -> void:
	_build()
	set_livery(Color("4f99de"))
	update_motion(0.0, false, 0.0)


func _build() -> void:
	var titanium := _metal("titanium", Color("b0bac5"), 0.65, 0.4)
	var carbon := _metal("carbon", Color("151e2a"), 0.5, 0.55)
	var panel := _metal("panels", Color("d4dbdd"), 0.25, 0.5)
	var glass := _metal("glass", Color("07202c"), 0.8, 0.13)
	var hull_parts: Array = []
	hull_parts.append([_loft("fuselage", [Vector4(-3.4, 0.08, 0.07, -0.08), Vector4(-2.6, 0.33, 0.18, -0.04), Vector4(-1.25, 0.63, 0.28, 0.0), Vector4(0.6, 0.72, 0.3, 0.0), Vector4(1.65, 0.48, 0.27, 0.0), Vector4(2.0, 0.3, 0.18, 0.0)]), Transform3D.IDENTITY])
	var dark_parts: Array = []
	var panel_parts: Array = []
	for sign_value: float in [-1.0, 1.0]:
		var nacelle := _loft("nacelle", [Vector4(-0.9, 0.23, 0.18, 0), Vector4(-0.35, 0.39, 0.3, 0), Vector4(1.55, 0.38, 0.29, 0), Vector4(2.25, 0.31, 0.26, 0)])
		hull_parts.append([nacelle, Transform3D(Basis.IDENTITY, Vector3(sign_value * 0.94, -0.06, 0))])
		var pod := _loft("cannon", [Vector4(-2.25, 0.105, 0.09, 0), Vector4(-1.9, 0.22, 0.16, 0), Vector4(0.45, 0.24, 0.19, 0), Vector4(1.38, 0.17, 0.15, 0)])
		dark_parts.append([pod, Transform3D(Basis.IDENTITY, Vector3(sign_value * 2.42, 0.19, 0))])
		var intake := _loft("intake", [Vector4(-0.95, 0.16, 0.11, 0), Vector4(-0.8, 0.23, 0.14, 0), Vector4(-0.6, 0.24, 0.14, 0)])
		dark_parts.append([intake, Transform3D(Basis.IDENTITY, Vector3(sign_value * 0.94, -0.05, 0))])
		for j in 4:
			var vent := _box("vent", Vector3(0.46, 0.026, 0.09))
			dark_parts.append([vent, Transform3D(Basis.IDENTITY, Vector3(sign_value * 0.94, 0.25, 0.5 + j * 0.17))])
		var wing := _plate("wing%d" % int(sign_value), _mirror([Vector2(0.55, -1.1), Vector2(1.02, -1.32), Vector2(3.36, 1.06), Vector2(3.1, 1.62), Vector2(1.0, 1.0), Vector2(0.55, 0.45)], sign_value), -0.1, 0.13)
		var pivot := Node3D.new()
		pivot.name = "WingPivotLeft" if sign_value > 0 else "WingPivotRight"
		add_child(pivot)
		_mesh("WingLeft" if sign_value > 0 else "WingRight", wing, panel, pivot)
		var inset := _plate("wing_inset%d" % int(sign_value), _mirror([Vector2(1.08, -0.78), Vector2(2.75, 0.97), Vector2(2.65, 1.23), Vector2(1.16, 0.76)], sign_value), -0.018, 0.016)
		panel_parts.append([inset, Transform3D.IDENTITY])
		var tip := _plate("tip%d" % int(sign_value), _mirror([Vector2(2.87, 0.72), Vector2(3.27, 1.1), Vector2(3.07, 1.48), Vector2(2.89, 1.41)], sign_value), 0.0, 0.024)
		dark_parts.append([tip, Transform3D.IDENTITY])
		var fin_mesh := _plate("fin", [Vector2(0.0, 0.42), Vector2(1.08, 1.5), Vector2(0.82, 2.02), Vector2(0.0, 1.81)], 0.0, 0.09, 0.0)
		var fin := _mesh("FinLeft" if sign_value > 0 else "FinRight", fin_mesh, panel)
		fin.position = Vector3(sign_value * 0.54, 0.23, 0)
		fin.rotation.z = deg_to_rad(90.0 - sign_value * 16.0)
		var fin_cap := _mesh("FinCapLeft" if sign_value > 0 else "FinCapRight", _plate("fin_cap", [Vector2(0.65, 1.25), Vector2(1.03, 1.51), Vector2(0.82, 1.97), Vector2(0.62, 1.87)], 0, 0.095, 0), carbon)
		fin_cap.transform = fin.transform
		var suffix := "Left" if sign_value > 0 else "Right"
		_build_engine(suffix, sign_value)
		var muzzle := Node3D.new()
		muzzle.name = "Muzzle" + suffix
		muzzle.position = Vector3(sign_value * 2.42, 0.19, -2.34)
		add_child(muzzle)
		var flash := _mesh("MuzzleFlash" + suffix, _quad(), _sprite(Color("9edbff"), 2.5, 0.8))
		flash.position = muzzle.position
		flash.scale = Vector3.ONE * 0.65
		flash.visible = false
		_flashes.append(flash)
		var lamp := _mesh("WingLamp" + suffix, _box("lamp", Vector3(0.08, 0.04, 0.28)), _lamp(Color("70dfe7") if sign_value > 0 else Color("ff7959"), 1.4))
		lamp.position = Vector3(sign_value * 3.1, 0.11, 1.04)
	_mesh("HullBody", _join("hull", hull_parts), titanium)
	_mesh("HullDark", _join("dark", dark_parts), carbon)
	_mesh("InsetPanels", _join("insets", panel_parts), panel)
	_mesh("Canopy", _loft("canopy", [Vector4(-2.06, 0.15, 0.035, 0.2), Vector4(-1.64, 0.31, 0.18, 0.3), Vector4(-0.68, 0.38, 0.26, 0.36), Vector4(-0.28, 0.26, 0.07, 0.32)]), glass)
	_mesh("HullSpine", _loft("spine", [Vector4(-0.22, 0.28, 0.024, 0.315), Vector4(0.3, 0.3, 0.04, 0.32), Vector4(1.44, 0.15, 0.024, 0.3)]), panel)
	var sensor := _mesh("Sensor", _box("sensor", Vector3(0.18, 0.018, 0.035)), _lamp(Color("73cce3"), 0.75))
	sensor.position = Vector3(0, 0.39, -1.78)
	_shield_material = ShaderMaterial.new()
	_shield_material.shader = SHIELD_SHADER
	var shell := SphereMesh.new()
	shell.radius = 2.7
	shell.height = 5.4
	shell.radial_segments = 32
	shell.rings = 16
	_shield = _mesh("ShieldImpact", shell, _shield_material)
	_shield.scale = Vector3(1.27, 0.38, 1.3)
	_shield.visible = false
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_engine(suffix: String, sign_value: float) -> void:
	var at := Vector3(sign_value * 0.94, -0.06, 2.26)
	var bell := CylinderMesh.new()
	bell.top_radius = 0.33
	bell.bottom_radius = 0.3
	bell.height = 0.34
	bell.radial_segments = 12
	var nozzle := _mesh("Nozzle" + suffix, bell, _metal("nozzle", Color("596575"), 0.8, 0.38))
	nozzle.rotation.x = PI * 0.5
	nozzle.position = at
	var core := SphereMesh.new()
	core.radius = 0.23
	core.height = 0.46
	core.radial_segments = 16
	core.rings = 8
	var glow := _mesh("EngineGlow" + suffix, core, null)
	glow.position = at + Vector3(0, 0, 0.19)
	glow.scale.z = 0.15
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cores.append(glow)
	var jet := CylinderMesh.new()
	jet.top_radius = 0.02
	jet.bottom_radius = 0.28
	jet.height = 1.0
	jet.radial_segments = 20
	jet.rings = 8
	jet.cap_top = false
	jet.cap_bottom = false
	var mesh := _join("jet", [[jet, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)]])
	var burner := _mesh("Burner" + suffix, mesh, null)
	burner.position = at + Vector3(0, 0, 0.65)
	burner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jets.append(burner)
	var light := OmniLight3D.new()
	light.name = "EngineLight" + suffix
	light.position = at + Vector3(0, 0, 0.45)
	light.omni_range = 4.0
	light.light_energy = 0.25
	light.shadow_enabled = false
	add_child(light)
	_lights.append(light)


func set_livery(color: Color) -> void:
	var paint := _metal("paint" + color.to_html(), color.lerp(Color("243248"), 0.22), 0.38, 0.48)
	for path: String in PAINT:
		(get_node(path) as MeshInstance3D).material_override = paint
	var tint := color.lerp(Color("73d7ff"), 0.65)
	_core_material = _lamp(tint, 1.8).duplicate()
	_jet_material = ShaderMaterial.new()
	_jet_material.shader = JET_SHADER
	_jet_material.set_shader_parameter("tint", tint)
	for core: MeshInstance3D in _cores:
		core.material_override = _core_material
	for jet: MeshInstance3D in _jets:
		jet.material_override = _jet_material
	for light: OmniLight3D in _lights:
		light.light_color = tint
	for flash: MeshInstance3D in _flashes:
		(flash.material_override as ShaderMaterial).set_shader_parameter("tint", tint)
	_shield_material.set_shader_parameter("tint", color.lerp(Color("c4edff"), 0.25))


func update_motion(throttle_value: float, boosting: bool, delta: float) -> void:
	_load = lerpf(_load, absf(throttle_value), clampf(delta * 8.0, 0, 1))
	_core_material.emission_energy_multiplier = 1.25 + _load * 0.7 + (0.5 if boosting else 0.0)
	_jet_length = lerpf(_jet_length, 2.8 if boosting else 0.001, clampf(delta * 14.0, 0, 1))
	_jet_material.set_shader_parameter("power", 1.5 + _load * 0.4)
	for jet: MeshInstance3D in _jets:
		jet.scale = Vector3(1.0, 1.0, maxf(_jet_length, 0.001))
		jet.position.z = 2.48 + _jet_length * 0.5
		jet.visible = _jet_length > 0.06
	for light: OmniLight3D in _lights:
		light.light_energy = 0.25 + _load * 0.35 + (0.25 if boosting else 0.0)
	for i in _flashes.size():
		if not _fresh_flash[i]:
			_flash_timers[i] = maxf(_flash_timers[i] - delta, 0.0)
		_fresh_flash[i] = false
		_flashes[i].visible = _flash_timers[i] > 0.0
		(_flashes[i].material_override as ShaderMaterial).set_shader_parameter("opacity", _flash_timers[i] / 0.06)
	_shield_timer = maxf(_shield_timer - delta, 0.0)
	_shield.visible = _shield_timer > 0.0
	_shield_material.set_shader_parameter("pulse", pow(_shield_timer / 0.32, 1.5))


func flash_muzzle(index: int) -> void:
	_flash_timers[index % 2] = 0.06
	_fresh_flash[index % 2] = true
	_flashes[index % 2].visible = true
	(_flashes[index % 2].material_override as ShaderMaterial).set_shader_parameter("opacity", 1.0)


func flash_shield(local_hit: Vector3) -> void:
	_shield_timer = 0.32
	_shield_material.set_shader_parameter("hit_direction", local_hit.normalized() if local_hit.length_squared() > 0.01 else Vector3.FORWARD)
	_shield.visible = true


func reset_feedback() -> void:
	_flash_timers = [0.0, 0.0]
	_fresh_flash = [false, false]
	_shield_timer = 0.0
	_load = 0.0
	_jet_length = 0.001
	update_motion(0.0, false, 0.0)


func _mesh(node_name: String, mesh: Mesh, material: Material, parent: Node = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	parent.add_child(instance)
	return instance


static func _metal(key: String, color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	if not _materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = metallic
		mat.roughness = roughness
		_materials[key] = mat
	return _materials[key]


static func _lamp(color: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


static func _sprite(color: Color, energy: float, rays: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SPRITE_SHADER
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("energy", energy)
	mat.set_shader_parameter("rays", rays)
	return mat


static func _quad() -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	return quad


static func _box(key: String, size_value: Vector3) -> BoxMesh:
	if not _geometry.has(key):
		var box := BoxMesh.new()
		box.size = size_value
		_geometry[key] = box
	return _geometry[key]


static func _join(key: String, parts: Array) -> ArrayMesh:
	if not _geometry.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: Array in parts:
			# Indexed primitives and nonindexed lofts cannot share one index
			# buffer: the latter would vanish as soon as an indexed vent is added.
			var source := SurfaceTool.new()
			source.create_from(part[0], 0)
			source.deindex()
			var arrays := source.commit_to_arrays()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var placement: Transform3D = part[1]
			for i in vertices.size():
				st.set_normal((placement.basis * normals[i]).normalized())
				st.add_vertex(placement * vertices[i])
		_geometry[key] = st.commit()
	return _geometry[key]


static func _mirror(points: Array[Vector2], sign_value: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point: Vector2 in points:
		result.append(Vector2(point.x * sign_value, point.y))
	return result


static func _loft(key: String, sections: Array[Vector4]) -> ArrayMesh:
	if _geometry.has(key):
		return _geometry[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile: Array[Vector2] = [Vector2(0.7, 1), Vector2(-0.7, 1), Vector2(-1, 0.5), Vector2(-1, -0.5), Vector2(-0.7, -1), Vector2(0.7, -1), Vector2(1, -0.5), Vector2(1, 0.5)]
	var rings: Array[Array] = []
	for section: Vector4 in sections:
		var ring: Array[Vector3] = []
		for point: Vector2 in profile:
			ring.append(Vector3(point.x * section.y, point.y * section.z + section.w, section.x))
		rings.append(ring)
	for j in rings.size() - 1:
		for i in profile.size():
			var n := (i + 1) % profile.size()
			var direction := Vector3(profile[i].x + profile[n].x, profile[i].y + profile[n].y, 0)
			_face(st, rings[j][i], rings[j][n], rings[j + 1][n], direction)
			_face(st, rings[j][i], rings[j + 1][n], rings[j + 1][i], direction)
	for end in [0, rings.size() - 1]:
		var section: Vector4 = sections[end]
		var centre := Vector3(0, section.w, section.x)
		for i in profile.size():
			_face(st, centre, rings[end][i], rings[end][(i + 1) % profile.size()], Vector3.FORWARD if end == 0 else Vector3.BACK)
	_geometry[key] = st.commit()
	return _geometry[key]


static func _plate(key: String, polygon: Array[Vector2], height_value: float, thickness: float, bank := 0.06) -> ArrayMesh:
	if _geometry.has(key):
		return _geometry[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector2.ZERO
	for p: Vector2 in polygon:
		centre += p
	centre /= polygon.size()
	for side: float in [-1.0, 1.0]:
		var mid := Vector3(centre.x, height_value + side * thickness * 0.5 + absf(centre.x) * bank, centre.y)
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			_face(st, mid, Vector3(a.x, height_value + side * thickness * 0.5 + absf(a.x) * bank, a.y), Vector3(b.x, height_value + side * thickness * 0.5 + absf(b.x) * bank, b.y), Vector3.UP * side)
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var av := Vector3(a.x, height_value + absf(a.x) * bank, a.y)
		var bv := Vector3(b.x, height_value + absf(b.x) * bank, b.y)
		var direction := (av + bv) * 0.5 - Vector3(centre.x, height_value, centre.y)
		_face(st, av + Vector3.UP * thickness * 0.5, av - Vector3.UP * thickness * 0.5, bv - Vector3.UP * thickness * 0.5, direction)
		_face(st, av + Vector3.UP * thickness * 0.5, bv - Vector3.UP * thickness * 0.5, bv + Vector3.UP * thickness * 0.5, direction)
	_geometry[key] = st.commit()
	return _geometry[key]


static func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	# Mirrored parts retain outward normals and clockwise front faces.
	var normal := (c - a).cross(b - a).normalized()
	if normal.dot(outward) < 0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	st.set_normal(normal)
	st.add_vertex(a)
	st.set_normal(normal)
	st.add_vertex(b)
	st.set_normal(normal)
	st.add_vertex(c)
