extends Node
## Headless cassette test: the eight tapes are all there (a title, a tune that's long enough for
## every line, lines in order); a cassette is a small item named for its tape; the deck on the
## dashboard plays the tape put in it (music bus, title then Dot's lines as subtitles, only
## near the RV), stops when it's taken out or runs out, stays quiet for a tape that was in it
## when the trip loaded, and counts towards the achievements; tapes lie in the places and caves
## and are saved, restored and sent over the network with their number.
##
##   godot --headless --path game --fixed-fps 60 res://tests/tapes.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60

var _pg: Playground
var _rv: RV
var _failures: PackedStringArray = []


func _ready() -> void:
	_run()


func _run() -> void:
	_data()
	_items()
	Session.seed_code = Playground.DEFAULT_SEED
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60 * 5: # (Frames run faster than the generator thread under load.)
		await get_tree().physics_frame
		waited += 1
	_rv = _pg.rv
	await _hold(0.5)
	_music_bus()
	_world()
	await _deck()
	await _loaded_tape()
	_saving()
	_pg.trip.clear_save()
	_pg.queue_free()
	Session.seed_code = ""
	await get_tree().process_frame
	_finish()


func _data() -> void:
	_check(Tapes.COUNT == 8 and Tapes.TAPES.size() == 8, "there are eight tapes")
	_check(Achievements.definition(&"tape_all")["goal"] == Tapes.COUNT, "and the last achievement wants them all")
	for id: int in Tapes.COUNT:
		var lines := Tapes.lines(id)
		_check(Tapes.title(id) != "" and lines.size() >= 3, "tape %d, '%s': a title and %d lines" % [id + 1, Tapes.title(id), lines.size()])
		var in_order := true
		for i: int in range(1, lines.size()):
			in_order = in_order and float(lines[i][0]) >= float(lines[i - 1][0]) + 6.0
		_check(in_order, "... each line at least 6 s after the last, to be read")
		var tune := Sfx.stream(Tapes.file(id))
		var last := float(lines[-1][0])
		_check(tune.get_length() > last + 4.0, "... and the tune (%.0f s) outlasts the last line (%.0f s)" % [tune.get_length(), last])
	_check(Tapes.line_at(0, 0.0) == "", "before the first line, silence")
	_check(Tapes.line_at(0, 4.0).begins_with("Testing, testing"), "then the first line")
	_check(Tapes.line_at(0, 12.5) == "" or Tapes.line_at(0, 12.5).begins_with("Testing"), "a line goes when it's been read (%s)" % Tapes.line_at(0, 12.5).left(20))
	_check(Tapes.line_at(0, 14.0).begins_with("If you've found"), "the next comes along")
	_check(Tapes.line_at(0, 1000.0) == "", "and nothing once they're done")


func _items() -> void:
	var tape := ItemLibrary.create_tape(3)
	_check(tape.kind == &"tape" and int(tape.get_meta(&"tape")) == 3 and tape.display_name() == "Cassette: Night Drive", "a cassette is named for its tape (%s)" % tape.display_name())
	_check(tape.def["stow"] == &"tape" and tape.mass < 0.5, "it's small, and has its own place in the RV")
	tape.set_meta(&"tape", 6)
	ItemLibrary.refresh_tape(tape)
	_check(tape.display_name() == "Cassette: Frostpeak", "and renames itself for the number it carries (%s)" % tape.display_name())
	_check(NetGame.META_KEYS.has(&"tape"), "the number goes over the network")
	tape.free()


func _music_bus() -> void:
	_check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == &"Master", "there's a Music bus, through Master")
	_check(Settings.volumes.has("Music"), "with a volume of its own")
	var volumes := Settings.volumes.duplicate()
	volumes["Music"] = 0.0
	Settings.set_value(&"volumes", volumes)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "at 0 it's muted")
	Settings.reset()
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "and back")


func _world() -> void:
	var starter: Item = null
	var lying := 0
	for n: Node in get_tree().get_nodes_in_group(&"items"):
		var item := n as Item
		if item == null or item.kind != &"tape":
			continue
		if item.get_parent() == _rv.stash:
			starter = item
		elif item.get_parent() == _pg.items:
			lying += 1
	_check(starter != null and int(starter.get_meta(&"tape")) == 0 and starter.get_meta(&"slot", &"") == &"", "a first cassette is loose on the dashboard")
	_check(lying >= 1, "and more lie in the places and caves (%d)" % lying)
	_check(_rv.deck != null and _rv.storage.has(&"TapeDeck1") and not _rv.deck.playing, "the deck is on the dashboard, quiet")


func _deck() -> void:
	var deck := _rv.deck
	var slot := _rv.storage[&"TapeDeck1"]
	var before := Achievements.stat(&"tapes_played")
	var started: Array[int] = []
	var ended: Array[int] = []
	deck.tape_started.connect(func(id: int) -> void: started.append(id))
	deck.tape_ended.connect(func(id: int) -> void: ended.append(id))
	var tape := ItemLibrary.create_tape(2)
	_rv.stash.add_child(tape)
	slot.store(tape)
	_check(slot.fits(tape) and slot.stored() == tape, "a cassette goes in the deck's slot")
	await _hold(0.5)
	_check(deck.playing and deck.tape == 2 and deck.is_audible() and deck.speaker.bus == &"Music", "it plays (tape 3, on the Music bus)")
	_check(started == [2] and Achievements.stat(&"tapes_played") == before + 1.0, "counted once")
	_check(deck.subtitle() == "♪ Gas Station Waltz", "the title first (%s)" % deck.subtitle())
	deck.seconds = 13.0
	_check(deck.subtitle() == Tapes.line_at(2, 13.0) and deck.subtitle().begins_with("The burgers"), "then Dot (%s)" % deck.subtitle().left(24))

	# The subtitles show near the RV only.
	var subs := _pg.tape_subtitles
	var player := _pg.player
	player.global_position = _rv.global_position + Vector3(0.0, 1.0, 4.0)
	await _hold(0.2)
	_check(subs._label.visible and subs._label.text == deck.subtitle(), "the subtitles show while you're by the RV")
	player.global_position = _rv.global_position + Vector3(120.0, 1.0, 0.0)
	await _hold(0.2)
	_check(not subs._label.visible, "and not from far away")
	player.global_position = _pg.by_the_door()
	player.velocity = Vector3.ZERO
	await _hold(0.3)

	# Taking it out stops it.
	player.pick_up(tape)
	await _hold(0.5)
	_check(not deck.playing and deck.tape == -1 and not deck.speaker.playing and ended == [2], "picking it up stops the music")
	_check(deck.subtitle() == "", "and the words")
	player.drop_held()
	tape = ItemLibrary.create_tape(5)
	_rv.stash.add_child(tape)
	slot.store(tape)
	await _hold(0.5)
	_check(deck.playing and deck.tape == 5 and started == [2, 5], "another goes in and plays from the top (tape 6)")
	# It runs out and clicks off; the cassette stays in.
	deck.seconds = deck._length + 1.0
	await _hold(0.2)
	_check(not deck.playing and ended == [2, 5] and slot.stored() == tape, "when it ends the deck stops and the cassette stays put")
	await _hold(1.0)
	_check(not deck.playing, "and it doesn't start itself again")
	_rv.stash.remove_child(tape)
	tape.free()
	await _hold(0.5)


## A tape in the deck when the trip loads doesn't blare; take it out and put it back and it plays.
func _loaded_tape() -> void:
	var deck := _rv.deck
	var slot := _rv.storage[&"TapeDeck1"]
	var tape := ItemLibrary.create_tape(7)
	_rv.stash.add_child(tape)
	Sfx.armed = false
	slot.store(tape)
	await _hold(0.5)
	Sfx.armed = true
	_check(not deck.playing and slot.stored() == tape, "a tape already in the deck at the start stays quiet")
	tape.remove_meta(&"slot")
	_pg.player.pick_up(tape)
	await _hold(0.5)
	_pg.player.drop_held()
	tape = ItemLibrary.create_tape(7)
	_rv.stash.add_child(tape)
	slot.store(tape)
	await _hold(0.5)
	_check(deck.playing and deck.tape == 7, "put in again, it plays (tape 8)")
	_rv.stash.remove_child(tape)
	tape.free()
	await _hold(0.5)
	_check(not deck.playing, "and taking it away stops it")


func _saving() -> void:
	var tape := ItemLibrary.create_tape(4)
	var meta := Playground._item_meta(tape)
	_check(meta.get("tape") == 4, "a saved cassette keeps its number")
	var back := _pg._saved_item([&"tape", "Cassette", meta, Transform3D.IDENTITY, false, true])
	_check(back != null and back.display_name() == "Cassette: Bayou Blues" and int(back.get_meta(&"tape")) == 4, "and comes back as the same tape (%s)" % back.display_name())
	back.free()
	tape.free()


func _hold(seconds: float) -> void:
	for i: int in int(seconds * HZ):
		await get_tree().physics_frame


func _finish() -> void:
	if _failures.is_empty():
		print("tapes: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
