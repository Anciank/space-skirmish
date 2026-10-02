extends Node
## Registers the whole input map at runtime.
##
## Doing it in code (instead of hand-editing project.godot) keeps the bindings
## readable and guarantees every action exists before anything polls input.

const DEADZONE := 0.18

## action name -> array of physical keycodes
const KEYS := {
	"thrust_forward": [KEY_W, KEY_UP],
	"thrust_back": [KEY_S, KEY_DOWN],
	"thrust_left": [KEY_A, KEY_LEFT],
	"thrust_right": [KEY_D, KEY_RIGHT],
	"roll_left": [KEY_Q],
	"roll_right": [KEY_E],
	"thrust_up": [KEY_R],
	"thrust_down": [KEY_F],
	"boost": [KEY_SHIFT],
	"fire": [KEY_SPACE],
	"dampeners": [KEY_X],
	"recenter": [KEY_C],
	"next_target": [KEY_TAB],
	"toggle_camera": [KEY_V],
	"toggle_mouse": [KEY_M],
	"pause": [KEY_ESCAPE, KEY_P],
	"restart": [KEY_F5],
}

## action name -> [joypad button]
const PAD_BUTTONS := {
	"fire": [JOY_BUTTON_A],
	"boost": [JOY_BUTTON_LEFT_STICK],
	"next_target": [JOY_BUTTON_RIGHT_SHOULDER],
	"recenter": [JOY_BUTTON_RIGHT_STICK],
	"dampeners": [JOY_BUTTON_B],
	"pause": [JOY_BUTTON_START],
	"thrust_up": [JOY_BUTTON_DPAD_UP],
	"thrust_down": [JOY_BUTTON_DPAD_DOWN],
}

## action name -> [joypad axis, direction]
const PAD_AXES := {
	"steer_x": [[JOY_AXIS_RIGHT_X, 1.0]],
	"steer_y": [[JOY_AXIS_RIGHT_Y, 1.0]],
	"thrust_forward": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]],
	"thrust_back": [[JOY_AXIS_TRIGGER_LEFT, 1.0]],
	"thrust_left": [[JOY_AXIS_LEFT_X, -1.0]],
	"thrust_right": [[JOY_AXIS_LEFT_X, 1.0]],
	"roll_left": [[JOY_AXIS_LEFT_Y, -1.0]],
	"roll_right": [[JOY_AXIS_LEFT_Y, 1.0]],
}


## NOTE: registration happens in `_ready()`, never `_init()`.
##
## An autoload's `_init()` runs while the singleton is being constructed, which
## is *before* the engine finishes applying `project.godot`'s `[input]` section.
## The settings load then overwrites the InputMap, leaving every action present
## but bound to zero events — so `InputMap.has_action()` passes, the action
## exists, and no key ever fires it. `_ready()` runs after that load, so the
## bindings survive.
func _ready() -> void:
	for action: String in KEYS:
		_add_action(action)
		for code: int in KEYS[action]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(action, key)

	for action: String in PAD_BUTTONS:
		_add_action(action)
		for button: int in PAD_BUTTONS[action]:
			var btn := InputEventJoypadButton.new()
			btn.button_index = button
			InputMap.action_add_event(action, btn)

	for action: String in PAD_AXES:
		_add_action(action)
		for pair: Array in PAD_AXES[action]:
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(pair[0])
			motion.axis_value = float(pair[1])
			InputMap.action_add_event(action, motion)


## Creates the action if it does not exist yet.
##
## Must NOT erase an existing action: several actions are declared in more than
## one table (e.g. "thrust_forward" is in both KEYS and PAD_AXES), and erasing
## on the second pass silently discards the key bindings installed by the first.
## The symptom is an action that exists and reports a gamepad axis as its only
## event, so the keyboard does nothing while `has_action()` still says fine.
func _add_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
