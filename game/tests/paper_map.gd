extends Node
## Headless paper-map test: a new trip starts with the map on the dashboard; Use unfolds it
## and it shows the road from camp through every gas station to home (laid out from the route
## generator's data, inside the sheet); putting it down folds it away; a save from before the
## map gets one on the dashboard.
##
##   godot --headless --path game --fixed-fps 60 res://tests/paper_map.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _failures: PackedStringArray = []


func _ready() -> void:
	await _start(true)
	var map := _find_map()
	_check(map != null and map.get_parent() == _pg.rv.stash, "the paper map is in the RV")
	var player := _pg.player
	player.pick_up(map)
	_check(ItemLibrary.use_hint(map, player).ends_with(" read"), "holding it says Use to read it")
	map.use(player)
	await _frames(2)
	var pm := _pg.paper_map
	_check(pm.visible and player.reading_map, "Use unfolds it")
	_check(pm.road.size() > 20, "the road is drawn (%d points)" % pm.road.size())
	_check(Array(pm.road).all(func(m: Vector2) -> bool: return m.x >= -0.001 and m.x <= 1.001 and m.y >= -0.001 and m.y <= 1.001), "and fits on the sheet")
	var kinds := pm.stops.map(func(s: Dictionary) -> StringName: return s["kind"])
	_check(kinds.front() == &"camp" and kinds.back() == &"home", "from camp to home")
	_check(kinds.count(&"station") == _pg.trip.station_count(), "with every gas station (%d)" % _pg.trip.station_count())
	_check(pm.stops[0]["at"].distance_to(pm.road[0]) < 0.1, "camp is at the start of the road")
	map.use(player)
	await _frames(2)
	_check(not pm.visible, "Use again folds it up")
	map.use(player)
	await _frames(2)
	player.drop_held()
	await _frames(2)
	_check(not pm.visible and not player.reading_map, "dropping it puts it away")

	# A save from before there was a map.
	map.queue_free()
	await _frames(2)
	_pg.trip.save()
	_pg.queue_free()
	await _frames(2)
	await _start(false)
	_check(_find_map() != null, "an older save gets a map on the dashboard")
	_pg.trip.clear_save()
	_finish()


func _find_map() -> Item:
	for n: Node in get_tree().get_nodes_in_group(&"items"):
		if n is Item and (n as Item).kind == &"map" and _pg.is_ancestor_of(n) and not n.is_queued_for_deletion():
			return n
	return null


func _start(fresh: bool) -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = fresh
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60 * 5:
		await get_tree().physics_frame
		waited += 1
	await _frames(20)


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("paper_map: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
