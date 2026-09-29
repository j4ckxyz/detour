class_name Item
extends RigidBody3D
## A physical thing in the world the player can pick up, carry, use, drop and throw.
## Items put down inside the RV are frozen onto its `stash`, so they ride along (the RV's
## storage). Kinds and their data are in `ItemLibrary`.

## Physics layer of loose items.
const LAYER := 4

var kind: StringName
var def: Dictionary
## Who is holding it (null when it's loose or stashed).
var holder: Player
## Height of the model's origin above its lowest point, for setting it down.
var base_offset := 0.0
## Online: the same number for this item on every machine (0 until the host numbers it).
var net_id := 0

## Online, set by `NetGame`: told about every item that appears and every one freed.
static var on_ready: Callable
static var on_freed: Callable


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"items")
	collision_layer = LAYER
	collision_mask = TerrainStreamer.WORLD_LAYER | RV.VEHICLE_LAYER | LAYER
	continuous_cd = true
	if on_ready.is_valid():
		on_ready.call(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and net_id != 0 and on_freed.is_valid():
		on_freed.call(net_id)


func display_name() -> String:
	return def.get("name", String(kind))


func interact_prompt(player: Player) -> String:
	if holder != null:
		return ""
	var winch := winch_of()
	if winch:
		if winch.state == RVWinch.State.STOWED:
			return "" # The drum's own prompt handles it.
		if player.held == null and winch.state == RVWinch.State.ANCHORED:
			return "Unhook the %s winch" % winch.label
	if not player.can_pick_up(self):
		return "Hands full (%s)" % player.held.display_name()
	return "Pick up %s" % display_name()


func interact(player: Player) -> void:
	if holder == null and player.can_pick_up(self):
		player.pick_up(self)


func interact_reach() -> float:
	return def.get("reach", 2.4)


## Called by the holder's Use button. Returns true if something happened.
func use(player: Player) -> bool:
	var action := ItemLibrary.use_action(kind)
	return action.is_valid() and action.call(self, player)


## The winch this item is the hook of, if it is one.
func winch_of() -> RVWinch:
	return get_meta(&"winch") if has_meta(&"winch") else null


func is_placed() -> bool:
	return get_meta(&"placed", false)


## Takes the item into a hand (frozen, no collision) under `hand`.
func grab(player: Player, hand: Node3D) -> void:
	set_meta(&"placed", false)
	if winch_of():
		winch_of().on_hook_grabbed()
	holder = player
	freeze = true
	collision_layer = 0
	collision_mask = 0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	reparent(hand, false)
	transform = def.get("hold", Transform3D(Basis.IDENTITY, Vector3(0.25, -0.25, -0.55)))


## Lets go into the world at `xf` with `velocity` (dropping or throwing).
func release(world_parent: Node, xf: Transform3D, velocity: Vector3) -> void:
	holder = null
	reparent(world_parent, false)
	global_transform = xf
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	reset_physics_interpolation()
	collision_layer = LAYER
	collision_mask = TerrainStreamer.WORLD_LAYER | RV.VEHICLE_LAYER | LAYER
	freeze = false
	linear_velocity = velocity
	angular_velocity = Vector3.ZERO
	if winch_of():
		winch_of().on_hook_released()


## Sets the item down as solid ground (a plank bridge or ramp): static, on the world layer
## so the RV's wheels and players ride on it.
func place(parent: Node, xf: Transform3D) -> void:
	holder = null
	reparent(parent, false)
	global_transform = xf
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	reset_physics_interpolation()
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = TerrainStreamer.WORLD_LAYER
	collision_mask = 0
	set_meta(&"placed", true)


## Puts the item down inside the RV at `local` (RV space), where it rides along frozen.
func stow(rv: RV, local: Transform3D) -> void:
	holder = null
	reparent(rv.stash, false)
	transform = local
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	reset_physics_interpolation()
	freeze = true
	collision_layer = 0 # Inside the hull; the RV must never collide with its own cargo.
	collision_mask = 0
