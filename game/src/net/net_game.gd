class_name NetGame
extends Node
## Plays the trip together (PLAN.md §6.2). Everything goes through this node (the same path
## on every machine), with peer ids in the arguments:
##
## - **Players**: each machine moves its own player and sends snapshots 30 times a second;
##   everyone else draws a puppet. Things done to a puppet (a bear's swipe, a revive) are sent
##   to its machine.
## - **The RV** is simulated by the driver's machine, or the host's while nobody drives, and
##   the others follow its snapshots. Pushes, repairs and winch remotes are "ops" sent to the
##   simulating machine (`RV.op`).
## - **Items** are the host's: it numbers them and says where each one is (held by whom, in the
##   RV, laid as a plank, on a grill, loose). Players move items locally straight away and tell
##   the host, which passes it on (or corrects them if someone else got there first).
## - **Wildlife and the trip** (arrivals, saves, restocks) run on the host; clients copy them.
##
## The host only sends game messages to clients that have loaded the trip (`ready_peers`).

enum Where { LOOSE, HELD, STOWED, PLACED, GRILL, CARRIED, WINCH, ANCHORED }

const SNAPSHOT_INTERVAL := 1.0 / 30.0
const SLOW_INTERVAL := 0.25
const ITEM_INTERVAL := 1.0 / 12.0
const ANIMAL_INTERVAL := 0.1
const TRIP_INTERVAL := 1.0
## First ids are fixed: the winch hooks (made by every machine's RV).
const HOOK_IDS: Array[int] = [1, 2]
const PLAYER_CALLS: Array[StringName] = [&"hurt", &"poison", &"knock", &"revive", &"say"]
const META_KEYS: Array[StringName] = [&"fuel", &"puffs", &"cook", &"tire", &"part", &"wheel", &"slot", &"tape", &"settling"]

var active := false
var pg: Playground
var rv: RV
## Everyone else's players, by peer id.
var puppets: Dictionary[int, Player] = {}
## Host: clients that have loaded the trip.
var ready_peers: Array[int] = []
## Who simulates the RV.
var rv_owner := 1
var items: Dictionary[int, Item] = {}

var _next_id := 100
## id → the last record sent or applied, to notice local changes.
var _known: Dictionary[int, Array] = {}
## Loose items the host last saw moving (their final resting place still has to go out).
var _moving: Dictionary[int, bool] = {}
var _applying := false
var _rv_target: Array = []
var _rv_age := 0.0
var _t_snap := 0.0
var _t_slow := 0.0
var _t_items := 0.0
var _t_animals := 0.0
var _t_trip := 0.0


func _ready() -> void:
	name = "Net"


## Starts playing online (does nothing solo). Call once the trip is built and the local
## player spawned.
func start(playground: Playground) -> void:
	pg = playground
	rv = pg.rv
	if not Session.is_online():
		return
	active = true
	pg.player.peer_id = Session.local_id()
	Item.on_ready = _on_item_ready
	Item.on_freed = _on_item_freed
	for i: int in rv.winches.size():
		var hook := rv.winches[i].hook
		hook.net_id = HOOK_IDS[i]
		_register(hook)
	rv.forward_op = _forward_op
	rv.door_toggled.connect(func(open: bool) -> void: _to_all(&"_door", [open]))
	for animal: Node in pg.wildlife.get_children():
		(animal as Animal).puppet = not Session.is_host()
		(animal as Animal).remote_spray = _send_spray
	Session.roster_changed.connect(_sync_puppets)
	Session.player_left.connect(_on_player_left)
	pg.player.seat_changed.connect(_on_local_seat)
	_sync_puppets()
	if Session.is_host():
		for n: Node in get_tree().get_nodes_in_group(&"items"):
			var item := n as Item
			if item and item.net_id == 0 and pg.is_ancestor_of(item):
				item.net_id = _new_id()
				_register(item)
		pg.trip.checkpoint_reached.connect(func(i: int, _total: int) -> void: _to_all(&"_trip_reached", [i]))
		pg.trip.finished.connect(func() -> void: _to_all(&"_trip_reached", [pg.trip.checkpoint]))
	else:
		pg.trip.is_authority = false
		rv.damage.spawn_loose = _ask_spawn_loose
		_set_simulated(false)
		_client_ready.rpc_id(1)


func _exit_tree() -> void:
	if active:
		Item.on_ready = Callable()
		Item.on_freed = Callable()
		active = false


func _new_id() -> int:
	_next_id += 1
	return _next_id


func is_host() -> bool:
	return Session.is_host()


func local_id() -> int:
	return Session.local_id()


## The player with `peer`'s id (ours or a puppet), or null.
func player_of(peer: int) -> Player:
	if peer == local_id():
		return pg.player
	return puppets.get(peer)


# --- sending ---------------------------------------------------------------------------------

## Host: to every ready client (but `except`). Client: to the host, which passes it on.
func _to_all(method: StringName, args: Array, except: int = 0) -> void:
	if is_host():
		for peer: int in ready_peers:
			if peer != except:
				callv(&"rpc_id", [peer, method] + args)
	else:
		callv(&"rpc_id", [1, method] + args)


func _send(peer: int, method: StringName, args: Array) -> void:
	if peer == local_id():
		callv(method, args)
	else:
		callv(&"rpc_id", [peer, method] + args)


## Who sent the RPC being handled (1 for calls made locally on the host).
func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return s if s != 0 else local_id()


# --- joining -----------------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not is_host():
		return
	var peer := _sender()
	var list: Array = []
	for id: int in items:
		var item := items[id]
		if is_instance_valid(item):
			list.append(_spawn_record(item))
	rpc_id(peer, &"_full_state", {
		"items": list, "rv_owner": rv_owner, "door": rv.door_open,
		"rv": rv.snapshot(), "rv_slow": rv.slow_snapshot(), "trip": _trip_state(),
	})
	if not ready_peers.has(peer):
		ready_peers.append(peer)


@rpc("authority", "reliable")
func _full_state(state: Dictionary) -> void:
	for rec: Array in state["items"]:
		_apply_spawn(rec)
	rv.door_open = state["door"]
	_on_rv_state(state["rv"])
	rv.global_position = (state["rv"] as Array)[0]
	rv.global_basis = Basis((state["rv"] as Array)[1])
	rv.apply_slow_snapshot(state["rv_slow"])
	_apply_trip_state(state["trip"])
	_set_rv_owner(state["rv_owner"])


func _sync_puppets() -> void:
	for existing: Player in puppets.values():
		if is_instance_valid(existing):
			existing.refresh_look()
	for peer: int in Session.players:
		if peer == local_id() or puppets.has(peer):
			continue
		var p := Player.new()
		p.puppet = true
		p.peer_id = peer
		p.name = "Player_%d" % peer
		p.rv = rv
		p.world_items = pg.items
		p.remote = _call_player
		p.input_enabled = false
		pg.add_child(p)
		p.global_position = pg.by_the_door()
		puppets[peer] = p
	for peer: int in puppets.keys():
		if not Session.players.has(peer):
			_on_player_left(peer)


func _on_player_left(peer: int) -> void:
	ready_peers.erase(peer)
	var p: Player = puppets.get(peer)
	if p:
		for i: int in Player.SLOTS:
			var item := p.slots[i]
			if item:
				p.slots[i] = null # What they carried drops where they stood.
				if is_host():
					item.release(pg.items, Transform3D(Basis.IDENTITY, p.global_position + Vector3.UP), Vector3.ZERO)
		puppets.erase(peer)
		p.queue_free()
	if is_host() and rv_owner == peer:
		_grant_rv(local_id())


# --- players ---------------------------------------------------------------------------------

@rpc("any_peer", "unreliable_ordered")
func _player_state(peer: int, s: Array) -> void:
	if is_host():
		if peer != _sender():
			return
		_to_all(&"_player_state", [peer, s], peer)
	var p: Player = puppets.get(peer)
	if p:
		p.apply_net_state(s)


## Something done to someone else's player (see Player._tell).
func _call_player(peer: int, method: StringName, args: Array) -> void:
	_send(peer, &"_player_call", [method, args])


@rpc("any_peer", "reliable")
func _player_call(method: StringName, args: Array) -> void:
	if not PLAYER_CALLS.has(method):
		return
	var me := pg.player
	match method:
		&"hurt":
			me.hurt(float(args[0]), String(args[1]))
		&"poison":
			me.poison()
		&"knock":
			me.knock(args[0])
		&"revive":
			me.revive(player_of(int(args[0])))
		&"say":
			me.say(String(args[0]))


# --- the RV ----------------------------------------------------------------------------------

func _set_simulated(on: bool) -> void:
	if on == rv.is_simulated:
		return
	rv.is_simulated = on
	if on:
		rv.freeze = false
		if _rv_target.size() > 3:
			rv.linear_velocity = _rv_target[2]
			rv.angular_velocity = _rv_target[3]
	else:
		rv.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rv.freeze = true


func _on_local_seat(seat: StringName) -> void:
	if seat == &"driver":
		_send(1, &"_ask_rv", [true])
	elif rv_owner == local_id() and not is_host():
		_send(1, &"_ask_rv", [false])


@rpc("any_peer", "reliable")
func _ask_rv(drive: bool) -> void:
	if not is_host():
		return
	var peer := _sender()
	if drive:
		_grant_rv(peer)
	elif rv_owner == peer:
		_grant_rv(local_id())


func _grant_rv(peer: int) -> void:
	for p: int in ready_peers:
		rpc_id(p, &"_set_rv_owner", peer)
	_set_rv_owner(peer)


@rpc("authority", "reliable")
func _set_rv_owner(peer: int) -> void:
	rv_owner = peer
	_set_simulated(peer == local_id())


## Host: everyone back to the last stop (`Playground.back_to_checkpoint`): the RV's where and
## how it is now, and each player comes back to it.
func back_to_checkpoint(message: String) -> void:
	if active and is_host():
		_to_all(&"_back_to_checkpoint", [message, rv.global_transform, rv.slow_snapshot()])


@rpc("authority", "reliable")
func _back_to_checkpoint(message: String, xf: Transform3D, slow: Array) -> void:
	rv.global_transform = xf
	rv.apply_slow_snapshot(slow)
	pg.return_to_rv(message)


## Whether everyone is down (`me` included), solo or online.
func everyone_down(me: Player) -> bool:
	if not me.downed:
		return false
	for p: Player in puppets.values():
		if is_instance_valid(p) and not p.downed:
			return false
	return true


## Host: takes the RV back (a tow, a restart).
func reclaim_rv() -> void:
	if active and is_host() and rv_owner != local_id():
		_grant_rv(local_id())


func _forward_op(op: StringName, args: Array) -> void:
	if op == &"push":
		_send(rv_owner, &"_rv_push", [args[0], args[1]])
	else:
		_send(rv_owner, &"_rv_op", [op, args])


@rpc("any_peer", "reliable")
func _rv_op(op: StringName, args: Array) -> void:
	if rv.is_simulated and RV.OPS.has(op):
		rv.apply_op(op, args)


@rpc("any_peer", "unreliable")
func _rv_push(force: Vector3, offset: Vector3) -> void:
	if rv.is_simulated and force.length() <= Player.PUSH_FORCE * 1.01:
		rv.apply_force(force, offset)


@rpc("any_peer", "unreliable_ordered")
func _rv_state(s: Array) -> void:
	if is_host():
		if _sender() != rv_owner:
			return
		_to_all(&"_rv_state", [s], rv_owner)
	_on_rv_state(s)


func _on_rv_state(s: Array) -> void:
	if rv.is_simulated:
		return # Stale, from before we took over.
	_rv_target = s
	_rv_age = 0.0
	rv.apply_snapshot(s)


@rpc("any_peer", "reliable")
func _rv_slow(s: Array) -> void:
	if is_host():
		if _sender() != rv_owner:
			return
		_to_all(&"_rv_slow", [s], rv_owner)
	if not rv.is_simulated:
		rv.apply_slow_snapshot(s)


@rpc("any_peer", "reliable")
func _door(open: bool) -> void:
	if is_host():
		_to_all(&"_door", [open], _sender())
	rv.door_open = open


## Follows the simulating machine's RV: extrapolated a little along its velocity, eased in.
func _follow_rv(dt: float) -> void:
	if _rv_target.is_empty():
		return
	_rv_age += dt
	var ahead := minf(_rv_age, 0.25)
	var target_pos: Vector3 = _rv_target[0] + (_rv_target[2] as Vector3) * ahead
	var target_rot: Quaternion = _rv_target[1]
	var w: Vector3 = _rv_target[3]
	if w.length() > 0.001:
		target_rot = Quaternion(w.normalized(), w.length() * ahead) * target_rot
	var cur := rv.global_transform
	if cur.origin.distance_to(target_pos) > 6.0:
		rv.global_transform = Transform3D(Basis(target_rot), target_pos)
		rv.reset_physics_interpolation()
		return
	var k := minf(1.0, dt * 12.0)
	var rot := cur.basis.get_rotation_quaternion().slerp(target_rot, k)
	rv.global_transform = Transform3D(Basis(rot), cur.origin.lerp(target_pos, k))


@rpc("any_peer", "reliable")
func _spawn_loose_request(kind: StringName, key: Variant, xf: Transform3D, velocity: Vector3, tire: float) -> void:
	if not is_host() or _sender() != rv_owner:
		return
	if kind == &"part" and rv.damage.parts.has(StringName(key)):
		rv.damage.make_debris(StringName(key), xf, velocity)
	elif kind == &"wheel":
		rv.damage.make_wheel(clampi(int(key), 0, 3), xf, velocity, tire)


func _ask_spawn_loose(kind: StringName, key: Variant, xf: Transform3D, velocity: Vector3) -> void:
	var tire := rv.damage.tires[int(key)] if kind == &"wheel" else 0.0
	rpc_id(1, &"_spawn_loose_request", kind, key, xf, velocity, tire)


# --- items -----------------------------------------------------------------------------------

func _register(item: Item) -> void:
	items[item.net_id] = item


func _on_item_ready(item: Item) -> void:
	if item.net_id != 0:
		_register(item)
	elif is_host():
		item.net_id = _new_id()
		_register(item) # Its spawn goes out on the next poll, once it has been placed.
	# (Clients don't make items of their own: the host does and sends them.)


func _on_item_freed(id: int) -> void:
	items.erase(id)
	_moving.erase(id)
	if _known.erase(id) and not _applying and active:
		_to_all(&"_item_gone", [id])


@rpc("any_peer", "reliable")
func _item_gone(id: int) -> void:
	if is_host():
		_to_all(&"_item_gone", [id], _sender())
	var item: Item = items.get(id)
	if item:
		_known.erase(id)
		_applying = true
		_forget_everywhere(item)
		item.free()
		_applying = false


## Where an item is, as a record: [Where, a, b, name, meta].
func _record(item: Item) -> Array:
	var meta := {}
	for k: StringName in META_KEYS:
		if item.has_meta(k):
			var v: Variant = item.get_meta(k)
			meta[k] = snappedf(float(v), 1.0) if k == &"cook" else v
	var name := item.display_name()
	var parent := item.get_parent()
	var winch := item.winch_of()
	if item.holder:
		return [Where.HELD, item.holder.peer_id, item.holder.slots.find(item), name, meta]
	if winch and parent == winch:
		return [Where.WINCH, rv.winches.find(winch), 0, name, meta]
	if winch and winch.state == RVWinch.State.ANCHORED:
		return [Where.ANCHORED, rv.winches.find(winch), winch.anchor_point(), name, meta]
	if parent == rv.stash:
		return [Where.STOWED, item.transform, 0, name, meta]
	if item.is_placed():
		return [Where.PLACED, item.global_transform, 0, name, meta]
	if parent is Grill:
		return [Where.GRILL, pg.get_path_to(parent), (parent as Grill).spot_of(item), name, meta]
	if parent is Animal:
		return [Where.CARRIED, parent.get_index(), 0, name, meta]
	return [Where.LOOSE, 0, 0, name, meta]


func _spawn_record(item: Item) -> Array:
	return [item.net_id, item.kind, _record(item), item.global_transform, item.linear_velocity]


func _apply_spawn(rec: Array) -> void:
	var id: int = rec[0]
	if not items.has(id):
		var kind: StringName = rec[1]
		var r: Array = rec[2]
		var meta: Dictionary = r[4]
		var item: Item
		if kind == &"rv_part" and rv.damage.parts.has(StringName(meta.get(&"part", &""))):
			item = ItemLibrary.create_from_mesh(kind, rv.damage.parts[StringName(meta[&"part"])].node.mesh, r[3])
		elif kind == &"rv_wheel":
			item = ItemLibrary.create_from_mesh(kind, (rv.wheels[clampi(int(meta.get(&"wheel", 0)), 0, 3)].visual as MeshInstance3D).mesh, r[3])
		elif ItemLibrary.DEFS.has(kind):
			item = ItemLibrary.create(kind)
		else:
			return
		item.net_id = id
		_applying = true
		pg.items.add_child(item)
		item.global_transform = rec[3]
		_applying = false
	_apply_record(id, rec[2], rec[3], rec[4])


@rpc("any_peer", "reliable")
func _item_spawn(rec: Array) -> void:
	if not is_host():
		_apply_spawn(rec)


@rpc("any_peer", "reliable")
func _item_state(id: int, r: Array, xf: Transform3D, velocity: Vector3) -> void:
	var from := _sender()
	if is_host():
		var item: Item = items.get(id)
		if item == null:
			return
		var mine: Array = _known.get(id, [])
		var theirs := int(r[0]) == Where.HELD and int(r[1]) == from
		var taken := not mine.is_empty() and int(mine[0]) == Where.HELD and int(mine[1]) != from
		if theirs and taken:
			# Someone else got there first: put the sender right.
			rpc_id(from, &"_item_state", id, mine, item.global_transform, Vector3.ZERO)
			return
		_apply_record(id, r, xf, velocity)
		_to_all(&"_item_state", [id, r, xf, velocity], from)
	else:
		_apply_record(id, r, xf, velocity)


## Puts an item where a record says.
func _apply_record(id: int, r: Array, xf: Transform3D, velocity: Vector3) -> void:
	var item: Item = items.get(id)
	if item == null:
		return
	_applying = true
	_known[id] = r
	item.def["name"] = r[3]
	var where: int = r[0]
	var holder := player_of(int(r[1])) if where == Where.HELD else null
	if item.holder != holder or where != Where.HELD:
		_forget_everywhere(item)
	match where:
		Where.HELD:
			if holder:
				var slot := int(r[2])
				if slot < 0 or slot >= Player.SLOTS or (holder.slots[slot] != null and holder.slots[slot] != item):
					slot = holder.slots.find(null)
				if slot >= 0:
					holder.slots[slot] = item
					item.grab(holder, holder.hand)
					item.visible = slot == holder.selected
		Where.STOWED:
			item.stow(rv, r[1])
		Where.PLACED:
			item.place(pg.items, r[1])
		Where.GRILL:
			var grill := pg.get_node_or_null(r[1]) as Grill
			if grill and int(r[2]) >= 0:
				grill.put(item, int(r[2]))
		Where.CARRIED:
			var animal := pg.wildlife.get_child(int(r[1])) as Eagle if int(r[1]) < pg.wildlife.get_child_count() else null
			if animal:
				animal.carry(item)
		Where.WINCH:
			rv.winches[int(r[1])].stow_hook()
		Where.ANCHORED:
			item.holder = null
			rv.winches[int(r[1])].anchor(r[2])
		_:
			if item.get_parent() != pg.items or item.freeze:
				item.release(pg.items, xf, velocity)
			if not is_host():
				item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				item.freeze = true # The host simulates loose things.
	# Meta last: moving an item clears its storage slot.
	if not (r[4] as Dictionary).has(&"slot"):
		item.remove_meta(&"slot")
	for k: Variant in (r[4] as Dictionary):
		item.set_meta(StringName(k), r[4][k])
	if item.kind == &"patty":
		ItemLibrary.tint(item, ItemLibrary.patty_color(float(item.get_meta(&"cook", 0.0))))
	_applying = false


func _forget_everywhere(item: Item) -> void:
	for p: Player in [pg.player] + puppets.values():
		p.forget(item)
	item.holder = null
	item.visible = true


## Sends what changed here: new items (host) and items that moved on.
func _poll_items() -> void:
	for id: int in items.keys():
		var item: Item = items[id]
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var r := _record(item)
		if not _known.has(id):
			_known[id] = r
			if is_host():
				_to_all(&"_item_spawn", [_spawn_record(item)])
			continue
		if r != _known[id]:
			_known[id] = r
			_to_all(&"_item_state", [id, r, item.global_transform, item.linear_velocity])
			if int(r[0]) == Where.LOOSE and not is_host():
				item.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				item.freeze = true # Thrown or dropped: the host takes it from here.


## Host: where loose things are rolling to.
func _send_item_moves() -> void:
	var batch: Array = []
	for id: int in items:
		var item := items[id]
		if not is_instance_valid(item) or int(_known.get(id, [Where.HELD])[0]) != Where.LOOSE or item.freeze:
			continue
		var moving := item.linear_velocity.length_squared() > 0.0025 or item.angular_velocity.length_squared() > 0.01
		if moving or _moving.has(id):
			batch.append([id, item.global_position, item.global_basis.get_rotation_quaternion()])
		if moving:
			_moving[id] = true
		else:
			_moving.erase(id)
	if not batch.is_empty():
		_to_all(&"_item_moves", [batch])


@rpc("authority", "unreliable_ordered")
func _item_moves(batch: Array) -> void:
	for e: Array in batch:
		var item: Item = items.get(int(e[0]))
		if item and item.freeze and item.holder == null and int(_known.get(int(e[0]), [Where.HELD])[0]) == Where.LOOSE:
			item.global_transform = Transform3D(Basis(e[2] as Quaternion), e[1])


# --- wildlife --------------------------------------------------------------------------------

func _send_animals() -> void:
	var batch: Array = []
	for c: Node in pg.wildlife.get_children():
		var a := c as Animal
		if a and a.process_mode != Node.PROCESS_MODE_DISABLED:
			batch.append([a.get_index(), a.net_state()])
	if not batch.is_empty():
		_to_all(&"_animals", [batch])


@rpc("authority", "unreliable_ordered")
func _animals(batch: Array) -> void:
	for e: Array in batch:
		if int(e[0]) < pg.wildlife.get_child_count():
			var a := pg.wildlife.get_child(int(e[0])) as Animal
			if a:
				a.apply_net_state(e[1], player_of)


func _send_spray(animal: Animal, from: Vector3) -> void:
	rpc_id(1, &"_spray", animal.get_index(), from)


@rpc("any_peer", "reliable")
func _spray(index: int, from: Vector3) -> void:
	if is_host() and index < pg.wildlife.get_child_count():
		(pg.wildlife.get_child(index) as Animal).sprayed(from)


# --- the trip --------------------------------------------------------------------------------

func _trip_state() -> Array:
	return [pg.trip.checkpoint, pg.trip.elapsed, pg.trip.distance_driven, pg.trip.stalls, pg.trip.is_finished, pg.trip.hours]


func _apply_trip_state(s: Array) -> void:
	pg.trip.checkpoint = s[0]
	pg.trip.elapsed = s[1]
	pg.trip.distance_driven = s[2]
	pg.trip.stalls = s[3]
	pg.trip.is_finished = s[4]
	pg.trip.hours = s[5]


@rpc("authority", "unreliable_ordered")
func _trip(s: Array) -> void:
	_apply_trip_state(s)


@rpc("authority", "reliable")
func _trip_reached(i: int) -> void:
	pg.trip.reach(i)


# --- each tick ---------------------------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if not active or not pg.is_spawned:
		return
	if not rv.is_simulated:
		_follow_rv(dt)
	_t_snap += dt
	if _t_snap >= SNAPSHOT_INTERVAL:
		_t_snap = 0.0
		_to_all(&"_player_state", [local_id(), pg.player.net_state()])
		if rv.is_simulated:
			_to_all(&"_rv_state", [rv.snapshot()])
	_t_slow += dt
	if _t_slow >= SLOW_INTERVAL:
		_t_slow = 0.0
		if rv.is_simulated:
			_to_all(&"_rv_slow", [rv.slow_snapshot()])
	_t_items += dt
	if _t_items >= ITEM_INTERVAL:
		_t_items = 0.0
		_poll_items()
		if is_host():
			_send_item_moves()
	if not is_host():
		return
	_t_animals += dt
	if _t_animals >= ANIMAL_INTERVAL:
		_t_animals = 0.0
		_send_animals()
	_t_trip += dt
	if _t_trip >= TRIP_INTERVAL:
		_t_trip = 0.0
		_to_all(&"_trip", [_trip_state()])
