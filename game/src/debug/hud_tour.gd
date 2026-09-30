extends Node
## Screenshots of the HUD in play: the status panel (you and the RV) with everything fine and
## then knocked about, a hammer mid-swing at a dent, and the RV pulled into a station's
## forecourt between the pumps.
##
##   godot --path game res://src/debug/hud_tour.tscn -- --shots=/tmp/hud

const PLAYGROUND := preload("res://src/game/playground.tscn")

var _pg: Playground
var _dir := "user://hud_tour"
var _shot := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_dir)
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	_tour()


func _tour() -> void:
	while not _pg.is_spawned or is_instance_valid(_pg.loading):
		await get_tree().process_frame
	var player := _pg.player
	var rv := _pg.rv
	await _seconds(2.0)
	_face(player, rv.global_position + Vector3.UP * 1.2)
	await _seconds(0.6)
	await _snap("status_fine")
	var d := rv.damage
	d.frame = 38.0
	d.engine = 71.0
	d.oil = 0.18
	d.fuel = 22.0
	d.tires[1] = 30.0
	d.bolts[2] = 2
	var dented: StringName = d.parts.keys()[0]
	for id: StringName in d.parts.keys().slice(0, 5):
		d.parts[id].hp = 25.0
	player.hurt(38.0, "testing")
	player.poison()
	await _seconds(0.5)
	await _snap("status_knocked_about")
	var hammer := ItemLibrary.create(&"hammer")
	_pg.items.add_child(hammer)
	player.pick_up(hammer)
	var at := rv.global_transform * (d.parts[dented] as RVDamage.Part).centre
	player.global_position = at + (player.global_position - at).normalized() * 1.6
	player.global_position.y = _pg.world.height_at(player.global_position.x, player.global_position.z) + 0.1
	_face(player, at)
	await _seconds(0.5)
	var aim := player.aim_rv()
	if not aim.is_empty(): # Where the crosshair meets the panel, as the hammer does.
		at = ItemLibrary.struck_at(player, float(aim["distance"]))
	player.swing(at, 3)
	await _seconds(0.12)
	await _snap("hammer_raised")
	await player.struck
	await get_tree().process_frame
	await _snap("hammer_blow")
	await _seconds(1.5)
	# The RV in the forecourt, between the pumps.
	var station: Dictionary = _pg.trip.pad(1)
	_pg._place_rv(_pg.trip.road_transform(float(station["s"])))
	while _pg.is_rv_waiting():
		await get_tree().physics_frame
	var pump: Node3D = null
	for n: Node in get_tree().get_nodes_in_group(&"fuel_pumps"):
		if pump == null or (n as Node3D).global_position.distance_to(rv.global_position) < pump.global_position.distance_to(rv.global_position):
			pump = n
	var st := (pump.get_parent() as Node3D).global_transform
	var facing := st.basis.z
	facing.y = 0.0
	var lane := st * Vector3(0.0, 0.0, -1.0)
	lane.y = _pg.world.height_at(lane.x, lane.z) + 0.5
	_pg._place_rv(Transform3D(Basis.looking_at(facing.normalized(), Vector3.UP), lane))
	player.global_position = lane + st.basis.x.normalized() * 6.5 - st.basis.z.normalized() * 7.0
	player.global_position.y = _pg.world.height_at(player.global_position.x, player.global_position.z) + 0.2
	await _seconds(2.0)
	_face(player, lane + Vector3.UP * 0.8)
	await _seconds(0.6)
	await _snap("forecourt")
	print("TOUR done: %d shots in %s" % [_shot, ProjectSettings.globalize_path(_dir)])
	get_tree().quit()


func _face(player: Player, target: Vector3) -> void:
	var to := target - player.camera.global_position
	player.look(atan2(-to.x, -to.z), atan2(to.y, Vector2(to.x, to.z).length()))


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path := _dir.path_join("%02d_%s.png" % [_shot, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
