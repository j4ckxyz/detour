extends Node
## Achievements and lifetime stats, kept on this machine (`user://achievements.cfg`).
##
## Things that happen in a trip add to a stat (`add`, `raise`); a stat reaching an achievement's
## goal unlocks it, shows a toast at the top of the screen and is saved. `watch` hooks a trip up:
## the road and the winch rope are counted by watching the RV, the rest by what the player and
## the trip announce (`Player.did`, `Trip.checkpoint_reached`, ...). Nothing here changes how the
## game plays; the list is in the main menu (Achievements) and the pause menu.

signal unlocked(id: StringName)

const PATH := "user://achievements.cfg"
## Seconds each toast stays up.
const TOAST_TIME := 5.0
const SAMPLE_INTERVAL := 0.5
const SAVE_INTERVAL := 30.0

## Every achievement: id, title, what to do, the stat that counts towards it and how much of it
## earns it. `hidden` ones read "???" until they're earned.
const LIST: Array[Dictionary] = [
	# The road.
	{"id": &"first_stop", "title": "Fill 'er up", "desc": "Reach a gas station.", "stat": &"stations", "goal": 1},
	{"id": &"five_stops", "title": "Regular", "desc": "Reach 5 gas stations, in any trips.", "stat": &"stations", "goal": 5},
	{"id": &"home", "title": "There yet!", "desc": "Get home.", "stat": &"trips_finished", "goal": 1},
	{"id": &"home_3", "title": "Frequent traveller", "desc": "Get home 3 times.", "stat": &"trips_finished", "goal": 3},
	{"id": &"clean_run", "title": "Smooth operator", "desc": "Get home without stalling once.", "stat": &"clean_runs", "goal": 1},
	{"id": &"quick_trip", "title": "Are we there yet?", "desc": "Get home averaging 25 km/h or better, stops and tows included.", "stat": &"quick_trips", "goal": 1},
	{"id": &"km_25", "title": "Long haul", "desc": "Drive 25 km in total.", "stat": &"km", "goal": 25},
	{"id": &"km_100", "title": "Odometer", "desc": "Drive 100 km in total.", "stat": &"km", "goal": 100},
	{"id": &"top_gear", "title": "Top gear", "desc": "Reach 100 km/h.", "stat": &"top_kmh", "goal": 100},
	{"id": &"night_driver", "title": "Night driver", "desc": "Drive 1 km after dark.", "stat": &"night_km", "goal": 1},
	{"id": &"overnight", "title": "Overnight", "desc": "Still be on the road on day 2.", "stat": &"max_day", "goal": 2},
	{"id": &"stalls_5", "title": "Clutch trouble", "desc": "Stall the engine 5 times.", "stat": &"stalls", "goal": 5},
	{"id": &"horn", "title": "Beep beep", "desc": "Use the horn.", "stat": &"honks", "goal": 1},
	# The RV.
	{"id": &"handyman", "title": "Handyman", "desc": "Repair the RV.", "stat": &"repairs", "goal": 1},
	{"id": &"mechanic", "title": "Mechanic", "desc": "Do 25 repairs.", "stat": &"repairs", "goal": 25},
	{"id": &"pit_crew", "title": "Pit crew", "desc": "Fit a wheel or a spare tire.", "stat": &"tires_fitted", "goal": 1},
	{"id": &"jerry_rigged", "title": "Jerry-rigged", "desc": "Pour a jerry can into the tank.", "stat": &"cans_poured", "goal": 1},
	{"id": &"winch_1", "title": "Hooked", "desc": "Reel in 5 m of winch rope.", "stat": &"winch_m", "goal": 5},
	{"id": &"winch_100", "title": "Winch operator", "desc": "Reel in 100 m of winch rope.", "stat": &"winch_m", "goal": 100},
	{"id": &"plank_1", "title": "Bridge builder", "desc": "Lay a plank.", "stat": &"planks", "goal": 1},
	{"id": &"plank_10", "title": "Carpenter", "desc": "Lay 10 planks.", "stat": &"planks", "goal": 10},
	{"id": &"shedding", "title": "Shedding parts", "desc": "Lose a piece of the RV on the road.", "stat": &"parts_lost", "goal": 1, "hidden": true},
	{"id": &"wheel_off", "title": "Wheelie bad", "desc": "Lose a wheel.", "stat": &"wheels_lost", "goal": 1, "hidden": true},
	{"id": &"tow", "title": "Back to the start", "desc": "Get sent back to the last stop.", "stat": &"tows", "goal": 1, "hidden": true},
	# Staying alive.
	{"id": &"epipen", "title": "Not today", "desc": "Use an EpiPen.", "stat": &"epipens", "goal": 1},
	{"id": &"paramedic", "title": "Paramedic", "desc": "Use 5 EpiPens.", "stat": &"epipens", "goal": 5},
	{"id": &"guardian", "title": "Guardian angel", "desc": "Revive a teammate.", "stat": &"revives", "goal": 1},
	{"id": &"rattled", "title": "Rattled", "desc": "Get bitten by a rattlesnake.", "stat": &"bites", "goal": 1},
	{"id": &"antidote", "title": "Just in time", "desc": "Cure snake venom with an antidote.", "stat": &"antidotes", "goal": 1},
	{"id": &"bear_off", "title": "Bear necessities", "desc": "Send a bear packing with bear spray.", "stat": &"bears_sprayed", "goal": 1},
	{"id": &"fast_food", "title": "Fast food", "desc": "Eat 5 burgers.", "stat": &"burgers", "goal": 5},
	{"id": &"grill_master", "title": "Grill master", "desc": "Cook a patty properly, then eat it.", "stat": &"cooked_patties", "goal": 1},
	{"id": &"passed_out", "title": "Rough day", "desc": "Bleed out and wake up back at the RV.", "stat": &"passouts", "goal": 1, "hidden": true},
	# Tapes.
	{"id": &"tape_1", "title": "Side A", "desc": "Play a cassette in the RV's tape deck.", "stat": &"tapes_played", "goal": 1},
	{"id": &"tape_all", "title": "Whole album", "desc": "Play every cassette.", "stat": &"tapes_heard", "goal": 8},
	# Time.
	{"id": &"hour_1", "title": "Settling in", "desc": "Spend an hour on the road.", "stat": &"hours", "goal": 1},
	{"id": &"hour_10", "title": "Road trip", "desc": "Spend 10 hours on the road.", "stat": &"hours", "goal": 10},
]

## Where the achievements are kept. Headless runs (the tests, a server) keep their own, so they
## never touch the player's.
var path := PATH if DisplayServer.get_name() != "headless" else "user://achievements_headless.cfg"
var stats: Dictionary[StringName, float] = {}
## id → when it was earned (unix seconds).
var earned: Dictionary[StringName, int] = {}

var _by_id: Dictionary[StringName, Dictionary] = {}
var _by_stat: Dictionary[StringName, Array] = {}
var _toasts: Array[Dictionary] = []
var _toast_left := 0.0
var _layer := CanvasLayer.new()
var _panel := PanelContainer.new()
var _toast_title := Label.new()
var _toast_desc := Label.new()

var _pg: Playground
var _t_sample := 0.0
var _t_save := 0.0
var _last_distance := 0.0
var _last_rope := 0.0
var _horn_down := false
var _played_ids: Dictionary[int, bool] = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _dirty:
		save()


func _exit_tree() -> void:
	if _dirty:
		save()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for def: Dictionary in LIST:
		_by_id[def["id"]] = def
		var list: Array = _by_stat.get(def["stat"], [])
		list.append(def)
		_by_stat[def["stat"]] = list
	_build_toast()
	load_saved()


## How much of `stat` there is so far.
func stat(name: StringName) -> float:
	return stats.get(name, 0.0)


func is_earned(id: StringName) -> bool:
	return earned.has(id)


func earned_count() -> int:
	return earned.size()


## The achievement's row (see `LIST`), or an empty dictionary.
func definition(id: StringName) -> Dictionary:
	return _by_id.get(id, {})


## 0..1 of the way to an achievement.
func progress_of(id: StringName) -> float:
	var def := definition(id)
	if def.is_empty():
		return 0.0
	return 1.0 if is_earned(id) else clampf(stat(def["stat"]) / float(def["goal"]), 0.0, 1.0)


## Adds to a running total (kilometres driven, planks laid...).
func add(name: StringName, amount: float = 1.0) -> void:
	if amount <= 0.0:
		return
	stats[name] = stat(name) + amount
	_check(name)


## Raises a best (top speed, latest day) if `value` beats it.
func raise(name: StringName, value: float) -> void:
	if value > stat(name):
		stats[name] = value
		_check(name)


## Forgets everything (Reset in the achievements screen).
func reset_all() -> void:
	stats.clear()
	earned.clear()
	_played_ids.clear()
	save()


func _check(name: StringName) -> void:
	_dirty = true
	var changed := false
	for def: Dictionary in _by_stat.get(name, []):
		if not earned.has(def["id"]) and stat(name) >= float(def["goal"]):
			earned[def["id"]] = int(Time.get_unix_time_from_system())
			changed = true
			_toasts.append(def)
			unlocked.emit(def["id"])
	if changed:
		save()


## Whether there's anything not saved yet (stats are written when something's earned, every
## half minute while playing, and when the trip ends or the game closes).
var _dirty := false


func save() -> void:
	_dirty = false
	var cfg := ConfigFile.new()
	for name: StringName in stats:
		cfg.set_value("stats", String(name), stats[name])
	for id: StringName in earned:
		cfg.set_value("earned", String(id), earned[id])
	cfg.set_value("tapes", "heard", PackedInt32Array(_played_ids.keys()))
	cfg.save(path)


func load_saved() -> void:
	stats.clear()
	earned.clear()
	_played_ids.clear()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var heard: Variant = cfg.get_value("tapes", "heard", PackedInt32Array())
	if heard is PackedInt32Array:
		for id: int in heard:
			_played_ids[id] = true
	for key: String in cfg.get_section_keys("stats") if cfg.has_section("stats") else PackedStringArray():
		var v: Variant = cfg.get_value("stats", key)
		if v is float or v is int:
			stats[StringName(key)] = float(v)
	for key: String in cfg.get_section_keys("earned") if cfg.has_section("earned") else PackedStringArray():
		if _by_id.has(StringName(key)):
			earned[StringName(key)] = int(cfg.get_value("earned", key, 0))


# --- what happens in a trip ----------------------------------------------------------------

## Starts counting a trip: call once the trip is built (the playground does).
func watch(pg: Playground) -> void:
	unwatch()
	_pg = pg
	_last_distance = pg.trip.distance_driven
	_last_rope = _rope_total()
	_horn_down = false
	pg.tree_exiting.connect(unwatch, CONNECT_ONE_SHOT)
	pg.trip.checkpoint_reached.connect(_on_checkpoint)
	pg.trip.finished.connect(_on_finished)
	pg.rv.engine_stalled.connect(func() -> void: add(&"stalls"))
	pg.rv.damage.part_lost.connect(func(_part: StringName) -> void: add(&"parts_lost"))
	pg.rv.damage.wheel_lost.connect(func(_i: int) -> void: add(&"wheels_lost"))
	pg.player.did.connect(_on_did)
	pg.rv.deck.tape_started.connect(tape_played)
	pg.player.passed_out.connect(func() -> void: add(&"passouts"))
	pg.sent_back.connect(func(_why: String) -> void: add(&"tows"))


## Stops counting (the trip's gone); what's counted so far is saved. The trip's signals go
## with its nodes.
func unwatch() -> void:
	_pg = null
	if _dirty:
		save()


## Something the player did (see `Player.did`).
func _on_did(what: StringName) -> void:
	match what:
		&"repair": add(&"repairs")
		&"tire_fitted": add(&"tires_fitted")
		&"can_poured": add(&"cans_poured")
		&"plank": add(&"planks")
		&"epipen": add(&"epipens")
		&"revive": add(&"revives")
		&"bitten": add(&"bites")
		&"antidote": add(&"antidotes")
		&"sprayed_bear": add(&"bears_sprayed")
		&"burger": add(&"burgers")
		&"cooked_patty": add(&"cooked_patties")


func _on_checkpoint(_index: int, _total: int) -> void:
	add(&"stations")


func _on_finished() -> void:
	add(&"trips_finished")
	if _pg == null:
		return
	if _pg.trip.stalls == 0:
		add(&"clean_runs")
	var length := float(_pg.trip.data.get("length", 0.0))
	if length > 0.0 and length / maxf(_pg.trip.elapsed, 1.0) * 3.6 >= 25.0:
		add(&"quick_trips")


func _rope_total() -> float:
	if _pg == null or _pg.rv == null:
		return 0.0
	return _pg.rv.winches[0].reeled_total + _pg.rv.winches[1].reeled_total


## Whether `hour` (0..24) is after dark.
static func is_night(hour: float) -> bool:
	return hour >= 21.0 or hour < 5.0


func _process(dt: float) -> void:
	_update_toast(dt)
	if _pg == null or not is_instance_valid(_pg) or not _pg.is_spawned:
		return
	stats[&"hours"] = stat(&"hours") + dt / 3600.0
	_t_sample += dt
	_t_save += dt
	if _t_save > SAVE_INTERVAL and _dirty:
		_t_save = 0.0
		save()
	if _t_sample < SAMPLE_INTERVAL:
		return
	_t_sample = 0.0
	var rv := _pg.rv
	var km := maxf(0.0, _pg.trip.distance_driven - _last_distance) / 1000.0
	_last_distance = _pg.trip.distance_driven
	if km > 0.0:
		add(&"km", km)
		if is_night(fposmod(_pg.trip.hours, 24.0)):
			add(&"night_km", km)
	raise(&"top_kmh", absf(rv.forward_speed()) * 3.6)
	raise(&"max_day", float(_pg.trip.day()))
	var rope := _rope_total()
	if rope > _last_rope:
		add(&"winch_m", rope - _last_rope)
	_last_rope = rope
	if rv.horn and not _horn_down:
		add(&"honks")
	_horn_down = rv.horn
	_check(&"hours")


## A tape was played (see the cassette deck): counts plays and different tapes heard.
func tape_played(id: int) -> void:
	add(&"tapes_played")
	if not _played_ids.has(id):
		_played_ids[id] = true
		raise(&"tapes_heard", float(_played_ids.size()))


# --- the toast -----------------------------------------------------------------------------

func _build_toast() -> void:
	_layer.layer = 130
	add_child(_layer)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.06, 0.92)
	style.border_color = Color(0.95, 0.62, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.offset_top = 18.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	_toast_title.add_theme_font_size_override("font_size", 20)
	_toast_title.add_theme_color_override("font_color", Color(0.95, 0.62, 0.25))
	_toast_desc.add_theme_font_size_override("font_size", 14)
	_toast_desc.add_theme_color_override("font_color", Color(0.96, 0.93, 0.86))
	box.add_child(_toast_title)
	box.add_child(_toast_desc)
	_panel.add_child(box)
	_panel.visible = false
	_layer.add_child(_panel)


## The toast being shown now, or an empty dictionary.
func current_toast() -> Dictionary:
	return _toasts[0] if _panel.visible and not _toasts.is_empty() else {}


func _update_toast(dt: float) -> void:
	if _panel.visible:
		_toast_left -= dt
		_panel.modulate.a = clampf(_toast_left / 0.5, 0.0, 1.0) if _toast_left < 0.5 else 1.0
		if _toast_left <= 0.0:
			_panel.visible = false
			_toasts.pop_front()
	if not _panel.visible and not _toasts.is_empty():
		var def := _toasts[0]
		_toast_title.text = "Achievement: " + String(def["title"])
		_toast_desc.text = String(def["desc"])
		Sfx.play_ui(self, "ui/toast", -8.0)
		_panel.visible = true
		_panel.modulate.a = 1.0
		_toast_left = TOAST_TIME
