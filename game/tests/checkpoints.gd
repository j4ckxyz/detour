extends Node
## Headless test of going back to the last stop: wreck the RV (its frame gone) or leave it
## lying down a ravine and it's back where it last set off from, in the condition it left in,
## everyone beside it and half an hour gone; parked in a station's forecourt lane, between
## the pumps, it fits and the pump fills its tank.
##
##   godot --headless --path game --fixed-fps 60 res://tests/checkpoints.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _failures: PackedStringArray = []


func _ready() -> void:
	_run()


func _run() -> void:
	Session.seed_code = Playground.DEFAULT_SEED
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60:
		await get_tree().physics_frame
		waited += 1
	_check(_pg.is_spawned, "spawned")
	await _hold(1.0)
	await _wrecked()
	await _fallen()
	await _forecourt()
	_finish()


## Knocked about on the road out, then its frame gives: back at the camp as it set off.
func _wrecked() -> void:
	var rv := _pg.rv
	var trip := _pg.trip
	var d := rv.damage
	var start := trip.start_transform().origin
	d.fuel = 41.0
	await _teleport(220.0)
	_check(trip._left_stop, "driving off, the RV's left the camp (its state kept)")
	d.fuel = 12.0
	d.engine = 55.0
	d.frame = 0.0
	var elapsed := trip.elapsed
	await _hold(0.5)
	await _settle()
	_check(rv.global_position.distance_to(start) < 3.0, "the frame gone, the RV's back at the camp (%.1f m off)" % rv.global_position.distance_to(start))
	_check(d.frame > 99.0 and d.engine > 99.0 and absf(d.fuel - 41.0) < 0.5, "... as it set off (frame %.0f, engine %.0f, fuel %.0f L)" % [d.frame, d.engine, d.fuel])
	_check(absf(trip.elapsed - elapsed - Playground.CHECKPOINT_MINUTES * 60.0) < 5.0, "... half an hour later (%+.0f s)" % (trip.elapsed - elapsed))
	_check(_pg.player.global_position.distance_to(rv.global_position) < 8.0, "you're beside it (%.1f m)" % _pg.player.global_position.distance_to(rv.global_position))
	_check(trip.notice.begins_with("The RV's frame gave out. Back to the camp"), "told why: %s" % trip.notice)


## Lying at the bottom of the ravine under a bridge: after a few seconds, back at the camp.
## Just driving across the bridge (well above the ravine) doesn't count.
func _fallen() -> void:
	var rv := _pg.rv
	var trip := _pg.trip
	var bridge := _first(Trip.BRIDGE)
	_check(not bridge.is_empty(), "the trip has a bridge")
	if bridge.is_empty():
		return
	var s := float(bridge["s"])
	var deck := (bridge["pos"] as Vector3).y
	var on_deck := _pg.trip.road_transform(s + float(bridge["hole_at"]) - 9.0) # Clear of the hole.
	on_deck.origin.y = deck + 0.6
	_pg._place_rv(on_deck)
	await _settle()
	await _hold(Playground.FALLEN_SECONDS + 1.0)
	_check(_pg.world.road_progress(rv.global_position.x, rv.global_position.z) > s - 30.0, "sitting on the bridge deck isn't a fall")
	# Down on the ravine floor, beside the road under the deck.
	var xf := TripStructures.frame(bridge)
	var over := xf * Vector3(0.0, 0.0, 6.0)
	var floor := _ground(Vector3(over.x, deck - 2.5, over.z), 30.0)
	_check(floor.y < deck - Playground.FALLEN_DEPTH - 1.0, "the ravine is deep (%.1f m below the deck)" % (deck - floor.y))
	_pg._place_rv(Transform3D(xf.basis, floor + Vector3.UP * 1.0))
	await _hold(1.0)
	_check(rv.global_position.distance_to(trip.start_transform().origin) > 100.0, "... not at once")
	await _hold(Playground.FALLEN_SECONDS + 1.0)
	await _settle()
	var off := rv.global_position.distance_to(trip.start_transform().origin)
	_check(off < 3.0, "lying in the ravine, it's back at the camp (%.1f m off)" % off)
	_check(trip.notice.begins_with("The RV went over the edge."), "told why: %s" % trip.notice)


## Pulled into the forecourt between the pumps: it fits, and the hose reaches the tank.
func _forecourt() -> void:
	var rv := _pg.rv
	var trip := _pg.trip
	var station: Dictionary = trip.pad(1)
	await _teleport(float(station["s"]))
	var pump: Interactable = null
	for n: Node in get_tree().get_nodes_in_group(&"fuel_pumps"):
		if pump == null or (n as Node3D).global_position.distance_to(rv.global_position) < pump.global_position.distance_to(rv.global_position):
			pump = n
	_check(pump != null, "the station has pumps")
	if pump == null:
		return
	var st := (pump.get_parent() as Node3D).global_transform
	# Out on the road in front of the lane, then drive in nose first, towards the shop (the
	# station's +Z), steering for the lane's middle.
	var lane := st * Vector3(0.0, 0.0, -1.0)
	var facing := st.basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var from := lane - facing * 14.0
	from.y = _ground(from, 12.0).y + 0.4
	_pg._place_rv(Transform3D(Basis.looking_at(facing, Vector3.UP), from))
	await _settle()
	await _hold(1.0)
	_check(not rv.freeze, "the RV's down on the ground in front of the station")
	_pg.driver.enabled = false
	rv.set_automatic(true)
	rv.parking_brake = false
	var along := func() -> float: return facing.dot(rv.global_position - lane)
	var stuck := 0
	for i: int in HZ * 20:
		var to := rv.to_local(lane + facing * 6.0)
		rv.steer_input = clampf(to.x * 0.4, -1.0, 1.0)
		var v := rv.forward_speed()
		rv.throttle = clampf((2.0 - v) * 0.6 + 0.2, 0.0, 1.0) if v < 2.5 else 0.0
		rv.brake = 0.0
		stuck = stuck + 1 if i > HZ * 3 and v < 0.3 else 0
		await get_tree().physics_frame
		if along.call() > 0.0 or stuck > HZ:
			break
	rv.throttle = 0.0
	rv.steer_input = 0.0
	rv.brake = 1.0
	await _hold(1.5)
	rv.parking_brake = true
	var side := absf(st.basis.x.normalized().dot(rv.global_position - lane))
	_check(stuck <= HZ and along.call() > -1.5 and side < 1.0, "the RV drives into the lane between the pumps (%.1f m along, %.2f m off the middle)" % [along.call(), side])
	_check(rv.damage.frame > 99.0 and rv.global_basis.y.y > 0.97, "... without hitting anything (frame %.0f)" % rv.damage.frame)
	var gap := INF
	for n: Node in get_tree().get_nodes_in_group(&"fuel_pumps"):
		if (n as Node3D).get_parent() == pump.get_parent():
			gap = minf(gap, absf(rv.global_basis.x.dot((n as Node3D).global_position - rv.global_position)))
	_check(gap > 2.0, "... with room each side (%.1f m to the nearer pump)" % gap)
	rv.damage.fuel = 4.0
	_pg.player.global_position = pump.global_position + st.basis.z * 1.2
	var prompt: String = pump.prompt_for.call(_pg.player)
	_check(prompt.begins_with("Fill up"), "the pump offers to fill the tank ('%s')" % prompt)
	pump.interact(_pg.player)
	_check(rv.damage.fuel > RVDamage.TANK - 0.5, "the tank's full (%.0f L)" % rv.damage.fuel)


# --- helpers ---------------------------------------------------------------------------------

func _first(kind: int) -> Dictionary:
	for o: Dictionary in _pg.trip.data["obstacles"]:
		if int(o["kind"]) == kind:
			return o
	return {}


## Moves the RV along the road and waits until the ground there is solid.
func _teleport(s: float) -> void:
	_pg._place_rv(_pg.trip.road_transform(s))
	await _settle()
	await _hold(0.5)


func _settle() -> void:
	var waited := 0
	while _pg.is_rv_waiting() and waited < HZ * 30:
		await get_tree().physics_frame
		waited += 1


## The solid surface under a point, by raycast `depth` metres down.
func _ground(p: Vector3, depth: float) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p + Vector3.DOWN * depth, TerrainStreamer.WORLD_LAYER)
	var hit := _pg.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else p


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
		print("checkpoints: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
