class_name StatusPanel
extends CanvasLayer
## A small panel in the top-left corner: your health, and the RV's condition as one bar made
## of its systems side by side, each in its own colour: body panels (metal), the frame, the
## engine, the wheels and tires, oil and fuel. Each takes a sixth of the bar and shrinks as it
## wears, so a short bar shows what needs seeing to, and the icons underneath say which (they
## blink when one's nearly gone). Always shown, on foot and driving.

const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.55)
const TRACK := Color(1.0, 1.0, 1.0, 0.1)
const HEALTH := Color(0.86, 0.3, 0.27)
const POISONED := Color(0.55, 0.72, 0.2)
## (name, colour) for each RV system, in bar order.
const SYSTEMS: Array[Array] = [
	["Body", Color(0.42, 0.64, 0.9)],
	["Frame", Color(0.68, 0.52, 0.86)],
	["Engine", Color(0.92, 0.55, 0.22)],
	["Wheels", Color(0.74, 0.74, 0.76)],
	["Oil", Color(0.78, 0.62, 0.18)],
	["Fuel", Color(0.35, 0.72, 0.4)],
]
## Below this a system's icon blinks.
const LOW := 0.25

var player: Player
var rv: RV

var _view := View.new()


class View:
	extends Control
	## Draws the panel.

	var panel: StatusPanel
	var _time := 0.0

	func _process(dt: float) -> void:
		_time += dt
		queue_redraw()

	func _draw() -> void:
		var p := panel
		if p.player == null or p.rv == null:
			return
		var font := ThemeDB.fallback_font
		var w := size.x
		draw_style_box(_box(), Rect2(Vector2.ZERO, size))
		var x0 := 14.0
		# The bars start after the icons and leave room at the end for a number.
		var bar_w := w - (x0 + 30.0) - 48.0
		# You.
		var y := 14.0
		_heart(Vector2(x0 + 11.0, y + 10.0), 9.0, HEALTH)
		var health := clampf(p.player.health / Player.MAX_HEALTH, 0.0, 1.0)
		var colour := POISONED if p.player.venom > 0.0 else HEALTH
		if p.player.downed:
			colour = colour.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 8.0))
		_bar(Rect2(x0 + 30.0, y + 4.0, bar_w, 12.0), [[health, colour]])
		draw_string(font, Vector2(x0 + 34.0 + bar_w, y + 15.0), "%d" % roundi(p.player.health), HORIZONTAL_ALIGNMENT_RIGHT, 34.0, 13, DIM)
		# The RV: one bar, a segment per system.
		y += 30.0
		_rv_icon(Vector2(x0 + 11.0, y + 10.0), TEXT)
		var values := p.systems()
		var segments: Array = []
		var total := 0.0
		for i: int in SYSTEMS.size():
			segments.append([values[i] / SYSTEMS.size(), SYSTEMS[i][1]])
			total += values[i] / SYSTEMS.size()
		_bar(Rect2(x0 + 30.0, y + 4.0, bar_w, 12.0), segments)
		draw_string(font, Vector2(x0 + 34.0 + bar_w, y + 15.0), "%d%%" % roundi(total * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, 34.0, 13, DIM)
		# Each system: its icon, in its colour, with a little gauge under it.
		y += 26.0
		var step := bar_w / SYSTEMS.size()
		for i: int in SYSTEMS.size():
			var c: Color = SYSTEMS[i][1]
			var v: float = values[i]
			var centre := Vector2(x0 + 30.0 + step * (i + 0.5), y + 10.0)
			var tint := c.lightened(0.25)
			if v < LOW and fmod(_time, 0.8) < 0.4:
				tint = Color(1.0, 0.35, 0.3)
			_icon(i, centre, tint)
			var g := Rect2(centre.x - step * 0.32, y + 24.0, step * 0.64, 3.0)
			draw_rect(g, TRACK)
			draw_rect(Rect2(g.position, Vector2(g.size.x * v, g.size.y)), c.lightened(0.1))

	func _box() -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.08, 0.07, 0.62)
		sb.set_corner_radius_all(10)
		return sb

	## Filled segments `[[fraction, colour], ...]` left to right over a dim track.
	func _bar(r: Rect2, segments: Array) -> void:
		draw_rect(r, TRACK)
		var x := r.position.x
		for seg: Array in segments:
			var len := r.size.x * clampf(float(seg[0]), 0.0, 1.0)
			if len > 0.5:
				draw_rect(Rect2(x, r.position.y, len, r.size.y), seg[1])
				draw_rect(Rect2(x, r.position.y, len, 2.0), (seg[1] as Color).lightened(0.3))
			x += len
		draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)

	func _heart(c: Vector2, r: float, colour: Color) -> void:
		draw_circle(c + Vector2(-r * 0.45, -r * 0.2), r * 0.55, colour)
		draw_circle(c + Vector2(r * 0.45, -r * 0.2), r * 0.55, colour)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r, -r * 0.05), c + Vector2(r, -r * 0.05), c + Vector2(0.0, r * 0.95)]), colour)

	func _rv_icon(c: Vector2, colour: Color) -> void:
		draw_rect(Rect2(c + Vector2(-10.0, -6.0), Vector2(16.0, 9.0)), colour)
		draw_rect(Rect2(c + Vector2(6.0, -2.0), Vector2(5.0, 5.0)), colour)
		draw_rect(Rect2(c + Vector2(-8.0, -4.0), Vector2(4.0, 3.0)), Color(0.1, 0.1, 0.1))
		for x: float in [-6.0, 6.0]:
			draw_circle(c + Vector2(x, 4.5), 2.6, colour)
			draw_circle(c + Vector2(x, 4.5), 1.1, Color(0.1, 0.1, 0.1))

	## One system's icon: body (a riveted panel), frame (a girder), engine (a cog), wheels (a
	## tire), oil (a drop), fuel (a jerry can).
	func _icon(i: int, c: Vector2, colour: Color) -> void:
		match i:
			0:
				draw_rect(Rect2(c + Vector2(-8.0, -6.0), Vector2(16.0, 12.0)), colour)
				for d: Vector2 in [Vector2(-5, -3), Vector2(5, -3), Vector2(-5, 3), Vector2(5, 3)]:
					draw_circle(c + d, 1.2, Color(0.1, 0.1, 0.1))
			1:
				draw_rect(Rect2(c + Vector2(-8.0, -7.0), Vector2(16.0, 3.0)), colour)
				draw_rect(Rect2(c + Vector2(-8.0, 4.0), Vector2(16.0, 3.0)), colour)
				draw_rect(Rect2(c + Vector2(-1.5, -5.0), Vector2(3.0, 10.0)), colour)
			2:
				for k: int in 8:
					var a := TAU * k / 8.0
					draw_line(c, c + Vector2(cos(a), sin(a)) * 8.5, colour, 3.0)
				draw_circle(c, 6.0, colour)
				draw_circle(c, 2.4, Color(0.1, 0.1, 0.1))
			3:
				draw_circle(c, 8.0, colour)
				draw_circle(c, 4.2, Color(0.55, 0.55, 0.58))
				draw_circle(c, 1.6, Color(0.1, 0.1, 0.1))
			4:
				draw_circle(c + Vector2(0.0, 2.5), 5.2, colour)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-4.6, 0.5), c + Vector2(4.6, 0.5), c + Vector2(0.0, -8.5)]), colour)
			_:
				draw_rect(Rect2(c + Vector2(-6.0, -5.0), Vector2(12.0, 13.0)), colour)
				draw_rect(Rect2(c + Vector2(-2.0, -8.5), Vector2(6.0, 3.5)), colour)
				draw_line(c + Vector2(-3.5, -2.0), c + Vector2(3.5, 5.0), Color(0.1, 0.1, 0.1), 1.5)
				draw_line(c + Vector2(3.5, -2.0), c + Vector2(-3.5, 5.0), Color(0.1, 0.1, 0.1), 1.5)


func _ready() -> void:
	layer = 45
	_view.panel = self
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.position = Vector2(16.0, 16.0)
	_view.size = Vector2(300.0, 104.0)
	add_child(_view)


## Each RV system's condition, 0..1, in `SYSTEMS` order.
func systems() -> Array[float]:
	var d := rv.damage
	var body := 0.0
	for part: RVDamage.Part in d.parts.values():
		body += clampf(part.hp, 0.0, RVDamage.FULL) / RVDamage.FULL if part.attached else 0.0
	body /= maxf(1.0, d.parts.size())
	var wheels := 0.0
	for i: int in 4:
		if d.wheel_on[i]:
			wheels += 0.25 * (0.5 * clampf(d.tires[i] / RVDamage.FULL, 0.0, 1.0) + 0.5 * float(d.bolts[i]) / RVDamage.BOLTS)
	return [
		body, clampf(d.frame / RVDamage.FULL, 0.0, 1.0), clampf(d.engine / RVDamage.FULL, 0.0, 1.0),
		wheels, clampf(d.oil, 0.0, 1.0), clampf(d.fuel / RVDamage.TANK, 0.0, 1.0),
	]


## The RV's overall condition, 0..1 (the length of its bar).
func overall() -> float:
	var total := 0.0
	for v: float in systems():
		total += v
	return total / SYSTEMS.size()
