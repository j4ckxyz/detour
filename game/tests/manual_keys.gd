extends Node
## Headless manual-gearbox test through the real keyboard (key events into the driver's
## input, not the RV's inputs set directly): from the driver's seat, clutch (Q), 1st, let the
## clutch out and it creeps off without stalling; throttle pulls away; E/Z shift up to 5th and
## back; 1 without Q works too (the clutch dips for you); a stall restarts with Q + I.
##
##   godot --headless --path game --fixed-fps 60 res://tests/manual_keys.tscn

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

	# Q, 1, let Q go: it creeps off at idle, no gas, no stall.
	_key(KEY_Q, true)
	await _frames(20)
	await _tap(KEY_1)
	_check(d.gear == 1, "1st with the clutch down")
	_key(KEY_Q, false)
	await _frames(HZ * 2)
	_check(d.running and _rv.forward_speed() > 0.5, "letting the clutch out creeps off without stalling (%.2f m/s, %.0f rpm)" % [_rv.forward_speed(), d.rpm])
	_check(not _rv.parking_brake, "and the parking brake came off")

	# Gas, then up through the gears with E.
	_key(KEY_W, true)
	for g: int in range(2, 6):
		await _frames(HZ * 2)
		await _tap(KEY_E)
		await _frames(HZ / 2)
		_check(d.gear == g and d.running, "E shifts up to %d (%.1f m/s)" % [g, _rv.forward_speed()])
	_key(KEY_W, false)
	_key(KEY_Q, true) # Clutch down to slow, or 5th would lug and stall.
	_key(KEY_S, true)
	await _frames(HZ)
	_key(KEY_S, false)
	for g: int in [4, 3]:
		await _tap(KEY_Z)
		await _frames(HZ / 3)
		_check(d.gear == g, "Z shifts down to %d" % g)
	_check(d.running, "still running")

	# Stop (clutch down, so it doesn't stall), neutral, then 1 straight from the key (no Q):
	# the clutch dips itself.
	_key(KEY_Q, true)
	_key(KEY_S, true)
	await _frames(HZ * 4)
	_key(KEY_S, false)
	_check(d.running and absf(_rv.forward_speed()) < 0.3, "braked to a stop with the clutch down, still running")
	_rv.select_gear(0)
	_key(KEY_Q, false)
	await _frames(HZ / 2)
	await _tap(KEY_1)
	await _frames(HZ * 2)
	_check(d.gear == 1 and d.running and _rv.forward_speed() > 0.3, "1 without Q puts it in gear and it goes (%.2f m/s)" % _rv.forward_speed())

	# A stall (out against the brakes) restarts with Q + I.
	_key(KEY_S, true)
	_key(KEY_Q, true)
	await _frames(HZ)
	_key(KEY_Q, false)
	await _frames(HZ * 2)
	_check(not d.running, "letting the clutch out against the brakes stalls it")
	_key(KEY_S, false)
	_key(KEY_Q, true)
	await _frames(10)
	await _tap(KEY_I)
	await _frames(HZ)
	_check(d.running, "Q + I restarts it")
	_key(KEY_Q, false)
	await _frames(HZ * 2)
	_check(d.running, "and it keeps running")
	_finish()


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(2)
	_key(code, false)
	await _frames(2)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	for k: Key in [KEY_W, KEY_S, KEY_Q]:
		_key(k, false)
	if _failures.is_empty():
		print("manual keys: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
