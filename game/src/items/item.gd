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


func _ready() -> void:
	add_to_group(&"interactable")
	add_to_group(&"items")
	collision_layer = LAYER
	collision_mask = TerrainStreamer.WORLD_LAYER | RV.VEHICLE_LAYER | LAYER
	continuous_cd = true


func display_name() -> String:
	return def.get("name", String(kind))


func interact_prompt(player: Player) -> String:
	if holder != null:
		return ""
	if player.held != null:
		return "Hands full (%s)" % player.held.display_name()
	return "Pick up %s" % display_name()


func interact(player: Player) -> void:
	if holder == null and player.held == null:
		player.pick_up(self)


func interact_reach() -> float:
	return 2.4


## Called by the holder's Use button. Returns true if something happened.
func use(player: Player) -> bool:
	var action := ItemLibrary.use_action(kind)
	return action.is_valid() and action.call(self, player)


## Takes the item into a hand (frozen, no collision) under `hand`.
func grab(player: Player, hand: Node3D) -> void:
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
