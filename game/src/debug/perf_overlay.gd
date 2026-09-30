class_name PerfOverlay
extends CanvasLayer
## Frame timing and streaming stats. F3 toggles.

var streamer: TerrainStreamer
var extra_lines: Callable # Optional `func() -> String` appended to the overlay.

var _label := Label.new()
var _timer := 0.0


func _ready() -> void:
	layer = 100
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.72)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(12, 12)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
	panel.add_child(_label)
	add_child(panel)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible


func gpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not visible:
		return
	_timer = 0.25
	var vp := get_viewport()
	var size := Vector2(vp.size) # Pixels (the visible rect is in UI units).
	var lines: PackedStringArray = [
		"%d fps   cpu %.2f ms   gpu %s" % [
			Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			# The Metal driver doesn't report GPU timestamps (always 0).
			"%.2f ms" % gpu_ms() if gpu_ms() > 0.0 else "n/a",
		],
		"%s / %s  —  %s" % [
			Graphics.renderer(), Graphics.driver(), RenderingServer.get_video_adapter_name(),
		],
		"preset %s   3D %.0f%% of %dx%d   scaling %s" % [
			Graphics.current, vp.scaling_3d_scale * 100.0, size.x, size.y, _scaling_name(vp.scaling_3d_mode),
		],
		"draws %d   prims %.2fM   vram %.0f MB" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1.0e6,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		],
	]
	if streamer:
		lines.append("chunks %d (+%d pending, %d threads)   trees %d" % [
			streamer.chunks_loaded, streamer.pending(), streamer.worker_count(), streamer.trees_loaded,
		])
		lines.append("chunk gen %.2f ms   upload %.2f ms (max %.2f)" % [
			streamer.avg_gen_usec / 1000.0, streamer.last_upload_usec / 1000.0, streamer.max_upload_usec / 1000.0,
		])
	if extra_lines.is_valid():
		lines.append(extra_lines.call())
	_label.text = "\n".join(lines)


func _scaling_name(mode: Viewport.Scaling3DMode) -> String:
	match mode:
		Viewport.SCALING_3D_MODE_METALFX_TEMPORAL:
			return "MetalFX temporal"
		Viewport.SCALING_3D_MODE_METALFX_SPATIAL:
			return "MetalFX spatial"
		Viewport.SCALING_3D_MODE_FSR2:
			return "FSR2"
		Viewport.SCALING_3D_MODE_FSR:
			return "FSR1"
		_:
			return "bilinear"
