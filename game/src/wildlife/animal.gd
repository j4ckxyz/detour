class_name Animal
extends Node3D
## Base for the wildlife (PLAN.md §4.5): walks on the terrain's heightfield (no physics body,
## so animals work anywhere the world exists, streamed collision or not), finds players out in
## the open, and gets scared off by bear spray and a moving RV. Players inside the RV are safe.

## The RV scares animals off when it comes this close (m) moving faster than this (m/s).
const RV_SCARE_RADIUS := 7.0
const RV_SCARE_SPEED := 3.0

var world: WorldGen
var rv: RV
## Where dropped things go (the eagle lets go of what it stole).
var world_items: Node
## Where it lives; it wanders around here and comes back here.
var home := Vector3.ZERO
var state := 0
var state_time := 0.0
var yaw := 0.0
## Current ground speed (m/s), for the walk animation.
var speed := 0.0
var rng := RandomNumberGenerator.new()
## What it's after.
var target: Player
## Online, on clients: follows the host's snapshots instead of thinking; bear spray is sent
## to the host through `remote_spray` (`func(animal: Animal, from: Vector3)`).
var puppet := false
var remote_spray: Callable
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0

var _stride := 0.0


func _ready() -> void:
	add_to_group(&"wildlife")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()


## Builds the look (placeholder low-poly shapes, to be swapped for models later).
func _build() -> void:
	pass


## Called by bear spray: `from` is where the spray came from.
func sprayed(_from: Vector3) -> void:
	pass


## Bear spray hit it (sent on to the host if this is a copy).
func spray_from(from: Vector3) -> void:
	if puppet and remote_spray.is_valid():
		remote_spray.call(self, from)
	else:
		sprayed(from)


## What it does each physics tick (the host, or solo).
func think(_dt: float) -> void:
	pass


func _physics_process(dt: float) -> void:
	if puppet:
		state_time += dt
		global_position = global_position.lerp(_net_pos, minf(1.0, dt * 10.0))
		yaw = lerp_angle(yaw, _net_yaw, minf(1.0, dt * 10.0))
		basis = Basis(Vector3.UP, yaw)
	else:
		think(dt)


func net_state() -> Array:
	return [global_position, yaw, state, speed, target.peer_id if is_instance_valid(target) else 0]


func apply_net_state(s: Array, find_player: Callable) -> void:
	_net_pos = s[0]
	_net_yaw = s[1]
	if int(s[2]) != state:
		set_state(s[2])
	speed = s[3]
	target = find_player.call(int(s[4])) if int(s[4]) != 0 else null


func set_state(s: int) -> void:
	state = s
	state_time = 0.0


func ground_at(p: Vector3) -> float:
	return world.height_at(p.x, p.z)


## Players out in the open (not in the RV, not down) within `radius`, crouching ones only
## within `radius * crouch_factor`. Nearest first; null if none.
func nearest_player(radius: float, crouch_factor: float = 1.0) -> Player:
	var best: Player = null
	var best_d := INF
	for n: Node in get_tree().get_nodes_in_group(&"players"):
		var p := n as Player
		if not is_exposed(p):
			continue
		var r := radius * (crouch_factor if p.is_crouching() else 1.0)
		var d := flat_distance(p.global_position)
		if d < r and d < best_d:
			best = p
			best_d = d
	return best


static func is_exposed(p: Player) -> bool:
	return is_instance_valid(p) and p.is_inside_tree() and not p.inside and not p.downed


func flat_distance(to: Vector3) -> float:
	return Vector2(to.x - global_position.x, to.z - global_position.z).length()


## Turns towards and walks at `rate` m/s to `point` on the ground; true once within `close`.
func go_to(point: Vector3, rate: float, dt: float, close: float = 0.5) -> bool:
	var to := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	var d := to.length()
	if d <= close:
		speed = 0.0
		return true
	turn_towards(point, dt)
	var step := minf(rate * dt, d - close * 0.5)
	var ahead := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	# Walk where it faces (turning while moving looks like an animal, not a sliding box).
	var p := global_position + ahead * step * clampf(ahead.dot(to / d) * 1.5, 0.2, 1.0)
	p.y = ground_at(p)
	speed = rate
	global_position = p
	_face()
	return false


func turn_towards(point: Vector3, dt: float, rate: float = 4.0) -> void:
	var to := point - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	var want := atan2(-to.x, -to.z)
	yaw = rotate_toward(yaw, want, rate * dt)
	_face()


func _face() -> void:
	# Follow the slope a little, like a real animal on a hillside.
	var ahead := Basis(Vector3.UP, yaw) * Vector3.FORWARD
	var p := global_position
	var pitch := atan2(ground_at(p + ahead * 0.8) - ground_at(p - ahead * 0.8), 1.6)
	basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, clampf(pitch, -0.5, 0.5))


## True if the RV is bearing down on it.
func rv_scare() -> bool:
	if rv == null or rv.linear_velocity.length() < RV_SCARE_SPEED:
		return false
	return rv.global_position.distance_to(global_position) < RV_SCARE_RADIUS + 3.0


## A random point on the ground within `radius` of `around`.
func random_point(around: Vector3, radius: float) -> Vector3:
	var a := rng.randf() * TAU
	var r := sqrt(rng.randf()) * radius
	var p := around + Vector3(cos(a), 0.0, sin(a)) * r
	p.y = ground_at(p)
	return p


## Point `dist` metres directly away from `from`.
func away_from(from: Vector3, dist: float) -> Vector3:
	var d := global_position - from
	d.y = 0.0
	if d.length() < 0.1:
		d = Basis(Vector3.UP, yaw) * Vector3.BACK
	var p := global_position + d.normalized() * dist
	p.y = ground_at(p)
	return p


## Leg phase for the walk animation (radians), advanced by speed.
func stride(dt: float, per_metre: float) -> float:
	_stride = fmod(_stride + speed * dt * per_metre, TAU)
	return _stride


## A low-poly box part for the placeholder bodies.
static func part(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


## A pivot (to swing a leg or a wing from) with a box hanging off it.
static func limb(parent: Node3D, pivot: Vector3, size: Vector3, offset: Vector3, color: Color) -> Node3D:
	var joint := Node3D.new()
	joint.position = pivot
	parent.add_child(joint)
	part(joint, size, offset, color)
	return joint
