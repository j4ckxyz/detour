class_name Eagle
extends Animal
## An eagle circling overhead. It dives at anyone out in the open holding something small and
## tasty (food, or a little medical item), snatches it with a scratch, flies off and drops it
## somewhere a long walk away. Bear spray at it as it comes in makes it veer off.

enum State { CIRCLE, DIVE, CARRY, CLIMB }

const CIRCLE_RADIUS := 16.0
const CIRCLE_HEIGHT := 22.0
const CIRCLE_SPEED := 9.0
const SPOT_RADIUS := 35.0
const DIVE_SPEED := 17.0
const CARRY_SPEED := 11.0
const SCRATCH := 5.0
## Seconds between tries, and after a successful snatch.
const PATIENCE := 8.0
const REST := 45.0

var _angle := 0.0
var _cooldown := 4.0
var _carrying: Item
var _drop_at := Vector3.ZERO
var _wings: Array[Node3D] = []


func _build() -> void:
	var brown := Color(0.3, 0.2, 0.12)
	part(self, Vector3(0.3, 0.26, 0.8), Vector3.ZERO, brown)
	part(self, Vector3(0.2, 0.2, 0.22), Vector3(0.0, 0.08, -0.46), Color(0.95, 0.95, 0.92)) # White head.
	part(self, Vector3(0.07, 0.07, 0.12), Vector3(0.0, 0.05, -0.62), Color(0.95, 0.75, 0.1)) # Beak.
	part(self, Vector3(0.36, 0.05, 0.25), Vector3(0.0, 0.0, 0.5), Color(0.95, 0.95, 0.92)) # Tail.
	for side: float in [-1.0, 1.0]:
		_wings.append(limb(self, Vector3(0.15 * side, 0.05, 0.0), Vector3(1.1, 0.05, 0.42), Vector3(0.55 * side, 0.0, 0.0), brown))
	_angle = rng.randf() * TAU
	global_position = _circle_point()


## Whether a held item is something an eagle would go for.
static func tempting(item: Item) -> bool:
	return item != null and item.mass <= 0.5 and not item.def.get("no_throw", false)


func sprayed(_from: Vector3) -> void:
	if state == State.DIVE or state == State.CARRY:
		_let_go()
		_cooldown = REST * 0.5
		set_state(State.CLIMB)


func _circle_point() -> Vector3:
	var p := home + Vector3(cos(_angle), 0.0, sin(_angle)) * CIRCLE_RADIUS
	p.y = ground_at(home) + CIRCLE_HEIGHT
	return p


func think(dt: float) -> void:
	state_time += dt
	_cooldown = maxf(0.0, _cooldown - dt)
	match state:
		State.CIRCLE:
			_angle = wrapf(_angle + CIRCLE_SPEED / CIRCLE_RADIUS * dt, 0.0, TAU)
			_fly_to(_circle_point(), CIRCLE_SPEED * 1.5, dt)
			if _cooldown <= 0.0:
				_cooldown = PATIENCE
				var p := nearest_player(SPOT_RADIUS)
				if p and tempting(p.held):
					target = p
					set_state(State.DIVE)
		State.DIVE:
			if not is_exposed(target) or not tempting(target.held) or state_time > 8.0:
				set_state(State.CLIMB)
				return
			var hand := target.hand.global_position
			_fly_to(hand, DIVE_SPEED, dt)
			if global_position.distance_to(hand) < 1.0:
				_snatch()
		State.CARRY:
			var arrived := _fly_to(_drop_at, CARRY_SPEED, dt)
			if arrived or state_time > 15.0:
				_let_go()
				_cooldown = REST
				set_state(State.CLIMB)
		State.CLIMB:
			if _fly_to(_circle_point(), CIRCLE_SPEED * 1.5, dt, 3.0):
				set_state(State.CIRCLE)


## Holds `item` in its talons (a copy of what the host's eagle did).
func carry(item: Item) -> void:
	item.holder = null
	item.reparent(self, false)
	item.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.3, 0.0))
	item.freeze = true
	item.collision_layer = 0
	item.collision_mask = 0
	_carrying = item


func _snatch() -> void:
	var item := target.held
	target.held = null
	carry(item)
	target.hurt(SCRATCH, "scratched by an eagle")
	target.say("An eagle took your %s!" % item.display_name().to_lower())
	var a := rng.randf() * TAU
	_drop_at = global_position + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(60.0, 90.0)
	_drop_at.y = ground_at(_drop_at) + 12.0
	set_state(State.CARRY)


func _let_go() -> void:
	if not is_instance_valid(_carrying):
		_carrying = null
		return
	var parent := world_items if world_items else get_parent()
	_carrying.release(parent, _carrying.global_transform, Basis(Vector3.UP, yaw) * Vector3.FORWARD * 3.0)
	_carrying = null


## Flies straight at `point`; true once within `close`.
func _on_state(s: int) -> void:
	if s == State.DIVE:
		Sfx.cue(self, "wildlife/eagle_screech", global_position, 0.0, 16.0, 160.0)


func _fly_to(point: Vector3, rate: float, dt: float, close: float = 0.3) -> bool:
	var to := point - global_position
	var d := to.length()
	if d <= close:
		return true
	var step := to / d * minf(rate * dt, d)
	var p := global_position + step
	p.y = maxf(p.y, ground_at(p) + 0.8)
	speed = rate
	global_position = p
	var flat := Vector2(to.x, to.z)
	if flat.length() > 0.05:
		yaw = rotate_toward(yaw, atan2(-to.x, -to.z), 3.0 * dt)
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, clampf(-to.y / maxf(d, 0.1), -0.8, 0.8))
	return false


func _process(dt: float) -> void:
	var flap := 0.0
	var phase := stride(dt, 0.9 if state == State.CARRY or state == State.CLIMB else 0.35)
	if state != State.DIVE:
		flap = sin(phase) * 0.5
	for i: int in _wings.size():
		_wings[i].rotation.z = flap * (1.0 if i == 0 else -1.0) + (0.4 if state == State.DIVE else 0.0) * (-1.0 if i == 0 else 1.0)
