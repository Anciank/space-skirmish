extends Node
## Deterministic, original synthesis with separate world, cockpit, UI and score
## voices. All steady-state gain changes use elapsed time, including at uncapped FPS.

const MIX_RATE := 22050
const VOICE_COUNT := 16
const LOCAL_COUNT := 8
const UI_COUNT := 4
const PRIORITIES := {
	"laser": 1, "laser_heavy": 1, "shield": 2, "impact": 3, "thud": 3,
	"hit": 2, "boost": 2, "lock": 3, "kill": 5, "critical": 6,
	"explosion": 5, "explosion_big": 5,
}

var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _local_voices: Array[AudioStreamPlayer] = []
var _ui_voices: Array[AudioStreamPlayer] = []
var _engine_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _pulse_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _engine_load := 0.0
var _engine_boost := 0.0
var _context := "command"


func _ready() -> void:
	# Menus and their sounds remain usable while gameplay is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 0x5EED
	_build_bank()
	_build_voices()
	_engine_player = _loop_player(_make_engine(), "Engine")
	_music_player = _loop_player(_make_score(), "Music")
	_pulse_player = _loop_player(_make_pulse(), "Music")
	_music_player.play()
	_pulse_player.play()


func _process(delta: float) -> void:
	if is_instance_valid(_engine_player) and _engine_player.playing:
		var response := 1.0 - exp(-7.0 * delta)
		var gain := lerpf(-26.0, -13.0, _engine_load) + _engine_boost * 3.0
		_engine_player.volume_db = lerpf(_engine_player.volume_db, gain, response)
		_engine_player.pitch_scale = lerpf(_engine_player.pitch_scale,
			lerpf(0.86, 1.42, _engine_load * 0.65 + _engine_boost * 0.35), response)
	var fade := 1.0 - exp(-2.0 * delta)
	if is_instance_valid(_music_player):
		_music_player.volume_db = lerpf(_music_player.volume_db,
			-20.0 if _context == "flight" else -14.0, fade)
	if is_instance_valid(_pulse_player):
		_pulse_player.volume_db = lerpf(_pulse_player.volume_db,
			-19.0 if _context == "flight" else -70.0, fade)


func set_context(context: String) -> void:
	_context = context


func stop_combat_audio() -> void:
	set_engine(0.0, 0.0, false)
	for voice: AudioStreamPlayer3D in _voices:
		voice.stop()
	for voice: AudioStreamPlayer in _local_voices:
		voice.stop()


## Positional one-shot. A quiet, distant shot cannot evict a stronger nearby hit.
func play_at(stream_name: String, position: Vector3, volume_db := 0.0, pitch := 0.0, max_distance := 1400.0) -> void:
	if not _bank.has(stream_name) or _voices.is_empty():
		return
	var camera := get_viewport().get_camera_3d()
	var listener := camera.global_position if camera != null else Vector3.ZERO
	var distance := listener.distance_to(position)
	if distance >= max_distance:
		return
	var strength := _strength(stream_name, volume_db, distance)
	var voice: AudioStreamPlayer3D = null
	var weakest := INF
	for candidate: AudioStreamPlayer3D in _voices:
		if not candidate.playing:
			voice = candidate
			break
		var score := _strength(String(candidate.get_meta("cue", "laser")), candidate.volume_db,
			listener.distance_to(candidate.global_position))
		if score < weakest:
			weakest = score
			voice = candidate
	if voice == null or (voice.playing and strength < weakest):
		return
	voice.stop()
	voice.set_meta("cue", stream_name)
	voice.stream = _bank[stream_name]
	voice.global_position = position
	voice.volume_db = volume_db
	voice.pitch_scale = _pitch(pitch)
	voice.max_distance = max_distance
	voice.play()


func _strength(cue: String, gain: float, distance: float) -> float:
	return float(PRIORITIES.get(cue, 1)) * 4.0 + gain - linear_to_db(maxf(distance / 55.0, 1.0))


## Cockpit cues use their own pool, so remote weapons never steal player feedback.
func play_local(stream_name: String, volume_db := 0.0, pitch := 0.0) -> void:
	_play_nonpositional(_local_voices, stream_name, volume_db, pitch)


func play_ui(stream_name := "ui_select", volume_db := -14.0) -> void:
	_play_nonpositional(_ui_voices, stream_name, volume_db, 0.0)


func _play_nonpositional(pool: Array[AudioStreamPlayer], cue: String, gain: float, pitch: float) -> void:
	if not _bank.has(cue):
		return
	var player: AudioStreamPlayer = null
	var weakest := INF
	var priority := int(PRIORITIES.get(cue, 3))
	for candidate: AudioStreamPlayer in pool:
		if not candidate.playing:
			player = candidate
			break
		var score := float(candidate.get_meta("priority", 1)) * 4.0 + candidate.volume_db
		if score < weakest:
			weakest = score
			player = candidate
	if player == null or (player.playing and priority * 4.0 + gain < weakest):
		return
	player.stop()
	player.set_meta("priority", priority)
	player.set_meta("cue", cue)
	player.stream = _bank[cue]
	player.volume_db = gain
	player.pitch_scale = _pitch(pitch)
	player.play()


func _pitch(semitones: float) -> float:
	return clampf(pow(2.0, semitones / 12.0), 0.25, 4.0)


## Called by flight code; smoothing happens once per frame using delta.
func set_engine(load: float, boost: float, active: bool) -> void:
	if not is_instance_valid(_engine_player):
		return
	if not active:
		_engine_player.stop()
		_engine_boost = 0.0
		return
	var boosting := clampf(boost, 0.0, 1.0)
	if boosting > 0.5 and _engine_boost <= 0.5:
		play_local("boost", -17.0)
	_engine_load = clampf(load, 0.0, 1.0)
	_engine_boost = boosting
	if not _engine_player.playing:
		_engine_player.volume_db = -48.0
		_engine_player.pitch_scale = 0.86
		_engine_player.play()


func _build_voices() -> void:
	for _i in VOICE_COUNT:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "SFX"
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		voice.unit_size = 55.0
		voice.max_db = 0.0
		add_child(voice)
		_voices.append(voice)
	for _i in LOCAL_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		_local_voices.append(voice)
	for _i in UI_COUNT:
		var voice := AudioStreamPlayer.new()
		voice.bus = "UI"
		add_child(voice)
		_ui_voices.append(voice)


func _loop_player(stream: AudioStreamWAV, bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = bus
	player.volume_db = -70.0
	add_child(player)
	return player


func _exit_tree() -> void:
	shutdown_audio()


func shutdown_audio() -> void:
	for voice: AudioStreamPlayer3D in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	for voice: AudioStreamPlayer in _local_voices + _ui_voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
	for player: AudioStreamPlayer in [_engine_player, _music_player, _pulse_player]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_bank.clear()


func finish_audio() -> void:
	shutdown_audio()
	# Mixing uses wall time even when a test advances with --fixed-fps.
	var deadline := Time.get_ticks_msec() + 250
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


# ------------------------------------------------------------ synthesis ----

func _build_bank() -> void:
	_bank["laser"] = _make_laser()
	_bank["laser_heavy"] = _make_laser(true)
	_bank["impact"] = _make_impact()
	_bank["shield"] = _make_shield()
	_bank["explosion"] = _make_explosion()
	_bank["explosion_big"] = _make_explosion(1.8)
	_bank["thud"] = _make_thud()
	_bank["boost"] = _make_boost()
	_bank["ui_focus"] = _make_chime([660.0], 0.035)
	_bank["ui_select"] = _make_chime([660.0, 990.0], 0.065)
	_bank["ui_back"] = _make_chime([660.0, 440.0], 0.06)
	_bank["lock"] = _make_chime([880.0, 1174.66], 0.075)
	_bank["hit"] = _make_chime([1568.0], 0.04)
	_bank["kill"] = _make_chime([783.99, 1174.66, 1568.0], 0.10)
	_bank["deploy"] = _make_chime([293.66, 440.0, 587.33], 0.14)
	_bank["critical"] = _make_chime([440.0, 0.0, 440.0], 0.11)
	_bank["minute"] = _make_chime([587.33, 783.99], 0.17)
	_bank["death"] = _make_chime([587.33, 440.0, 293.66], 0.16)
	_bank["victory"] = _make_chime([392.0, 493.88, 587.33, 783.99], 0.20)
	_bank["defeat"] = _make_chime([392.0, 349.23, 293.66], 0.24)


func _make_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	# Normalize excessive peaks as a whole clip, retaining the waveform's shape.
	var peak := 0.0
	for sample: float in samples:
		peak = maxf(peak, absf(sample))
	var gain := 0.9 / peak if peak > 0.9 else 1.0
	var count := samples.size()
	var bytes := PackedByteArray()
	bytes.resize((count + (1 if loop else 0)) * 2)
	for i in count:
		bytes.encode_s16(i * 2, int(samples[i] * gain * 32767.0))
	if loop:
		# The mixer may read through the boundary; keep an identical guard sample.
		bytes.encode_s16(count * 2, int(samples[0] * gain * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = count
	return wav


func _envelope(time: float, duration: float, attack: float, decay: float) -> float:
	return minf(time / attack, 1.0) * exp(-time * decay) * clampf((duration - time) / 0.02, 0.0, 1.0)


func _make_laser(heavy := false) -> AudioStreamWAV:
	var duration := 0.20 if heavy else 0.13
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * duration))
	var phase := 0.0
	var noise := 0.0
	for i in out.size():
		var time := float(i) / MIX_RATE
		var progress := time / duration
		var frequency := lerpf(1150.0 if heavy else 1500.0, 200.0 if heavy else 420.0, pow(progress, 0.45))
		phase += TAU * frequency / MIX_RATE
		noise = lerpf(noise, _rng.randf_range(-1.0, 1.0), 0.3)
		out[i] = (sin(phase) * 0.65 + sin(phase * 2.0) * 0.12 + noise * 0.22) * _envelope(time, duration, 0.002, 24.0) * 0.85
	return _make_wav(out)


func _make_impact() -> AudioStreamWAV:
	var duration := 0.24
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * duration))
	var noise := 0.0
	for i in out.size():
		var time := float(i) / MIX_RATE
		noise = lerpf(noise, _rng.randf_range(-1.0, 1.0), 0.45)
		var body := sin(TAU * 240.0 * time) * 0.32 + sin(TAU * 511.0 * time) * 0.18
		out[i] = (noise * 0.65 + body) * _envelope(time, duration, 0.002, 22.0)
	return _make_wav(out)


func _make_shield() -> AudioStreamWAV:
	var duration := 0.28
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * duration))
	for i in out.size():
		var time := float(i) / MIX_RATE
		var shimmer := sin(TAU * 1180.0 * time) * 0.48 + sin(TAU * 1760.0 * time) * 0.26 + sin(TAU * 2640.0 * time) * 0.10
		out[i] = shimmer * _envelope(time, duration, 0.004, 18.0) * 0.65
	return _make_wav(out)


func _make_explosion(scale := 1.0) -> AudioStreamWAV:
	var duration := scale
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * duration))
	var noise := 0.0
	var phase := 0.0
	for i in out.size():
		var time := float(i) / MIX_RATE
		var progress := time / duration
		phase += TAU * lerpf(115.0 / sqrt(scale), 32.0, pow(progress, 0.6)) / MIX_RATE
		var raw := _rng.randf_range(-1.0, 1.0)
		noise = lerpf(noise, raw, lerpf(0.38, 0.05, progress))
		var crack := raw * exp(-time * 32.0) * 0.34
		var boom := sin(phase) * exp(-progress * 5.0) * 0.64
		var tail := noise * exp(-progress * 3.8) * 0.75
		out[i] = (crack + boom + tail) * minf(time / 0.003, 1.0) * clampf((duration - time) / 0.08, 0.0, 1.0)
	return _make_wav(out)


func _make_thud() -> AudioStreamWAV:
	var duration := 0.26
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * duration))
	var phase := 0.0
	for i in out.size():
		var time := float(i) / MIX_RATE
		phase += TAU * lerpf(150.0, 48.0, time / duration) / MIX_RATE
		out[i] = sin(phase) * _envelope(time, duration, 0.002, 26.0) * 0.75
	return _make_wav(out)


func _make_boost() -> AudioStreamWAV:
	var duration := 0.55
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * duration))
	var noise := 0.0
	var phase := 0.0
	for i in out.size():
		var time := float(i) / MIX_RATE
		noise = lerpf(noise, _rng.randf_range(-1.0, 1.0), 0.15)
		phase += TAU * lerpf(90.0, 180.0, time / duration) / MIX_RATE
		out[i] = (noise * 0.45 + sin(phase) * 0.32) * sin(PI * time / duration) * 0.8
	return _make_wav(out)


func _make_chime(notes: Array, note_length: float) -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * note_length * notes.size()))
	for i in out.size():
		var time := float(i) / MIX_RATE
		var note := mini(int(time / note_length), notes.size() - 1)
		var local := fmod(time, note_length)
		var phase := TAU * float(notes[note]) * local
		out[i] = (sin(phase) * 0.75 + sin(phase * 2.0) * 0.10) * _envelope(local, note_length, 0.004, 8.0) * 0.55
	return _make_wav(out)


func _make_engine() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(MIX_RATE * 2)
	for i in out.size():
		var time := float(i) / MIX_RATE
		# Integer cycle counts over two seconds create a continuous loop; no dip.
		var body := sin(TAU * 46.0 * time) * 0.35 + sin(TAU * 69.5 * time) * 0.20
		body += sin(TAU * 92.0 * time) * 0.15 + sin(TAU * 138.0 * time) * 0.09
		var rasp := sin(TAU * 46.0 * time) * sin(TAU * 230.0 * time) * 0.07
		rasp += sin(TAU * 311.0 * time + 0.4) * 0.026 + sin(TAU * 517.5 * time + 1.0) * 0.018
		out[i] = (body + rasp) * 0.7
	return _make_wav(out, true)


func _make_score() -> AudioStreamWAV:
	# Eight bars: Am / G / C / F pads, an A pedal and sparse plucked overtones.
	var duration := 16.0
	var roots := [55.0, 49.0, 65.4064, 43.6535]
	var thirds := [3, 4, 4, 4]
	var steps := [0, 7, 12, 7, 3, 7, 10, 7]
	var out := PackedFloat32Array()
	out.resize(int(MIX_RATE * duration))
	for i in out.size():
		var time := float(i) / MIX_RATE
		var chord := mini(int(time / 4.0), 3)
		var local := fmod(time, 4.0)
		var root: float = roots[chord]
		var swell := pow(maxf(0.0, sin(PI * local / 4.0)), 0.65)
		var pad := sin(TAU * root * local) * 0.14 + sin(TAU * root * pow(2.0, float(thirds[chord]) / 12.0) * local) * 0.07
		pad += sin(TAU * root * pow(2.0, 7.0 / 12.0) * local) * 0.08
		var step := int(time / 0.5) % steps.size()
		var pluck_time := fmod(time, 0.5)
		var interval: int = steps[step]
		if interval == 3 and chord != 0:
			interval = 4
		var frequency := root * 4.0 * pow(2.0, float(interval) / 12.0)
		var pluck := (sin(TAU * frequency * pluck_time) + sin(TAU * frequency * 2.0 * pluck_time) * 0.15)
		pluck *= _envelope(pluck_time, 0.5, 0.01, 10.0) * 0.08
		out[i] = pad * swell + pluck + sin(TAU * 55.0 * time) * 0.10 + sin(TAU * 110.0 * time) * 0.025
	return _make_wav(out, true)


func _make_pulse() -> AudioStreamWAV:
	var out := PackedFloat32Array()
	out.resize(MIX_RATE * 4)
	for i in out.size():
		var time := float(i) / MIX_RATE
		var beat := fmod(time, 0.5)
		var kick := sin(TAU * (42.0 * beat + 0.9 * (1.0 - exp(-beat * 35.0))))
		kick *= _envelope(beat, 0.5, 0.002, 15.0) * 0.38
		var tick := fmod(time, 0.25)
		var hat := sin(TAU * 2810.0 * tick) * sin(TAU * 4070.0 * tick)
		hat *= _envelope(tick, 0.25, 0.001, 100.0) * 0.055
		out[i] = kick + hat
	return _make_wav(out, true)
