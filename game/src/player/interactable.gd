class_name Interactable
extends Node3D
## Something the on-foot player can use by looking at it and pressing Interact (E): a door,
## a seat, a winch drum. Items implement the same three methods themselves.
##
## Anything in the "interactable" group must have `interact_prompt(player) -> String` ("" to
## hide), `interact(player)` and `interact_reach() -> float`.

signal used(player: Player)

@export var prompt := "Use"
@export var reach := 2.0
## Optional `func(player: Player) -> String`, for prompts that change ("Open"/"Close").
var prompt_for: Callable


func _ready() -> void:
	add_to_group(&"interactable")


func interact_prompt(player: Player) -> String:
	return prompt_for.call(player) if prompt_for.is_valid() else prompt


func interact(player: Player) -> void:
	used.emit(player)


func interact_reach() -> float:
	return reach
