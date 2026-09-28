class_name RV
extends RigidBody3D
## The motorhome: a ~5.5 t rear-wheel-drive rigid body on four shape-cast wheels, with a
## manual 5-speed (clutch + H-pattern) or automatic gearbox (PLAN.md §4.2).
##
## Whoever drives writes the control inputs below (`RVDriverInput` for the local player;
## tests and, later, the network write them directly). The model comes from
## `assets/models/rv.glb`; its hull colliders from `rv_collision.glb`.

## Emitted when the engine stalls or starts, for UI and sound.
signal engine_stalled
signal engine_started

const MODEL_COLLISION := "res://assets/models/rv_collision.glb"
## Physics layer of vehicles.
const VEHICLE_LAYER := 2
const WHEELBASE := 4.45
const TRACK := 1.84
const WHEEL_RADIUS := 0.4
## Wheel centre sits this far below its suspension mount at ride height.
const RIDE_LENGTH := 0.2
## Total service brake force at the tires, N (~0.8 g).
const BRAKE_FORCE := 44000.0
const HANDBRAKE_FORCE := 14000.0
## Driveshaft, axle and wheels, reflected to the wheels (kg·m²). Sets how fast they spin up
## when the tires break loose (visual only: the engine stays coupled to the ground speed).
const AXLE_INERTIA := 40.0
## ½ ρ C_d A with C_d 0.65 and 7.5 m² of frontal area.
const DRAG := 2.9
const MAX_STEER := deg_to_rad(34.0)
const HIGH_SPEED_STEER := deg_to_rad(10.0)
## Steering-wheel turns from centre to full lock.
const STEERING_WHEEL_TURNS := 1.5

## Throttle 0..1.
var throttle := 0.0
## Brake 0..1.
var brake := 0.0
## Steering -1 (left) .. 1 (right).
var steer_input := 0.0
## Clutch pedal 0 (up) .. 1 (pressed).
var clutch_input := 0.0
var handbrake := false
## Holds the rear wheels like the handbrake until the driver first touches the throttle,
## so a parked RV doesn't roll off a slope.
var parking_brake := true
var headlights := false:
	set(on):
		headlights = on
		for light: SpotLight3D in _headlights:
			light.visible = on

## Height above each contact patch where tire forces act. Real tires push at the ground;
## lifting the point towards the centre of mass trades a little realism for an RV that
## only tips when the terrain helps.
@export var tire_force_height := 0.35

var drivetrain := RVDrivetrain.new()
var gear_stick := RVGearStick.new()
var wheels: Array[RVWheel] = []
## First-person camera point (the driver's eyes), in RV space.
var driver_eye := Transform3D.IDENTITY

var _steer := 0.0
var _axle_spin := 0.0 # Driven wheels' spin beyond rolling speed, rad/s (visual).
var _auto_reverse_timer := 0.0
var _assist_timer := 0.0 # Clutch held down by a key shift in manual mode.
var _pending_gear := 0
var _headlights: Array[SpotLight3D] = []
var _steering_wheel: Node3D
var _steering_rest := Transform3D.IDENTITY
var _steering_axis := Vector3.UP
var _gear_lever: Node3D
var _gear_lever_rest := Basis.IDENTITY

@onready var model: Node3D = $Model


func _ready() -> void:
	mass = 5500.0
	# A box of the RV's size and mass. Set explicitly: the hull boxes are hollow-ish and
	# would under-estimate how lazily the RV rolls and pitches.
	inertia = Vector3(28200.0, 27500.0, 5500.0)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = _local("CenterOfMass")
	angular_damp = 0.4
	can_sleep = false
	continuous_cd = true
	collision_layer = VEHICLE_LAYER
	collision_mask = TerrainStreamer.WORLD_LAYER | VEHICLE_LAYER
	var surface := PhysicsMaterial.new()
	surface.friction = 0.6
	physics_material_override = surface

	_build_hull()
	_build_wheels()
	_build_headlights()
	driver_eye = Transform3D(Basis.IDENTITY, _local("Eye_Driver"))
	_steering_wheel = _marker("SteeringWheel")
	_steering_rest = _steering_wheel.transform
	# The wheel's mesh was tilted in Blender (-65° about X); its column is that tilt of +Z,
	# converted to Godot's axes.
	_steering_axis = Vector3(0.0, sin(deg_to_rad(25.0)), -cos(deg_to_rad(25.0)))
	_gear_lever = _marker("GearStick")
	_gear_lever_rest = _gear_lever.basis

	drivetrain.stalled.connect(engine_stalled.emit)
	drivetrain.started.connect(engine_started.emit)
	drivetrain.gear_changed.connect(gear_stick.set_gear)


func _marker(node_name: String) -> Node3D:
	var node := model.find_child(node_name, true, false) as Node3D
	assert(node != null, "rv.glb has no node '%s'" % node_name)
	return node


## A marker's position in RV space.
func _local(node_name: String) -> Vector3:
	return to_local(_marker(node_name).global_position)


func _build_hull() -> void:
	var scene := load(MODEL_COLLISION) as PackedScene
	var source := scene.instantiate()
	for node: Node in source.find_children("Hull_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var aabb := mi.transform * mi.mesh.get_aabb()
		var box := BoxShape3D.new()
		box.size = aabb.size
		var shape := CollisionShape3D.new()
		shape.name = mi.name
		shape.shape = box
		shape.position = aabb.get_center()
		add_child(shape)
	source.free()


func _build_wheels() -> void:
	# (name, driven, steered, brake share). Front brakes do more of the work.
	var specs: Array[Array] = [
		["Wheel_FL", false, true, 0.3], ["Wheel_FR", false, true, 0.3],
		["Wheel_RL", true, false, 0.2], ["Wheel_RR", true, false, 0.2],
	]
	# Static load per wheel from where the centre of mass sits between the axles, so the
	# RV rides level at RIDE_LENGTH.
	var front_z := _local("Wheel_FL").z
	var rear_z := _local("Wheel_RL").z
	var front_share := (rear_z - center_of_mass.z) / (rear_z - front_z)
	var weight := mass * 9.8
	for spec: Array in specs:
		var visual := _marker(spec[0])
		var wheel := RVWheel.new()
		wheel.name = spec[0]
		wheel.driven = spec[1]
		wheel.steered = spec[2]
		wheel.has_handbrake = spec[1]
		wheel.brake_share = spec[3]
		wheel.radius = WHEEL_RADIUS
		var share := front_share if wheel.steered else 1.0 - front_share
		var corner_load := weight * share * 0.5
		var compression := wheel.travel - RIDE_LENGTH
		wheel.spring_rate = corner_load / compression
		# About 35 % of critical damping: soft and floaty, like an old motorhome.
		var critical := 2.0 * sqrt(wheel.spring_rate * corner_load / 9.8)
		wheel.bump_damping = critical * 0.3
		wheel.rebound_damping = critical * 0.4
		wheel.position = to_local(visual.global_position) + Vector3.UP * RIDE_LENGTH
		wheel.visual = visual
		wheel.visual_rest = visual.basis
		add_child(wheel)
		wheels.append(wheel)


func _build_headlights() -> void:
	for side: String in ["Headlight_L", "Headlight_R"]:
		var light := SpotLight3D.new()
		light.position = _local(side) + Vector3(0.0, 0.0, -0.05)
		light.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
		light.spot_range = 70.0
		light.spot_angle = 32.0
		light.spot_attenuation = 0.6
		light.light_energy = 6.0
		light.light_color = Color(1.0, 0.93, 0.78)
		light.shadow_enabled = Graphics.current == &"high"
		light.visible = headlights
		add_child(light)
		_headlights.append(light)


## Velocity of a world-space point on the RV.
func point_velocity(point: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(point - to_global(center_of_mass))


## Forward speed, m/s (negative when reversing).
func forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


func is_automatic() -> bool:
	return drivetrain.automatic


func set_automatic(on: bool) -> void:
	drivetrain.automatic = on
	if on and drivetrain.gear == 0 and drivetrain.running:
		drivetrain.shift_to(1)


## Sequential shift (keys, controller). Manual: dips the clutch for you if it isn't held.
func shift_by(steps: int) -> void:
	select_gear((_pending_gear if _assist_timer > 0.0 else drivetrain.gear) + steps)


## Goes straight to a gear (-1 = reverse). Manual: dips the clutch if it isn't held.
func select_gear(target: int) -> void:
	target = clampi(target, -1, 5)
	if drivetrain.can_shift():
		drivetrain.shift_to(target)
	else:
		_pending_gear = target
		_assist_timer = 0.3


## Mouse drag on the H-pattern stick (stick units). Only moves while the clutch is down.
func drag_gear_stick(delta: Vector2) -> void:
	if drivetrain.automatic or not drivetrain.can_shift():
		return
	gear_stick.drag(delta)
	var g := gear_stick.gear()
	if g != drivetrain.gear:
		drivetrain.shift_to(g)


func start_engine() -> void:
	drivetrain.crank()


func _physics_process(dt: float) -> void:
	if freeze:
		return
	var speed := forward_speed()
	var drive_throttle := throttle
	var service_brake := brake
	if drivetrain.automatic:
		_automatic_selector(dt, speed)
		if drivetrain.gear == -1:
			# Reversing in an automatic: the pedals swap, like in most driving games.
			drive_throttle = brake
			service_brake = throttle

	_update_steering(dt, speed)
	for wheel: RVWheel in wheels:
		wheel.probe(self)

	# Drivetrain: the engine is coupled to the driven wheels' rolling speed. (Feeding it
	# wheelspin too would couple the light axle to the flywheel through a stiff clutch,
	# which a 60 Hz step can't integrate stably.)
	var driven_on_ground: Array[RVWheel] = []
	var ground_omega := 0.0
	for wheel: RVWheel in wheels:
		if wheel.driven and wheel.grounded:
			driven_on_ground.append(wheel)
			ground_omega += wheel.ground_speed / wheel.radius
	if driven_on_ground.is_empty():
		ground_omega = speed / WHEEL_RADIUS # Airborne: the wheels keep turning.
	else:
		ground_omega /= driven_on_ground.size()
	if drive_throttle > 0.1:
		parking_brake = false
	var clutch := clutch_input
	if _assist_timer > 0.0:
		_assist_timer -= dt
		clutch = 1.0
		if drivetrain.can_shift() and _pending_gear != drivetrain.gear:
			drivetrain.shift_to(_pending_gear)
			_assist_timer = minf(_assist_timer, 0.05)
	var axle_torque := drivetrain.step(dt, drive_throttle, clutch, ground_omega)
	var drive := axle_torque / WHEEL_RADIUS

	var excess := 0.0
	for wheel: RVWheel in wheels:
		var wheel_drive := 0.0
		if wheel.driven and wheel.grounded:
			wheel_drive = drive / driven_on_ground.size()
		var wheel_brake := service_brake * BRAKE_FORCE * wheel.brake_share
		if (handbrake or parking_brake) and wheel.has_handbrake:
			wheel_brake += HANDBRAKE_FORCE * 0.5
		wheel.apply_forces(self, dt, wheel_drive, wheel_brake)
		excess += wheel.excess_drive
	_update_wheelspin(dt, axle_torque, excess, driven_on_ground.is_empty())

	_anti_roll(wheels[0], wheels[1], 26000.0)
	_anti_roll(wheels[2], wheels[3], 18000.0)
	apply_central_force(-linear_velocity * linear_velocity.length() * DRAG)

	for wheel: RVWheel in wheels:
		wheel.update_visual(self, dt, _axle_spin if wheel.driven else 0.0)
	_update_cab_visuals()


func _automatic_selector(dt: float, speed: float) -> void:
	if not drivetrain.running:
		return
	var gear := drivetrain.gear
	if gear == 0 and throttle > 0.1:
		drivetrain.shift_to(1)
	elif gear >= 1 and brake > 0.1 and throttle < 0.1 and speed < 0.6:
		_auto_reverse_timer += dt
		if _auto_reverse_timer > 0.35:
			drivetrain.shift_to(-1)
			_auto_reverse_timer = 0.0
	elif gear == -1 and throttle > 0.1 and speed > -0.6:
		drivetrain.shift_to(1)
	else:
		_auto_reverse_timer = 0.0


func _update_steering(dt: float, speed: float) -> void:
	# Keyboard steering eases in, and returns to centre a little quicker.
	var rate := 2.2 if absf(steer_input) > absf(_steer) else 3.2
	_steer = move_toward(_steer, clampf(steer_input, -1.0, 1.0), rate * dt)
	var max_angle := lerpf(MAX_STEER, HIGH_SPEED_STEER, clampf(absf(speed) / 28.0, 0.0, 1.0))
	var angle := _steer * max_angle
	var outer := angle
	var inner := angle
	if absf(angle) > 0.001:
		# Ackermann: the inside wheel turns tighter so neither tire scrubs.
		var turn_radius := WHEELBASE / tan(absf(angle))
		inner = signf(angle) * atan(WHEELBASE / (turn_radius - TRACK * 0.5))
		outer = signf(angle) * atan(WHEELBASE / (turn_radius + TRACK * 0.5))
	# Positive input steers right (towards +X), which is a negative rotation about +Y.
	wheels[0].steer_angle = -(outer if angle > 0.0 else inner) # Front left.
	wheels[1].steer_angle = -(inner if angle > 0.0 else outer) # Front right.


func _update_wheelspin(dt: float, axle_torque: float, excess: float, airborne: bool) -> void:
	if airborne:
		# Nothing resists the axle but the brakes.
		_axle_spin += axle_torque / AXLE_INERTIA * dt
		_axle_spin = move_toward(_axle_spin, 0.0, (brake + (1.0 if handbrake else 0.0)) * 60.0 * dt)
	elif absf(excess) > 1.0:
		# Torque the tires couldn't use spins the wheels up.
		_axle_spin += excess * WHEEL_RADIUS / AXLE_INERTIA * dt
	else:
		# Grip is back: the tires drag the spin down quickly.
		_axle_spin = move_toward(_axle_spin, 0.0, (absf(_axle_spin) * 8.0 + 2.0) * dt)
	_axle_spin = clampf(_axle_spin, -60.0, 60.0)


## Anti-roll bar: resists one side of an axle compressing more than the other.
func _anti_roll(left: RVWheel, right: RVWheel, stiffness: float) -> void:
	if not (left.grounded and right.grounded):
		return
	var force := (right.length - left.length) * stiffness # > 0 when the left is more compressed.
	var up := global_basis.y
	apply_force(up * force, left.global_position - global_position)
	apply_force(-up * force, right.global_position - global_position)


func _update_cab_visuals() -> void:
	var turn := _steer * STEERING_WHEEL_TURNS * TAU
	# The column points away from the driver, so a positive turn is clockwise to them.
	_steering_wheel.transform = _steering_rest * Transform3D(Basis(_steering_axis, turn), Vector3.ZERO)
	var p := gear_stick.position
	_gear_lever.basis = _gear_lever_rest * Basis.from_euler(Vector3(-p.y * 0.35, 0.0, -p.x * 0.22))
