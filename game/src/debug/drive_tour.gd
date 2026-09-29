extends Node
## Scripted drive through the playground that saves screenshots along the way: a quick
## visual check of the RV, cameras, HUD and scattered props.
##
##   godot --path game res://src/debug/drive_tour.tscn -- --shots=/tmp/tour
##
## Arguments (after `--`): --shots=DIR (default user://tour), plus the playground's own.

const PLAYGROUND := preload("res://src/game/playground.tscn")

var _pg: Playground
var _dir := "user://tour"
var _shot := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Keeps touring while the pause menu is open.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_dir)
	_pg = PLAYGROUND.instantiate()
	add_child(_pg)
	_tour()


func _tour() -> void:
	while not _pg.is_spawned:
		await get_tree().process_frame
	var rv := _pg.rv
	var cam := _pg.camera
	var player := _pg.player
	await _seconds(2.5)
	await _snap("on_foot")
	# Hook the front winch onto the nearest rock or tree ahead, and hold a plank.
	var anchor: Variant = _anchor_ahead(rv)
	if anchor != null:
		rv.winches[0].rope_length = 1.0
		rv.winches[0].anchor(anchor)
		rv.winches[0].rope_length += 1.5 # A little slack so it sags.
	var plank := ItemLibrary.create(&"plank")
	_pg.items.add_child(plank)
	player.pick_up(plank)
	player.look(player._yaw + 0.9, -0.55)
	await _seconds(0.4)
	await _snap("plank_ghost")
	cam.current = true
	cam.set_look(0.5, -0.35)
	await _seconds(0.6)
	await _snap("winch_rope")
	player.camera.current = true
	player.drop_held()
	rv.door_open = true
	await _seconds(1.2)
	await _snap("door_open")
	player.board(rv.to_local(player.global_position))
	player.look(0.4, -0.15) # Looking forward towards the cab and dinette.
	await _seconds(0.5)
	await _snap("inside")
	for n: Node in rv.stash.get_children():
		if n is Item and (n as Item).kind == &"burger":
			player.pick_up(n)
			break
	player.look(PI, -0.2) # Back towards the kitchen and bed.
	await _seconds(0.5)
	await _snap("inside_holding")
	player.take_wheel()
	cam.mode = RVCamera.Mode.CHASE # Debug only: players are always in first person.
	_pg.driver.enabled = false
	await _seconds(2.5) # Let the view stream in and the RV settle.
	await _snap("parked_chase")
	cam.set_look(2.4, -0.25)
	await _seconds(0.3)
	await _snap("parked_front")
	cam.set_look(-1.2, -0.35)
	await _seconds(0.3)
	await _snap("parked_side")
	cam.set_look(0.0, -0.12)

	rv.set_automatic(true)
	rv.throttle = 0.55
	for i: int in 60 * 6:
		rv.steer_input = sin(i / 60.0 * 0.8) * 0.5
		await get_tree().physics_frame
	await _snap("driving_chase")
	cam.mode = RVCamera.Mode.COCKPIT
	cam.set_look(0.0, -0.08)
	await _seconds(2.0)
	await _snap("driving_cab")
	cam.set_look(0.7, -0.2)
	await _seconds(0.3)
	await _snap("cab_interior")
	cam.mode = RVCamera.Mode.CHASE
	cam.set_look(0.0, -0.12)

	rv.throttle = 0.0
	rv.brake = 1.0
	await _seconds(3.0)
	rv.brake = 0.0
	rv.set_automatic(false)
	rv.clutch_input = 1.0 # Shows the H-pattern on the HUD.
	await _seconds(0.5)
	# Out of whatever the automatic left it in, across the neutral lane and down into 2nd.
	rv.drag_gear_stick(Vector2(0.0, -rv.gear_stick.position.y))
	rv.drag_gear_stick(Vector2(-2.0, 0.0))
	rv.drag_gear_stick(Vector2(0.0, -1.0))
	rv.headlights = true
	await _seconds(0.3)
	await _snap("clutch_gate_lights")
	_pg.menu.open()
	await _seconds(0.3)
	await _snap("pause_menu")
	print("TOUR done: %d shots in %s" % [_shot, ProjectSettings.globalize_path(_dir)])
	get_tree().quit()


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path := _dir.path_join("%02d_%s.png" % [_shot, label])
	var err := get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s (%s)" % [path, error_string(err)])


func _anchor_ahead(rv: RV) -> Variant:
	var sphere := SphereShape3D.new()
	sphere.radius = 30.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.collision_mask = TerrainStreamer.WORLD_LAYER
	q.transform = Transform3D(Basis.IDENTITY, rv.global_position)
	var best: Variant = null
	var best_d := INF
	for hit: Dictionary in rv.get_world_3d().direct_space_state.intersect_shape(q, 256):
		var body := hit["collider"] as StaticBody3D
		if body == null or int(hit["shape"]) == TerrainStreamer.GROUND_SHAPE:
			continue
		var p := body.to_global(body.shape_owner_get_transform(body.shape_find_owner(int(hit["shape"]))).origin)
		var d := p.distance_to(rv.global_position)
		if rv.to_local(p).z < -6.0 and d < best_d:
			best = p + Vector3.UP * 0.5
			best_d = d
	return best
