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
## Health ran out (true) or someone got them back up (false).
signal downed_changed(is_downed: bool)
## Bled out while down: the playground wakes them up again by the RV.
signal passed_out

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
## Push on the RV per player (N), fading out by PUSH_FADE_SPEED (m/s).
const PUSH_FORCE := 3000.0
const PUSH_FADE_SPEED := 1.4
## Seconds a downed player lasts before passing out, and how fast they crawl meanwhile.
const BLEED_OUT := 60.0
const CRAWL_SPEED := 0.8
const DOWNED_EYE_HEIGHT := 0.45
## Health an EpiPen gets you back up with.
const REVIVE_HEALTH := 40.0
## Snake venom: health lost per second, and how long a bite keeps working without antidote.
const VENOM_DPS := 1.2
const VENOM_TIME := 90.0
## Landing faster than this (m/s) hurts, by FALL_DAMAGE per m/s over (a ~5 m drop is safe,
## ~8 m costs a quarter of your health, ~15 m nearly all of it).
const FALL_SAFE_SPEED := 10.0
const FALL_DAMAGE := 9.0
## The RV moving into you faster than this (m/s) knocks you over, by RV_HIT_DAMAGE per m/s over.
const RV_HIT_SPEED := 3.5
const RV_HIT_DAMAGE := 9.0

## Online: whose player this is, and whether it's someone else's (a puppet following their
## snapshots; things done to it are sent to them through `remote`).
var peer_id := 1
var puppet := false
## `func(peer: int, method: StringName, args: Array)`, set by NetGame on puppets.
var remote: Callable
## The RV this player can board.
var rv: RV
## Where dropped and thrown items go in the world.
var world_items: Node
var input_enabled := true
var sensitivity := 0.0025
## The hotbar: small things pocket into the other slots, the selected one is in your hand.
## Big things (two-handed) need an empty hand and can't be pocketed.
const SLOTS := 4
var slots: Array[Item] = [null, null, null, null]
var selected := 0
var held: Item:
	get:
		return slots[selected]
	set(item):
		slots[selected] = item
## &"" when standing, else the seat name (see RV.seats).
var seat := &""
## In the RV's interior space (walking inside, or seated).
var inside := false
var health := MAX_HEALTH
## Out of health: crawling, waiting for an EpiPen, bleeding out (`bleed_out` seconds left).
var downed := false
var bleed_out := 0.0
## Seconds of snake venom left working (0 = not poisoned).
var venom := 0.0
## What hurt last, and a 0..1 flash for the HUD that fades after each hit.
var hurt_cause := ""
var hurt_flash := 0.0
## Current interaction target (an Interactable or an Item) and its prompt.
var target: Node3D
var target_prompt := ""

var camera := Camera3D.new()
var hand := Node3D.new()
## Which winch the remote works (index into rv.winches).
var winch_choice := 0
var message := ""
var message_time := 0.0
## True while walking into the RV hard enough to push it.
var pushing := false

var _yaw := 0.0
var _pitch := 0.0
var _crouch := 0.0
var _proxy := CharacterBody3D.new()
var _prev_rv_velocity := Vector3.ZERO
var _ghost := MeshInstance3D.new()
var _tool_timer := 0.0
var _rv_hit_cooldown := 0.0
var _winch_sent: Array[int] = [0, 0]
## Puppets: where the snapshots say we are (world, or RV space when inside) and how fast.
var _net_pos := Vector3.ZERO
var _net_velocity := Vector3.ZERO
var _net_age := 0.0
var _avatar: Node3D


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


func is_crouching() -> bool:
	return _crouch > 0.5 and not downed


func is_on_ground() -> bool:
	return _proxy.is_on_floor() if inside else is_on_floor()


func _ready() -> void:
	add_to_group(&"players")
	if puppet:
		collision_layer = 0
		collision_mask = 0
		_build_avatar()
	camera.name = "Eyes"
	camera.fov = 75.0
	camera.near = 0.05
	camera.top_level = true
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	hand.name = "Hand"
	camera.add_child(hand)
	var ghost_material := StandardMaterial3D.new()
	ghost_material.albedo_color = Color(0.6, 1.0, 0.6, 0.35)
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ghost_mesh := BoxMesh.new()
	ghost_mesh.size = Vector3(ItemLibrary.PLANK_LENGTH, 0.06, 0.3)
	ghost_mesh.material = ghost_material
	_ghost.mesh = ghost_mesh
	_ghost.top_level = true
	_ghost.visible = false
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_ghost)


## Looks towards `yaw` (radians, in the current frame).
func look(yaw: float, pitch: float) -> void:
	_yaw = wrapf(yaw, -PI, PI)
	_pitch = clampf(pitch, -1.45, 1.45)


func is_driving() -> bool:
	return seat == &"driver"


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or puppet:
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not is_driving():
		look(_yaw - motion.relative.x * sensitivity, _pitch - motion.relative.y * sensitivity)
		return
	if event.is_echo():
		return
	if downed:
		if event.is_action_pressed(&"use_item") and find_item(&"epipen"):
			consume(find_item(&"epipen"))
			revive(null)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(&"interact"):
			bleed_out = 0.0 # Give up and pass out now.
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"winch_select") and held and held.kind == &"winch_remote" and rv:
		winch_choice = (winch_choice + 1) % rv.winches.size()
		get_viewport().set_input_as_handled()
		return
	if seat != &"":
		if event.is_action_pressed(&"leave_seat"):
			stand_up()
			get_viewport().set_input_as_handled()
		return
	for i: int in SLOTS:
		if event.is_action_pressed(StringName("slot_%d" % (i + 1))):
			select_slot(i)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"slot_next") or event.is_action_pressed(&"slot_prev"):
		var step := 1 if event.is_action_pressed(&"slot_next") else -1
		select_slot(wrapi(selected + step, 0, SLOTS))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"interact") and target:
		target.call(&"interact", self)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"use_item") and held:
		held.use(self)
	elif event.is_action_pressed(&"throw_item") and held and not held.def.get("no_throw", false):
		throw_held()
	elif event.is_action_pressed(&"drop_item") and held:
		drop_held()


func _physics_process(dt: float) -> void:
	if puppet:
		_follow_snapshots(dt)
		return
	_tick_health(dt)
	_work_winch_remote()
	_work_held_tool(dt)
	if seat != &"":
		_follow_rv(_proxy.position)
		return
	var wish := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back") if input_enabled else Vector2.ZERO
	var crouching := input_enabled and Input.is_action_pressed(&"crouch")
	_crouch = move_toward(_crouch, 1.0 if crouching or downed else 0.0, dt * 6.0)
	var speed := CROUCH_SPEED if crouching else (SPRINT_SPEED if Input.is_action_pressed(&"sprint") else WALK_SPEED)
	if downed:
		speed = CRAWL_SPEED
	var jump := input_enabled and Input.is_action_just_pressed(&"jump") and not crouching and not downed
	if inside:
		_move_inside(dt, wish, speed, jump)
	else:
		_move_outside(dt, wish, speed, jump)


func _process(dt: float) -> void:
	message_time = maxf(0.0, message_time - dt)
	_place_camera()
	if puppet:
		_pose_avatar()
		return
	_find_target()
	_update_ghost()


## Shows where a held plank would go.
func _update_ghost() -> void:
	var xf: Variant = ItemLibrary.plank_placement(self) if held and held.kind == &"plank" and seat == &"" else null
	_ghost.visible = xf != null
	if xf != null:
		_ghost.global_transform = xf


func _move_outside(dt: float, wish: Vector2, speed: float, jump: bool) -> void:
	velocity = _walk(velocity, wish, speed, dt, is_on_floor(), jump, get_gravity())
	var was_on_floor := is_on_floor()
	var wished := velocity
	move_and_slide()
	if not was_on_floor and is_on_floor() and -wished.y > FALL_SAFE_SPEED:
		hurt((-wished.y - FALL_SAFE_SPEED) * FALL_DAMAGE, "fell")
	if was_on_floor and is_on_wall():
		_step_up(self, Vector3(velocity.x, 0.0, velocity.z) * dt)
	_push_rv(wished, wish)
	_check_run_over(dt)
	if rv and rv.door_open and not downed:
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


## The RV doesn't collide with people (it would stop dead against them): instead, standing in
## its way while it moves hurts and knocks you aside.
func _check_run_over(dt: float) -> void:
	_rv_hit_cooldown = maxf(0.0, _rv_hit_cooldown - dt)
	if rv == null or _rv_hit_cooldown > 0.0:
		return
	for i: int in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() == rv and col.get_normal().y > 0.7:
			return # Riding on it (the roof, the bumper).
	var local := rv.to_local(global_position + Vector3.UP * 0.9)
	var half := Playground.RV_HALF_EXTENTS + Vector3(RADIUS, 0.0, RADIUS)
	if absf(local.x) > half.x or absf(local.z) > half.z or local.y < -0.6 or local.y > 3.4:
		return
	var rv_v := rv.point_velocity(global_position)
	var away := Vector3(global_position.x - rv.global_position.x, 0.0, global_position.z - rv.global_position.z)
	var side := rv.global_basis.x * signf(local.x) if absf(local.x) / half.x > absf(local.z) / half.z else rv.global_basis.z * signf(local.z)
	var closing := (rv_v - velocity).dot(side)
	if closing < RV_HIT_SPEED or away.length() < 0.01:
		return
	_rv_hit_cooldown = 1.0
	velocity = rv_v + side * 2.5 + Vector3.UP * 3.0
	hurt((closing - RV_HIT_SPEED) * RV_HIT_DAMAGE + 5.0, "hit by the RV")


## Takes `amount` of health (`cause` for the HUD). At zero you go down.
func hurt(amount: float, cause: String) -> void:
	if puppet:
		_tell(&"hurt", [amount, cause])
		return
	if downed or amount <= 0.0:
		return
	health -= amount
	hurt_cause = cause
	hurt_flash = 1.0
	if health <= 0.0:
		go_down()


func heal(amount: float) -> void:
	if not downed:
		health = minf(MAX_HEALTH, health + amount)


func poison() -> void:
	if puppet:
		_tell(&"poison", [])
		return
	venom = VENOM_TIME


## A shove (a bear's swipe): added to our velocity.
func knock(push: Vector3) -> void:
	if puppet:
		_tell(&"knock", [push])
		return
	if not inside:
		velocity += push


## Sends something done to a puppet to its player's machine.
func _tell(method: StringName, args: Array) -> void:
	if remote.is_valid():
		remote.call(peer_id, method, args)


## Out of health: down on the ground, crawling, until an EpiPen or bleeding out.
func go_down() -> void:
	if downed:
		return
	health = 0.0
	downed = true
	bleed_out = BLEED_OUT
	if seat != &"":
		stand_up()
	if held and held.def.get("two_handed", false):
		drop_held()
	add_to_group(&"interactable") # Teammates revive you by looking at you.
	downed_changed.emit(true)


## Back on your feet (an EpiPen: `by` another player, or null for your own).
func revive(by: Player) -> void:
	if puppet:
		_tell(&"revive", [by.peer_id if by else 0])
		return
	if not downed:
		return
	downed = false
	health = REVIVE_HEALTH
	venom = minf(venom, 20.0) # It buys time; the antidote still cures it.
	remove_from_group(&"interactable")
	downed_changed.emit(false)


## Wakes up after passing out (the playground has moved us back to the RV).
func wake_up(with_health: float) -> void:
	downed = false
	health = with_health
	venom = 0.0
	remove_from_group(&"interactable")
	downed_changed.emit(false)


## Takes an item out of the hotbar without freeing it (it went somewhere else).
func forget(item: Item) -> void:
	var i := slots.find(item)
	if i >= 0:
		slots[i] = null


# --- network -------------------------------------------------------------------------------

## What the other machines need to draw us, 30 times a second.
func net_state() -> Array:
	var pos := _proxy.position if inside else global_position
	var v := _proxy.velocity if inside else velocity
	return [inside, pos, v, _yaw, _pitch, _crouch, seat, downed, health, venom > 0.0, selected]


## Puppets: takes on a snapshot from the player's machine.
func apply_net_state(s: Array) -> void:
	var was_inside := inside
	inside = s[0]
	_net_pos = s[1]
	_net_velocity = s[2]
	_net_age = 0.0
	_yaw = s[3]
	_pitch = s[4]
	_crouch = s[5]
	seat = s[6]
	downed = s[7]
	health = s[8]
	venom = 1.0 if s[9] else 0.0
	if int(s[10]) != selected:
		selected = s[10]
		for i: int in SLOTS:
			if slots[i]:
				slots[i].visible = i == selected
	if inside != was_inside or global_position.distance_to(_net_world()) > 6.0:
		global_position = _net_world() # Jumped (in or out of the RV, or a respawn).
		reset_physics_interpolation()
	if downed and not is_in_group(&"interactable"):
		add_to_group(&"interactable")
	elif not downed and is_in_group(&"interactable"):
		remove_from_group(&"interactable")


func _net_world() -> Vector3:
	var p := _net_pos + _net_velocity * minf(_net_age, 0.2)
	return rv.global_transform * p if inside and rv else p


func _follow_snapshots(dt: float) -> void:
	_net_age += dt
	if inside and rv:
		global_transform = rv.global_transform * Transform3D(Basis.IDENTITY, _net_pos + _net_velocity * minf(_net_age, 0.2))
		velocity = rv.linear_velocity
	else:
		global_position = global_position.lerp(_net_world(), minf(1.0, dt * 15.0))
		velocity = _net_velocity


## A simple stand-in body for other players: a jacket in their colour, a head, a name.
func _build_avatar() -> void:
	_avatar = Node3D.new()
	_avatar.name = "Avatar"
	add_child(_avatar)
	var jacket := StandardMaterial3D.new()
	jacket.albedo_color = Session.color_of(peer_id)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.93, 0.76, 0.62)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.2, 0.2, 0.25)
	var body := CapsuleMesh.new()
	body.radius = 0.28
	body.height = 1.1
	body.radial_segments = 8
	body.rings = 2
	body.material = jacket
	_avatar_part(body, Vector3(0.0, 1.0, 0.0))
	var legs := BoxMesh.new()
	legs.size = Vector3(0.42, 0.55, 0.26)
	legs.material = dark
	_avatar_part(legs, Vector3(0.0, 0.3, 0.0))
	var head := SphereMesh.new()
	head.radius = 0.16
	head.height = 0.32
	head.radial_segments = 8
	head.rings = 4
	head.material = skin
	_avatar_part(head, Vector3(0.0, 1.68, 0.0))
	var cap := BoxMesh.new()
	cap.size = Vector3(0.3, 0.08, 0.36)
	cap.material = jacket
	_avatar_part(cap, Vector3(0.0, 1.81, -0.04))
	var tag := Label3D.new()
	tag.text = Session.name_of(peer_id)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0.0, 2.15, 0.0)
	tag.font_size = 40
	tag.outline_size = 10
	tag.no_depth_test = true
	tag.fixed_size = false
	tag.pixel_size = 0.004
	_avatar.add_child(tag)


func _avatar_part(mesh: Mesh, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	_avatar.add_child(mi)


func _pose_avatar() -> void:
	if _avatar == null:
		return
	var lying := Basis(Vector3.RIGHT, -PI / 2.0) if downed else Basis.IDENTITY
	var squat := 1.0 - 0.35 * _crouch if not downed else 1.0
	_avatar.transform = Transform3D(Basis(Vector3.UP, _yaw) * lying * Basis.from_scale(Vector3(1.0, squat, 1.0)), Vector3(0.0, 0.25 if downed else 0.0, 0.0))
	if seat != &"" and rv:
		var eye: Vector3 = rv.seats[seat]["eye"]
		_avatar.global_transform = rv.global_transform * Transform3D(Basis(Vector3.UP, _yaw) * Basis.from_scale(Vector3(1.0, 0.75, 1.0)), eye - Vector3(0.0, 1.35, 0.0))


func _tick_health(dt: float) -> void:
	hurt_flash = maxf(0.0, hurt_flash - dt * 1.5)
	if venom > 0.0:
		venom = maxf(0.0, venom - dt)
		if not downed:
			health -= VENOM_DPS * dt
			hurt_cause = "snake venom"
			if health <= 0.0:
				go_down()
	if downed:
		bleed_out -= dt
		if bleed_out <= 0.0:
			bleed_out = 0.0
			passed_out.emit()


# Downed players are interactable (for teammates with an EpiPen).
func interact_prompt(player: Player) -> String:
	if player == self or not downed:
		return ""
	if player.find_item(&"epipen"):
		return "Revive with your EpiPen"
	return "Needs an EpiPen to get up"


func interact(player: Player) -> void:
	var pen := player.find_item(&"epipen")
	if player != self and downed and pen:
		player.consume(pen)
		revive(player)


func interact_reach() -> float:
	return 2.2


## Walking into the RV pushes it (PLAN.md §4.2): a scripted force at the contact, strongest
## from a standstill and gone by a brisk walk, so pushing helps but never launches it.
func _push_rv(wished: Vector3, wish: Vector2) -> void:
	pushing = false
	if rv == null or wish == Vector2.ZERO:
		return
	for i: int in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col.get_collider() != rv:
			continue
		var dir := Vector3(wished.x, 0.0, wished.z).normalized()
		var into := -col.get_normal()
		if dir.dot(into) < 0.5:
			return
		var along := rv.point_velocity(col.get_position()).dot(dir)
		var fade := clampf(1.0 - along / PUSH_FADE_SPEED, 0.0, 1.0)
		rv.apply_force(dir * PUSH_FORCE * fade, col.get_position() - rv.global_position)
		pushing = fade > 0.0
		return


## The winch remote: hold Use to reel in, Throw to pay out (works from a seat too).
## Tools you hold the button down for (the drill): ticks while Use is held.
func _work_held_tool(dt: float) -> void:
	_tool_timer = maxf(0.0, _tool_timer - dt)
	if held == null or not input_enabled or downed or seat != &"" or not Input.is_action_pressed(&"use_item"):
		return
	var action := ItemLibrary.hold_action(held.kind)
	if action.is_valid() and _tool_timer <= 0.0:
		_tool_timer = action.call(held, self)


func _work_winch_remote() -> void:
	if rv == null or puppet:
		return
	var remote := held != null and held.kind == &"winch_remote" and input_enabled and not downed
	for i: int in rv.winches.size():
		var drive := 0
		if remote and i == winch_choice:
			if Input.is_action_pressed(&"use_item"):
				drive = -1
			elif Input.is_action_pressed(&"throw_item"):
				drive = 1
		if drive != _winch_sent[i]:
			_winch_sent[i] = drive
			rv.op(&"winch_drive", [i, peer_id, drive])


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
	if not inside or seat != &"" or on != rv or rv.seat_occupant(seat_name) != null:
		return
	if held and not held.def.get("seated", false):
		drop_held() # Hands free to drive (the winch remote can come along).
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
	var big := bool(item.def.get("two_handed", false))
	if held:
		if big or held.def.get("two_handed", false):
			return # Big things need a free hand.
		var free := slots.find(null)
		if free < 0:
			return
		select_slot(free)
	held = item
	item.grab(self, hand)
	item.visible = true


## Whether there's room to pick `item` up.
func can_pick_up(item: Item) -> bool:
	if held == null:
		return true
	if item.def.get("two_handed", false) or held.def.get("two_handed", false):
		return false
	return slots.has(null)


## Switches the hand to another slot (not while carrying something big).
func select_slot(i: int) -> void:
	if i == selected or (held and held.def.get("two_handed", false)):
		return
	if held:
		held.visible = false
	selected = i
	if held:
		held.visible = true


## The first pocketed (or held) item of a kind, or null.
func find_item(kind: StringName) -> Item:
	for it: Item in slots:
		if it and it.kind == kind:
			return it
	return null


## Uses up an item from the hotbar (scrap for a repair, an empty oil bottle...).
func consume(item: Item) -> void:
	var i := slots.find(item)
	if i >= 0:
		slots[i] = null
	item.queue_free()


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


func eat(item: Item, amount: float = 30.0) -> void:
	heal(amount)
	consume(item)


## A short message for the player (shown by the HUD for a few seconds).
func say(text: String) -> void:
	if puppet:
		_tell(&"say", [text])
		return
	message = text
	message_time = 4.0


## What of the RV the crosshair is on (see RVDamage.aim), within arm's reach.
func aim_rv() -> Dictionary:
	if rv == null or inside:
		return {}
	return rv.damage.aim(camera.global_position, -camera.global_basis.z, 2.8)


func _place_camera() -> void:
	var eye_height := lerpf(EYE_HEIGHT, DOWNED_EYE_HEIGHT if downed else CROUCH_EYE_HEIGHT, _crouch)
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
	if not input_enabled or seat != &"" or downed:
		return
	var eye := camera.global_position
	var forward := -camera.global_basis.z
	var best := -INF
	for node: Node in get_tree().get_nodes_in_group(&"interactable"):
		var n := node as Node3D
		if n == null or n == held or n == self or not n.is_visible_in_tree():
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
