extends Node
## Screenshots of the interface at the window's full resolution: the main menu, the settings
## screen, and a trip's HUD with the pause menu, at interface scale 100 % and 150 %. Pass
## `--size=WxH` for the window size (clamped to the screen).
##
##   godot --path game res://src/debug/ui_shots.tscn -- --shots=/tmp/ui --size=3840x2160

const PLAYGROUND := preload("res://src/game/playground.tscn")

var _dir := "user://ui_shots"
var _shot := 0


func _ready() -> void:
	var size := Vector2i.ZERO
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--size="):
			var wh := arg.trim_prefix("--size=").split("x")
			size = Vector2i(int(wh[0]), int(wh[1]))
	DirAccess.make_dir_recursive_absolute(_dir)
	var before := Settings.ui_scale
	if size != Vector2i.ZERO:
		var room := DisplayServer.screen_get_usable_rect()
		DisplayServer.window_set_size(size.min(room.size))
		DisplayServer.window_set_position(room.position)
	_tour.call_deferred(before)


func _tour(before: float) -> void:
	await _seconds(0.5)
	print("window %s pixels, screen %s, screen scale %.1f" % [DisplayServer.window_get_size(), DisplayServer.screen_get_size(), DisplayServer.screen_get_scale()])
	for scale: float in [1.0, 1.5]:
		Settings.ui_scale = scale
		Settings.apply()
		var menu: Control = load("res://src/ui/main_menu.tscn").instantiate()
		add_child(menu)
		await _seconds(0.5)
		await _snap("main_menu_%d" % roundi(scale * 100.0))
		var settings := SettingsMenu.new()
		add_child(settings)
		await _seconds(0.4)
		await _snap("settings_%d" % roundi(scale * 100.0))
		settings.queue_free()
		menu.queue_free()
	Settings.ui_scale = 1.0
	Settings.apply()
	var pg: Playground = PLAYGROUND.instantiate()
	pg.fresh_start = true
	pg.peaceful = true
	add_child(pg)
	while not pg.is_spawned or is_instance_valid(pg.loading):
		await get_tree().process_frame
	await _seconds(2.0)
	await _snap("hud_100")
	Settings.ui_scale = 1.5
	Settings.apply()
	await _seconds(0.3)
	await _snap("hud_150")
	pg.menu.open()
	await _seconds(0.3)
	await _snap("pause_150")
	pg.menu.close()
	pg.trip.clear_save()
	Settings.ui_scale = before
	Settings.apply()
	print("SHOTS done: %d in %s" % [_shot, ProjectSettings.globalize_path(_dir)])
	get_tree().quit()


func _snap(label: String) -> void:
	await RenderingServer.frame_post_draw
	_shot += 1
	var img := get_viewport().get_texture().get_image()
	var path := _dir.path_join("%02d_%s.png" % [_shot, label])
	img.save_png(path)
	print("SHOT %s (%dx%d)" % [path, img.get_width(), img.get_height()])


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
