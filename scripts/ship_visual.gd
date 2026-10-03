@tool
class_name ShipVisual
extends Node3D
## Armored corvette: pressure hull, replaceable armor, radiator outriggers,
## twin autocannons and reaction-control ports. Shared meshes survive respawns.

const JET_SHADER := preload("res://shaders/engine_jet.gdshader")
const SPRITE_SHADER := preload("res://shaders/soft_sprite.gdshader")
const SHIELD_SHADER := preload("res://shaders/shield.gdshader")
const HULL_SHADER := preload("res://shaders/hull_surface.gdshader")
const PAINT := ["HullSpine", "SquadronBands"]
const ENGINE_TINT := Color("95c6db")
const MUZZLE_TINT := Color("ffd4a0")

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
var _rcs: Array[MeshInstance3D] = []
var _rcs_directions: Array[Vector3] = []
var _rcs_material: StandardMaterial3D
## Hull-space solid bounds used by contact brackets, independent of collision tuning.
var contact_bounds := AABB()


func _ready() -> void:
	_build()
	set_livery(Color("4f99de"))
	update_motion(0.0, false, 0.0)


func _build() -> void:
	var alloy := _metal("alloy", Color("767f83"), 0.72, 0.43)
	var armor := _metal("armor", Color("a2a5a1"), 0.52, 0.52)
	var graphite := _metal("graphite", Color("22282c"), 0.62, 0.6)
	var heat_sink := _metal("heat_sink", Color("343537"), 0.75, 0.72)
	var glass := _metal("optics", Color("101c20"), 0.84, 0.18)
	var hull_parts: Array = []
	var dark_parts: Array = []
	var armor_parts: Array = []
	var machinery: Array = []
	var radiators: Array = []
	var markings: Array = []
	# A blunt armored prow protects the pressure vessel, rather than an aircraft nose.
	hull_parts.append([_loft("pressure_hull", [Vector4(-3.2, 0.38, 0.31, -0.04), Vector4(-2.65, 0.68, 0.45, 0), Vector4(-1.5, 0.84, 0.49, 0), Vector4(1.45, 0.78, 0.44, 0), Vector4(2.1, 0.48, 0.32, 0)]), Transform3D.IDENTITY])
	for sign_value: float in [-1.0, 1.0]:
		var suffix := "Left" if sign_value > 0 else "Right"
		# Segmented armor leaves narrow recesses showing the underlying hull.
		for j in 5:
			var z := -2.65 + float(j) * 0.87
			if sign_value > 0:
				armor_parts.append([_loft("armor_section%d" % j, [Vector4(z, 0.57 if j == 0 else 0.81, 0.085, 0.48), Vector4(z + 0.76, 0.79, 0.09, 0.48)]), Transform3D.IDENTITY])
			armor_parts.append([_box("side_armor", Vector3(0.11, 0.5, 0.7)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 0.79, 0, z + 0.42))])
		var nacelle := _loft("drive_housing", [Vector4(-0.7, 0.3, 0.29, 0), Vector4(-0.36, 0.48, 0.38, 0), Vector4(1.75, 0.46, 0.36, 0), Vector4(2.28, 0.39, 0.34, 0)])
		hull_parts.append([nacelle, Transform3D(Basis.IDENTITY, Vector3(sign_value * 1.18, -0.05, 0))])
		machinery.append([_box("drive_mount", Vector3(0.48, 0.38, 1.6)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 0.87, -0.12, 0.8))])
		# Cannons have feed housings, cooling sleeves and exposed barrels.
		dark_parts.append([_loft("gun_breech", [Vector4(-1.82, 0.18, 0.19, 0), Vector4(-1.5, 0.29, 0.24, 0), Vector4(0.2, 0.3, 0.25, 0), Vector4(0.68, 0.22, 0.2, 0)]), Transform3D(Basis.IDENTITY, Vector3(sign_value * 2.04, 0.02, 0))])
		machinery.append([_box("gun_mount", Vector3(0.7, 0.28, 0.62)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 1.55, 0.04, -1.12))])
		for j in 3:
			machinery.append([_box("feed_segment", Vector3(0.28, 0.13, 0.16)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 1.86, 0.29, -0.54 + j * 0.24))])
		var barrel := _mesh("CannonBarrel" + suffix, _cylinder("barrel", 0.08, 0.11, 1.28), alloy)
		barrel.position = Vector3(sign_value * 2.04, 0.02, -2.38)
		barrel.rotation.x = PI * 0.5
		var sleeve := _mesh("CannonSleeve" + suffix, _cylinder("sleeve", 0.14, 0.17, 0.46), graphite)
		sleeve.position = Vector3(sign_value * 2.04, 0.02, -1.91)
		sleeve.rotation.x = PI * 0.5
		var muzzle := Node3D.new()
		muzzle.name = "Muzzle" + suffix
		muzzle.position = Vector3(sign_value * 2.04, 0.02, -3.05)
		add_child(muzzle)
		var bore := _mesh("CannonBore" + suffix, _cylinder("bore", 0.065, 0.065, 0.012), graphite)
		bore.position = muzzle.position
		bore.rotation.x = PI * 0.5
		var flash := _mesh("MuzzleFlash" + suffix, _quad(), _sprite(MUZZLE_TINT, 2.8, 0.25))
		flash.position = muzzle.position + Vector3(0, 0, -0.12)
		flash.scale = Vector3.ONE * 0.38
		flash.visible = false
		_flashes.append(flash)
		# Heat exchangers need area in vacuum. Thick booms support rectangular banks.
		machinery.append([_box("radiator_boom", Vector3(1.12, 0.16, 0.21)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 2.0, -0.08, 1.12))])
		var radiator := _plate("radiator%d" % int(sign_value), _mirror([Vector2(1.92, 0.32), Vector2(2.9, 0.32), Vector2(2.9, 1.95), Vector2(1.92, 1.95)], sign_value), -0.02, 0.065, 0)
		radiators.append([radiator, Transform3D.IDENTITY])
		for j in 9:
			machinery.append([_box("radiator_rib", Vector3(0.94, 0.024, 0.045)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 2.41, 0.028, 0.4 + j * 0.18))])
		for j in 6:
			dark_parts.append([_box("drive_vent", Vector3(0.48, 0.035, 0.085)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 1.18, 0.338, 0.32 + j * 0.2))])
		markings.append([_box("identity_band", Vector3(0.66, 0.02, 0.14)), Transform3D(Basis.IDENTITY, Vector3(sign_value * 1.18, 0.346, -0.12))])
		_build_engine(suffix, sign_value, alloy, graphite)
		var nav := _mesh("NavigationLight" + suffix, _box("navigation_lamp", Vector3(0.045, 0.035, 0.1)), _lamp(Color("d85c4f") if sign_value < 0 else Color("71b8a0"), 0.6))
		nav.position = Vector3(sign_value * 2.91, 0.045, 1.84)
		# Opposing thruster ports show lateral/vertical/reverse control forces.
		for z: float in [-2.1, 1.6]:
			_build_rcs(Vector3(sign_value * 0.92, 0.03, z), Vector3(sign_value, 0, 0), graphite)
			_build_rcs(Vector3(sign_value * 0.6, 0.61, z), Vector3.UP, graphite)
			_build_rcs(Vector3(sign_value * 0.6, -0.51, z), Vector3.DOWN, graphite)
		_build_rcs(Vector3(sign_value * 1.18, -0.05, -0.78), Vector3.FORWARD, graphite)
	# Restore a real base surface when the damage flash override is removed.
	var hull_mesh := _join("corvette_hull", hull_parts)
	hull_mesh.surface_set_material(0, alloy)
	_mesh("HullBody", hull_mesh, null)
	_mesh("ArmorPanels", _join("corvette_armor", armor_parts), armor)
	_mesh("HullDark", _join("corvette_recesses", dark_parts), graphite)
	_mesh("Machinery", _join("corvette_machinery", machinery), alloy)
	_mesh("RadiatorBanks", _join("corvette_radiators", radiators), heat_sink)
	_mesh("SquadronBands", _join("corvette_markings", markings), armor)
	_mesh("HullSpine", _loft("dorsal_spine", [Vector4(-0.9, 0.33, 0.025, 0.61), Vector4(0.7, 0.33, 0.03, 0.62), Vector4(1.4, 0.18, 0.025, 0.58)]), armor)
	_mesh("Canopy", _loft("sensor_bridge", [Vector4(-2.4, 0.15, 0.04, 0.58), Vector4(-2.02, 0.28, 0.15, 0.65), Vector4(-1.25, 0.28, 0.14, 0.65), Vector4(-1.04, 0.18, 0.04, 0.6)]), glass)
	var mast := _mesh("SensorMast", _box("sensor_mast", Vector3(0.09, 0.38, 0.1)), graphite)
	mast.position = Vector3(0.25, 0.82, 0.2)
	var sensor := _mesh("Sensor", _box("sensor_array", Vector3(0.34, 0.1, 0.16)), alloy)
	sensor.position = Vector3(0.25, 1.03, 0.2)
	var lens := _mesh("SensorOptic", _box("sensor_lens", Vector3(0.08, 0.028, 0.025)), _lamp(Color("adc8cd"), 0.4))
	lens.position = Vector3(0.25, 1.03, 0.106)
	for part: Node in get_children():
		if part is MeshInstance3D and not (_jets.has(part) or _cores.has(part) or _flashes.has(part) or _rcs.has(part)):
			var solid := part as MeshInstance3D
			contact_bounds = contact_bounds.merge(solid.transform * solid.mesh.get_aabb())
	_shield_material = ShaderMaterial.new()
	_shield_material.shader = SHIELD_SHADER
	var shell := SphereMesh.new()
	shell.radius = 2.7
	shell.height = 5.4
	shell.radial_segments = 32
	shell.rings = 16
	_shield = _mesh("ShieldImpact", shell, _shield_material)
	_shield.scale = Vector3(1.14, 0.46, 1.28)
	_shield.visible = false
	_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_engine(suffix: String, sign_value: float, alloy: Material, graphite: Material) -> void:
	var at := Vector3(sign_value * 1.18, -0.05, 2.29)
	var nozzle := _mesh("Nozzle" + suffix, _cylinder("engine_bell", 0.35, 0.4, 0.4), alloy)
	nozzle.rotation.x = PI * 0.5
	nozzle.position = at
	for j in 3:
		var collar := _mesh("EngineCollar" + suffix + str(j), _cylinder("engine_collar", 0.405, 0.405, 0.05), graphite)
		collar.position = at + Vector3(0, 0, -0.13 + j * 0.12)
		collar.rotation.x = PI * 0.5
	var glow := _mesh("EngineGlow" + suffix, _cylinder("engine_core", 0.29, 0.29, 0.018), null)
	glow.rotation.x = PI * 0.5
	glow.position = at + Vector3(0, 0, 0.21)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cores.append(glow)
	var jet := CylinderMesh.new()
	jet.top_radius = 0.015
	jet.bottom_radius = 0.29
	jet.height = 1.0
	jet.radial_segments = 20
	jet.rings = 8
	jet.cap_top = false
	jet.cap_bottom = false
	var mesh := _join("drive_jet", [[jet, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)]])
	var burner := _mesh("Burner" + suffix, mesh, null)
	burner.position = at + Vector3(0, 0, 0.7)
	burner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_jets.append(burner)
	var light := OmniLight3D.new()
	light.name = "EngineLight" + suffix
	light.position = at + Vector3(0, 0, 0.45)
	light.omni_range = 2.3
	light.light_energy = 0.1
	light.shadow_enabled = false
	add_child(light)
	_lights.append(light)


func _build_rcs(at: Vector3, exhaust_direction: Vector3, material: Material) -> void:
	var orientation := Basis(Quaternion(Vector3.UP, exhaust_direction))
	var port := _mesh("RCSPort%d" % _rcs.size(), _cylinder("rcs_port", 0.06, 0.085, 0.1), material)
	port.transform = Transform3D(orientation, at)
	var core := _mesh("RCSJet%d" % _rcs.size(), _cylinder("rcs_core", 0.025, 0.05, 0.18), null)
	core.transform = Transform3D(orientation, at + exhaust_direction * 0.09)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.visible = false
	_rcs.append(core)
	_rcs_directions.append(exhaust_direction)


static func _cylinder(key: String, top: float, bottom: float, height_value: float) -> CylinderMesh:
	if not _geometry.has(key):
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = top
		cylinder.bottom_radius = bottom
		cylinder.height = height_value
		cylinder.radial_segments = 16
		_geometry[key] = cylinder
	return _geometry[key]


func set_livery(color: Color) -> void:
	# Identification is paint. Drive and ammunition colors belong to their systems.
	var paint := _metal("paint" + color.to_html(), color.lerp(Color("5c686b"), 0.58), 0.35, 0.57)
	for path: String in PAINT:
		(get_node(path) as MeshInstance3D).material_override = paint
	_core_material = _lamp(ENGINE_TINT, 0.75)
	_rcs_material = _lamp(ENGINE_TINT, 1.0)
	_jet_material = ShaderMaterial.new()
	_jet_material.shader = JET_SHADER
	_jet_material.set_shader_parameter("tint", ENGINE_TINT)
	for core: MeshInstance3D in _cores:
		core.material_override = _core_material
	for jet: MeshInstance3D in _jets:
		jet.material_override = _jet_material
	for light: OmniLight3D in _lights:
		light.light_color = ENGINE_TINT
	for port: MeshInstance3D in _rcs:
		port.material_override = _rcs_material
	_shield_material.set_shader_parameter("tint", Color("9dbccf"))


func update_motion(throttle_value: float, boosting: bool, delta: float, maneuver := Vector2.ZERO) -> void:
	var drive_boost := boosting and throttle_value > 0.02
	_load = lerpf(_load, maxf(throttle_value, 0.0), clampf(delta * 8.0, 0, 1))
	_core_material.emission_energy_multiplier = 0.4 + _load * 0.65 + (0.4 if drive_boost else 0.0)
	_jet_length = lerpf(_jet_length, 2.4 if drive_boost else maxf(0.001, _load * 0.72), clampf(delta * 14.0, 0, 1))
	_jet_material.set_shader_parameter("power", 0.7 + _load * 0.25 + (0.3 if drive_boost else 0.0))
	for jet: MeshInstance3D in _jets:
		jet.scale = Vector3(1.0, 1.0, maxf(_jet_length, 0.001))
		jet.position.z = 2.52 + _jet_length * 0.5
		jet.visible = _jet_length > 0.06
	for light: OmniLight3D in _lights:
		light.light_energy = 0.04 + _load * 0.12 + (0.1 if drive_boost else 0.0)
	var thrust := Vector3(maneuver.x, maneuver.y, maxf(-throttle_value, 0.0))
	for i in _rcs.size():
		_rcs[i].visible = _rcs_directions[i].dot(thrust) < -0.08
	for i in _flashes.size():
		if not _fresh_flash[i]:
			_flash_timers[i] = maxf(_flash_timers[i] - delta, 0.0)
		_fresh_flash[i] = false
		_flashes[i].visible = _flash_timers[i] > 0.0
		(_flashes[i].material_override as ShaderMaterial).set_shader_parameter("opacity", _flash_timers[i] / 0.06)
	_shield_timer = maxf(_shield_timer - delta, 0.0)
	_shield.visible = _shield_timer > 0.0
	_shield_material.set_shader_parameter("pulse", _shield_timer / 0.32)


func flash_muzzle(index: int) -> void:
	_flash_timers[index % 2] = 0.06
	_fresh_flash[index % 2] = true
	_flashes[index % 2].visible = true
	(_flashes[index % 2].material_override as ShaderMaterial).set_shader_parameter("opacity", 1.0)


func flash_shield(local_hit: Vector3) -> void:
	_shield_timer = 0.32
	_shield_material.set_shader_parameter("hit_direction", _shield.to_local(to_global(local_hit)).normalized() if local_hit.length_squared() > 0.01 else Vector3.FORWARD)
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


static func _metal(key: String, color: Color, metallic: float, roughness: float) -> ShaderMaterial:
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = HULL_SHADER
		mat.set_shader_parameter("base_color", color)
		mat.set_shader_parameter("metalness", metallic)
		mat.set_shader_parameter("surface_roughness", roughness)
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
