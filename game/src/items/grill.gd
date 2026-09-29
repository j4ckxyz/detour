class_name Grill
extends Interactable
## Somewhere to cook frozen patties: the RV's stove, the camp fire, a gas station's grill.
## Hold a patty and press Interact to put it on; it thaws, cooks, then burns (see
## ItemLibrary.PATTY_*). Take it off again like any item.

## Where patties sit, local to the grill (its top surface at y = 0).
const SPOTS: Array[Vector3] = [Vector3(0.0, 0.0, -0.13), Vector3(0.0, 0.0, 0.13)]

var _on: Array[Item] = [null, null]


func _ready() -> void:
	super._ready()
	reach = 2.2
	prompt_for = _prompt
	used.connect(_put_on)


func _prompt(player: Player) -> String:
	if player.held == null or player.held.kind != &"patty":
		return "" # Leaves the crosshair to the patties on it.
	return "Put the patty on to cook" if _on.has(null) else "The grill's full"


func _put_on(player: Player) -> void:
	var i := _on.find(null)
	if player.held == null or player.held.kind != &"patty" or i < 0:
		return
	var patty := player.held
	player.held = null
	patty.holder = null
	patty.reparent(self, false)
	patty.transform = Transform3D(Basis.IDENTITY, SPOTS[i])
	patty.freeze = true
	patty.collision_layer = 0
	patty.collision_mask = 0
	patty.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
	patty.reset_physics_interpolation()
	_on[i] = patty


## Whether anything's cooking.
func is_cooking() -> bool:
	return _on.any(func(it: Item) -> bool: return it != null)


func _physics_process(dt: float) -> void:
	for i: int in _on.size():
		var patty := _on[i]
		if patty == null:
			continue
		if not is_instance_valid(patty) or patty.get_parent() != self:
			_on[i] = null # Taken off (picked up).
			continue
		var cook := float(patty.get_meta(&"cook", 0.0)) + dt
		patty.set_meta(&"cook", cook)
		patty.def["name"] = ItemLibrary.patty_name(cook)
		ItemLibrary.tint(patty, ItemLibrary.patty_color(cook))
