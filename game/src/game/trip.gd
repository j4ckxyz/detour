class_name Trip
extends Node3D
## One trip (PLAN.md §4.1, §4.6): from the camp along the generated road, through gas-station
## checkpoints, to home. Builds the stops and supplies from `WorldGen.trip()`, notices the RV
## arriving, saves (at each station, and every so often along the way) and ends the trip at
## home. Nothing tells you what's ahead: no signs before obstacles, just the road.

signal checkpoint_reached(index: int, total: int)
signal finished

const PAD_CAMP := 0
const PAD_STATION := 1
const PAD_HOME := 2
const BIOME_NAMES: Array[String] = ["the Pine Woods", "Muddy Bayou", "Red Rock Canyon", "Frostpeak Pass"]
## What each kind of place off the road might hold (kind, weight): a cabin, a fire lookout
## tower, a wreck, a hill with a view.
const POI_LOOT: Array = [
	[[&"burger", 2], [&"soda", 2], [&"first_aid", 1], [&"jerrycan", 1], [&"plank", 1], [&"epipen", 1], [&"motor_oil", 1]],
	[[&"bear_spray", 2], [&"first_aid", 1], [&"burger", 1], [&"soda", 1], [&"antidote", 1], [&"scrap_metal", 1]],
	[[&"scrap_metal", 4], [&"spare_tire", 1], [&"motor_oil", 2], [&"jerrycan", 1]],
	[[&"burger", 2], [&"soda", 2], [&"patty", 1]],
]
## Obstacle kinds (`WorldGen.trip()`).
const GAP := 0
const BRIDGE := 6
const BEAMS := 7
const JUMP := 8
const HILL := 9
## What a cave might hold (kind, weight).
const CAVE_LOOT: Array[Array] = [
	[&"scrap_metal", 3], [&"plank", 2], [&"burger", 2], [&"soda", 2], [&"jerrycan", 1],
	[&"antidote", 1], [&"epipen", 1], [&"bear_spray", 1], [&"first_aid", 1], [&"motor_oil", 1], [&"spare_tire", 1],
]
## How close (m) the RV must get to a pad's centre to arrive (stations sit beside the road:
## their centre is ~14 m from it).
const ARRIVE_RADIUS := 20.0
## How near a pump the RV must be for the hose to reach its tank (the lane between the pumps,
## or pulled up on the road outside), metres.
const PUMP_REACH := 16.0
## Once this far from the last stop the RV has set off (its state is the checkpoint's).
const LEAVE_RADIUS := 45.0
const START_HOUR := 8.0
const HOURS_PER_SECOND := 1.0 / 60.0
## Items a station restocks (kind, count).
const RESTOCK: Array[Array] = [
	[&"plank", 2], [&"jerrycan", 1], [&"scrap_metal", 2], [&"motor_oil", 1], [&"burger", 2], [&"spare_tire", 1],
	[&"patty", 2], [&"soda", 1], [&"epipen", 1], [&"antidote", 1], [&"bear_spray", 1],
]

var world: WorldGen
var rv: RV
var items: Node3D
var data: Dictionary
## Index into `data.pads` of the last stop reached (0 = the camp).
var checkpoint := 0
var elapsed := 0.0
## Game time: hours since midnight before the trip (starts at 08:00; one game hour passes per
## real minute, so a day is 24 minutes).
var hours := START_HOUR
var distance_driven := 0.0
var stalls := 0
var is_finished := false
## A one-line message for the HUD (e.g. "Checkpoint!"), and how long it stays.
var notice := ""
var notice_time := 0.0
## Online clients follow the host's trip (arrivals, saves and restocks happen there).
var is_authority := true
## Optional `func() -> Dictionary`: more to save (the RV and where it is, what's stowed in it,
## what lies about the world, the player), and what came back from the last load.
var extra_save: Callable
var loaded_extra: Dictionary = {}
## A save was loaded (so the world's things come from it, not fresh).
var resumed := false
## Seconds the "Saved" mark shows for (the HUD fades it).
var saved_flash := 0.0
## The RV as it left the last stop (`RV.slow_snapshot()`: damage, fuel, oil...): what it's put
## back to if it's wrecked or everyone's down (`Playground.back_to_checkpoint`).
var checkpoint_rv: Array = []
## The RV has driven away from the last stop since reaching it.
var _left_stop := false

var _last_rv_pos := Vector3.INF
var _biome := -1
var _biome_check := 0.0


func setup(gen: WorldGen, the_rv: RV, item_parent: Node3D) -> void:
	world = gen
	rv = the_rv
	items = item_parent
	data = world.trip()
	rv.engine_stalled.connect(func() -> void: stalls += 1)


func pads() -> Array:
	return data.get("pads", [])


func pad(i: int) -> Dictionary:
	return pads()[i]


func station_count() -> int:
	return pads().size() - 2


## Builds the stops, plank piles, bridges and beams, telephone poles and the places off the
## road (after the ground under the start has streamed in, so things sit on it).
func build(spawn_items: bool = true) -> void:
	for i: int in pads().size():
		var p: Dictionary = pads()[i]
		var node := TripStops.build(int(p["kind"]), i, station_count())
		add_child(node)
		node.global_transform = _pad_transform(p)
	_wire_station_services()
	var supplies: Array = data.get("supplies", [])
	for i: int in supplies.size():
		if int(supplies[i]["kind"]) == 0 and spawn_items:
			_spawn_planks(i, supplies[i])
	for o: Dictionary in data.get("obstacles", []):
		match int(o["kind"]):
			GAP:
				_add_abutments(o)
			BRIDGE:
				_add_structure(TripStructures.bridge(o, data["deck_kicker"]), o)
			BEAMS:
				_add_structure(TripStructures.beams(o, float(data["beam_width"]), float(data["beam_offset"])), o)
	add_child(TripStructures.poles(_pole_spots()))
	var pois: Array = data.get("pois", [])
	for i: int in pois.size():
		_build_poi(i, pois[i], spawn_items)
	var water := WaterBodies.new()
	water.name = "Water"
	add_child(water)
	water.build(data)
	var caves: Array = data.get("caves", [])
	for i: int in caves.size():
		_build_cave(i, caves[i], spawn_items)


func _add_structure(node: Node3D, o: Dictionary) -> void:
	add_child(node)
	node.global_transform = TripStructures.frame(o)


## Where telephone poles stand: every so often along the road on its right, up the hills
## too, but not at the crossings (the line's down there) or the stops.
func _pole_spots() -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var pts: PackedVector3Array = data["points"]
	var length := float(data["length"])
	var s := 40.0
	while s < length - 40.0:
		var clear := true
		for o: Dictionary in data.get("obstacles", []):
			var reach := float(o["length"]) * 0.5 + 30.0
			if int(o["kind"]) == HILL: # Poles all the way up it.
				continue
			if absf(float(o["s"]) - s) < reach:
				clear = false
		for p: Dictionary in pads():
			if absf(float(p["s"]) - s) < 28.0:
				clear = false
		for sp: Dictionary in data.get("spurs", []):
			if absf(float(sp["from_s"]) - s) < 16.0:
				clear = false
		if clear:
			var xf := road_transform(s)
			var at := xf.origin + xf.basis.x * TripStructures.POLE_OFFSET
			at.y = world.height_at(at.x, at.z)
			out.append(Transform3D(xf.basis, at))
		s += TripStructures.POLE_SPACING
	return out


## A place off the road (a cabin, a tower, a wreck, a hill with a view), with a few things
## left there (the same for the same seed).
func _build_poi(index: int, p: Dictionary, stock: bool) -> void:
	var kind := int(p["kind"])
	var node := TripStructures.poi(kind)
	node.name = "%s%d" % [node.name, index]
	add_child(node)
	var pos: Vector3 = p["pos"]
	pos.y = world.height_at(pos.x, pos.z)
	node.global_transform = Transform3D(Basis.looking_at(p["dir"], Vector3.UP), pos)
	if stock:
		_stock(node, POI_LOOT[kind], node.get_meta(&"loot_spots"), "%s:poi%d" % [world.get_code(), index])


## Leaves a few things from `table` at `spots` (local to `node`), seeded by `key`.
func _stock(node: Node3D, table: Array, spots: Array, key: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var total := 0
	for e: Array in table:
		total += int(e[1])
	for k: int in 2 + rng.randi() % (spots.size() - 1):
		var roll := rng.randi() % total
		var kind: StringName = table[0][0]
		for e: Array in table:
			roll -= int(e[1])
			if roll < 0:
				kind = e[0]
				break
		var item := ItemLibrary.create(kind)
		items.add_child(item)
		var local: Vector3 = spots[k % spots.size()] + Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
		var at := node.global_transform * local
		at.y = maxf(at.y, world.height_at(at.x, at.z)) + item.base_offset + 0.05
		item.global_position = at
		item.freeze = true # Waits there until picked up.
		item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


## A cave off the road, stocked with a few random supplies (the same for the same seed).
func _build_cave(index: int, c: Dictionary, stock: bool) -> void:
	var pos: Vector3 = c["pos"]
	var dir: Vector3 = c["dir"]
	var node := TripStops.cave(int(c["biome"]) == 2)
	node.name = "Cave%d" % index
	add_child(node)
	pos.y = world.height_at(pos.x, pos.z)
	node.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), pos)
	if not stock:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:cave%d" % [world.get_code(), index])
	var total := 0
	for e: Array in CAVE_LOOT:
		total += int(e[1])
	for k: int in 3 + rng.randi() % 3:
		var roll := rng.randi() % total
		var kind: StringName = CAVE_LOOT[0][0]
		for e: Array in CAVE_LOOT:
			roll -= int(e[1])
			if roll < 0:
				kind = e[0]
				break
		var item := ItemLibrary.create(kind)
		items.add_child(item)
		var at := node.global_transform * Vector3(-1.5 + 1.0 * k, 0.0, 1.5 + 0.8 * (k % 2))
		at.y = world.height_at(at.x, at.z) + item.base_offset + 0.05
		item.global_position = at
		item.freeze = true # Waits there (the ground may not be solid yet) until picked up.
		item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


## A washed-out bridge's two concrete abutments: crisp edges at road level either side of the
## clear span, for planks to rest on.
func _add_abutments(o: Dictionary) -> void:
	var pos: Vector3 = o["pos"]
	var dir: Vector3 = o["dir"]
	var half := float(o["length"]) * 0.5
	var width := float(data["road_half_width"]) * 2.0 + 1.6
	for sign: float in [-1.0, 1.0]:
		var block := TripStops.abutment(width)
		add_child(block)
		var at := pos + dir * sign * (half + TripStops.ABUTMENT_DEPTH * 0.5)
		at.y = pos.y
		block.global_transform = Transform3D(Basis(dir.cross(Vector3.UP), Vector3.UP, -dir) if sign > 0.0 else Basis(-dir.cross(Vector3.UP), Vector3.UP, dir), at)


## Where the RV starts: on the road at the camp, or at the saved checkpoint.
func start_transform() -> Transform3D:
	return road_transform(float(pad(checkpoint)["s"]) + (0.0 if checkpoint == 0 else 8.0))


## The RV's pose on the road `s` metres along it.
func road_transform(s: float) -> Transform3D:
	var pts: PackedVector3Array = data["points"]
	var i := clampi(int(s / 8.0), 0, pts.size() - 2)
	var a := pts[i]
	var b := pts[i + 1]
	var dir := (b - a)
	dir.y = 0.0
	dir = dir.normalized()
	var pos := a
	pos.y = world.height_at(pos.x, pos.z) + 0.35
	return Transform3D(Basis.looking_at(dir, Vector3.UP), pos)


func _pad_transform(p: Dictionary) -> Transform3D:
	var pos: Vector3 = p["pos"]
	var dir: Vector3 = p["dir"]
	var side: float = p["side"]
	# Stops face the road: their -Z points at it.
	var facing := Vector3(dir.z, 0.0, -dir.x) * side
	pos.y = world.height_at(pos.x, pos.z)
	return Transform3D(Basis.looking_at(facing if facing.length() > 0.1 else dir, Vector3.UP), pos)


## Pumps fill the RV (parked close) or a held jerry can; the welder fixes the frame.
func _wire_station_services() -> void:
	for n: Node in get_tree().get_nodes_in_group(&"fuel_pumps"):
		var pump := n as Interactable
		if pump == null or not is_ancestor_of(pump):
			continue
		pump.prompt_for = func(player: Player) -> String:
			if player.held and player.held.kind == &"jerrycan":
				return "Fill"
			if _rv_near(pump, PUMP_REACH):
				return "Fill up (%d / %d L)" % [roundi(rv.damage.fuel), roundi(RVDamage.TANK)]
			return "Pump"
		pump.used.connect(func(player: Player) -> void:
			if player.held and player.held.kind == &"jerrycan":
				player.held.set_meta(&"fuel", ItemLibrary.JERRY_CAN_LITRES)
				player.held.def["name"] = "Jerry can (20 L)"
				player.say("Jerry can filled.")
			elif _rv_near(pump, PUMP_REACH):
				rv.op(&"add_fuel", [RVDamage.TANK])
				player.say("Tank full.")
			else:
				player.say("The hose doesn't reach."))
	for n: Node in get_tree().get_nodes_in_group(&"welders"):
		var welder := n as Interactable
		if welder == null or not is_ancestor_of(welder):
			continue
		welder.prompt_for = func(_player: Player) -> String:
			return "Weld" if _rv_near(welder, 28.0) else "Welder"
		welder.used.connect(func(player: Player) -> void:
			if _rv_near(welder, 28.0):
				rv.op(&"weld")
				player.did.emit(&"repair")
				Sfx.cue(self, "tools/weld_zap", welder.global_position, -4.0, 8.0, 60.0)
				player.say("Frame welded good as new; the mechanic looked the engine over too.")
			else:
				player.say("The leads don't reach that far."))


func _rv_near(node: Node3D, radius: float) -> bool:
	return rv.global_position.distance_to(node.global_position) < radius


## What's left of a washed-out bridge: its planks, dumped in a heap off in the trees (where
## the generator put them), the same for the same seed. Nothing points to them.
func _spawn_planks(index: int, supply: Dictionary) -> void:
	var pos: Vector3 = supply["pos"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:planks%d" % [world.get_code(), index])
	for k: int in int(supply["count"]):
		var plank := ItemLibrary.create(&"plank")
		items.add_child(plank)
		var yaw := rng.randf() * TAU
		var at := pos + Vector3(rng.randf_range(-1.6, 1.6), 0.0, rng.randf_range(-1.6, 1.6))
		at.y = world.height_at(at.x, at.z) + 0.12 + 0.07 * k
		var tilt := Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
		plank.global_transform = Transform3D(Basis(Vector3.UP, yaw) * tilt, at)
		plank.freeze = true # Lying there until someone picks one up.
		plank.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func _physics_process(dt: float) -> void:
	if is_finished or rv == null or rv.freeze:
		return
	elapsed += dt
	hours += dt * HOURS_PER_SECOND
	notice_time = maxf(0.0, notice_time - dt)
	if _last_rv_pos != Vector3.INF:
		distance_driven += Vector2(rv.global_position.x - _last_rv_pos.x, rv.global_position.z - _last_rv_pos.z).length()
	_last_rv_pos = rv.global_position
	saved_flash = maxf(0.0, saved_flash - dt)
	_biome_check -= dt
	if _biome_check <= 0.0:
		_biome_check = 1.0
		var b := world.biome_at(rv.global_position.x, rv.global_position.z)
		if b != _biome and _biome >= 0:
			show_notice("Entering %s" % BIOME_NAMES[b], 6.0)
		_biome = b
	if not is_authority:
		return
	if not _left_stop:
		var here: Vector3 = pad(checkpoint)["pos"]
		if Vector2(rv.global_position.x - here.x, rv.global_position.z - here.z).length() > LEAVE_RADIUS:
			_left_stop = true
			checkpoint_rv = rv.slow_snapshot() # As it set off: after the stop's repairs.
	var next := checkpoint + 1
	if next >= pads().size():
		return
	var p := pad(next)
	var pos: Vector3 = p["pos"]
	if Vector2(rv.global_position.x - pos.x, rv.global_position.z - pos.z).length() < ARRIVE_RADIUS:
		_arrive(next)


func _arrive(i: int) -> void:
	reach(i)
	if not is_finished:
		restock(i)
	save()


## Marks stop `i` reached (the host's arrival, copied on clients).
func reach(i: int) -> void:
	checkpoint = i
	checkpoint_rv = rv.slow_snapshot()
	_left_stop = false
	var kind := int(pad(i)["kind"])
	if kind == PAD_HOME:
		is_finished = true
		show_notice("Home! Trip complete.", 30.0)
		finished.emit()
		return
	show_notice("Gas station %d of %d" % [i, station_count()], 8.0)
	checkpoint_reached.emit(i, station_count())


## Puts a station's supplies out in front of its shop.
func restock(i: int) -> void:
	var xf := _pad_transform(pad(i))
	var k := 0
	for spec: Array in RESTOCK:
		for n: int in int(spec[1]):
			var item := ItemLibrary.create(spec[0])
			items.add_child(item)
			var at := xf * Vector3(-5.0 + 1.1 * (k % 9), 0.0, 4.5 + 1.2 * (k / 9))
			at.y = world.height_at(at.x, at.z) + 0.4
			item.global_position = at
			k += 1


## A stop's name: "the camp", "gas station 2", "home".
func stop_name(i: int) -> String:
	match int(pad(i)["kind"]):
		PAD_CAMP:
			return "the camp"
		PAD_HOME:
			return "home"
	return "gas station %d" % i


## Distance (m) to the next stop along the road, and its name.
func next_stop() -> Array:
	var next := checkpoint + 1
	if next >= pads().size():
		return ["", 0.0]
	var p := pad(next)
	var progress := world.road_progress(rv.global_position.x, rv.global_position.z)
	var name := "Home" if int(p["kind"]) == PAD_HOME else "Gas station %d" % next
	if progress < 0.0:
		return [name, -1.0]
	return [name, maxf(0.0, float(p["s"]) - progress)]


func show_notice(text: String, seconds: float) -> void:
	notice = text
	notice_time = seconds


func summary() -> String:
	return "Home in %s: %.1f km driven, %d gas stations, %d stalls, %.0f m of winch rope reeled in." % [
		clock_of(elapsed), distance_driven / 1000.0, station_count(), stalls,
		rv.winches[0].reeled_total + rv.winches[1].reeled_total,
	]


## The time of day, "14:05".
func clock_text() -> String:
	var h := fposmod(hours, 24.0)
	return "%02d:%02d" % [int(h), int(fposmod(h * 60.0, 60.0))]


## Day of the trip, 1 on the first.
func day() -> int:
	return int(hours / 24.0) + 1


static func clock_of(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


# --- saves -------------------------------------------------------------------------------------

func _save_path() -> String:
	return Saves.path(world.get_code())


## Writes the trip as it stands: progress, the clock and (via `extra_save`) the RV, its load
## and everything lying about, so it carries on from right here. A finished trip is kept as
## a record (it can't be continued, only started again).
func save() -> void:
	var previous := Saves.read(world.get_code())
	var progress := world.road_progress(rv.global_position.x, rv.global_position.z)
	var d := {
		"gen": WorldGen.gen_version(), "seed": world.get_code(), "checkpoint": checkpoint,
		"stations": station_count(), "elapsed": elapsed, "distance": distance_driven,
		"stalls": stalls, "hours": hours, "saved_at": Time.get_unix_time_from_system(),
		"finished": is_finished,
	}
	if progress >= 0.0:
		d["progress"] = clampf(progress / float(data.get("length", 1.0)), 0.0, 1.0)
	if is_finished:
		d["completed"] = {"elapsed": elapsed, "at": d["saved_at"]}
	elif previous.has("completed"):
		d["completed"] = previous["completed"]
	if not is_finished:
		d["extra"] = JSON.from_native(extra_save.call() if extra_save.is_valid() else {})
		d["checkpoint_rv"] = JSON.from_native(checkpoint_rv)
	if Saves.write(world.get_code(), d):
		saved_flash = 2.5


## Picks up a saved trip for this seed, if there's one to carry on. Returns true if it did.
func load_save() -> bool:
	var d := Saves.read(world.get_code())
	if not Saves.can_continue(d):
		return false
	checkpoint = clampi(int(d.get("checkpoint", 0)), 0, pads().size() - 2)
	elapsed = float(d.get("elapsed", 0.0))
	distance_driven = float(d.get("distance", 0.0))
	stalls = int(d.get("stalls", 0))
	hours = float(d.get("hours", START_HOUR))
	var extra: Variant = JSON.to_native(d.get("extra", {}))
	loaded_extra = extra if extra is Dictionary else {}
	var at_stop: Variant = JSON.to_native(d.get("checkpoint_rv", []))
	checkpoint_rv = at_stop if at_stop is Array else []
	_left_stop = true # Wherever it was left, it keeps the stop's state it had.
	resumed = true
	return true


func clear_save() -> void:
	Saves.delete(world.get_code())
