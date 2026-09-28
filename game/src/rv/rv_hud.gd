class_name RVHud
extends CanvasLayer
## Developer HUD for driving until the diegetic dashboard lands: speed, rpm, gear, clutch and
## engine state, plus the H-pattern gate while the clutch is held. F1 toggles the help.

const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.45)
const WARN := Color(1.0, 0.62, 0.35)
const REDLINE := Color(0.92, 0.36, 0.25)
const HELP := """W/S  throttle / brake     A/D  steer     Space  handbrake
Q  clutch (hold + move mouse: H-pattern)     E/Z or wheel  shift up / down
1-5, R  pick a gear     T  manual / automatic     I  start engine
L  headlights     C  chase / cab camera     Backspace  back on the wheels
Click  capture mouse     Esc  menu (updates, quit)     F1  this help     F3  perf"""

var rv: RV

var _gauges := Label.new()
var _status := Label.new()
var _help := Label.new()
var _gate := GateView.new()


class GateView:
	extends Control
	## Draws the H-pattern and where the stick is.

	var stick := Vector2.ZERO
	var gear := 0

	func _draw() -> void:
		var s := size
		var cols: Array[float] = [s.x * 0.2, s.x * 0.5, s.x * 0.8]
		var top := s.y * 0.12
		var bottom := s.y * 0.88
		var mid := s.y * 0.5
		var line := Color(0.96, 0.93, 0.86, 0.5)
		draw_line(Vector2(cols[0], mid), Vector2(cols[2], mid), line, 3.0)
		for x: float in cols:
			draw_line(Vector2(x, top), Vector2(x, bottom), line, 3.0)
		var labels: Array[String] = ["1", "2", "3", "4", "5", "R"]
		for i: int in 6:
			var x := cols[i >> 1]
			var y := top - 4.0 if i % 2 == 0 else bottom + 16.0
			draw_string(ThemeDB.fallback_font, Vector2(x - 4.0, y), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, line)
		var p := Vector2(lerpf(cols[0], cols[2], (stick.x + 1.0) * 0.5), lerpf(bottom, top, (stick.y + 1.0) * 0.5))
		draw_circle(p, 8.0, Color(1.0, 0.8, 0.45) if gear != 0 else Color(0.96, 0.93, 0.86))


func _ready() -> void:
	layer = 50
	var panel := _panel()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var box := VBoxContainer.new()
	_gauges.add_theme_font_size_override("font_size", 22)
	_gauges.add_theme_color_override("font_color", TEXT)
	_status.add_theme_font_size_override("font_size", 14)
	box.add_child(_gauges)
	box.add_child(_status)
	panel.add_child(box)
	add_child(panel)

	_gate.custom_minimum_size = Vector2(150, 130)
	_gate.anchor_left = 1.0
	_gate.anchor_right = 1.0
	_gate.anchor_top = 1.0
	_gate.anchor_bottom = 1.0
	_gate.offset_left = -180.0
	_gate.offset_right = -30.0
	_gate.offset_top = -170.0
	_gate.offset_bottom = -40.0
	add_child(_gate)

	var help_panel := _panel()
	help_panel.anchor_left = 0.5
	help_panel.anchor_right = 0.5
	help_panel.offset_top = 16.0
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_help.text = HELP
	_help.add_theme_font_size_override("font_size", 14)
	_help.add_theme_color_override("font_color", TEXT)
	help_panel.add_child(_help)
	add_child(help_panel)


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_help") and not event.is_echo():
		var panel := _help.get_parent() as Control
		panel.visible = not panel.visible


func _process(_delta: float) -> void:
	if rv == null:
		return
	var d := rv.drivetrain
	var kmh := absf(rv.forward_speed()) * 3.6
	var gear := "R" if d.gear == -1 else ("N" if d.gear == 0 else str(d.gear))
	_gauges.text = "%3d km/h   %s   %4d rpm" % [roundi(kmh), gear, roundi(d.rpm)]
	_gauges.add_theme_color_override("font_color", REDLINE if d.rpm > RVDrivetrain.REDLINE_RPM - 150.0 else TEXT)

	var bits: PackedStringArray = []
	bits.append("AUTO" if d.automatic else "MANUAL")
	if not d.automatic:
		bits.append("clutch %d%%" % roundi(d.clutch_pedal * 100.0))
	if rv.handbrake:
		bits.append("HANDBRAKE")
	if rv.headlights:
		bits.append("lights")
	var warn := false
	if d.is_cranking():
		bits.append("cranking…")
	elif not d.running:
		bits.append("STALLED — hold Q (or neutral) and press I")
		warn = true
	if d.grinding > 0.0:
		bits.append("GRIND — press the clutch to shift")
		warn = true
	_status.text = "   ".join(bits)
	_status.add_theme_color_override("font_color", WARN if warn else DIM)

	_gate.visible = not d.automatic and (Input.is_action_pressed(&"rv_clutch") or d.clutch_pedal > 0.5)
	_gate.stick = rv.gear_stick.position
	_gate.gear = d.gear
	_gate.queue_redraw()
