class_name BindingsMenu
extends CanvasLayer
## The key bindings screen (from the settings): every action with its key, second key or mouse
## button, and controller button. Click one, then press what you want on it (Esc cancels,
## Delete clears). Taking something another action of the same kind used moves it (that
## action's slot goes empty, and the screen says so). Everything's saved as it changes
## (`Controls`).

signal closed

const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.6)
const ACCENT := Color(0.95, 0.62, 0.25)
## Events this soon (seconds) after a button was pressed are the press that chose it, not an
## answer.
const LISTEN_DELAY := 0.2
## How far a stick or trigger has to go to count as pressed.
const AXIS_THRESHOLD := 0.6

var _root := Control.new()
var _grid := GridContainer.new()
var _hint := Label.new()
var _done := Button.new()
## action → its slot buttons and its reset button.
var _buttons: Dictionary[StringName, Array] = {}
var _resets: Dictionary[StringName, Button] = {}
## The slot being changed (action, slot), or none.
var _action: StringName = &""
var _slot := -1
## Seconds left of LISTEN_DELAY.
var _wait := 0.0


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_refresh()
	Controls.bindings_changed.connect(_refresh)
	_done.grab_focus.call_deferred()


func is_listening() -> bool:
	return _slot >= 0


func _input(event: InputEvent) -> void:
	if is_listening():
		_listen(event)
	elif event.is_action_pressed(&"pause_menu") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func _process(dt: float) -> void:
	_wait = maxf(0.0, _wait - dt)


func close() -> void:
	closed.emit()
	queue_free()


## Starts waiting for the next key, button or stick push for `action`'s `slot`.
func listen(action: StringName, slot: int) -> void:
	_action = action
	_slot = slot
	_wait = LISTEN_DELAY
	_hint.text = "%s, %s: press %s.   Esc cancels, Delete clears." % [
		Controls.label_of(action), Controls.SLOT_NAMES[slot].to_lower(),
		"a controller button or push a stick or trigger" if slot == Controls.SLOT_PAD else "a key or mouse button"]
	_refresh()


func _listen(event: InputEvent) -> void:
	if _wait > 0.0:
		return
	var pressed := false
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		pressed = event.pressed and not event.is_echo()
	elif event is InputEventJoypadMotion:
		pressed = absf(event.axis_value) >= AXIS_THRESHOLD
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key and key.physical_keycode == KEY_ESCAPE:
		_stop("")
		return
	if key and key.physical_keycode == KEY_DELETE:
		Controls.bind(_action, _slot, null)
		_stop("%s cleared." % Controls.label_of(_action))
		return
	if not Controls.fits(_slot, event):
		_hint.text = "That can't go there (%s slots take %s)." % [
			Controls.SLOT_NAMES[_slot].to_lower(), "controller buttons and sticks" if _slot == Controls.SLOT_PAD else "keys and mouse buttons, but not Esc, F1, F3 or F5-F8"]
		return
	var action := _action
	var displaced := Controls.bind(action, _slot, event)
	var note := "%s: %s." % [Controls.label_of(action), Controls.describe(event)]
	if not displaced.is_empty():
		var names: PackedStringArray = []
		for d: StringName in displaced:
			names.append(Controls.label_of(d))
		note += "  Taken off %s." % ", ".join(names)
	_stop(note)


func _stop(note: String) -> void:
	_action = &""
	_slot = -1
	_hint.text = note if note != "" else _default_hint()
	_refresh()


static func _default_hint() -> String:
	return "Click a binding, then press the key, button or stick you want."


func _build() -> void:
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.7)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)
	var panel := PanelContainer.new()
	var style := PauseMenu._style(22)
	style.bg_color.a = 0.98
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -400
	panel.offset_right = 400
	panel.offset_top = 24
	panel.offset_bottom = -24
	_root.add_child(panel)
	_root.resized.connect(func() -> void:
		var half := minf(400.0, _root.size.x * 0.5 - 12.0)
		panel.offset_left = -half
		panel.offset_right = half)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	outer.add_child(MainMenu._label("Key bindings", 32, TEXT))
	_hint.text = _default_hint()
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", ACCENT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	_grid.columns = 5
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 6)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)
	scroll.add_child(pad)
	pad.add_child(_grid)
	for row: Array in Controls.LAYOUT:
		if row.size() == 1:
			_grid.add_child(MainMenu._heading(row[0]))
			for i: int in 4:
				var head := MainMenu._label(Controls.SLOT_NAMES[i] if i < Controls.SLOTS else "", 13, DIM)
				head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				_grid.add_child(head)
			continue
		var action: StringName = row[0]
		var label := MainMenu._label(row[1], 15, TEXT)
		label.custom_minimum_size = Vector2(200, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(label)
		var slot_buttons: Array = []
		for slot: int in Controls.SLOTS:
			var b := Button.new()
			b.custom_minimum_size = Vector2(112, 32)
			b.add_theme_font_size_override("font_size", 14)
			b.clip_text = true
			b.pressed.connect(listen.bind(action, slot))
			_grid.add_child(b)
			slot_buttons.append(b)
		_buttons[action] = slot_buttons
		var reset := Button.new()
		reset.text = "↺"
		reset.tooltip_text = "Put %s back to its default" % String(row[1]).to_lower()
		reset.custom_minimum_size = Vector2(36, 32)
		reset.pressed.connect(func() -> void:
			Controls.reset_action(action)
			_stop("%s is back to its default." % Controls.label_of(action)))
		_grid.add_child(reset)
		_resets[action] = reset
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var reset_all := Button.new()
	reset_all.text = "Reset all"
	reset_all.pressed.connect(func() -> void:
		Controls.reset_all()
		_stop("Every binding is back to its default."))
	buttons.add_child(MainMenu._button(reset_all))
	_done.text = "Done"
	_done.pressed.connect(close)
	buttons.add_child(MainMenu._button(_done))
	outer.add_child(buttons)


func _refresh() -> void:
	for action: StringName in _buttons:
		var s := Controls.slots(action)
		for slot: int in Controls.SLOTS:
			var b: Button = _buttons[action][slot]
			var waiting := action == _action and slot == _slot
			b.text = "press…" if waiting else ("—" if s[slot] == null else Controls.describe(s[slot]))
			b.modulate = ACCENT if waiting else Color.WHITE
		_resets[action].disabled = Controls.is_default(action)
