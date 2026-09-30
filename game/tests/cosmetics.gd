extends Node
## Headless cosmetics test: the hats and glasses on offer (free ones and earned ones, each unlock
## naming a real achievement), what's worn is kept and sent to the others (roster), each looks
## different and sits on the head, the main menu offers them (locked ones greyed out) and saves
## the choice, and other players' hats turn up on their puppets when the roster arrives.
##
##   godot --headless --path game --fixed-fps 60 res://tests/cosmetics.tscn

var _failures: PackedStringArray = []
var _saved_achievements := ""
var _saved_path := ""
var _saved_hat: StringName
var _saved_glasses: StringName


func _ready() -> void:
	_run()


func _run() -> void:
	_saved_path = Achievements.path
	Achievements.path = "user://achievements_cosmetics_test.cfg"
	Achievements.reset_all()
	_saved_hat = Session.player_hat
	_saved_glasses = Session.player_glasses
	_lists()
	_unlocking()
	_roster()
	_looks()
	await _menu()
	await _puppets()
	Session.player_hat = _saved_hat
	Session.player_glasses = _saved_glasses
	Session.players.clear()
	Achievements.reset_all()
	DirAccess.remove_absolute(Achievements.path)
	Achievements.path = _saved_path
	Achievements.load_saved()
	_finish()


func _lists() -> void:
	for kind: StringName in [&"hat", &"glasses"]:
		var seen: Dictionary[StringName, bool] = {}
		var free := 0
		for d: Dictionary in Cosmetics.list(kind):
			_check(not seen.has(d["id"]) and String(d["name"]) != "", "%s %s is listed once, with a name" % [kind, d["id"]])
			seen[d["id"]] = true
			if d.has("unlock"):
				_check(not Achievements.definition(d["unlock"]).is_empty(), "%s needs a real achievement (%s)" % [d["id"], d["unlock"]])
			else:
				free += 1
		_check(free >= 2 and Cosmetics.list(kind).size() > free, "%ss: some free, some to earn (%d free of %d)" % [kind, free, Cosmetics.list(kind).size()])
		_check(Cosmetics.is_valid(kind, Cosmetics.ids(kind)[0]) and not Cosmetics.is_valid(kind, &"nope"), "ids are checked")
	_check(Cosmetics.DEFAULT_HAT == &"beanie" and Cosmetics.DEFAULT_GLASSES == &"shades", "the default look is the beanie and dark glasses")
	_check(Cosmetics.valid_or_default(&"hat", &"nope") == &"beanie" and Cosmetics.valid_or_default(&"glasses", &"") == &"shades", "rubbish falls back to it")


func _unlocking() -> void:
	_check(Cosmetics.is_unlocked(&"hat", &"cap") and Cosmetics.is_unlocked(&"glasses", &"none"), "free ones are yours")
	_check(not Cosmetics.is_unlocked(&"hat", &"tophat"), "the top hat isn't, yet")
	_check(Cosmetics.how_to_unlock(&"hat", &"tophat").contains("There yet!"), "and says how: %s" % Cosmetics.how_to_unlock(&"hat", &"tophat"))
	_check(Cosmetics.how_to_unlock(&"hat", &"cap") == "", "a free one needs nothing")
	_check(Cosmetics.wearable(&"hat", &"tophat") == &"beanie", "an unearned hat isn't worn: the default is")
	Achievements.add(&"trips_finished")
	_check(Cosmetics.is_unlocked(&"hat", &"tophat") and Cosmetics.wearable(&"hat", &"tophat") == &"tophat", "getting home unlocks the top hat")
	Achievements.raise(&"top_kmh", 120.0)
	_check(Cosmetics.is_unlocked(&"glasses", &"goggles"), "100 km/h, the goggles")
	Achievements.add(&"repairs", 25.0)
	Achievements.add(&"bears_sprayed")
	Achievements.add(&"burgers", 5.0)
	Achievements.add(&"km", 25.0)
	for id: StringName in [&"hardhat", &"antlers", &"chef", &"cowboy"]:
		_check(Cosmetics.is_unlocked(&"hat", id), "%s unlocked by its achievement" % id)
	Achievements.reset_all()
	_check(not Cosmetics.is_unlocked(&"hat", &"chef"), "resetting the achievements locks them again")


func _roster() -> void:
	Session.players.clear()
	_check(Session.hat_of(1) == Session.player_hat or Session.hat_of(1) == Cosmetics.DEFAULT_HAT, "solo: your own hat")
	Session.player_hat = &"cap"
	Session.player_glasses = &"round"
	_check(Session.hat_of(Session.local_id()) == &"cap" and Session.glasses_of(Session.local_id()) == &"round", "solo, no roster: what you chose (%s, %s)" % [Session.hat_of(1), Session.glasses_of(1)])
	Session.player_hat = &"tophat" # Not earned.
	_check(Session.hat_of(Session.local_id()) == &"beanie", "a hat you haven't earned isn't worn")
	Session._set_roster({1: {"name": "Host", "color": 0, "hat": "cap", "glasses": "none"}, 2: {"name": "Guest", "color": 1, "hat": "cowboy", "glasses": "round"}, 3: {"name": "Old", "color": 2}})
	_check(Session.hat_of(2) == &"cowboy" and Session.glasses_of(2) == &"round", "the roster carries what others wear")
	_check(Session.hat_of(3) == &"beanie" and Session.glasses_of(3) == &"shades", "someone with nothing listed gets the default")
	Session._set_roster({2: {"name": "X", "color": 0, "hat": "evil_hat", "glasses": "<script>"}})
	_check(Session.hat_of(2) == &"beanie" and Session.glasses_of(2) == &"shades", "and nonsense is ignored")
	_check(Session.PROTOCOL >= 2, "the wire protocol moved on with the horn")
	# Saved and read back.
	Session.player_hat = &"bucket"
	Session.player_glasses = &"none"
	Session.save_settings()
	Session.player_hat = &"beanie"
	Session.player_glasses = &"shades"
	Session._load_settings()
	_check(Session.player_hat == &"bucket" and Session.player_glasses == &"none", "what you wear is remembered")
	Session.players.clear()


func _looks() -> void:
	var plain := PillAvatar.build(Color.RED, "", false, &"none", &"none")
	var plain_boxes := _meshes(plain)
	var tops: Dictionary[StringName, float] = {}
	for d: Dictionary in Cosmetics.HATS:
		var id: StringName = d["id"]
		var avatar := PillAvatar.build(Color.RED, "", false, id, &"none")
		var count := _meshes(avatar)
		var top := _top(avatar)
		tops[id] = top
		if id == &"none":
			_check(count == plain_boxes, "no hat adds nothing")
		else:
			_check(count > plain_boxes and top > 1.6 and top < 2.6, "%s: on the head (%d more parts, top at %.2f m)" % [id, count - plain_boxes, top])
		avatar.free()
	_check(tops[&"chef"] > tops[&"beanie"] + 0.3, "the chef's hat is tall")
	for d: Dictionary in Cosmetics.GLASSES:
		var id: StringName = d["id"]
		var avatar := PillAvatar.build(Color.RED, "", false, &"none", id)
		if id == &"none":
			_check(_meshes(avatar) == plain_boxes, "no glasses adds nothing")
		else:
			var front := _front(avatar)
			_check(_meshes(avatar) > plain_boxes and front < -0.2, "%s: on the face (front at z %.2f)" % [id, front])
		avatar.free()
	# The name tag rides above whatever's worn.
	var tagged := PillAvatar.build(Color.RED, "Someone", false, &"chef", &"shades")
	var label: Label3D = null
	for c: Node in tagged.get_children():
		if c is Label3D:
			label = c
	_check(label != null and label.position.y > tops[&"chef"], "the name tag clears a tall hat (%.2f over %.2f)" % [label.position.y if label else 0.0, tops[&"chef"]])
	tagged.free()
	# Your own body is a shadow, hat and all.
	var mine := PillAvatar.build(Color.RED, "", true, &"cowboy", &"goggles")
	var all_shadow := true
	for c: Node in mine.get_children():
		all_shadow = all_shadow and (c as GeometryInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_check(all_shadow, "your own hat only casts a shadow")
	mine.free()
	plain.free()


func _menu() -> void:
	Session.player_hat = &"cap"
	Session.player_glasses = &"shades"
	var menu: MainMenu = load("res://src/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	var hats := menu._hat
	var glasses := menu._glasses
	_check(hats.item_count == Cosmetics.HATS.size() and glasses.item_count == Cosmetics.GLASSES.size(), "the menu offers every hat and pair of glasses")
	_check(hats.get_item_text(hats.selected) == "Baseball cap" and glasses.get_item_text(glasses.selected) == "Dark glasses", "with your choice selected (%s, %s)" % [hats.get_item_text(hats.selected), glasses.get_item_text(glasses.selected)])
	var top_index := Cosmetics.ids(&"hat").find(&"tophat")
	_check(hats.is_item_disabled(top_index) and hats.get_item_text(top_index).contains("locked") and hats.get_item_tooltip(top_index).contains("There yet!"), "a locked hat is greyed out and says how to get it (%s)" % hats.get_item_text(top_index))
	hats.item_selected.emit(Cosmetics.ids(&"hat").find(&"bucket"))
	glasses.item_selected.emit(Cosmetics.ids(&"glasses").find(&"round"))
	_check(Session.player_hat == &"bucket" and Session.player_glasses == &"round", "picking changes what you wear")
	var cfg := ConfigFile.new()
	_check(cfg.load(Session.SETTINGS_PATH) == OK and cfg.get_value("player", "hat") == "bucket", "and it's saved")
	menu.queue_free()
	await get_tree().process_frame


## A puppet is dressed from the roster, and re-dressed when the roster changes.
func _puppets() -> void:
	Session.players[2] = {"name": "Guest", "color": 1, "hat": "", "glasses": ""}
	var puppet := Player.new()
	puppet.puppet = true
	puppet.peer_id = 2
	add_child(puppet)
	await get_tree().process_frame
	_check(_meshes(puppet._avatar) > 0 and puppet._worn[1] == &"beanie", "a puppet starts in the default look")
	Session.players[2]["hat"] = "cowboy"
	Session.players[2]["glasses"] = "goggles"
	puppet.refresh_look()
	await get_tree().process_frame
	_check(puppet._worn[1] == &"cowboy" and puppet._worn[2] == &"goggles", "and takes on what the roster says (%s, %s)" % [puppet._worn[1], puppet._worn[2]])
	var old := puppet._avatar
	puppet.refresh_look()
	_check(puppet._avatar == old, "nothing's rebuilt when nothing changed")
	puppet.queue_free()
	await get_tree().process_frame


func _meshes(node: Node) -> int:
	var n := 0
	for c: Node in node.find_children("*", "MeshInstance3D", true, false):
		n += 1
	return n


## The highest point of an avatar's parts (metres above the feet).
func _top(node: Node3D) -> float:
	var best := 0.0
	for c: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var aabb := mi.transform * mi.mesh.get_aabb()
		best = maxf(best, aabb.end.y)
	return best


## The most forward (most negative z) point of parts at face height.
func _front(node: Node3D) -> float:
	var best := 0.0
	for c: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var aabb := mi.transform * mi.mesh.get_aabb()
		if aabb.position.y > 1.3 and aabb.end.y < 1.6 and aabb.size.x < 0.4:
			best = minf(best, aabb.position.z)
	return best


func _finish() -> void:
	if _failures.is_empty():
		print("cosmetics: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
