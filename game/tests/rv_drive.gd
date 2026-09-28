extends Node
## Headless driving test: loads the playground, waits for the RV to spawn on streamed
## collision, then drives a scripted sequence and checks the RV behaves: it settles on its
## wheels, stalls when the clutch is dumped, restarts, pulls away in 1st, shifts to 2nd,
## brakes to a stop, and the automatic drives forwards and backwards. Also checks the map
## got decorated (trees, rocks, colliders).
##
##   godot --headless --path game --fixed-fps 60 res://tests/rv_drive.tscn
##
## A scene rather than a `--script` test, because it needs the autoloads.

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _rv: RV
var _failures: PackedStringArray = []
var _min_up := 1.0


func _ready() -> void:
	_pg = PLAYGROUND.instantiate()
	add_child(_pg)
	_run()


func _run() -> void:
	var waited := 0
	while not _pg.is_spawned:
		await get_tree().physics_frame
		waited += 1
		if waited > HZ * 60:
			_failures.append("RV never spawned (no collision under it?)")
			_finish()
			return
	_rv = _pg.rv
	_pg.driver.enabled = false # This test holds the controls.
	var streamer := _pg.streamer
	_check(streamer.trees_loaded > 0, "trees streamed in")
	_check(streamer.props_loaded > 0, "rocks/stumps/logs streamed in")
	_check(streamer.bodies_loaded > 0, "collision built")

	await _settle()
	await _stall_and_restart()
	await _pull_away_and_shift()
	_check(not _rv.parking_brake, "throttle released the parking brake")
	await _brake_to_stop()
	await _automatic()
	_check(_min_up > 0.5, "stayed on its wheels (min up·Y %.2f)" % _min_up)
	_finish()


func _settle() -> void:
	_check(_rv.parking_brake, "spawns with the parking brake on")
	await _hold(2.0)
	var ground := _pg.world.height_at(_rv.global_position.x, _rv.global_position.z)
	var grounded := 0
	for w: RVWheel in _rv.wheels:
		grounded += 1 if w.grounded else 0
	_check(grounded == 4, "all four wheels on the ground (%d)" % grounded)
	_check(_rv.global_basis.y.dot(Vector3.UP) > 0.9, "settled upright")
	# Body lean should match the ground under the wheels (the spawn picks near-level spots).
	var spots: Array[float] = []
	for w: RVWheel in _rv.wheels:
		spots.append(_pg.world.height_at(w.global_position.x, w.global_position.z))
	var ground_roll := rad_to_deg(atan2((spots[0] + spots[2]) - (spots[1] + spots[3]), 2.0 * RV.TRACK))
	var body_roll := rad_to_deg(asin(-_rv.global_basis.x.y))
	var lengths := PackedFloat32Array()
	for w: RVWheel in _rv.wheels:
		lengths.append(snappedf(w.length, 0.01))
	print("    spawn: ground roll %.1f°, body roll %.1f°, spring lengths %s" % [ground_roll, body_roll, lengths])
	if OS.has_environment("RV_TEST_TRACE"):
		var space := _rv.get_world_3d().direct_space_state
		for w: RVWheel in _rv.wheels:
			var from := w.global_position + Vector3.UP * 2.0
			var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0, TerrainStreamer.WORLD_LAYER)
			var hit := space.intersect_ray(q)
			print("    %s mount %s ray hit y %.2f shape %s  height_at %.2f" % [w.name, w.global_position.snappedf(0.01),
				(hit["position"] as Vector3).y if hit else NAN, hit.get("shape", "-"),
				_pg.world.height_at(w.global_position.x, w.global_position.z)])
	_check(absf(body_roll) < 8.0, "parked level enough (roll %.1f°)" % body_roll)
	_check(_rv.linear_velocity.length() < 0.3, "at rest (%.2f m/s)" % _rv.linear_velocity.length())
	_check(absf(_rv.global_position.y - ground) < 0.6, "rides at the right height (%.2f m off the ground)" % (_rv.global_position.y - ground))
	_check(_rv.drivetrain.running, "engine idling")


func _stall_and_restart() -> void:
	_rv.clutch_input = 1.0
	await _hold(0.4)
	_rv.select_gear(1)
	_check(_rv.drivetrain.gear == 1, "into 1st with the clutch down")
	_rv.brake = 1.0
	_rv.clutch_input = 0.0 # Dumped against the brakes, no throttle.
	await _hold(1.5)
	_check(not _rv.drivetrain.running, "stalls when the clutch is dumped at rest")
	_rv.brake = 0.0
	_rv.clutch_input = 1.0
	await _hold(0.3)
	_rv.start_engine()
	await _hold(1.2)
	_check(_rv.drivetrain.running, "restarts with the clutch down")


## Re-places the RV at a clear spot with room ahead, so each phase starts fresh whatever the
## last one ran into.
func _fresh_start(ahead: float) -> void:
	_check(_pg.respawn(_rv.global_position, 150.0, ahead), "found a clear spot with %.0f m ahead" % ahead)
	_rv.throttle = 0.0
	_rv.brake = 0.0
	await _hold(1.0)


func _pull_away_and_shift() -> void:
	await _fresh_start(60.0)
	var start := _rv.global_position
	var forward := -_rv.global_basis.z
	# Rev a little, then let the clutch out over 1.5 s.
	_rv.throttle = 0.5
	await _hold(0.5)
	for i: int in HZ * 3 / 2:
		_rv.clutch_input = 1.0 - float(i) / (HZ * 1.5)
		await _tick()
	_rv.clutch_input = 0.0
	_rv.throttle = 0.9
	await _hold(3.0)
	_check(_rv.drivetrain.running, "didn't stall pulling away")
	var moved := (_rv.global_position - start).dot(forward)
	_check(moved > 5.0, "drove forwards in 1st (%.1f m)" % moved)
	var speed_1st := _rv.forward_speed()
	_check(speed_1st > 2.0, "speed in 1st (%.1f m/s)" % speed_1st)

	# Clutch in, 2nd, clutch out.
	_rv.throttle = 0.0
	_rv.clutch_input = 1.0
	await _hold(0.25)
	_rv.select_gear(2)
	for i: int in HZ / 2:
		_rv.clutch_input = 1.0 - float(i) / (HZ * 0.5)
		await _tick()
	_rv.clutch_input = 0.0
	_rv.throttle = 1.0
	await _hold(3.0)
	_check(_rv.drivetrain.gear == 2 and _rv.drivetrain.running, "pulling in 2nd")
	_check(_rv.forward_speed() > speed_1st, "faster in 2nd (%.1f m/s)" % _rv.forward_speed())
	var moved_total := (_rv.global_position - start).dot(forward)
	_check(moved_total > 20.0, "covered ground (%.1f m)" % moved_total)


func _brake_to_stop() -> void:
	_rv.throttle = 0.0
	_rv.clutch_input = 1.0
	_rv.brake = 1.0
	await _hold(4.0)
	_check(absf(_rv.forward_speed()) < 0.3, "brakes to a stop (%.2f m/s)" % _rv.forward_speed())
	_rv.brake = 0.0
	_rv.handbrake = true
	var parked := _rv.global_position
	await _hold(2.0)
	_check(_rv.global_position.distance_to(parked) < 0.25, "handbrake holds (%.2f m)" % _rv.global_position.distance_to(parked))
	_rv.handbrake = false


func _automatic() -> void:
	_rv.clutch_input = 0.0
	_rv.set_automatic(true)
	await _fresh_start(60.0)
	_rv.throttle = 0.8
	await _hold(5.0)
	_check(_rv.forward_speed() > 3.0, "automatic drives forwards (%.1f m/s)" % _rv.forward_speed())
	_rv.throttle = 0.0
	_rv.brake = 1.0
	await _hold(5.0)
	_check(_rv.drivetrain.gear == -1, "automatic selects reverse when held on the brake (gear %d)" % _rv.drivetrain.gear)
	_rv.brake = 0.7 # The brake pedal drives in reverse.
	await _hold(3.0)
	_check(_rv.forward_speed() < -1.0, "automatic reverses (%.1f m/s)" % _rv.forward_speed())
	_rv.brake = 0.0
	_rv.throttle = 1.0 # Throttle brakes, then back to 1st.
	await _hold(3.0)
	_check(_rv.drivetrain.gear >= 1, "back to drive (gear %d)" % _rv.drivetrain.gear)
	_rv.throttle = 0.0


func _hold(seconds: float) -> void:
	for i: int in roundi(seconds * HZ):
		await _tick()
		if OS.has_environment("RV_TEST_TRACE") and i % HZ == 0:
			var d := _rv.drivetrain
			var hits := 0
			for w: RVWheel in _rv.wheels:
				hits += 1 if w.grounded else 0
			print("    t pos %s v %.2f gear %d rpm %.0f pedal %.2f torque %.0f thr %.2f brk %.2f wheels %d pitch %.2f" % [
				_rv.global_position.snappedf(0.1), _rv.forward_speed(), d.gear, d.rpm, d.clutch_pedal,
				d.axle_torque, _rv.throttle, _rv.brake, hits, (-_rv.global_basis.z).y])


func _tick() -> void:
	await get_tree().physics_frame
	_min_up = minf(_min_up, _rv.global_basis.y.dot(Vector3.UP))


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("rv drive: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
