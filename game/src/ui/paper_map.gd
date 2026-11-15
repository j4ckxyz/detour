class_name PaperMap
extends Control
## The paper map, held up to read (the "Paper map" item, Use to unfold it): the road from camp
## to home as the route generator laid it out (`Trip.data`), its gas stations, lakes, caves and
## places off the road, and a pencil cross at each known trouble spot. No "you are here": you
## work that out from the stations and the land, as on a real map.

const PAPER := Color(0.93, 0.88, 0.74)
const INK := Color(0.2, 0.17, 0.14)
const ROAD := Color(0.55, 0.18, 0.12)
const WATER := Color(0.35, 0.55, 0.75, 0.75)
const PENCIL := Color(0.3, 0.3, 0.32, 0.8)
const MARGIN := 0.08

var player: Player
var trip: Trip

## The route in map space (0..1 both ways, north up), kept for tests.
var road: PackedVector2Array = []
## [{kind: &"camp"|&"station"|&"home", at: Vector2, label: String}]
var stops: Array[Dictionary] = []
var _lakes: Array[Array] = [] # [centre, radius] in map space
var _marks: PackedVector2Array = []
var _places: PackedVector2Array = []
var _built := false
var _min := Vector2.ZERO
var _scale := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_dt: float) -> void:
	var reading := player != null and player.reading_map
	if reading and (player.held == null or player.held.kind != &"map" or player.downed):
		player.reading_map = false # Put away, dropped, or knocked down.
		reading = false
	if reading and not _built:
		build()
	if visible != reading:
		visible = reading
		queue_redraw()


## Lays the trip out on paper (once: the route doesn't change).
func build() -> void:
	_built = true
	road.clear()
	stops.clear()
	_lakes.clear()
	_marks.clear()
	_places.clear()
	if trip == null or not trip.data.has("points"):
		return
	var pts: PackedVector3Array = trip.data["points"]
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p: Vector3 in pts:
		lo = lo.min(Vector2(p.x, p.z))
		hi = hi.max(Vector2(p.x, p.z))
	var span := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 1.0)
	_scale = 1.0 / span
	_min = (lo + hi) * 0.5 - Vector2.ONE * span * 0.5
	for p: Vector3 in pts:
		road.append(to_map(p))
	var n := 0
	for pad: Dictionary in trip.pads():
		var kind: StringName = [&"camp", &"station", &"home"][clampi(int(pad["kind"]), 0, 2)]
		var label := "Camp" if kind == &"camp" else ("Home" if kind == &"home" else "Gas %d" % (n + 1))
		if kind == &"station":
			n += 1
		stops.append({"kind": kind, "at": to_map(pad["pos"]), "label": label})
	for l: Dictionary in trip.data.get("lakes", []):
		_lakes.append([to_map(l["pos"]), float(l["radius"]) * _scale])
	for o: Dictionary in trip.data.get("obstacles", []):
		_marks.append(to_map(o["pos"]))
	for key: String in ["pois", "caves"]:
		for e: Dictionary in trip.data.get(key, []):
			_places.append(to_map(e["pos"]))


## World position → map space (0..1, north up).
func to_map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _min) * _scale


func _draw() -> void:
	var side := minf(size.x, size.y) * 0.86
	var sheet := Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	draw_rect(sheet, PAPER)
	draw_rect(sheet, INK, false, 2.0)
	# Folds.
	for f: float in [1.0 / 3.0, 2.0 / 3.0]:
		draw_line(sheet.position + Vector2(side * f, 0), sheet.position + Vector2(side * f, side), Color(0, 0, 0, 0.08), 2.0)
		draw_line(sheet.position + Vector2(0, side * f), sheet.position + Vector2(side, side * f), Color(0, 0, 0, 0.08), 2.0)
	var inner := side * (1.0 - MARGIN * 2.0)
	var at := func(m: Vector2) -> Vector2: return sheet.position + Vector2.ONE * side * MARGIN + m * inner
	var font := get_theme_default_font()
	for l: Array in _lakes:
		draw_circle(at.call(l[0]), maxf(float(l[1]) * inner, 3.0), WATER)
	if road.size() >= 2:
		var line := PackedVector2Array()
		for m: Vector2 in road:
			line.append(at.call(m))
		draw_polyline(line, ROAD, maxf(side * 0.006, 2.0), true)
	for m: Vector2 in _places:
		draw_rect(Rect2(at.call(m) - Vector2(3, 3), Vector2(6, 6)), INK, false, 1.5)
	for m: Vector2 in _marks:
		var c: Vector2 = at.call(m)
		draw_line(c - Vector2(5, 5), c + Vector2(5, 5), PENCIL, 2.0)
		draw_line(c - Vector2(5, -5), c + Vector2(5, -5), PENCIL, 2.0)
	for s: Dictionary in stops:
		var c: Vector2 = at.call(s["at"])
		draw_circle(c, 7.0, INK if s["kind"] == &"station" else ROAD)
		draw_circle(c, 4.0, PAPER)
		draw_string_outline(font, c + Vector2(10, 5), s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, PAPER)
		draw_string(font, c + Vector2(10, 5), s["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)
	# North arrow and a title.
	var n := sheet.position + Vector2(side - 36, 44)
	draw_line(n + Vector2(0, 18), n - Vector2(0, 18), INK, 2.0)
	draw_line(n - Vector2(0, 18), n - Vector2(6, 8), INK, 2.0)
	draw_line(n - Vector2(0, 18), n + Vector2(6, -8), INK, 2.0)
	draw_string(font, n + Vector2(-5, 36), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
	var title := "Trip %s" % (trip.world.get_code() if trip and trip.world else "")
	draw_string(font, sheet.position + Vector2(18, 34), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK)
