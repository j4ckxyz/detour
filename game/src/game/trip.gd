class_name Trip
extends Node3D
## One trip (PLAN.md §4.1, §4.6): from the camp along the generated road, through gas-station
## checkpoints, to home. Builds the stops, supplies and signs from `WorldGen.trip()`, notices
## the RV arriving, saves at each station and ends the trip at home.

signal checkpoint_reached(index: int, total: int)
signal finished

const PAD_CAMP := 0
const PAD_STATION := 1
const PAD_HOME := 2
const OBSTACLE_NAMES: Array[String] = ["Washed-out gap", "Ledge", "Mud", "Steep climb"]
## How close (m) the RV must get to a pad's centre to arrive (stations sit beside the road:
## their centre is ~14 m from it).
const ARRIVE_RADIUS := 20.0
const SAVE_DIR := "user://saves"
## Items a station restocks (kind, count).
const RESTOCK: Array[Array] = [
	[&"plank", 2], [&"jerrycan", 1], [&"scrap_metal", 2], [&"motor_oil", 1], [&"burger", 2], [&"spare_tire", 1],
]

var world: WorldGen
var rv: RV
var items: Node3D
var data: Dictionary
## Index into `data.pads` of the last stop reached (0 = the camp).
var checkpoint := 0
var elapsed := 0.0
var distance_driven := 0.0
var stalls := 0
var is_finished := false
## A one-line message for the HUD (e.g. "Checkpoint!"), and how long it stays.
var notice := ""
var notice_time := 0.0

var _last_rv_pos := Vector3.INF


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


## Builds the stops, plank piles and warning signs (after the ground under them has
## streamed in, so things sit on it).
func build() -> void:
	for i: int in pads().size():
		var p: Dictionary = pads()[i]
		var node := TripStops.build(int(p["kind"]), i, station_count())
		add_child(node)
		node.global_transform = _pad_transform(p)
	for supply: Dictionary in data.get("supplies", []):
		if int(supply["kind"]) == 0:
			_spawn_planks(supply)
	for o: Dictionary in data.get("obstacles", []):
		_add_warning_sign(o)
		if int(o["kind"]) == 0:
			_add_abutments(o)


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


func _spawn_planks(supply: Dictionary) -> void:
	var pos: Vector3 = supply["pos"]
	var dir: Vector3 = supply["dir"]
	var side := Vector3(-dir.z, 0.0, dir.x)
	for k: int in int(supply["count"]):
		var plank := ItemLibrary.create(&"plank")
		items.add_child(plank)
		var at := pos + side * (0.4 * k)
		at.y = world.height_at(at.x, at.z) + 0.15 + 0.06 * k
		plank.global_transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), at) # Lying along the road.
		plank.freeze = true # Stacked neatly until someone picks one up.
		plank.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC


func _add_warning_sign(o: Dictionary) -> void:
	var kind := int(o["kind"])
	var pos: Vector3 = o["pos"]
	var dir: Vector3 = o["dir"]
	var at := pos - dir * 45.0 + Vector3(-dir.z, 0.0, dir.x) * (float(data["road_half_width"]) + 1.2)
	at.y = world.height_at(at.x, at.z)
	var sign := TripStops.warning_sign(OBSTACLE_NAMES[kind])
	add_child(sign)
	sign.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at)


func _physics_process(dt: float) -> void:
	if is_finished or rv == null or rv.freeze:
		return
	elapsed += dt
	notice_time = maxf(0.0, notice_time - dt)
	if _last_rv_pos != Vector3.INF:
		distance_driven += Vector2(rv.global_position.x - _last_rv_pos.x, rv.global_position.z - _last_rv_pos.z).length()
	_last_rv_pos = rv.global_position
	var next := checkpoint + 1
	if next >= pads().size():
		return
	var p := pad(next)
	var pos: Vector3 = p["pos"]
	if Vector2(rv.global_position.x - pos.x, rv.global_position.z - pos.z).length() < ARRIVE_RADIUS:
		_arrive(next)


func _arrive(i: int) -> void:
	checkpoint = i
	var kind := int(pad(i)["kind"])
	if kind == PAD_HOME:
		is_finished = true
		clear_save()
		show_notice("Home! Trip complete.", 30.0)
		finished.emit()
		return
	restock(i)
	save()
	show_notice("Gas station %d of %d: checkpoint saved, supplies restocked." % [i, station_count()], 8.0)
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
		_clock(elapsed), distance_driven / 1000.0, station_count(), stalls,
		rv.winches[0].reeled_total + rv.winches[1].reeled_total,
	]


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]


# --- saves -------------------------------------------------------------------------------------

func _save_path() -> String:
	return SAVE_DIR.path_join("%s.json" % world.get_code())


func save() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"gen": WorldGen.gen_version(), "seed": world.get_code(), "checkpoint": checkpoint,
		"elapsed": elapsed, "distance": distance_driven, "stalls": stalls,
	}, "\t"))


## Picks up a saved trip for this seed, if there is one. Returns true if it did.
func load_save() -> bool:
	var text := FileAccess.get_file_as_string(_save_path())
	var d: Variant = JSON.parse_string(text) if text != "" else null
	if not d is Dictionary or int(d.get("gen", 0)) != WorldGen.gen_version():
		return false
	checkpoint = clampi(int(d.get("checkpoint", 0)), 0, pads().size() - 2)
	elapsed = float(d.get("elapsed", 0.0))
	distance_driven = float(d.get("distance", 0.0))
	stalls = int(d.get("stalls", 0))
	return checkpoint > 0


func clear_save() -> void:
	if FileAccess.file_exists(_save_path()):
		DirAccess.remove_absolute(_save_path())
