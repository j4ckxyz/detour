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
##
## Solo and hosting, the trip saves itself every AUTOSAVE_SECONDS, on reaching a gas station,
## and on leaving or quitting; the next launch carries on from exactly there.
##   --peaceful       no wildlife
##
## Keys: see the F1 help. F5-F8 switch graphics presets, F3 perf overlay.

## Emitted once the RV has been placed on solid ground and can drive.
signal spawned

const DEFAULT_SEED := "DT5-00000-000ZG" # A short trip: woods, mud, gaps and a bridge with a hole; canyon: a climb, a ledge, a ford; the pass: ice, beams and a hill.
const START := Vector3(64.0, 0.0, 64.0)
const RV_SCENE := preload("res://src/rv/rv.tscn")
const MAIN_MENU := "res://src/ui/main_menu.tscn"
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
const AUTOSAVE_SECONDS := 60.0
## The RV's wrecked (back to the last stop) once it's lain this far below the road for this
## long: down a ravine or a gully it can't get out of.
const FALLEN_DEPTH := 3.5
const FALLEN_SECONDS := 3.0
## Going back to the last stop costs this much of the day.
const CHECKPOINT_MINUTES := 30.0
## Item kinds a save doesn't keep: the winch hooks belong to the RV.
const UNSAVED_KINDS: Array[StringName] = [&"winch_hook"]

var world := WorldGen.new()
var lighting := WorldLighting.new()
var streamer := TerrainStreamer.new()
var camera := RVCamera.new()
var driver := RVDriverInput.new()
var hud := RVHud.new()
var overlay := PerfOverlay.new()
## Up while the world generates and the ground streams in; gone once the trip's ready.
var loading: LoadingScreen
var menu := PauseMenu.new()
var player := Player.new()
var player_hud := PlayerHud.new()
var trip := Trip.new()
var trip_hud := TripHud.new()
var status_panel := StatusPanel.new()
var wildlife := Wildlife.new()
var net := NetGame.new()
var weather := Weather.new()
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
var _autosave_timer := 0.0
## Loose things put back from a save, held still until the ground under them is solid.
var _settling: Array[Item] = []
## Set when the trip is being thrown away (restarting it): nothing more gets saved.
var _discard_save := false
## The world has finished generating (in the background) and the scene is set up.
var _loaded := false
var _load_waited := 0.0
var _fallen_for := 0.0


func _ready() -> void:
	_parse_args()
	var code: String = _args.get("seed", Session.seed_code if Session.seed_code != "" else DEFAULT_SEED)
	var problem := WorldGen.code_error(code)
	if problem != "":
		push_error("Bad seed code '%s': %s" % [code, problem])
		get_tree().quit(2)
		return
	loading = LoadingScreen.new(_loading_title(code), "Seed %s" % code)
	add_child(loading)
	# The world generates on a background thread; the rest waits for it (`_poll_load`).
	world.begin_load(code)


## What the loading screen says: joining someone, carrying on a saved trip, a map built before
## (this session), or a brand new one.
func _loading_title(code: String) -> String:
	if Session.mode == Session.Mode.CLIENT:
		return "Joining %s's trip" % Session.name_of(1)
	if not (_args.has("new") or fresh_start) and Saves.can_continue(Saves.read(code)):
		return "Loading your trip"
	if WorldGen.is_cached(code):
		return "Loading the map"
	return "Generating a new map"


func _poll_load(dt: float) -> void:
	if _loaded:
		# The ground streams in round the RV: that's the rest of the bar.
		var ready := float(streamer.chunks_loaded)
		var fraction := ready / maxf(1.0, ready + float(streamer.pending()))
		loading.progress = maxf(loading.progress, 0.5 + 0.45 * fraction)
		if is_spawned:
			_load_waited += dt
			loading.stage = "Almost there"
			if streamer.pending() == 0 or _load_waited > 6.0:
				loading.finish()
		return
	match world.poll_load():
		0:
			loading.progress = 0.5 * world.load_progress()
			loading.stage = world.load_stage()
		1:
			_loaded = true
			loading.progress = 0.5
			loading.stage = "Building the terrain"
			_setup()
		_:
			Session.last_message = "Couldn't load the trip: %s" % world.load_error()
			Session.leave()
			get_tree().change_scene_to_file(MAIN_MENU)


## Everything that needs the world: the RV, the trip, the streamer, the HUDs.
func _setup() -> void:
	add_child(lighting)

	rv = RV_SCENE.instantiate()
	rv.freeze = true # Until the ground under it exists.
	add_child(rv)
	rv.set_automatic(_args.has("automatic"))
	rv.surface_query = world.mud_at
	rv.ice_query = world.ice_at
	rv.water_query = world.water_level
	trip.name = "Trip"
	add_child(trip)
	trip.setup(world, rv, items)
	trip.extra_save = _save_extra
	if Session.mode == Session.Mode.CLIENT:
		# Joining: the host says where the RV is (the full state follows once we're in).
		var info := Session.start_info
		trip.checkpoint = int(info.get("checkpoint", 0))
		rv.global_transform = info.get("rv", trip.start_transform())
		_spawn_near = rv.global_position
	else:
		if not (_args.has("new") or fresh_start):
			trip.load_save()
		var start := _resume_transform()
		_spawn_near = start.origin
		rv.global_transform = start.translated(Vector3.UP * 1.0)
		Session.start_info_source = func() -> Dictionary:
			return {"checkpoint": trip.checkpoint, "rv": rv.global_transform}

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
	player.water_query = world.water_level
	player.ice_query = world.ice_at
	player_hud.player = player
	player_hud.visible = false
	add_child(player_hud)
	trip_hud.trip = trip
	trip_hud.weather = weather
	status_panel.player = player
	status_panel.rv = rv
	add_child(status_panel)
	add_child(trip_hud)
	weather.name = "Weather"
	weather.setup(world.get_code())
	add_child(weather)
	menu.before_quit = autosave
	if Session.is_host():
		menu.add_action("Tow to the last checkpoint", tow_to_checkpoint)
		menu.add_action("Restart this trip", restart_trip)
	menu.add_action("Leave to the main menu" if Session.is_online() else "Main menu", leave_to_menu)
	overlay.streamer = streamer
	overlay.extra_lines = _overlay_lines
	overlay.visible = false
	add_child(overlay)
	add_child(menu)
	add_child(net)
	Session.ended.connect(func(_message: String) -> void: get_tree().change_scene_to_file(MAIN_MENU))

	_spawn_box.size = RV_HALF_EXTENTS * 2.0
	_apply_preset(StringName(_args.get("preset", String(Graphics.detect_default()))))


func _exit_tree() -> void:
	if not player.is_inside_tree():
		player.free() # Quit before spawning.


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()


## Saves the trip as it is now (solo or hosting, once it's running and not over).
func autosave() -> void:
	if is_spawned and Session.is_host() and not trip.is_finished and not _discard_save:
		trip.save()
	_autosave_timer = 0.0


## Where the RV goes when the trip loads: where a save left it, else the last stop reached.
func _resume_transform() -> Transform3D:
	var xf: Variant = trip.loaded_extra.get("rv_xf")
	if xf is Transform3D:
		var at: Transform3D = xf
		# Upright, on the ground there (a save mid-tumble shouldn't load upside down).
		var fwd := -at.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.1:
			fwd = Vector3.FORWARD
		var pos := at.origin
		pos.y = world.height_at(pos.x, pos.z) + 0.6
		return Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)
	return trip.start_transform()


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
	if not _loaded:
		return
	var button := event as InputEventMouseButton
	if button and button.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and PRESET_KEYS.has(key.physical_keycode):
		_apply_preset(PRESET_KEYS[key.physical_keycode])


func _process(dt: float) -> void:
	if is_instance_valid(loading) and not loading.is_finishing():
		_poll_load(dt)
	if not _loaded:
		return
	var cam := get_viewport().get_camera_3d()
	var at := cam.global_position if cam else rv.global_position
	weather.update(trip.hours, at, world.biome_at(at.x, at.z), dt)
	lighting.set_conditions(fposmod(trip.hours, 24.0), weather.cloud, weather.fog, weather.flash)
	rv.wetness = weather.wetness
	rv.wind = weather.wind


func _physics_process(dt: float) -> void:
	if not _loaded:
		return
	if is_spawned and Session.is_host() and not trip.is_finished:
		_autosave_timer += dt
		if _autosave_timer >= AUTOSAVE_SECONDS:
			autosave()
	if is_spawned and rv.is_simulated and rv.freeze and streamer.has_collision_at(rv.global_position):
		rv.freeze = false
		rv.reset_physics_interpolation()
	if is_spawned and not player.inside:
		_catch_falling_player()
	if is_spawned:
		_check_wreck(dt)
	if not _settling.is_empty(): # One a frame, round and round.
		var item: Item = _settling.pop_back()
		if is_instance_valid(item) and item.holder == null and item.get_parent() == items and item.freeze:
			if streamer.has_collision_at(item.global_position):
				item.freeze = false
			else:
				_settling.push_front(item)
	if is_spawned or not streamer.has_collision_at(_spawn_near):
		return
	var client := Session.mode == Session.Mode.CLIENT
	if not client:
		_place_rv(_resume_transform())
	# A save has everything that lay about the world (what was picked up is gone from it).
	var restoring := trip.resumed and trip.loaded_extra.has("world")
	trip.build(not client and not restoring)
	wildlife.name = "Wildlife"
	add_child(wildlife)
	wildlife.setup(world, rv, items, trip.data)
	if not (peaceful or _args.has("peaceful")):
		wildlife.populate()
	_spawn_player()
	if client:
		trip.show_notice("Joined %s's trip." % Session.name_of(1), 6.0)
	elif not trip.resumed:
		_spawn_starter_items()
		trip.checkpoint_rv = rv.slow_snapshot()
	else:
		_restore_extra(trip.loaded_extra)
		if trip.checkpoint_rv.is_empty():
			trip.checkpoint_rv = rv.slow_snapshot()
		if not restoring and trip.checkpoint > 0:
			trip.restock(trip.checkpoint)
		trip.show_notice("Welcome back.", 5.0)
	is_spawned = true
	net.start(self)
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
	net.reclaim_rv()
	if player.seat != &"":
		player.stand_up()
	if player.inside:
		player.leave_rv()
	_place_rv(trip.start_transform())
	player.global_position = by_the_door() + Vector3.UP * 0.1
	player.reset_physics_interpolation()
	trip.elapsed += 15.0 * 60.0
	trip.hours += 1.0
	trip.show_notice("Towed back to the last checkpoint (+15 min).", 6.0)


func restart_trip() -> void:
	_discard_save = true
	trip.clear_save()
	if Session.is_online():
		Session.leave()
	get_tree().reload_current_scene()


func leave_to_menu() -> void:
	autosave()
	Session.leave()
	get_tree().change_scene_to_file(MAIN_MENU)


## Where someone stands outside the RV's door (world space, on the ground).
func by_the_door() -> Vector3:
	var door := Vector3(rv.interior.door_x_outer + 1.6, 0.0, (rv.interior.door_z.x + rv.interior.door_z.y) * 0.5)
	var at := rv.to_global(door)
	at.y = world.height_at(at.x, at.z) + 0.1
	return at


## Whether the RV's done for (host or solo): its frame or engine gone, or lying down a ravine
## below the road. Then everyone goes back to the last stop.
func _check_wreck(dt: float) -> void:
	if not Session.is_host() or trip.is_finished or rv.freeze:
		_fallen_for = 0.0
		return
	var d := rv.damage
	var reason := ""
	if d.frame <= 0.0:
		reason = "The RV's frame gave out."
	elif d.engine <= 0.0:
		reason = "The engine's finished."
	elif rv.global_position.y < road_height_near(rv.global_position) - FALLEN_DEPTH:
		_fallen_for += dt
		if _fallen_for > FALLEN_SECONDS:
			reason = "The RV went over the edge."
	else:
		_fallen_for = 0.0
	if reason != "":
		back_to_checkpoint(reason)


## The road's own height (not the ground's: a ravine under a bridge doesn't count) near a
## point, or -INF if it's well away from the road.
func road_height_near(p: Vector3) -> float:
	var s := world.road_progress(p.x, p.z)
	if s < 0.0:
		return -INF
	var pts: PackedVector3Array = trip.data["points"]
	var i := clampi(int(s / 8.0), 0, pts.size() - 2)
	return lerpf(pts[i].y, pts[i + 1].y, clampf(s / 8.0 - i, 0.0, 1.0))


## The RV's wrecked or everyone's down: the RV goes back to the last stop as it was when it
## set off from there, and everyone with it. It costs half an hour. Host or solo.
func back_to_checkpoint(reason: String) -> void:
	if not is_spawned:
		return
	net.reclaim_rv()
	_fallen_for = 0.0
	if not trip.checkpoint_rv.is_empty():
		_restore_rv(trip.checkpoint_rv)
	_place_rv(trip.start_transform())
	trip.elapsed += CHECKPOINT_MINUTES * 60.0
	trip.hours += CHECKPOINT_MINUTES / 60.0
	var message := "%s Back to %s (+%d min)." % [reason, trip.stop_name(trip.checkpoint), roundi(CHECKPOINT_MINUTES)]
	return_to_rv(message)
	net.back_to_checkpoint(message)
	autosave()


## Puts the RV back in the condition `slow` (`RV.slow_snapshot()`), clearing away the pieces
## of it lying about that are back on it.
func _restore_rv(slow: Array) -> void:
	var d := rv.damage
	var parts_off: Dictionary = {}
	for id: StringName in d.parts:
		parts_off[id] = not d.parts[id].attached
	var wheels_off: Array[bool] = []
	for i: int in 4:
		wheels_off.append(not d.wheel_on[i])
	var automatic := rv.drivetrain.automatic # The driver's choice, not the RV's condition.
	rv.apply_slow_snapshot(slow)
	rv.drivetrain.automatic = automatic
	rv.drivetrain.shift_to_neutral() # Parked, ready to start.
	for n: Node in get_tree().get_nodes_in_group(&"items"):
		var item := n as Item
		if item == null or item.holder != null:
			continue
		if item.kind == &"rv_part":
			var id := StringName(item.get_meta(&"part", &""))
			if parts_off.get(id, false) and d.parts.has(id) and d.parts[id].attached:
				item.queue_free()
		elif item.kind == &"rv_wheel":
			var i := int(item.get_meta(&"wheel", -1))
			if i >= 0 and i < 4 and wheels_off[i] and d.wheel_on[i]:
				item.queue_free()
	# Never back to a wreck (it would only be sent back again).
	d.frame = maxf(d.frame, RVDamage.FULL * 0.25)
	d.engine = maxf(d.engine, RVDamage.FULL * 0.25)
	d.temperature = 0.25
	rv.drivetrain.running = d.can_start()


## Brings the local player back to the RV's door (after `back_to_checkpoint`): out of any
## seat, on their feet, told why.
func return_to_rv(message: String) -> void:
	if player.seat != &"":
		player.stand_up()
	if player.inside:
		player.leave_rv()
	if player.downed or player.health < 30.0:
		player.wake_up(maxf(player.health, 60.0))
	player.global_position = by_the_door()
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	trip.show_notice(message, 8.0)


## Bled out: solo (or everyone down), back to the last stop; with others still up, they come
## to by the RV (or where they lay, if that was inside it).
func _on_passed_out() -> void:
	var cause := player.hurt_cause
	if Session.is_host() and net.everyone_down(player):
		back_to_checkpoint("You passed out (%s)." % cause if not Session.is_online() else "Everyone's down.")
		return
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


## A few things to find: planks and fuel by the RV; tools, food and medicine put away inside.
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
	var remote := ItemLibrary.create(&"winch_remote")
	rv.stash.add_child(remote)
	remote.stow(rv, Transform3D(Basis.IDENTITY, Vector3(-0.3, 1.34, -2.35))) # On the dashboard.
	var stored: Array[Array] = [
		[&"hammer", &"ToolWall1"], [&"drill", &"ToolWall2"],
		[&"burger", &"FridgeTop1"], [&"burger", &"FridgeTop2"], [&"patty", &"FridgeTop3"], [&"patty", &"FridgeTop4"],
		[&"soda", &"CupHolder1"], [&"first_aid", &"Bed1"], [&"scrap_metal", &"Bed2"], [&"scrap_metal", &"Bed3"],
		[&"epipen", &"Shelf1"], [&"antidote", &"Shelf2"], [&"bear_spray", &"Shelf3"],
	]
	for spec: Array in stored:
		var item := ItemLibrary.create(spec[0])
		rv.stash.add_child(item)
		rv.storage[spec[1]].store(item)


## What a save keeps besides progress: the RV (its state and where it is), what's stowed in
## it, everything lying about the world (dropped, laid as planks, left in caves and at
## stations, fallen off the RV), and the player (where, health, hotbar).
func _save_extra() -> Dictionary:
	var stowed: Array = []
	for c: Node in rv.stash.get_children():
		var item := c as Item
		if item and ItemLibrary.DEFS.has(item.kind) and item.kind not in [&"rv_part", &"rv_wheel"]:
			stowed.append([item.kind, item.display_name(), _item_meta(item), item.transform])
	var hotbar: Array = []
	for item: Item in player.slots:
		if item and item.kind not in UNSAVED_KINDS:
			hotbar.append([item.kind, item.display_name(), _item_meta(item)])
	var lying: Array = []
	for n: Node in get_tree().get_nodes_in_group(&"items"):
		var item := n as Item
		if item == null or not is_ancestor_of(item) or item.kind in UNSAVED_KINDS or item.winch_of():
			continue
		if item.get_parent() == rv.stash or (item.holder == player):
			continue
		var xf := item.global_transform
		if item.holder: # Someone else's hands (online): it's left where they stand.
			xf = Transform3D(Basis.IDENTITY, item.holder.global_position + Vector3.UP * 0.3)
		elif xf.origin.y < world.height_at(xf.origin.x, xf.origin.z) - 2.0:
			continue # Fell through the world.
		lying.append([item.kind, item.display_name(), _item_meta(item), xf, item.is_placed(), item.freeze or item.holder != null])
	var me := {"health": player.health, "venom": player.venom, "inside": player.inside}
	me["at"] = player.local_position() if player.inside else player.global_position
	return {
		"rv": rv.slow_snapshot(), "rv_xf": rv.global_transform, "stowed": stowed, "hotbar": hotbar,
		"world": lying, "player": me, "door": rv.door_open,
	}


static func _item_meta(item: Item) -> Dictionary:
	var meta := {}
	for k: StringName in [&"fuel", &"puffs", &"cook", &"tire", &"slot", &"part", &"wheel"]:
		if item.has_meta(k):
			meta[String(k)] = item.get_meta(k)
	return meta


## Puts back what a save had: the RV's state, its stowed items, what lay about the world, and
## the player.
func _restore_extra(extra: Dictionary) -> void:
	if extra.has("rv"):
		rv.apply_slow_snapshot(extra["rv"])
	rv.door_open = bool(extra.get("door", rv.door_open))
	for e: Array in extra.get("stowed", []):
		var item := _saved_item(e)
		if item:
			rv.stash.add_child(item)
			item.stow(rv, e[3])
			if (e[2] as Dictionary).has("slot"):
				item.set_meta(&"slot", StringName(e[2]["slot"]))
	for e: Array in extra.get("world", []):
		var item := _saved_item(e)
		if item == null:
			continue
		items.add_child(item)
		if e[4]:
			item.place(items, e[3])
		else:
			item.global_transform = e[3]
			item.freeze = true # The ground may not be solid there yet.
			item.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			if not e[5]:
				_settling.append(item) # It was loose: let go once the ground's there.
		if item.kind == &"rv_part":
			var part: RVDamage.Part = rv.damage.parts.get(item.get_meta(&"part", &""))
			if part and not part.attached:
				part.debris = item
	var me: Dictionary = extra.get("player", {})
	if me.has("health"):
		player.health = float(me["health"])
		player.venom = float(me.get("venom", 0.0))
	if me.get("inside", false):
		player.board(me["at"])
	elif me.has("at") and (me["at"] as Vector3).distance_to(rv.global_position) < 200.0:
		var at: Vector3 = me["at"]
		at.y = maxf(at.y, world.height_at(at.x, at.z)) + 0.2
		player.global_position = at
		player.reset_physics_interpolation()
	for e: Array in extra.get("hotbar", []):
		var item := _saved_item(e)
		if item:
			items.add_child(item)
			item.global_position = player.global_position + Vector3.UP
			player.pick_up(item)


func _saved_item(e: Array) -> Item:
	var kind := StringName(e[0])
	var meta: Dictionary = e[2]
	var item: Item
	if kind == &"rv_part":
		var part: RVDamage.Part = rv.damage.parts.get(StringName(meta.get("part", "")))
		if part == null or part.attached:
			return null # Put back (or rebuilt) since.
		item = ItemLibrary.create_from_mesh(kind, part.node.mesh, e[1])
	elif kind == &"rv_wheel":
		var wheel := rv.wheels[clampi(int(meta.get("wheel", 0)), 0, 3)]
		item = ItemLibrary.create_from_mesh(kind, (wheel.visual as MeshInstance3D).mesh, e[1])
	elif ItemLibrary.DEFS.has(kind):
		item = ItemLibrary.create(kind)
	else:
		return null
	item.def["name"] = e[1]
	for k: Variant in meta:
		var v: Variant = meta[k]
		item.set_meta(StringName(k), StringName(v) if String(k) in ["part", "slot"] else v)
	if item.kind == &"patty":
		ItemLibrary.tint(item, ItemLibrary.patty_color(float(item.get_meta(&"cook", 0.0))))
	return item


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
			if not rv.is_automatic():
				rv.drivetrain.shift_to_neutral() # Left idling, not stalling against the brake.


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
	if not rv.is_simulated:
		return
	rv.freeze = not streamer.has_collision_at(xf.origin)
	rv.global_transform = xf
	rv.linear_velocity = Vector3.ZERO
	rv.angular_velocity = Vector3.ZERO
	rv.parking_brake = true
	rv.reset_physics_interpolation()
	camera.snap()
