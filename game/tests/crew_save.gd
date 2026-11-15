extends Node
## Headless per-player inventory test: a save keeps each other player's hotbar and health under
## their player uuid (not dropped on the ground), carries it through later saves until they
## come back, and hands it back to them when they rejoin.
##
##   godot --headless --path game --fixed-fps 60 res://tests/crew_save.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60
const PEER := 7
const UUID := "0123456789abcdef0123456789abcdef"

var _pg: Playground
var _calls: Array = []
var _failures: PackedStringArray = []


func _ready() -> void:
	_check(Session.player_uuid.length() == 32, "this machine has a player uuid (%s)" % Session.player_uuid)
	Session.players[PEER] = {"name": "Guest", "color": 1, "hat": "", "glasses": "", "uuid": UUID}

	await _start(true)
	var guest := _add_puppet()
	for kind: StringName in [&"drill", &"bear_spray"]:
		var item := ItemLibrary.create(kind)
		_pg.items.add_child(item)
		var slot := guest.slots.find(null)
		guest.slots[slot] = item
		item.grab(guest, guest.hand)
	guest.health = 42.0
	_pg.trip.checkpoint = 1
	_pg.trip.save()
	var crew: Dictionary = _pg._save_extra().get("crew", {})
	_check(crew.has(UUID) and (crew[UUID]["hotbar"] as Array).size() == 2, "the save has the guest's hotbar under their uuid")
	var lying: Array = _pg._save_extra()["world"]
	_check(lying.all(func(e: Array) -> bool: return e[0] not in [&"drill", &"bear_spray"]), "and their things aren't also saved lying about")

	# Carry on without them: their things wait in the save, and in the next save too.
	await _restart()
	_check(_pg.crew_saved.has(UUID), "continuing keeps the guest's things aside")
	_check(_pg._save_extra()["crew"].has(UUID), "and a save made before they're back still has them")

	# They come back.
	guest = _add_puppet()
	_pg.give_back(guest, UUID)
	var kinds := guest.slots.filter(func(i: Item) -> bool: return i != null).map(func(i: Item) -> StringName: return i.kind)
	_check(kinds.has(&"drill") and kinds.has(&"bear_spray"), "rejoining hands their hotbar back (%s)" % [kinds])
	_check(guest.slots.all(func(i: Item) -> bool: return i == null or i.holder == guest), "held by them")
	_check(absf(guest.health - 42.0) < 0.01, "with their health (%.0f)" % guest.health)
	_check(_calls.size() == 1 and _calls[0][1] == &"restore" and absf(float(_calls[0][2][0]) - 42.0) < 0.01, "and their own machine is told their health")
	_check(not _pg.crew_saved.has(UUID), "it's only handed back once")
	_pg.give_back(guest, "someone-else")
	_check(guest.slots.filter(func(i: Item) -> bool: return i != null).size() == 2, "an unknown uuid gets nothing")

	Session.players.erase(PEER)
	_pg.trip.clear_save()
	_finish()


func _add_puppet() -> Player:
	var p := Player.new()
	p.puppet = true
	p.peer_id = PEER
	p.rv = _pg.rv
	p.world_items = _pg.items
	p.remote = func(peer: int, method: StringName, args: Array) -> void: _calls.append([peer, method, args])
	p.input_enabled = false
	_pg.add_child(p)
	p.global_position = _pg.by_the_door()
	_pg.net.puppets[PEER] = p
	return p


func _restart() -> void:
	_pg.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _start(false)


func _start(fresh: bool) -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = fresh
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60 * 5:
		await get_tree().physics_frame
		waited += 1
	for i: int in 30:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("crew_save: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
