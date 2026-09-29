extends Node
## Headless trip test: the generated trip's shape, starting at the camp on the road,
## reaching a gas station (checkpoint, save, restock), continuing from that save, reaching
## home, and a real obstacle: the RV can't cross a washed-out gap on its own, but crosses on
## two planks.
##
##   godot --headless --path game --fixed-fps 60 res://tests/trip_flow.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _failures: PackedStringArray = []


func _ready() -> void:
	_run()


func _start(fresh: bool) -> void:
	if _pg:
		_pg.queue_free()
		await get_tree().process_frame
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = fresh
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60:
		await get_tree().physics_frame
		waited += 1
	_check(_pg.is_spawned, "spawned")
	await _hold(1.0)


func _run() -> void:
	await _start(true)
	var trip := _pg.trip
	var rv := _pg.rv
	trip.clear_save()
	var pads := trip.pads()
	_check(pads.size() == 4 and int(pads[0]["kind"]) == Trip.PAD_CAMP and int(pads[-1]["kind"]) == Trip.PAD_HOME, "camp, two stations, home (%d stops)" % pads.size())
	var obstacles: Array = trip.data["obstacles"]
	_check(obstacles.size() >= 5, "obstacles along the road (%d)" % obstacles.size())
	var s0 := _pg.world.road_progress(rv.global_position.x, rv.global_position.z)
	_check(s0 >= 0.0 and s0 < 60.0, "starts on the road at the camp (%.0f m along)" % s0)
	_check(rv.global_basis.y.dot(Vector3.UP) > 0.97, "parked level on the road")
	var planks_near_gaps := true
	for o: Dictionary in obstacles:
		if int(o["kind"]) == 0:
			planks_near_gaps = planks_near_gaps and _items_near(o["pos"], &"plank", 60.0) >= 2
	_check(planks_near_gaps, "planks lie somewhere near every gap")

	# Obstacle shapes in the ground.
	for o: Dictionary in obstacles:
		var pos: Vector3 = o["pos"]
		var dir: Vector3 = o["dir"]
		match int(o["kind"]):
			0:
				var drop := _pg.world.height_at(pos.x - dir.x * 4.0, pos.z - dir.z * 4.0) - _pg.world.height_at(pos.x, pos.z)
				_check(drop > float(o["size"]) * 0.6, "gap at %.0f m is a trench (%.2f m deep)" % [o["s"], drop])
			1:
				var rise := _pg.world.height_at(pos.x + dir.x * 2.0, pos.z + dir.z * 2.0) - _pg.world.height_at(pos.x - dir.x * 2.0, pos.z - dir.z * 2.0)
				_check(rise > float(o["size"]) * 0.8, "ledge at %.0f m steps up (%.2f m)" % [o["s"], rise])
			2:
				_check(_pg.world.mud_at(pos.x, pos.z) > 0.9, "mud at %.0f m is muddy" % o["s"])

	# A gap: stuck without planks, across with two.
	var gap: Dictionary = {}
	for o: Dictionary in obstacles:
		if int(o["kind"]) == 0:
			gap = o
			break
	if not gap.is_empty():
		await _gap_crossing(gap)

	# Drive into the first station: checkpoint, save, restock.
	var station := trip.pad(1)
	var reached := [false]
	trip.checkpoint_reached.connect(func(_i: int, _n: int) -> void: reached[0] = true)
	await _teleport(float(station["s"]) - 40.0)
	await _drive(0.6, 12.0, func() -> bool: return reached[0])
	_check(reached[0] and trip.checkpoint == 1, "arrived at gas station 1")
	_check(FileAccess.file_exists(trip._save_path()), "checkpoint saved")
	_check(_items_near(station["pos"], &"jerrycan", 25.0) >= 1, "the station restocked supplies")

	# Continue from the save.
	await _start(false)
	trip = _pg.trip
	_check(trip.checkpoint == 1, "a new session continues from gas station 1")
	var at_station := _pg.world.road_progress(_pg.rv.global_position.x, _pg.rv.global_position.z)
	_check(absf(at_station - float(trip.pad(1)["s"])) < 30.0, "the RV starts at gas station 1 (%.0f m)" % at_station)

	# Home.
	var done := [false]
	trip.finished.connect(func() -> void: done[0] = true)
	trip.checkpoint = trip.pads().size() - 2
	var d := _pg.rv.damage
	_check(d.tires.min() < RVDamage.FULL or d.bolts.min() < RVDamage.BOLTS or d.fuel != RVDamage.START_FUEL, "the RV's wear came back with the save")
	for i: int in 4: # A mechanic's once-over, so the drive home tests the trip, not the tires.
		d.tires[i] = RVDamage.FULL
		d.bolts[i] = RVDamage.BOLTS
	d.fuel = RVDamage.TANK
	await _teleport(float(trip.pad(-1)["s"]) - 40.0)
	await _drive(0.6, 14.0, func() -> bool: return done[0])
	_check(done[0] and trip.is_finished, "reached home: trip complete")
	_check(not FileAccess.file_exists(trip._save_path()), "the finished trip's save is cleared")
	_check(trip.summary().begins_with("Home in"), "a trip summary: %s" % trip.summary())
	_finish()


func _gap_crossing(gap: Dictionary) -> void:
	var trip := _pg.trip
	var rv := _pg.rv
	var s := float(gap["s"])
	var pos: Vector3 = gap["pos"]
	var dir: Vector3 = gap["dir"]
	# Without planks: the front wheels drop in and it doesn't get across.
	await _teleport(s - 25.0)
	await _drive(0.8, 12.0, func() -> bool: return false)
	_check(rv.global_position.y > _pg.world.height_at(rv.global_position.x, rv.global_position.z) - 3.0, "the RV stayed on (or in) the ground")
	var progress := _pg.world.road_progress(rv.global_position.x, rv.global_position.z)
	_check(progress < s + 6.0, "without planks the RV can't cross the gap (stuck at %.1f m, gap at %.1f m)" % [progress, s])

	# Two planks across it, one under each wheel track.
	await _teleport(s - 25.0)
	var side := Vector3(-dir.z, 0.0, dir.x)
	for offset: float in [-0.9, 0.9]:
		var plank := ItemLibrary.create(&"plank")
		_pg.items.add_child(plank)
		var c := pos + side * offset
		var reach := ItemLibrary.PLANK_LENGTH * 0.5 - 0.15
		var a := _ground(c - dir * reach)
		var b := _ground(c + dir * reach)
		var x := (b - a).normalized()
		var up := x.cross(Vector3.UP).cross(x).normalized()
		if up.y < 0.0:
			up = -up
		plank.place(_pg.items, Transform3D(Basis(x, up, x.cross(up)), (a + b) * 0.5 + up * 0.03))
	await _hold(1.0)
	await _drive(0.8, 16.0, func() -> bool: return _pg.world.road_progress(rv.global_position.x, rv.global_position.z) > s + 12.0)
	progress = _pg.world.road_progress(rv.global_position.x, rv.global_position.z)
	_check(progress > s + 12.0, "on two planks the RV crosses the gap (reached %.1f m)" % progress)


## Drives straight down the road in automatic, steering to stay on it, until `done` or time.
func _drive(throttle: float, seconds: float, done: Callable) -> void:
	var rv := _pg.rv
	_pg.driver.enabled = false
	rv.set_automatic(true)
	rv.parking_brake = false
	for i: int in roundi(seconds * HZ):
		var s := _pg.world.road_progress(rv.global_position.x, rv.global_position.z)
		if s >= 0.0:
			var ahead := _pg.trip.road_transform(s + 10.0).origin
			var to := rv.to_local(ahead)
			rv.steer_input = clampf(to.x * 0.25, -1.0, 1.0)
		rv.throttle = throttle
		if OS.has_environment("TRIP_TRACE") and i % HZ == 0:
			print("    t%d s %.1f v %.2f gear %d rpm %.0f park %s frozen %s y %.1f" % [i / HZ, s, rv.forward_speed(), rv.drivetrain.gear, rv.drivetrain.rpm, rv.parking_brake, rv.freeze, rv.global_position.y])
		await get_tree().physics_frame
		if done.call():
			break
	rv.throttle = 0.0
	rv.steer_input = 0.0
	rv.brake = 1.0
	await _hold(0.6)
	rv.brake = 0.0
	rv.parking_brake = true


func _items_near(pos: Vector3, kind: StringName, radius: float) -> int:
	var n := 0
	for node: Node in get_tree().get_nodes_in_group(&"items"):
		var it := node as Item
		if it and it.kind == kind and Vector2(it.global_position.x - pos.x, it.global_position.z - pos.z).length() < radius:
			n += 1
	return n


## The solid surface under a point (terrain, abutment, placed plank), by raycast.
func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, TerrainStreamer.WORLD_LAYER)
	var hit := _pg.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else p


## Moves the RV along the road and waits until the ground there is solid.
func _teleport(s: float) -> void:
	_pg._place_rv(_pg.trip.road_transform(s))
	var waited := 0
	while _pg.is_rv_waiting() and waited < HZ * 30:
		await get_tree().physics_frame
		waited += 1
	await _hold(1.0)


func _hold(seconds: float) -> void:
	for i: int in roundi(seconds * HZ):
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _pg:
		_pg.trip.clear_save()
	if _failures.is_empty():
		print("trip flow: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
