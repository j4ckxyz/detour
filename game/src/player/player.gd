class_name Player
extends CharacterBody3D
## The on-foot, first-person player: walks, sprints, crouches and jumps; walks into and around
## the RV (even while it moves); sits in its seats; and picks up, carries, uses, drops and
## throws items.
##
## Outside, this body moves in the world. Inside the RV it hands its movement to a proxy body
## in the RV's own physics space (`RVInterior`) and follows it at `rv.global_transform *
## proxy`, so nothing jitters however the RV bounces. Look angles are kept relative to the
## current frame: the world outside, the RV inside.

## Seat changes: &"" when standing up. The playground switches cameras and controls on this.
signal seat_changed(seat: StringName)

## Physics layer of players.
const LAYER := 8
const WALK_SPEED := 4.2
const SPRINT_SPEED := 7.0
const CROUCH_SPEED := 2.0
const JUMP_SPEED := 4.6
const ACCEL := 14.0
const AIR_ACCEL := 3.0
const EYE_HEIGHT := 1.62
const CROUCH_EYE_HEIGHT := 1.05
const RADIUS := 0.3
const HEIGHT := 1.8
## How much of the RV's acceleration people standing inside feel (braking makes you stumble).
const INERTIA := 0.35
const THROW_SPEED := 9.0
## Tallest ledge (a rock, a kerb, the cab step) walked up without jumping.
const STEP_HEIGHT := 0.4
const MAX_HEALTH := 100.0

## The RV this player can board.
var rv: RV
## Where dropped and thrown items go in the world.
var world_items: Node
var input_enabled := true
var sensitivity := 0.0025
var held: Item
## &"" when standing, else the seat name (see RV.seats).
var seat := &""
## In the RV's interior space (walking inside, or seated).
var inside := false
var health := MAX_HEALTH
## Current interaction target (an Interactable or an Item) and its prompt.
var target: Node3D
var target_prompt := ""

var camera := Camera3D.new()
var hand := Node3D.new()

var _yaw := 0.0
var _pitch := 0.0
var _crouch := 0.0
var _proxy := CharacterBody3D.new()
var _prev_rv_velocity := Vector3.ZERO


func _init() -> void:
	collision_layer = LAYER
	collision_mask = TerrainStreamer.WORLD_LAYER | RV.VEHICLE_LAYER
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
	for body: CharacterBody3D in [self, _proxy]:
		var capsule := CapsuleShape3D.new()
		capsule.radius = RADIUS
		capsule.height = HEIGHT
		var shape := CollisionShape3D.new()
		shape.shape = capsule
		shape.position.y = HEIGHT * 0.5
		body.add_child(shape)
	_proxy.name = "PlayerProxy"
	_proxy.floor_max_angle = deg_to_rad(50.0)
	_proxy.floor_snap_length = 0.2


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_proxy) and not _proxy.is_inside_tree():
		_proxy.free() # Never boarded: the proxy was never parented.


## Where the player is in RV space while inside (the interior proxy's position).
func local_position() -> Vector3:
	return _proxy.position


func is_on_ground() -> bool:
	return _proxy.is_on_floor() if inside else is_on_floor()


func _ready() -> void:
	camera.name = "Eyes"
	camera.fov = 75.0
	camera.near = 0.05
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	hand.name = "Hand"
	camera.add_child(hand)


## Looks towards `yaw` (radians, in the current frame).
func look(yaw: float, pitch: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)
	_pitch = clampf(pitch, -1.45, 1.45)


func is_driving() -> bool:
	return seat == &"driver"


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_driving():
		look(_yaw - motion.relative.x * sensitivity, _pitch - motion.relative.y * sensitivity)
		return
	if event.is_echo():
		return
	if seat != &"":
		if event.is_action_pressed(&"leave_seat"):
			stand_up()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") and target:
		target.call(&"interact", self)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"use_item") and held and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		held.use(self)
	elif event.is_action_pressed(&"throw_item") and held:
		throw_held()
	elif event.is_action_pressed(&"drop_item") and held:
		drop_held()


func _physics_process(dt: float) -> void:
	if seat != &"":
		_follow_rv(_proxy.position)
		return
	var wish := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if input_enabled else Vector2.ZERO
	var crouching := input_enabled and Input.is_action_pressed(&"crouch")
	_crouch = move_toward(_crouch, 1.0 if crouching else 0.0, dt * 6.0)
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED)
	var jump := input_enabled and Input.is_action_just_pressed(&"jump") and not crouching
	if inside:
		_move_inside(dt, wish, speed, jump)
	else:
		_move_outside(dt, wish, speed, jump)


func _process(_dt: float) -> void:
	_place_camera()
	_find_target()


func _move_outside(dt: float, wish: Vector2, speed: float, jump: bool) -> void:
	velocity = _walk(velocity, wish, speed, dt, is_on_floor(), jump, get_gravity())
	var was_on_floor := is_on_floor()
	move_and_slide()
	if was_on_floor and is_on_wall():
		_step_up(self, Vector3(velocity.x, 0.0, velocity.z) * dt)
	if rv and rv.door_open:
		var local := rv.to_local(global_position)
		var toward_rv := (rv.global_basis.inverse() * velocity).x < -0.2
		if rv.interior.in_doorway(local, 0.9) and local.y < rv.interior.floor_y + 0.6 and toward_rv:
			board(local)


func _move_inside(dt: float, wish: Vector2, speed: float, jump: bool) -> void:
	# Gravity in RV space: on a slope it pulls you towards the low side, like in a real van.
	var basis_inv := rv.global_basis.inverse()
	var gravity := basis_inv * get_gravity()
	var v := _walk(_proxy.velocity, wish, speed, dt, _proxy.is_on_floor(), jump, gravity)
	var accel := (rv.linear_velocity - _prev_rv_velocity) / dt
	_prev_rv_velocity = rv.linear_velocity
	var local_accel := basis_inv * accel
	v -= Vector3(local_accel.x, 0.0, local_accel.z) * INERTIA * dt
	_proxy.velocity = v
	var was_on_floor := _proxy.is_on_floor()
	_proxy.move_and_slide()
	if was_on_floor and _proxy.is_on_wall():
		_step_up(_proxy, Vector3(v.x, 0.0, v.z) * dt)
	var p := _proxy.position
	if p.x > rv.interior.door_x_outer + 0.1 and rv.interior.in_doorway(p, 1.0):
		leave_rv()
	elif p.y < -2.0:
		leave_rv() # Fell out somehow: put them back in the world.
	else:
		_follow_rv(p)


## Lifts `body` onto a ledge it walked into, if there's room above and ground beyond.
static func _step_up(body: CharacterBody3D, motion: Vector3) -> void:
	if motion.length_squared() < 1e-6:
		return
	var up := Vector3.UP * STEP_HEIGHT
	var xf := body.global_transform
	if body.test_move(xf, up):
		return # Head room.
	var raised := xf.translated(up)
	var ahead := motion.normalized() * maxf(motion.length(), RADIUS * 0.5)
	if body.test_move(raised, ahead):
		return # Still a wall: too tall.
	var col := KinematicCollision3D.new()
	var moved := raised.translated(ahead)
	if body.test_move(moved, -up, col) and col.get_normal().y > 0.7:
		body.global_transform = moved.translated(col.get_travel())


## Horizontal steering towards the wished direction, plus gravity or a jump.
func _walk(v: Vector3, wish: Vector2, speed: float, dt: float, on_floor: bool, jump: bool, gravity: Vector3) -> Vector3:
	var dir := Basis(Vector3.UP, _yaw) * Vector3(wish.x, 0.0, wish.y)
	var target_v := dir * speed
	var rate := ACCEL if on_floor else AIR_ACCEL
	var h := Vector3(v.x, 0.0, v.z).move_toward(Vector3(target_v.x, 0.0, target_v.z), rate * speed * dt)
	var vy := v.y
	if on_floor and jump:
		vy = JUMP_SPEED
	elif not on_floor:
		vy += gravity.y * dt
	elif vy < 0.0:
		vy = 0.0
	h += Vector3(gravity.x, 0.0, gravity.z) * dt # Sideways gravity when the RV leans.
	return Vector3(h.x, vy, h.z)


func _follow_rv(local: Vector3) -> void:
	global_transform = rv.global_transform * Transform3D(Basis.IDENTITY, local)


## Steps into the RV through the door (`local`: where we are in RV space).
func board(local: Vector3) -> void:
	inside = true
	collision_layer = 0
	collision_mask = 0
	var start := rv.interior.inside_door()
	start.z = clampf(local.z, rv.interior.door_z.x + 0.3, rv.interior.door_z.y - 0.3)
	# Keep facing the same way, now measured in the RV's frame.
	var world_dir := Basis(Vector3.UP, _yaw) * Vector3.FORWARD
	var local_dir := rv.global_basis.inverse() * world_dir
	_yaw = atan2(-local_dir.x, -local_dir.z)
	if _proxy.get_parent() != rv.interior:
		if _proxy.get_parent():
			_proxy.get_parent().remove_child(_proxy)
		rv.interior.add_child(_proxy)
	_proxy.position = start
	_proxy.velocity = Vector3.ZERO
	_prev_rv_velocity = rv.linear_velocity
	_follow_rv(start)
	reset_physics_interpolation()


## Steps out of the RV door into the world.
func leave_rv() -> void:
	var p := _proxy.position
	var out := Vector3(rv.interior.door_x_outer + 0.55, rv.interior.floor_y - 0.2, clampf(p.z, rv.interior.door_z.x, rv.interior.door_z.y))
	var world_dir := rv.global_basis * (Basis(Vector3.UP, _yaw) * Vector3.FORWARD)
	_yaw = atan2(-world_dir.x, -world_dir.z)
	inside = false
	global_transform = Transform3D(Basis.IDENTITY, rv.to_global(out))
	velocity = rv.point_velocity(global_position)
	collision_layer = LAYER
	collision_mask = TerrainStreamer.WORLD_LAYER | RV.VEHICLE_LAYER
	reset_physics_interpolation()


## Sits in one of the RV's seats (must already be inside).
func sit(on: RV, seat_name: StringName) -> void:
	if not inside or seat != &"" or on != rv:
		return
	if held and held.def.get("two_handed", false):
		drop_held() # Can't drive holding a spare tire.
	seat = seat_name
	_yaw = 0.0
	_pitch = -0.1
	_proxy.velocity = Vector3.ZERO
	_proxy.position = rv.seats[seat_name]["stand"]
	seat_changed.emit(seat)


func stand_up() -> void:
	if seat == &"":
		return
	_proxy.position = rv.seats[seat]["stand"]
	seat = &""
	_proxy.velocity = Vector3.ZERO
	_prev_rv_velocity = rv.linear_velocity
	seat_changed.emit(seat)


## Puts the player in the driver's seat directly (spawn, tests).
func take_wheel() -> void:
	if not inside:
		board(rv.to_local(global_position))
	sit(rv, &"driver")


func pick_up(item: Item) -> void:
	if held:
		return
	held = item
	item.grab(self, hand)


func drop_held() -> void:
	if not held:
		return
	var item := held
	held = null
	if inside:
		_stow(item)
	else:
		var at := camera.global_transform.translated_local(Vector3(0.0, -0.3, -0.8))
		item.release(world_items, Transform3D(Basis(Vector3.UP, _yaw), at.origin), velocity)


func throw_held() -> void:
	if not held:
		return
	if inside:
		drop_held()
		return
	var item := held
	held = null
	var forward := -camera.global_basis.z
	var speed := THROW_SPEED / sqrt(maxf(1.0, item.mass))
	item.release(world_items, item.global_transform, velocity + forward * speed)


## Puts an item down on whatever is under it inside the RV.
func _stow(item: Item) -> void:
	var local_cam := rv.global_transform.affine_inverse() * camera.global_transform
	var from := local_cam.origin
	var ahead := from + (local_cam.basis * Vector3.FORWARD) * 0.7
	var query := PhysicsRayQueryParameters3D.create(ahead + Vector3.UP * 0.3, ahead + Vector3.DOWN * 3.0)
	query.exclude = [_proxy.get_rid()]
	var hit := rv.interior.space_state().intersect_ray(query)
	var spot: Vector3 = hit["position"] if hit else Vector3(ahead.x, rv.interior.floor_y, ahead.z)
	item.stow(rv, Transform3D(Basis(Vector3.UP, _yaw), spot + Vector3.UP * (item.base_offset + 0.01)))


func eat(item: Item) -> void:
	health = minf(MAX_HEALTH, health + 30.0)
	if held == item:
		held = null
	item.queue_free()


func _place_camera() -> void:
	var eye_height := lerpf(EYE_HEIGHT, CROUCH_EYE_HEIGHT, _crouch)
	if seat != &"" and rv:
		var rv_xf := rv.get_global_transform_interpolated()
		var eye: Vector3 = rv.seats[seat]["eye"]
		camera.global_transform = Transform3D(rv_xf.basis * Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), rv_xf * eye)
		return
	var body := get_global_transform_interpolated()
	var frame := rv.get_global_transform_interpolated().basis if inside and rv else Basis.IDENTITY
	var eye_pos := body.origin + frame * Vector3(0.0, eye_height, 0.0)
	camera.global_transform = Transform3D(frame * Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), eye_pos)


## Picks what the player is looking at: the closest interactable near the view centre.
func _find_target() -> void:
	target = null
	target_prompt = ""
	if not input_enabled or seat != &"":
		return
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var best := -INF
	for node: Node in get_tree().get_nodes_in_group(&"interactable"):
		var n := node as Node3D
		if n == null or n == held or not n.is_visible_in_tree():
			continue
		var to := n.global_position - eye
		var dist := to.length()
		if dist > float(n.call(&"interact_reach")) or dist < 0.01:
			continue
		var facing := to.dot(forward) / dist
		if facing < 0.9:
			continue
		var score := facing - dist * 0.03
		if score > best:
			var prompt: String = n.call(&"interact_prompt", self)
			if prompt != "":
				best = score
				target = n
				target_prompt = prompt
