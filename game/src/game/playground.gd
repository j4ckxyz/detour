class_name Playground
extends Node3D
## Walk, board and drive the RV through a generated world. Becomes the game scene once trips
## and netcode land.
##
## User arguments (after `--`):
##   --seed=CODE      world seed code
##   --preset=NAME    potato | low | medium | high (default: detected)
##   --automatic      start with the automatic gearbox
##   --new            ignore any saved progress for this seed (start at the camp)
##   --peaceful       no wildlife
##
## Keys: see the F1 help. F5-F8 switch graphics presets, F3 perf overlay.

## Emitted once the RV has been placed on solid ground and can drive.
signal spawned

const DEFAULT_SEED := "DT2-01YPW-3A7T8" # A Short trip (v1 terrain seed DT1-81YPW-3A7TA).
const START := Vector3(64.0, 0.0, 64.0)
const RV_SCENE := preload("res://src/rv/rv.tscn")
const PRESET_KEYS: Dictionary[Key, StringName] = {
	KEY_F5: &"potato", KEY_F6: &"low", KEY_F7: &"medium", KEY_F8: &"high",
}
## RV footprint for spawn checks (half extents, metres), a little generous.
const RV_HALF_EXTENTS := Vector3(1.5, 1.4, 4.2)
## Wheel contact points in RV space (FL, FR, RL, RR), for levelness checks.
const WHEEL_SPOTS: Array[Vector2] = [
	Vector2(-0.92, -2.9), Vector2(0.92, -2.9), Vector2(-0.9, 1.55), Vector2(0.9, 1.55),
]
## Steepest spawn: nose-to-tail rise over the wheelbase (≈ 9°) and side-to-side lean over
## the track (≈ 4°).
const MAX_SPAWN_PITCH := 0.7
const MAX_SPAWN_ROLL := 0.12

var world := WorldGen.new()
var lighting := WorldLighting.new()
var streamer := TerrainStreamer.new()
var camera := RVCamera.new()
var driver := RVDriverInput.new()
var hud := RVHud.new()
var overlay := PerfOverlay.new()
var menu := PauseMenu.new()
var player := Player.new()
var player_hud := PlayerHud.new()
var trip := Trip.new()
var trip_hud := TripHud.new()
var wildlife := Wildlife.new()
## Loose items in the world.
var items := Node3D.new()
var rv: RV
var is_spawned := false
## Ignore saved progress (tests set this before adding the playground).
var fresh_start := false
## No wildlife (tests that aren't about it set this before adding the playground).
var peaceful := false

var _args: Dictionary[String, String] = {}
var _spawn_near := START
var _spawn_box := BoxShape3D.new()


func _ready() -> void:
	_parse_args()
	var code: String = _args.get("seed", DEFAULT_SEED)
	if not world.load(code):
		get_tree().quit(2)
		return
	add_child(lighting)

	rv = RV_SCENE.instantiate()
	rv.freeze = true # Until the ground under it exists.
	add_child(rv)
	rv.set_automatic(_args.has("automatic"))
	rv.surface_query = world.mud_at
	trip.name = "Trip"
	add_child(trip)
	trip.setup(world, rv, items)
	if not (_args.has("new") or fresh_start):
		trip.load_save()
	var start := trip.start_transform()
	_spawn_near = start.origin
	rv.global_transform = start.translated(Vector3.UP * 1.0)

	items.name = "Items"
	add_child(items)
	driver.rv = rv
	driver.enabled = false # Until someone sits in the driver's seat.
	driver.reset_requested.connect(_on_reset_requested)
	add_child(driver)
	camera.rv = rv
	camera.driver_input = driver
	camera.fov = 72.0
	add_child(camera)

	streamer.focus = rv
	streamer.collision_foci = [rv]
	add_child(streamer)
	if not streamer.start(world.get_code()):
		get_tree().quit(2)
		return

	hud.rv = rv
	hud.visible = false
	add_child(hud)
	player.name = "Player"
	player.rv = rv
	player.world_items = items
	player.seat_changed.connect(_on_seat_changed)
	player.passed_out.connect(_on_passed_out)
	player_hud.player = player
	player_hud.visible = false
	add_child(player_hud)
	trip_hud.trip = trip
	add_child(trip_hud)
	menu.add_action("Tow to the last checkpoint", tow_to_checkpoint)
	menu.add_action("Restart this trip", restart_trip)
	overlay.streamer = streamer
	overlay.extra_lines = _overlay_lines
	overlay.visible = false
	add_child(overlay)
	add_child(menu)

	_spawn_box.size = RV_HALF_EXTENTS * 2.0
	_apply_preset(StringName(_args.get("preset", String(Graphics.detect_default()))))


func _exit_tree() -> void:
	if not player.is_inside_tree():
		player.free() # Quit before spawning.


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _apply_preset(preset: StringName) -> void:
	lighting.apply_preset(preset, get_viewport(), streamer, camera)
	player.camera.far = camera.far


func _overlay_lines() -> String:
	return "seed %s\nRV %s  %.1f m/s" % [world.get_code(), rv.global_position.snappedf(0.1), rv.forward_speed()]


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button and button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and PRESET_KEYS.has(key.physical_keycode):
		_apply_preset(PRESET_KEYS[key.physical_keycode])


func _physics_process(_dt: float) -> void:
	if is_spawned and rv.freeze and streamer.has_collision_at(rv.global_position):
		rv.freeze = false
		rv.reset_physics_interpolation()
	if is_spawned and not player.inside:
		_catch_falling_player()
	if is_spawned or not streamer.has_collision_at(_spawn_near):
		return
	_place_rv(trip.start_transform())
	trip.build()
	wildlife.name = "Wildlife"
	add_child(wildlife)
	wildlife.setup(world, rv, items, trip.data)
	if not (peaceful or _args.has("peaceful")):
		wildlife.populate()
	_spawn_player()
	if trip.checkpoint == 0:
		_spawn_starter_items()
	else:
		trip.restock(trip.checkpoint)
		trip.show_notice("Welcome back: continuing from gas station %d." % trip.checkpoint, 6.0)
	is_spawned = true
	spawned.emit()


## Someone who slipped under the ground (a glitch, a teleport onto a slope) is put back on it.
func _catch_falling_player() -> void:
	var p := player.global_position
	var ground := world.height_at(p.x, p.z)
	if p.y < ground - 3.0 and streamer.has_collision_at(p):
		player.global_position = Vector3(p.x, ground + 0.5, p.z)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()


## "Call a tow": the RV (and you) go back to the last checkpoint. It costs 15 minutes.
func tow_to_checkpoint() -> void:
	if not is_spawned:
		return
	if player.seat != &"":
		player.stand_up()
	if player.inside:
		player.leave_rv()
	_place_rv(trip.start_transform())
	player.global_position = by_the_door() + Vector3.UP * 0.1
	player.reset_physics_interpolation()
	trip.elapsed += 15.0 * 60.0
	trip.show_notice("Towed back to the last checkpoint (+15 min).", 6.0)


func restart_trip() -> void:
	trip.clear_save()
	get_tree().reload_current_scene()


## Where someone stands outside the RV's door (world space, on the ground).
func by_the_door() -> Vector3:
	var door := Vector3(rv.interior.door_x_outer + 1.6, 0.0, (rv.interior.door_z.x + rv.interior.door_z.y) * 0.5)
	var at := rv.to_global(door)
	at.y = world.height_at(at.x, at.z) + 0.1
	return at


## Bled out: they come to by the RV (or where they lay, if that was inside it).
func _on_passed_out() -> void:
	var cause := player.hurt_cause
	if not player.inside:
		player.global_position = by_the_door()
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
	player.wake_up(50.0)
	trip.elapsed += 5.0 * 60.0
	trip.show_notice("You passed out (%s) and came to by the RV (+5 min)." % cause, 6.0)


## Puts the player on foot by the RV's door, facing it.
func _spawn_player() -> void:
	var at := by_the_door()
	add_child(player)
	player.global_position = at
	var to_rv := rv.global_position - at
	player.look(atan2(-to_rv.x, -to_rv.z), -0.1)
	player.camera.current = true
	player_hud.visible = true
	streamer.focus = player
	streamer.collision_foci = [rv, player]


## A few things to find: planks and fuel by the RV, the winch remote and first aid inside.
func _spawn_starter_items() -> void:
	var outside: Array[Array] = [
		[&"plank", Vector3(3.0, 0.0, 1.0)], [&"plank", Vector3(3.0, 0.0, 1.4)],
		[&"jerrycan", Vector3(2.6, 0.0, -2.2)], [&"scrap_metal", Vector3(3.2, 0.0, -1.6)],
		[&"spare_tire", Vector3(-2.8, 0.0, 0.5)], [&"motor_oil", Vector3(2.4, 0.0, 2.4)],
	]
	for spec: Array in outside:
		var item := ItemLibrary.create(spec[0])
		var at := rv.to_global(spec[1])
		at.y = world.height_at(at.x, at.z) + 0.3
		items.add_child(item)
		item.global_position = at
	var inside: Array[Array] = [
		[&"winch_remote", Vector3(-0.3, 1.34, -2.35)], [&"first_aid", Vector3(-0.85, 1.6, -0.62)],
		[&"burger", Vector3(-0.7, 1.6, -0.5)], [&"burger", Vector3(-0.95, 1.6, -0.45)],
		[&"hammer", Vector3(0.85, 1.8, -1.1)], [&"drill", Vector3(0.85, 1.8, -1.35)],
		[&"scrap_metal", Vector3(0.0, 0.9, -0.9)], [&"scrap_metal", Vector3(0.0, 0.9, -1.4)],
		[&"epipen", Vector3(-0.3, 1.34, -2.15)], [&"antidote", Vector3(-0.15, 1.34, -2.2)],
		[&"bear_spray", Vector3(0.95, 1.8, -0.85)], [&"soda", Vector3(0.7, 1.8, 0.7)],
		[&"patty", Vector3(0.75, 1.8, 0.45)], [&"patty", Vector3(0.9, 1.8, 0.45)],
	]
	for spec: Array in inside:
		var item := ItemLibrary.create(spec[0])
		rv.stash.add_child(item)
		item.stow(rv, Transform3D(Basis.IDENTITY, spec[1]))


func _on_seat_changed(seat: StringName) -> void:
	var driving := seat == &"driver"
	driver.enabled = driving
	hud.visible = driving
	camera.current = driving
	player.camera.current = not driving
	if not driving:
		rv.throttle = 0.0
		rv.brake = 0.0
		rv.steer_input = 0.0
		rv.clutch_input = 0.0
		rv.handbrake = false
		if absf(rv.forward_speed()) < 1.0:
			rv.parking_brake = true


func _on_reset_requested() -> void:
	if not is_spawned:
		return
	# Back on the wheels on the road where you are, else somewhere clear nearby.
	var s := world.road_progress(rv.global_position.x, rv.global_position.z)
	if s >= 0.0:
		_place_rv(trip.road_transform(s))
	else:
		respawn(rv.global_position, 60.0)


## Puts the RV back on its wheels at the nearest clear, level spot. False if none is found.
func respawn(near: Vector3, max_radius: float, ahead: float = 22.0) -> bool:
	var spot: Variant = find_spawn(near, max_radius, ahead)
	if spot == null:
		return false
	_place_rv(spot)
	return true


## A level spot with nothing in the way near `near`, facing a direction with `ahead` metres
## of open ground if it can, as the RV's transform; or null. Searches outwards in rings, only
## where collision has streamed in.
func find_spawn(near: Vector3, max_radius: float, ahead: float = 22.0) -> Variant:
	var space := get_world_3d().direct_space_state
	var ring := 0
	while ring * 12.0 <= max_radius:
		var count := maxi(1, ring * 8)
		for i: int in count:
			var angle := TAU * i / count
			var p := near + Vector3(cos(angle), 0.0, sin(angle)) * ring * 12.0
			if not streamer.has_collision_at(p):
				continue
			var best: Variant = null
			for y: int in 8:
				var yaw := TAU * y / 8.0
				var ground: Variant = _level_ground(p, yaw)
				if ground == null:
					continue
				var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, ground, p.z))
				if not _footprint_clear(space, xf):
					continue
				if best == null:
					best = xf
				if _clear_ahead(space, xf, ahead):
					return xf.translated(Vector3.UP * 0.25) # Open road ahead: take it.
			if best != null:
				return (best as Transform3D).translated(Vector3.UP * 0.25)
		ring += 1
	return null


## Highest ground under the wheels if the spot is level enough, else null.
func _level_ground(p: Vector3, yaw: float) -> Variant:
	var basis := Basis(Vector3.UP, yaw)
	var h: Array[float] = []
	for w: Vector2 in WHEEL_SPOTS:
		var q := p + basis * Vector3(w.x, 0.0, w.y)
		h.append(world.height_at(q.x, q.z))
	var pitch := absf((h[0] + h[1]) - (h[2] + h[3])) * 0.5
	var roll := absf((h[0] + h[2]) - (h[1] + h[3])) * 0.5
	var twist := absf((h[0] - h[1]) - (h[2] - h[3]))
	if pitch > MAX_SPAWN_PITCH or roll > MAX_SPAWN_ROLL or twist > MAX_SPAWN_ROLL:
		return null
	return h.max()


## Whether nothing (a rock, stump, trunk, log) sits under or around the RV. The box reaches
## below the ground, so the terrain's own shape is ignored.
func _footprint_clear(space: PhysicsDirectSpaceState3D, xf: Transform3D) -> bool:
	var query := _box_query(xf.translated_local(Vector3(0.0, RV_HALF_EXTENTS.y - 0.5, 0.0)))
	return _only_ground(space.intersect_shape(query, 16))


## Whether the corridor `ahead` metres in front of the RV is free of props (the terrain
## itself doesn't count: the RV can climb).
func _clear_ahead(space: PhysicsDirectSpaceState3D, xf: Transform3D, ahead: float) -> bool:
	if ahead <= 0.0:
		return true
	var corridor := BoxShape3D.new()
	corridor.size = Vector3(RV_HALF_EXTENTS.x * 2.0 + 1.0, 6.0, ahead)
	var query := _box_query(xf.translated_local(Vector3(0.0, 1.0, -RV_HALF_EXTENTS.z - ahead * 0.5)))
	query.shape = corridor
	return _only_ground(space.intersect_shape(query, 32))


static func _only_ground(hits: Array[Dictionary]) -> bool:
	for hit: Dictionary in hits:
		if int(hit["shape"]) != TerrainStreamer.GROUND_SHAPE:
			return false
	return true


func _box_query(xf: Transform3D) -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _spawn_box
	query.collision_mask = TerrainStreamer.WORLD_LAYER
	query.transform = xf
	return query


## True while the RV waits (frozen) for collision to stream in where it was just put.
func is_rv_waiting() -> bool:
	return rv.freeze and is_spawned


func _place_rv(xf: Transform3D) -> void:
	# After a long move (a tow, a reset far away) the ground there may not be solid yet: hold
	# the RV still until it is, or it would fall through the world.
	rv.freeze = not streamer.has_collision_at(xf.origin)
	rv.global_transform = xf
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	rv.parking_brake = true
	rv.reset_physics_interpolation()
	camera.snap()
