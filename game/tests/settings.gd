extends Node
## Headless settings test: changes apply at once (interface scale, frame-rate cap, quality,
## resolution scale, field of view, look speed), are saved and read back, the settings screen
## sets them, and it opens from the pause menu (Esc closes it, not the pause menu) and the
## main menu.
##
##   godot --headless --path game --fixed-fps 60 res://tests/settings.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _failures: PackedStringArray = []
var _saved := ""


func _ready() -> void:
	_run()


func _run() -> void:
	if FileAccess.file_exists(Settings.PATH): # Put the player's own settings back after.
		_saved = FileAccess.get_file_as_string(Settings.PATH)
	Settings.reset()
	_check(get_tree().root.content_scale_factor == 1.0, "the interface starts at 100 %")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items", "the interface stretches with the window")

	Settings.set_value(&"ui_scale", 1.5)
	_check(is_equal_approx(get_tree().root.content_scale_factor, 1.5), "interface scale 150 % applies at once")
	Settings.set_value(&"max_fps", 90)
	_check(Engine.max_fps == 90, "the frame-rate cap applies (%d)" % Engine.max_fps)
	var cfg := ConfigFile.new()
	_check(cfg.load(Settings.PATH) == OK and is_equal_approx(float(cfg.get_value("display", "ui_scale", 0.0)), 1.5), "and they're saved")
	var fresh: Node = load("res://src/autoload/settings.gd").new()
	fresh._load()
	_check(is_equal_approx(fresh.ui_scale, 1.5) and fresh.max_fps == 90, "and read back next time")
	fresh.free()

	# The settings screen sets them.
	var menu := SettingsMenu.new()
	add_child(menu)
	await get_tree().process_frame
	_check(menu._ui.get_item_text(menu._ui.selected) == "150 %", "the screen shows the interface scale (%s)" % menu._ui.get_item_text(menu._ui.selected))
	menu._ui.item_selected.emit(Settings.UI_SCALES.find(1.25) if Settings.UI_SCALES.has(1.25) else 2)
	_check(Settings.ui_scale != 1.5, "picking another interface scale changes it (%.2f)" % Settings.ui_scale)
	menu._fps.item_selected.emit(Settings.FPS_LIMITS.find(0))
	_check(Engine.max_fps == 0, "unlimited frame rate")
	menu._invert.toggled.emit(true)
	_check(Settings.invert_y and Settings.look_y() < 0.0, "inverted look")
	menu._look.value = 2.0
	_check(is_equal_approx(Settings.look_speed(), 0.005), "look sensitivity 2× (%.4f rad/px)" % Settings.look_speed())
	_check(menu._captions.button_pressed and not menu._reduce.button_pressed, "captions start on, reduce motion off")
	menu._captions.toggled.emit(false)
	menu._reduce.toggled.emit(true)
	_check(not Settings.captions and Settings.reduce_motion, "the accessibility switches change the settings")
	var saved := ConfigFile.new()
	_check(saved.load(Settings.PATH) == OK and saved.get_value("accessibility", "captions") == false and saved.get_value("accessibility", "reduce_motion") == true, "and they're saved")
	Settings.reset()
	_check(Settings.captions and not Settings.reduce_motion, "reset puts them back")
	menu.queue_free()
	await get_tree().process_frame

	# In a trip: quality, resolution scale and field of view take effect straight away.
	Session.seed_code = Playground.DEFAULT_SEED
	var pg: Playground = PLAYGROUND.instantiate()
	pg.fresh_start = true
	pg.peaceful = true
	add_child(pg)
	var waited := 0
	while not pg.is_spawned and waited < HZ * 60 * 5: # (Frames run faster than the generator thread under load.)
		await get_tree().physics_frame
		waited += 1
	_check(pg.is_spawned, "a trip starts")
	_check(Graphics.current == Graphics.detect_default(), "Auto quality uses the detected preset (%s)" % Graphics.current)
	Settings.set_value(&"quality", &"low")
	_check(Graphics.current == &"low" and is_equal_approx(get_viewport().scaling_3d_scale, 0.67), "Low quality applies at once (3D at %d %%)" % roundi(get_viewport().scaling_3d_scale * 100.0))
	Settings.set_value(&"render_scale", 1.0)
	_check(is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "resolution scale 100 % overrides the preset's")
	Settings.set_value(&"fov", 90.0)
	_check(is_equal_approx(pg.player.camera.fov, 90.0) and is_equal_approx(pg.camera.fov, 90.0), "field of view 90°")
	pg.player._blow(pg.player.global_position + Vector3(0.0, 1.0, -2.0))
	_check(pg.player._shake > 0.0, "a hammer blow shakes the view")
	pg.player._shake = 0.0
	Settings.set_value(&"reduce_motion", true)
	pg.player._blow(pg.player.global_position + Vector3(0.0, 1.0, -2.0))
	_check(pg.player._shake == 0.0, "reduce motion: it doesn't")
	Settings.set_value(&"reduce_motion", false)

	# From the pause menu; Esc closes the settings, leaving the pause menu open.
	pg.menu.open()
	pg.menu.open_settings()
	await get_tree().process_frame
	var open := pg.menu.find_children("*", "SettingsMenu", true, false)
	_check(open.size() == 1, "the pause menu opens the settings")
	var esc := InputEventAction.new()
	esc.action = &"pause_menu"
	esc.pressed = true
	Input.parse_input_event(esc)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(pg.menu.find_children("*", "SettingsMenu", true, false).is_empty() and pg.menu.is_open(), "Esc closes them, back to the pause menu")
	pg.menu.close()
	pg.trip.clear_save()
	pg.queue_free()
	Session.seed_code = ""
	await get_tree().process_frame

	var main: MainMenu = load("res://src/ui/main_menu.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var button: Button = null
	for b: Node in main.find_children("*", "Button", true, false):
		if (b as Button).text == "Settings":
			button = b
	_check(button != null, "the main menu has a Settings button")
	if button:
		button.pressed.emit()
		await get_tree().process_frame
		_check(main.find_children("*", "SettingsMenu", true, false).size() == 1, "which opens them")
	main.queue_free()

	Settings.reset()
	if _saved != "":
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(_saved)
		f.close()
	else:
		DirAccess.remove_absolute(Settings.PATH)
	if _failures.is_empty():
		print("settings: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
