class_name RVDrivetrain
extends RefCounted
## Engine, clutch and 5-speed gearbox of the RV (PLAN.md §4.2). Pure logic: `RV` feeds it the
## driven wheels' speed and applies the torque it returns.
##
## The clutch couples the engine's flywheel to the gearbox. It transmits up to its capacity
## (scaled by how far the pedal is released) and otherwise slips, so dumping it at low rpm
## drags the engine below its stall speed, and slipping it with some throttle pulls away.

signal stalled
signal started
signal gear_changed(gear: int)

const IDLE_RPM := 750.0
const REDLINE_RPM := 3800.0
const STALL_RPM := 380.0
const CRANK_RPM := 220.0
const CRANK_SECONDS := 0.7
## Gear → ratio. -1 is reverse, 0 neutral.
const RATIOS: Dictionary[int, float] = {-1: -4.6, 0: 0.0, 1: 5.2, 2: 3.0, 3: 1.8, 4: 1.25, 5: 1.0}
const FINAL_DRIVE := 4.56
const EFFICIENCY := 0.88
## Flywheel + crank, kg·m².
const ENGINE_INERTIA := 0.9
## Most torque the clutch can pass when fully released, N·m at the flywheel.
const CLUTCH_CAPACITY := 1400.0
## Seconds for the pedal to travel fully (pressing is quicker than releasing).
const PEDAL_PRESS_TIME := 0.12
const PEDAL_RELEASE_TIME := 0.55
## Automatic gearbox: shift points in rpm (upshift rises with throttle).
const AUTO_UPSHIFT_MIN := 2100.0
const AUTO_UPSHIFT_MAX := 3400.0
const AUTO_DOWNSHIFT := 1250.0
const AUTO_SHIFT_SECONDS := 0.3
## Automatic: least time between shifts, so it doesn't hunt.
const AUTO_SHIFT_HOLD := 1.2

## (rpm, full-throttle torque N·m): an old big-block V8, torquey and lazy.
const TORQUE_CURVE: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(600.0, 300.0), Vector2(1500.0, 460.0), Vector2(2400.0, 520.0),
	Vector2(3200.0, 480.0), Vector2(3800.0, 400.0), Vector2(4200.0, 250.0),
]

var automatic := false
var running := true
var rpm := IDLE_RPM
var gear := 0
## 0 = pedal up (engaged), 1 = pedal down (disengaged). Smoothed from the input.
var clutch_pedal := 0.0
## Torque last sent to the driven axle, N·m (after gearing).
var axle_torque := 0.0
## The last shift that was refused (manual, clutch not pressed), for UI feedback.
var grinding := 0.0

var _crank_timer := -1.0
var _auto_shift_timer := 0.0
var _since_auto_shift := 10.0


func ratio(g: int = gear) -> float:
	return RATIOS[g] * FINAL_DRIVE


func max_torque(at_rpm: float) -> float:
	for i: int in range(1, TORQUE_CURVE.size()):
		var b := TORQUE_CURVE[i]
		if at_rpm <= b.x:
			var a := TORQUE_CURVE[i - 1]
			return lerpf(a.y, b.y, (at_rpm - a.x) / (b.x - a.x))
	return TORQUE_CURVE[-1].y


## Pumping losses + friction: what slows the engine (and the RV, through the clutch) when
## the throttle is closed.
func friction_torque(at_rpm: float) -> float:
	return 25.0 + at_rpm * 0.028


## How much the clutch is holding, 0..1.
func engagement() -> float:
	if gear == 0:
		return 0.0
	var e := 1.0 - clutch_pedal
	return e * e * (3.0 - 2.0 * e) # Bite point in the middle of the travel.


func can_shift() -> bool:
	return automatic or clutch_pedal > 0.8


## Selects a gear. Manual: refused (with a grind) unless the clutch is pressed.
func shift_to(new_gear: int) -> bool:
	new_gear = clampi(new_gear, -1, 5)
	if new_gear == gear:
		return true
	if not can_shift():
		grinding = 0.4
		return false
	gear = new_gear
	gear_changed.emit(gear)
	return true


func crank() -> void:
	if running or _crank_timer >= 0.0:
		return
	_crank_timer = 0.0


func is_cranking() -> bool:
	return _crank_timer >= 0.0


## Advances the drivetrain by `dt`.
## `wheel_omega`: driven wheels' angular speed from the ground (rad/s, + = forward).
## `clutch_input`: the pedal the player holds (ignored by the automatic).
## Returns the torque at the driven axle (N·m, + = forward).
func step(dt: float, throttle: float, clutch_input: float, wheel_omega: float) -> float:
	grinding = maxf(0.0, grinding - dt)
	if automatic:
		_auto_gearbox(dt, throttle, wheel_omega)
	else:
		var rate := 1.0 / (PEDAL_PRESS_TIME if clutch_input > clutch_pedal else PEDAL_RELEASE_TIME)
		clutch_pedal = move_toward(clutch_pedal, clampf(clutch_input, 0.0, 1.0), rate * dt)

	var omega := rpm * TAU / 60.0
	var engine_torque := -friction_torque(rpm) if rpm > 1.0 else 0.0
	if running:
		# Idle governor opens the throttle a little when the engine sags below idle.
		var governor := clampf((IDLE_RPM - rpm) / 250.0, 0.0, 1.0) * 0.4
		var open := maxf(throttle, governor)
		if rpm > REDLINE_RPM or _auto_shift_timer > 0.0:
			open = governor # Rev limiter; the automatic also backs off while it shifts.
		engine_torque = max_torque(rpm) * open - friction_torque(rpm) * (1.0 - open)
	elif _crank_timer >= 0.0:
		_crank_timer += dt
		engine_torque = (CRANK_RPM - rpm) * 2.0 # Starter motor.

	var free_omega := omega + engine_torque / ENGINE_INERTIA * dt
	var clutch_torque := 0.0
	var e := engagement()
	if e > 0.0:
		# Torque that would lock the flywheel to the gearbox this step, limited by what the
		# clutch can hold. Seen through the gearing the RV outweighs the flywheel (≈1.6 kg·m²
		# in 1st, 40+ in 5th), so treating its speed as fixed within a step stays stable.
		var gearbox_omega := wheel_omega * ratio()
		var lock := (free_omega - gearbox_omega) * ENGINE_INERTIA / dt
		var capacity := e * CLUTCH_CAPACITY
		clutch_torque = clampf(lock, -capacity, capacity)
	omega = maxf(0.0, free_omega - clutch_torque / ENGINE_INERTIA * dt)
	rpm = omega * 60.0 / TAU

	if _crank_timer >= CRANK_SECONDS:
		_crank_timer = -1.0
		if e < 0.3:
			running = true
			rpm = maxf(rpm, IDLE_RPM)
			started.emit()
	elif running and rpm < STALL_RPM:
		running = false
		stalled.emit()

	axle_torque = clutch_torque * ratio() * EFFICIENCY
	return axle_torque


func _auto_gearbox(dt: float, throttle: float, wheel_omega: float) -> void:
	# A centrifugal-style clutch: engages as the engine revs, so it never stalls.
	var target_pedal := 1.0 - smoothstep(900.0, 1500.0, rpm) if running else 1.0
	_auto_shift_timer = maxf(0.0, _auto_shift_timer - dt)
	_since_auto_shift += dt
	if _auto_shift_timer > 0.0:
		target_pedal = 1.0 # Mid-shift.
	# Opens instantly (like a torque converter, it can't let the engine stall), closes gently.
	if target_pedal > clutch_pedal:
		clutch_pedal = target_pedal
	else:
		clutch_pedal = move_toward(clutch_pedal, target_pedal, dt / PEDAL_PRESS_TIME)
	if gear <= 0 or _since_auto_shift < AUTO_SHIFT_HOLD:
		return
	var up_at := lerpf(AUTO_UPSHIFT_MIN, AUTO_UPSHIFT_MAX, throttle)
	if gear < 5 and _geared_rpm(wheel_omega, gear) > up_at:
		_auto_shift(gear + 1)
	elif gear > 1 and _geared_rpm(wheel_omega, gear) < AUTO_DOWNSHIFT \
			and _geared_rpm(wheel_omega, gear - 1) < up_at * 0.85:
		_auto_shift(gear - 1)


func _geared_rpm(wheel_omega: float, g: int) -> float:
	return absf(wheel_omega * ratio(g)) * 60.0 / TAU


func _auto_shift(new_gear: int) -> void:
	gear = new_gear
	_auto_shift_timer = AUTO_SHIFT_SECONDS
	_since_auto_shift = 0.0
	gear_changed.emit(gear)
