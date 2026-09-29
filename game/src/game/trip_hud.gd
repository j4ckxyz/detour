class_name TripHud
extends CanvasLayer
## Top-of-screen trip line: the next stop and how far along the road it is, checkpoint
## notices, a brief "Saved" in the corner, and the summary at the end.

var trip: Trip
var weather: Weather

var _line := Label.new()
var _notice := Label.new()
var _saved := Label.new()


func _ready() -> void:
	layer = 45
	for label: Label in [_line, _notice]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color(0.98, 0.95, 0.86))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 7)
		label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		add_child(label)
	_line.add_theme_font_size_override("font_size", 16)
	_line.offset_top = 10.0
	_notice.add_theme_font_size_override("font_size", 24)
	_notice.offset_top = 40.0
	_saved.text = "Saved"
	_saved.add_theme_font_size_override("font_size", 14)
	_saved.add_theme_color_override("font_color", Color(0.98, 0.95, 0.86))
	_saved.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_saved.add_theme_constant_override("outline_size", 5)
	_saved.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	_saved.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(_saved)


func _process(_delta: float) -> void:
	if trip == null or trip.rv == null:
		return
	if trip.is_finished:
		_line.text = trip.summary()
	else:
		var next: Array = trip.next_stop()
		if next[0] == "":
			_line.text = ""
		elif float(next[1]) < 0.0:
			_line.text = "%s — find the road" % next[0]
		else:
			_line.text = "%s — %.1f km down the road" % [next[0], float(next[1]) / 1000.0]
	if weather:
		_line.text = "Day %d, %s · %s\n%s" % [trip.day(), trip.clock_text(), weather.describe(), _line.text]
	if Session.is_online():
		var names: PackedStringArray = []
		for peer: int in Session.players:
			names.append(Session.name_of(peer))
		var code := "   ·   room %s" % Session.room_code if Session.room_code != "" else ""
		_line.text += "\n%s%s" % [", ".join(names), code]
	_notice.visible = trip.notice_time > 0.0
	_notice.text = trip.notice
	_saved.visible = trip.saved_flash > 0.0
	_saved.modulate.a = clampf(trip.saved_flash, 0.0, 1.0)
