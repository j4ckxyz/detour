extends Node3D
## Phase 0 terrain/renderer benchmark and dev playground.
##
## User arguments (after `--`):
##   --seed=CODE          world seed code (default: a fixed code so runs are comparable)
##   --preset=NAME        potato | low | medium | high (default: detected)
##   --bench[=SECONDS]    drive a fixed route at RV speed, print a BENCH json line, quit
##   --screenshot=PATH    save a PNG once the view has streamed in, then quit
##
## Engine arguments worth combining: `--rendering-method forward_plus|mobile|gl_compatibility`,
## `--resolution 1920x1080`.
## Keys: F3 overlay, 1-4 presets, right mouse + WASD/QE fly, Shift fast.

const DEFAULT_SEED := "DT5-00000-000ZG" # A short trip: woods, mud, gaps and a bridge with a hole; canyon: a climb, a ledge, a ford; the pass: ice, beams and a hill.
const START := Vector3(64.0, 0.0, 64.0)
const DRIVER_EYE_HEIGHT := 2.6
const BENCH_SPEED := 22.0 # m/s, about 80 km/h: a fast RV.
const BENCH_WARMUP := 2.0
const PRESET_KEYS: Dictionary[Key, StringName] = {
	KEY_1: &"potato", KEY_2: &"low", KEY_3: &"medium", KEY_4: &"high",
}

var _args: Dictionary[String, String] = {}
var _world := WorldGen.new()
var _lighting := WorldLighting.new()
var _camera := FreeFlyCamera.new()
var _streamer := TerrainStreamer.new()
var _overlay := PerfOverlay.new()

var _bench_seconds := 0.0
var _bench_elapsed := -1.0 # < 0: not running.
var _frame_ms: PackedFloat32Array = []
var _gpu_ms: PackedFloat32Array = []
var _draws: PackedFloat32Array = []
var _upload_ms: PackedFloat32Array = []
var _refresh_ms: PackedFloat32Array = []
var _last_tick := 0
var _screenshot_countdown := -1


func _ready() -> void:
	_parse_args()
	var code: String = _args.get("seed", DEFAULT_SEED)
	if not _world.load(code):
		get_tree().quit(2)
		return

	add_child(_lighting)
	_camera.fov = 72.0
	_camera.near = 0.1
	_camera.ground_height = _world.height_at
	add_child(_camera)
	_camera.position = START + Vector3.UP * (_world.height_at(START.x, START.z) + 30.0)
	_camera.look(-0.7, -0.25)

	_streamer.focus = _camera
	add_child(_streamer)
	if not _streamer.start(_world.get_code()):
		get_tree().quit(2)
		return
	_streamer.area_ready.connect(_on_area_ready)

	_overlay.streamer = _streamer
	_overlay.extra_lines = func() -> String: return "seed %s" % _world.get_code()
	add_child(_overlay)

	var preset := StringName(_args.get("preset", String(Graphics.detect_default())))
	_apply_preset(preset)

	if _args.has("bench"):
		_bench_seconds = float(_args["bench"]) if _args["bench"] != "" else 20.0
		_camera.look(-PI / 2.0, -0.06) # Face +X, the direction of travel.
		_camera.position.y = _world.height_at(START.x, START.z) + DRIVER_EYE_HEIGHT
		_camera.set_process(false)
		_camera.set_process_unhandled_input(false)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		print("BENCH waiting for terrain…")


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.substr(2).split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _apply_preset(preset: StringName) -> void:
	_lighting.apply_preset(preset, get_viewport(), _streamer, _camera)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and PRESET_KEYS.has(key.physical_keycode):
		_apply_preset(PRESET_KEYS[key.physical_keycode])


func _on_area_ready() -> void:
	if _args.has("screenshot"):
		_screenshot_countdown = 30 # Let temporal upscalers converge.
	if _bench_seconds > 0.0 and _bench_elapsed < 0.0:
		print("BENCH terrain ready, driving for %.0f s" % _bench_seconds)
		_bench_elapsed = 0.0
		_last_tick = Time.get_ticks_usec()


func _process(delta: float) -> void:
	if _screenshot_countdown > 0:
		_screenshot_countdown -= 1
		if _screenshot_countdown == 0:
			var path: String = _args["screenshot"]
			var err := get_viewport().get_texture().get_image().save_png(path)
			print("SCREENSHOT %s (%s)" % [path, error_string(err)])
			get_tree().quit(0 if err == OK else 1)
	if _bench_elapsed >= 0.0:
		_bench_step(delta)


func _bench_step(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var frame_ms := (now - _last_tick) / 1000.0
	_last_tick = now
	_bench_elapsed += delta

	var p := _camera.position
	p.x += BENCH_SPEED * delta
	var target_y := _world.height_at(p.x, p.z) + DRIVER_EYE_HEIGHT
	p.y = lerpf(p.y, target_y, minf(1.0, delta * 8.0))
	_camera.position = p

	if _bench_elapsed > BENCH_WARMUP:
		_frame_ms.append(frame_ms)
		_gpu_ms.append(_overlay.gpu_ms())
		_draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_upload_ms.append(_streamer.last_upload_usec / 1000.0)
		_refresh_ms.append(_streamer.last_refresh_usec / 1000.0)
	if _bench_elapsed >= _bench_seconds + BENCH_WARMUP:
		_finish_bench()


func _finish_bench() -> void:
	var frames := _frame_ms.duplicate()
	frames.sort()
	var gpu := _gpu_ms.duplicate()
	gpu.sort()
	var total := 0.0
	for ms: float in _frame_ms:
		total += ms
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var result := {
		"renderer": Graphics.renderer(),
		"driver": Graphics.driver(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"preset": String(Graphics.current),
		"resolution": "%dx%d" % [size.x, size.y],
		"render_scale": vp.scaling_3d_scale,
		"seconds": _bench_seconds,
		"frames": frames.size(),
		"avg_fps": snappedf(1000.0 * frames.size() / total, 0.1),
		"p50_ms": snappedf(_pct(frames, 0.50), 0.01),
		"p95_ms": snappedf(_pct(frames, 0.95), 0.01),
		"p99_ms": snappedf(_pct(frames, 0.99), 0.01),
		"max_ms": snappedf(frames[-1], 0.01),
		"gpu_p50_ms": snappedf(_pct(gpu, 0.50), 0.01),
		"gpu_p95_ms": snappedf(_pct(gpu, 0.95), 0.01),
		"draws_avg": roundi(_mean(_draws)),
		"chunk_gen_ms": snappedf(_streamer.avg_gen_usec / 1000.0, 0.01),
		"max_upload_ms": snappedf(_streamer.max_upload_usec / 1000.0, 0.01),
		"max_upload_parts_ms": [
			snappedf(_streamer.max_mesh_usec / 1000.0, 0.01),
			snappedf(_streamer.max_decor_usec / 1000.0, 0.01),
			snappedf(_streamer.max_body_usec / 1000.0, 0.01),
		],
		"chunks": _streamer.chunks_loaded,
		"trees": _streamer.trees_loaded,
		"props": _streamer.props_loaded,
		"vram_mb": roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
	}
	result["hitches"] = _hitches(_pct(frames, 0.50))
	var line := JSON.stringify(result)
	print("BENCH ", line)
	var file := FileAccess.open("user://bench.json", FileAccess.WRITE)
	if file:
		file.store_line(line)
	get_tree().quit()


## The five worst frames slower than 1.5x the median, with the streaming work inside them.
## This node processes before its streamer child, so the streamer stats sampled at index i
## come from the interval that `_frame_ms[i]` measures.
func _hitches(median_ms: float) -> Array[String]:
	var idx: Array[int] = []
	for i: int in _frame_ms.size():
		if _frame_ms[i] > median_ms * 1.5:
			idx.append(i)
	idx.sort_custom(func(a: int, b: int) -> bool: return _frame_ms[a] > _frame_ms[b])
	var out: Array[String] = []
	for i: int in idx.slice(0, 5):
		out.append("%.1fms (upload %.1f, refresh %.1f)" % [_frame_ms[i], _upload_ms[i], _refresh_ms[i]])
	out.append("%d/%d frames over 1.5x median" % [idx.size(), _frame_ms.size()])
	return out


func _pct(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(sorted.size() - 1, int(q * sorted.size()))]


func _mean(values: PackedFloat32Array) -> float:
	var total := 0.0
	for v: float in values:
		total += v
	return total / maxf(1.0, values.size())
