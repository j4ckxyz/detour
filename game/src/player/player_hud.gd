class_name PlayerHud
extends CanvasLayer
## On-foot HUD: a crosshair, what you can interact with, what you're holding, and health.

const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.7)

var player: Player

var _dot := Label.new()
var _prompt := Label.new()
var _status := Label.new()


func _ready() -> void:
	layer = 40
	_dot.text = "·"
	_dot.add_theme_font_size_override("font_size", 28)
	_dot.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_dot)
	for label: Label in [_prompt, _status]:
		label.add_theme_color_override("font_color", TEXT)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		label.add_theme_constant_override("outline_size", 6)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(label)
	_prompt.add_theme_font_size_override("font_size", 18)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 28.0
	_prompt.offset_bottom = 56.0
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_status.add_theme_font_size_override("font_size", 15)
	_status.add_theme_color_override("font_color", DIM)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_status.offset_top = -44.0
	_status.offset_bottom = -16.0
	_status.grow_horizontal = Control.GROW_DIRECTION_BOTH


func _process(_delta: float) -> void:
	if player == null:
		return
	visible = not player.is_driving()
	_dot.visible = player.seat == &""
	if player.seat != &"":
		_prompt.text = "F  Get up"
	elif player.target_prompt != "":
		_prompt.text = "E  " + player.target_prompt
	else:
		_prompt.text = ""
	var bits: PackedStringArray = []
	if player.held:
		var hint := "LMB use · " if ItemLibrary.use_action(player.held.kind).is_valid() else ""
		bits.append("Holding %s  (%sRMB throw · Q drop)" % [player.held.display_name(), hint])
	bits.append("Health %d" % roundi(player.health))
	_status.text = "     ".join(bits)
