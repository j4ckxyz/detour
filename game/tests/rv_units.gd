extends SceneTree
## Unit tests for the RV's drivetrain and H-pattern stick (pure logic, no physics).
##   godot --headless --path game --script res://tests/rv_units.gd

const DT := 1.0 / 60.0

var _failures: PackedStringArray = []


func _initialize() -> void:
	_gear_stick()
	_manual_drivetrain()
	_automatic_drivetrain()
	if _failures.is_empty():
		print("rv units: all checks passed")
		quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _gear_stick() -> void:
	var s := RVGearStick.new()
	_check(s.gear() == 0, "stick starts in neutral")
	s.drag(Vector2(0.0, 1.0))
	_check(s.gear() == 3, "straight up from the middle is 3rd, got %d" % s.gear())
	s.drag(Vector2(-1.0, 0.0))
	_check(s.gear() == 3 and is_equal_approx(s.position.x, 0.0), "can't slide sideways out of a gate")
	s.drag(Vector2(0.0, -1.0))
	_check(s.gear() == 0 and absf(s.position.y) <= RVGearStick.LANE, "back to the neutral lane")
	s.drag(Vector2(-1.0, 0.0))
	s.drag(Vector2(0.0, -1.0))
	_check(s.gear() == 2, "left and down is 2nd, got %d" % s.gear())
	s.set_gear(0)
	s.drag(Vector2(2.0, 0.0))
	s.drag(Vector2(0.0, -1.0))
	_check(s.gear() == -1, "right and down is reverse, got %d" % s.gear())
	s.set_gear(0)
	s.position = Vector2(0.5, 0.0) # Between columns: the gate is closed.
	s.drag(Vector2(0.0, 1.0))
	_check(s.gear() == 0, "no gear between columns")
	s.set_gear(0)
	s.drag(Vector2(0.0, 1.0), false)
	_check(s.gear() == 0, "can't enter a gate when the gearbox refuses")
	for g: int in [-1, 1, 2, 3, 4, 5]:
		s.set_gear(g)
		_check(s.gear() == g, "set_gear(%d) round-trips" % g)


func _manual_drivetrain() -> void:
	var d := RVDrivetrain.new()
	_check(not d.shift_to(1) and d.gear == 0 and d.grinding > 0.0, "no shifting without the clutch")
	_run(d, 0.5, 0.0, 1.0, 0.0)
	_check(d.shift_to(1) and d.gear == 1, "shifts with the clutch pressed")
	_check(d.running and absf(d.rpm - RVDrivetrain.IDLE_RPM) < 150.0, "idles at %d rpm" % d.rpm)

	# Dump the clutch against a stopped RV: the engine can't turn the wheels and stalls.
	var stalled := [false]
	d.stalled.connect(func() -> void: stalled[0] = true)
	_run(d, 1.5, 0.0, 0.0, 0.0)
	_check(not d.running and stalled[0], "stalls when the clutch is dumped at rest")

	# Restart: the starter holds the clutch in for you, so it starts in gear with the pedal up.
	_run(d, 1.0, 0.0, 0.0, 0.0)
	d.crank()
	_check(d.is_cranking(), "cranking")
	_run(d, 0.3, 0.0, 0.0, 0.0)
	_check(d.clutch_pedal > 0.9, "the starter presses the clutch (pedal %.2f)" % d.clutch_pedal)
	while d.is_cranking():
		d.step(DT, 0.0, 0.0, 0.0)
	_check(d.running, "starts in gear without touching the clutch")
	d.anti_stall = true # As the RV sets it when the brakes are off.
	_run(d, 2.0, 0.0, 0.0, 3.5) # Creeping along at ~1.4 m/s.
	_check(d.running and d.clutch_pedal > 0.9, "the clutch stays in after the start, the engine idling (pedal %.2f)" % d.clutch_pedal)
	_run(d, 3.0, 0.3, 0.0, 3.5)
	_check(d.running and d.clutch_pedal < 0.1, "and comes out when the throttle asks for it (pedal %.2f), still running" % d.clutch_pedal)
	d.anti_stall = false
	# Pressing the clutch takes the pedal back from the starter too.
	d.running = false
	d.rpm = 0.0
	d.crank()
	while d.is_cranking():
		d.step(DT, 0.0, 0.0, 0.0)
	d.anti_stall = true
	_run(d, 0.2, 0.0, 1.0, 3.5)
	_run(d, 2.0, 0.0, 0.0, 3.5)
	_check(d.running and d.clutch_pedal < 0.1, "the driver's own clutch takes over after a start")
	d.anti_stall = false
	d.running = false
	d.rpm = 0.0
	d.gear = 5 # A tall gear from a standstill: idles quietly, doesn't stall itself.
	d.crank()
	while d.is_cranking():
		d.step(DT, 0.0, 0.0, 0.0)
	_run(d, 4.0, 0.0, 0.0, 0.0)
	_check(d.running, "starting in 5th at rest holds the engine idling (no stall)")
	d.gear = 1
	# ... and again with the RV rolling in gear: the wheels don't stop it starting.
	d.running = false
	d.rpm = 300.0
	d.crank()
	for i: int in 120:
		d.step(DT, 0.0, 0.0, 6.0)
	_check(d.running, "starts while rolling in gear")
	d.running = false
	d.rpm = 0.0
	d.crank()
	_run(d, 1.0, 0.0, 1.0, 0.0)
	_check(d.running, "starts with the clutch down")

	# Clutch slipping near the bite point with throttle: torque reaches the wheels, and the
	# engine stays alive even though they aren't turning yet.
	_run(d, 0.3, 0.6, 1.0, 0.0)
	var torque := 0.0
	for i: int in 30:
		torque = d.step(DT, 0.6, 0.8, 0.0)
	_check(d.running and torque > 2000.0, "slipping the clutch drives the wheels (%.0f N·m)" % torque)

	# Locked at speed: rpm follows the wheels through the gearing.
	var wheel_omega := 8.0 # ≈ 3.2 m/s
	_run(d, 2.0, 0.3, 0.0, wheel_omega)
	var expected := wheel_omega * d.ratio() * 60.0 / TAU
	_check(absf(d.rpm - expected) < 30.0, "rpm %.0f locked to wheels (%.0f)" % [d.rpm, expected])

	# Off the throttle, the engine brakes the RV.
	_check(d.step(DT, 0.0, 0.0, wheel_omega) < 0.0, "engine braking")
	_check(d.max_torque(2400.0) > d.max_torque(900.0), "torque curve rises to its peak")


func _automatic_drivetrain() -> void:
	var d := RVDrivetrain.new()
	d.automatic = true
	d.shift_to(1)
	_run(d, 1.0, 0.0, 0.0, 0.0)
	_check(d.running, "automatic doesn't stall at rest in gear")
	var torque := 0.0
	for i: int in 60:
		torque = d.step(DT, 1.0, 0.0, 0.0)
	_check(torque > 2000.0, "automatic pulls away (%.0f N·m)" % torque)
	_run(d, 4.0, 0.8, 0.0, 30.0) # ≈ 43 km/h; it holds each gear a moment before the next.
	_check(d.gear >= 3, "automatic upshifts at speed (gear %d)" % d.gear)
	_run(d, 3.0, 0.2, 0.0, 3.0)
	_check(d.gear <= 2, "automatic downshifts when slow (gear %d)" % d.gear)


func _run(d: RVDrivetrain, seconds: float, throttle: float, clutch: float, wheel_omega: float) -> void:
	for i: int in roundi(seconds / DT):
		d.step(DT, throttle, clutch, wheel_omega)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
