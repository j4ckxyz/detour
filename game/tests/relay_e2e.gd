extends SceneTree
## End-to-end relay test. Starts the real relay binary, then a host and two clients (three
## SceneMultiplayer branches in this one process) exchange RPCs through it.
##
##   cargo build --release -p detour-relay
##   godot --headless --path game --script res://tests/relay_e2e.gd
##
## Proves Godot's ENet and the relay's rusty_enet interoperate, and that Godot's high-level
## multiplayer (RPCs, authority, channels, fragmentation) works unchanged over the relay.

const Probe := preload("res://tests/support/rpc_probe.gd")
const TIMEOUT_MSEC := 15000
const BLOB_SIZE := 20000
const TICKS := 50

var _relay_pid := -1
var _port := 0
var _probes: Dictionary[String, Probe] = {}
var _peers: Dictionary[String, RelayMultiplayerPeer] = {}
var _intruder := RelayMultiplayerPeer.new()
var _step := 0
var _step_started := 0
var _deadline := 0


func _initialize() -> void:
	var relay := ProjectSettings.globalize_path("res://").path_join("../target/release/detour-relay").simplify_path()
	if not FileAccess.file_exists(relay):
		_finish("relay binary missing, run: cargo build --release -p detour-relay")
		return
	_port = 30000 + randi() % 20000
	_relay_pid = OS.create_process(relay, ["--bind", "127.0.0.1:%d" % _port])
	OS.delay_msec(300) # Let it bind.
	_deadline = Time.get_ticks_msec() + TIMEOUT_MSEC
	for branch: String in ["Host", "A", "B"]:
		_make_branch(branch)
	var err := _peers["Host"].create_room("127.0.0.1", _port)
	if err != OK:
		_finish("create_room: %s" % error_string(err))
		return
	_attach("Host")


func _make_branch(branch: String) -> void:
	var holder := Node.new()
	holder.name = branch
	root.add_child(holder)
	var probe: Probe = Probe.new()
	probe.name = "Probe"
	holder.add_child(probe)
	_probes[branch] = probe
	_peers[branch] = RelayMultiplayerPeer.new()


func _attach(branch: String) -> void:
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = _peers[branch]
	set_multiplayer(api, NodePath("/root/" + branch))


func _ids(branch: String) -> PackedInt32Array:
	return get_multiplayer(NodePath("/root/" + branch)).get_peers()


func _next() -> void:
	_step += 1
	_step_started = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if _step < 0:
		return false
	if Time.get_ticks_msec() > _deadline:
		_finish("timed out at step %d" % _step)
		return false
	_intruder.poll()
	var host := _peers["Host"]
	var a := _probes["A"]
	var b := _probes["B"]
	match _step:
		0: # Room created: clients join with the code, an intruder guesses a code.
			if host.room_code != "":
				_peers["A"].join_room("127.0.0.1", _port, host.room_code)
				_attach("A")
				# Lower-case with a look-alike letter still works.
				_peers["B"].join_room("127.0.0.1", _port, host.room_code.to_lower())
				_attach("B")
				_intruder.join_room("127.0.0.1", _port, "ZZZZZZ")
				_next()
		1: # Everyone sees everyone; the intruder is refused.
			if _ids("Host").size() == 2 and _ids("A").size() == 2 and _ids("B").size() == 2 \
					and _intruder.reject_reason != 0:
				if _intruder.reject_reason != RelayMultiplayerPeer.REJECT_ROOM_NOT_FOUND:
					_finish("intruder got reason %d" % _intruder.reject_reason)
					return false
				if not get_multiplayer(^"/root/Host").is_server() or get_multiplayer(^"/root/A").is_server():
					_finish("host must be peer 1 / server")
					return false
				a.ping.rpc_id(1)
				b.ping.rpc_id(1)
				a.direct.rpc_id(_peers["B"].get_unique_id())
				var host_probe := _probes["Host"]
				host_probe.pong.rpc()
				for i: int in TICKS:
					host_probe.tick.rpc(i)
				var data := PackedByteArray()
				data.resize(BLOB_SIZE)
				data.fill(7)
				host_probe.blob.rpc(data)
				_next()
		2: # All messages arrive with the right senders.
			var host_probe := _probes["Host"]
			var a_id := _peers["A"].get_unique_id()
			var b_id := _peers["B"].get_unique_id()
			var done := host_probe.pings.size() == 2 and a.pongs == 1 and b.pongs == 1 \
					and b.directs.size() == 1 and a.blob_sizes.size() == 1 and b.blob_sizes.size() == 1
			if done and Time.get_ticks_msec() - _step_started > 200: # Give unreliable ticks a moment.
				var ok := host_probe.pings.has(a_id) and host_probe.pings.has(b_id) \
						and b.directs[0] == a_id and a.blob_sizes[0] == BLOB_SIZE and b.blob_sizes[0] == BLOB_SIZE \
						and a.ticks >= TICKS * 9 / 10 and b.ticks >= TICKS * 9 / 10
				if not ok:
					_finish("wrong data: pings %s directs %s blobs %s/%s ticks %d/%d" % [
						host_probe.pings, b.directs, a.blob_sizes, b.blob_sizes, a.ticks, b.ticks])
					return false
				print("relay e2e: RPCs ok (ticks %d/%d of %d unreliable)" % [a.ticks, b.ticks, TICKS])
				_peers["B"].close()
				_next()
		3: # A client leaving is seen by the others.
			if _ids("Host").size() == 1 and _ids("A").size() == 1:
				_peers["Host"].close()
				_next()
		4: # The host leaving closes the room for everyone.
			var peer_a := _peers["A"]
			if peer_a.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
				if peer_a.reject_reason != RelayMultiplayerPeer.REJECT_HOST_LEFT:
					_finish("A got reason %d, want HOST_LEFT" % peer_a.reject_reason)
				else:
					_finish("")
	return false


func _finish(failure: String) -> void:
	_step = -1
	if _relay_pid > 0:
		OS.kill(_relay_pid)
	if failure == "":
		print("relay e2e: all checks passed")
		quit(0)
	else:
		printerr("FAIL: ", failure)
		quit(1)
