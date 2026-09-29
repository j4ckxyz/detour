extends Node
## Two-player co-op test over real ENet on localhost: this process joins as a client and
## starts a second Godot process as the host (the same scene with `--coop-role=host`). The
## client drives the test and asks the host about its side through RPCs on this node (which
## has the same path in both processes).
##
## Checks: joining gets the host's seed and roster; each side sees the other's player move;
## the host's items appear on the client; picking up and dropping items shows on the host;
## taking the wheel hands the RV's simulation to the client and the host follows it;
## getting up hands it back; a part knocked off on the host shows on the client, which
## patches it through the RV's owner; the winch hook and the door sync; the host's snake
## bites the client; leaving removes the client's player on the host.
##
##   godot --headless --path game --fixed-fps 60 res://tests/coop.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const SEED := "DT5-00000-000ZG"
const TIMEOUT := 100.0

var _host_role := false
var _port := 0
var _pg: Playground
var _failures: PackedStringArray = []
var _host_pipe: FileAccess
var _host_pid := -1
var _host_output := ""
var _answers: Dictionary = {}
var _started := 0
var _joined := false
var _frame_start := 0


func _ready() -> void:
	_started = Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--coop-role=host":
			_host_role = true
		elif arg.begins_with("--port="):
			_port = int(arg.substr(7))
	if _host_role:
		_run_host()
	else:
		_run_client()


func _process(_dt: float) -> void:
	# Run in real time (--fixed-fps turns that off): two processes talk over the network.
	var spent := Time.get_ticks_usec() - _frame_start
	if spent < 16667:
		OS.delay_usec(16667 - spent)
	_frame_start = Time.get_ticks_usec()
	if Time.get_ticks_msec() - _started > TIMEOUT * 1000.0:
		print("coop %s: timed out" % ("host" if _host_role else "client"))
		_fail_now("timed out")
	if _host_pipe:
		_read_host()


func _read_host() -> void:
	var chunk := _host_pipe.get_buffer(65536)
	while chunk.size() > 0:
		_host_output += chunk.get_string_from_utf8()
		chunk = _host_pipe.get_buffer(65536)


# --- host side -------------------------------------------------------------------------------

func _run_host() -> void:
	Session.seed_code = SEED
	Session.player_name = "Hosty"
	var err := Session.host_direct(_port, false, "127.0.0.1")
	if err != OK:
		print("coop host: can't host: ", error_string(err))
		get_tree().quit(1)
		return
	_add_playground()
	Session.player_left.connect(func(_peer: int) -> void:
		await get_tree().create_timer(1.0).timeout
		var gone := _pg.net.puppets.is_empty()
		print("coop host: %s" % ("all checks passed" if gone else "FAIL: the client's player is still there"))
		get_tree().quit(0 if gone else 1))


## The client asks; the host does it and answers with `_answer(key, value)`.
@rpc("any_peer", "reliable")
func _ask(key: String, args: Array) -> void:
	var value: Variant = null
	var net := _pg.net
	match key:
		"seed":
			value = _pg.world.get_code()
		"item_count":
			value = net.items.size()
		"puppet_pos":
			var p: Player = net.puppets.get(int(args[0]))
			value = p.global_position if p else null
		"move_host":
			var at: Vector3 = args[0]
			_pg.player.global_position = at
			_pg.player.velocity = Vector3.ZERO
			_pg.player.reset_physics_interpolation()
			value = true
		"host_pos":
			value = _pg.player.global_position
		"item_where":
			var item: Item = net.items.get(int(args[0]))
			value = net._record(item) if item else null
		"item_pos":
			var item: Item = net.items.get(int(args[0]))
			value = item.global_position if item else null
		"rv":
			value = [net.rv_owner, _pg.rv.is_simulated, _pg.rv.global_position]
		"knock_off":
			_pg.rv.damage.detach(StringName(args[0]))
			value = true
		"part":
			value = _pg.rv.damage.parts[StringName(args[0])].attached
		"winch_state":
			value = _pg.rv.winches[0].state
		"door":
			value = _pg.rv.door_open
		"snake_at":
			var snake := Snake.new()
			snake.world = _pg.world
			snake.rv = _pg.rv
			var at: Vector3 = args[0]
			at.y = _pg.world.height_at(at.x, at.z)
			snake.home = at
			snake.position = at
			_pg.wildlife.add_child(snake)
			value = true
	_answer.rpc_id(multiplayer.get_remote_sender_id(), key, value)


@rpc("any_peer", "reliable")
func _answer(key: String, value: Variant) -> void:
	_answers[key] = value


# --- client side -----------------------------------------------------------------------------

func _run_client() -> void:
	_port = 31000 + randi() % 20000
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60",
		"res://tests/coop.tscn", "--", "--coop-role=host", "--port=%d" % _port]
	var proc := OS.execute_with_pipe(OS.get_executable_path(), args, false)
	if proc.is_empty():
		_fail_now("couldn't start the host process")
		return
	_host_pipe = proc["stdio"]
	_host_pid = proc["pid"]
	await _seconds(2.0)
	Session.player_name = "Clienty"
	var err := Session.join_direct("127.0.0.1", _port)
	if err != OK:
		_fail_now("join: %s" % error_string(err))
		return
	Session.joined.connect(func() -> void: _joined = true)
	Session.failed.connect(func(m: String) -> void: _fail_now("join failed: " + m))
	for i: int in 50:
		if _joined:
			break
		if i == 30:
			err = Session.join_direct("127.0.0.1", _port) # The host may have been slow to start.
		await _seconds(0.5)
	_check(_joined, "joined the host")
	if not _joined:
		_finish()
		return
	_check(Session.seed_code == SEED, "got the host's seed")
	_check(Session.players.size() == 2 and Session.name_of(1) == "Hosty", "roster has both players")
	_add_playground()
	while not _pg.is_spawned:
		await _frames(1)
	await _seconds(2.0)
	await _players()
	await _items()
	await _driving()
	await _repairs()
	await _winch_and_door()
	await _snake()
	_finish()


func _players() -> void:
	var me := Session.local_id()
	var host: Player = _pg.net.puppets.get(1)
	_check(host != null, "the host's player shows up")
	var seen: Variant = await _ask_host("puppet_pos", [me])
	_check(seen is Vector3 and (seen as Vector3).distance_to(_pg.player.global_position) < 1.5, "the host sees us where we are")
	var to := _pg.by_the_door() + Vector3(3.0, 0.0, 0.0)
	to.y = _pg.world.height_at(to.x, to.z) + 0.2
	await _ask_host("move_host", [to])
	await _seconds(1.0)
	var host_at: Vector3 = await _ask_host("host_pos", [])
	_check(host != null and host.global_position.distance_to(host_at) < 1.0, "the host's player moves here (%.2f m off)" % (host.global_position.distance_to(host_at) if host else -1.0))


func _items() -> void:
	var host_count: int = await _ask_host("item_count", [])
	_check(_pg.net.items.size() == host_count and host_count > 10, "all %d of the host's items are here (%d)" % [host_count, _pg.net.items.size()])
	var can: Item = null
	for item: Item in _pg.net.items.values():
		if item.kind == &"jerrycan" and item.holder == null:
			can = item
	_check(can != null, "the starter jerry can is here")
	if can == null:
		return
	_stand(can.global_position + Vector3(1.0, 0.0, 0.0))
	await _seconds(0.3)
	_pg.player.pick_up(can)
	await _seconds(1.0)
	var where: Array = await _ask_host("item_where", [can.net_id])
	_check(int(where[0]) == NetGame.Where.HELD and int(where[1]) == Session.local_id(), "the host sees us holding it")
	_pg.player.throw_held()
	await _seconds(2.5)
	where = await _ask_host("item_where", [can.net_id])
	_check(int(where[0]) == NetGame.Where.LOOSE, "and throwing it")
	var host_pos: Vector3 = await _ask_host("item_pos", [can.net_id])
	_check(host_pos.distance_to(can.global_position) < 0.5, "where it landed matches (%.2f m)" % host_pos.distance_to(can.global_position))


func _driving() -> void:
	var rv := _pg.rv
	_pg.player.take_wheel()
	await _seconds(1.0)
	var host_rv: Array = await _ask_host("rv", [])
	_check(_pg.net.rv_owner == Session.local_id() and rv.is_simulated and int(host_rv[0]) == Session.local_id() and not host_rv[1],
		"taking the wheel hands us the RV")
	_pg.driver.enabled = false # The test holds the controls.
	rv.set_automatic(true)
	rv.parking_brake = false
	var start := rv.global_position
	for i: int in 60 * 4:
		rv.throttle = 0.6
		await _frames(1)
	rv.throttle = 0.0
	rv.brake = 1.0
	await _seconds(1.5)
	rv.brake = 0.0
	rv.parking_brake = true
	host_rv = await _ask_host("rv", [])
	var gap := (host_rv[2] as Vector3).distance_to(rv.global_position)
	_check(rv.global_position.distance_to(start) > 5.0, "we drove (%.1f m)" % rv.global_position.distance_to(start))
	_check(gap < 1.0, "the host's RV follows ours (%.2f m apart)" % gap)
	_pg.player.stand_up()
	await _seconds(1.0)
	host_rv = await _ask_host("rv", [])
	_check(_pg.net.rv_owner == 1 and not rv.is_simulated and host_rv[1], "getting up hands it back")
	_pg.player.leave_rv()
	await _seconds(0.5)


func _repairs() -> void:
	var d := _pg.rv.damage
	await _ask_host("knock_off", ["MirrorL"])
	await _seconds(1.0)
	_check(not d.parts[&"MirrorL"].attached and not d.parts[&"MirrorL"].node.visible, "a part knocked off on the host is gone here")
	var debris := false
	for item: Item in _pg.net.items.values():
		debris = debris or (item.kind == &"rv_part" and item.get_meta(&"part", &"") == &"MirrorL")
	_check(debris, "and its piece lies on the ground")
	_pg.rv.op(&"patch_part", [&"MirrorL"])
	await _seconds(1.0)
	var on: bool = await _ask_host("part", ["MirrorL"])
	_check(on and d.parts[&"MirrorL"].attached, "patching it here fixes it on the host")


func _winch_and_door() -> void:
	var winch := _pg.rv.winches[0]
	_stand(winch.global_position + _pg.rv.global_basis.z * -1.2)
	await _seconds(0.3)
	if _pg.player.held:
		_pg.player.drop_held()
	_pg.player.pick_up(winch.hook)
	await _seconds(1.0)
	var state: int = await _ask_host("winch_state", [])
	_check(winch.state == RVWinch.State.HELD and state == RVWinch.State.HELD, "taking the winch hook shows on the host")
	_pg.player.held = null
	winch.stow_hook()
	await _seconds(1.0)
	state = await _ask_host("winch_state", [])
	_check(state == RVWinch.State.STOWED, "and putting it back")
	var door := not _pg.rv.door_open
	_pg.rv.door_open = door
	_pg.rv.door_toggled.emit(door)
	await _seconds(0.7)
	var host_door: bool = await _ask_host("door", [])
	_check(host_door == door, "the door opens for everyone")


func _snake() -> void:
	var at := _pg.player.global_position + Vector3(1.0, 0.0, 0.0)
	await _ask_host("snake_at", [at])
	await _seconds(2.0)
	_check(_pg.player.venom > 0.0, "the host's snake bites us (health %.0f)" % _pg.player.health)


# --- helpers ---------------------------------------------------------------------------------

func _add_playground() -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)


func _stand(at: Vector3) -> void:
	if _pg.player.inside:
		_pg.player.leave_rv()
	at.y = _pg.world.height_at(at.x, at.z) + 0.2
	_pg.player.global_position = at
	_pg.player.velocity = Vector3.ZERO
	_pg.player.reset_physics_interpolation()


func _ask_host(key: String, args: Array) -> Variant:
	_answers.erase(key)
	_ask.rpc_id(1, key, args)
	for i: int in 300:
		if _answers.has(key):
			return _answers[key]
		await _frames(1)
	_check(false, "the host answered '%s'" % key)
	return null


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _fail_now(why: String) -> void:
	_failures.append(why)
	_finish()


func _finish() -> void:
	if _host_role:
		get_tree().quit(1)
		return
	Session.leave()
	# The host checks our player went, then quits; its verdict comes down the pipe.
	for i: int in 100:
		if _host_output.contains("coop host:"):
			break
		await _seconds(0.1)
		_read_host()
	var host_ok := _host_output.contains("coop host: all checks passed")
	_check(host_ok, "the host removed our player when we left")
	if not host_ok:
		printerr(_host_output.right(3000))
	if _host_pid > 0 and OS.is_process_running(_host_pid):
		OS.kill(_host_pid)
	if _pg:
		_pg.trip.clear_save()
	if _failures.is_empty():
		print("coop: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
