extends Node
## Headless test of getting out of a pit: fall into the gap's trench (2 m deep) and jump at its
## wall: you climb up onto the road; a deep ravine (a bridge's) can't be climbed, so after a
## while you're told to use the menu, and "Back to the RV" puts you beside the RV's door.
##
##   godot --headless --path game --fixed-fps 60 res://tests/climb_out.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")
const HZ := 60

var _pg: Playground
var _w: Walker
var _failures: PackedStringArray = []


func _ready() -> void:
	_run()


func _run() -> void:
	await _start(Playground.DEFAULT_SEED)
	var gap := _first(Trip.GAP)
	var bridge := _first(Trip.BRIDGE)
	_check(not gap.is_empty() and not bridge.is_empty(), "the trip has a gap and a bridge")
	if gap.is_empty() or bridge.is_empty():
		_finish()
		return
	await _trench(gap)
	await _ravine(bridge)
	_finish()


## Into the gap's trench, then out again by jumping at the wall.
func _trench(gap: Dictionary) -> void:
	var s := float(gap["s"])
	await _teleport(s - float(gap["length"]) * 0.5 - 14.0)
	var dir: Vector3 = gap["dir"]
	var centre: Vector3 = gap["pos"]
	var road := centre.y
	var player := _pg.player
	player.global_position = Vector3(centre.x, _ground(centre).y + 0.3, centre.z)
	player.velocity = Vector3.ZERO
	await _w.hold(1.0)
	_check(player.is_on_floor() and player.global_position.y < road - 1.5, "in the trench, %.1f m below the road" % (road - player.global_position.y))
	_check(not player.in_pit(), "a trench you can climb out of isn't a pit to be rescued from")
	# Walk to the near wall, facing it, and jump.
	_face(-dir)
	Input.action_press(&"move_forward")
	await _w.hold(1.2)
	Input.action_release(&"move_forward")
	await _w.hold(0.2)
	await _jump()
	await _w.hold(0.3)
	_check(player.is_climbing(), "jumping at the wall starts a climb")
	await _w.hold(1.6)
	var here := player.global_position
	var along := (here - centre).dot(dir)
	_check(not player.is_climbing() and absf(here.y - road) < 0.4 and along < -float(gap["length"]) * 0.5 - 0.1, "and you're on the road, on the near side (%.2f m from the road's level, %.1f m from the gap's middle)" % [here.y - road, along])
	_check(not player.in_pit(), "no longer in a pit")


## The ravine under a bridge, too deep to climb: told what to do, and "Back to the RV" works.
func _ravine(bridge: Dictionary) -> void:
	await _teleport(float(bridge["s"]) - float(bridge["length"]) * 0.5 - 14.0)
	var dir: Vector3 = bridge["dir"]
	var side := Vector3(-dir.z, 0.0, dir.x)
	var centre: Vector3 = bridge["pos"]
	var player := _pg.player
	var floor_at := centre + side * 8.0
	player.global_position = Vector3(floor_at.x, _ground(floor_at).y + 0.3, floor_at.z)
	player.velocity = Vector3.ZERO
	player.health = Player.MAX_HEALTH
	await _w.hold(1.0)
	_check(player.is_on_floor() and player.global_position.y < centre.y - 5.0, "at the bottom of the ravine, %.1f m below the road" % (centre.y - player.global_position.y))
	_check(player.in_pit(), "which is a pit")
	_face(-dir)
	await _w.hold(0.2)
	await _jump()
	await _w.hold(1.0)
	_check(not player.is_climbing() and player.global_position.y < centre.y - 5.0, "it's too high to climb")
	player.message_time = 0.0
	var told := false
	for i: int in HZ * 8:
		await get_tree().physics_frame
		if player.message.contains("Stuck?") and player.message_time > 0.0:
			told = true
			break
	_check(told, "after a few seconds you're told to use the menu (%.1f s in the pit)" % player.pit_time)
	_pg.rescue_player()
	await _w.hold(0.5)
	var door := _pg.by_the_door()
	_check(player.global_position.distance_to(door) < 2.0 and not player.in_pit(), "Back to the RV puts you by its door (%.1f m)" % player.global_position.distance_to(door))


# --- helpers ---------------------------------------------------------------------------------

func _face(dir: Vector3) -> void:
	_pg.player.look(atan2(-dir.x, -dir.z), 0.0)


func _jump() -> void:
	await _w.press(&"jump")


func _start(code: String) -> void:
	if _pg:
		_pg.queue_free()
		await get_tree().process_frame
	Session.seed_code = code
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60 * 5: # (Frames run faster than the generator thread under load.)
		await get_tree().physics_frame
		waited += 1
	_check(_pg.is_spawned, "%s spawned" % code)
	_w = Walker.new(get_tree(), _pg.player, _pg.rv)
	await _w.hold(1.0)


func _first(kind: int) -> Dictionary:
	for o: Dictionary in _pg.trip.data["obstacles"]:
		if int(o["kind"]) == kind:
			return o
	return {}


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 14.0, TerrainStreamer.WORLD_LAYER)
	var hit := _pg.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else p


func _teleport(s: float) -> void:
	var rv := _pg.rv
	_pg._place_rv(_pg.trip.road_transform(s))
	var waited := 0
	while _pg.is_rv_waiting() and waited < HZ * 30:
		await get_tree().physics_frame
		waited += 1
	await _w.hold(1.0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("climb out: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
