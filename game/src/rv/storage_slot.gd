class_name StorageSlot
extends Interactable
## A place on or in the RV where one item belongs (PLAN.md §4.2, RV storage): the plank rack
## down the side, the spare-tire mount and jerry-can holders at the back, the tool wall,
## the top of the fridge, the overhead shelf, the bed and the cup holders. Hold a fitting item
## and press Interact to put it there; it rides along until someone picks it up again.
##
## The slot's transform (RV space) is where the item sits; `turn` rotates the item into place.

## Item storage kinds this slot takes (see ItemLibrary.DEFS "stow").
var accepts: Array[StringName] = []
## What it's called in the prompt ("plank rack").
var label := ""
var turn := Basis.IDENTITY
var rv: RV


func _ready() -> void:
	super._ready()
	reach = 1.9
	prompt_for = _prompt
	used.connect(_store_held)


func fits(item: Item) -> bool:
	return item != null and accepts.has(StringName(item.def.get("stow", &"")))


## The item stored here, or null.
func stored() -> Item:
	for c: Node in rv.stash.get_children():
		var item := c as Item
		if item and item.get_meta(&"slot", &"") == name:
			return item
	return null


func _prompt(player: Player) -> String:
	if not fits(player.held) or stored() != null:
		return ""
	return "Put the %s in the %s" % [player.held.display_name().to_lower(), label]


func _store_held(player: Player) -> void:
	if not fits(player.held) or stored() != null:
		return
	var item := player.held
	player.held = null
	store(item)


## Puts `item` here (the player's hand, the starter kit, a save being loaded).
func store(item: Item) -> void:
	item.stow(rv, Transform3D(transform.basis * turn, transform.origin + transform.basis * turn * Vector3.UP * item.base_offset))
	item.set_meta(&"slot", name)
