class_name RVGearStick
extends RefCounted
## The cab's H-pattern shifter, dragged with the mouse while the clutch is held.
##
##     1   3   5
##     |   |   |
##     +---N---+
##     |   |   |
##     2   4   R
##
## `position` is in stick units: x in [-1, 1] across the three columns, y in [-1, 1] with
## +y towards the top row. The stick slides sideways only in the neutral lane, and into a
## column only when lined up with it, so it feels like a real gate.

## Half-height of the neutral lane.
const LANE := 0.12
## How close to a column the stick must be to enter it (it snaps to the column).
const SNAP := 0.28
## How far into a column counts as "in gear".
const ENGAGE := 0.75
const COLUMNS: Array[float] = [-1.0, 0.0, 1.0]
## (column index, top row?) → gear.
const GATES: Dictionary[Vector2i, int] = {
	Vector2i(0, 1): 1, Vector2i(0, -1): 2,
	Vector2i(1, 1): 3, Vector2i(1, -1): 4,
	Vector2i(2, 1): 5, Vector2i(2, -1): -1,
}

var position := Vector2.ZERO


## The gear the stick is in (0 in the neutral lane or half-way into a gate).
func gear() -> int:
	if absf(position.y) < ENGAGE:
		return 0
	var col := _nearest_column(position.x)
	return GATES[Vector2i(col, 1 if position.y > 0.0 else -1)]


## Moves the stick by `delta`. `can_enter` false keeps it in the neutral lane (the gearbox
## refuses to go into gear without the clutch).
func drag(delta: Vector2, can_enter: bool = true) -> void:
	var p := position
	if absf(p.y) <= LANE:
		p.x = clampf(p.x + delta.x, -1.0, 1.0)
	var col := COLUMNS[_nearest_column(p.x)]
	var limit := 1.0 if can_enter else LANE
	if absf(p.x - col) <= SNAP:
		var y := clampf(p.y + delta.y, -limit, limit)
		if absf(y) > LANE:
			p.x = col
		p.y = y
	else:
		p.y = clampf(p.y + delta.y, -LANE, LANE)
	position = p


## Puts the stick in `gear`'s gate (used when shifting with keys or the automatic).
func set_gear(g: int) -> void:
	if g == 0:
		position = Vector2(clampf(position.x, -1.0, 1.0), 0.0)
		return
	for gate: Vector2i in GATES:
		if GATES[gate] == g:
			position = Vector2(COLUMNS[gate.x], float(gate.y))
			return


static func _nearest_column(x: float) -> int:
	return clampi(roundi(x + 1.0), 0, 2)
