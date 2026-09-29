extends Node
## Headless survival test: falls and the RV hurt; burgers, soda, first aid and cooked patties
## heal (a patty cooks on the RV's stove); a snake bite poisons until the antidote; running
## out of health downs you, an EpiPen gets you up, bleeding out wakes you by the RV; a bear
## charges and swipes, bear spray sends it off, and it gives up on someone inside the RV; an
## eagle steals a burger and drops it far away; the trip's wildlife is placed the same way
## for the same seed.
##
##   godot --headless --path game --fixed-fps 60 res://tests/survival.tscn

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
	_pg.peaceful = true # Animals are added by hand below.
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
	await _w.hold(1.0)
	_placement()
	await _falls_and_the_rv()
	await _food()
	await _snake()
	await _downed()
	await _bear()
	await _eagle()
	_finish()


func _placement() -> void:
	var a := Wildlife.new()
	var b := Wildlife.new()
	for w: Wildlife in [a, b]:
		add_child(w)
		w.setup(_pg.world, _rv, _pg.items, _pg.trip.data)
		w.populate()
	_check(a.count(Snake) > 0 and a.count(Bear) > 0 and a.count(Eagle) > 0,
		"the trip has wildlife (%d snakes, %d bears, %d eagles)" % [a.count(Snake), a.count(Bear), a.count(Eagle)])
	var same := a.get_child_count() == b.get_child_count()
	for i: int in mini(a.get_child_count(), b.get_child_count()):
		same = same and (a.get_child(i) as Node3D).position.is_equal_approx((b.get_child(i) as Node3D).position)
	_check(same, "the same seed puts the same animals in the same places")
	var camp: Vector3 = _pg.trip.pad(0)["pos"]
	var near_camp := false
	for c: Node in a.get_children():
		if c is Bear and (c as Node3D).position.distance_to(camp) < Wildlife.BEAR_CLEARANCE:
			near_camp = true
	_check(not near_camp, "no bears by the camp")
	a.free()
	b.free()


func _falls_and_the_rv() -> void:
	var at := _open_ground()
	_player.global_position = at + Vector3.UP * 11.0
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _w.hold(2.5)
	_check(_player.health < Player.MAX_HEALTH and not _player.downed, "an 11 m fall hurts (%.0f)" % _player.health)
	_player.health = Player.MAX_HEALTH
	_player.global_position = at + Vector3.UP * 0.3
	await _w.hold(1.0)
	_check(_player.health == Player.MAX_HEALTH, "walking about doesn't")

	# Stand in front of the RV and have it roll into us.
	_rv.parking_brake = false
	var front := _rv.to_global(Vector3(0.0, 0.0, -4.35))
	front.y = _pg.world.height_at(front.x, front.z) + 0.05
	_player.global_position = front
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	var hit := false
	for i: int in HZ:
		_rv.linear_velocity = -_rv.global_basis.z * 8.0
		await get_tree().physics_frame
		if _player.health < Player.MAX_HEALTH:
			hit = true
			break
	_rv.linear_velocity = Vector3.ZERO
	_rv.parking_brake = true
	_check(hit, "the RV running into you hurts (%.0f, %s)" % [_player.health, _player.hurt_cause])
	await _w.hold(1.5)
	_player.health = Player.MAX_HEALTH


func _food() -> void:
	_player.health = 40.0
	_give(&"burger")
	await _w.press(&"use_item")
	_check(is_equal_approx(_player.health, 70.0), "a burger heals 30 (%.0f)" % _player.health)
	_give(&"soda")
	await _w.press(&"use_item")
	_check(is_equal_approx(_player.health, 80.0), "a soda heals 10 (%.0f)" % _player.health)
	var kit := _give(&"first_aid")
	await _w.press(&"use_item")
	_check(_player.health == Player.MAX_HEALTH and not is_instance_valid(kit), "a first-aid kit patches you up")

	var patty := _give(&"patty")
	await _w.press(&"use_item")
	_check(is_instance_valid(patty) and _player.held == patty, "a frozen patty can't be eaten")
	_rv.stove.interact(_player)
	_check(patty.get_parent() == _rv.stove and _player.held == null, "the patty goes on the RV's stove")
	await _w.hold(ItemLibrary.PATTY_COOKED + 1.0)
	_check(patty.display_name() == "Cooked patty", "it cooks (%s)" % patty.display_name())
	_player.pick_up(patty)
	_player.health = 50.0
	await _w.press(&"use_item")
	_check(is_equal_approx(_player.health, 90.0), "a cooked patty heals 40 (%.0f)" % _player.health)
	_player.health = Player.MAX_HEALTH


func _snake() -> void:
	var at := _open_ground()
	_player.global_position = at
	_player.reset_physics_interpolation()
	await _w.hold(0.5)
	var snake := _spawn(Snake.new(), at + Vector3(3.0, 0.0, 0.0)) as Snake
	await _w.hold(0.5)
	_check(snake.is_rattling(), "a snake rattles a warning at 3 m")
	_check(_player.venom == 0.0, "... without biting")
	await _w.walk_to(snake.global_position, 0.8)
	await _w.hold(0.5)
	_check(_player.venom > 0.0 and _player.health < Player.MAX_HEALTH, "walking up to it gets you bitten and poisoned")
	_put(at + Vector3(-8.0, 0.0, 0.0))
	var before := _player.health
	await _w.hold(3.0)
	_check(_player.health < before - 2.0, "venom keeps hurting (%.0f → %.0f)" % [before, _player.health])
	_give(&"antidote")
	await _w.press(&"use_item")
	_check(_player.venom == 0.0, "the antidote cures it")
	before = _player.health
	await _w.hold(2.0)
	_check(is_equal_approx(_player.health, before), "and health stops dropping")
	_put(snake.global_position + Vector3(-4.0, 0.0, 0.0))
	await _w.hold(0.3)
	_give(&"bear_spray")
	_w.face(snake.global_position)
	await _w.press(&"use_item")
	_check(snake.state == Snake.State.FLEE, "bear spray sends the snake off")
	snake.queue_free()
	_player.health = Player.MAX_HEALTH


func _downed() -> void:
	_player.global_position = _open_ground()
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	await _w.hold(0.5)
	_player.hurt(500.0, "testing")
	await _w.hold(0.5)
	_check(_player.downed and _player.health == 0.0, "out of health: downed")
	var start := _player.global_position
	await _w.hold_action(&"move_forward", 1.0)
	var crawled := _player.global_position.distance_to(start)
	_check(crawled > 0.2 and crawled < 1.5, "downed players crawl slowly (%.2f m in 1 s)" % crawled)
	_give_pocket(&"epipen")
	await _w.press(&"use_item")
	_check(not _player.downed and is_equal_approx(_player.health, Player.REVIVE_HEALTH), "an EpiPen gets you back up (%.0f)" % _player.health)
	_check(_player.find_item(&"epipen") == null, "... and is used up")

	_put(_open_ground(40.0))
	await _w.hold(0.3)
	_player.hurt(500.0, "testing")
	await _w.hold(0.3)
	await _w.press(&"interact") # Give up.
	await _w.hold(0.5)
	_check(not _player.downed and _player.health == 50.0, "passing out wakes you up again")
	_check(_player.global_position.distance_to(_pg.by_the_door()) < 3.0, "... by the RV")
	_player.health = Player.MAX_HEALTH


func _bear() -> void:
	var at := _open_ground()
	_player.global_position = at
	_player.reset_physics_interpolation()
	await _w.hold(0.3)
	var bear := _spawn(Bear.new(), at + Vector3(0.0, 0.0, 16.0)) as Bear
	var charged := false
	for i: int in HZ * 6:
		await get_tree().physics_frame
		if bear.state == Bear.State.CHASE or bear.state == Bear.State.ATTACK:
			charged = true
		if _player.health < Player.MAX_HEALTH:
			break
	_check(charged, "a bear spots you and charges")
	_check(_player.health <= Player.MAX_HEALTH - Bear.SWIPE_DAMAGE, "its swipe hurts (%.0f)" % _player.health)
	_give(&"bear_spray")
	_w.face(bear.global_position + Vector3.UP)
	await _w.press(&"use_item")
	_check(bear.state == Bear.State.FLEE, "bear spray sends it running")
	var d0 := bear.global_position.distance_to(_player.global_position)
	await _w.hold(3.0)
	_check(bear.global_position.distance_to(_player.global_position) > d0 + 10.0, "... far away")
	_check(int(_player.held.get_meta(&"puffs")) == ItemLibrary.SPRAY_PUFFS - 1, "one puff used")
	bear.queue_free()

	# Safe in the RV: a charging bear gives up.
	_player.health = Player.MAX_HEALTH
	_player.global_position = _pg.by_the_door()
	_player.reset_physics_interpolation()
	var bear2 := _spawn(Bear.new(), _player.global_position + (_player.global_position - _rv.global_position).normalized() * 14.0) as Bear
	for i: int in HZ * 4:
		await get_tree().physics_frame
		if bear2.state == Bear.State.CHASE:
			break
	_player.board(_rv.to_local(_player.global_position))
	await _w.hold(2.5)
	_check(_player.inside and bear2.state in [Bear.State.RETURN, Bear.State.WANDER], "it gives up on someone inside the RV (%s)" % Bear.State.keys()[bear2.state])
	_player.leave_rv()
	bear2.queue_free()
	_player.health = Player.MAX_HEALTH
	await _w.hold(0.5)


func _eagle() -> void:
	var at := _open_ground()
	_player.global_position = at
	_player.reset_physics_interpolation()
	await _w.hold(0.3)
	var burger := _give(&"burger")
	var eagle := _spawn(Eagle.new(), at) as Eagle
	eagle.set(&"_cooldown", 0.0)
	var stolen := false
	for i: int in HZ * 10:
		await get_tree().physics_frame
		if _player.held == null:
			stolen = true
			break
	_check(stolen and burger.get_parent() == eagle, "an eagle swoops down and takes your burger")
	for i: int in HZ * 15:
		await get_tree().physics_frame
		if burger.get_parent() == _pg.items:
			break
	_check(burger.get_parent() == _pg.items, "... and drops it")
	await _w.hold(3.0)
	_check(burger.global_position.distance_to(at) > 40.0, "a long walk away (%.0f m)" % burger.global_position.distance_to(at))
	eagle.queue_free()


## A clear spot on the ground away from the RV (`away` metres off its right side).
func _open_ground(away: float = 20.0) -> Vector3:
	var p := _rv.to_global(Vector3(away, 0.0, 0.0))
	p.y = _pg.world.height_at(p.x, p.z) + 0.2
	return p


## Stands the player on the ground at `p` (x, z).
func _put(p: Vector3) -> void:
	p.y = _pg.world.height_at(p.x, p.z) + 0.2
	_player.global_position = p
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()


func _spawn(animal: Animal, at: Vector3) -> Animal:
	animal.world = _pg.world
	animal.rv = _rv
	animal.world_items = _pg.items
	at.y = _pg.world.height_at(at.x, at.z)
	animal.home = at
	animal.position = at
	_pg.wildlife.add_child(animal)
	return animal


## Puts a fresh item straight into the player's hand.
func _give(kind: StringName) -> Item:
	var item := ItemLibrary.create(kind)
	_pg.items.add_child(item)
	item.global_position = _player.global_position + Vector3.UP
	if _player.held:
		_player.drop_held()
	_player.pick_up(item)
	return item


## Puts a fresh item in a free pocket (not the hand).
func _give_pocket(kind: StringName) -> Item:
	var item := ItemLibrary.create(kind)
	_pg.items.add_child(item)
	var slot := _player.slots.find(null, _player.selected + 1)
	if slot < 0:
		slot = _player.slots.find(null)
	_player.slots[slot] = item
	item.grab(_player, _player.hand)
	item.visible = false
	return item


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)


func _finish() -> void:
	if _pg:
		_pg.trip.clear_save()
	if _failures.is_empty():
		print("survival: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)
