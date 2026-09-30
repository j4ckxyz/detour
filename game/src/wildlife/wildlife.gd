class_name Wildlife
extends Node3D
## Puts the trip's animals out (PLAN.md §4.5), the same ones for the same seed: snakes near the
## obstacles (but not where you have to work: see `WORK_SNAKE_CLEARANCE`), bears in the woods a
## good way from them (on the valley floor, never up its walls), eagles over the gas stations.
## There are more, and meaner, the further along the road you get. Animals far from everyone
## don't think.

## Animals within this of a player or the RV are awake (m).
const AWAKE_RADIUS := 170.0
## No bears this close to the camp or home, no snakes this close to any stop (m).
const BEAR_CLEARANCE := 90.0
const SNAKE_CLEARANCE := 35.0
## Where people are on foot getting past an obstacle (its stretch of road, the planks and the
## winch anchors for it) no bear lives within this (m): its senses reach 24 m and it wanders 20 m
## from home, and nobody should be fetching planks with a bear at their back. Snakes stay this far.
const WORK_BEAR_CLEARANCE := 70.0
const WORK_SNAKE_CLEARANCE := 12.0

var world: WorldGen
var rv: RV
var items: Node
var data: Dictionary
var _rng := RandomNumberGenerator.new()
var _check := 0.0
## Points where people work on foot (see `WORK_BEAR_CLEARANCE`).
var _work := PackedVector3Array()


func setup(gen: WorldGen, the_rv: RV, item_parent: Node, trip_data: Dictionary) -> void:
	world = gen
	rv = the_rv
	items = item_parent
	data = trip_data
	_rng.seed = hash(gen.get_code() + ":wildlife")


func populate() -> void:
	_find_work()
	var total := maxf(1.0, float(data.get("length", 1.0)))
	var half := float(data.get("road_half_width", 3.2))
	for o: Dictionary in data.get("obstacles", []):
		var t := float(o["s"]) / total
		var pos: Vector3 = o["pos"]
		var dir: Vector3 = o["dir"]
		var side := Vector3(-dir.z, 0.0, dir.x)
		var reach := float(o.get("length", 4.0)) * 0.5
		var snakes := (1 if _rng.randf() < 0.35 + 0.5 * t else 0) + (1 if _rng.randf() < t - 0.3 else 0)
		for k: int in snakes:
			# Beside the road a little way off (before or after), out of where people work.
			for attempt: int in 4:
				var along := dir * (reach + _rng.randf_range(14.0, 30.0)) * (1.0 if _rng.randf() < 0.5 else -1.0)
				if _add(Snake.new(), pos + along + side * _side() * (half + _rng.randf_range(0.8, 4.0)), SNAKE_CLEARANCE):
					break
		if _rng.randf() < 0.1 + 0.6 * t:
			# In the woods well before or after it, where the valley has opened out again.
			for attempt: int in 4:
				var along_bear := dir * (reach + _rng.randf_range(75.0, 115.0)) * _side()
				if _add(Bear.new(), pos + along_bear + side * _side() * _rng.randf_range(9.0, 16.0), BEAR_CLEARANCE):
					break
	# Along the way, between obstacles.
	var points: PackedVector3Array = data.get("points", PackedVector3Array())
	var step := 250.0
	var s := step
	while s < total - step:
		var t := s / total
		var i := clampi(int(s / 8.0), 0, points.size() - 2)
		var pos := points[i]
		var dir := (points[i + 1] - pos)
		dir.y = 0.0
		dir = dir.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		if _rng.randf() < 0.15 + 0.3 * t:
			_add(Snake.new(), pos + side * _side() * (half + _rng.randf_range(1.0, 5.0)), SNAKE_CLEARANCE)
		if _rng.randf() < 0.05 + 0.25 * t:
			_add(Bear.new(), pos + side * _side() * _rng.randf_range(22.0, 36.0), BEAR_CLEARANCE)
		if t > 0.25 and fmod(s, 1250.0) < step and _rng.randf() < 0.5:
			_add(Eagle.new(), pos, 0.0)
		s += step
	for p: Dictionary in data.get("pads", []):
		if int(p["kind"]) == Trip.PAD_STATION:
			_add(Eagle.new(), p["pos"], 0.0)


## Where people will be on foot: along each obstacle's stretch of the road (and the way in),
## and at every pile of planks and every winch anchor.
func _find_work() -> void:
	_work.clear()
	var points: PackedVector3Array = data.get("points", PackedVector3Array())
	for o: Dictionary in data.get("obstacles", []):
		# (The way in from the planks, too.)
		var first := int(floorf((float(o.get("start", o["s"])) - 24.0) / 8.0))
		var last := int(ceilf(float(o.get("end", o["s"])) / 8.0))
		for i: int in range(maxi(first, 0), mini(last, points.size() - 1) + 1):
			_work.append(points[i])
	for supply: Dictionary in data.get("supplies", []):
		_work.append(supply["pos"])


## Whether a point is within `radius` of somewhere people work on foot.
func near_work(at: Vector3, radius: float) -> bool:
	for p: Vector3 in _work:
		if Vector2(at.x - p.x, at.z - p.z).length() < radius:
			return true
	return false


func _side() -> float:
	return 1.0 if _rng.randf() < 0.5 else -1.0


## Puts `animal` out at `at` unless it can't live there (returns whether it did).
func _add(animal: Animal, at: Vector3, clearance: float) -> bool:
	# Who lives where: no snakes in the snowy pass, no bears in the dry canyon.
	var biome := world.biome_at(at.x, at.z)
	var walled := world.outside_valley(at.x, at.z) > -4.0 # Up a valley wall.
	if (animal is Snake and biome == 3) or (animal is Bear and (biome == 2 or walled)) or world.water_level(at.x, at.z) > -1000.0:
		animal.free()
		return false
	# Not where people have to work.
	if (animal is Bear and near_work(at, WORK_BEAR_CLEARANCE)) or (animal is Snake and near_work(at, WORK_SNAKE_CLEARANCE)):
		animal.free()
		return false
	for p: Dictionary in data.get("pads", []):
		var kind := int(p["kind"])
		var near := Vector2(at.x - (p["pos"] as Vector3).x, at.z - (p["pos"] as Vector3).z).length()
		if animal is Bear and kind == Trip.PAD_STATION:
			continue # Bears may roam near stations (there's an RV to hide in).
		if near < clearance:
			animal.free()
			return false
	animal.world = world
	animal.rv = rv
	animal.world_items = items
	animal.rng.seed = _rng.randi()
	at.y = world.height_at(at.x, at.z)
	animal.home = at
	animal.position = at
	animal.yaw = _rng.randf() * TAU
	add_child(animal)
	_wake(animal, false)
	return true


func _physics_process(dt: float) -> void:
	_check -= dt
	if _check > 0.0:
		return
	_check = 0.5
	var foci: Array[Vector3] = [rv.global_position]
	for n: Node in get_tree().get_nodes_in_group(&"players"):
		foci.append((n as Node3D).global_position)
	for c: Node in get_children():
		var animal := c as Animal
		var awake := false
		for f: Vector3 in foci:
			if f.distance_to(animal.global_position) < AWAKE_RADIUS:
				awake = true
				break
		_wake(animal, awake)


func _wake(animal: Animal, awake: bool) -> void:
	animal.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED
	animal.visible = awake


func count(kind: Variant) -> int:
	var n := 0
	for c: Node in get_children():
		n += 1 if is_instance_of(c, kind) else 0
	return n
