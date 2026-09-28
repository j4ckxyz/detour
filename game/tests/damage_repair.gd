extends Node
## Headless damage and repair test: crashing hurts the RV; knocked-off parts are rebuilt with
## hammer + scrap or refitted; a lost wheel is replaced with a spare and its bolts drilled in;
## an empty tank stops the engine until a jerry can is poured in; oil tops up; the station
## pump fills the tank and the welder fixes the frame. Uses go through the real Use action.
##
##   godot --headless --path game --fixed-fps 60 res://tests/damage_repair.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const Walker := preload("res://tests/support/walker.gd")
const HZ := 60

var _pg: Playground
var _rv: RV
var _player: Player
var _w: Walker
var _failures: PackedStringArray = []


func _ready() -> void:
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	add_child(_pg)
	_run()


func _run() -> void:
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60:
		await get_tree().physics_frame
		waited += 1
	_rv = _pg.rv
	_player = _pg.player
	_w = Walker.new(get_tree(), _player, _rv)
	var d := _rv.damage
	await _w.hold(1.0)
	_check(d.parts.size() >= 14, "the RV is made of detachable parts (%d)" % d.parts.size())

	await _crash_into_ledge()
	await _rebuild_and_refit()
	await _wheel()
	await _fuel_and_oil()
	await _station()
	_finish()


func _crash_into_ledge() -> void:
	var d := _rv.damage
	var ledge: Dictionary = {}
	for o: Dictionary in _pg.trip.data["obstacles"]:
		if int(o["kind"]) == 1:
			ledge = o
			break
	if ledge.is_empty():
		_check(false, "a ledge to crash into")
		return
	await _teleport(float(ledge["s"]) - 45.0)
	var frame_before := d.frame
	_rv.set_automatic(true)
	_rv.parking_brake = false
	for i: int in HZ * 10:
		_rv.throttle = 1.0
		var s := _pg.world.road_progress(_rv.global_position.x, _rv.global_position.z)
		if s >= 0.0:
			_rv.steer_input = clampf(_rv.to_local(_pg.trip.road_transform(s + 10.0).origin).x * 0.25, -1.0, 1.0)
		await get_tree().physics_frame
	_rv.throttle = 0.0
	_rv.steer_input = 0.0
	var worst := RVDamage.FULL
	for p: RVDamage.Part in d.parts.values():
		worst = minf(worst, p.hp)
	_check(d.frame < frame_before, "the crash hurt the frame (%.0f%%)" % d.frame)
	_check(worst < RVDamage.FULL, "the crash dented the front (worst part %.0f%%)" % worst)
	_rv.parking_brake = true
	await _w.hold(1.0)


func _rebuild_and_refit() -> void:
	var d := _rv.damage
	await _teleport(60.0)
	# Knock the rear bumper and the grille off.
	d.hit(d.parts[&"BumperRear"].centre, RVDamage.IMPACT_THRESHOLD + 30000.0, Vector3.BACK)
	_check(d.parts[&"BumperRear"].hp < RVDamage.FULL, "a hard knock dents the rear bumper (%.0f%%)" % d.parts[&"BumperRear"].hp)
	d.detach(&"BumperRear", Vector3.BACK)
	d.detach(&"Grille", Vector3.FORWARD)
	_check(not d.parts[&"BumperRear"].attached and not d.parts[&"Grille"].attached, "a big hit knocks parts off")
	var debris := d.parts[&"Grille"].debris
	_check(is_instance_valid(debris) and debris.kind == &"rv_part", "the grille lies on the ground as a part you can carry")
	await _w.hold(1.5)

	# Hammer + scrap (pocketed) rebuilds the bumper.
	var hammer := _give(&"hammer")
	var scrap := _give(&"scrap_metal")
	_player.select_slot(_player.slots.find(hammer))
	await _stand_facing(d.parts[&"BumperRear"].centre, Vector3(0.0, 0.0, 2.2))
	_check(ItemLibrary.use_hint(hammer, _player).begins_with("LMB rebuild"), "hammer hint: %s" % ItemLibrary.use_hint(hammer, _player))
	await _w.press(&"use_item")
	_check(d.parts[&"BumperRear"].attached and not is_instance_valid(scrap), "hammer + scrap rebuilt the rear bumper")

	# Carry the grille back and fit it.
	_player.drop_held()
	await _w.hold(0.3)
	var grille: Item = d.parts[&"Grille"].debris
	_player.pick_up(grille)
	_check(_player.held == grille, "carrying the grille")
	await _stand_facing(d.parts[&"Grille"].centre, Vector3(0.0, 0.0, -2.2))
	await _w.press(&"use_item")
	_check(d.parts[&"Grille"].attached, "the grille is back on")


func _wheel() -> void:
	var d := _rv.damage
	d.lose_wheel(1)
	_check(not d.wheel_on[1] and _rv.wheels[1].detached, "the front right wheel came off")
	await _w.hold(1.0)
	var spare := _give(&"spare_tire")
	var hub := _rv.wheels[1].position + Vector3.DOWN * RV.RIDE_LENGTH
	await _stand_facing(hub, Vector3(1.8, 0.0, 0.0))
	await _w.press(&"use_item")
	_check(d.wheel_on[1] and d.bolts[1] == 0 and not is_instance_valid(spare), "the spare is on the hub, bolts out (aim %s, hint '%s')" % [_player.aim_rv(), ItemLibrary.use_hint(spare, _player) if is_instance_valid(spare) else ""])
	var drill := _give(&"drill")
	_player.select_slot(_player.slots.find(drill))
	await _stand_facing(hub, Vector3(1.8, 0.0, 0.0))
	await _w.hold_action(&"use_item", 3.0)
	_check(d.bolts[1] == RVDamage.BOLTS, "drilled all the bolts in (%d/%d)" % [d.bolts[1], RVDamage.BOLTS])
	_player.drop_held()


func _fuel_and_oil() -> void:
	var d := _rv.damage
	d.engine = RVDamage.FULL # Whatever the crash did, this is about fuel.
	d.fuel = 0.0
	await _w.hold(0.2)
	_check(not _rv.drivetrain.running, "an empty tank stops the engine")
	_rv.drivetrain.clutch_pedal = 1.0
	_rv.clutch_input = 1.0
	_rv.start_engine()
	await _w.hold(1.2)
	_check(not _rv.drivetrain.running, "it won't start with no fuel")
	var can := _give(&"jerrycan")
	await _stand_facing(RVDamage.FUEL_CAP, Vector3(-1.9, 0.0, 0.0))
	await _w.press(&"use_item")
	_check(d.fuel > 19.0 and float(can.get_meta(&"fuel", 20.0)) < 0.5, "poured the jerry can in (%.0f L)" % d.fuel)
	_rv.start_engine()
	await _w.hold(1.2)
	_check(_rv.drivetrain.running, "starts again")
	_rv.clutch_input = 0.0
	_player.drop_held()
	d.oil = 0.1
	var oil := _give(&"motor_oil")
	await _stand_facing(RVDamage.ENGINE_SPOT, Vector3(0.0, 0.0, -2.4))
	await _w.press(&"use_item")
	_check(d.oil > 0.99 and not is_instance_valid(oil), "topped up the oil")


func _station() -> void:
	var d := _rv.damage
	d.fuel = 10.0
	d.frame = 40.0
	var station: Dictionary = _pg.trip.pad(1)
	await _teleport(float(station["s"]))
	var pump: Interactable = null
	var welder: Interactable = null
	for n: Node in get_tree().get_nodes_in_group(&"fuel_pumps"):
		if pump == null or (n as Node3D).global_position.distance_to(_rv.global_position) < pump.global_position.distance_to(_rv.global_position):
			pump = n
	for n: Node in get_tree().get_nodes_in_group(&"welders"):
		if welder == null or (n as Node3D).global_position.distance_to(_rv.global_position) < welder.global_position.distance_to(_rv.global_position):
			welder = n
	_check(pump != null and welder != null, "the station has a pump and a welder")
	if pump == null or welder == null:
		return
	pump.interact(_player)
	_check(d.fuel > RVDamage.TANK - 0.5, "the pump filled the RV (%.0f L)" % d.fuel)
	welder.interact(_player)
	_check(d.frame >= RVDamage.FULL, "the welder fixed the frame")


## Puts a fresh item straight into the player's hotbar (and hand).
func _give(kind: StringName) -> Item:
	var item := ItemLibrary.create(kind)
	_pg.items.add_child(item)
	item.global_position = _player.global_position + Vector3.UP
	if _player.held and (item.def.get("two_handed", false) or _player.held.def.get("two_handed", false)):
		_player.drop_held()
	_player.pick_up(item)
	return item


## Stands the player at `offset` (RV space) from a spot on the RV and looks at it.
func _stand_facing(local_target: Vector3, offset: Vector3) -> void:
	var at := _rv.to_global(local_target + offset)
	at.y = _pg.world.height_at(at.x, at.z) + 0.1
	if _player.inside:
		_player.leave_rv()
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _w.hold(0.3)
	_w.face(_rv.to_global(local_target))
	await _w.hold(0.1)


func _teleport(s: float) -> void:
	_pg._place_rv(_pg.trip.road_transform(s))
	var waited := 0
	while _pg.is_rv_waiting() and waited < HZ * 30:
		await get_tree().physics_frame
		waited += 1
	await _w.hold(1.0)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _pg:
		_pg.trip.clear_save()
	if _failures.is_empty():
		print("damage/repair: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
