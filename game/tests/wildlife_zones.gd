extends Node
## Headless test that nobody has to fetch planks or winch with a bear at their back: on several
## trips (short and medium) no bear lives within 70 m, and no snake within 12 m, of anywhere
## people work on foot (each obstacle's stretch of road and the way in, every pile of planks,
## every winch anchor); and there are still animals about (bears and snakes elsewhere along
## the road).
##
##   godot --headless --path game --fixed-fps 60 res://tests/wildlife_zones.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60
const SEEDS: Array[String] = ["DT6-00000-000ZT", "DT6-00000-0009Q", "DT6-80000-000ZJ", "DT6-80000-0009Z"]

var _pg: Playground
var _failures: PackedStringArray = []


func _ready() -> void:
	_run()


func _run() -> void:
	var bears := 0
	var snakes := 0
	for code: String in SEEDS:
		await _start(code)
		var wildlife := _pg.wildlife
		var trip_bears := 0
		var trip_snakes := 0
		var nearest_bear := INF
		var nearest_snake := INF
		var work := wildlife._work
		_check(work.size() > 20, "%s: %d places where people work" % [code, work.size()])
		for c: Node in wildlife.get_children():
			var animal := c as Animal
			if animal is Bear:
				trip_bears += 1
				nearest_bear = minf(nearest_bear, _nearest(work, animal.home))
			elif animal is Snake:
				trip_snakes += 1
				nearest_snake = minf(nearest_snake, _nearest(work, animal.home))
		_check(nearest_bear >= Wildlife.WORK_BEAR_CLEARANCE, "%s: %d bears, the nearest %.0f m from where people work" % [code, trip_bears, nearest_bear if trip_bears > 0 else 0.0])
		_check(nearest_snake >= Wildlife.WORK_SNAKE_CLEARANCE, "%s: %d snakes, the nearest %.0f m from where people work" % [code, trip_snakes, nearest_snake if trip_snakes > 0 else 0.0])
		# No bear lives within reach of a pile of planks or the walk to it.
		var nearest_pile := INF
		for supply: Dictionary in _pg.trip.data["supplies"]:
			if int(supply["kind"]) == 0:
				for c: Node in wildlife.get_children():
					if c is Bear:
						var here: Vector3 = supply["pos"]
						nearest_pile = minf(nearest_pile, Vector2(here.x - (c as Bear).home.x, here.z - (c as Bear).home.z).length())
		_check(nearest_pile > Bear.SENSE + 20.0 + 10.0, "%s: the nearest bear lives %.0f m from any pile of planks" % [code, nearest_pile])
		bears += trip_bears
		snakes += trip_snakes
	_check(bears >= 3 and snakes >= 6, "there are still animals about (%d bears, %d snakes over %d trips)" % [bears, snakes, SEEDS.size()])
	_finish()


func _nearest(points: PackedVector3Array, at: Vector3) -> float:
	var best := INF
	for p: Vector3 in points:
		best = minf(best, Vector2(at.x - p.x, at.z - p.z).length())
	return best


func _start(code: String) -> void:
	if _pg:
		_pg.queue_free()
		await get_tree().process_frame
	Session.seed_code = code
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = false
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60 * 5: # (Frames run faster than the generator thread under load.)
		await get_tree().physics_frame
		waited += 1
	_check(_pg.is_spawned, "%s spawned" % code)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("wildlife zones: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
