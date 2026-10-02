extends Node
## Procedural sound effects — the demo ships with zero audio assets.
##
## Every clip is synthesised into an AudioStreamWAV at boot: laser zaps, hull
## impacts, shield tingles and the ship engine drone. Keeps the repository tiny
## and lets the pitch/gain react to runtime state (weapon heat, ship speed).

const MIX_RATE := 22050
const VOICE_COUNT := 10

var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_idx := 0
var _engine_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x5EED
	_build_bank()
	_build_voices()
	_build_engine_drone()


# ------------------------------------------------------------------ API ----

## Positional one-shot. `pitch` in semitones, 0 = unmodified.
func play_at(stream_name: String, position: Vector3, volume_db := 0.0, pitch := 0.0, max_distance := 1400.0) -> void:
	if not _bank.has(stream_name) or _voices.is_empty():
		return
	var voice := _voices[_voice_idx]
	_voice_idx = (_voice_idx + 1) % _voices.size()
	voice.stream = _bank[stream_name]
	voice.global_position = position
	voice.volume_db = volume_db
	voice.pitch_scale = clampf(pow(2.0, pitch / 12.0), 0.25, 4.0)
	voice.max_distance = max_distance
	voice.play()


## Non-positional one-shot, used for the local player's own weapons.
func play_local(stream_name: String, volume_db := 0.0, pitch := 0.0) -> void:
	if not _bank.has(stream_name):
		return
	var player := _get_local_voice()
	if player == null:
		return
	player.stream = _bank[stream_name]
	player.volume_db = volume_db
	player.pitch_scale = clampf(pow(2.0, pitch / 12.0), 0.25, 4.0)
	player.play()


## Drives the looping engine drone. `load` is 0..1 throttle, `boost` 0..1.
func set_engine(load: float, boost: float, active: bool) -> void:
	if _engine_player == null:
		return
	if not active:
		_engine_player.volume_db = -60.0
		return
	var target := lerpf(-24.0, -9.0, clampf(load, 0.0, 1.0)) + (4.0 if boost > 0.5 else 0.0)
	_engine_player.volume_db = lerpf(_engine_player.volume_db, target, 0.12)
	_engine_player.pitch_scale = lerpf(0.85, 1.55, clampf(load * 0.5 + boost * 0.5, 0.0, 1.0))


var _local_voices: Array[AudioStreamPlayer] = []
var _local_idx := 0


func _get_local_voice() -> AudioStreamPlayer:
	if _local_voices.is_empty():
		return null
	var p := _local_voices[_local_idx]
	_local_idx = (_local_idx + 1) % _local_voices.size()
	return p


# ------------------------------------------------------------ synthesis ----

func _build_voices() -> void:
	for i in VOICE_COUNT:
		var v := AudioStreamPlayer3D.new()
		v.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		v.unit_size = 55.0
		v.max_db = 0.0
		add_child(v)
		_voices.append(v)
	for i in 4:
		var l := AudioStreamPlayer.new()
		add_child(l)
		_local_voices.append(l)


## A looping stream still held by a live playback keeps its resource alive past
## shutdown, so release everything explicitly on the way out.
func _exit_tree() -> void:
	for v: AudioStreamPlayer3D in _voices:
		if is_instance_valid(v):
			v.stop()
			v.stream = null
	for v: AudioStreamPlayer in _local_voices:
		if is_instance_valid(v):
			v.stop()
			v.stream = null
	if is_instance_valid(_engine_player):
		_engine_player.stop()
		_engine_player.stream = null
	_bank.clear()


func _build_bank() -> void:
	_bank["laser"] = _make_laser()
	_bank["laser_heavy"] = _make_laser(true)
	_bank["impact"] = _make_impact()
	_bank["shield"] = _make_shield()
	_bank["explosion"] = _make_explosion()
	_bank["explosion_big"] = _make_explosion(1.8)
	_bank["thud"] = _make_thud()


func _make_wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size() - 1
	return wav


## Short descending zap with a bit of grit. Heat (0..1) bends the pitch up.
func _make_laser(heavy := false) -> AudioStreamWAV:
	var dur := 0.20 if heavy else 0.13
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var start := 260.0 if heavy else 520.0
	var end := 1700.0 if heavy else 780.0
	var noise := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(start, end, pow(t, 0.45))
		phase += TAU * f / MIX_RATE
		noise = lerpf(noise, _rng.randf_range(-1.0, 1.0), 0.35)
		var env: float = pow(1.0 - t, 2.6)
		var body := sin(phase) * 0.7 + sin(phase * 2.01) * 0.22
		out[i] = (body + noise * 0.28) * env * 0.85
	return _make_wav(out)


## Metallic clank when a hull takes a collision or a bolt.
func _make_impact() -> AudioStreamWAV:
	var dur := 0.18
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / float(n)
		var raw := _rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.55)
		var tone := sin(TAU * 240.0 * t) * 0.35 + sin(TAU * 511.0 * t) * 0.2
		var env: float = pow(1.0 - t, 4.0)
		out[i] = (lp * 0.8 + tone) * env * 0.9
	return _make_wav(out)


## Bright tingle for shield hits.
func _make_shield() -> AudioStreamWAV:
	var dur := 0.30
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(n)
		var env: float = exp(-t * 11.0)
		var s := sin(TAU * 1180.0 * t) * 0.5 + sin(TAU * 1760.0 * t) * 0.32 + sin(TAU * 2640.0 * t) * 0.16
		out[i] = s * env * 0.55
	return _make_wav(out)


## Layered noise + sub-drop boom.
func _make_explosion(pitch_scale := 1.0) -> AudioStreamWAV:
	var dur := 1.0 * pitch_scale
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var sub_phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(120.0 * pitch_scale, 32.0 * pitch_scale, pow(t, 0.6))
		sub_phase += TAU * f / MIX_RATE
		var raw := _rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, lerpf(0.45, 0.06, t))
		var crack := raw * exp(-t * 26.0) * 0.6
		var boom := sin(sub_phase) * exp(-t * 4.2)
		var tail := lp * exp(-t * 3.0) * 0.9
		out[i] = clampf((crack + boom * 0.85 + tail) * 0.8, -1.0, 1.0)
	return _make_wav(out)


## Dull low thump, used for bumping into rocks and the arena wall.
func _make_thud() -> AudioStreamWAV:
	var dur := 0.26
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / float(n)
		var f: float = lerpf(150.0, 48.0, t)
		phase += TAU * f / MIX_RATE
		out[i] = sin(phase) * exp(-t * 9.0) * 0.8
	return _make_wav(out)


## Seamless 2 second loop: stacked detuned saws over a low sine, plus a faint
## filtered-noise "hiss" so the burner feels mechanical rather than tonal.
func _build_engine_drone() -> void:
	var dur := 2.0
	var n := int(MIX_RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := [0.0, 0.0, 0.0, 0.0]
	var freqs := [46.0, 69.5, 92.0, 138.0]
	var noise := 0.0
	for i in n:
		var acc := 0.0
		for k in 4:
			phases[k] += TAU * freqs[k] / MIX_RATE
			if phases[k] > TAU:
				phases[k] -= TAU
			# Soft saw: sums to a rounded edge without aliasing harshness.
			acc += sin(phases[k] + sin(phases[k] * 0.5) * 0.35) * (0.5 / (k + 1))
		noise = lerpf(noise, _rng.randf_range(-1.0, 1.0), 0.06)
		# Crossfade the loop seam so there is no click.
		var t := float(i) / float(n)
		var fade := minf(t / 0.05, (1.0 - t) / 0.05)
		out[i] = (acc * 0.55 + noise * 0.05) * clampf(fade, 0.0, 1.0) * 0.8

	var wav := _make_wav(out, true)
	_engine_player = AudioStreamPlayer.new()
	_engine_player.stream = wav
	_engine_player.volume_db = -60.0
	_engine_player.max_polyphony = 1
	add_child(_engine_player)
	_engine_player.play()
