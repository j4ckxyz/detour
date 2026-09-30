extends Node
## Headless test of the generator's harder crossings, driven for real: a bridge with a hole
## in its deck (creep onto it and the front drops in; hit the kicker fast and it jumps the
## hole; or lay two planks across it), two narrow beams over a ravine (lined up it creeps
## across; off-line a wheel drops), a steep hill climbed at full throttle, and a gully jumped
## off its kicker at speed (but not at a crawl).
##
##   godot --headless --path game --fixed-fps 60 res://tests/crossings.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60
## A short trip with a jump (6.6 m) in it.
const JUMP_SEED := "DT6-00000-0009Q"

var _pg: Playground
var _failures: PackedStringArray = []


func _ready() -> void:
	_run()


func _run() -> void:
	await _start(Playground.DEFAULT_SEED)
	var bridge := _first(Trip.BRIDGE)
	var beams := _first(Trip.BEAMS)
	var hill := _first(Trip.HILL)
	_check(not bridge.is_empty() and not beams.is_empty() and not hill.is_empty(), "the default trip has a bridge, beams and a hill")
	if not bridge.is_empty():
		await _bridge(bridge)
	if not beams.is_empty():
		await _beams(beams)
	if not hill.is_empty():
		await _hill(hill)
	await _start(JUMP_SEED)
	var jump := _first(Trip.JUMP)
	_check(not jump.is_empty(), "the jump seed has a jump")
	if not jump.is_empty():
		await _jump(jump)
	_finish()


func _bridge(o: Dictionary) -> void:
	var s := float(o["s"])
	var half := float(o["length"]) * 0.5
	var hole_end := s + float(o["hole_at"]) + float(o["hole"]) * 0.5
	var deck := (o["pos"] as Vector3).y
	var past := func() -> bool: return _progress() > s + half + 8.0
	# Creeping onto it, the front wheels drop into the hole.
	await _teleport(s - half - 20.0)
	var low := await _drive(2.5, 30.0, past)
	_check(_progress() < hole_end + 2.0 or low < deck - 1.5, "creeping, the RV doesn't get past the hole (%.1f m, hole ends %.1f m; lowest %.1f m, deck %.1f m)" % [_progress(), hole_end, low, deck])
	# Hit the kicker fast and it jumps the hole.
	await _teleport(s - half - 70.0)
	var top := [0.0]
	var watch := func() -> bool:
		if _progress() < s + float(o["hole_at"]) - float(o["hole"]) * 0.5:
			top[0] = _pg.rv.forward_speed()
		return _progress() > s + half + 8.0
	low = await _drive(17.0, 30.0, watch)
	_check(_progress() > s + half + 8.0 and low > deck - 1.0, "at %.0f km/h it jumps the hole and carries on (%.1f m, lowest %.1f m)" % [top[0] * 3.6, _progress(), low])
	# Or: two planks across the hole, one under each wheel track.
	await _teleport(s - half - 20.0)
	var xf := TripStructures.frame(o)
	var dir := -xf.basis.z
	for x: float in [-0.91, 0.91]:
		var plank := ItemLibrary.create(&"plank")
		_pg.items.add_child(plank)
		var c := xf * Vector3(x, 0.0, -float(o["hole_at"]))
		var a := _ground(c - dir * (ItemLibrary.PLANK_LENGTH * 0.5 - 0.15))
		var b := _ground(c + dir * (ItemLibrary.PLANK_LENGTH * 0.5 - 0.15))
		var ax := (b - a).normalized()
		var up := ax.cross(Vector3.UP).cross(ax).normalized()
		if up.y < 0.0:
			up = -up
		plank.place(_pg.items, Transform3D(Basis(ax, up, ax.cross(up)), (a + b) * 0.5 + up * 0.04))
	await _hold(0.5)
	low = await _drive(2.5, 40.0, past)
	_check(_progress() > s + half + 8.0 and low > deck - 1.0, "on two planks it creeps across (%.1f m, lowest %.1f m)" % [_progress(), low])


func _beams(o: Dictionary) -> void:
	var s := float(o["s"])
	var half := float(o["length"]) * 0.5
	var deck := (o["pos"] as Vector3).y
	var past := func() -> bool: return _progress() > s + half + 8.0
	await _teleport(s - half - 25.0)
	var low := await _drive(2.0, 40.0, past)
	_check(_progress() > s + half + 8.0 and low > deck - 1.0, "lined up, it creeps across the beams (%.1f m, lowest %.1f m)" % [_progress(), low])
	await _teleport(s - half - 25.0, 0.7)
	low = await _drive(2.0, 30.0, past, 0.7)
	_check(low < deck - 1.0 or _progress() < s + half, "0.7 m off-line the wheels drop off (%.1f m, lowest %.1f m)" % [_progress(), low])


func _hill(o: Dictionary) -> void:
	var s := float(o["s"])
	var top := s + float(o["length"])
	await _teleport(s - 40.0)
	var start := _pg.rv.global_position.y
	await _drive(20.0, 60.0, func() -> bool: return _progress() > top + 5.0)
	_check(_progress() > top + 5.0, "full throttle climbs the hill (%.0f m, top at %.0f m, %.0f m up)" % [_progress(), top, _pg.rv.global_position.y - start])
	var spurs: Array = _pg.trip.data["spurs"]
	_check(not spurs.is_empty(), "a side track leaves at the hill's foot")
	if not spurs.is_empty():
		var pts: PackedVector3Array = spurs[0]["points"]
		var end := pts[pts.size() - 1]
		_check(end.y < pts[0].y and _pg.world.road_progress(end.x, end.z) < 0.0, "it heads downhill, away from the road")


func _jump(o: Dictionary) -> void:
	var s := float(o["s"])
	var half := float(o["length"]) * 0.5
	var level := (o["pos"] as Vector3).y
	var past := func() -> bool: return _progress() > s + half + 12.0
	await _teleport(s - half - 18.0)
	var low := await _drive(3.0, 30.0, past)
	_check(_progress() < s + half or low < level - 2.0, "at a crawl the RV drops into the gully (%.1f m, lowest %.1f m)" % [_progress(), low])
	await _teleport(s - half - 130.0)
	var top := [0.0]
	var watch := func() -> bool:
		if _progress() < s - half:
			top[0] = _pg.rv.forward_speed()
		return _progress() > s + half + 12.0
	low = await _drive(20.0, 40.0, watch)
	_check(_progress() > s + half + 12.0 and low > level - 2.0, "at %.0f km/h it clears the %.1f m gully (%.1f m, lowest %.1f m)" % [top[0] * 3.6, float(o["length"]), _progress(), low])


# --- helpers ---------------------------------------------------------------------------------

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
	await _hold(1.0)


func _first(kind: int) -> Dictionary:
	for o: Dictionary in _pg.trip.data["obstacles"]:
		if int(o["kind"]) == kind:
			return o
	return {}


## Drives down the road in automatic at about `speed` m/s, steering `lateral` metres right
## of the centreline, until `done` or time. Returns the lowest the RV got.
func _drive(speed: float, seconds: float, done: Callable, lateral: float = 0.0) -> float:
	var rv := _pg.rv
	_pg.driver.enabled = false
	rv.set_automatic(true)
	rv.parking_brake = false
	var low := rv.global_position.y
	for i: int in roundi(seconds * HZ):
		var s := _progress()
		if s >= 0.0:
			var ahead := _pg.trip.road_transform(s + 9.0)
			var here := _pg.trip.road_transform(s)
			var off := here.basis.x.dot(rv.global_position - here.origin) - lateral
			var to := rv.to_local(ahead.origin + ahead.basis.x * lateral)
			rv.steer_input = clampf(to.x * 0.3 - off * 0.4, -1.0, 1.0)
		var v := rv.forward_speed()
		rv.throttle = clampf((speed - v) * 0.6 + 0.25, 0.0, 1.0) if v < speed + 0.5 else 0.0
		rv.brake = clampf((v - speed - 1.0) * 0.3, 0.0, 1.0)
		low = minf(low, rv.global_position.y)
		if OS.has_environment("CROSS_TRACE") and i % 20 == 0:
			var near := _pg.trip.road_transform(maxf(s, 0.0))
			print("    s %.1f v %.1f lateral %.2f y %.2f" % [s, v, near.basis.x.dot(rv.global_position - near.origin), rv.global_position.y])
		await get_tree().physics_frame
		if done.call():
			break
	rv.throttle = 0.0
	rv.steer_input = 0.0
	rv.brake = 1.0
	await _hold(0.6)
	rv.brake = 0.0
	rv.parking_brake = true
	return low


func _progress() -> float:
	var p := _pg.rv.global_position
	return _pg.world.road_progress(p.x, p.z)


## The solid surface under a point (terrain, deck, kicker), by raycast.
func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, TerrainStreamer.WORLD_LAYER)
	var hit := _pg.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else p


## Moves the RV along the road and waits until the ground there is solid.
func _teleport(s: float, lateral: float = 0.0) -> void:
	var rv := _pg.rv
	rv.damage.engine = RVDamage.FULL
	rv.drivetrain.running = true
	for i: int in 4:
		rv.damage.tires[i] = RVDamage.FULL
	var xf := _pg.trip.road_transform(s)
	_pg._place_rv(xf.translated(xf.basis.x * lateral))
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
	Session.seed_code = ""
	if _failures.is_empty():
		print("crossings: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
