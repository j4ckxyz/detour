extends Node
## Headless test of the RV's physical problem-solving tools, through real input actions:
## take the front winch hook, hook it onto a rock or tree, reel the RV in with the remote and
## pay out again; place a plank as solid ground; push the RV by walking into it.
##
##   godot --headless --path game --fixed-fps 60 res://tests/winch_plank_push.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")

var _pg: Playground
var _rv: RV
var _player: Player
var _w: Walker
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
		if waited > 3600:
			_check(false, "spawned")
			_finish()
			return
	_rv = _pg.rv
	_player = _pg.player
	_w = Walker.new(get_tree(), _player, _rv)
	await _w.hold(1.0)
	await _winch()
	await _plank()
	await _push()
	_finish()


func _winch() -> void:
	var winch: RVWinch = _rv.winches[0]
	# Walk round to the front winch and take the hook.
	await _w.walk_to(_rv.to_global(Vector3(2.5, 0.0, -5.5)), 0.4)
	await _w.walk_to(_rv.to_global(Vector3(0.0, 0.0, -5.2)), 0.3)
	_w.face(winch.global_position)
	await _w.hold(0.2)
	_check(_player.target_prompt == "Take the front winch hook", "front winch offers its hook (got '%s')" % _player.target_prompt)
	await _w.press(&"interact")
	_check(_player.held == winch.hook and winch.state == RVWinch.State.HELD, "holding the front hook")

	# Find something to hook onto ahead of the RV, and go there (the test teleports: the
	# forest in between is not what this test is about).
	var anchor: Variant = _find_anchor_ahead()
	_check(anchor != null, "a tree or rock ahead of the RV")
	if anchor == null:
		return
	var target: Vector3 = anchor
	var toward := (_rv.global_position - target)
	toward.y = 0.0
	var stand := target + toward.normalized() * 1.6
	stand.y = _pg.world.height_at(stand.x, stand.z) + 0.2
	if stand.distance_to(winch.global_position) > RVWinch.MAX_ROPE - 2.0:
		_check(false, "anchor within rope reach (%.1f m)" % stand.distance_to(winch.global_position))
		return
	_player.global_position = stand
	_player.reset_physics_interpolation()
	await _w.hold(0.5)
	_w.face(target + Vector3.UP * 0.3)
	await _w.hold(0.2)
	_check(ItemLibrary.find_anchor(_player) != null, "looking at the anchor (hint '%s')" % ItemLibrary.use_hint(winch.hook, _player))
	await _w.press(&"use_item")
	_check(winch.is_anchored() and _player.held == null, "hooked on")

	# Free the RV to roll (neutral, brakes off) and fetch the remote from the dash.
	_rv.parking_brake = false
	_rv.drivetrain.clutch_pedal = 1.0
	var remote: Item = null
	for n: Node in _rv.stash.get_children():
		if n is Item and (n as Item).kind == &"winch_remote":
			remote = n
	_check(remote != null, "the remote is in the RV")
	if remote == null:
		return
	_player.pick_up(remote)
	_player.winch_choice = 0
	var before := _rv.to_global(winch.position).distance_to(target)
	var rope_before := winch.rope_length
	var peak := 0.0
	Input.action_press(&"use_item")
	for i: int in 60 * 10:
		await get_tree().physics_frame
		peak = maxf(peak, winch.tension)
	Input.action_release(&"use_item")
	var after := winch.mount_position().distance_to(target)
	_check(winch.rope_length < rope_before - 2.0, "reeled in rope (%.1f → %.1f m)" % [rope_before, winch.rope_length])
	_check(after < before - 1.5, "the winch pulled the RV towards the anchor (%.1f → %.1f m)" % [before, after])
	_check(peak > 1000.0 and peak < RVWinch.SNAP_TENSION, "the rope took the load (peak %.0f N)" % peak)
	await _w.hold_action(&"throw_item", 2.0)
	_check(winch.rope_length > rope_before - 2.0 - 5.0 and winch.state == RVWinch.State.ANCHORED, "paid out again (%.1f m)" % winch.rope_length)
	_rv.parking_brake = true
	_player.held = null
	remote.stow(_rv, Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.34, -2.35))) # Back on the dash.
	winch.stow_hook() # Rope back on the drum, so the next phases start clean.


func _plank() -> void:
	var plank := ItemLibrary.create(&"plank")
	_pg.items.add_child(plank)
	plank.global_position = _player.global_position + Vector3.UP
	await _w.hold(0.1)
	_player.pick_up(plank)
	var ahead := _player.global_position + (Basis(Vector3.UP, _player._yaw) * Vector3.FORWARD) * 2.5
	ahead.y = _pg.world.height_at(ahead.x, ahead.z)
	_w.face(ahead)
	await _w.hold(0.2)
	_check(ItemLibrary.plank_placement(_player) != null, "a spot for the plank ahead")
	await _w.press(&"use_item")
	_check(plank.is_placed() and plank.collision_layer == TerrainStreamer.WORLD_LAYER, "plank placed as solid ground")
	var probe := PhysicsRayQueryParameters3D.create(plank.global_position + Vector3.UP * 2.0, plank.global_position + Vector3.DOWN)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(probe)
	_check(not hit.is_empty() and hit["collider"] == plank, "the placed plank is what's underfoot (hit %s)" % (hit.get("collider") if hit else "nothing"))
	_w.face(plank.global_position)
	await _w.hold(0.2)
	await _w.press(&"interact")
	_check(_player.held == plank and not plank.is_placed(), "picked the plank back up (target %s prompt '%s' dist %.2f)" % [_player.target, _player.target_prompt, _player.camera.global_position.distance_to(plank.global_position)])
	_player.drop_held()


func _push() -> void:
	# Stand behind the RV and walk into it, towards its nose.
	var winch: RVWinch = _rv.winches[0]
	if winch.is_anchored():
		winch.rope_length = RVWinch.MAX_ROPE # Slack, so it doesn't hold the RV back.
	_rv.parking_brake = false
	_rv.drivetrain.shift_to(0)
	await _w.walk_to(_rv.to_global(Vector3(2.6, 0.0, 6.0)), 0.4)
	await _w.walk_to(_rv.to_global(Vector3(0.3, 0.0, 5.3)), 0.3)
	var start := _rv.global_position
	var pushed := false
	for i: int in 60 * 4:
		var d := _rv.global_basis * Vector3.FORWARD
		_player.look(atan2(-d.x, -d.z), 0.0)
		Input.action_press(&"move_forward")
		await get_tree().physics_frame
		pushed = pushed or _player.pushing
	Input.action_release(&"move_forward")
	var moved := _rv.global_position.distance_to(start)
	_check(pushed, "walking into the RV pushes it")
	_check(moved > 0.3, "the RV rolled when pushed (%.2f m)" % moved)
	_rv.parking_brake = true


func _find_anchor_ahead() -> Variant:
	var space := _rv.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = 30.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = TerrainStreamer.WORLD_LAYER
	q.transform = Transform3D(Basis.IDENTITY, _rv.global_position)
	var best: Variant = null
	var best_d := INF
	for hit: Dictionary in space.intersect_shape(q, 256):
		var body := hit["collider"] as StaticBody3D
		var shape := int(hit["shape"])
		if body == null or shape == TerrainStreamer.GROUND_SHAPE:
			continue
		var owner := body.shape_find_owner(shape)
		var p := body.to_global(body.shape_owner_get_transform(owner).origin)
		var local := _rv.to_local(p)
		var d := p.distance_to(_rv.global_position)
		if local.z < -8.0 and d < best_d and d < RVWinch.MAX_ROPE - 4.0:
			best = p
			best_d = d
	return best


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("winch/plank/push: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
