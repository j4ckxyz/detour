extends RefCounted
## Drives a Player through the real input actions for scene tests: walk to points, look at
## things, press buttons, wait.

const HZ := 60

var tree: SceneTree
var player: Player
var rv: RV


func _init(scene_tree: SceneTree, p: Player, r: RV) -> void:
	tree = scene_tree
	player = p
	rv = r


func hold(seconds: float) -> void:
	for i: int in roundi(seconds * HZ):
		await tree.physics_frame


## Points the view at a world point.
func face(point: Vector3) -> void:
	var frame := rv.global_basis if player.inside else Basis.IDENTITY
	var d := frame.inverse() * (point - player.camera.global_position)
	player.look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


## Steers with the move actions towards a world point until within `close` metres.
func walk_to(point: Vector3, close: float = 0.25) -> void:
	var seconds := player.global_position.distance_to(point) / 3.0 + 2.0
	for i: int in roundi(seconds * HZ):
		var to := point - player.global_position
		to.y = 0.0
		if to.length() < close:
			break
		var frame := rv.global_basis if player.inside else Basis.IDENTITY
		var d := frame.inverse() * to
		player.look(atan2(-d.x, -d.z), player._pitch)
		Input.action_press(&"move_forward")
		await tree.physics_frame
	Input.action_release(&"move_forward")
	await hold(0.3)


## Presses an action through the real input pipeline (reaches _unhandled_input).
func press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await tree.process_frame
	await tree.process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await tree.physics_frame


## Holds an action down for `seconds`.
func hold_action(action: StringName, seconds: float) -> void:
	Input.action_press(action)
	await hold(seconds)
	Input.action_release(action)
