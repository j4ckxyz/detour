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
	menu._seed.text = "DT6-00000-000ZV"
	menu._refresh_play()
	_check(menu._status.text != "", "a seed code with a typo is explained (%s)" % menu._status.text)
	_check(not menu._check_seed(), "and can't be played")
	# Any text is a seed, turned into a code (shown), the same every time.
	menu._seed.text = "Road trip!"
	menu._refresh_play()
	var from_text := menu._chosen_seed()
	_check(menu._check_seed() and WorldGen.code_error(from_text) == "" and from_text == menu._chosen_seed(), "any text makes a seed code (%s)" % from_text)
	_check(menu._seed_note.text.contains(from_text), "and the menu shows it: %s" % menu._seed_note.text)
	_check(menu._seed.max_length == 20, "seeds are up to 20 characters")
	menu._seed.text = "DT6-00000-000ZT"
	menu._refresh_play()
	_check(menu._status.text == "" and menu._check_seed(), "a good seed code is accepted")
	_check(WorldGen.code_error(menu._chosen_seed()) == "", "the chosen seed is playable")
	menu._seed.text = ""
	_check(WorldGen.code_error(menu._chosen_seed()) == "", "a new random seed is playable")
	_check(MainMenu._looks_like_code("K7M2QX") and not MainMenu._looks_like_code("10.0.0.2"), "room codes vs addresses")
	_check(MainMenu._split_address("10.0.0.2:4000", 1) == ["10.0.0.2", 4000] and MainMenu._split_address("host", 7) == ["host", 7], "addresses split into host and port")
	_check(menu._lan.get_child_count() >= 1, "the LAN games list is shown")
	# Saved trips are listed, to carry on or delete.
	var code := "DT6-00000-000ZT"
	var had := Saves.read(code)
	Saves.write(code, {"gen": WorldGen.gen_version(), "seed": code, "checkpoint": 1, "stations": 2,
		"elapsed": 600.0, "hours": 14.0, "progress": 0.4, "saved_at": Time.get_unix_time_from_system()})
	menu._refresh_trips()
	await get_tree().process_frame
	_check(menu._trips.get_child_count() >= 2, "your saved trips are listed")
	_check(Saves.describe(Saves.read(code)).contains("gas station 1 of 2"), "saying how far along: %s" % Saves.describe(Saves.read(code)))
	menu._seed.text = code
	menu._refresh_play()
	_check(menu._play.text == "Continue this trip", "and the seed box offers to continue it")
	if had.is_empty():
		Saves.delete(code)
	else:
		Saves.write(code, had)
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
