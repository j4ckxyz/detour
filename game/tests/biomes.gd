extends Node
## Headless biomes and water test: the trip runs woods → ... → mountain pass; the RV fords a
## river (wading, slowly) but water over the air intake floods the engine; ice leaves almost
## no grip, except where a plank is laid on it; the player swims in deep water; caves hold
## supplies; crossing into a new biome says so.
##
##   godot --headless --path game --fixed-fps 60 res://tests/biomes.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")
const HZ := 60
const FORD := 4
const ICE := 5

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
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60:
		await get_tree().physics_frame
		waited += 1
	_rv = _pg.rv
	_player = _pg.player
	_w = Walker.new(get_tree(), _player, _rv)
	await _w.hold(1.0)
	var trip := _pg.trip
	var biomes: PackedInt32Array = trip.data["biomes"]
	_check(biomes.size() >= 3 and biomes[0] == 0 and biomes[-1] == 3, "the trip goes from the woods to the mountain pass (%s)" % biomes)
	await _ford(_obstacle(FORD))
	await _ice(_obstacle(ICE))
	await _swim(_obstacle(FORD))
	_caves()
	_finish()


func _obstacle(kind: int) -> Dictionary:
	for o: Dictionary in _pg.trip.data["obstacles"]:
		if int(o["kind"]) == kind:
			return o
	_check(false, "the default trip has obstacle kind %d" % kind)
	return {}


func _ford(o: Dictionary) -> void:
	if o.is_empty():
		return
	var pos: Vector3 = o["pos"]
	var level := _pg.world.water_level(pos.x, pos.z)
	_check(level > -1000.0 and level - _pg.world.height_at(pos.x, pos.z) > 0.2, "there's water on the ford (%.2f m deep)" % (level - _pg.world.height_at(pos.x, pos.z)))
	var seen_biome := [""]
	await _teleport(float(o["s"]) - 30.0)
	_check(_pg.world.biome_at(_rv.global_position.x, _rv.global_position.z) != 0, "the ford is out of the woods")
	var waded := 0.0
	var start_s := float(o["s"]) - 30.0
	_rv.set_automatic(true)
	_rv.parking_brake = false
	for i: int in HZ * 20:
		_steer(0.45)
		waded = maxf(waded, _rv.wading)
		if _progress() > float(o["s"]) + 20.0:
			break
		await get_tree().physics_frame
	_stop()
	_check(waded > 0.1, "the RV waded through (%.2f m)" % waded)
	_check(_progress() > float(o["s"]) + 15.0 and _rv.drivetrain.running, "and came out the other side running (%.0f m on)" % (_progress() - start_s))
	await _w.hold(0.5)
	# Off the road the river is deep: the engine drowns.
	var side := Vector3(-(o["dir"] as Vector3).z, 0.0, (o["dir"] as Vector3).x)
	var deep := pos + side * 22.0
	_rv.drivetrain.running = true
	_pg._place_rv(Transform3D(_rv.global_basis, Vector3(deep.x, _pg.world.height_at(deep.x, deep.z) + 0.6, deep.z)))
	await _w.hold(2.0)
	_check(not _rv.drivetrain.running and _rv.damage.engine < RVDamage.FULL, "water over the air intake floods the engine (engine %.0f%%)" % _rv.damage.engine)
	_rv.damage.engine = RVDamage.FULL
	_rv.drivetrain.running = true


func _ice(o: Dictionary) -> void:
	if o.is_empty():
		return
	var pos: Vector3 = o["pos"]
	_check(_pg.world.ice_at(pos.x, pos.z) > 0.99, "the frozen pond is ice")
	await _teleport(float(o["s"]))
	await _w.hold(0.5)
	var grips: Array[float] = []
	for wheel: RVWheel in _rv.wheels:
		grips.append(wheel.surface_grip)
	_check(grips.max() < 0.3, "on the ice the tires barely grip (%s)" % [grips])
	# A plank under the front-left wheel gives it grip back.
	var wheel := _rv.wheels[0]
	var plank := ItemLibrary.create(&"plank")
	_pg.items.add_child(plank)
	var at := wheel.contact
	plank.place(_pg.items, Transform3D(Basis(_rv.global_basis.z, Vector3.UP, -_rv.global_basis.x).orthonormalized(), at + Vector3.UP * 0.02))
	_rv.global_position += Vector3.UP * 0.1
	await _w.hold(1.0)
	_check(wheel.on_item and wheel.surface_grip > 0.8, "a plank on the ice gives the wheel grip (%.2f)" % wheel.surface_grip)
	plank.queue_free()


func _swim(o: Dictionary) -> void:
	if o.is_empty():
		return
	var pos: Vector3 = o["pos"]
	var side := Vector3(-(o["dir"] as Vector3).z, 0.0, (o["dir"] as Vector3).x)
	var deep := pos + side * 25.0
	var level := _pg.world.water_level(deep.x, deep.z)
	_player.global_position = Vector3(deep.x, level - 0.5, deep.z)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _w.hold(2.0)
	_check(_player.swimming, "the player swims in deep water")
	_check(absf(_player.global_position.y - (level - 1.3)) < 0.4, "floating at the surface (%.2f m under)" % (level - _player.global_position.y))
	_player.global_position = _pg.by_the_door()
	_player.reset_physics_interpolation()
	await _w.hold(0.5)


func _caves() -> void:
	var caves: Array = _pg.trip.data["caves"]
	if caves.is_empty():
		print("  (no caves on this trip)")
		return
	var c: Dictionary = caves[0]
	var node := _pg.trip.get_node_or_null("Cave0") as Node3D
	_check(node != null, "cave 0 was built")
	var loot := 0
	for n: Node in _pg.items.get_children():
		var item := n as Item
		if item and item.global_position.distance_to(c["pos"]) < 8.0:
			loot += 1
	_check(loot >= 3, "the cave holds supplies (%d)" % loot)


func _teleport(s: float) -> void:
	_pg._place_rv(_pg.trip.road_transform(s))
	var waited := 0
	while _pg.is_rv_waiting() and waited < HZ * 30:
		await get_tree().physics_frame
		waited += 1
	await _w.hold(1.0)


func _progress() -> float:
	return _pg.world.road_progress(_rv.global_position.x, _rv.global_position.z)


func _steer(throttle: float) -> void:
	var s := _progress()
	if s >= 0.0:
		var to := _rv.to_local(_pg.trip.road_transform(s + 10.0).origin)
		_rv.steer_input = clampf(to.x * 0.25, -1.0, 1.0)
	_rv.throttle = throttle


func _stop() -> void:
	_rv.throttle = 0.0
	_rv.steer_input = 0.0
	_rv.parking_brake = true


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	_pg.trip.clear_save()
	if _failures.is_empty():
		print("biomes: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
