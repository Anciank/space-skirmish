extends Node
## Capture real materials, damage and weapon effects from useful close angles.
## godot --path . res://tools/visual_review.tscn -- /tmp/skirmish-art

var _main: Node3D
var _player: SpaceShip
var _out := "/tmp/skirmish-art"
var _animate := false


func _ready() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.ally_count = 0
	_main.enemy_count = 0
	add_child(_main)
	await _capture("title", 12)
	_main._start_match()
	GameMatch.running = false
	_player = _main.player
	_player.set_physics_process(false)
	_player.capture_mouse(false)
	_player.global_position = Vector3(0, 430, 0)
	_player.global_basis = Basis.IDENTITY
	_main.rig.set_process(false)
	_main.hud.hide()
	for rock: Asteroid in get_tree().get_nodes_in_group("rocks"):
		rock.freeze = true
	for body: StarBody in get_tree().get_nodes_in_group("bodies"):
		body.set_physics_process(false)
	_animate = true
	_view(_player.global_position, Vector3(8, 4.5, -9), 55)
	await _capture("ship-front", 12)
	_view(_player.global_position, Vector3(7, 4, 10), 55)
	await _capture("ship-rear", 12)
	_player.throttle = 1.0
	_player.boosting = true
	await _capture("boost", 24)
	_view(_player.global_position, Vector3(8, 4.5, -9), 55)
	_player.fire()
	await _capture("firing", 1)
	_view(_player.global_position, Vector3(7, 4, 10), 55)
	_player.take_damage(12, null, _player.global_position + Vector3(3, 0.3, 0))
	await _capture("shield-impact", 2)
	_player.boosting = false
	await _capture("coasting", 30)
	_player.take_damage(200, null, _player.global_position + Vector3(3, 0, 0))
	await _capture("explosion-flash", 2)
	await _capture("explosion-fragments", 12)
	await _capture("explosion-fade", 30)
	for body: StarBody in get_tree().get_nodes_in_group("bodies"):
		_view(body.global_position, Vector3(1.6, 0.6, 2.1) * body.radius, 55)
		await _capture("planet" if body.body_kind == 1 else "moon", 12)
		if body.body_kind == 0:
			break
	var biggest: Asteroid = null
	for rock: Asteroid in get_tree().get_nodes_in_group("rocks"):
		if biggest == null or rock.radius > biggest.radius:
			biggest = rock
	if biggest != null:
		_view(biggest.global_position, Vector3(2, 1.2, 2.5) * biggest.radius, 55)
		await _capture("asteroid", 12)
	_animate = false
	_main._show_title()
	_main.queue_free()
	await get_tree().process_frame
	await Sfx.finish_audio()
	get_tree().quit()


func _process(delta: float) -> void:
	if _animate and is_instance_valid(_player) and not _player.dead:
		_player._update_weapon(delta)
		_player._update_visuals(delta)


func _view(point: Vector3, offset: Vector3, fov: float) -> void:
	_main.rig.global_position = point + offset
	_main.rig.look_at(point)
	_main.rig.camera.fov = fov
	_main.rig.stars.global_position = _main.rig.camera.global_position


func _capture(caption: String, frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, caption]
	var error := texture.save_png(path)
	print("visual %s: %dx%d, error=%d" % [path, texture.get_width(), texture.get_height(), error])
