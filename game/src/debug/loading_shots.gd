extends Node
## Takes the loading screen's backdrops: a few scenic views along the default trip with the
## UI hidden, softened (scaled right down and back up) and saved as JPEGs.
##
##   godot --path game res://src/debug/loading_shots.tscn -- --out=res://assets/loading

const PLAYGROUND := preload("res://src/game/playground.tscn")

var _pg: Playground
var _out := "res://assets/loading"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	_run()


func _run() -> void:
	while not _pg.is_spawned or is_instance_valid(_pg.loading):
		await get_tree().process_frame
	var trip := _pg.trip
	var n := 0
	# (road distance, view offset right / up / back from the road, look-at offset ahead)
	var views: Array = []
	views.append([60.0, Vector3(-9.0, 3.0, 14.0), 10.0])
	for o: Dictionary in trip.data["obstacles"]:
		if int(o["kind"]) in [Trip.BRIDGE, Trip.BEAMS, Trip.HILL]:
			views.append([float(o["s"]) - float(o["length"]) * 0.5 - 6.0, Vector3(4.0, 9.0, 16.0), 8.0])
	for p: Dictionary in trip.data.get("pois", []):
		views.append([_nearest_s(p["pos"]), p["pos"], -1.0])
	views.append([float(trip.pad(1)["s"]) - 20.0, Vector3(-6.0, 4.0, 10.0), 26.0])
	for v: Array in views.slice(0, 9):
		_pg._place_rv(trip.road_transform(float(v[0]) - 12.0))
		var wait := 0
		while _pg.is_rv_waiting() and wait < 600:
			await get_tree().physics_frame
			wait += 1
		var road := trip.road_transform(float(v[0]))
		var eye: Vector3
		var target: Vector3
		if float(v[2]) < 0.0: # A place: from partway there, looking at it.
			target = v[1]
			target.y = _pg.world.height_at(target.x, target.z) + 3.0
			eye = road.origin.lerp(target, 0.3) + Vector3.UP * 5.0
		else:
			eye = road * (v[1] as Vector3)
			eye.y = maxf(eye.y, _pg.world.height_at(eye.x, eye.z) + 2.0)
			target = (road * Vector3(0.0, 0.0, -float(v[2]))) + Vector3.UP * 1.0
		var cam := Camera3D.new()
		cam.fov = 65.0
		cam.far = 2500.0
		add_child(cam)
		cam.global_transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
		cam.current = true
		for c: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			(c as CanvasLayer).visible = false
		for c: Node in get_tree().root.find_children("*", "Control", true, false):
			(c as Control).visible = false
		await get_tree().create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		var img := _soften(get_viewport().get_texture().get_image())
		n += 1
		var path := ProjectSettings.globalize_path(_out.path_join("shot_%02d.jpg" % n))
		img.save_jpg(path, 0.82)
		print("SHOT ", path)
		cam.queue_free()
		_pg.camera.current = true
	print("LOADING SHOTS done: %d" % n)
	get_tree().quit()


## A soft blur: down to 240 × 135, three box-blur passes, then back up in steps.
static func _soften(img: Image) -> Image:
	img.convert(Image.FORMAT_RGB8)
	img.resize(240, 135, Image.INTERPOLATE_LANCZOS)
	for pass_i: int in 3:
		var src := img.duplicate() as Image
		for y: int in 135:
			for x: int in 240:
				var sum := Color(0, 0, 0)
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						sum += src.get_pixel(clampi(x + dx, 0, 239), clampi(y + dy, 0, 134))
				img.set_pixel(x, y, sum / 9.0)
	img.resize(480, 270, Image.INTERPOLATE_BILINEAR)
	img.resize(960, 540, Image.INTERPOLATE_BILINEAR)
	return img


func _nearest_s(at: Vector3) -> float:
	var pts: PackedVector3Array = _pg.trip.data["points"]
	var best := 0
	for i: int in pts.size():
		if Vector2(pts[i].x - at.x, pts[i].z - at.z).length() < Vector2(pts[best].x - at.x, pts[best].z - at.z).length():
			best = i
	return best * 8.0
