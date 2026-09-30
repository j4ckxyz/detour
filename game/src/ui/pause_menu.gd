class_name PauseMenu
extends CanvasLayer
## Esc (or Start) menu: resume, settings, update, auto-update toggle, quit. Pauses the game
## while open.
## Also shows a short notice when an automatic update has been installed.

const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.6)
const NOTICE_SECONDS := 10.0

var _backdrop := ColorRect.new()
var _panel := PanelContainer.new()
var _resume := Button.new()
var _settings := Button.new()
var _achievements := Button.new()
var _update := Button.new()
var _auto := CheckBox.new()
var _quit := Button.new()
var _status := Label.new()
var _bar := ProgressBar.new()
var _notice := PanelContainer.new()
var _notice_label := Label.new()
var _mouse_before := Input.MOUSE_MODE_VISIBLE
var _extras := VBoxContainer.new() # Built early: add_action() may run before _ready.
## Optional `func()` run just before Quit to desktop (the game saves).
var before_quit: Callable


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_backdrop.visible = false
	_panel.visible = false
	_notice.visible = false
	Updater.changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(_backdrop)

	_panel.add_theme_stylebox_override("panel", _style(18))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(380, 0)
	root.add_child(_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", TEXT)
	box.add_child(title)
	var version := Label.new()
	version.text = "Detour %s" % BuildInfo.describe()
	version.add_theme_color_override("font_color", DIM)
	box.add_child(version)

	for b: Button in [_resume, _settings, _achievements, _update, _quit]:
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 17)
	_resume.text = "Resume"
	_resume.pressed.connect(close)
	box.add_child(_resume)
	_settings.text = "Settings"
	_settings.pressed.connect(open_settings)
	box.add_child(_settings)
	_achievements.text = "Achievements"
	_achievements.pressed.connect(open_achievements)
	box.add_child(_achievements)
	_update.pressed.connect(Updater.press)
	box.add_child(_update)
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	box.add_child(_bar)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", DIM)
	box.add_child(_status)
	_auto.text = "Update automatically"
	_auto.button_pressed = Updater.auto_update
	_auto.toggled.connect(func(on: bool) -> void: Updater.auto_update = on)
	box.add_child(_auto)
	_extras.add_theme_constant_override("separation", 10)
	box.add_child(_extras)
	_quit.text = "Quit to desktop"
	_quit.pressed.connect(func() -> void:
		if before_quit.is_valid():
			before_quit.call()
		get_tree().quit())
	box.add_child(_quit)

	_notice.add_theme_stylebox_override("panel", _style(10))
	_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	_notice.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notice_label.add_theme_color_override("font_color", TEXT)
	_notice.add_child(_notice_label)
	root.add_child(_notice)


## Adds a button (above Quit) that closes the menu and runs `action`.
func add_action(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.add_theme_font_size_override("font_size", 17)
	b.pressed.connect(func() -> void:
		close()
		action.call())
	_extras.add_child(b)


static func _style(margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.9)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(margin)
	return style


## The settings screen, over this menu; back to it after.
func open_settings() -> void:
	var settings := SettingsMenu.new()
	settings.closed.connect(func() -> void:
		if is_open():
			_settings.grab_focus())
	add_child(settings)


## The achievements list, over this menu; back to it after.
func open_achievements() -> void:
	var list := AchievementsMenu.new()
	list.closed.connect(func() -> void:
		if is_open():
			_achievements.grab_focus())
	add_child(list)


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	if is_open():
		return
	_mouse_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_backdrop.visible = true
	_panel.visible = true
	get_tree().paused = not Session.is_online() # The others keep playing.
	_resume.grab_focus()
	_refresh()


func close() -> void:
	if not is_open():
		return
	_panel.visible = false
	_backdrop.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_before


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_menu") and not event.is_echo():
		if is_open():
			close()
		else:
			open()
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	_update.text = Updater.button_text()
	_update.disabled = not Updater.can_press()
	_update.visible = Updater.state != Updater.State.DISABLED
	_auto.visible = _update.visible
	_bar.visible = Updater.progress >= 0.0
	_bar.value = maxf(Updater.progress, 0.0)
	_status.text = Updater.status
	_status.visible = Updater.status != ""
	if Updater.state == Updater.State.READY and Updater.was_automatic and not is_open():
		_show_notice("Detour %s is installed. Restart from the menu (Esc) to play it." % Updater.new_version)


func _show_notice(text: String) -> void:
	if _notice.visible and _notice_label.text == text:
		return
	_notice_label.text = text
	_notice.visible = true
	get_tree().create_timer(NOTICE_SECONDS, true).timeout.connect(func() -> void: _notice.visible = false)
