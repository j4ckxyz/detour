extends Node
## Screenshot tour of a trip's places: the camp and the valley wall behind it, the road, the
## valley's walls, a washed-out gap, a gas station and home.
##
##   godot --path game res://src/debug/trip_tour.tscn -- --shots=/tmp/trip

const PLAYGROUND := preload("res://src/game/playground.tscn")

var _pg: Playground
var _dir := "user://trip_tour"
var _shot := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.trim_prefix("--shots=")
	DirAccess.make_dir_recursive_absolute(_dir)
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	add_child(_pg)
	_tour()


func _tour() -> void:
	while not _pg.is_spawned:
		await get_tree().process_frame
	var trip := _pg.trip
	var cam := _pg.camera
	_pg.player.take_wheel()
	await _seconds(3.0)
	cam.set_look(2.6, -0.2)
	await _seconds(0.5)
	await _snap("camp")
	cam.set_look(0.0, -0.12)
	cam.mode = RVCamera.Mode.COCKPIT
	await _seconds(0.5)
	await _snap("road_ahead")
	cam.mode = RVCamera.Mode.CHASE
	cam.set_look(PI, -0.05)
	await _seconds(0.8)
	await _snap("behind_the_camp")
	await _go(360.0)
	for side: float in [1.4, -1.4]:
		cam.set_look(side, 0.0)
		await _seconds(0.8)
		await _snap("valley_wall")
	for o: Dictionary in trip.data["obstacles"]:
		if int(o["kind"]) == 0:
			await _go(float(o["s"]) - 12.0)
			cam.set_look(0.3, -0.35)
			await _seconds(0.5)
			await _snap("washed_out_gap")
			break
	for o: Dictionary in trip.data["obstacles"]:
		if int(o["kind"]) == 1:
			await _go(float(o["s"]) - 12.0)
			cam.set_look(0.3, -0.25)
			await _seconds(0.5)
			await _snap("ledge")
			break
	for o: Dictionary in trip.data["obstacles"]:
		if int(o["kind"]) == 2:
			await _go(float(o["s"]) - 10.0)
			cam.set_look(0.2, -0.3)
			await _seconds(0.5)
			await _snap("mud")
			break
	await _go(float(trip.pad(1)["s"]) - 18.0)
	cam.set_look(-0.9 * float(trip.pad(1)["side"]), -0.15)
	await _seconds(0.8)
	await _snap("gas_station")
	await _go(float(trip.pad(-1)["s"]) - 20.0)
	cam.set_look(-0.8 * float(trip.pad(-1)["side"]), -0.1)
	await _seconds(0.8)
	await _snap("home")
	print("TOUR done: %d shots in %s" % [_shot, ProjectSettings.globalize_path(_dir)])
	get_tree().quit()


func _go(s: float) -> void:
	_pg._place_rv(_pg.trip.road_transform(s))
	_pg.camera.snap()
	var waited := 0
	while _pg.is_rv_waiting() and waited < 600:
		await get_tree().physics_frame
		waited += 1
	await _seconds(2.5) # Let the view stream in.


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path := _dir.path_join("%02d_%s.png" % [_shot, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)
