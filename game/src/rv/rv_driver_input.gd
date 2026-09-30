class_name RVDriverInput
extends Node
## Local player's controls for the RV they are driving (actions from the `Controls`
## autoload). Holding the clutch turns mouse movement into moving the H-pattern stick, and a
## controller's right stick into flicks on its gate.

## Emitted when the player asks to be put back on the wheels (until there's a tow truck).
signal reset_requested

## How far the right stick must go to flick the gear stick.
const PAD_FLICK := 0.6

## Stick units per pixel of mouse movement.
@export var stick_sensitivity := 0.006

var rv: RV
var enabled := true

var _flick := Vector2i.ZERO


func _physics_process(_dt: float) -> void:
	if rv == null or not enabled:
		return
	rv.throttle = Input.get_action_strength(&"rv_throttle")
	rv.brake = Input.get_action_strength(&"rv_brake")
	rv.steer_input = Input.get_axis(&"rv_steer_left", &"rv_steer_right")
	rv.clutch_input = Input.get_action_strength(&"rv_clutch")
	rv.handbrake = Input.is_action_pressed(&"rv_handbrake")
	rv.horn = Input.is_action_pressed(&"rv_horn")
	_pad_gate()


func _unhandled_input(event: InputEvent) -> void:
	if rv == null or not enabled:
		return
	var motion := event as InputEventMouseMotion
	if motion and holding_stick():
		# Screen up is towards the top row of the gate.
		rv.drag_gear_stick(Vector2(motion.relative.x, -motion.relative.y) * stick_sensitivity)
		get_viewport().set_input_as_handled()
		return
	if event.is_echo():
		return
	if event.is_action_pressed(&"rv_shift_up"):
		rv.shift_by(1)
	elif event.is_action_pressed(&"rv_shift_down"):
		rv.shift_by(-1)
	elif event.is_action_pressed(&"rv_gear_reverse"):
		rv.select_gear(-1)
	elif event.is_action_pressed(&"rv_ignition"):
		rv.start_engine()
	elif event.is_action_pressed(&"rv_headlights"):
		rv.headlights = not rv.headlights
	elif event.is_action_pressed(&"rv_toggle_gearbox"):
		rv.set_automatic(not rv.is_automatic())
	elif event.is_action_pressed(&"rv_reset"):
		reset_requested.emit()
	else:
		for g: int in range(1, 6):
			if event.is_action_pressed(StringName("rv_gear_%d" % g)):
				rv.select_gear(g)
				break


## True while mouse movement drives the gear stick instead of the camera.
func holding_stick() -> bool:
	return enabled and rv != null and not rv.is_automatic() \
		and Input.is_action_pressed(&"rv_clutch") \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## True while a controller's right stick works the gear stick instead of the camera: a manual
## gearbox with the clutch held.
func pad_on_gate() -> bool:
	return enabled and rv != null and not rv.is_automatic() and Input.is_action_pressed(&"rv_clutch")


## The right stick, clutch held: each flick moves the stick one step on the gate (up and down
## between the neutral lane and the gears, sideways along it). Going sideways from a gear keeps
## the row, so 1 to 3 to 5 is two flicks right and 2 to 4 to R the same on the bottom.
func _pad_gate() -> void:
	var flick := Vector2i.ZERO
	if pad_on_gate():
		var pad := Input.get_vector(&"camera_look_left", &"camera_look_right", &"camera_look_up", &"camera_look_down")
		if absf(pad.x) >= PAD_FLICK and absf(pad.x) >= absf(pad.y):
			flick.x = 1 if pad.x > 0.0 else -1
		elif absf(pad.y) >= PAD_FLICK:
			flick.y = -1 if pad.y > 0.0 else 1 # Stick up is the top row.
	if flick != Vector2i.ZERO and flick != _flick:
		var p := rv.gear_stick.position
		var column := clampi(roundi(p.x), -1, 1)
		var row := 0 if absf(p.y) <= RVGearStick.LANE else (1 if p.y > 0.0 else -1)
		if flick.x != 0:
			column += flick.x
		else:
			row += flick.y
		rv.place_gear_stick(column, row)
	_flick = flick
