extends Node
## Native rendering benchmark with the normal six-ship battle and real input.
## Warm the renderer, disable VSync for the sample, and report wall frame times.
## godot --path . res://tools/performance_review.tscn -- /tmp/skirmish-performance.json

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


func _ready() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		_out = OS.get_cmdline_user_args()[0]
	if DisplayServer.get_name() == "headless":
		push_error("Rendering benchmarks need a native window.")
		await Sfx.finish_audio()
		get_tree().quit(1)
		return
	_main = load("res://scenes/main.tscn").instantiate()
	_main.start_in_menu = false
	add_child(_main)
	Input.action_press("thrust_forward")
	Input.action_press("fire")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
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
		"peak_static_memory_mb": _peak_memory / 1048576.0,
		"combat_shots": _shots(),
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
	await Sfx.finish_audio()
	get_tree().quit(1 if file == null or capture_error != OK else 0)


func _sample_for(seconds: float, record: bool) -> void:
	var start := Time.get_ticks_usec()
	var last := start
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
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
