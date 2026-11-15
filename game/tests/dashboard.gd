extends Node
## Headless dashboard test: the cab's three dials get working needles (speed, revs, fuel) facing
## the driver, which swing to their readings, and the warning lights come on for low oil, an
## overheating engine, the engine off and a wheel that needs attention.
##
##   godot --headless --path game --fixed-fps 60 res://tests/dashboard.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _failures: PackedStringArray = []


func _ready() -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60 * 5:
		await get_tree().physics_frame
		waited += 1
	var rv := _pg.rv
	_pg.driver.enabled = false
	var dash := rv.dashboard
	_check(dash._needles.size() == 3 and dash._lamps.size() == 4, "three needles and four warning lights")
	var eye := rv.driver_eye.origin
	for i: int in 3:
		var dial := dash.get_node("Dial%d" % i) as Node3D
		var off := eye - dial.position
		_check(off.z > 0.2 and off.length() < 1.3, "dial %d is in front of the driver, facing them (%.2f m away)" % [i, off.length()])
	_check(eye.distance_to(dash.get_node("Dial1").position) < eye.distance_to(dash.get_node("Dial0").position), "the rev counter is the one behind the wheel")

	var d := rv.drivetrain
	var dmg := rv.damage
	d.running = true
	dmg.fuel = RVDamage.TANK * 0.5
	await _seconds(1.5)
	_check(d.rpm > 500.0 and absf(dash.readings[1] - d.rpm / RVDashboard.MAX_RPM) < 0.05, "the rev counter reads the engine's %d rpm (%.2f)" % [roundi(d.rpm), dash.readings[1]])
	_check(absf(dash.readings[2] - 0.5) < 0.05, "the fuel gauge reads half (%.2f)" % dash.readings[2])
	_check(dash.readings[0] < 0.05, "the speedometer rests at standstill (%.2f)" % dash.readings[0])
	_check(absf(dash._needles[2].rotation.z) < 0.05, "half a tank points straight up")
	_check(not dash.lights[&"oil"] and not dash.lights[&"hot"] and not dash.lights[&"charge"] and not dash.lights[&"check"], "no warning lights on a healthy running RV")

	dmg.oil = 0.05
	dmg.temperature = 0.95
	dmg.bolts[0] = 1
	d.running = false
	await _seconds(0.2)
	_check(dash.lights[&"oil"] and dash.lights[&"hot"] and dash.lights[&"charge"] and dash.lights[&"check"], "low oil, overheating, engine off and a loose wheel light up")
	_check((dash._lamps[&"oil"].material_override as StandardMaterial3D).emission_enabled, "and glow")
	await _seconds(1.5)
	_check(dash.readings[1] < 0.01, "engine off: the rev counter drops to zero")
	_finish()


func _seconds(s: float) -> void:
	for i: int in roundi(s * HZ):
		await get_tree().physics_frame


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("dashboard: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
