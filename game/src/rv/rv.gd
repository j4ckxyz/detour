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
## A seat's occupant changed (seat names: &"driver", &"passenger", &"dinette_front", ...).
signal seat_used(seat: StringName, player: Player)
## Someone here opened or closed the door (for the network to pass on).
signal door_toggled(open: bool)

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
## The clutch (the pedal or the shift assist) was down since the last time it came up.
var _clutch_was_down := false
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
var damage := RVDamage.new()
var gear_stick := RVGearStick.new()
## Its sounds (see `RVAudio`).
var audio := RVAudio.new()
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
var _door: Node3D
var _door_rest := Basis.IDENTITY
var _door_angle := 0.0

## The inside, as its own physics world (see `RVInterior`).
var interior := RVInterior.new()
## Items put down inside ride here, frozen (see `Item`).
var stash := Node3D.new()
var door_open := false:
	set(open):
		door_open = open
		interior.set_door_open(open)
## Optional `func(x: float, z: float) -> float`: how muddy the ground is (0..1).
var surface_query: Callable
## Optional `func(x, z) -> float`: how icy the ground is (0..1).
var ice_query: Callable
## Optional `func(x, z) -> float`: the water surface there (-10000 if dry).
var water_query: Callable
## 0..1: how wet the ground is (rain); the tires grip a little less.
var wetness := 0.0
## Storm gusts (a unit-ish vector scaled by strength); pushes the tall RV sideways.
var wind := Vector3.ZERO
const WIND_FORCE := 2200.0
## How deep the RV stands in water (metres over the bottom of the body), for the HUD.
var wading := 0.0
## Grip left on ice (planks laid on it give it back).
const ICE_GRIP := 0.15
## Water drag per metre of depth (N per (m/s)²), and the engine's air intake (RV space):
## water above it floods the engine.
const WATER_DRAG := 900.0
const AIR_INTAKE := Vector3(0.0, 1.35, -3.0)
## Front and rear winches.
var winches: Array[RVWinch] = []
## Seat name → {eye, stand} in RV space: where a seated player looks from, and where they
## stand up.
var seats: Dictionary[StringName, Dictionary] = {}
## Whether this machine simulates the RV: always solo; online, the driver's machine, or the
## host's while nobody drives. Elsewhere it follows the simulating machine's snapshots.
var is_simulated := true
## Online: `func(op: StringName, args: Array)` that sends an op to the simulating machine.
var forward_op: Callable
## Ops anyone may ask the simulating machine for (see apply_op).
const OPS: Array[StringName] = [
	&"push", &"patch_part", &"refit_part", &"mount_wheel", &"swap_tire", &"tighten_bolt",
	&"add_oil", &"add_fuel", &"weld", &"winch_drive",
]

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
	contact_monitor = true # For impact damage (see _integrate_forces).
	max_contacts_reported = 12
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
	_build_interior() # Needs driver_eye.
	for which: String in ["Front", "Rear"]:
		var winch := RVWinch.new()
		winch.name = "Winch" + which
		winch.position = _local("WinchMount_" + which)
		add_child(winch)
		winch.setup(self, which.to_lower(), _marker("WinchDrum_" + which))
		winches.append(winch)

	damage.name = "Damage"
	add_child(damage)
	damage.setup(self)
	drivetrain.can_start = damage.can_start
	drivetrain.stalled.connect(engine_stalled.emit)
	drivetrain.started.connect(engine_started.emit)
	drivetrain.gear_changed.connect(gear_stick.set_gear)

	audio.name = "Audio"
	add_child(audio)
	audio.setup(self)


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


## The kitchen stove's top, RV space (cooks patties like any grill).
const STOVE_TOP := Vector3(0.83, 1.79, 1.3)
var stove := Grill.new()


func _build_interior() -> void:
	interior.build(load(MODEL_COLLISION) as PackedScene)
	add_child(interior)
	stash.name = "Stash"
	add_child(stash)
	_door = _marker("Door_Entry")
	_door_rest = _door.basis
	var door := Interactable.new()
	door.name = "DoorHandle"
	door.position = Vector3(interior.door_x_outer, interior.floor_y + 0.8, (interior.door_z.x + interior.door_z.y) * 0.5)
	door.reach = 2.4
	door.prompt_for = func(_p: Player) -> String: return "Close door" if door_open else "Open door"
	door.used.connect(func(_p: Player) -> void:
		door_open = not door_open
		door_toggled.emit(door_open))
	add_child(door)
	stove.name = "Stove"
	stove.position = STOVE_TOP
	add_child(stove)
	_build_storage()

	# (seat, marker, label, how far behind the seat the player stands up)
	var seat_specs: Array[Array] = [
		[&"driver", "Seat_Driver", "Drive", Vector3(0.0, 0.0, 0.55)],
		[&"passenger", "Seat_Passenger", "Sit", Vector3(0.0, 0.0, 0.55)],
		[&"dinette_front", "Seat_DinetteFront", "Sit", Vector3(0.55, 0.0, 0.0)],
		[&"dinette_rear", "Seat_DinetteRear", "Sit", Vector3(0.55, 0.0, 0.0)],
	]
	for spec: Array in seat_specs:
		var seat_pos := _local(spec[1])
		var eye := seat_pos + Vector3(0.0, 0.62, 0.02)
		if spec[0] == &"driver":
			eye = driver_eye.origin
		var stand := seat_pos + (spec[3] as Vector3)
		stand.y = interior.floor_y + 0.05
		seats[spec[0]] = {"eye": eye, "stand": stand}
		var seat := Interactable.new()
		seat.name = "Seat_" + String(spec[0])
		seat.position = seat_pos + Vector3(0.0, 0.3, 0.0)
		seat.reach = 1.6
		var label: String = spec[2]
		var seat_name: StringName = spec[0]
		seat.prompt_for = func(p: Player) -> String:
			if not p.inside or p.seat != &"":
				return ""
			return label if seat_occupant(seat_name) == null else ""
		seat.used.connect(func(p: Player) -> void: p.sit(self, seat_name))
		add_child(seat)


## Where things are kept (RV space): [name prefix, accepts, label, positions, turn].
const STORAGE: Array[Array] = [
	["PlankRack", [&"plank"], "plank rack", [Vector3(-1.36, 1.95, 1.15), Vector3(-1.36, 2.05, 1.15), Vector3(-1.36, 2.15, 1.15)], Vector3(0.0, PI / 2.0, 0.0)],
	["SpareMount", [&"tire"], "spare-tire mount", [Vector3(-0.6, 1.7, 3.61)], Vector3(PI / 2.0, 0.0, 0.0)],
	["CanHolder", [&"can"], "jerry-can holder", [Vector3(-0.05, 0.72, 3.69), Vector3(0.3, 0.72, 3.69)], Vector3.ZERO],
	["ToolWall", [&"tool"], "tool wall", [Vector3(-0.5, 1.65, 1.2), Vector3(-0.5, 1.65, 1.5), Vector3(-0.5, 1.65, 1.8)], Vector3(0.0, PI / 2.0, 0.0)],
	["FridgeTop", [&"food", &"drink"], "top of the fridge", [Vector3(-0.95, 2.6, 0.35), Vector3(-0.7, 2.6, 0.35), Vector3(-0.95, 2.6, 0.6),
		Vector3(-0.7, 2.6, 0.6), Vector3(-0.95, 2.6, 0.85), Vector3(-0.7, 2.6, 0.85)], Vector3.ZERO],
	["Shelf", [&"small", &"tool"], "overhead shelf", [Vector3(-0.75, 2.25, -1.55), Vector3(-0.25, 2.25, -1.55), Vector3(0.25, 2.25, -1.55),
		Vector3(0.75, 2.25, -1.55), Vector3(-0.75, 2.25, -1.85), Vector3(-0.25, 2.25, -1.85), Vector3(0.25, 2.25, -1.85), Vector3(0.75, 2.25, -1.85)], Vector3.ZERO],
	["Bed", [&"medium", &"small", &"food"], "bed", [Vector3(-0.6, 1.59, 2.4), Vector3(0.0, 1.59, 2.4), Vector3(0.6, 1.59, 2.4),
		Vector3(-0.6, 1.59, 2.9), Vector3(0.0, 1.59, 2.9), Vector3(0.6, 1.59, 2.9)], Vector3.ZERO],
	["CupHolder", [&"drink"], "cup holder", [Vector3(0.1, 1.32, -2.3), Vector3(0.3, 1.32, -2.3)], Vector3.ZERO],
]
## Every storage slot, by name ("PlankRack1", "Shelf5", ...).
var storage: Dictionary[StringName, StorageSlot] = {}


func _build_storage() -> void:
	for spec: Array in STORAGE:
		var positions: Array = spec[3]
		for i: int in positions.size():
			var slot := StorageSlot.new()
			slot.name = "%s%d" % [spec[0], i + 1]
			slot.rv = self
			slot.label = spec[2]
			slot.outside = spec[0] in ["PlankRack", "SpareMount", "CanHolder"]
			for kind: StringName in spec[1]:
				slot.accepts.append(kind)
			slot.turn = Basis.from_euler(spec[4])
			slot.position = positions[i]
			add_child(slot)
			storage[StringName(slot.name)] = slot


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


## Changes the RV's state (a push, a repair, a winch remote): here if this machine simulates
## it, else sent to the one that does.
func op(name: StringName, args: Array = []) -> void:
	if is_simulated or not forward_op.is_valid():
		apply_op(name, args)
	else:
		forward_op.call(name, args)


func apply_op(name: StringName, args: Array) -> void:
	match name:
		&"push":
			apply_force(args[0], args[1])
		&"patch_part":
			damage.patch_part(args[0])
		&"refit_part":
			damage.refit_part(args[0])
		&"mount_wheel":
			damage.mount_wheel(args[0], args[1])
		&"swap_tire":
			damage.swap_tire(args[0])
		&"tighten_bolt":
			damage.tighten_bolt(args[0])
		&"add_oil":
			damage.add_oil()
		&"add_fuel":
			damage.add_fuel(args[0])
		&"weld":
			damage.weld()
		&"winch_drive":
			winches[args[0]].set_drive(args[1], args[2])


## Who's sitting in a seat (any player, here or remote), or null.
func seat_occupant(seat_name: StringName) -> Player:
	for n: Node in get_tree().get_nodes_in_group(&"players"):
		var p := n as Player
		if p.seat == seat_name and p.rv == self:
			return p
	return null


## What the simulating machine sends out, 30 times a second.
func snapshot() -> Array:
	var w := PackedFloat32Array()
	for wheel: RVWheel in wheels:
		w.append_array([wheel.length, wheel.ground_speed, 1.0 if wheel.grounded else 0.0])
	return [
		global_position, global_basis.get_rotation_quaternion(), linear_velocity, angular_velocity,
		_steer, _axle_spin, w, drivetrain.gear, drivetrain.rpm, drivetrain.running, headlights,
		PackedFloat32Array([winches[0].rope_length, winches[0].tension, winches[1].rope_length, winches[1].tension]),
		PackedInt32Array([winches[0].drive, winches[1].drive]), throttle,
	]


## Takes on the non-transform parts of a snapshot (the network layer moves the body).
func apply_snapshot(s: Array) -> void:
	linear_velocity = s[2]
	angular_velocity = s[3]
	_steer = s[4]
	steer_input = _steer
	_axle_spin = s[5]
	var w: PackedFloat32Array = s[6]
	for i: int in wheels.size():
		wheels[i].length = w[i * 3]
		wheels[i].ground_speed = w[i * 3 + 1]
		wheels[i].grounded = w[i * 3 + 2] > 0.5
	drivetrain.gear = s[7]
	drivetrain.rpm = s[8]
	drivetrain.running = s[9]
	if headlights != bool(s[10]):
		headlights = s[10]
	var rope: PackedFloat32Array = s[11]
	var drives: PackedInt32Array = s[12]
	for i: int in 2:
		winches[i].rope_length = rope[i * 2]
		winches[i].tension = rope[i * 2 + 1]
		winches[i].drive = drives[i]
	throttle = s[13]


## Slower-changing state: damage, gearbox mode, parking brake.
func slow_snapshot() -> Array:
	return [damage.snapshot(), drivetrain.automatic, parking_brake]


func apply_slow_snapshot(s: Array) -> void:
	damage.apply_snapshot(s[0])
	drivetrain.automatic = s[1]
	parking_brake = s[2]


## Following another machine's simulation: just the moving parts.
func _puppet_step(dt: float) -> void:
	_update_steering(0.0, forward_speed())
	for wheel: RVWheel in wheels:
		wheel.update_visual(self, dt, _axle_spin if wheel.driven else 0.0)
	_update_cab_visuals()
	for winch: RVWinch in winches:
		winch.puppet_step(dt)


func _physics_process(dt: float) -> void:
	if not is_simulated:
		_puppet_step(dt)
		return
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
	drivetrain.power_scale = damage.tick(dt, drive_throttle)
	for i: int in wheels.size():
		var wheel := wheels[i]
		wheel.probe(self)
		wheel.surface_grip = damage.wheel_grip(i)
		wheel.mud = 0.0
		if wheel.grounded and not wheel.on_item:
			if surface_query.is_valid():
				wheel.mud = surface_query.call(wheel.contact.x, wheel.contact.z)
				wheel.surface_grip *= 1.0 - 0.6 * wheel.mud
			if ice_query.is_valid():
				var ice: float = ice_query.call(wheel.contact.x, wheel.contact.z)
				wheel.surface_grip *= lerpf(1.0, ICE_GRIP, ice)
			wheel.surface_grip *= 1.0 - 0.15 * wetness

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
	# Letting the clutch out in gear means "go": the parking brake comes off with it.
	if clutch > 0.5:
		_clutch_was_down = true
	elif _clutch_was_down and drivetrain.gear != 0 and not drivetrain.automatic:
		_clutch_was_down = false
		parking_brake = false
	drivetrain.anti_stall = service_brake < 0.1 and not handbrake and not parking_brake
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
		if wheel.impact_speed > 0.0:
			damage.wheel_impact(wheels.find(wheel), wheel.impact_speed)
	_update_wheelspin(dt, axle_torque, excess, driven_on_ground.is_empty())

	for winch: RVWinch in winches:
		winch.step(dt)
	_wade(dt)
	if wind != Vector3.ZERO:
		apply_force(wind * WIND_FORCE, global_basis.y * 1.5) # High up: it rocks the RV.
	_anti_roll(wheels[0], wheels[1], 26000.0)
	_anti_roll(wheels[2], wheels[3], 18000.0)
	apply_central_force(-linear_velocity * linear_velocity.length() * DRAG)

	for wheel: RVWheel in wheels:
		wheel.update_visual(self, dt, _axle_spin if wheel.driven else 0.0)
	_update_cab_visuals()


## Driving through water: drag that grows with depth and speed, and water over the air
## intake stalls the engine and damages it.
func _wade(dt: float) -> void:
	wading = 0.0
	if not water_query.is_valid():
		return
	var level: float = water_query.call(global_position.x, global_position.z)
	if level < -1000.0:
		return
	wading = maxf(0.0, level - global_position.y)
	if wading > 0.0:
		var v := linear_velocity
		apply_central_force(-v * v.length() * WATER_DRAG * minf(wading, 2.0))
	if level > to_global(AIR_INTAKE).y:
		damage.engine = maxf(0.0, damage.engine - 8.0 * dt)
		if drivetrain.running:
			drivetrain.running = false
			drivetrain.stalled.emit()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not is_simulated:
		return
	for i: int in state.get_contact_count():
		var impulse := state.get_contact_impulse(i).length()
		if impulse > RVDamage.IMPACT_THRESHOLD:
			var at := to_local(state.get_contact_local_position(i))
			damage.hit(at, impulse, state.get_contact_local_normal(i))


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


func _process(delta: float) -> void:
	var target := deg_to_rad(-100.0) if door_open else 0.0
	if not is_equal_approx(_door_angle, target):
		_door_angle = move_toward(_door_angle, target, delta * 4.0)
		_door.basis = Basis(Vector3.UP, _door_angle) * _door_rest


func _update_cab_visuals() -> void:
	var turn := _steer * STEERING_WHEEL_TURNS * TAU
	# The column points away from the driver, so a positive turn is clockwise to them.
	_steering_wheel.transform = _steering_rest * Transform3D(Basis(_steering_axis, turn), Vector3.ZERO)
	var p := gear_stick.position
	_gear_lever.basis = _gear_lever_rest * Basis.from_euler(Vector3(-p.y * 0.35, 0.0, -p.x * 0.22))
