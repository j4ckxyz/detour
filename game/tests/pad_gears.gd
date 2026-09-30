extends Node
## Headless controller H-pattern test: with the clutch held (X), the right stick flicks the gear
## stick about its gate instead of turning the camera (up/down between the neutral lane and the
## gears, sideways along it, keeping the row); a held stick doesn't repeat; without the clutch it
## looks around as before; a dead clutch refuses (the gearbox grinds).
##
##   godot --headless --path game --fixed-fps 60 res://tests/pad_gears.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _rv: RV
var _failures: PackedStringArray = []


func _ready() -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	while not _pg.is_spawned:
		await get_tree().physics_frame
	_rv = _pg.rv
	await _frames(HZ)
	_pg.player.take_wheel()
	_rv.set_automatic(false)
	await _frames(HZ / 2)
	var d := _rv.drivetrain
	_check(_pg.driver.enabled and d.running and not d.automatic, "in the driver's seat, manual, engine running")

	# Not clutched: the right stick looks round the cab and leaves the gears alone.
	var yaw := _pg.camera._look_yaw
	await _stick(Vector2(1.0, 0.0), 20)
	_check(d.gear == 0 and not _pg.driver.pad_on_gate(), "without the clutch the stick isn't on the gate")
	_check(absf(_pg.camera._look_yaw - yaw) > 0.05, "and it looks round (yaw %.2f → %.2f)" % [yaw, _pg.camera._look_yaw])

	await _stick(Vector2.ZERO, 5)

	# Clutch down: flicks work the gate.
	_button(JOY_BUTTON_X, true)
	await _frames(20)
	_check(_pg.driver.pad_on_gate() and d.clutch_pedal > 0.8, "clutch held: the stick is on the gate (pedal %.2f)" % d.clutch_pedal)
	yaw = _pg.camera._look_yaw
	await _flick(Vector2(0.0, -1.0))
	_check(d.gear == 3, "up from neutral: 3rd (gear %d)" % d.gear)
	await _flick(Vector2(-1.0, 0.0))
	_check(d.gear == 1, "left along the top row: 1st (gear %d)" % d.gear)
	await _flick(Vector2(0.0, 1.0))
	_check(d.gear == 0, "down from 1st: neutral (gear %d)" % d.gear)
	await _flick(Vector2(0.0, 1.0))
	_check(d.gear == 2, "down again: 2nd (gear %d)" % d.gear)
	await _flick(Vector2(1.0, 0.0))
	_check(d.gear == 4, "right along the bottom row: 4th (gear %d)" % d.gear)
	await _flick(Vector2(1.0, 0.0))
	_check(d.gear == -1, "right again: reverse (gear %d)" % d.gear)
	await _flick(Vector2(1.0, 0.0))
	_check(d.gear == -1, "the gate's edge stops it (gear %d)" % d.gear)
	await _flick(Vector2(0.0, -1.0))
	_check(d.gear == 0, "up from reverse: neutral (gear %d)" % d.gear)
	await _flick(Vector2(0.0, -1.0))
	_check(d.gear == 5, "up again: 5th (gear %d)" % d.gear)
	await _flick(Vector2(-1.0, 0.0))
	_check(d.gear == 3, "left along the top row: 3rd (gear %d)" % d.gear)
	_check(is_equal_approx(_pg.camera._look_yaw, yaw), "the camera stayed put while shifting (yaw %.2f)" % _pg.camera._look_yaw)

	# A held stick is one flick, and a gentle push isn't one.
	await _stick(Vector2(0.0, 1.0), HZ)
	_check(d.gear == 0, "holding it down is one step: neutral, not 2nd (gear %d)" % d.gear)
	await _stick(Vector2(0.0, 0.0), 10)
	await _stick(Vector2(0.0, -0.4), 10)
	_check(d.gear == 0, "a gentle push does nothing (gear %d)" % d.gear)
	await _stick(Vector2(0.0, 0.0), 10)
	_check(_rv.gear_stick.position == Vector2(0.0, 0.0) or _rv.gear_stick.position.y == 0.0, "the diagram's stick is in the lane")

	# Diagonals go to the stronger direction.
	await _flick(Vector2(-0.7, -0.9))
	_check(d.gear == 1 or d.gear == 3, "a diagonal takes its stronger direction (gear %d)" % d.gear)
	await _flick(Vector2(0.0, 1.0))

	# Clutch up: a flick is just looking again, and the gear stays.
	_button(JOY_BUTTON_X, false)
	await _frames(20)
	var kept := d.gear
	await _stick(Vector2(0.0, -1.0), 20)
	_check(d.gear == kept and not _pg.driver.pad_on_gate(), "clutch up: the stick's the camera again, the gear stays (%d)" % d.gear)
	await _stick(Vector2(0.0, 0.0), 5)

	# Automatic: no gate.
	_rv.set_automatic(true)
	_button(JOY_BUTTON_X, true)
	await _frames(20)
	_check(not _pg.driver.pad_on_gate(), "in an automatic there's no gate")
	_button(JOY_BUTTON_X, false)
	_finish()


## Holds the right stick at `v` for `frames`.
func _stick(v: Vector2, frames: int) -> void:
	for pair: Array in [[JOY_AXIS_RIGHT_X, v.x], [JOY_AXIS_RIGHT_Y, v.y]]:
		var e := InputEventJoypadMotion.new()
		e.axis = pair[0]
		e.axis_value = pair[1]
		Input.parse_input_event(e)
	await _frames(frames)


## Push the stick over, then let go.
func _flick(v: Vector2) -> void:
	await _stick(v, 6)
	await _stick(Vector2.ZERO, 6)


func _button(index: JoyButton, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	e.pressed = down
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("pad gears: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
