class_name RVDriverInput
extends Node
## Local player's controls for the RV they are driving (actions from the `Controls`
## autoload). Holding the clutch turns mouse movement into moving the H-pattern stick.

## Emitted when the player asks to be put back on the wheels (until there's a tow truck).
signal reset_requested

## Stick units per pixel of mouse movement.
@export var stick_sensitivity := 0.006

var rv: RV
var enabled := true


func _physics_process(_dt: float) -> void:
	if rv == null or not enabled:
		return
	rv.throttle = Input.get_action_strength(&"rv_throttle")
	rv.brake = Input.get_action_strength(&"rv_brake")
	rv.steer_input = Input.get_axis(&"rv_steer_left", &"rv_steer_right")
	rv.clutch_input = Input.get_action_strength(&"rv_clutch")
	rv.handbrake = Input.is_action_pressed(&"rv_handbrake")


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
