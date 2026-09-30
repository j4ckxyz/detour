class_name TapeSubtitles
extends CanvasLayer
## What Dot says over the cassette that's playing (see `Tapes`), at the bottom of the screen: the
## tape's title as it goes in, then her lines. Shown while you're in the RV or close by.

const TEXT := Color(0.98, 0.95, 0.86)
## How near the RV you must be to hear the tape (m, from the deck).
const HEARING := 16.0

var deck: RVTapeDeck
var player: Player

var _label := Label.new()


func _ready() -> void:
	layer = 45
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 19)
	_label.add_theme_color_override("font_color", TEXT)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("outline_size", 7)
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.anchor_left = 0.2
	_label.anchor_right = 0.8
	_label.offset_top = -150.0
	_label.offset_bottom = -100.0
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	add_child(_label)


func _process(_dt: float) -> void:
	if deck == null or player == null or not player.is_inside_tree() or not deck.is_inside_tree():
		return # (The player joins the trip once it's loaded.)
	var text := deck.subtitle()
	var near := player.global_position.distance_to(deck.global_position) < HEARING
	_label.visible = text != "" and near and Settings.captions
	_label.text = text
