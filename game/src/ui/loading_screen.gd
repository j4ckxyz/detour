class_name LoadingScreen
extends CanvasLayer
## Shown while a trip loads: soft, blurred shots of the game drifting and fading into one
## another, what's happening in large type ("Generating a new map", "Loading your trip",
## "Joining ..."), the current step underneath, and a progress bar. `progress` and `stage`
## are set by whoever's loading; `finish()` fades it out and frees it.

const SHOTS_DIR := "res://assets/loading"
const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.7)
const ACCENT := Color(0.95, 0.62, 0.25)
## Seconds each shot shows for, and the crossfade between them.
const SHOT_SECONDS := 4.0
const FADE_SECONDS := 1.2
## The screen stays up at least this long, so it can be read (then fades out over FADE_OUT).
const MIN_SECONDS := 1.5
const FADE_OUT := 0.6

## 0..1.
var progress := 0.0
## What's happening now ("Surveying routes", "Building the terrain" ...).
var stage := ""

var _title := Label.new()
var _stage := Label.new()
var _detail := Label.new()
var _bar := ProgressBar.new()
var _shots: Array[Texture2D] = []
var _front := TextureRect.new()
var _back := TextureRect.new()
var _root := Control.new()
var _shot := 0
var _shot_time := 0.0
var _shown := 0.0
var _shown_progress := 0.0
var _finishing := false


## `title`: the big line; `detail`: a smaller one under it (the seed, say).
func _init(title: String = "Loading", detail: String = "") -> void:
	_title.text = title
	_detail.text = detail


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)
	for rect: TextureRect in [_back, _front]:
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		rect.resized.connect(func() -> void: rect.pivot_offset = rect.size * 0.5)
		_root.add_child(rect)
	# Darker towards the bottom, where the words are.
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.0, 0.0, 0.0, 0.15))
	gradient.set_color(1, Color(0.0, 0.0, 0.0, 0.75))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	shade.texture = tex
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_root.add_child(shade)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 64
	box.offset_right = -64
	box.offset_bottom = -56
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 8)
	_root.add_child(box)
	_style_label(_title, 40, TEXT)
	box.add_child(_title)
	_style_label(_stage, 18, DIM)
	box.add_child(_stage)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT
	bar_fill.set_corner_radius_all(4)
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.step = 0.0
	box.add_child(_bar)
	_style_label(_detail, 14, DIM)
	box.add_child(_detail)

	_load_shots()
	if not _shots.is_empty():
		_shot = int(Time.get_ticks_usec() % _shots.size())
		_front.texture = _shots[_shot]
		_back.texture = _shots[(_shot + 1) % _shots.size()]
		_back.modulate.a = 0.0


func _process(dt: float) -> void:
	_shown += dt
	_shown_progress = move_toward(_shown_progress, maxf(_shown_progress, progress), dt * 1.5)
	_bar.value = _shown_progress
	_stage.text = stage
	_animate_shots(dt)
	if _finishing and _shown >= MIN_SECONDS:
		_bar.value = 1.0
		_root.modulate.a = move_toward(_root.modulate.a, 0.0, dt / FADE_OUT)
		if _root.modulate.a <= 0.0:
			queue_free()


## Fades out (after it's been up for at least MIN_SECONDS) and frees itself.
func finish() -> void:
	progress = 1.0
	_finishing = true


func is_finishing() -> bool:
	return _finishing


func _animate_shots(dt: float) -> void:
	if _shots.size() < 2:
		return
	_shot_time += dt
	# A slow push-in on whichever shot is showing.
	var zoom := 1.04 + 0.04 * clampf(_shot_time / (SHOT_SECONDS + FADE_SECONDS), 0.0, 1.0)
	_front.scale = Vector2.ONE * zoom
	_back.scale = Vector2.ONE * 1.04
	if _shot_time > SHOT_SECONDS:
		var t := clampf((_shot_time - SHOT_SECONDS) / FADE_SECONDS, 0.0, 1.0)
		_back.modulate.a = t
		_front.modulate.a = 1.0 - t
		if t >= 1.0:
			_shot = (_shot + 1) % _shots.size()
			var swap := _front
			_front = _back
			_back = swap
			_back.texture = _shots[(_shot + 1) % _shots.size()]
			_back.modulate.a = 0.0
			_front.modulate.a = 1.0
			_shot_time = 0.0
			# Keep the one showing on top.
			_root.move_child(_front, _back.get_index() + 1)


func _load_shots() -> void:
	for file: String in ResourceLoader.list_directory(SHOTS_DIR):
		if file.ends_with(".jpg") or file.ends_with(".png"):
			var tex := load(SHOTS_DIR.path_join(file)) as Texture2D
			if tex:
				_shots.append(tex)


static func _style_label(l: Label, size: int, color: Color) -> void:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.5))
	l.add_theme_constant_override("outline_size", 4)
