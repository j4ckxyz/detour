extends Node
## Who you're playing with (PLAN.md §6): solo, hosting or joining; the transport (direct/LAN
## ENet, or the relay with a room code); the handshake (protocol and game version checks);
## and the roster of players. The game itself (`NetGame`) takes over once the trip loads.
##
## The host is always peer 1. Clients say hello; the host checks versions and room, then
## welcomes them with the trip's seed and the roster, and they load the trip.

## Client: the host let us in; `seed_code` is set, load the trip.
signal joined
## Hosting or joining didn't work (readable message).
signal failed(message: String)
signal roster_changed
## A player left (host and clients).
signal player_left(peer: int)
## The session closed under us (the host left, we were dropped).
signal ended(message: String)
signal lan_games_changed

enum Mode { SOLO, HOST, CLIENT }

## Bump when gameplay messages change incompatibly.
const PROTOCOL := 1
const DEFAULT_PORT := 24652
const LAN_BEACON_PORT := 24653
const MAX_PLAYERS := 4
## Player colours (jackets), picked by index.
const COLORS: Array[Color] = [
	Color(0.85, 0.3, 0.2), Color(0.2, 0.5, 0.85), Color(0.3, 0.7, 0.3), Color(0.9, 0.7, 0.15),
	Color(0.65, 0.35, 0.8), Color(0.2, 0.7, 0.7), Color(0.9, 0.45, 0.65), Color(0.4, 0.4, 0.4),
]
const SETTINGS_PATH := "user://session.cfg"

var mode := Mode.SOLO
## The trip everyone plays (the host picks it; clients get it in the welcome).
var seed_code := ""
var player_name := "Traveller"
var player_color := 0
var relay_address := ""
## Relay room code once hosting or joining through the relay.
var room_code := ""
## peer id → {name: String, color: int}
var players: Dictionary[int, Dictionary] = {}
## "address:port" → {name, players, seed, seen (msec)}, from LAN beacons.
var lan_games: Dictionary[String, Dictionary] = {}
## Why the last session ended (shown on the main menu), or "".
var last_message := ""
## Client: where the trip stands as the host welcomed us ({checkpoint, rv: Transform3D}).
var start_info: Dictionary = {}
## Host: `func() -> Dictionary` giving that (set by the game once it's running).
var start_info_source: Callable

var _beacon := PacketPeerUDP.new()
var _beacon_timer := 0.0
var _beacon_port := 0
var _listener := PacketPeerUDP.new()
var _listening := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_settings()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Couldn't reach the host."))
	multiplayer.server_disconnected.connect(func() -> void: _end("The host left the game."))


func is_online() -> bool:
	return mode != Mode.SOLO


## Solo counts as hosting: the local game is the authority.
func is_host() -> bool:
	return mode != Mode.CLIENT


func local_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func color_of(peer: int) -> Color:
	return COLORS[int(players.get(peer, {}).get("color", 0)) % COLORS.size()]


func name_of(peer: int) -> String:
	return String(players.get(peer, {}).get("name", "Player %d" % peer))


# --- hosting and joining -------------------------------------------------------------------

## Hosts on this machine (LAN, or over the internet with the port forwarded).
## `bind` "127.0.0.1" keeps it to this machine (tests).
func host_direct(port: int = DEFAULT_PORT, announce: bool = true, bind: String = "*") -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind)
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		return err
	_begin(Mode.HOST, peer)
	if announce:
		_beacon_port = port
		_beacon.set_broadcast_enabled(true)
		_beacon.set_dest_address("255.255.255.255", LAN_BEACON_PORT)
	return OK


## Hosts through a relay (nobody forwards ports); `room_code` arrives when it answers.
func host_relay(address: String, port: int = RelayMultiplayerPeer.DEFAULT_PORT) -> Error:
	var peer := RelayMultiplayerPeer.new()
	var err := peer.create_room(address, port)
	if err != OK:
		return err
	peer.room_joined.connect(func(code: String, _id: int) -> void:
		room_code = code
		roster_changed.emit())
	peer.rejected.connect(func(_reason: int, message: String) -> void: _fail(message))
	_begin(Mode.HOST, peer)
	return OK


func join_direct(address: String, port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	_begin(Mode.CLIENT, peer)
	return OK


func join_relay(address: String, code: String, port: int = RelayMultiplayerPeer.DEFAULT_PORT) -> Error:
	var peer := RelayMultiplayerPeer.new()
	var err := peer.join_room(address, port, code.strip_edges().to_upper())
	if err != OK:
		return err
	peer.rejected.connect(func(_reason: int, message: String) -> void: _fail(message))
	room_code = code
	_begin(Mode.CLIENT, peer)
	return OK


## Back to solo: closes the connection.
func leave() -> void:
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.SOLO
	room_code = ""
	players.clear()
	start_info = {}
	start_info_source = Callable()
	_beacon_port = 0
	_beacon.close()


func _begin(m: Mode, peer: MultiplayerPeer) -> void:
	mode = m
	multiplayer.multiplayer_peer = peer
	players.clear()
	if m == Mode.HOST:
		players[1] = {"name": player_name, "color": player_color}


func _fail(message: String) -> void:
	leave()
	last_message = message
	failed.emit(message)


func _end(message: String) -> void:
	leave()
	last_message = message
	ended.emit(message)


func _on_connected() -> void:
	_hello.rpc_id(1, PROTOCOL, BuildInfo.version, player_name, player_color)


func _on_peer_connected(_peer: int) -> void:
	pass # They say hello first.


func _on_peer_disconnected(peer: int) -> void:
	if players.erase(peer):
		if mode == Mode.HOST:
			_roster.rpc(players)
		roster_changed.emit()
		player_left.emit(peer)


@rpc("any_peer", "reliable")
func _hello(protocol: int, version: String, who: String, color: int) -> void:
	if mode != Mode.HOST:
		return
	var peer := multiplayer.get_remote_sender_id()
	var refuse := ""
	if protocol != PROTOCOL or version != BuildInfo.version:
		refuse = "Version mismatch: the host runs Detour %s (protocol %d), you have %s (protocol %d). Update to play together." % [
			_or_dev(BuildInfo.version), PROTOCOL, _or_dev(version), protocol]
	elif players.size() >= MAX_PLAYERS:
		refuse = "The game is full (%d players)." % MAX_PLAYERS
	if refuse != "":
		_refused.rpc_id(peer, refuse)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer:
				multiplayer.multiplayer_peer.disconnect_peer(peer))
		return
	var taken: Array[int] = []
	for p: Dictionary in players.values():
		taken.append(int(p["color"]))
	while taken.has(color):
		color = (color + 1) % COLORS.size() # Everyone gets their own colour.
	players[peer] = {"name": who.substr(0, 24).strip_edges(), "color": color}
	_welcome.rpc_id(peer, seed_code, players, start_info_source.call() if start_info_source.is_valid() else {})
	_roster.rpc(players)
	roster_changed.emit()


static func _or_dev(v: String) -> String:
	return v if v != "" else "(dev build)"


@rpc("authority", "reliable")
func _welcome(code: String, roster: Dictionary, info: Dictionary) -> void:
	seed_code = code
	start_info = info
	_set_roster(roster)
	joined.emit()


@rpc("authority", "reliable")
func _refused(message: String) -> void:
	_fail(message)


@rpc("authority", "reliable")
func _roster(roster: Dictionary) -> void:
	if mode == Mode.CLIENT:
		_set_roster(roster)
		roster_changed.emit()


func _set_roster(roster: Dictionary) -> void:
	players.clear()
	for k: Variant in roster:
		var p: Dictionary = roster[k]
		players[int(k)] = {"name": String(p.get("name", "")), "color": int(p.get("color", 0))}


# --- LAN discovery -------------------------------------------------------------------------

## Starts listening for games hosted on the local network.
func listen_lan() -> void:
	if _listening:
		return
	_listening = _listener.bind(LAN_BEACON_PORT) == OK


func stop_listening() -> void:
	_listener.close()
	_listening = false
	lan_games.clear()


func _process(dt: float) -> void:
	if _beacon_port > 0 and mode == Mode.HOST:
		_beacon_timer -= dt
		if _beacon_timer <= 0.0:
			_beacon_timer = 1.0
			var msg := "DETOUR|%d|%d|%s|%d|%s" % [PROTOCOL, _beacon_port, player_name.replace("|", " "), players.size(), seed_code]
			_beacon.put_packet(msg.to_utf8_buffer())
	if not _listening:
		return
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var text := _listener.get_packet().get_string_from_utf8()
		var parts := text.split("|")
		if parts.size() < 6 or parts[0] != "DETOUR" or int(parts[1]) != PROTOCOL:
			continue
		var key := "%s:%s" % [_listener.get_packet_ip(), parts[2]]
		changed = changed or not lan_games.has(key)
		lan_games[key] = {"address": _listener.get_packet_ip(), "port": int(parts[2]), "name": parts[3],
			"players": int(parts[4]), "seed": parts[5], "seen": Time.get_ticks_msec()}
	for key: String in lan_games.keys():
		if Time.get_ticks_msec() - int(lan_games[key]["seen"]) > 4000:
			lan_games.erase(key)
			changed = true
	if changed:
		lan_games_changed.emit()


# --- settings ------------------------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		player_color = randi() % COLORS.size()
		return
	player_name = String(cfg.get_value("player", "name", player_name))
	player_color = int(cfg.get_value("player", "color", 0))
	relay_address = String(cfg.get_value("net", "relay", ""))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "color", player_color)
	cfg.set_value("net", "relay", relay_address)
	cfg.save(SETTINGS_PATH)
