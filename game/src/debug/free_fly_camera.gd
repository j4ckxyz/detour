class_name FreeFlyCamera
extends Camera3D
## Debug camera. Hold right mouse to look; WASD to move, Q/E down/up, Shift = fast.

@export var speed := 25.0
@export var fast_multiplier := 6.0
@export var sensitivity := 0.0025
@export var min_ground_clearance := 1.8

## Optional `func(x: float, z: float) -> float` giving terrain height, to stay above ground.
var ground_height: Callable

var _yaw := 0.0
var _pitch := 0.0


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF # Moved every frame.
	_yaw = rotation.y
	_pitch = rotation.x


func look(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = clampf(pitch, -1.5, 1.5)
	rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if button.pressed else Input.MOUSE_MODE_VISIBLE
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(_yaw - motion.relative.x * sensitivity, _pitch - motion.relative.y * sensitivity)


func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= basis.z
	if Input.is_physical_key_pressed(KEY_S):
		dir += basis.z
	if Input.is_physical_key_pressed(KEY_A):
		dir -= basis.x
	if Input.is_physical_key_pressed(KEY_D):
		dir += basis.x
	if Input.is_physical_key_pressed(KEY_E):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		dir -= Vector3.UP
	if dir != Vector3.ZERO:
		var s := speed * (fast_multiplier if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		position += dir.normalized() * s * delta
	if ground_height.is_valid():
		var ground: float = ground_height.call(position.x, position.z)
		position.y = maxf(position.y, ground + min_ground_clearance)
