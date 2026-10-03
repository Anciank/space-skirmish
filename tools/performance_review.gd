extends Node
## Native rendering benchmark with explicit fleet sizes and real input.
## Warm the renderer, disable VSync for the sample, and report wall frame times.
## godot --path . res://tools/performance_review.tscn -- /tmp/skirmish-performance.json
## Add --allies=31 --enemies=32 for the sixty-four-ship battle.
## Add --stationary to keep the battle in the initial forward view.

var _main: Node3D
var _out := "/tmp/skirmish-performance.json"
var _frames: Array[float] = []
var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _gpu_ms: Array[float] = []
var _render_cpu_ms: Array[float] = []
var _peak_draw_calls := 0
var _peak_nodes := 0
var _peak_memory := 0
var _peak_bolts := 0
var _peak_effects := 0
var _peak_pending := 0
var _preferences: Dictionary
var _seen_spawns: Dictionary = {}
var _spawn_min_ship := INF
var _spawn_min_surface := INF
var _spawn_overlaps := 0
var _allies := 2
var _enemies := 3
var _old_fps_cap := 0
var _stationary := false


func _ready() -> void:
	var arguments := OS.get_cmdline_user_args()
	if not arguments.is_empty():
		_out = arguments[0]
	for argument: String in arguments:
		if argument.begins_with("--allies="):
			_allies = argument.get_slice("=", 1).to_int()
		elif argument.begins_with("--enemies="):
			_enemies = argument.get_slice("=", 1).to_int()
		elif argument == "--stationary":
			_stationary = true
	if DisplayServer.get_name() == "headless":
		push_error("Rendering benchmarks need a native window.")
		await Sfx.finish_audio()
		get_tree().quit(1)
		return
	_preferences = GameSettings.values.duplicate(true)
	GameSettings.reset_to_defaults(false)
	_old_fps_cap = Engine.max_fps
	Engine.max_fps = 0
	_main = load("res://scenes/main.tscn").instantiate()
	_main.pause_on_focus_loss = false
	_main.start_in_menu = false
	_main.ally_count = _allies
	_main.enemy_count = _enemies
	add_child(_main)
	_record_deployments()
	if not _stationary:
		Input.action_press("thrust_forward")
	Input.action_press("fire")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	DisplayServer.window_move_to_foreground()
	# Wall time is deliberate: this measures the actual renderer, not the
	# simulated clock used by the headless soak test.
	await _sample_for(2.0, false)
	await _sample_for(10.0, true)
	Input.action_release("thrust_forward")
	Input.action_release("fire")
	_frames.sort()
	# ViewportTexture metadata can report the stretched canvas size. Read one
	# image after timing to record the actual render target's pixel dimensions.
	var render_image := get_viewport().get_texture().get_image()
	var capture_error := render_image.save_png(_out.get_basename() + ".png")
	var report := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": [render_image.get_width(), render_image.get_height()],
		"viewport_3d_scale": get_viewport().scaling_3d_scale,
		"sample_seconds": _frames.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / 1000.0,
		"frames": _frames.size(),
		"fps_mean": 1000.0 / _average(_frames),
		"frame_ms_median": _percentile(0.5),
		"frame_ms_p95": _percentile(0.95),
		"frame_ms_p99": _percentile(0.99),
		"process_monitor_ms_mean": _average(_process_ms),
		"physics_monitor_ms_mean": _average(_physics_ms),
		"gpu_ms_mean": _average(_gpu_ms),
		"render_cpu_ms_mean": _average(_render_cpu_ms),
		"peak_draw_calls": _peak_draw_calls,
		"peak_nodes": _peak_nodes,
		"peak_bolts": _peak_bolts,
		"peak_effects": _peak_effects,
		"peak_pending": _peak_pending,
		"peak_static_memory_mb": _peak_memory / 1048576.0,
		"combat_shots": _shots(),
		"combat_deaths": _deaths(),
		"requested_allies": _allies,
		"requested_enemies": _enemies,
		"stationary_player": _stationary,
		"pilots": GameMatch.pilots.size(),
		"spawn_events": _seen_spawns.size(),
		"spawn_min_ship_distance": _spawn_min_ship,
		"spawn_min_surface_clearance": _spawn_min_surface,
		"unsafe_spawns": _spawn_overlaps,
	}
	var file := FileAccess.open(_out, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write performance report: " + _out)
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	if capture_error != OK:
		push_error("Cannot save the benchmark frame: " + _out.get_basename() + ".png")
	print("performance: " + JSON.stringify(report))
	_main._show_title()
	_main.queue_free()
	await get_tree().process_frame
	GameSettings.values = _preferences
	GameSettings._apply()
	Engine.max_fps = _old_fps_cap
	await Sfx.finish_audio()
	get_tree().quit(1 if file == null or capture_error != OK or report.pilots != 1 + _allies + _enemies or _spawn_overlaps > 0 else 0)


func _sample_for(seconds: float, record: bool) -> void:
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		_record_deployments()
		if record:
			_frames.append(float(now - last) / 1000.0)
			_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
			_render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
			_peak_draw_calls = maxi(_peak_draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			_peak_nodes = maxi(_peak_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
			_peak_memory = maxi(_peak_memory, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
			_peak_bolts = maxi(_peak_bolts, get_tree().get_nodes_in_group("bolts").size())
			_peak_effects = maxi(_peak_effects, _main.effects_root.get_child_count())
			_peak_pending = maxi(_peak_pending, _main._pending.size())
		last = now


func _percentile(fraction: float) -> float:
	return _frames[clampi(int(ceil(_frames.size() * fraction)) - 1, 0, _frames.size() - 1)]


func _average(values: Array[float]) -> float:
	var sum := 0.0
	for value: float in values:
		sum += value
	return sum / maxf(1.0, values.size())


func _shots() -> int:
	var count := 0
	for pilot: Dictionary in GameMatch.standings():
		count += int(pilot.shots)
	return count


func _deaths() -> int:
	var count := 0
	for pilot: Dictionary in GameMatch.pilots.values():
		count += int(pilot.deaths)
	return count


func _record_deployments() -> void:
	for row: Dictionary in _main._roster:
		var ship := row.ship as Node3D
		if not is_instance_valid(ship) or _seen_spawns.has(ship.get_instance_id()):
			continue
		_seen_spawns[ship.get_instance_id()] = true
		var nearest_ship := INF
		for other_row: Dictionary in _main._roster:
			var other := other_row.ship as Node3D
			if is_instance_valid(other) and other != ship:
				nearest_ship = minf(nearest_ship, ship.global_position.distance_to(other.global_position))
		_spawn_min_ship = minf(_spawn_min_ship, nearest_ship)
		if nearest_ship < ship.collision_radius * 2.0 + 20.0:
			_spawn_overlaps += 1
		for body: StarBody in _main.arena.bodies:
			var clearance := ship.global_position.distance_to(body.global_position) - body.radius
			_spawn_min_surface = minf(_spawn_min_surface, clearance)
			if clearance < ship.collision_radius + 10.0:
				_spawn_overlaps += 1
		for rock: Asteroid in _main.arena.asteroids:
			if rock.dead:
				continue
			var clearance := ship.global_position.distance_to(rock.global_position) - rock.radius
			_spawn_min_surface = minf(_spawn_min_surface, clearance)
			if clearance < ship.collision_radius + 10.0:
				_spawn_overlaps += 1
