extends Node
## Screenshot tour of a trip's places: the camp, two people by the RV, the valley wall behind
## the camp, the road, the valley's walls, the first of each kind of obstacle, the places off
## the road, a gas station and home. (It uses
## the chase camera, which only these debug tours can.)
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
	# The loading screen, while the map generates and the ground streams in.
	await get_tree().process_frame
	await _snap("loading")
	var t := 0.0
	while is_instance_valid(_pg.loading) and t < 1.2:
		await get_tree().process_frame
		t += get_process_delta_time()
	if is_instance_valid(_pg.loading):
		await _snap("loading")
	while not _pg.is_spawned or is_instance_valid(_pg.loading):
		await get_tree().process_frame
	var trip := _pg.trip
	var cam := _pg.camera
	_pg.player.take_wheel()
	cam.mode = RVCamera.Mode.CHASE # Debug only: players are always in first person.
	await _seconds(3.0)
	cam.set_look(2.6, -0.2)
	await _seconds(0.5)
	await _snap("camp")
	# Two people by the RV's door, as others see them.
	var people: Array[Node3D] = []
	for i: int in 2:
		var body := PillAvatar.build(Session.COLORS[i + 1], "Player %d" % (i + 2))
		_pg.add_child(body)
		var at := _pg.by_the_door() + _pg.rv.global_basis.z * (1.2 * i - 0.6)
		body.global_transform = Transform3D(Basis.looking_at(_pg.rv.global_basis.x, Vector3.UP).rotated(Vector3.UP, 0.4 - 0.8 * i), at)
		people.append(body)
	cam.set_look(1.9, -0.05)
	await _seconds(0.6)
	await _snap("people")
	for body: Node3D in people:
		body.queue_free()
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
	# The first of each kind of obstacle, from a little way back.
	var shots := {0: "washed_out_gap", 1: "ledge", 2: "mud", 6: "bridge", 7: "beams", 8: "jump", 9: "hill"}
	for kind: int in shots:
		for o: Dictionary in trip.data["obstacles"]:
			if int(o["kind"]) != kind:
				continue
			var back := float(o["length"]) * 0.5 + (16.0 if kind in [6, 7] else 12.0)
			if kind == 9:
				back = 30.0
			await _go(float(o["s"]) - back)
			cam.set_look(0.35 if kind != 9 else 0.0, -0.3 if kind != 9 else -0.05)
			await _seconds(0.5)
			await _snap(shots[kind])
			if kind in [0, 6, 7, 8]: # And from the side, up close.
				var pos: Vector3 = o["pos"]
				var dir: Vector3 = o["dir"]
				var right := dir.cross(Vector3.UP).normalized()
				await _look_from(pos + right * 12.0 - dir * 6.0 + Vector3.UP * 5.0, pos + Vector3.DOWN * 1.5, shots[kind] + "_side")
			if kind == 9 and not (trip.data["spurs"] as Array).is_empty():
				cam.set_look(0.9, -0.1)
				await _seconds(0.5)
				await _snap("hill_side_track")
			break
	# Places off the road, from the road.
	var seen := {}
	for p: Dictionary in trip.data.get("pois", []):
		if seen.has(int(p["kind"])):
			continue
		seen[int(p["kind"])] = true
		var at: Vector3 = p["pos"]
		await _go(_nearest_s(at) - 10.0)
		var road := _pg.rv.global_position
		var eye := road + (at - road) * 0.35 + Vector3.UP * 6.0
		at.y = _pg.world.height_at(at.x, at.z) + 2.0
		await _look_from(eye, at, ["cabin", "tower", "wreck", "lookout"][int(p["kind"])])
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


## A shot from a free camera at `eye` looking at `target`.
func _look_from(eye: Vector3, target: Vector3, label: String) -> void:
	var free := Camera3D.new()
	free.fov = 70.0
	free.far = 2000.0
	add_child(free)
	free.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	free.current = true
	await _seconds(0.6)
	await _snap(label)
	free.queue_free()
	_pg.camera.current = true


func _nearest_s(at: Vector3) -> float:
	var pts: PackedVector3Array = _pg.trip.data["points"]
	var best := 0
	for i: int in pts.size():
		if Vector2(pts[i].x - at.x, pts[i].z - at.z).length() < Vector2(pts[best].x - at.x, pts[best].z - at.z).length():
			best = i
	return best * 8.0


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var path := _dir.path_join("%02d_%s.png" % [_shot, label])
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT %s" % path)
