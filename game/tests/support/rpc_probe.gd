extends Node
## Records RPCs received, for net tests.

var pings: Array[int] = [] # Sender ids.
var pongs := 0
var directs: Array[int] = [] # Sender ids.
var ticks := 0
var blob_sizes: Array[int] = []


@rpc("any_peer", "call_remote", "reliable")
func ping() -> void:
	pings.append(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "reliable")
func pong() -> void:
	pongs += 1


@rpc("any_peer", "call_remote", "reliable")
func direct() -> void:
	directs.append(multiplayer.get_remote_sender_id())


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func tick(_i: int) -> void:
	ticks += 1


@rpc("authority", "call_remote", "reliable", 2)
func blob(data: PackedByteArray) -> void:
	blob_sizes.append(data.size())
