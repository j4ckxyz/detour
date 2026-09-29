extends Node
## Headless day/night and weather test: the sun and moon follow the clock; weather comes in
## seeded spells the same for everyone (fine on the first morning); wet spells snow in the
## pass and stay dry in the canyon; rain falls, wets the ground and cuts tire grip; storms
## push the RV; the clock is saved; the flashlight works.
##
##   godot --headless --path game --fixed-fps 60 res://tests/atmosphere.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")
const HZ := 60

var _pg: Playground
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
	var w := Walker.new(get_tree(), _pg.player, _pg.rv)
	var trip := _pg.trip
	var light := _pg.lighting
	_check(trip.clock_text() == "08:00" and trip.day() == 1, "the trip starts at 08:00 on day 1 (%s)" % trip.clock_text())
	var before := trip.hours
	await w.hold(3.0)
	_check(is_equal_approx(snappedf(trip.hours - before, 0.001), 0.05), "a game hour passes every real minute")

	trip.hours = 12.0
	await w.hold(0.1)
	_check(light.daylight > 0.99 and light.sun.light_energy > 0.8 and not light.moon.visible, "noon is bright")
	trip.hours = 24.0 + 1.0
	await w.hold(0.1)
	_check(light.daylight < 0.01 and not light.sun.visible and light.moon.visible, "1 am is dark, with the moon up")
	_check(trip.day() == 2 and trip.clock_text() == "01:00", "and it's day 2 (%s)" % trip.clock_text())
	trip.hours = 17.5
	await w.hold(0.1)
	_check(light.sun.light_color.b < 0.6, "the setting sun is orange")

	# Weather: seeded, the same for everyone, clear on the first morning.
	var a := Weather.new()
	var b := Weather.new()
	a.setup("DT3-0EHYA-0MEKW")
	b.setup("DT3-0EHYA-0MEKW")
	var kinds := {}
	var same := true
	var morning_clear := true
	var rain_hour := -1.0
	for h: int in range(8, 8 + 24 * 6, 3):
		var k := a.base_kind(h + 1.0)
		same = same and k == b.base_kind(h + 1.0)
		kinds[k] = true
		if h + 1.0 < 12.0:
			morning_clear = morning_clear and k == Weather.Kind.CLEAR
		if k == Weather.Kind.RAIN and rain_hour < 0.0:
			rain_hour = h + 1.5
	a.free()
	b.free()
	_check(same, "the same seed makes the same weather")
	_check(kinds.size() >= 3, "the weather changes over six days (%d kinds)" % kinds.size())
	_check(morning_clear, "the first morning is fine")
	_check(Weather.local_kind(Weather.Kind.RAIN, 3) == Weather.Kind.SNOW and Weather.local_kind(Weather.Kind.RAIN, 2) == Weather.Kind.CLOUDY,
		"wet weather snows in the pass and stays dry in the canyon")

	if rain_hour > 0.0:
		trip.hours = rain_hour
		var weather := _pg.weather
		for i: int in 40:
			weather.update(trip.hours, _pg.rv.global_position, 0, 1.0) # 40 s of rain, fast.
		_check(weather.kind == Weather.Kind.RAIN and weather.wetness > 0.3, "rain wets the ground (%.2f)" % weather.wetness)
		await w.hold(0.5)
		var grip := 0.0
		for wheel: RVWheel in _pg.rv.wheels:
			grip = maxf(grip, wheel.surface_grip)
		_check(_pg.rv.wetness > 0.3 and grip < 0.97, "wet roads grip less (%.2f)" % grip)
		_check((weather.get_child(0) as GPUParticles3D).emitting, "rain falls")
	else:
		_check(false, "a rainy spell within six days")

	# Storm gusts push the RV sideways.
	_pg.rv.parking_brake = false
	var start := _pg.rv.global_position
	_pg.set_process(false) # Hold the gust steady.
	_pg.rv.wind = Vector3(1.0, 0.0, 0.0)
	await w.hold(0.5)
	_check(_pg.rv.linear_velocity.x > 0.01, "a storm gust pushes the RV (%.3f m/s)" % _pg.rv.linear_velocity.x)
	_pg.rv.wind = Vector3.ZERO
	_pg.set_process(true)
	_pg.rv.parking_brake = true

	# Saved with the trip.
	trip.hours = 33.5
	trip.save()
	trip.hours = 0.0
	trip.load_save()
	_check(is_equal_approx(trip.hours, 33.5), "the clock is saved (%.1f)" % trip.hours)
	trip.clear_save()

	# The flashlight.
	await w.press(&"flashlight")
	_check(_pg.player.flashlight.visible, "L turns the flashlight on")
	await w.press(&"flashlight")
	_check(not _pg.player.flashlight.visible, "and off")
	_check(_pg.trip_hud._line.text.contains("Day"), "the HUD shows the day, time and weather: %s" % _pg.trip_hud._line.text.get_slice("\n", 0))
	_pg.rv.global_position = start

	if _failures.is_empty():
		print("atmosphere: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
