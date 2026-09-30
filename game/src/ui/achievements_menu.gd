class_name AchievementsMenu
extends CanvasLayer
## The achievements list (from the main menu and the pause menu): how many are earned, each
## one's title, what to do and how far along it is; hidden ones read "???" until they're earned.
## Esc or Done closes it.

signal closed

const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.55)
const ACCENT := Color(0.95, 0.62, 0.25)

var _root := Control.new()
var _rows := VBoxContainer.new()
var _summary := Label.new()
var _done := Button.new()
var _reset := Button.new()


func _ready() -> void:
	layer = 115
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_refresh()
	Achievements.unlocked.connect(func(_id: StringName) -> void: _refresh())
	_done.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause_menu") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()


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
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = 24
	panel.offset_bottom = -24
	_root.add_child(panel)
	_root.resized.connect(func() -> void:
		var half := minf(330.0, _root.size.x * 0.5 - 12.0)
		panel.offset_left = -half
		panel.offset_right = half)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	outer.add_child(MainMenu._label("Achievements", 32, TEXT))
	_summary.add_theme_font_size_override("font_size", 16)
	_summary.add_theme_color_override("font_color", ACCENT)
	outer.add_child(_summary)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)
	scroll.add_child(pad)
	_rows.add_theme_constant_override("separation", 8)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	_reset.text = "Reset"
	_reset.tooltip_text = "Forget every achievement and count (press twice)"
	_reset.pressed.connect(func() -> void:
		if _reset.text != "Sure?":
			_reset.text = "Sure?"
			return
		_reset.text = "Reset"
		Achievements.reset_all()
		_refresh())
	buttons.add_child(MainMenu._button(_reset))
	_done.text = "Done"
	_done.pressed.connect(close)
	buttons.add_child(MainMenu._button(_done))
	outer.add_child(buttons)


func _refresh() -> void:
	for c: Node in _rows.get_children():
		c.queue_free()
	_summary.text = "%d of %d earned" % [Achievements.earned_count(), Achievements.LIST.size()]
	# Earned ones first, then the ones nearest to being earned.
	var order: Array[Dictionary] = Achievements.LIST.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ea := Achievements.is_earned(a["id"])
		var eb := Achievements.is_earned(b["id"])
		if ea != eb:
			return ea
		return Achievements.progress_of(a["id"]) > Achievements.progress_of(b["id"]))
	for def: Dictionary in order:
		_rows.add_child(_row(def))


func _row(def: Dictionary) -> Control:
	var id: StringName = def["id"]
	var earned := Achievements.is_earned(id)
	var hidden := bool(def.get("hidden", false)) and not earned
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title := MainMenu._label("???" if hidden else ("✓ " if earned else "") + String(def["title"]), 17, ACCENT if earned else TEXT)
	box.add_child(title)
	var desc := MainMenu._label("A hidden achievement." if hidden else String(def["desc"]), 13, DIM)
	box.add_child(desc)
	if not earned and not hidden:
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = Achievements.progress_of(id)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 6)
		box.add_child(bar)
	return box
