class_name RVCamera
extends Camera3D
## Follows the RV: a chase view that trails behind and can be orbited, or the driver's eyes
## in the cab. Click to capture the mouse (the Esc menu releases it), C (camera_toggle) to
## switch.

enum Mode { CHASE, COCKPIT }

@export var chase_distance := 12.5
@export var chase_height := 3.2
@export var sensitivity := 0.0025
@export var pad_look_speed := 2.5

var rv: RV
var driver_input: RVDriverInput
var mode := Mode.CHASE

var _look_yaw := 0.0 # Relative to the RV's heading.
var _look_pitch := -0.12
var _chase_yaw := 0.0 # Smoothed heading the chase view trails.
var _has_chase_yaw := false


func _ready() -> void:
	# Placed every frame from the RV's interpolated transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event.is_action_pressed(&"camera_toggle") and not event.is_echo():
		mode = Mode.COCKPIT if mode == Mode.CHASE else Mode.CHASE
		_look_yaw = 0.0
		_look_pitch = -0.05 if mode == Mode.COCKPIT else -0.12
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not (driver_input and driver_input.holding_stick()):
		_look(-motion.relative.x * sensitivity, -motion.relative.y * sensitivity)


func _look(yaw: float, pitch: float) -> void:
	if mode == Mode.COCKPIT:
		_look_yaw = clampf(_look_yaw + yaw, -2.2, 2.2)
		_look_pitch = clampf(_look_pitch + pitch, -1.1, 0.9)
	else:
		_look_yaw = wrapf(_look_yaw + yaw, -PI, PI)
		_look_pitch = clampf(_look_pitch + pitch, -1.2, 0.35)


func _process(delta: float) -> void:
	if rv == null:
		return
	var pad := Input.get_vector(&"camera_look_left", &"camera_look_right", &"camera_look_up", &"camera_look_down")
	if pad != Vector2.ZERO:
		_look(-pad.x * pad_look_speed * delta, -pad.y * pad_look_speed * delta)
	var body := rv.get_global_transform_interpolated()
	if mode == Mode.COCKPIT:
		var eye := body * rv.driver_eye
		global_transform = Transform3D(eye.basis * Basis.from_euler(Vector3(_look_pitch, _look_yaw, 0.0)), eye.origin)
		near = 0.05
		return
	near = 0.1
	_update_chase(body, delta)


func _update_chase(body: Transform3D, delta: float) -> void:
	# Trail the RV's heading (flattened), lagging a little so turns read.
	var forward := -body.basis.z
	var heading := atan2(-forward.x, -forward.z)
	if not _has_chase_yaw:
		_chase_yaw = heading
		_has_chase_yaw = true
	_chase_yaw = lerp_angle(_chase_yaw, heading, 1.0 - exp(-3.0 * delta))
	var yaw := _chase_yaw + _look_yaw
	var pivot := body.origin + Vector3.UP * 2.4
	var dir := Basis.from_euler(Vector3(_look_pitch, yaw, 0.0)) * Vector3.BACK
	var wanted := pivot + dir * chase_distance + Vector3.UP * (chase_height - 2.4)
	# Pull in if terrain or a rock is between the RV and the camera.
	var query := PhysicsRayQueryParameters3D.create(pivot, wanted, TerrainStreamer.WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		wanted = pivot.lerp(hit["position"], 0.9)
	global_position = wanted
	look_at(pivot, Vector3.UP)


## Points the view: yaw relative to the RV's heading, pitch up/down (radians).
func set_look(yaw: float, pitch: float) -> void:
	_look_yaw = 0.0
	_look_pitch = 0.0
	_look(yaw, pitch)


## Snaps the chase view behind the RV (after a teleport).
func snap() -> void:
	_has_chase_yaw = false
