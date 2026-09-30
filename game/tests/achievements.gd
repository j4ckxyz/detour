extends Node
## Headless achievements test (in a scratch file, never the player's own): counting and
## unlocking (totals, bests, thresholds, only once), the toast (shown, queued, timed out), saving
## and reading back, hidden achievements, and a real trip feeding them: the road and winch rope
## counted from the RV, checkpoints, stalls, horn, EpiPens, repairs, planks, bites, antidotes,
## going home; and the list screen.
##
##   godot --headless --path game --fixed-fps 60 res://tests/achievements.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")
const HZ := 60

var _failures: PackedStringArray = []
var _saved_path := ""
var _got: Array[StringName] = []


func _ready() -> void:
	_run()


func _run() -> void:
	_saved_path = Achievements.path
	Achievements.path = "user://achievements_test.cfg"
	DirAccess.remove_absolute(Achievements.path)
	Achievements.reset_all()
	Achievements.unlocked.connect(func(id: StringName) -> void: _got.append(id))
	_list()
	_counting()
	await _toasts()
	_saving()
	await _trip()
	await _screen()
	Achievements.reset_all()
	DirAccess.remove_absolute(Achievements.path)
	Achievements.path = _saved_path
	Achievements.load_saved()
	_finish()


func _list() -> void:
	var ids: Dictionary[StringName, bool] = {}
	for def: Dictionary in Achievements.LIST:
		_check(not ids.has(def["id"]), "%s is listed once" % def["id"])
		ids[def["id"]] = true
		_check(String(def["title"]) != "" and String(def["desc"]) != "" and float(def["goal"]) > 0.0 and def["stat"] is StringName, "%s has a title, a description, a stat and a goal" % def["id"])
	_check(Achievements.LIST.size() >= 30, "there are plenty of them (%d)" % Achievements.LIST.size())
	_check(Achievements.definition(&"horn")["title"] == "Beep beep" and Achievements.definition(&"nope").is_empty(), "definitions can be looked up")


func _counting() -> void:
	_check(Achievements.earned_count() == 0 and Achievements.stat(&"planks") == 0.0, "a clean slate")
	Achievements.add(&"planks")
	_check(_got == [&"plank_1"] and Achievements.is_earned(&"plank_1"), "the first plank earns Bridge builder")
	_check(is_equal_approx(Achievements.progress_of(&"plank_10"), 0.1), "and Carpenter is a tenth of the way (%.2f)" % Achievements.progress_of(&"plank_10"))
	for i: int in 8:
		Achievements.add(&"planks")
	_check(not Achievements.is_earned(&"plank_10"), "nine planks isn't ten")
	Achievements.add(&"planks")
	_check(Achievements.is_earned(&"plank_10") and _got.count(&"plank_10") == 1, "the tenth earns Carpenter, once")
	Achievements.add(&"planks", 5.0)
	_check(_got.count(&"plank_1") == 1 and _got.count(&"plank_10") == 1, "more planks earn nothing new")
	# Bests only go up.
	Achievements.raise(&"top_kmh", 60.0)
	Achievements.raise(&"top_kmh", 40.0)
	_check(is_equal_approx(Achievements.stat(&"top_kmh"), 60.0), "a best keeps the highest (%.0f)" % Achievements.stat(&"top_kmh"))
	_check(not Achievements.is_earned(&"top_gear"), "60 km/h isn't Top gear")
	Achievements.raise(&"top_kmh", 101.0)
	_check(Achievements.is_earned(&"top_gear"), "100 km/h is")
	# Fractions add up (kilometres).
	for i: int in 25:
		Achievements.add(&"km", 1.0)
	_check(Achievements.is_earned(&"km_25") and not Achievements.is_earned(&"km_100"), "25 km earns Long haul, not Odometer")
	Achievements.add(&"planks", -3.0)
	Achievements.add(&"planks", 0.0)
	_check(Achievements.stat(&"planks") == 15.0, "nothing goes down (%.0f)" % Achievements.stat(&"planks"))
	_check(Achievements.is_night(22.0) and Achievements.is_night(2.0) and not Achievements.is_night(14.0), "night is 21:00 to 05:00")
	# Tapes: distinct ones count.
	Achievements.tape_played(3)
	Achievements.tape_played(3)
	_check(Achievements.stat(&"tapes_played") == 2.0 and Achievements.stat(&"tapes_heard") == 1.0, "playing a tape twice is two plays, one tape")
	_check(Achievements.is_earned(&"tape_1"), "the first play earns Side A")


func _toasts() -> void:
	Achievements.reset_all()
	_got.clear()
	Achievements._toasts.clear()
	Achievements._panel.visible = false
	Achievements.add(&"honks")
	Achievements.add(&"repairs")
	await get_tree().process_frame
	await get_tree().process_frame
	var toast := Achievements.current_toast()
	_check(not toast.is_empty() and Achievements._panel.visible and Achievements._toast_title.text.contains("Beep beep"), "a toast announces it (%s)" % Achievements._toast_title.text)
	_check(Achievements._toast_desc.text == "Use the horn.", "with what it was for")
	await get_tree().create_timer(Achievements.TOAST_TIME + 0.3).timeout
	_check(Achievements._toast_title.text.contains("Handyman") and Achievements._panel.visible, "the next one follows (%s)" % Achievements._toast_title.text)
	await get_tree().create_timer(Achievements.TOAST_TIME + 0.3).timeout
	_check(not Achievements._panel.visible and Achievements._toasts.is_empty(), "and then it goes")


func _saving() -> void:
	Achievements.reset_all()
	Achievements.add(&"planks", 3.0)
	Achievements.add(&"honks")
	Achievements.tape_played(2)
	Achievements.save()
	var fresh: Node = load("res://src/autoload/achievements.gd").new()
	fresh.path = Achievements.path
	fresh._by_id = Achievements._by_id
	fresh.load_saved()
	_check(fresh.stat(&"planks") == 3.0 and fresh.is_earned(&"horn") and fresh.is_earned(&"plank_1") and not fresh.is_earned(&"plank_10"), "stats and what's earned are read back")
	_check(fresh._played_ids.has(2), "and which tapes were heard")
	fresh.free()
	# Rubbish in the file is ignored.
	var cfg := ConfigFile.new()
	cfg.set_value("stats", "planks", "many")
	cfg.set_value("stats", "km", 2.5)
	cfg.set_value("earned", "made_up", 5)
	cfg.set_value("earned", "horn", 12345)
	cfg.save(Achievements.path)
	Achievements.load_saved()
	_check(Achievements.stat(&"km") == 2.5 and Achievements.stat(&"planks") == 0.0 and not Achievements.is_earned(&"made_up") and Achievements.is_earned(&"horn"), "rubbish is skipped, the rest read")
	Achievements.reset_all()
	_check(Achievements.earned_count() == 0 and Achievements.stat(&"km") == 0.0, "reset forgets everything")


## A real trip, watched: the road, the rope, stalls, the horn, checkpoints, home.
func _trip() -> void:
	Achievements.reset_all()
	_got.clear()
	Session.seed_code = Playground.DEFAULT_SEED
	var pg: Playground = PLAYGROUND.instantiate()
	pg.fresh_start = true
	pg.peaceful = true
	add_child(pg)
	var waited := 0
	while not pg.is_spawned and waited < HZ * 60 * 5: # (Frames run faster than the generator thread under load.)
		await get_tree().physics_frame
		waited += 1
	var rv := pg.rv
	var player := pg.player
	var w := Walker.new(get_tree(), player, rv)
	await w.hold(1.0)
	_check(Achievements._pg == pg, "the trip is being watched")

	# The road: driving 600 m counts kilometres (the trip's odometer, sampled).
	pg.trip.distance_driven += 600.0
	await w.hold(1.0)
	_check(is_equal_approx(Achievements.stat(&"km"), 0.6), "600 m driven is 0.6 km (%.2f)" % Achievements.stat(&"km"))
	# Night: the same after dark counts as night driving.
	pg.trip.hours = 23.0
	pg.trip.distance_driven += 1500.0
	await w.hold(1.0)
	_check(Achievements.stat(&"night_km") >= 1.4 and Achievements.is_earned(&"night_driver"), "1.5 km at 23:00 is night driving (%.1f km)" % Achievements.stat(&"night_km"))
	pg.trip.hours = 8.0
	# Top speed and the day.
	rv.linear_velocity = -rv.global_basis.z * 30.0
	await w.hold(0.6)
	_check(Achievements.stat(&"top_kmh") > 100.0 and Achievements.is_earned(&"top_gear"), "30 m/s is over 100 km/h (%.0f)" % Achievements.stat(&"top_kmh"))
	rv.linear_velocity = Vector3.ZERO
	pg.trip.hours = 32.0
	await w.hold(0.6)
	_check(Achievements.is_earned(&"overnight"), "day 2 is Overnight")
	pg.trip.hours = 8.0
	# The winch rope.
	rv.winches[0].reeled_total += 12.0
	await w.hold(1.0)
	_check(Achievements.stat(&"winch_m") >= 12.0 and Achievements.is_earned(&"winch_1") and not Achievements.is_earned(&"winch_100"), "12 m of rope reeled in (%.0f)" % Achievements.stat(&"winch_m"))
	# The horn.
	rv.horn = true
	await w.hold(1.0)
	rv.horn = false
	await w.hold(1.0)
	_check(Achievements.stat(&"honks") == 1.0 and Achievements.is_earned(&"horn"), "one honk (%.0f)" % Achievements.stat(&"honks"))
	# Stalls and lost parts come from the RV.
	for i: int in 5:
		rv.engine_stalled.emit()
	_check(Achievements.is_earned(&"stalls_5"), "5 stalls is Clutch trouble")
	rv.damage.part_lost.emit(&"Hood")
	rv.damage.wheel_lost.emit(0)
	_check(Achievements.is_earned(&"shedding") and Achievements.is_earned(&"wheel_off"), "lost parts and wheels count")
	# What the player does.
	for what: StringName in [&"repair", &"tire_fitted", &"can_poured", &"plank", &"epipen", &"revive", &"bitten", &"antidote", &"sprayed_bear", &"burger", &"cooked_patty"]:
		player.did.emit(what)
	for id: StringName in [&"handyman", &"pit_crew", &"jerry_rigged", &"plank_1", &"epipen", &"guardian", &"rattled", &"antidote", &"bear_off", &"grill_master"]:
		_check(Achievements.is_earned(id), "%s is earned by doing it" % id)
	player.passed_out.emit()
	pg.sent_back.emit("test")
	_check(Achievements.is_earned(&"passed_out") and Achievements.is_earned(&"tow"), "passing out and being sent back count")
	# Checkpoints and home.
	pg.trip.checkpoint_reached.emit(1, 2)
	_check(Achievements.is_earned(&"first_stop"), "a gas station is Fill 'er up")
	pg.trip.stalls = 0
	pg.trip.elapsed = 60.0
	pg.trip.finished.emit()
	_check(Achievements.is_earned(&"home") and Achievements.is_earned(&"clean_run") and Achievements.is_earned(&"quick_trip"), "getting home with no stalls in a minute earns home, a clean run and a quick trip")
	var before := Achievements.earned_count()
	pg.trip.stalls = 3
	pg.trip.elapsed = 100000.0
	pg.trip.finished.emit()
	_check(Achievements.stat(&"clean_runs") == 1.0 and Achievements.stat(&"quick_trips") == 1.0 and Achievements.stat(&"trips_finished") == 2.0, "a slow trip with stalls doesn't count as clean or quick")
	_check(Achievements.earned_count() == before, "... and earns nothing new")
	pg.trip.clear_save()
	pg.queue_free()
	Session.seed_code = ""
	await get_tree().process_frame
	_check(Achievements._pg == null or not is_instance_valid(Achievements._pg), "when the trip goes, so does the watch")
	# Saved when the trip ended.
	var cfg := ConfigFile.new()
	_check(cfg.load(Achievements.path) == OK and cfg.has_section_key("earned", "home"), "and it was saved")


func _screen() -> void:
	Achievements.reset_all()
	Achievements.add(&"planks", 4.0)
	var menu := AchievementsMenu.new()
	add_child(menu)
	await get_tree().process_frame
	_check(menu._summary.text == "1 of %d earned" % Achievements.LIST.size(), "the screen counts them (%s)" % menu._summary.text)
	var texts: PackedStringArray = []
	for label: Node in menu.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	_check(texts.has("✓ Bridge builder") and texts.has("Carpenter"), "earned ones are ticked, others listed")
	_check(texts.has("???") and not texts.has("Shedding parts"), "hidden ones are hidden until earned")
	_check(texts.find("✓ Bridge builder") < texts.find("Carpenter"), "earned ones come first")
	Achievements.add(&"parts_lost")
	await get_tree().process_frame
	await get_tree().process_frame
	texts.clear()
	for label: Node in menu.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	_check(texts.has("✓ Shedding parts"), "earning one updates the open screen")
	menu.close()
	await get_tree().process_frame


func _finish() -> void:
	if _failures.is_empty():
		print("achievements: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
