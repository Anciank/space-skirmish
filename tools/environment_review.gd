extends Node
## Native captures of the distant sky, local stone and cold rock break-up.
## godot --path . res://tools/environment_review.tscn -- /tmp/skirmish-environment

var _main: Node3D
var _out := "/tmp/skirmish-environment"


func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	if not OS.get_cmdline_user_args().is_empty():
		_out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.ally_count = 0
	_main.enemy_count = 0
	_main.pause_on_focus_loss = false
	add_child(_main)
	_main._start_match(false)
	GameMatch.running = false
	_main.player.set_physics_process(false)
	_main.player.capture_mouse(false)
	_main.player.hide()
	_main.rig.set_process(false)
	_main.hud.hide()
	# Hold the controller while the camera samples its prepared scene.
	_main.set_process(false)
	for rock: Asteroid in get_tree().get_nodes_in_group("rocks"):
		rock.freeze = true
	for body: StarBody in get_tree().get_nodes_in_group("bodies"):
		body.set_physics_process(false)
		body.set_process(false)

	_main.rig.global_position = Vector3(0, 430, 0)
	_main.rig.global_basis = Basis.looking_at(Starfield.PLANET_DIRECTION.normalized(), Vector3.UP)
	_main.rig.camera.fov = 62.0
	_main.rig.stars.global_position = _main.rig.camera.global_position
	await _capture("distant-planet-and-dust", 14)
	var anchor: StarBody = _main.arena.bodies[0]
	_view(anchor.global_position, Vector3(1.6, 0.6, 2.1) * anchor.radius)
	await _capture("gravity-anchor", 12)
	var biggest: Asteroid = null
	for rock: Asteroid in get_tree().get_nodes_in_group("rocks"):
		if biggest == null or rock.radius > biggest.radius:
			biggest = rock
	if biggest != null:
		_view(biggest.global_position, Vector3(2.0, 1.2, 2.5) * biggest.radius)
		await _capture("asteroid", 12)
		biggest.take_damage(biggest.hp + 1.0)
		await _capture("rock-shatter-start", 2)
		await _capture("rock-shatter-fragments", 12)
	_main._show_title()
	_main.queue_free()
	await get_tree().process_frame
	await Sfx.finish_audio()
	get_tree().quit()


func _view(point: Vector3, offset: Vector3) -> void:
	_main.rig.global_position = point + offset
	_main.rig.look_at(point)
	_main.rig.camera.fov = 55.0
	_main.rig.stars.global_position = _main.rig.camera.global_position


func _capture(caption: String, frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
	# Occluded macOS windows may never emit frame_post_draw. Render explicitly
	# so capture can finish even while another native window has focus.
	RenderingServer.force_draw(true)
	var picture := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, caption]
	var result := picture.save_png(path)
	print("environment %s: %dx%d, error=%d" % [path, picture.get_width(), picture.get_height(), result])
