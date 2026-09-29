class_name Wildlife
extends Node3D
## Puts the trip's animals out (PLAN.md §4.5), the same ones for the same seed: snakes by the
## obstacles (where you have to get out), bears in the woods beside them (on the valley floor,
## short of its walls), eagles over the gas stations. There are more, and meaner, the further along the road you get. Animals far from
## everyone don't think.

## Animals within this of a player or the RV are awake (m).
const AWAKE_RADIUS := 170.0
## No bears this close to the camp or home, no snakes this close to any stop (m).
const BEAR_CLEARANCE := 90.0
const SNAKE_CLEARANCE := 35.0

var world: WorldGen
var rv: RV
var items: Node
var data: Dictionary
var _rng := RandomNumberGenerator.new()
var _check := 0.0


func setup(gen: WorldGen, the_rv: RV, item_parent: Node, trip_data: Dictionary) -> void:
	world = gen
	rv = the_rv
	items = item_parent
	data = trip_data
	_rng.seed = hash(gen.get_code() + ":wildlife")


func populate() -> void:
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
			var along := dir * (reach + _rng.randf_range(3.0, 12.0)) * (1.0 if _rng.randf() < 0.5 else -1.0)
			_add(Snake.new(), pos + along + side * _side() * (half + _rng.randf_range(0.8, 4.0)), SNAKE_CLEARANCE)
		if _rng.randf() < 0.1 + 0.6 * t:
			_add(Bear.new(), pos + dir * _rng.randf_range(-20.0, 20.0) + side * _side() * _rng.randf_range(20.0, 34.0), BEAR_CLEARANCE)
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


func _side() -> float:
	return 1.0 if _rng.randf() < 0.5 else -1.0


func _add(animal: Animal, at: Vector3, clearance: float) -> void:
	# Who lives where: no snakes in the snowy pass, no bears in the dry canyon.
	var biome := world.biome_at(at.x, at.z)
	if (animal is Snake and biome == 3) or (animal is Bear and biome == 2) or world.water_level(at.x, at.z) > -1000.0:
		animal.free()
		return
	for p: Dictionary in data.get("pads", []):
		var kind := int(p["kind"])
		var near := Vector2(at.x - (p["pos"] as Vector3).x, at.z - (p["pos"] as Vector3).z).length()
		if animal is Bear and kind == Trip.PAD_STATION:
			continue # Bears may roam near stations (there's an RV to hide in).
		if near < clearance:
			animal.free()
			return
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
