extends Node
## Headless on-foot test, driven through the real input actions: the player spawns by the RV,
## can't walk through the shut door, opens it, walks in, walks to the driver's seat and sits,
## gets up, stays put inside while the RV drives, walks back out, and picks up, throws and
## stows items (stowed items ride along with the RV).
##
##   godot --headless --path game --fixed-fps 60 res://tests/player_foot.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _rv: RV
var _player: Player
var _failures: PackedStringArray = []


func _ready() -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	_run()


func _run() -> void:
	var waited := 0
	while not _pg.is_spawned:
		await get_tree().physics_frame
		waited += 1
		if waited > HZ * 60:
			_check(false, "spawned")
			_finish()
			return
	_rv = _pg.rv
	_player = _pg.player
	await _hold(1.5)
	_check(not _player.inside and _player.is_on_ground(), "starts on foot, on the ground")

	# Walk at the shut door: blocked.
	await _walk_to_world(_door_outside(0.3), 3.0)
	_check(not _player.inside, "the shut door blocks the way in")

	# Open it the way a player would: look at it, press Interact.
	_face(_rv.to_global(Vector3(_rv.interior.door_x_outer, _rv.interior.floor_y + 0.8, _door_z())))
	await _hold(0.2)
	_check(_player.target_prompt == "Open door", "looking at the door offers to open it (got '%s')" % _player.target_prompt)
	await _press(&"interact")
	_check(_rv.door_open, "Interact opened the door")
	_tracing = true
	_trace.clear()
	await _walk_to_world(_door_outside(-0.6), 3.0)
	_tracing = false
	_check(_player.inside, "walked in through the open door")
	_smooth(_trace, "walking in through the door")
	_check(not _player.is_in_transit(), "... and the walk in is over")

	# To the driver's seat and sit.
	var stand: Vector3 = _rv.seats[&"driver"]["stand"]
	await _walk_to_local(stand, 6.0)
	_face(_rv.to_global(_rv.seats[&"driver"]["eye"] + Vector3(0.0, -0.3, 0.0)))
	await _hold(0.2)
	_check(_player.target_prompt == "Drive", "at the driver's seat (prompt '%s', at %s)" % [_player.target_prompt, _player.local_position()])
	await _press(&"interact")
	_check(_player.is_driving() and _pg.driver.enabled and _pg.camera.current, "sitting in the driver's seat hands over the wheel")
	await _press(&"leave_seat")
	_check(not _player.is_driving() and not _pg.driver.enabled and _player.camera.current, "got up again")

	# Stand in the living area while the RV drives off.
	await _walk_to_local(Vector3(0.0, _rv.interior.floor_y, 0.6), 4.0)
	var local_before := _player.local_position()
	var rv_before := _rv.global_position
	_pg.driver.enabled = false
	_rv.set_automatic(true)
	_rv.throttle = 0.7
	await _hold(5.0)
	await _stop_rv()
	var travelled := _rv.global_position.distance_to(rv_before)
	var drift := _player.local_position().distance_to(local_before)
	_check(travelled > 8.0, "the RV drove (%.1f m)" % travelled)
	_check(_player.inside and _player.is_on_ground(), "still standing inside after the drive")
	_check(drift < 2.5, "barely moved inside the RV (%.2f m: a stumble when braking)" % drift)
	_check(_player.global_position.distance_to(_rv.to_global(_player.local_position())) < 0.25, "drawn where the RV is")

	# Walk out.
	_tracing = true
	_trace.clear()
	await _walk_to_local(Vector3(_rv.interior.door_x_outer + 1.5, _rv.interior.floor_y, _door_z()), 4.0)
	_tracing = false
	_check(not _player.inside, "walked out of the door")
	_smooth(_trace, "walking out through the door")
	await _hold(1.0)
	_check(_player.is_on_ground(), "landed outside")

	# Items: pick up the nearest loose one, throw it, then carry another inside and put it down.
	_check(_nearest_item() != null, "there are items lying around")
	# The starter items were left behind when the RV drove off; use a fresh one by the door.
	var item := ItemLibrary.create(&"scrap_metal")
	_pg.items.add_child(item)
	var drop_at := _rv.to_global(Vector3(_rv.interior.door_x_outer + 2.2, 0.0, _door_z() + 1.2))
	drop_at.y = _pg.world.height_at(drop_at.x, drop_at.z) + 0.4
	item.global_position = drop_at
	await _hold(1.0)
	if item:
		await _walk_to_world(item.global_position, 6.0, 1.3)
		_face(item.global_position)
		await _hold(0.2)
		_check(_player.target == item, "looking at the %s (prompt '%s')" % [item.display_name(), _player.target_prompt])
		await _press(&"interact")
		_check(_player.held == item, "picked it up")
		var held_at := item.global_position
		await _press(&"throw_item")
		await _hold(0.5)
		_check(_player.held == null and not item.freeze, "threw it")
		_check(item.global_position.distance_to(held_at) > 0.3, "it flew (%.2f m)" % item.global_position.distance_to(held_at))
		await _hold(2.0)
		await _walk_to_world(item.global_position, 6.0, 1.3)
		_face(item.global_position)
		await _hold(0.2)
		await _press(&"interact")
		_check(_player.held == item, "picked it up again")
		await _walk_to_door()
		_check(_player.inside, "carried it inside (at %s, RV-local)" % _rv.to_local(_player.global_position))
		await _press(&"drop_item")
		_check(item.get_parent() == _rv.stash and item.freeze, "put it down inside: it's in the RV's storage")
		var stored := item.transform
		_rv.throttle = 0.6
		await _hold(3.0)
		await _stop_rv()
		_check(item.get_parent() == _rv.stash and item.transform.origin.distance_to(stored.origin) < 0.001, "stored items ride along")
	_finish()


## Stops with a short stab of the brake, then holds on the handbrake. (Holding the brake at a
## standstill in automatic means "reverse", which is not what we want here.)
func _stop_rv() -> void:
	_rv.throttle = 0.0
	_rv.brake = 1.0
	await _hold(0.6)
	_rv.brake = 0.0
	_rv.handbrake = true
	await _hold(1.5)
	_rv.handbrake = false
	_rv.parking_brake = true # As when a driver gets out: the RV stays put.


## Walks round the RV (past its nose or tail if needed) to the door, and in.
func _walk_to_door() -> void:
	var local := _rv.to_local(_player.global_position)
	if local.x < _rv.interior.door_x_outer + 1.0:
		var end_z := -6.0 if local.z < 0.0 else 6.0
		await _walk_to_world(_rv.to_global(Vector3(local.x, 0.0, end_z)), 6.0, 0.6)
		await _walk_to_world(_rv.to_global(Vector3(4.0, 0.0, end_z)), 6.0, 0.6)
	await _walk_to_world(_door_outside(1.3), 6.0)
	await _walk_to_world(_door_outside(-0.6), 3.0)


## Where the view was each physics frame while `_tracing`.
var _trace: Array[Vector3] = []
var _tracing := false


func _physics_process(_dt: float) -> void:
	if _tracing and _player:
		_trace.append(_player.camera.global_position)


## The path has no jumps: the view never moved further than a brisk walk in one frame (the old
## teleport through the door was over a metre), and rises and drops at a walking pace too.
func _smooth(path: Array[Vector3], what: String) -> void:
	var worst := 0.0
	var worst_up := 0.0
	var total := 0.0
	for i: int in range(1, path.size()):
		var step := path[i].distance_to(path[i - 1])
		worst = maxf(worst, step)
		worst_up = maxf(worst_up, absf(path[i].y - path[i - 1].y))
		total += step
	_check(path.size() > 20 and worst < 0.12, "%s: no jump in the view (largest step %.3f m a frame, %d frames, %.1f m)" % [what, worst, path.size(), total])
	_check(worst_up < 0.05, "%s: rises and drops smoothly (largest %.3f m a frame)" % [what, worst_up])


func _door_z() -> float:
	return (_rv.interior.door_z.x + _rv.interior.door_z.y) * 0.5


## A world point `out` metres outside the middle of the door (negative: inside).
func _door_outside(out: float) -> Vector3:
	return _rv.to_global(Vector3(_rv.interior.door_x_outer + out, 0.0, _door_z()))


func _nearest_item() -> Item:
	var best: Item = null
	for n: Node in get_tree().get_nodes_in_group(&"items"):
		var it := n as Item
		if it and it.get_parent() == _pg.items and (best == null or
				it.global_position.distance_to(_player.global_position) < best.global_position.distance_to(_player.global_position)):
			best = it
	return best


## Points the view at a world point.
func _face(point: Vector3) -> void:
	var frame := _rv.global_basis if _player.inside else Basis.IDENTITY
	var eye := _player.camera.global_position
	var d := frame.inverse() * (point - eye)
	_player.look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))


## Steers with the move actions towards a world point until within `close` metres.
func _walk_to_world(point: Vector3, seconds: float, close: float = 0.25) -> void:
	seconds = maxf(seconds, _player.global_position.distance_to(point) / 3.0 + 2.0)
	for i: int in roundi(seconds * HZ):
		var here := _player.global_position
		var to := point - here
		to.y = 0.0
		if to.length() < close:
			break
		var frame := _rv.global_basis if _player.inside else Basis.IDENTITY
		var d := frame.inverse() * to
		_player.look(atan2(-d.x, -d.z), _player._pitch)
		Input.action_press(&"move_forward")
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	await _hold(0.3)


## Same, towards a point in RV space.
func _walk_to_local(local: Vector3, seconds: float) -> void:
	for i: int in roundi(seconds * HZ):
		var here := _player.local_position() if _player.inside else _rv.to_local(_player.global_position)
		var d := local - here
		d.y = 0.0
		if d.length() < 0.2:
			break
		if _player.inside:
			_player.look(atan2(-d.x, -d.z), _player._pitch)
		else:
			var w := _rv.global_basis * d
			_player.look(atan2(-w.x, -w.z), _player._pitch)
		Input.action_press(&"move_forward")
		await get_tree().physics_frame
	Input.action_release(&"move_forward")
	await _hold(0.3)


## Presses an action through the real input pipeline (reaches _unhandled_input).
func _press(action: StringName) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().physics_frame


func _hold(seconds: float) -> void:
	for i: int in roundi(seconds * HZ):
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("player foot: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
