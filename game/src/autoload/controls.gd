extends Node
## Default input bindings, registered at startup so every scene (and headless tests) sees
## the same actions. A rebinding UI (PLAN.md §10) will save overrides on top of these.

## action → events. Keys are physical (layout-independent) keycodes.
var _defaults: Dictionary[StringName, Array] = {
	&"rv_throttle": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
	&"rv_brake": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
	&"rv_steer_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
	&"rv_steer_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
	&"rv_clutch": [_key(KEY_Q), _button(JOY_BUTTON_X)],
	&"rv_handbrake": [_key(KEY_SPACE), _button(JOY_BUTTON_B)],
	&"rv_shift_up": [_key(KEY_E), _mouse(MOUSE_BUTTON_WHEEL_UP), _button(JOY_BUTTON_RIGHT_SHOULDER)],
	&"rv_shift_down": [_key(KEY_Z), _mouse(MOUSE_BUTTON_WHEEL_DOWN), _button(JOY_BUTTON_LEFT_SHOULDER)],
	&"rv_gear_reverse": [_key(KEY_R)],
	&"rv_gear_1": [_key(KEY_1)],
	&"rv_gear_2": [_key(KEY_2)],
	&"rv_gear_3": [_key(KEY_3)],
	&"rv_gear_4": [_key(KEY_4)],
	&"rv_gear_5": [_key(KEY_5)],
	&"rv_ignition": [_key(KEY_I), _button(JOY_BUTTON_Y)],
	&"rv_headlights": [_key(KEY_L), _button(JOY_BUTTON_DPAD_UP)],
	&"rv_toggle_gearbox": [_key(KEY_T), _button(JOY_BUTTON_DPAD_DOWN)],
	&"rv_reset": [_key(KEY_BACKSPACE), _button(JOY_BUTTON_START)],
	&"camera_toggle": [_key(KEY_C), _button(JOY_BUTTON_BACK)],
	&"camera_look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
	&"camera_look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
	&"camera_look_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
	&"camera_look_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
	&"toggle_help": [_key(KEY_F1)],
}


func _enter_tree() -> void:
	for action: StringName in _defaults:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		for event: InputEvent in _defaults[action]:
			InputMap.action_add_event(action, event)


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	return e


static func _button(button: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	return e


static func _axis(axis: JoyAxis, direction: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = direction
	return e


static func _mouse(button: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	return e
