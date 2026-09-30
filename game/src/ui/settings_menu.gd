class_name SettingsMenu
extends CanvasLayer
## The settings screen (from the main menu and the pause menu): display (window, size, vsync,
## frame-rate cap, interface scale), graphics (quality, resolution scale, field of view),
## controls (look speed, invert) and sound (volumes). Changes apply at once and are saved
## (Settings). Esc or Done closes it.

signal closed

const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.6)
const ACCENT := Color(0.95, 0.62, 0.25)
const WINDOW_MODES: Array[String] = ["Windowed", "Fullscreen", "Exclusive fullscreen"]
const QUALITY_NAMES: Dictionary[StringName, String] = {
	&"auto": "Auto", &"potato": "Potato", &"low": "Low", &"medium": "Medium", &"high": "High",
}
const BUS_NAMES: Dictionary[String, String] = {
	"Master": "Master volume", "Effects": "Effects (the RV, tools)", "Ambience": "Ambience (birds, wind, rain)",
}

var _root := Control.new()
var _grid := GridContainer.new()
var _done := Button.new()
var _window := OptionButton.new()
var _size := OptionButton.new()
var _sizes: Array[Vector2i] = []
var _vsync := CheckButton.new()
var _fps := OptionButton.new()
var _ui := OptionButton.new()
var _quality := OptionButton.new()
var _render := OptionButton.new()
var _fov := HSlider.new()
var _look := HSlider.new()
var _invert := CheckButton.new()
var _volumes: Dictionary[String, HSlider] = {}
var _refreshing := false


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_refresh()
	Settings.changed.connect(_refresh)
	_done.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_menu") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


## The key bindings screen, over this one (Esc or Done comes back here).
func open_bindings() -> BindingsMenu:
	var screen := BindingsMenu.new()
	add_child(screen)
	return screen


func _build() -> void:
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.7)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(backdrop)
	var panel := PanelContainer.new()
	var style := PauseMenu._style(22)
	style.bg_color.a = 0.98 # Over the main menu: nothing showing through.
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Centred, up to 760 wide, never taller than the screen (it scrolls).
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -380
	panel.offset_right = 380
	panel.offset_top = 24
	panel.offset_bottom = -24
	_root.add_child(panel)
	_root.resized.connect(func() -> void:
		var half := minf(380.0, _root.size.x * 0.5 - 12.0)
		panel.offset_left = -half
		panel.offset_right = half)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	outer.add_child(MainMenu._label("Settings", 32, TEXT))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 20)
	_grid.add_theme_constant_override("v_separation", 10)
	var pad := MarginContainer.new() # Clear of the scroll bar.
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)
	scroll.add_child(pad)
	pad.add_child(_grid)

	_section("Display")
	for name: String in WINDOW_MODES:
		_window.add_item(name)
	_window.item_selected.connect(func(i: int) -> void: _change(&"window_mode", i))
	_row("Window", _window)
	_size.item_selected.connect(func(i: int) -> void: _change(&"window_size", _sizes[i]))
	_row("Window size", _size)
	_vsync.text = "On"
	_vsync.toggled.connect(func(on: bool) -> void: _change(&"vsync", on))
	_row("Vertical sync", _vsync, "Waits for the display: no tearing, frame rate capped at its refresh rate.")
	for fps: int in Settings.FPS_LIMITS:
		_fps.add_item("Unlimited" if fps == 0 else "%d fps" % fps)
	_fps.item_selected.connect(func(i: int) -> void: _change(&"max_fps", Settings.FPS_LIMITS[i]))
	_row("Frame rate limit", _fps)
	for s: float in Settings.UI_SCALES:
		_ui.add_item("%d %%" % roundi(s * 100.0))
	_ui.item_selected.connect(func(i: int) -> void: _change(&"ui_scale", Settings.UI_SCALES[i]))
	_row("Interface scale", _ui, "Menus and HUD keep their size at any resolution; this makes them bigger or smaller.")

	_section("Graphics")
	for q: StringName in Settings.QUALITIES:
		_quality.add_item(QUALITY_NAMES[q] + (" (%s here)" % QUALITY_NAMES[Graphics.detect_default()] if q == &"auto" else ""))
	_quality.item_selected.connect(func(i: int) -> void: _change(&"quality", Settings.QUALITIES[i]))
	_row("Quality", _quality, "View distance, shadows, trees and ambient occlusion.")
	for r: float in Settings.RENDER_SCALES:
		_render.add_item("The quality's own" if r == 0.0 else "%d %%" % roundi(r * 100.0))
	_render.item_selected.connect(func(i: int) -> void: _change(&"render_scale", Settings.RENDER_SCALES[i]))
	_row("Resolution scale", _render, "The 3D view is drawn at this share of the window's resolution and upscaled.")
	_slider(_fov, Settings.FOV_RANGE, 1.0, func(v: float) -> void: _change(&"fov", v))
	_row("Field of view", _with_value(_fov, "%d°"))

	_section("Controls")
	_slider(_look, Settings.SENSITIVITY_RANGE, 0.05, func(v: float) -> void: _change(&"look_sensitivity", v))
	_row("Look sensitivity", _with_value(_look, "%.2f×"))
	_invert.text = "Inverted"
	_invert.toggled.connect(func(on: bool) -> void: _change(&"invert_y", on))
	_row("Look up and down", _invert)
	var bindings := Button.new()
	bindings.text = "Change key bindings…"
	bindings.pressed.connect(open_bindings)
	_row("Keys and buttons", bindings, "Rebind every action: keyboard, mouse and controller.")

	_section("Sound")
	for bus: String in BUS_NAMES:
		var slider := HSlider.new()
		_slider(slider, Vector2(0.0, 1.0), 0.01, func(v: float) -> void:
			var volumes := Settings.volumes.duplicate()
			volumes[bus] = v
			_change(&"volumes", volumes))
		_volumes[bus] = slider
		_row(BUS_NAMES[bus], _with_value(slider, "%d %%", 100.0))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(Settings.reset)
	buttons.add_child(MainMenu._button(reset))
	_done.text = "Done"
	_done.pressed.connect(close)
	buttons.add_child(MainMenu._button(_done))
	outer.add_child(buttons)


func _section(title: String) -> void:
	var heading := MainMenu._heading(title)
	_grid.add_child(heading)
	_grid.add_child(Control.new())


func _row(title: String, control: Control, hint: String = "") -> void:
	var label := MainMenu._label(title, 16, TEXT)
	label.custom_minimum_size = Vector2(220, 0)
	label.tooltip_text = hint
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 34.0)
	control.tooltip_text = hint
	_grid.add_child(control)


func _slider(slider: HSlider, limits: Vector2, step: float, on_change: Callable) -> void:
	slider.min_value = limits.x
	slider.max_value = limits.y
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(v: float) -> void:
		if not _refreshing:
			on_change.call(v))


## A slider with its value written beside it (`format` of value × `scale`).
func _with_value(slider: HSlider, format: String, scale: float = 1.0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(slider)
	var value := MainMenu._label("", 15, DIM)
	value.custom_minimum_size = Vector2(56, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	var write := func(v: float) -> void: value.text = format % (v * scale)
	slider.value_changed.connect(write)
	write.call(slider.value)
	return row


func _change(key: StringName, value: Variant) -> void:
	if not _refreshing:
		Settings.set_value(key, value)


## Shows the current settings.
func _refresh() -> void:
	_refreshing = true
	_window.selected = Settings.window_mode
	_sizes = Settings.window_sizes()
	_size.clear()
	var now := DisplayServer.window_get_size() if Settings.window_size == Vector2i.ZERO else Settings.window_size
	for s: Vector2i in _sizes:
		_size.add_item("%d × %d" % [s.x, s.y])
	_size.selected = _sizes.find(now)
	_size.disabled = Settings.window_mode != Settings.WindowMode.WINDOWED or _sizes.is_empty()
	_vsync.button_pressed = Settings.vsync
	_fps.selected = maxi(0, Settings.FPS_LIMITS.find(Settings.max_fps))
	_ui.selected = _nearest(Settings.UI_SCALES, Settings.ui_scale)
	_quality.selected = maxi(0, Settings.QUALITIES.find(Settings.quality))
	_render.selected = _nearest(Settings.RENDER_SCALES, Settings.render_scale)
	_fov.value = Settings.fov
	_look.value = Settings.look_sensitivity
	_invert.button_pressed = Settings.invert_y
	for bus: String in _volumes:
		_volumes[bus].value = Settings.volumes.get(bus, 1.0)
	_refreshing = false


static func _nearest(values: Array[float], v: float) -> int:
	var best := 0
	for i: int in values.size():
		if absf(values[i] - v) < absf(values[best] - v):
			best = i
	return best
