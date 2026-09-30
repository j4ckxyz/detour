extends Node
## Headless manual-gearbox driving test on a long, flat, straight road (no world): every gear
## the RV shifts up into really does make it faster (the speed used to stop at ~45 km/h in any
## gear: Godot's default damping was eating the engine's thrust); it coasts instead of
## braking itself; shifting up through the gears with the assisted keys never stalls it; and a
## stalled engine starts again with the pedal up and the RV in gear (the starter holds the
## clutch in), the driving HUD saying plainly that the engine is off.
##
##   godot --headless --path game --fixed-fps 60 res://tests/manual_driving.tscn

const RV_SCENE := preload("res://src/rv/rv.tscn")
const HZ := 60
## Speeds (km/h) each gear must at least reach at full throttle on the flat, against its top
## speed at the rev limiter (24, 42, 70, 100, 122): drag and a few seconds' run-up allow for
## the rest.
const REACHES: Dictionary[int, float] = {1: 20.0, 2: 34.0, 3: 55.0, 4: 80.0, 5: 100.0}

var _rv: RV
var _failures: PackedStringArray = []
var _top: Dictionary[int, float] = {}


func _ready() -> void:
	_run()


func _run() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = TerrainStreamer.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 2.0, 6000.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, -2900.0)
	floor_body.add_child(shape)
	add_child(floor_body)
	_rv = RV_SCENE.instantiate()
	add_child(_rv)
	_rv.global_position = Vector3(0.0, 1.2, 0.0)
	_rv.drivetrain.running = true
	await _frames(HZ * 2)

	_check(_rv.linear_damp_mode == RigidBody3D.DAMP_MODE_REPLACE and _rv.linear_damp == 0.0, "the RV has no hidden linear damping")
	await _coasting()
	await _up_the_gears()
	await _stall_and_restart()
	await _hud()
	_finish()


## In neutral, engine off, at 20 m/s: drag and rolling resistance only (~0.4 m/s²), so it
## carries on. With Godot's default damping it lost 2 m/s² and was down to 10 m/s in 5 s.
func _coasting() -> void:
	_rv.parking_brake = false
	_rv.drivetrain.shift_to_neutral()
	_rv.linear_velocity = -_rv.global_basis.z * 20.0
	await _frames(HZ * 5)
	_check(_rv.forward_speed() > 16.0, "coasting keeps its speed (20 → %.1f m/s in 5 s)" % _rv.forward_speed())
	await _frames(HZ * 4)
	_rv.brake = 1.0
	await _frames(HZ * 6)
	_rv.brake = 0.0
	_check(absf(_rv.forward_speed()) < 0.5, "and the brakes stop it")
	_rv.parking_brake = true


func _up_the_gears() -> void:
	_rv.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, -100.0))
	_rv.linear_velocity = Vector3.ZERO
	_rv.angular_velocity = Vector3.ZERO
	await _frames(HZ)
	var d := _rv.drivetrain
	_rv.set_automatic(false)
	_rv.clutch_input = 1.0
	await _frames(HZ / 2)
	_rv.select_gear(1)
	_check(d.gear == 1, "1st with the clutch down")
	_rv.clutch_input = 0.0 # A key: the pedal comes up at once and the feathering takes over.
	_rv.throttle = 1.0
	var stalls := 0
	var was_running := true
	var last_shift := 0.0
	var t := 0.0
	var before_shift := 0.0
	var faster_after: Array[String] = []
	while t < 75.0 and d.gear <= 5:
		await get_tree().physics_frame
		t += 1.0 / HZ
		if was_running and not d.running:
			stalls += 1
		was_running = d.running
		var kmh := _rv.forward_speed() * 3.6
		_top[d.gear] = maxf(_top.get(d.gear, 0.0), kmh)
		if d.gear < 5 and d.rpm > 3300.0 and t - last_shift > 1.5 and d.clutch_pedal < 0.1:
			before_shift = kmh
			var from := d.gear
			_rv.shift_by(1)
			last_shift = t
			await _frames(HZ * 2)
			var after := _rv.forward_speed() * 3.6
			faster_after.append("%d→%d: %.0f → %.0f km/h" % [from, d.gear, before_shift, after])
			_check(after > before_shift - 3.0, "shifting up %d → %d doesn't lose speed (%.0f → %.0f km/h)" % [from, d.gear, before_shift, after])
		if d.gear == 5 and t - last_shift > 30.0:
			break
	_rv.throttle = 0.0
	print("    top speed by gear (km/h): ", _top)
	print("    shifts: ", faster_after)
	_check(stalls == 0, "no stalls launching and shifting up through the gears (%d)" % stalls)
	for g: int in REACHES:
		_check(_top.get(g, 0.0) >= REACHES[g], "gear %d reaches %.0f km/h (%.0f)" % [g, REACHES[g], _top.get(g, 0.0)])
	for g: int in range(2, 6):
		_check(_top.get(g, 0.0) > _top.get(g - 1, 0.0) + 8.0, "gear %d is faster than gear %d (%.0f vs %.0f)" % [g, g - 1, _top.get(g, 0.0), _top.get(g - 1, 0.0)])
	_check(_top.get(5, 0.0) > 90.0, "well past the old ~45 km/h ceiling (%.0f km/h)" % _top.get(5, 0.0))


func _stall_and_restart() -> void:
	var d := _rv.drivetrain
	_rv.brake = 1.0
	_rv.throttle = 0.0
	_rv.clutch_input = 1.0
	await _frames(HZ * 12)
	_rv.brake = 0.0
	_check(absf(_rv.forward_speed()) < 0.3, "stopped")
	_rv.select_gear(1)
	_rv.brake = 1.0
	_rv.clutch_input = 0.0 # Let it out against the brakes: it stalls.
	await _frames(HZ * 2)
	_check(not d.running, "it stalled")
	_rv.brake = 0.0
	# Pedal up, in gear, and press start: the starter holds the clutch in.
	_rv.clutch_input = 0.0
	_rv.start_engine()
	await _frames(HZ / 3)
	_check(d.is_cranking() and d.clutch_pedal > 0.9, "start: cranking with the clutch held in for us (pedal %.2f)" % d.clutch_pedal)
	await _frames(HZ * 2)
	_check(d.running and not d.is_cranking(), "it starts again with the pedal up and 1st selected")
	await _frames(HZ * 3)
	_check(d.running and d.clutch_pedal > 0.9 and absf(_rv.forward_speed()) < 0.5, "and idles with the clutch still in, going nowhere")
	_rv.throttle = 0.3
	await _frames(HZ * 3)
	_check(d.running and _rv.forward_speed() > 0.5, "throttle brings the clutch out and it pulls away (%.1f m/s)" % _rv.forward_speed())
	_rv.throttle = 0.0
	# In 5th at a crawl with no throttle: lugs and stalls; starting it again still works.
	_rv.brake = 1.0
	await _frames(HZ * 4)
	_rv.brake = 0.0
	_rv.clutch_input = 1.0
	await _frames(HZ / 2)
	_rv.select_gear(5)
	_rv.clutch_input = 0.0
	await _frames(HZ * 3)
	_check(d.gear == 5, "in 5th")
	if d.running:
		d.running = false # (Lugging in 5th from a crawl is a stall too; make sure of it.)
		d.stalled.emit()
	_rv.start_engine()
	await _frames(HZ * 4)
	_check(d.running and absf(_rv.forward_speed()) < 0.5, "a stalled engine in 5th at rest starts again and idles (it doesn't stall itself)")
	# Pressing and letting go of the clutch key is the driver taking the pedal back.
	_rv.clutch_input = 1.0
	await _frames(HZ / 2)
	_rv.select_gear(1)
	_rv.clutch_input = 0.0
	await _frames(HZ * 3)
	_check(d.running and d.gear == 1 and _rv.forward_speed() > 0.3, "then clutch, 1st, let go: it creeps off (%.1f m/s)" % _rv.forward_speed())


func _hud() -> void:
	var hud := RVHud.new()
	hud.rv = _rv
	add_child(hud)
	await _drawn()
	var d := _rv.drivetrain
	_check(not hud._engine_state.visible and hud._status.text.contains("ENGINE ON"), "running: no banner, and the status says ENGINE ON")
	d.running = false
	await _drawn()
	_check(hud._engine_state.visible and hud._engine_state.text.begins_with("ENGINE OFF") and hud._engine_state.text.contains("start"), "stalled: a big ENGINE OFF banner says how to start (%s)" % hud._engine_state.text.replace("\n", " | "))
	_check(hud._status.text.contains("ENGINE OFF"), "the status line says ENGINE OFF")
	_rv.start_engine()
	await _frames(10)
	_check(hud._engine_state.visible and hud._engine_state.text == "STARTING…", "cranking: STARTING…")
	await _frames(HZ * 2)
	_check(not hud._engine_state.visible, "running again: the banner goes")
	var fuel := _rv.damage.fuel
	d.running = false
	_rv.damage.fuel = 0.0
	await _drawn()
	_check(hud._engine_state.text.contains("out of fuel"), "out of fuel says so")
	_rv.damage.fuel = fuel
	hud.queue_free()


## Two frames: the HUD's own _process has run for sure.
func _drawn() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().physics_frame


func _finish() -> void:
	_rv.throttle = 0.0
	if _failures.is_empty():
		print("manual driving: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
