extends Node
## Headless test of bridging a real trip's washed-out gap with planks, from the player's own
## view: standing at various distances from the edge and looking down into the trench, the
## preview lies across it (level with the road, centred, resting on both banks), lined up with
## the RV's wheel track; two planks laid one after the other take the two tracks; and the RV
## then creeps across on them. All the gaps in a few trips are the width the planks are made for.
##
##   godot --headless --path game --fixed-fps 60 res://tests/plank_bridges.tscn

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
	_check(not gap.is_empty(), "the default trip has a gap")
	if gap.is_empty():
		_finish()
		return
	var s := float(gap["s"])
	var half := float(gap["length"]) * 0.5
	var deck := (gap["pos"] as Vector3).y
	_check(float(gap["length"]) <= ItemLibrary.PLANK_LENGTH - 1.6 + 0.001, "the gap is %.1f m: a %.0f m plank spans it with room to spare" % [gap["length"], ItemLibrary.PLANK_LENGTH])
	await _teleport(s - half - 14.0)
	var rv := _pg.rv
	var heading := -rv.global_basis.z
	heading.y = 0.0
	heading = heading.normalized()
	var right := heading.cross(Vector3.UP)
	var centre: Vector3 = gap["pos"]

	# Standing at various distances from the edge, looking down into the trench.
	for back: float in [1.0, 2.5, 4.0]:
		await _stand(gap, back)
		var plank := await _hold_plank()
		_w.face(centre + Vector3.DOWN * float(gap["size"]) * 0.8)
		await _w.hold(0.2)
		var plan := ItemLibrary.plank_plan(_pg.player)
		_check(not plan.is_empty() and plan["bridging"] and plan["secure"], "standing %.1f m back, looking into the trench: a secure bridge (%s)" % [back, plan.get("bridging")])
		if not plan.is_empty():
			var xf: Transform3D = plan["xf"]
			var along := (xf.origin - centre).dot(heading)
			_check(absf(along) < 0.6, "centred on the gap (%.2f m off)" % along)
			_check(absf(xf.origin.y - deck) < 0.25 and absf(xf.basis.x.y) < 0.05, "at the road's level, not down in the trench (%.2f m from the road, slope %.3f)" % [xf.origin.y - deck, xf.basis.x.y])
			_check(absf(absf(xf.basis.x.dot(heading)) - 1.0) < 0.01, "lined up with the RV's heading (%.3f)" % xf.basis.x.dot(heading))
			var lateral := (xf.origin - rv.global_position).dot(right)
			_check(absf(absf(lateral) - RV.TRACK * 0.5) < 0.15, "on a wheel track (%.2f m off the RV's middle)" % lateral)
			var tips_ok := _rests_on_both_banks(xf)
			_check(tips_ok, "both ends rest on ground")
		_drop(plank)

	# Two planks, one for each wheel track, aimed a little either side of the middle.
	await _stand(gap, 2.0)
	var laid: Array[Item] = []
	for side: float in [-1.0, 1.0]:
		var plank := await _hold_plank()
		_w.face(centre + right * side * 0.7 + Vector3.DOWN * float(gap["size"]) * 0.8)
		await _w.hold(0.2)
		await _w.press(&"use_item")
		_check(plank.is_placed(), "the plank on the %s is laid" % ("left" if side < 0.0 else "right"))
		laid.append(plank)
	if laid.size() == 2:
		var lateral := absf((laid[0].global_position - laid[1].global_position).dot(right))
		_check(absf(lateral - RV.TRACK) < 0.15, "they're a wheel track apart (%.2f m)" % lateral)
		_check(absf(laid[0].global_basis.x.dot(laid[1].global_basis.x)) > 0.995, "and parallel")
	await _teleport(s - half - 12.0)
	var past := func() -> bool: return _progress() > s + half + 8.0
	var low := await _drive(2.5, 40.0, past)
	_check(_progress() > s + half + 8.0 and low > deck - 1.0, "the RV creeps across on the planks (%.1f m along, gap at %.1f m, lowest %.1f m, road %.1f m)" % [_progress(), s, low, deck])

	# The hole in a timber bridge's deck, from the deck itself.
	var bridge := _first(Trip.BRIDGE)
	_check(not bridge.is_empty(), "the trip has a bridge")
	if not bridge.is_empty():
		await _bridge_hole(bridge)

	# The rest of the plank gaps in a few more trips are all the same size or less.
	for code: String in ["DT6-00000-0000M", "DT6-00000-0009Q"]:
		await _start(code)
		for o: Dictionary in _pg.trip.data["obstacles"]:
			if int(o["kind"]) == Trip.GAP:
				_check(float(o["length"]) <= ItemLibrary.PLANK_LENGTH - 1.6 + 0.001, "%s: a %.1f m gap" % [code, o["length"]])
	_finish()


## Two planks across the hole in a bridge's deck, laid from the preview, and the RV over them.
func _bridge_hole(bridge: Dictionary) -> void:
	var s := float(bridge["s"])
	var half := float(bridge["length"]) * 0.5
	var dir: Vector3 = bridge["dir"]
	var right := dir.cross(Vector3.UP)
	var hole := float(bridge["hole"])
	var hole_centre: Vector3 = (bridge["pos"] as Vector3) + dir * float(bridge["hole_at"])
	var deck := (bridge["pos"] as Vector3).y
	_check(hole <= ItemLibrary.PLANK_LENGTH - 1.6 + 0.001, "the hole is %.1f m across" % hole)
	await _teleport(s - half - 14.0)
	await _stand_at(hole_centre - dir * (hole * 0.5 + 2.0), dir)
	var plank := await _hold_plank()
	_w.face(hole_centre + Vector3.DOWN * 3.0)
	await _w.hold(0.3)
	var plan := ItemLibrary.plank_plan(_pg.player)
	_check(not plan.is_empty() and plan["bridging"] and plan["secure"], "on the deck, looking into the hole: a secure bridge")
	if not plan.is_empty():
		var xf: Transform3D = plan["xf"]
		var surface := _ground(hole_centre - dir * (hole * 0.5 + 1.0)).y # (The deck's top, a little above the road's level.)
		_check(absf((xf.origin - hole_centre).dot(dir)) < 0.6 and absf(xf.origin.y - surface) < 0.15, "centred on the hole (%.2f m off), level with the deck (%.2f m)" % [(xf.origin - hole_centre).dot(dir), xf.origin.y - surface])
	_drop(plank)
	var laid: Array[Item] = []
	for side: float in [-1.0, 1.0]:
		var next := await _hold_plank()
		_w.face(hole_centre + right * side * 0.7 + Vector3.DOWN * 3.0)
		await _w.hold(0.3)
		await _w.press(&"use_item")
		_check(next.is_placed(), "a plank laid on the %s" % ("left" if side < 0.0 else "right"))
		laid.append(next)
	await _teleport(s - half - 14.0)
	var past := func() -> bool: return _progress() > s + half + 8.0
	var low := await _drive(2.5, 60.0, past)
	_check(_progress() > s + half + 8.0 and low > deck - 1.5, "the RV creeps over the bridge and the hole on the planks (%.1f m along, bridge at %.1f m, lowest %.1f m, deck %.1f m)" % [_progress(), s, low, deck])


# --- helpers ---------------------------------------------------------------------------------

## Both ends of a laid plank have ground under them, at about the plank's height.
func _rests_on_both_banks(xf: Transform3D) -> bool:
	var half := xf.basis.x * ItemLibrary.PLANK_LENGTH * 0.5
	for tip: Vector3 in [xf.origin - half * 0.9, xf.origin + half * 0.9]:
		var ground := _ground(tip)
		if absf(ground.y - xf.origin.y) > 0.25:
			return false
	return true


## On the road `back` metres before the gap's near edge, facing it.
func _stand(gap: Dictionary, back: float) -> void:
	var dir: Vector3 = gap["dir"]
	await _stand_at((gap["pos"] as Vector3) - dir * (float(gap["length"]) * 0.5 + back), dir)


func _stand_at(at: Vector3, dir: Vector3) -> void:
	at.y = _ground(at).y + 0.1
	var player := _pg.player
	player.global_position = at
	player.velocity = Vector3.ZERO
	player.look(atan2(-dir.x, -dir.z), -0.3)
	await _w.hold(0.6)


func _hold_plank() -> Item:
	var plank := ItemLibrary.create(&"plank")
	_pg.items.add_child(plank)
	plank.global_position = _pg.player.global_position + Vector3.UP
	await _w.hold(0.1)
	_pg.player.pick_up(plank)
	return plank


## Puts a held plank away for the next case.
func _drop(plank: Item) -> void:
	_pg.player.held = null
	plank.queue_free()


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


func _progress() -> float:
	var p := _pg.rv.global_position
	return _pg.world.road_progress(p.x, p.z)


func _ground(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 3.0, p + Vector3.DOWN * 6.0, TerrainStreamer.WORLD_LAYER)
	var hit := _pg.get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"] if hit else p


func _teleport(s: float) -> void:
	var rv := _pg.rv
	rv.damage.engine = RVDamage.FULL
	rv.drivetrain.running = true
	for i: int in 4:
		rv.damage.tires[i] = RVDamage.FULL
	_pg._place_rv(_pg.trip.road_transform(s))
	var waited := 0
	while _pg.is_rv_waiting() and waited < HZ * 30:
		await get_tree().physics_frame
		waited += 1
	await _w.hold(1.0)


func _drive(speed: float, seconds: float, done: Callable) -> float:
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
			var off := here.basis.x.dot(rv.global_position - here.origin)
			var to := rv.to_local(ahead.origin)
			rv.steer_input = clampf(to.x * 0.3 - off * 0.4, -1.0, 1.0)
		var v := rv.forward_speed()
		rv.throttle = clampf((speed - v) * 0.6 + 0.25, 0.0, 1.0) if v < speed + 0.5 else 0.0
		rv.brake = clampf((v - speed - 1.0) * 0.3, 0.0, 1.0)
		low = minf(low, rv.global_position.y)
		await get_tree().physics_frame
		if done.call():
			break
	rv.throttle = 0.0
	rv.steer_input = 0.0
	rv.brake = 1.0
	await _w.hold(0.6)
	rv.brake = 0.0
	rv.parking_brake = true
	return low


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("plank bridges: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
