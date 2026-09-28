class_name RVInterior
extends SubViewport
## The inside of the RV as its own small physics world, in RV space (PLAN.md §6.3).
##
## A player inside the RV walks around in here, against a static copy of the interior at the
## origin, and is drawn at `rv.global_transform * local`. Standing in a moving, bouncing RV is
## then exactly as stable as standing in a parked one; the RV's motion only reaches players
## through gravity and a little fake inertia (see `Player`).
##
## Never rendered: the SubViewport only exists to own a separate World3D (physics space).

## The door opening in RV space: x from the inner wall to the outer skin, z along the side.
var door_x_inner := 0.0
var door_x_outer := 0.0
var door_z := Vector2.ZERO # (min, max)
var door_top := 0.0
## Top of the living-area floor, RV space.
var floor_y := 0.0

var _body := StaticBody3D.new()
var _door_blocker := CollisionShape3D.new()


func _init() -> void:
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	size = Vector2i(4, 4)
	name = "Interior"


## Builds the interior from the `Interior_*` boxes in the RV's collision scene.
func build(collision_scene: PackedScene) -> void:
	add_child(_body)
	var source := collision_scene.instantiate()
	var boxes: Dictionary[String, AABB] = {}
	for node: Node in source.find_children("Interior_*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var aabb := mi.transform * mi.mesh.get_aabb()
		boxes[String(mi.name)] = aabb
		_add_box(aabb)
	source.free()

	var above: AABB = boxes["Interior_WallR_AboveDoor"]
	var floor_box: AABB = boxes["Interior_Floor"]
	door_x_inner = above.position.x
	door_x_outer = above.end.x
	door_z = Vector2(above.position.z, above.end.z)
	door_top = above.position.y
	floor_y = floor_box.end.y
	# Fills the doorway while the door is shut.
	var shut := AABB(Vector3(door_x_inner, floor_y, door_z.x), Vector3(door_x_outer - door_x_inner, door_top - floor_y, door_z.y - door_z.x))
	var box := BoxShape3D.new()
	box.size = shut.size
	_door_blocker.shape = box
	_door_blocker.position = shut.get_center()
	_body.add_child(_door_blocker)


func set_door_open(open: bool) -> void:
	_door_blocker.set_deferred(&"disabled", open)


## Whether an RV-space point is in the doorway (between the inner wall and just outside).
func in_doorway(local: Vector3, outside_margin: float) -> bool:
	return local.x > door_x_inner - 0.1 and local.x < door_x_outer + outside_margin \
		and local.z > door_z.x + 0.1 and local.z < door_z.y - 0.1


## Where to stand just inside the door (RV space).
func inside_door() -> Vector3:
	return Vector3(door_x_inner - 0.35, floor_y + 0.05, (door_z.x + door_z.y) * 0.5)


func space_state() -> PhysicsDirectSpaceState3D:
	return find_world_3d().direct_space_state # own_world_3d: `world_3d` stays null.


func _add_box(aabb: AABB) -> void:
	var box := BoxShape3D.new()
	box.size = aabb.size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = aabb.get_center()
	_body.add_child(shape)
