class_name RelayMultiplayerPeer
extends MultiplayerPeerExtension
## Godot MultiplayerPeer that talks to a detour-relay server (server/relay).
##
## Every player, the host included, connects out to the relay, so nobody needs to forward
## ports. The room creator becomes peer 1 (the server, as far as Godot is concerned), so
## RPCs, authority and `multiplayer.is_server()` work exactly as with a normal ENet host.
## Wire format: see server/relay/src/protocol.rs (must stay in sync).

## Emitted when the relay accepts us. `peer_id` is 1 for the room creator.
signal room_joined(code: String, peer_id: int)
## Emitted when the relay refuses or drops us. See REJECT_* constants.
signal rejected(reason: int, message: String)

const RELAY_PROTO := 1
const ENET_CHANNELS := 5 # 1 control + 4 game channels.
const MAX_GAME_CHANNELS := ENET_CHANNELS - 1
const DEFAULT_PORT := 24650

const MSG_HELLO := 1
const MSG_WELCOME := 2
const MSG_REJECT := 3
const MSG_PEER_JOINED := 4
const MSG_PEER_LEFT := 5
const MSG_KICK := 6
const ACTION_CREATE := 1
const ACTION_JOIN := 2

const REJECT_BAD_PROTOCOL := 1
const REJECT_ROOM_NOT_FOUND := 2
const REJECT_ROOM_FULL := 3
const REJECT_BAD_PASSWORD := 4
const REJECT_SERVER_FULL := 5
const REJECT_RATE_LIMITED := 6
const REJECT_MALFORMED := 7
const REJECT_HOST_LEFT := 8
const REJECT_KICKED := 9
const REJECT_TIMEOUT := 10

const DATA_HEADER := 5

var room_code := ""
var reject_reason := 0
var reject_message := ""

var _conn := ENetConnection.new()
var _server: ENetPacketPeer
var _status := CONNECTION_DISCONNECTED
var _unique_id := 0
var _hello := PackedByteArray()
var _peers: Dictionary[int, bool] = {}
var _incoming: Array[Packet] = []
var _target := 0
var _channel := 0
var _mode := TRANSFER_MODE_RELIABLE
var _refusing := false


class Packet:
	var data: PackedByteArray
	var from: int
	var channel: int
	var mode: MultiplayerPeer.TransferMode


## Connects to the relay and creates a new room; this peer becomes the host (id 1).
func create_room(address: String, port: int = DEFAULT_PORT, password: String = "") -> Error:
	return _connect(address, port, ACTION_CREATE, "", password)


## Connects to the relay and joins the room with `code`.
func join_room(address: String, port: int, code: String, password: String = "") -> Error:
	return _connect(address, port, ACTION_JOIN, code, password)


func _connect(address: String, port: int, action: int, code: String, password: String) -> Error:
	if _status != CONNECTION_DISCONNECTED:
		return ERR_ALREADY_IN_USE
	var err := _conn.create_host(1, ENET_CHANNELS)
	if err != OK:
		return err
	_server = _conn.connect_to_host(address, port, ENET_CHANNELS)
	if _server == null:
		_conn.destroy()
		return ERR_CANT_CONNECT
	var hello := StreamPeerBuffer.new()
	hello.put_u8(MSG_HELLO)
	hello.put_u16(RELAY_PROTO)
	hello.put_u8(action)
	_put_str8(hello, code)
	_put_str8(hello, password)
	_hello = hello.data_array
	_status = CONNECTION_CONNECTING
	return OK


static func _put_str8(buf: StreamPeerBuffer, s: String) -> void:
	var bytes := s.to_utf8_buffer().slice(0, 255)
	buf.put_u8(bytes.size())
	buf.put_data(bytes)


static func _get_str8(buf: StreamPeerBuffer) -> String:
	var n := buf.get_u8()
	return buf.get_utf8_string(n)


# --- MultiplayerPeerExtension ---------------------------------------------------------------

func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	while true:
		var event := _conn.service()
		var type: ENetConnection.EventType = event[0]
		match type:
			ENetConnection.EVENT_NONE:
				return
			ENetConnection.EVENT_ERROR:
				_drop(REJECT_TIMEOUT, "network error")
				return
			ENetConnection.EVENT_CONNECT:
				_server.send(0, _hello, ENetPacketPeer.FLAG_RELIABLE)
			ENetConnection.EVENT_DISCONNECT:
				var reason: int = event[2]
				_drop(reason if reason > 0 else REJECT_TIMEOUT, "disconnected from relay")
				return
			ENetConnection.EVENT_RECEIVE:
				var channel: int = event[3]
				var packet := _server.get_packet()
				if channel == 0:
					_on_control(packet)
				else:
					_on_data(packet, channel - 1)
			_:
				return


func _on_control(msg: PackedByteArray) -> void:
	if msg.is_empty():
		return
	var buf := StreamPeerBuffer.new()
	buf.data_array = msg
	match buf.get_u8():
		MSG_WELCOME:
			_unique_id = buf.get_32()
			room_code = _get_str8(buf)
			var count := buf.get_u8()
			_status = CONNECTION_CONNECTED
			room_joined.emit(room_code, _unique_id)
			for i: int in count:
				_add_peer(buf.get_32())
		MSG_REJECT:
			var reason := buf.get_u8()
			_drop(reason, _get_str8(buf))
		MSG_PEER_JOINED:
			_add_peer(buf.get_32())
		MSG_PEER_LEFT:
			_remove_peer(buf.get_32())


func _on_data(msg: PackedByteArray, channel: int) -> void:
	if msg.size() < DATA_HEADER or _status != CONNECTION_CONNECTED:
		return
	var p := Packet.new()
	p.mode = msg.decode_u8(0) as MultiplayerPeer.TransferMode
	p.from = msg.decode_s32(1)
	p.channel = channel
	p.data = msg.slice(DATA_HEADER)
	_incoming.append(p)


func _add_peer(id: int) -> void:
	if id > 0 and id != _unique_id and not _peers.has(id):
		_peers[id] = true
		peer_connected.emit(id)


func _remove_peer(id: int) -> void:
	if _peers.erase(id):
		peer_disconnected.emit(id)


func _drop(reason: int, message: String) -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	# Only surface a reason if we never got in, or the relay told us why we're out.
	if reject_reason == 0:
		reject_reason = reason
		reject_message = message
		rejected.emit(reason, message)
	_status = CONNECTION_DISCONNECTED
	for id: int in _peers.keys():
		_remove_peer(id)
	_incoming.clear()
	_conn.destroy()
	_server = null


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	return _incoming.pop_front().data


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED or _server == null:
		return ERR_UNCONFIGURED
	if _channel >= MAX_GAME_CHANNELS:
		return ERR_INVALID_PARAMETER
	var msg := PackedByteArray()
	msg.resize(DATA_HEADER)
	msg.encode_u8(0, _mode)
	msg.encode_s32(1, _target)
	msg.append_array(buffer)
	var flags := 0
	match _mode:
		TRANSFER_MODE_RELIABLE:
			flags = ENetPacketPeer.FLAG_RELIABLE
		TRANSFER_MODE_UNRELIABLE:
			flags = ENetPacketPeer.FLAG_UNSEQUENCED | ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT
		TRANSFER_MODE_UNRELIABLE_ORDERED:
			flags = ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT
	return _server.send(_channel + 1, msg, flags)


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_max_packet_size() -> int:
	return 65536 - DATA_HEADER


func _get_packet_peer() -> int:
	return _incoming[0].from if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return _incoming[0].channel if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _incoming[0].mode if not _incoming.is_empty() else TRANSFER_MODE_RELIABLE


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_target_peer(peer: int) -> void:
	_target = peer


func _is_server() -> bool:
	return _unique_id == 1


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


## The relay routes client-to-client packets itself, so Godot's server relaying is not needed.
func _is_server_relay_supported() -> bool:
	return false


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable # TODO(Phase 2): tell the relay to lock the room.


func _is_refusing_new_connections() -> bool:
	return _refusing


func _disconnect_peer(peer: int, force: bool) -> void:
	if peer == _unique_id or peer == 1:
		_close()
		return
	if _unique_id == 1 and _server:
		var msg := PackedByteArray([MSG_KICK, 0, 0, 0, 0])
		msg.encode_s32(1, peer)
		_server.send(0, msg, ENetPacketPeer.FLAG_RELIABLE)
		if force:
			_remove_peer(peer)


func _close() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	if _server:
		_server.peer_disconnect_now(0)
	_conn.flush()
	_status = CONNECTION_DISCONNECTED
	for id: int in _peers.keys():
		_remove_peer(id)
	_incoming.clear()
	_conn.destroy()
	_server = null
