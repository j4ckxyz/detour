class_name Playground
extends Node3D
## Drive the RV through a generated world. Phase 1 playground: becomes the game scene once
## trips, players and netcode land.
##
## User arguments (after `--`):
##   --seed=CODE      world seed code
##   --preset=NAME    potato | low | medium | high (default: detected)
##   --automatic      start with the automatic gearbox
##
## Keys: see the F1 help. F5-F8 switch graphics presets, F3 perf overlay.

## Emitted once the RV has been placed on solid ground and can drive.
signal spawned

const DEFAULT_SEED := "DT1-81YPW-3A7TA"
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
var rv: RV
var is_spawned := false

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
	rv.global_position = START + Vector3.UP * (world.height_at(START.x, START.z) + 1.0)
	rv.set_automatic(_args.has("automatic"))

	driver.rv = rv
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
	add_child(hud)
	overlay.streamer = streamer
	overlay.extra_lines = _overlay_lines
	overlay.visible = false
	add_child(overlay)

	_spawn_box.size = RV_HALF_EXTENTS * 2.0
	_apply_preset(StringName(_args.get("preset", String(Graphics.detect_default()))))


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _apply_preset(preset: StringName) -> void:
	lighting.apply_preset(preset, get_viewport(), streamer, camera)


func _overlay_lines() -> String:
	return "seed %s\nRV %s  %.1f m/s" % [world.get_code(), rv.global_position.snappedf(0.1), rv.forward_speed()]


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and PRESET_KEYS.has(key.physical_keycode):
		_apply_preset(PRESET_KEYS[key.physical_keycode])


func _physics_process(_dt: float) -> void:
	if is_spawned or not streamer.has_collision_at(_spawn_near):
		return
	var spot: Variant = find_spawn(_spawn_near, 240.0)
	if spot == null:
		push_warning("No clear, level spot near %s; dropping the RV there anyway." % _spawn_near)
		spot = Transform3D(Basis.IDENTITY, _spawn_near + Vector3.UP * (world.height_at(_spawn_near.x, _spawn_near.z) + 1.0))
	_place_rv(spot)
	is_spawned = true
	spawned.emit()


func _on_reset_requested() -> void:
	if is_spawned:
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


func _place_rv(xf: Transform3D) -> void:
	rv.freeze = false
	rv.global_transform = xf
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	rv.parking_brake = true
	rv.reset_physics_interpolation()
	camera.snap()
