extends Node
## Headless key-rebinding test: the defaults split into key / second / controller slots; binding
## a key takes effect in the input map at once and takes it off other actions of the same
## kind (on foot vs driving are separate); reserved keys and wrong kinds of event are refused;
## clearing and resetting work; the choices are saved and read back (in a scratch file, never
## the player's own); bindings round-trip through their text form; prompts name the bound key
## (or the controller button once a controller's been used); and the bindings screen rebinds,
## clears, cancels and reports what it displaced.
##
##   godot --headless --path game --fixed-fps 60 res://tests/controls.tscn

var _failures: PackedStringArray = []
var _saved_path := ""


func _ready() -> void:
	_run()


func _run() -> void:
	_saved_path = Controls.path
	Controls.path = "user://controls_test.cfg"
	DirAccess.remove_absolute(Controls.path)
	Controls.reset_all()
	_defaults()
	_naming()
	_round_trip()
	_binding()
	_conflicts()
	_refusals()
	_saving()
	await _screen()
	await _live_input()
	Controls.reset_all()
	DirAccess.remove_absolute(Controls.path)
	Controls.path = _saved_path
	_finish()


func _defaults() -> void:
	var interact := Controls.slots(&"interact")
	_check(interact[0] is InputEventKey and (interact[0] as InputEventKey).physical_keycode == KEY_E, "interact: E on the first slot")
	_check(interact[1] == null, "... nothing on the second")
	_check(interact[2] is InputEventJoypadButton and (interact[2] as InputEventJoypadButton).button_index == JOY_BUTTON_X, "... X on the controller")
	var drop := Controls.slots(&"drop_item")
	_check((drop[0] as InputEventKey).physical_keycode == KEY_Q and (drop[1] as InputEventKey).physical_keycode == KEY_G, "drop: Q, and G as the second key")
	var shift := Controls.slots(&"rv_shift_up")
	_check((shift[0] as InputEventKey).physical_keycode == KEY_E and shift[1] is InputEventMouseButton and shift[2] is InputEventJoypadButton, "shift up: E, wheel up, RB")
	_check(Controls.slots(&"rv_throttle")[2] is InputEventJoypadMotion, "throttle's on the right trigger (an axis)")
	for row: Array in Controls.LAYOUT:
		if row.size() == 3:
			_check(InputMap.has_action(row[0]) and Controls.is_default(row[0]), "%s exists and starts at its default" % row[0])
	_check(not Controls.has_custom_bindings(), "nothing's custom to start with")
	_check(InputMap.has_action(&"rv_horn"), "there's a horn action")
	_check(InputMap.action_get_events(&"pause_menu").size() == 2, "Esc and Menu pause")


func _naming() -> void:
	_check(Controls.describe(Controls._key(KEY_W)) == "W", "W is named W (%s)" % Controls.describe(Controls._key(KEY_W)))
	_check(Controls.describe(Controls._mouse(MOUSE_BUTTON_LEFT)) == "LMB", "left mouse button")
	_check(Controls.describe(Controls._mouse(MOUSE_BUTTON_WHEEL_UP)) == "Wheel up", "wheel up")
	_check(Controls.describe(Controls._button(JOY_BUTTON_RIGHT_SHOULDER)) == "RB", "RB")
	_check(Controls.describe(Controls._axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)) == "RT", "right trigger")
	_check(Controls.describe(Controls._axis(JOY_AXIS_LEFT_X, -1.0)) == "Left stick ←", "left stick left")
	_check(Controls.prompt(&"interact") == "E", "the interact prompt names E")
	Controls.using_pad = true
	_check(Controls.prompt(&"interact") == "X", "... and X once a controller's been used")
	_check(Controls.prompt(&"slot_1") == "1", "... a key-only action still shows its key")
	Controls.using_pad = false
	_check(Controls.label_of(&"rv_horn") == "Horn", "labels come from the layout")


func _round_trip() -> void:
	for e: InputEvent in [Controls._key(KEY_V), Controls._mouse(MOUSE_BUTTON_MIDDLE), Controls._button(JOY_BUTTON_Y),
			Controls._axis(JOY_AXIS_RIGHT_Y, -1.0), Controls._axis(JOY_AXIS_TRIGGER_LEFT, 1.0)]:
		var back := Controls.decode(Controls.encode(e))
		_check(back != null and Controls._same(e, back), "%s round-trips (%s)" % [Controls.describe(e), Controls.encode(e)])
	for junk: String in ["", "k", "k:x", "z:4", "a:2", "m:0", "k:-3"]:
		_check(Controls.decode(junk) == null, "'%s' isn't a binding" % junk)


func _binding() -> void:
	var displaced := Controls.bind(&"interact", 0, Controls._key(KEY_V))
	_check(displaced.is_empty(), "V was free")
	_check(InputMap.event_is_action(Controls._key(KEY_V), &"interact"), "V now interacts")
	_check(not InputMap.event_is_action(Controls._key(KEY_E), &"interact"), "E doesn't any more")
	_check(Controls.prompt(&"interact") == "V", "the prompt says V")
	_check(not Controls.is_default(&"interact") and Controls.has_custom_bindings(), "it's marked as changed")
	_check(InputMap.event_is_action(Controls._button(JOY_BUTTON_X), &"interact"), "the controller's untouched")
	Controls.bind(&"interact", 1, Controls._mouse(MOUSE_BUTTON_MIDDLE))
	_check(InputMap.event_is_action(Controls._mouse(MOUSE_BUTTON_MIDDLE), &"interact"), "a mouse button goes on the second slot")
	Controls.bind(&"interact", 2, Controls._button(JOY_BUTTON_BACK))
	_check(InputMap.event_is_action(Controls._button(JOY_BUTTON_BACK), &"interact") and not InputMap.event_is_action(Controls._button(JOY_BUTTON_X), &"interact"), "a controller button replaces the controller's")
	# Clearing.
	Controls.bind(&"interact", 1, null)
	_check(Controls.slots(&"interact")[1] == null and not InputMap.event_is_action(Controls._mouse(MOUSE_BUTTON_MIDDLE), &"interact"), "clearing a slot empties it")
	Controls.reset_action(&"interact")
	_check(Controls.is_default(&"interact") and InputMap.event_is_action(Controls._key(KEY_E), &"interact"), "resetting puts E back")
	# The same event on two slots of one action collapses to one.
	Controls.bind(&"jump", 1, Controls._key(KEY_C))
	Controls.bind(&"jump", 0, Controls._key(KEY_C))
	_check(Controls.slots(&"jump")[0] != null and Controls.slots(&"jump")[1] == null, "the same key isn't kept twice on one action")
	Controls.reset_action(&"jump")


func _conflicts() -> void:
	# On foot: V taken by the flashlight comes off interact (which has it after this).
	Controls.bind(&"interact", 0, Controls._key(KEY_V))
	var displaced := Controls.bind(&"flashlight", 0, Controls._key(KEY_V))
	_check(displaced == [&"interact"], "V comes off interact when the flashlight takes it (%s)" % [displaced])
	_check(Controls.slots(&"interact")[0] == null and Controls.slots(&"interact")[2] != null, "... only that slot; its controller button stays")
	_check(not InputMap.event_is_action(Controls._key(KEY_V), &"interact") and InputMap.event_is_action(Controls._key(KEY_V), &"flashlight"), "... and the input map agrees")
	# The horn (driving) and the flashlight (on foot) may share a key: never used at once.
	var shared := Controls.bind(&"rv_horn", 0, Controls._key(KEY_V))
	_check(shared.is_empty(), "driving actions don't clash with on-foot ones")
	_check(InputMap.event_is_action(Controls._key(KEY_V), &"flashlight") and InputMap.event_is_action(Controls._key(KEY_V), &"rv_horn"), "... V does both")
	# Getting up is used in both, so it clashes with either.
	var both := Controls.bind(&"leave_seat", 0, Controls._key(KEY_V))
	_check(both.size() == 2 and both.has(&"flashlight") and both.has(&"rv_horn"), "get up clashes with both kinds (%s)" % [both])
	# Resetting takes the default back even from whoever's using it now.
	Controls.bind(&"flashlight", 0, Controls._key(KEY_E))
	_check(Controls.slots(&"interact")[0] == null, "E moved off interact (already empty here)")
	Controls.reset_action(&"interact")
	_check(Controls.slots(&"interact")[0] != null and Controls.slots(&"flashlight")[0] == null, "resetting interact wins E back from the flashlight")
	Controls.reset_all()
	_check(not Controls.has_custom_bindings(), "reset all puts everything back")


func _refusals() -> void:
	for code: Key in Controls.RESERVED_KEYS:
		_check(not Controls.fits(0, Controls._key(code)), "%s is reserved" % Controls.key_name(code))
	var before: Variant = Controls.slots(&"jump")[0]
	_check(Controls.bind(&"jump", 0, Controls._key(KEY_F1)).is_empty() and Controls.slots(&"jump")[0] == before, "binding F1 does nothing")
	_check(not Controls.fits(0, Controls._button(JOY_BUTTON_A)), "a controller button doesn't fit a key slot")
	_check(not Controls.fits(2, Controls._key(KEY_A)), "a key doesn't fit the controller slot")
	_check(Controls.fits(2, Controls._axis(JOY_AXIS_LEFT_X, 1.0)) and Controls.fits(1, Controls._mouse(MOUSE_BUTTON_WHEEL_DOWN)), "a stick fits the controller slot, the wheel a mouse slot")
	Controls.bind(&"jump", 5, Controls._key(KEY_C))
	Controls.bind(&"not_an_action", 0, Controls._key(KEY_C))
	_check(Controls.is_default(&"jump") and not InputMap.has_action(&"not_an_action"), "nonsense slots and actions are ignored")


func _saving() -> void:
	DirAccess.remove_absolute(Controls.path)
	Controls.reset_all()
	_check(not FileAccess.file_exists(Controls.path), "no file while everything's default")
	Controls.bind(&"jump", 0, Controls._key(KEY_C))
	Controls.bind(&"rv_horn", 2, Controls._axis(JOY_AXIS_RIGHT_Y, 1.0))
	Controls.bind(&"drop_item", 1, null)
	_check(FileAccess.file_exists(Controls.path), "changes are saved")
	var fresh: Node = load("res://src/autoload/controls.gd").new()
	fresh.path = Controls.path
	fresh._enter_tree()
	_check(Controls._same(fresh.slots(&"jump")[0], Controls._key(KEY_C)) and fresh.slots(&"jump")[1] == null, "jump on C is read back")
	_check(Controls._same(fresh.slots(&"rv_horn")[2], Controls._axis(JOY_AXIS_RIGHT_Y, 1.0)), "the horn's stick direction is read back")
	_check(fresh.slots(&"drop_item")[1] == null and fresh.slots(&"drop_item")[0] != null, "a cleared slot stays cleared")
	_check(fresh.is_default(&"interact"), "what wasn't changed is default")
	fresh.free()
	# A file with rubbish in it: skipped, the rest still read.
	var cfg := ConfigFile.new()
	cfg.set_value("bindings", "jump", PackedStringArray(["k:67", "", "k:66"]))
	cfg.set_value("bindings", "interact", PackedStringArray(["not", "a", "binding"]))
	cfg.set_value("bindings", "ghost", PackedStringArray(["k:67", "", ""]))
	cfg.set_value("bindings", "crouch", "wrong type")
	cfg.save(Controls.path)
	Controls.reset_all()
	DirAccess.remove_absolute(Controls.path)
	cfg.save(Controls.path)
	Controls.load_bindings()
	_check(Controls._same(Controls.slots(&"jump")[0], Controls._key(KEY_C)), "a good line loads")
	_check(Controls.slots(&"jump")[2] == null, "... but a key can't go in the controller slot (%s)" % Controls.slots(&"jump")[2])
	_check(Controls.slots(&"interact").all(func(e: Variant) -> bool: return e == null), "a line of nonsense empties the action rather than crashing")
	_check(Controls.is_default(&"crouch"), "a wrong-typed value is ignored")
	Controls.reset_all()
	_check(not FileAccess.file_exists(Controls.path), "resetting everything removes the file")


func _screen() -> void:
	var menu := SettingsMenu.new()
	add_child(menu)
	await get_tree().process_frame
	var screen := menu.open_bindings()
	await get_tree().process_frame
	_check(screen.is_inside_tree() and screen._buttons.has(&"interact") and screen._buttons.has(&"rv_horn"), "the settings open the bindings screen with every action")
	_check((screen._buttons[&"interact"][0] as Button).text == "E" and (screen._buttons[&"interact"][1] as Button).text == "—", "it shows E and an empty second slot")
	_check((screen._resets[&"interact"] as Button).disabled, "nothing to reset yet")

	# Click the slot, press a key.
	screen.listen(&"interact", 0)
	_check(screen.is_listening() and (screen._buttons[&"interact"][0] as Button).text == "press…", "clicking a slot waits for a key")
	screen._input(_key_event(KEY_B))
	_check(Controls.slots(&"interact")[0] != null and (Controls.slots(&"interact")[0] as InputEventKey).physical_keycode == KEY_E, "a key straight away (the click that chose it) is ignored")
	await get_tree().create_timer(BindingsMenu.LISTEN_DELAY + 0.1).timeout
	screen._input(_key_event(KEY_B, false))
	_check(screen.is_listening(), "a key going up isn't an answer")
	screen._input(_key_event(KEY_B))
	_check(not screen.is_listening() and (Controls.slots(&"interact")[0] as InputEventKey).physical_keycode == KEY_B, "the next key press is bound (B)")
	_check((screen._buttons[&"interact"][0] as Button).text == "B" and not (screen._resets[&"interact"] as Button).disabled, "the screen shows B and lets it be reset")

	# Taking a key another action uses says so.
	screen.listen(&"jump", 0)
	await get_tree().create_timer(0.3).timeout
	screen._input(_key_event(KEY_B))
	_check(Controls.slots(&"interact")[0] == null and screen._hint.text.contains("Taken off Interact"), "taking B for Jump says it came off Interact (%s)" % screen._hint.text)

	# The wrong kind of thing is refused and it keeps waiting.
	screen.listen(&"jump", 0)
	await get_tree().create_timer(0.3).timeout
	screen._input(_key_event(KEY_F1))
	_check(screen.is_listening() and screen._hint.text.contains("can't go there"), "F1 can't be bound; it keeps waiting")
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	pad.pressed = true
	screen._input(pad)
	_check(screen.is_listening(), "a controller button can't go on a key slot")
	# Esc cancels (and doesn't close the screen).
	screen._input(_key_event(KEY_ESCAPE))
	_check(not screen.is_listening() and is_instance_valid(screen) and not screen.is_queued_for_deletion(), "Esc cancels")

	# Controllers: a stick push on the controller slot.
	screen.listen(&"rv_horn", 2)
	await get_tree().create_timer(0.3).timeout
	var weak := InputEventJoypadMotion.new()
	weak.axis = JOY_AXIS_RIGHT_X
	weak.axis_value = 0.3
	screen._input(weak)
	_check(screen.is_listening(), "a small stick movement is ignored")
	var push := InputEventJoypadMotion.new()
	push.axis = JOY_AXIS_RIGHT_X
	push.axis_value = 0.9
	screen._input(push)
	_check(not screen.is_listening() and Controls._same(Controls.slots(&"rv_horn")[2], Controls._axis(JOY_AXIS_RIGHT_X, 1.0)), "a firm stick push is bound (%s)" % Controls.describe(Controls.slots(&"rv_horn")[2]))

	# Delete clears; the reset button and Reset all put things back.
	screen.listen(&"rv_horn", 0)
	await get_tree().create_timer(0.3).timeout
	screen._input(_key_event(KEY_DELETE))
	_check(Controls.slots(&"rv_horn")[0] == null and (screen._buttons[&"rv_horn"][0] as Button).text == "—", "Delete clears a slot")
	(screen._resets[&"rv_horn"] as Button).pressed.emit()
	_check(Controls.is_default(&"rv_horn"), "the row's reset button puts it back")
	(screen._resets[&"jump"] as Button).pressed.emit()
	_check(Controls.is_default(&"jump"), "and jump's")
	Controls.bind(&"crouch", 0, Controls._key(KEY_X))
	for b: Node in screen.find_children("*", "Button", true, false):
		if (b as Button).text == "Reset all":
			(b as Button).pressed.emit()
	_check(not Controls.has_custom_bindings(), "Reset all puts everything back")

	# Esc closes the bindings screen, not the settings under it.
	screen._input(_key_event(KEY_ESCAPE))
	await get_tree().process_frame
	_check(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "Esc closes the bindings screen when nothing's waiting")
	_check(is_instance_valid(menu) and not menu.is_queued_for_deletion(), "... leaving the settings")
	menu.queue_free()
	await get_tree().process_frame


func _live_input() -> void:
	# A rebound key drives the real action (what the game reads).
	Controls.bind(&"crouch", 0, Controls._key(KEY_X))
	Input.parse_input_event(_key_event(KEY_X))
	await get_tree().process_frame
	_check(Input.is_action_pressed(&"crouch"), "pressing the new key crouches")
	Input.parse_input_event(_key_event(KEY_X, false))
	await get_tree().process_frame
	_check(not Input.is_action_pressed(&"crouch"), "and letting go stops it")
	Input.parse_input_event(_key_event(KEY_CTRL))
	await get_tree().process_frame
	_check(not Input.is_action_pressed(&"crouch"), "the old key does nothing")
	Input.parse_input_event(_key_event(KEY_CTRL, false))
	await get_tree().process_frame
	Controls.reset_all()


func _key_event(code: Key, down: bool = true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	return e


func _finish() -> void:
	if _failures.is_empty():
		print("controls: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
