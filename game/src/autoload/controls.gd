extends Node
## Input bindings, registered at startup so every scene (and headless tests) sees the same
## actions, with the player's own choices (`user://controls.cfg`) laid over the defaults.
##
## Each rebindable action has three slots: a key or mouse button, a second one (an alternative),
## and a controller button or stick/trigger direction. Binding something that another action of
## the same kind (on foot, or driving) already uses takes it off that action. Escape, F1, F3,
## F5-F8 and the right stick's look are fixed. The settings screen is `BindingsMenu`.

## Something was rebound.
signal bindings_changed

const PATH := "user://controls.cfg"
## Key, second key or mouse button, controller.
const SLOTS := 3
const SLOT_PAD := 2
const SLOT_NAMES: Array[String] = ["Key", "Second", "Controller"]
## Where an action is used; actions only clash with others that share a context.
const FOOT := 1
const DRIVE := 2
## Keys the game uses itself (menus, overlays, graphics presets): not for binding.
const RESERVED_KEYS: Array[Key] = [KEY_ESCAPE, KEY_F1, KEY_F3, KEY_F5, KEY_F6, KEY_F7, KEY_F8]
## The rebindable actions in the order the screen lists them: a heading, then
## [action, label, contexts].
const LAYOUT: Array[Array] = [
	["On foot"],
	[&"move_forward", "Walk forward", FOOT], [&"move_back", "Walk back", FOOT],
	[&"move_left", "Walk left", FOOT], [&"move_right", "Walk right", FOOT],
	[&"sprint", "Sprint", FOOT], [&"crouch", "Crouch", FOOT], [&"jump", "Jump", FOOT],
	[&"interact", "Interact", FOOT], [&"use_item", "Use the held item", FOOT],
	[&"throw_item", "Throw the held item", FOOT], [&"drop_item", "Drop the held item", FOOT],
	[&"winch_select", "Winch remote: front / rear", FOOT], [&"flashlight", "Flashlight", FOOT],
	[&"slot_1", "Hotbar slot 1", FOOT], [&"slot_2", "Hotbar slot 2", FOOT],
	[&"slot_3", "Hotbar slot 3", FOOT], [&"slot_4", "Hotbar slot 4", FOOT],
	[&"slot_next", "Next hotbar slot", FOOT], [&"slot_prev", "Previous hotbar slot", FOOT],
	["Driving"],
	[&"rv_throttle", "Throttle", DRIVE], [&"rv_brake", "Brake / reverse", DRIVE],
	[&"rv_steer_left", "Steer left", DRIVE], [&"rv_steer_right", "Steer right", DRIVE],
	[&"rv_handbrake", "Handbrake", DRIVE], [&"rv_clutch", "Clutch", DRIVE],
	[&"rv_shift_up", "Shift up", DRIVE], [&"rv_shift_down", "Shift down", DRIVE],
	[&"rv_gear_1", "Gear 1", DRIVE], [&"rv_gear_2", "Gear 2", DRIVE], [&"rv_gear_3", "Gear 3", DRIVE],
	[&"rv_gear_4", "Gear 4", DRIVE], [&"rv_gear_5", "Gear 5", DRIVE], [&"rv_gear_reverse", "Reverse", DRIVE],
	[&"rv_toggle_gearbox", "Manual / automatic", DRIVE], [&"rv_ignition", "Start the engine", DRIVE],
	[&"rv_headlights", "Headlights", DRIVE], [&"rv_horn", "Horn", DRIVE],
	[&"rv_reset", "Back on the wheels", DRIVE],
	["In a seat"],
	[&"leave_seat", "Get up", FOOT | DRIVE],
]

## action → events, in slot order (see `_split`). Keys are physical (layout-independent).
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
	&"rv_horn": [_key(KEY_H), _button(JOY_BUTTON_LEFT_STICK)],
	&"rv_reset": [_key(KEY_BACKSPACE), _button(JOY_BUTTON_RIGHT_STICK)],
	&"pause_menu": [_key(KEY_ESCAPE), _button(JOY_BUTTON_START)],
	&"camera_look_left": [_axis(JOY_AXIS_RIGHT_X, -1.0)],
	&"camera_look_right": [_axis(JOY_AXIS_RIGHT_X, 1.0)],
	&"camera_look_up": [_axis(JOY_AXIS_RIGHT_Y, -1.0)],
	&"camera_look_down": [_axis(JOY_AXIS_RIGHT_Y, 1.0)],
	&"toggle_help": [_key(KEY_F1)],
	# On foot.
	&"move_forward": [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
	&"move_back": [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
	&"move_left": [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
	&"move_right": [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
	&"jump": [_key(KEY_SPACE), _button(JOY_BUTTON_A)],
	&"sprint": [_key(KEY_SHIFT), _button(JOY_BUTTON_LEFT_STICK)],
	&"crouch": [_key(KEY_CTRL), _button(JOY_BUTTON_RIGHT_STICK)],
	&"interact": [_key(KEY_E), _button(JOY_BUTTON_X)],
	&"use_item": [_mouse(MOUSE_BUTTON_LEFT), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)],
	&"throw_item": [_mouse(MOUSE_BUTTON_RIGHT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0)],
	&"drop_item": [_key(KEY_Q), _key(KEY_G), _button(JOY_BUTTON_B)],
	&"winch_select": [_key(KEY_R), _button(JOY_BUTTON_Y)],
	&"flashlight": [_key(KEY_L), _button(JOY_BUTTON_DPAD_UP)],
	&"slot_1": [_key(KEY_1)],
	&"slot_2": [_key(KEY_2)],
	&"slot_3": [_key(KEY_3)],
	&"slot_4": [_key(KEY_4)],
	&"slot_next": [_mouse(MOUSE_BUTTON_WHEEL_DOWN), _button(JOY_BUTTON_RIGHT_SHOULDER)],
	&"slot_prev": [_mouse(MOUSE_BUTTON_WHEEL_UP), _button(JOY_BUTTON_LEFT_SHOULDER)],
	# In a seat.
	&"leave_seat": [_key(KEY_F), _button(JOY_BUTTON_DPAD_RIGHT)],
}

## Where the bindings are kept (tests point it elsewhere).
var path := PATH
## Whether the last input came from a controller (so prompts name its buttons).
var using_pad := false

## action → its SLOTS events (null for an empty slot).
var _slots: Dictionary[StringName, Array] = {}
var _contexts: Dictionary[StringName, int] = {}
var _labels: Dictionary[StringName, String] = {}


func _enter_tree() -> void:
	for row: Array in LAYOUT:
		if row.size() == 3:
			_contexts[row[0]] = row[2]
			_labels[row[0]] = row[1]
	for action: StringName in _defaults:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.15)
		_slots[action] = _split(_defaults[action])
		_apply(action)
	load_bindings()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		using_pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		using_pad = true
	elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		using_pad = false


# --- reading -------------------------------------------------------------------------------

## The label of a rebindable action ("Throttle").
func label_of(action: StringName) -> String:
	return _labels.get(action, String(action))


## The events on `action`'s slots (null where empty).
func slots(action: StringName) -> Array:
	return _slots.get(action, [null, null, null])


## What to show for `action` in a prompt: its key or mouse button, or its controller button
## if that's what was used last (or the only thing it has).
func prompt(action: StringName) -> String:
	var s := slots(action)
	var order: Array[int] = []
	order.assign([SLOT_PAD, 0, 1] if using_pad else [0, 1, SLOT_PAD])
	for i: int in order:
		if s[i] != null:
			return describe(s[i])
	return "?"


func is_default(action: StringName) -> bool:
	var now := slots(action)
	var was := _split(_defaults.get(action, []))
	for i: int in SLOTS:
		if not _same(now[i], was[i]):
			return false
	return true


func has_custom_bindings() -> bool:
	for action: StringName in _labels:
		if not is_default(action):
			return true
	return false


## Which actions clash with `event` if it went on `action`: the others in the same context
## that already use it.
func users_of(event: InputEvent, action: StringName) -> Array[StringName]:
	var found: Array[StringName] = []
	var context := int(_contexts.get(action, 0))
	for other: StringName in _labels:
		if other == action or not (int(_contexts[other]) & context):
			continue
		for e: Variant in slots(other):
			if e != null and _same(e, event):
				found.append(other)
				break
	return found


## Whether `event` can go in `slot`: keys and mouse buttons in the first two, controller
## buttons and stick or trigger directions in the last (and keys that aren't reserved).
func fits(slot: int, event: InputEvent) -> bool:
	var is_pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if is_pad != (slot == SLOT_PAD):
		return false
	if event is InputEventKey:
		return not RESERVED_KEYS.has((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).button_index in [
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP,
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
	return is_pad


# --- changing ------------------------------------------------------------------------------

## Puts `event` on `action`'s `slot` (an empty `event`, null, clears it). Takes it off the
## other actions in this context that had it, and returns those. Saves.
func bind(action: StringName, slot: int, event: InputEvent) -> Array[StringName]:
	var displaced: Array[StringName] = []
	if not _slots.has(action) or slot < 0 or slot >= SLOTS:
		return displaced
	if event != null:
		if not fits(slot, event):
			return displaced
		event = _copy(event)
		for other: StringName in users_of(event, action):
			var s: Array = _slots[other]
			for i: int in SLOTS:
				if s[i] != null and _same(s[i], event):
					s[i] = null
			_apply(other)
			displaced.append(other)
		# The same event twice on one action is no use.
		var mine: Array = _slots[action]
		for i: int in SLOTS:
			if i != slot and mine[i] != null and _same(mine[i], event):
				mine[i] = null
	_slots[action][slot] = event
	_apply(action)
	save()
	bindings_changed.emit()
	return displaced


func reset_action(action: StringName) -> void:
	if not _defaults.has(action):
		return
	_slots[action] = _split(_defaults[action])
	_apply(action)
	# Putting the defaults back can clash with what's been moved since: the reset action wins.
	for slot: int in SLOTS:
		var e: Variant = _slots[action][slot]
		if e != null:
			for other: StringName in users_of(e, action):
				var s: Array = _slots[other]
				for i: int in SLOTS:
					if s[i] != null and _same(s[i], e):
						s[i] = null
				_apply(other)
	save()
	bindings_changed.emit()


func reset_all() -> void:
	for action: StringName in _defaults:
		_slots[action] = _split(_defaults[action])
		_apply(action)
	save()
	bindings_changed.emit()


# --- saving --------------------------------------------------------------------------------

func save() -> void:
	var cfg := ConfigFile.new()
	for action: StringName in _labels:
		if is_default(action):
			continue
		var text := PackedStringArray()
		for e: Variant in slots(action):
			text.append("" if e == null else encode(e))
		cfg.set_value("bindings", String(action), text)
	if cfg.get_sections().is_empty():
		DirAccess.remove_absolute(path)
	else:
		cfg.save(path)


## Reads the saved bindings over the defaults (unknown actions and events are skipped).
func load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: String in cfg.get_section_keys("bindings") if cfg.has_section("bindings") else PackedStringArray():
		var action := StringName(key)
		if not _labels.has(action):
			continue
		var text: Variant = cfg.get_value("bindings", key)
		if not text is PackedStringArray or (text as PackedStringArray).size() != SLOTS:
			continue
		var events: Array = [null, null, null]
		for i: int in SLOTS:
			var e := decode(text[i])
			events[i] = e if e != null and fits(i, e) else null
		_slots[action] = events
		_apply(action)


## `event` as text for the config file: k:<key>, m:<button>, b:<button>, a:<axis>:<sign>.
static func encode(event: InputEvent) -> String:
	if event is InputEventKey:
		return "k:%d" % (event as InputEventKey).physical_keycode
	if event is InputEventMouseButton:
		return "m:%d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return "b:%d" % (event as InputEventJoypadButton).button_index
	var axis := event as InputEventJoypadMotion
	return "a:%d:%d" % [axis.axis, 1 if axis.axis_value > 0.0 else -1]


## The event `encode` made from `text`, or null.
static func decode(text: String) -> InputEvent:
	var parts := text.split(":")
	if parts.size() < 2 or not parts[1].is_valid_int():
		return null
	var n := int(parts[1])
	match parts[0]:
		"k":
			return _key(n as Key) if n > 0 else null
		"m":
			return _mouse(n as MouseButton) if n > 0 else null
		"b":
			return _button(n as JoyButton) if n >= 0 else null
		"a":
			if parts.size() == 3 and parts[2].is_valid_int() and n >= 0:
				return _axis(n as JoyAxis, 1.0 if int(parts[2]) > 0 else -1.0)
	return null


# --- naming --------------------------------------------------------------------------------

## A short name for an event: "W", "LMB", "Wheel up", "RT", "Left stick ←".
static func describe(event: InputEvent) -> String:
	if event is InputEventKey:
		return key_name((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		return MOUSE_NAMES.get((event as InputEventMouseButton).button_index, "Mouse %d" % (event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		return PAD_NAMES.get((event as InputEventJoypadButton).button_index, "Button %d" % (event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		var names: Array = AXIS_NAMES.get(m.axis, ["Axis %d" % m.axis, "Axis %d" % m.axis])
		return names[0 if m.axis_value < 0.0 else 1]
	return "—"


## The name of a physical key as it's printed on this keyboard layout.
static func key_name(code: Key) -> String:
	var shown := KEY_NONE if DisplayServer.get_name() == "headless" else DisplayServer.keyboard_get_keycode_from_physical(code)
	var text := OS.get_keycode_string(shown if shown != KEY_NONE else code)
	return text if text != "" else "Key %d" % code


const MOUSE_NAMES: Dictionary[int, String] = {
	MOUSE_BUTTON_LEFT: "LMB", MOUSE_BUTTON_RIGHT: "RMB", MOUSE_BUTTON_MIDDLE: "MMB",
	MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
	MOUSE_BUTTON_XBUTTON1: "Mouse 4", MOUSE_BUTTON_XBUTTON2: "Mouse 5",
}
const PAD_NAMES: Dictionary[int, String] = {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Menu", JOY_BUTTON_GUIDE: "Guide",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad up", JOY_BUTTON_DPAD_DOWN: "D-pad down",
	JOY_BUTTON_DPAD_LEFT: "D-pad left", JOY_BUTTON_DPAD_RIGHT: "D-pad right",
	JOY_BUTTON_MISC1: "Share", JOY_BUTTON_TOUCHPAD: "Touchpad",
}
## axis → [negative direction, positive direction].
const AXIS_NAMES: Dictionary[int, Array] = {
	JOY_AXIS_LEFT_X: ["Left stick ←", "Left stick →"], JOY_AXIS_LEFT_Y: ["Left stick ↑", "Left stick ↓"],
	JOY_AXIS_RIGHT_X: ["Right stick ←", "Right stick →"], JOY_AXIS_RIGHT_Y: ["Right stick ↑", "Right stick ↓"],
	JOY_AXIS_TRIGGER_LEFT: ["LT", "LT"], JOY_AXIS_TRIGGER_RIGHT: ["RT", "RT"],
}


# --- internals -----------------------------------------------------------------------------

## Defaults in a list (keys and mouse buttons first, then the controller's) → the slots.
func _split(events: Array) -> Array:
	var s: Array = [null, null, null]
	var next := 0
	for e: InputEvent in events:
		if e is InputEventJoypadButton or e is InputEventJoypadMotion:
			if s[SLOT_PAD] == null:
				s[SLOT_PAD] = e
		elif next < SLOT_PAD:
			s[next] = e
			next += 1
	return s


func _apply(action: StringName) -> void:
	InputMap.action_erase_events(action)
	for e: Variant in _slots[action]:
		if e != null:
			InputMap.action_add_event(action, e)


static func _same(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == b
	return encode(a) == encode(b)


static func _copy(event: InputEvent) -> InputEvent:
	return decode(encode(event))


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
