extends Node
## Validated, persistent player preferences. The UI and gameplay share this source.

signal changed(key: String)

const DEFAULTS := {
	"master_volume": 0.8,
	"sfx_volume": 0.85,
	"engine_volume": 0.7,
	"music_volume": 0.6,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"camera_shake": true,
	"show_hints": true,
	"field_of_view": 84.0,
	"fullscreen": false,
	"difficulty": 1,
}
const DIFFICULTIES := ["CADET", "PILOT", "ACE"]
const AI_SKILLS := [0.65, 1.0, 1.4]

var values: Dictionary = DEFAULTS.duplicate()
var storage_path := "user://settings.cfg"
var last_save_error := OK


func _ready() -> void:
	load_preferences()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant, persist := true) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = _validated(key, value)
	_apply()
	if persist:
		save_preferences()
	changed.emit(key)


func reset_to_defaults(persist := true) -> void:
	values = DEFAULTS.duplicate()
	_apply()
	if persist:
		save_preferences()
	changed.emit("*")


func load_preferences() -> void:
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(storage_path) == OK:
		for key: String in DEFAULTS:
			values[key] = _validated(key, config.get_value("player", key, DEFAULTS[key]))
	_apply()
	changed.emit("*")


func save_preferences() -> Error:
	var config := ConfigFile.new()
	for key: String in values:
		config.set_value("player", key, values[key])
	# Replace the previous file only after a complete write succeeds.
	var temp_path := storage_path + ".tmp"
	last_save_error = config.save(temp_path)
	if last_save_error == OK:
		last_save_error = DirAccess.rename_absolute(temp_path, storage_path)
	return last_save_error


func _validated(key: String, value: Variant) -> Variant:
	var fallback: Variant = DEFAULTS[key]
	if fallback is bool:
		return value if value is bool else fallback
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	match key:
		"master_volume", "sfx_volume", "engine_volume", "music_volume":
			return clampf(float(value), 0.0, 1.0)
		"mouse_sensitivity":
			return clampf(float(value), 0.25, 3.0)
		"field_of_view":
			return clampf(float(value), 70.0, 100.0)
		"difficulty":
			return clampi(int(value), 0, DIFFICULTIES.size() - 1)
	return fallback


func _apply() -> void:
	for pair: Array in [["Master", "master_volume"], ["SFX", "sfx_volume"], ["Engine", "engine_volume"], ["Music", "music_volume"]]:
		var bus := AudioServer.get_bus_index(pair[0])
		if bus >= 0:
			var volume := float(values[pair[1]])
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.0001)))
			AudioServer.set_bus_mute(bus, volume <= 0.0)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(values.fullscreen) else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
