extends Node
## Headless RV storage test: the RV starts with its kit put away in its slots; planks go on the
## side rack, the spare on the back, jerry cans in their holders, food on the fridge (through
## the real look-and-press-E flow); stored things ride along and come back out; and a save
## at a checkpoint keeps the RV's state, what's stowed and the hotbar.
##
##   godot --headless --path game --fixed-fps 60 res://tests/storage.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")
const HZ := 60

var _pg: Playground
var _rv: RV
var _player: Player
var _w: Walker
var _failures: PackedStringArray = []


func _ready() -> void:
	await _start(true)
	var s := _rv.storage
	_check(s.size() >= 30, "the RV has %d storage slots" % s.size())
	_check(s[&"ToolWall1"].stored() != null and s[&"ToolWall1"].stored().kind == &"hammer", "the hammer hangs on the tool wall")
	_check(s[&"FridgeTop1"].stored() != null and s[&"FridgeTop1"].stored().kind == &"burger", "burgers sit on the fridge")
	_check(s[&"Shelf1"].stored() != null and s[&"Shelf1"].stored().kind == &"epipen", "the EpiPen is on the overhead shelf")

	await _store_outside(&"plank", &"PlankRack1", Vector3(-1.1, 0.0, 0.0), "plank rack")
	await _store_outside(&"spare_tire", &"SpareMount1", Vector3(0.0, 0.0, 1.3), "spare-tire mount")
	await _store_outside(&"jerrycan", &"CanHolder1", Vector3(-0.3, 0.0, 1.2), "jerry-can holder")

	# It rides along, and comes back out.
	var plank := s[&"PlankRack1"].stored()
	var before := _rv.to_local(plank.global_position)
	var rv_before := _rv.global_position
	_rv.global_position += Vector3(0.0, 0.0, 0.5)
	await _w.hold(0.1)
	_check(_rv.to_local(plank.global_position).distance_to(before) < 0.01 and plank.global_position.distance_to(_rv.to_global(before)) < 0.01 and _rv.global_position.distance_to(rv_before) > 0.3,
		"stored things ride along")
	_rv.global_position = rv_before
	_player.pick_up(plank)
	_check(s[&"PlankRack1"].stored() == null and not plank.has_meta(&"slot"), "taking it out frees the slot")
	_player.drop_held()
	await _w.hold(0.5)

	# The wrong thing doesn't go in: a burger isn't a plank.
	var burger := _give(&"burger")
	await _face_slot(&"PlankRack2", Vector3(-1.1, 0.0, 0.0))
	await _w.hold(0.2)
	_check(_player.target_prompt != "Put it here", "a burger doesn't fit the plank rack")
	_player.drop_held()
	burger.queue_free()

	# Save at a checkpoint and continue.
	_rv.damage.fuel = 17.0
	_rv.damage.detach(&"MirrorL")
	var plank2 := _give(&"plank")
	s[&"PlankRack3"].store(plank2)
	_player.held = null
	_give(&"drill")
	_pg.trip.checkpoint = 1
	_pg.trip.save()
	_pg.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await _start(false)
	s = _rv.storage
	_check(_pg.trip.checkpoint == 1, "continued from the checkpoint")
	_check(absf(_rv.damage.fuel - 17.0) < 0.5, "the fuel level was kept (%.1f L)" % _rv.damage.fuel)
	_check(not _rv.damage.parts[&"MirrorL"].attached, "and the missing mirror")
	_check(s[&"PlankRack3"].stored() != null and s[&"PlankRack3"].stored().kind == &"plank", "the stored plank is still on the rack")
	_check(s[&"ToolWall1"].stored() != null, "the tool wall kept its hammer")
	_check(_player.find_item(&"drill") != null, "the hotbar came back")
	_pg.trip.clear_save()
	_finish()


func _start(fresh: bool) -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = fresh
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60 * 5: # (Frames run faster than the generator thread under load.)
		await get_tree().physics_frame
		waited += 1
	_rv = _pg.rv
	_player = _pg.player
	_w = Walker.new(get_tree(), _player, _rv)
	await _w.hold(1.0)


func _store_outside(kind: StringName, slot: StringName, offset: Vector3, label: String) -> void:
	_give(kind)
	await _face_slot(slot, offset)
	await _w.hold(0.2)
	_check(_player.target_prompt == "Put it here", "looking at the %s holding a %s: '%s'" % [label, kind, _player.target_prompt])
	await _w.press(&"interact")
	var stored := _rv.storage[slot].stored()
	_check(stored != null and stored.kind == kind and _player.held == null, "the %s goes in the %s" % [kind, label])


## Stands `offset` (RV space, pushed out to the ground) from a slot and looks at it.
func _face_slot(slot: StringName, offset: Vector3) -> void:
	var node := _rv.storage[slot]
	var at := _rv.to_global(node.position + offset)
	at.y = _pg.world.height_at(at.x, at.z) + 0.1
	if _player.inside:
		_player.leave_rv()
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _w.hold(0.1) # The eyes follow next frame.
	_w.face(node.global_position)


func _give(kind: StringName) -> Item:
	var item := ItemLibrary.create(kind)
	_pg.items.add_child(item)
	item.global_position = _player.global_position + Vector3.UP
	if _player.held:
		_player.drop_held()
	_player.pick_up(item)
	return item


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _failures.is_empty():
		print("storage: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
