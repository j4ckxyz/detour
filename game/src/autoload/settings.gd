extends Node
## The player's settings: display, graphics, controls (and sound volumes, see Audio). Kept in
## `user://options.cfg`, applied at startup and whenever they change (SettingsMenu).
##
## The interface is laid out for 1600x900 and stretches with the window (project setting
## stretch mode `canvas_items`), so it's the same size on screen at any resolution or pixel
## density; `ui_scale` makes it bigger or smaller on top of that. The 3D view always renders
## at the window's own resolution (times the quality preset's render scale).

signal changed

const PATH := "user://options.cfg"
const UI_SCALES: Array[float] = [0.75, 0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3200, 1800), Vector2i(3840, 2160),
]
## Frame-rate caps; 0 is none.
const FPS_LIMITS: Array[int] = [30, 60, 90, 120, 144, 165, 240, 0]
## Render scales on offer; 0 is the quality preset's own.
const RENDER_SCALES: Array[float] = [0.0, 0.5, 0.67, 0.77, 0.87, 1.0]
const QUALITIES: Array[StringName] = [&"auto", &"potato", &"low", &"medium", &"high"]
const FOV_RANGE := Vector2(60.0, 100.0)
const SENSITIVITY_RANGE := Vector2(0.25, 3.0)

enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE }

var ui_scale := 1.0
var window_mode := WindowMode.WINDOWED
## The windowed size picked in the menu; (0, 0) leaves the window as it opens.
var window_size := Vector2i.ZERO
var vsync := true
var max_fps := 0
var quality: StringName = &"auto"
var render_scale := 0.0
var fov := 75.0
## Multiplies mouse (and right-stick) look speed.
var look_sensitivity := 1.0
var invert_y := false
## 0..1 per bus: "Master", "Effects", "Ambience", "Music".
var volumes: Dictionary[String, float] = {"Master": 0.8, "Effects": 1.0, "Ambience": 1.0, "Music": 1.0}

## What the window was last set to from here: it's only changed again when these settings
## change (not when anything else does), so a window dragged to another size stays put.
var _applied_mode := -1
var _applied_size := Vector2i.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	apply()


## The graphics preset to use: the chosen one, or the one detected for this machine.
func preset() -> StringName:
	return Graphics.detect_default() if quality == &"auto" else quality


## Mouse look radians per pixel.
func look_speed() -> float:
	return 0.0025 * look_sensitivity


## -1 when looking up and down is inverted.
func look_y() -> float:
	return -1.0 if invert_y else 1.0


## Applies everything (the window, frame pacing, UI scale, volumes), tells everyone else
## (`changed`: the game re-applies the graphics preset and camera), and saves.
func apply() -> void:
	get_tree().root.content_scale_factor = ui_scale
	Engine.max_fps = max_fps
	for bus: String in volumes:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volumes[bus], 0.0001)))
			AudioServer.set_bus_mute(i, volumes[bus] <= 0.001)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
		_apply_window()
	changed.emit()


## Changes one setting (by property name), applies and saves.
func set_value(key: StringName, value: Variant) -> void:
	set(key, value)
	apply()
	save()


func reset() -> void:
	ui_scale = 1.0
	window_mode = WindowMode.WINDOWED
	vsync = true
	max_fps = 0
	quality = &"auto"
	render_scale = 0.0
	fov = 75.0
	look_sensitivity = 1.0
	invert_y = false
	volumes = {"Master": 0.8, "Effects": 1.0, "Ambience": 1.0, "Music": 1.0}
	apply()
	save()


## Window sizes that fit on this screen (the current one always included).
func window_sizes() -> Array[Vector2i]:
	var room := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen()).size
	var sizes: Array[Vector2i] = []
	for s: Vector2i in WINDOW_SIZES:
		if s.x <= room.x and s.y <= room.y:
			sizes.append(s)
	var now := DisplayServer.window_get_size()
	if window_mode == WindowMode.WINDOWED and not sizes.has(now) and now.x > 0:
		sizes.append(now)
		sizes.sort()
	return sizes


func _apply_window() -> void:
	if window_mode == _applied_mode and window_size == _applied_size:
		return
	var want: DisplayServer.WindowMode = [
		DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	][window_mode]
	if window_mode != _applied_mode and DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	if want == DisplayServer.WINDOW_MODE_WINDOWED and window_size != Vector2i.ZERO and window_size != _applied_size:
		var room := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		var size := window_size.min(room.size)
		DisplayServer.window_set_size(size)
		DisplayServer.window_set_position(room.position + (room.size - size) / 2)
	_applied_mode = window_mode
	_applied_size = window_size


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	ui_scale = clampf(float(cfg.get_value("display", "ui_scale", ui_scale)), UI_SCALES[0], UI_SCALES[-1])
	window_mode = clampi(int(cfg.get_value("display", "window_mode", window_mode)), 0, WindowMode.size() - 1) as WindowMode
	window_size = cfg.get_value("display", "window_size", window_size)
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	max_fps = maxi(0, int(cfg.get_value("display", "max_fps", max_fps)))
	var q := StringName(cfg.get_value("graphics", "quality", quality))
	quality = q if q in QUALITIES else &"auto"
	render_scale = clampf(float(cfg.get_value("graphics", "render_scale", render_scale)), 0.0, 1.0)
	fov = clampf(float(cfg.get_value("graphics", "fov", fov)), FOV_RANGE.x, FOV_RANGE.y)
	look_sensitivity = clampf(float(cfg.get_value("controls", "look_sensitivity", look_sensitivity)), SENSITIVITY_RANGE.x, SENSITIVITY_RANGE.y)
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	for bus: String in volumes:
		volumes[bus] = clampf(float(cfg.get_value("sound", bus.to_lower(), volumes[bus])), 0.0, 1.0)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "ui_scale", ui_scale)
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "window_size", window_size)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "max_fps", max_fps)
	cfg.set_value("graphics", "quality", String(quality))
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "fov", fov)
	cfg.set_value("controls", "look_sensitivity", look_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	for bus: String in volumes:
		cfg.set_value("sound", bus.to_lower(), volumes[bus])
	cfg.save(PATH)
