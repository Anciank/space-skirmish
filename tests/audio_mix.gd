extends Node
## Signal quality, frame-independent engine response and cue protection under load.

var _checks := 0
var _failures := 0
var _preferences: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preferences = GameSettings.values.duplicate()
	GameSettings.reset_to_defaults(false)
	Sfx.set_process(false)
	_signal_quality()
	_autocannon_quality()
	_mixing()
	_voice_pressure()
	_engine_response()
	get_tree().paused = true
	Sfx.play_ui()
	_check("menu cues and score remain active during pause", Sfx.process_mode == Node.PROCESS_MODE_ALWAYS and Sfx._music_player.playing and Sfx._ui_voices.any(func(voice: AudioStreamPlayer): return voice.playing))
	get_tree().paused = false
	Sfx.stop_combat_audio()
	_check("combat stop clears world and cockpit voices", not Sfx._engine_player.playing and Sfx._voices.all(func(voice: AudioStreamPlayer3D): return not voice.playing) and Sfx._local_voices.all(func(voice: AudioStreamPlayer): return not voice.playing))
	GameSettings.values = _preferences
	GameSettings._apply()
	await Sfx.finish_audio()
	_check("shutdown releases all looping streams", Sfx._engine_player.stream == null and Sfx._music_player.stream == null and Sfx._pulse_player.stream == null)
	print("--- audio mix: %d checks, %d failures ---" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)


func _signal_quality() -> void:
	var clips_valid := true
	var endpoints_valid := true
	for cue: String in Sfx._bank:
		var wav: AudioStreamWAV = Sfx._bank[cue]
		var pcm := wav.data
		var peak := 0.0
		var mean := 0.0
		for i in pcm.size() / 2:
			var value := float(pcm.decode_s16(i * 2)) / 32767.0
			peak = maxf(peak, absf(value))
			mean += value
		clips_valid = clips_valid and pcm.size() > 0 and peak > 0.05 and peak <= 0.901 and absf(mean / (pcm.size() / 2)) < 0.02
		endpoints_valid = endpoints_valid and pcm.decode_s16(0) == 0 and absf(float(pcm.decode_s16(pcm.size() - 2)) / 32767.0) < 0.005
	_check("all one-shots have audible signal, headroom and no DC offset", clips_valid)
	_check("one-shot attacks and tails do not introduce clicks", endpoints_valid)
	var shield: AudioStreamWAV = Sfx._bank.shield
	_check("shield fundamentals use real seconds", _power_at(shield.data, 1180.0) > _power_at(shield.data, 1180.0 / 0.28) * 100.0)
	var engine: AudioStreamWAV = Sfx._engine_player.stream
	var pcm := engine.data
	var global_rms := _rms(pcm, 0, engine.loop_end)
	var lowest_rms := INF
	var window := Sfx.MIX_RATE / 10
	for start in range(0, engine.loop_end - window, window):
		lowest_rms = minf(lowest_rms, _rms(pcm, start, window))
	_check("engine loop has no recurring silence or fade at the seam", lowest_rms > global_rms * 0.7)
	var loops_valid := true
	for player: AudioStreamPlayer in [Sfx._engine_player, Sfx._music_player, Sfx._pulse_player]:
		var wav: AudioStreamWAV = player.stream
		var data := wav.data
		loops_valid = loops_valid and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and data.decode_s16(wav.loop_end * 2) == data.decode_s16(0)
		loops_valid = loops_valid and absf(float(data.decode_s16((wav.loop_end - 1) * 2) - data.decode_s16(0)) / 32767.0) < 0.03
	_check("engine and score loops have continuous boundaries", loops_valid)


func _mixing() -> void:
	var master := AudioServer.get_bus_volume_db(0)
	GameSettings.set_value("sfx_volume", 0.0, false)
	GameSettings.set_value("engine_volume", 1.0, false)
	GameSettings.set_value("music_volume", 0.25, false)
	_check("sound categories can be adjusted independently", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")) and is_zero_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Engine"))) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.25)) and is_equal_approx(master, AudioServer.get_bus_volume_db(0)))
	var limiter := AudioServer.get_bus_effect(0, 0) as AudioEffectHardLimiter
	_check("summed combat peaks have a master safety ceiling", limiter != null and limiter.ceiling_db <= -1.0)
	GameSettings.set_value("music_volume", NAN, false)
	_check("invalid audio settings recover to a usable default", GameSettings.get_value("music_volume") == GameSettings.DEFAULTS.music_volume)
	GameSettings.set_value("master_volume", 0.0, false)
	_check("master mute covers music and menu sounds", AudioServer.is_bus_mute(0) and Sfx._music_player.bus == "Music" and Sfx._ui_voices[0].bus == "UI")
	GameSettings.reset_to_defaults(false)


func _autocannon_quality() -> void:
	var shot: AudioStreamWAV = Sfx._bank.laser
	var heavy: AudioStreamWAV = Sfx._bank.laser_heavy
	_check("autocannon tails fit two overlapping voices at 20 rounds per second",
		shot.get_length() >= 0.065 and shot.get_length() < 0.1 and heavy.get_length() < 0.1)
	var pcm := shot.data
	var samples := pcm.size() / 2
	var low := 0.0
	var high := 0.0
	var low_power := 0.0
	var high_power := 0.0
	var mean := 0.0
	for i in samples:
		var value := float(pcm.decode_s16(i * 2)) / 32767.0
		low = lerpf(low, value, 1.0 - exp(-TAU * 700.0 / Sfx.MIX_RATE))
		high = lerpf(high, value, 1.0 - exp(-TAU * 1800.0 / Sfx.MIX_RATE))
		if i < int(Sfx.MIX_RATE * 0.025):
			low_power += low * low
			high_power += (value - high) * (value - high)
		mean += value
	_check("autocannon has a low receiver body and a broad muzzle crack", low_power > 0.4 and high_power > 0.06)
	_check("autocannon has no measurable DC bias or abrupt endpoints", absf(mean / samples) < 0.0001
		and pcm.decode_s16(0) == 0 and absf(float(pcm.decode_s16(pcm.size() - 2)) / 32767.0) < 0.0001)
	# Sum actual PCM at firing cadence, including a narrow deterministic pitch
	# variation. Test the mix before the master limiter can hide a clipped shot.
	var burst := PackedFloat32Array()
	burst.resize(int(Sfx.MIX_RATE * 2.1))
	for round_index in 40:
		var pitch := Sfx._pitch(sin(round_index * 2.1) * 0.25)
		var onset := int(round_index * Sfx.MIX_RATE * 0.05)
		for i in int(ceil(samples / pitch)):
			var source := float(i) * pitch
			var left := int(source)
			if left >= samples - 1 or onset + i >= burst.size():
				break
			var a := float(pcm.decode_s16(left * 2)) / 32767.0
			var b := float(pcm.decode_s16((left + 1) * 2)) / 32767.0
			burst[onset + i] += lerpf(a, b, source - left) * db_to_linear(-7.0)
	var peak := 0.0
	var burst_mean := 0.0
	for sample: float in burst:
		peak = maxf(peak, absf(sample))
		burst_mean += sample
	_check("20 Hz automatic fire has headroom before master limiting", peak > 0.1 and peak < 0.8
		and absf(burst_mean / burst.size()) < 0.0001 and is_zero_approx(burst[-1]))
	Sfx.stop_combat_audio()
	var nodes := Sfx.get_child_count()
	Sfx.play_local("laser", -7.0)
	Sfx.play_local("laser", -7.0)
	_check("adjacent autocannon shots overlap in separate bounded voices",
		Sfx._local_voices.filter(func(voice: AudioStreamPlayer): return voice.playing).size() == 2
		and Sfx.get_child_count() == nodes)
	Sfx.stop_combat_audio()


func _voice_pressure() -> void:
	Sfx.stop_combat_audio()
	Sfx.play_at("laser", Vector3(1600, 0, 0))
	_check("inaudible distant shots consume no world voices", Sfx._voices.all(func(voice: AudioStreamPlayer3D): return not voice.playing))
	for _i in Sfx.VOICE_COUNT:
		Sfx.play_at("shield", Vector3.ZERO, -8.0)
	Sfx.play_at("laser", Vector3(900, 0, 0), -13.0)
	_check("distant laser fire cannot steal nearby damage cues", Sfx._voices.all(func(voice: AudioStreamPlayer3D): return voice.get_meta("cue", "") == "shield"))
	Sfx.play_at("explosion_big", Vector3.ZERO)
	_check("a nearby explosion can replace a less important cue", Sfx._voices.filter(func(voice: AudioStreamPlayer3D): return voice.get_meta("cue", "") == "explosion_big").size() == 1)
	for _i in Sfx.LOCAL_COUNT:
		Sfx.play_local("critical", -8.0)
	Sfx.play_local("laser", -13.0)
	_check("weapon bursts preserve critical cockpit warnings", Sfx._local_voices.all(func(voice: AudioStreamPlayer): return voice.get_meta("cue", "") == "critical"))
	Sfx.stop_combat_audio()


func _engine_response() -> void:
	Sfx.set_engine(0.8, 1.0, true)
	for _i in 30:
		Sfx.set_engine(0.8, 1.0, true)
		Sfx._process(1.0 / 30.0)
	var slow := Vector2(Sfx._engine_player.volume_db, Sfx._engine_player.pitch_scale)
	Sfx.set_engine(0.0, 0.0, false)
	Sfx.set_engine(0.8, 1.0, true)
	for _i in 240:
		Sfx.set_engine(0.8, 1.0, true)
		Sfx._process(1.0 / 240.0)
	var fast := Vector2(Sfx._engine_player.volume_db, Sfx._engine_player.pitch_scale)
	_check("engine gain and pitch settle equally at 30 and 240 FPS", slow.distance_to(fast) < 0.0001)
	Sfx.set_engine(0.0, 0.0, false)
	_check("death or pause immediately stops the engine", not Sfx._engine_player.playing)


func _rms(pcm: PackedByteArray, start: int, count: int) -> float:
	var sum := 0.0
	for i in range(start, start + count):
		var value := float(pcm.decode_s16(i * 2)) / 32767.0
		sum += value * value
	return sqrt(sum / count)


func _power_at(pcm: PackedByteArray, frequency: float) -> float:
	var real := 0.0
	var imaginary := 0.0
	for i in pcm.size() / 2:
		var value := float(pcm.decode_s16(i * 2)) / 32767.0
		var phase := TAU * frequency * float(i) / Sfx.MIX_RATE
		real += value * cos(phase)
		imaginary += value * sin(phase)
	return real * real + imaginary * imaginary


func _check(caption: String, ok: bool) -> void:
	_checks += 1
	_failures += 0 if ok else 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", caption])
