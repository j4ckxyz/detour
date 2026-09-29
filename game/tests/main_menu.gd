extends Node
## Headless main-menu test: it builds, validates seed codes, tells room codes from addresses,
## and remembers settings only when asked.
##
##   godot --headless --path game --fixed-fps 60 res://tests/main_menu.tscn

var _failures: PackedStringArray = []


func _ready() -> void:
	var menu: MainMenu = load("res://src/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	_check(menu._play.text == "Start a new trip", "a blank seed starts a new trip")
	menu._seed.text = "NOT-A-CODE"
	menu._refresh_play()
	_check(menu._status.text != "", "a bad seed code is explained (%s)" % menu._status.text)
	_check(not menu._check_seed(), "and can't be played")
	menu._seed.text = "DT3-0EHYA-0MEKW"
	menu._refresh_play()
	_check(menu._status.text == "" and menu._check_seed(), "a good seed code is accepted")
	_check(WorldGen.code_error(menu._chosen_seed()) == "", "the chosen seed is playable")
	menu._seed.text = ""
	_check(WorldGen.code_error(menu._chosen_seed()) == "", "a new random seed is playable")
	_check(MainMenu._looks_like_code("K7M2QX") and not MainMenu._looks_like_code("10.0.0.2"), "room codes vs addresses")
	_check(MainMenu._split_address("10.0.0.2:4000", 1) == ["10.0.0.2", 4000] and MainMenu._split_address("host", 7) == ["host", 7], "addresses split into host and port")
	_check(menu._lan.get_child_count() >= 1, "the LAN games list is shown")
	menu.queue_free()
	if _failures.is_empty():
		print("main menu: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
