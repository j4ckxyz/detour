class_name ItemLibrary
extends RefCounted
## Every item kind: name, model, mass, how it's held. `create()` builds a ready `Item`.
## Models come from `assets/models/props/` (built by tools/assets/blender/build_props.py).

const MODELS := "res://assets/models/props/%s.glb"
const SMALL_HOLD := Transform3D(Basis.IDENTITY, Vector3(0.24, -0.22, -0.45))

## kind → {name, model, mass, hold (camera-space transform), two_handed, stow (which RV
## storage slots take it: see RV.STORAGE)}
static var DEFS: Dictionary[StringName, Dictionary] = {
	# (The model is 5 m by 0.3 m; it's stretched to the plank's real size.)
	&"plank": {"stow": &"plank", "name": "Plank", "model": "plank", "mass": 15.0, "two_handed": true, "reach": 4.5,
		"stretch": Vector3(PLANK_LENGTH / 5.0, 1.0, PLANK_WIDTH / 0.3),
		"hold": Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.36, -0.48, -PLANK_LENGTH * 0.5))},
	&"jerrycan": {"stow": &"can", "name": "Jerry can", "model": "jerrycan", "mass": 20.0, "two_handed": true,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.3, -0.62, -0.5))},
	&"spare_tire": {"stow": &"tire", "name": "Spare tire", "model": "sparetire", "mass": 25.0, "two_handed": true,
		"hold": Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, -0.4, -0.8))},
	&"scrap_metal": {"stow": &"medium", "name": "Scrap metal", "model": "scrapmetal", "mass": 3.0,
		"hold": Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0.22, -0.3, -0.6))},
	&"motor_oil": {"stow": &"medium", "name": "Motor oil", "model": "oilbottle", "mass": 1.0, "hold": SMALL_HOLD},
	&"burger": {"stow": &"food", "name": "Burger", "model": "burger", "mass": 0.3, "hold": SMALL_HOLD, "heal": 30.0},
	&"patty": {"stow": &"food", "name": "Frozen patty", "model": "@patty", "mass": 0.2, "hold": SMALL_HOLD},
	&"soda": {"stow": &"drink", "name": "Soda", "model": "@soda", "mass": 0.35, "hold": SMALL_HOLD, "heal": 10.0},
	&"antidote": {"stow": &"small", "name": "Antidote", "model": "antidote", "mass": 0.2, "hold": SMALL_HOLD},
	&"epipen": {"stow": &"small", "name": "EpiPen", "model": "epipen", "mass": 0.1, "hold": SMALL_HOLD},
	&"bear_spray": {"stow": &"small", "name": "Bear spray", "model": "bearspray", "mass": 0.4, "hold": SMALL_HOLD},
	&"first_aid": {"stow": &"medium", "name": "First-aid kit", "model": "firstaidkit", "mass": 1.5,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.25, -0.38, -0.55))},
	&"winch_remote": {"stow": &"tool", "name": "Winch remote", "model": "winchremote", "mass": 0.3, "hold": SMALL_HOLD,
		"no_throw": true, "seated": true},
	&"hammer": {"stow": &"tool", "name": "Repair hammer", "model": "kenney:survival/hammer", "mass": 1.2, "scale": 2.6,
		"hold": Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.26, -0.3, -0.5))},
	&"drill": {"stow": &"tool", "name": "Power drill", "model": "drill", "mass": 1.8,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.24, -0.38, -0.45)) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)},
	&"rv_part": {"name": "RV part", "model": "", "mass": 12.0, "two_handed": true,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, -1.0))},
	&"rv_wheel": {"stow": &"tire", "name": "Wheel", "model": "", "mass": 30.0, "two_handed": true,
		"hold": Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, -0.5, -0.9))},
	&"winch_hook": {"name": "Winch hook", "model": "@hook", "mass": 2.0,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.25, -0.3, -0.55))},
	&"tape": {"stow": &"tape", "name": "Cassette", "model": "@cassette", "mass": 0.1, "hold": SMALL_HOLD},
}
## A full jerry can, litres.
const JERRY_CAN_LITRES := 20.0
## Must match rvgen::route::PLANK_LENGTH: a gap is narrower than a plank by at least 1.6 m.
const PLANK_LENGTH := 6.0
const PLANK_WIDTH := 0.5
## How far ahead of you a plank's near end can be laid, metres.
const PLANK_REACH := 5.5
## Laying a plank: the ground under its line is sampled every `PLANK_STEP` metres, from
## `PLANK_FROM` (a little behind you) to the far end of the furthest plank. Ends rest
## `PLANK_STEP` in from the tips. A plank needs `PLANK_HOLD` metres of ground under each end to be
## laid at all and `PLANK_SECURE` to be sure to stay (between the two, it's laid loose and may
## slip off); a gap is what it's laid over if there's `PLANK_VOID` metres under it; it won't
## climb more than `PLANK_MAX_RISE` end to end across a gap, or lie on ground steeper than
## `PLANK_MAX_SLOPE`, or ride up over a bump higher than `PLANK_MAX_LIFT`.
const PLANK_STEP := 0.25
const PLANK_FROM := -1.0
const PLANK_HOLD := 0.3
const PLANK_SECURE := 0.6
const PLANK_VOID := 0.6
const PLANK_MAX_RISE := 1.6
const PLANK_MAX_SLOPE := 0.6
const PLANK_MAX_LIFT := 0.6
## Near the RV a plank lines up with its wheels: within this far (m) of it, less than this far
## off its heading (radians) and this far (m) from a wheel track.
const PLANK_SNAP_RANGE := 30.0
const PLANK_SNAP_ANGLE := deg_to_rad(28.0)
const PLANK_SNAP_ACROSS := 1.3
## Nothing under a sample: the ray found no ground.
const NO_GROUND := -1.0e6
## Bear spray: puffs per can, and the cone it reaches (metres, cos of the half angle).
const SPRAY_PUFFS := 6
const SPRAY_RANGE := 7.0
const SPRAY_CONE := 0.8
const FIRST_AID_HEAL := 60.0
## A patty's cooking (seconds on a grill): thawed, cooked, burnt.
const PATTY_THAWED := 6.0
const PATTY_COOKED := 14.0
const PATTY_BURNT := 32.0

static var _meshes: Dictionary[String, Mesh] = {}


## An item made from an existing mesh (a part that fell off the RV, a wheel).
static func create_from_mesh(kind: StringName, mesh: Mesh, display: String) -> Item:
	var def: Dictionary = DEFS[kind].duplicate()
	def["name"] = display
	var item := Item.new()
	item.kind = kind
	item.def = def
	item.name = String(kind)
	item.mass = def["mass"]
	_dress(item, mesh)
	return item


## A cassette with tape `id` on it (see `Tapes`).
static func create_tape(id: int) -> Item:
	var item := create(&"tape")
	item.set_meta(&"tape", clampi(id, 0, Tapes.COUNT - 1))
	refresh_tape(item)
	return item


## Names a cassette after the tape on it (also after a save or the network gave it its number).
static func refresh_tape(item: Item) -> void:
	item.def["name"] = "Cassette: %s" % Tapes.title(int(item.get_meta(&"tape", 0)))


static func create(kind: StringName) -> Item:
	var def: Dictionary = DEFS[kind].duplicate() # Per item: some change (a jerry can's fill).
	var item := Item.new()
	item.kind = kind
	item.def = def
	item.name = String(kind)
	item.mass = def["mass"]
	_dress(item, _mesh(def["model"]), def.get("scale", 1.0), def.get("stretch", Vector3.ONE))
	return item


## Gives an item its look and a box collider fitted to the mesh.
static func _dress(item: Item, mesh: Mesh, scale: float = 1.0, stretch: Vector3 = Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var size := Vector3.ONE * scale * stretch
	mi.scale = size
	item.add_child(mi)
	var aabb := mesh.get_aabb()
	aabb = AABB(aabb.position * size, aabb.size * size)
	item.base_offset = -aabb.position.y
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.03)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = aabb.get_center()
	item.add_child(shape)


## What Use does for a kind, as `func(item: Item, player: Player) -> bool`, or an invalid
## Callable if it has no use of its own (yet).
static func use_action(kind: StringName) -> Callable:
	match kind:
		&"burger", &"soda":
			return func(item: Item, player: Player) -> bool:
				player.eat(item, item.def["heal"])
				return true
		&"patty":
			return func(item: Item, player: Player) -> bool:
				var cook := float(item.get_meta(&"cook", 0.0))
				if cook < PATTY_THAWED:
					player.say("Frozen solid. You nearly broke a tooth.")
					return false
				if cook < PATTY_COOKED:
					player.eat(item, 5.0)
					player.say("Still raw in the middle. Not great.")
				elif cook < PATTY_BURNT:
					player.did.emit(&"cooked_patty")
					player.eat(item, 40.0)
				else:
					player.eat(item, 10.0)
					player.say("Crunchy.")
				return true
		&"first_aid":
			return func(item: Item, player: Player) -> bool:
				if player.health >= Player.MAX_HEALTH:
					player.say("You're not hurt.")
					return false
				player.heal(FIRST_AID_HEAL)
				player.consume(item)
				return true
		&"antidote":
			return func(item: Item, player: Player) -> bool:
				if player.venom <= 0.0:
					player.say("You feel fine.")
					return false
				player.venom = 0.0
				player.did.emit(&"antidote")
				player.consume(item)
				player.say("The venom's gone.")
				return true
		&"epipen":
			return func(_item: Item, player: Player) -> bool:
				player.say("Not now.")
				return false
		&"bear_spray":
			return func(item: Item, player: Player) -> bool:
				var puffs := int(item.get_meta(&"puffs", SPRAY_PUFFS))
				if puffs <= 0:
					player.say("Empty.")
					return false
				item.set_meta(&"puffs", puffs - 1)
				item.def["name"] = "Bear spray (%d)" % (puffs - 1) if puffs > 1 else "Empty bear spray"
				spray(player)
				return true
		&"winch_hook":
			return func(item: Item, player: Player) -> bool:
				var anchor: Variant = find_anchor(player)
				if anchor == null:
					return false
				player.held = null
				item.holder = null
				item.winch_of().anchor(anchor["position"])
				return true
		&"hammer":
			return func(_item: Item, player: Player) -> bool:
				if player.is_swinging():
					return false
				var aim := player.aim_rv()
				if aim.get("kind") != "part":
					return false
				var d := player.rv.damage
				var id: StringName = aim["id"]
				var part: RVDamage.Part = d.parts[id]
				if part.attached and part.hp >= RVDamage.FULL:
					return false
				var scrap := player.find_item(&"scrap_metal")
				if scrap == null:
					player.say("Nothing to patch it with.")
					return false
				player.consume(scrap)
				# A few good whacks, and it's patched.
				player.swing(struck_at(player, float(aim["distance"])), 3, func() -> void:
					player.rv.op(&"patch_part", [id])
					player.did.emit(&"repair"))
				return true
		&"rv_part":
			return func(item: Item, player: Player) -> bool:
				var aim := player.aim_rv()
				var id: StringName = item.get_meta(&"part", &"")
				if aim.get("kind") != "part" or aim["id"] != id or player.rv.damage.parts[id].attached:
					return false
				player.consume(item)
				player.rv.op(&"refit_part", [id])
				player.did.emit(&"repair")
				Sfx.cue(player, "rv/part_fall", player.camera.global_position + -player.camera.global_basis.z * 0.8, -12.0, 4.0, 30.0)
				return true
		&"spare_tire", &"rv_wheel":
			return func(item: Item, player: Player) -> bool:
				var aim := player.aim_rv()
				if aim.get("kind") != "wheel":
					return false
				var d := player.rv.damage
				var i: int = aim["id"]
				var tire := float(item.get_meta(&"tire", RVDamage.FULL))
				if not d.wheel_on[i]:
					player.rv.op(&"mount_wheel", [i, tire])
				elif d.tires[i] <= 0.0:
					player.rv.op(&"swap_tire", [i])
				else:
					return false
				player.consume(item)
				player.did.emit(&"tire_fitted")
				player.did.emit(&"repair")
				Sfx.cue(player, "tools/winch_hook", player.camera.global_position + -player.camera.global_basis.z * 0.8, -10.0, 4.0, 30.0)
				player.say("Wheel on. It's hanging loose.")
				return true
		&"motor_oil":
			return func(item: Item, player: Player) -> bool:
				if player.aim_rv().get("kind") != "engine" or player.rv.damage.oil > 0.95:
					return false
				player.rv.op(&"add_oil")
				player.did.emit(&"repair")
				Sfx.cue(player, "tools/pour", player.camera.global_position, -8.0, 4.0, 30.0)
				player.consume(item)
				return true
		&"jerrycan":
			return func(item: Item, player: Player) -> bool:
				var litres := float(item.get_meta(&"fuel", JERRY_CAN_LITRES))
				if player.aim_rv().get("kind") != "fuel" or litres <= 0.0:
					return false
				var poured := minf(litres, RVDamage.TANK - player.rv.damage.fuel)
				player.rv.op(&"add_fuel", [poured])
				if poured > 0.0:
					player.did.emit(&"can_poured")
					player.did.emit(&"repair")
					Sfx.cue(player, "tools/pour", player.camera.global_position, -8.0, 4.0, 30.0)
				item.set_meta(&"fuel", litres - poured)
				item.def["name"] = "Jerry can (%d L)" % roundi(litres - poured) if litres - poured > 0.5 else "Empty jerry can"
				return poured > 0.0
		&"plank":
			return func(item: Item, player: Player) -> bool:
				var plan := plank_plan(player)
				if plan.is_empty():
					return false
				var xf: Transform3D = plan["xf"]
				player.held = null
				if plan["secure"]:
					item.place(player.world_items, xf)
				else:
					item.lay_loose(player.world_items, xf) # Barely on: it may hold, or slip off.
				player.did.emit(&"plank")
				Sfx.cue(player, "tools/plank_lay", xf.origin, -6.0, 5.0, 40.0)
				return true
	return Callable()


## What holding Use does for a kind, as `func(item, player) -> float` (seconds until the next
## tick), or an invalid Callable.
static func hold_action(kind: StringName) -> Callable:
	if kind == &"drill":
		return func(_item: Item, player: Player) -> float:
			var aim := player.aim_rv()
			if aim.get("kind") != "wheel":
				return 0.0
			var d := player.rv.damage
			var i: int = aim["id"]
			if not d.wheel_on[i] or d.bolts[i] >= RVDamage.BOLTS:
				return 0.0
			player.rv.op(&"tighten_bolt", [i])
			Sfx.cue(player, "tools/drill_bolt", player.camera.global_position + -player.camera.global_basis.z * 0.8, -7.0, 4.0, 30.0)
			if not player.rv.is_simulated:
				d.bolts[i] += 1 # Shown straight away; the RV's own machine confirms.
			return 0.45 # One bolt at a time.
	return Callable()


## What Use would do right now, for the HUD ("" if nothing). Only ever what's in reach this
## moment: it never says where to go or what to look for (working that out is the game).
static func use_hint(item: Item, player: Player) -> String:
	var use := Controls.prompt(&"use_item")
	var aim := player.aim_rv() if player.rv else {}
	var d: RVDamage = player.rv.damage if player.rv else null
	match item.kind:
		&"hammer":
			if aim.get("kind") == "part":
				var part: RVDamage.Part = d.parts[aim["id"]]
				if not part.attached:
					return use + " rebuild"
				if part.hp < RVDamage.FULL:
					return use + " patch"
		&"rv_part":
			if aim.get("kind") == "part" and aim["id"] == item.get_meta(&"part", &"") and not d.parts[aim["id"]].attached:
				return use + " fit"
		&"spare_tire", &"rv_wheel":
			if aim.get("kind") == "wheel":
				var i: int = aim["id"]
				if not d.wheel_on[i] or d.tires[i] <= 0.0:
					return use + " fit"
		&"drill":
			if aim.get("kind") == "wheel" and d.wheel_on[aim["id"]] and d.bolts[aim["id"]] < RVDamage.BOLTS:
				return "hold " + use
		&"motor_oil":
			if aim.get("kind") == "engine" and d.oil <= 0.95:
				return use + " pour"
		&"jerrycan":
			if aim.get("kind") == "fuel" and float(item.get_meta(&"fuel", JERRY_CAN_LITRES)) > 0.0:
				return use + " pour"
		&"burger":
			return use + " eat"
		&"soda":
			return use + " drink"
		&"patty":
			if float(item.get_meta(&"cook", 0.0)) >= PATTY_THAWED:
				return use + " eat"
		&"first_aid", &"antidote":
			return use + " use"
		&"bear_spray":
			return use + " spray"
		&"winch_hook":
			if find_anchor(player) != null:
				return use + " hook on"
		&"plank":
			var plan := plank_plan(player)
			if not plan.is_empty():
				return use + (" lay" if plan["secure"] else " lay (barely on)")
		&"winch_remote":
			return "%s in · %s out · %s other winch" % [use, Controls.prompt(&"throw_item"), Controls.prompt(&"winch_select")]
	return ""


## A puff of bear spray from the player's hand: an orange cloud, and every animal in the cone
## is scared off.
static func spray(player: Player) -> void:
	var from := player.camera.global_position
	var forward := -player.camera.global_basis.z
	Sfx.cue(player, "items/spray", from + forward * 0.5, -3.0, 6.0, 50.0)
	for n: Node in player.get_tree().get_nodes_in_group(&"wildlife"):
		var animal := n as Node3D
		var to := animal.global_position + Vector3.UP * 0.5 - from
		var d := to.length()
		if d < SPRAY_RANGE and (d < 1.2 or to.dot(forward) / d > SPRAY_CONE):
			animal.call(&"spray_from", player.global_position)
			if animal is Bear:
				player.did.emit(&"sprayed_bear")
	var cloud := CPUParticles3D.new()
	cloud.one_shot = true
	cloud.local_coords = true # (World-space particles get culled away from the origin.)
	cloud.explosiveness = 0.8
	cloud.amount = 40
	cloud.lifetime = 1.2
	cloud.direction = Vector3.FORWARD
	cloud.spread = 14.0
	cloud.initial_velocity_min = 5.0
	cloud.initial_velocity_max = 7.0
	cloud.damping_min = 4.0
	cloud.damping_max = 6.0
	cloud.gravity = Vector3(0.0, 0.3, 0.0)
	cloud.scale_amount_min = 0.3
	cloud.scale_amount_max = 0.9
	var puff := SphereMesh.new()
	puff.radius = 0.25
	puff.height = 0.5
	puff.radial_segments = 6
	puff.rings = 3
	var mist := StandardMaterial3D.new()
	mist.albedo_color = Color(1.0, 0.45, 0.15, 0.35)
	mist.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mist.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = mist
	cloud.mesh = puff
	player.get_tree().current_scene.add_child(cloud)
	cloud.global_transform = Transform3D(player.camera.global_basis, from + forward * 0.6 + Vector3.DOWN * 0.15)
	cloud.emitting = true
	cloud.finished.connect(cloud.queue_free)


## Where a hammer aimed at a panel `distance` metres off meets it: the RV's skin under the
## crosshair (so the sparks fly off its surface), or about that far along the view.
static func struck_at(player: Player, distance: float) -> Vector3:
	var cam := player.camera.global_transform
	var query := PhysicsRayQueryParameters3D.create(cam.origin, cam.origin - cam.basis.z * (distance + 0.8))
	query.exclude = [player.get_rid()]
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] == player.rv:
		distance = cam.origin.distance_to(hit["position"])
	# A hand's breadth short: the body's collision boxes sit inside its skin in places.
	return cam.origin - cam.basis.z * maxf(0.3, distance - 0.15)


## A winch anchor under the crosshair within reach: {position, what}, or null.
static func find_anchor(player: Player) -> Variant:
	if player.inside:
		return null
	var from := player.camera.global_position
	var to := from - player.camera.global_basis.z * 2.8
	var query := PhysicsRayQueryParameters3D.create(from, to, TerrainStreamer.WORLD_LAYER)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or int(hit["shape"]) == TerrainStreamer.GROUND_SHAPE or hit["collider"] is Item:
		return null
	return {"position": hit["position"], "what": "rock or tree"}


## Where a held plank would go, or null: see `plank_plan`.
static func plank_placement(player: Player) -> Variant:
	var plan := plank_plan(player)
	return plan["xf"] if not plan.is_empty() else null


## Where a held plank would go and how: {"xf": its transform, "secure": it's sure to stay,
## "bridging": it spans a gap} (or {} if there's nowhere). It lies along your view, level, its
## ends on the ground: over a gap in front of you it's centred on the gap and lies across it
## (not down into it, where you're looking), on the ground otherwise, and carries on from
## another plank's end if you're looking at one. Near the RV it lines up with a wheel track
## (see `PLANK_SNAP_RANGE`), so two planks make a road for its wheels.
static func plank_plan(player: Player) -> Dictionary:
	if player.inside:
		return {}
	var space := player.get_world_3d().direct_space_state
	var cam := player.camera.global_transform
	var view := -cam.basis.z
	if view.y > 0.35:
		return {} # Looking at the sky.
	var ray := PhysicsRayQueryParameters3D.create(cam.origin, cam.origin + view * (PLANK_REACH + 3.0), TerrainStreamer.WORLD_LAYER)
	var hit := space.intersect_ray(ray)
	var other := hit.get("collider") as Item if not hit.is_empty() else null
	if other and other.is_placed() and other.kind == &"plank":
		return _plank_continued(space, other, view)
	var dir := Vector3(view.x, 0.0, view.z)
	if dir.length_squared() < 0.01:
		dir = Vector3(-cam.basis.y.x, 0.0, -cam.basis.y.z) # Looking straight down: the way your head points.
	dir = dir.normalized()
	var origin := player.global_position
	var aim := (hit["position"] as Vector3) if not hit.is_empty() else origin + dir * 3.0
	var plan := _plank_along(space, origin, dir, aim)
	if plan.is_empty():
		return plan
	var snapped := _plank_lined_up(player, space, plan, origin, aim)
	return plan if snapped.is_empty() else snapped


## A plank laid from the end of the placed plank `other`, in its direction.
static func _plank_continued(space: PhysicsDirectSpaceState3D, other: Item, view: Vector3) -> Dictionary:
	var axis := other.global_basis.x.normalized()
	if axis.dot(view) < 0.0:
		axis = -axis
	var forward := Vector3(axis.x, 0.0, axis.z).normalized()
	var end := other.global_position + axis * (PLANK_LENGTH * 0.5)
	var center := end + forward * (PLANK_LENGTH * 0.5 - 0.05)
	var half := forward * (PLANK_LENGTH * 0.5 - 0.1)
	var ends: Array[Vector3] = []
	for e: Vector3 in [center - half, center + half]:
		var down := PhysicsRayQueryParameters3D.create(e + Vector3.UP * 1.2, e + Vector3.DOWN * 2.5, TerrainStreamer.WORLD_LAYER)
		var h := space.intersect_ray(down)
		if h.is_empty():
			return {} # That end would hang in the air.
		ends.append(h["position"])
	# A board rests on the highest points under it: lift it over any bump between the ends.
	var lift := 0.0
	for k: int in range(1, 6):
		var along := ends[0].lerp(ends[1], k / 6.0)
		var probe := PhysicsRayQueryParameters3D.create(along + Vector3.UP * 1.5, along + Vector3.DOWN * 1.0, TerrainStreamer.WORLD_LAYER)
		var h := space.intersect_ray(probe)
		if not h.is_empty():
			lift = maxf(lift, (h["position"] as Vector3).y - along.y)
	return {"xf": _plank_transform(ends[0], ends[1], lift), "secure": true, "bridging": false}


## The best way to lay a plank along the line from `origin` towards `dir` (horizontal), with
## `aim` where you're pointing: over the gap if there is one in reach, else on the ground there.
static func _plank_along(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, aim: Vector3) -> Dictionary:
	# The ground under the line, nearest the top: a ravine deeper than 8 m reads as no ground.
	var steps := int(ceil((PLANK_REACH + PLANK_LENGTH - PLANK_FROM) / PLANK_STEP)) + 1
	var ground := PackedFloat32Array()
	ground.resize(steps)
	for i: int in steps:
		var at := origin + dir * (PLANK_FROM + i * PLANK_STEP)
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 8.0, TerrainStreamer.WORLD_LAYER)
		var h := space.intersect_ray(query)
		ground[i] = (h["position"] as Vector3).y if not h.is_empty() else NO_GROUND
	var span := int(roundf(PLANK_LENGTH / PLANK_STEP))
	var aimed := clampf((aim - origin).dot(dir), 1.0, PLANK_REACH + PLANK_LENGTH * 0.5)
	var bridge := {}
	var lie := {}
	for j: int in range(0, mini(int((PLANK_REACH - PLANK_FROM) / PLANK_STEP), steps - span - 2) + 1):
		var a := j + 1 # Where each end rests: a step in from the tips.
		var b := j + span - 1
		if ground[a] <= NO_GROUND or ground[b] <= NO_GROUND:
			continue
		var y0 := ground[a]
		var y1 := ground[b]
		if absf(y1 - y0) > PLANK_MAX_SLOPE * (b - a) * PLANK_STEP:
			continue # Too steep even to lie on.
		var lift := 0.0
		for k: int in range(a, b + 1):
			if ground[k] > NO_GROUND:
				lift = maxf(lift, ground[k] - lerpf(y0, y1, float(k - a) / float(b - a)))
		if lift > PLANK_MAX_LIFT:
			continue # A boulder in the way.
		# How far under the plank the ground falls, and how much of it each end rests on.
		var void_depth := 0.0
		var bearing: Array[float] = [0.0, 0.0]
		for k: int in range(a, b + 1):
			var line := lerpf(y0, y1, float(k - a) / float(b - a)) + lift
			void_depth = maxf(void_depth, line - ground[k] if ground[k] > NO_GROUND else 8.0)
		for end: int in 2:
			var run := 0
			for n: int in range(b - a + 1):
				var k := a + n if end == 0 else b - n
				var line := lerpf(y0, y1, float(k - a) / float(b - a)) + lift
				if ground[k] > NO_GROUND and ground[k] >= line - 0.3:
					run += 1
				else:
					break
			bearing[end] = PLANK_STEP * (run + 0.5) if run > 0 else 0.0
		var center := PLANK_FROM + (j + span * 0.5) * PLANK_STEP
		var q := minf(bearing[0], bearing[1])
		if void_depth >= PLANK_VOID and absf(y1 - y0) > PLANK_MAX_RISE:
			continue # Spanning a gap it won't climb, just lying on the ground it will.
		var cand := {"a": a, "b": b, "y0": y0, "y1": y1, "lift": lift, "q": q, "center": center}
		if void_depth >= PLANK_VOID:
			if q >= PLANK_HOLD and (bridge.is_empty() or q > float(bridge["q"]) + 0.01
					or (absf(q - float(bridge["q"])) <= 0.01 and absf(center - aimed) < absf(float(bridge["center"]) - aimed))):
				bridge = cand
		elif lie.is_empty() or absf(center - aimed) < absf(float(lie["center"]) - aimed):
			lie = cand
	# Across a gap if you're pointing down into it (or a secure crossing is near where you're
	# pointing), else on the ground where you point.
	var pick := lie
	var bridging := false
	if not bridge.is_empty() and (lie.is_empty() or aim.y < origin.y - 0.6
			or (float(bridge["q"]) >= PLANK_SECURE and absf(float(bridge["center"]) - aimed) <= 4.0)):
		pick = bridge
		bridging = true
	if pick.is_empty():
		return {}
	var e0 := origin + dir * (PLANK_FROM + int(pick["a"]) * PLANK_STEP)
	var e1 := origin + dir * (PLANK_FROM + int(pick["b"]) * PLANK_STEP)
	e0.y = pick["y0"]
	e1.y = pick["y1"]
	return {"xf": _plank_transform(e0, e1, float(pick["lift"])), "bridging": bridging,
		"secure": not bridging or float(pick["q"]) >= PLANK_SECURE}


## A plank resting on `e0` and `e1` (its ends' support points), lifted `lift` over a bump.
static func _plank_transform(e0: Vector3, e1: Vector3, lift: float) -> Transform3D:
	var axis_x := (e1 - e0).normalized()
	var up := axis_x.cross(Vector3.UP).cross(axis_x).normalized()
	if up.y < 0.0:
		up = -up
	var z := axis_x.cross(up)
	return Transform3D(Basis(axis_x, up, z), (e0 + e1) * 0.5 + Vector3.UP * lift + up * 0.04)


## The same plank lined up with a wheel track of the RV if it's near enough and roughly
## pointing the way it does (or {}): so two planks laid one after the other are a road for its
## wheels, without measuring by eye. Only when it still lies as well as the plank as aimed.
static func _plank_lined_up(player: Player, space: PhysicsDirectSpaceState3D, plan: Dictionary, origin: Vector3, aim: Vector3) -> Dictionary:
	var rv := player.rv
	if rv == null:
		return {}
	var xf: Transform3D = plan["xf"]
	var center := xf.origin
	if center.distance_to(rv.global_position) > PLANK_SNAP_RANGE:
		return {}
	var heading := -rv.global_basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		return {}
	heading = heading.normalized()
	var axis := Vector3(xf.basis.x.x, 0.0, xf.basis.x.z).normalized()
	if axis.dot(heading) < 0.0:
		heading = -heading
	if axis.dot(heading) < cos(PLANK_SNAP_ANGLE):
		return {}
	var right := heading.cross(Vector3.UP)
	var across := (center - rv.global_position).dot(right)
	var tracks: Array[float] = [RV.TRACK * 0.5, -RV.TRACK * 0.5]
	tracks.sort_custom(func(x: float, y: float) -> bool: return absf(across - x) < absf(across - y))
	for track: float in tracks:
		if absf(across - track) > PLANK_SNAP_ACROSS:
			break # (Sorted: the other one is further off.)
		var base := Vector3(rv.global_position.x, origin.y, rv.global_position.z) + right * track
		if _plank_laid_along(player.get_tree(), base, heading, right, center):
			continue # That track's taken: the other one, then.
		var start := base + heading * (origin - base).dot(heading)
		start.y = origin.y
		var lined := _plank_along(space, start, heading, aim)
		if not lined.is_empty() and lined["bridging"] == plan["bridging"]:
			return lined
	return {}


## Whether a placed plank already lies along the line through `base` in direction `heading`,
## near `near`.
static func _plank_laid_along(tree: SceneTree, base: Vector3, heading: Vector3, right: Vector3, near: Vector3) -> bool:
	for n: Node in tree.get_nodes_in_group(&"items"):
		var item := n as Item
		if item == null or item.kind != &"plank" or not item.is_placed():
			continue
		var from := item.global_position - base
		if absf(from.dot(right)) < PLANK_WIDTH and absf((item.global_position - near).dot(heading)) < PLANK_LENGTH:
			return true
	return false


static func _mesh(model: String) -> Mesh:
	if model == "@hook" and not _meshes.has(model):
		_meshes[model] = _hook_mesh()
	if model == "@patty" and not _meshes.has(model):
		_meshes[model] = _disc_mesh(0.065, 0.025, Color(0.85, 0.6, 0.6))
	if model == "@soda" and not _meshes.has(model):
		_meshes[model] = _disc_mesh(0.033, 0.12, Color(0.8, 0.12, 0.12))
	if model == "@cassette" and not _meshes.has(model):
		_meshes[model] = _cassette_mesh()
	if not _meshes.has(model):
		var path := (TripStops.KENNEY % model.trim_prefix("kenney:")) if model.begins_with("kenney:") else MODELS % model
		var scene := load(path) as PackedScene
		var root := scene.instantiate()
		var mi := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_meshes[model] = mi.mesh
		root.free()
	return _meshes[model]


## A chunky low-poly winch hook: a ring on a shank with a curved hook (built in code; small
## enough not to need a model file).
static func _hook_mesh() -> Mesh:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.53, 0.5)
	steel.metallic = 0.8
	steel.roughness = 0.4
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.9, 0.7, 0.15)
	yellow.roughness = 0.5
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	var parts: Array[Array] = [
		[TorusMesh.new(), Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0.16, 0)), steel],
		[CylinderMesh.new(), Transform3D(Basis.IDENTITY, Vector3(0, 0.07, 0)), yellow],
		[TorusMesh.new(), Transform3D(Basis(Vector3.RIGHT, PI / 2.0).scaled(Vector3.ONE * 1.4), Vector3(0, -0.03, 0)), steel],
	]
	(parts[0][0] as TorusMesh).inner_radius = 0.025
	(parts[0][0] as TorusMesh).outer_radius = 0.04
	(parts[0][0] as TorusMesh).rings = 8
	(parts[0][0] as TorusMesh).ring_segments = 5
	(parts[1][0] as CylinderMesh).top_radius = 0.02
	(parts[1][0] as CylinderMesh).bottom_radius = 0.025
	(parts[1][0] as CylinderMesh).height = 0.12
	(parts[1][0] as CylinderMesh).radial_segments = 6
	(parts[2][0] as TorusMesh).inner_radius = 0.03
	(parts[2][0] as TorusMesh).outer_radius = 0.05
	(parts[2][0] as TorusMesh).rings = 8
	(parts[2][0] as TorusMesh).ring_segments = 5
	for part: Array in parts:
		st.clear()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(part[0], 0, part[1])
		st.set_material(part[2])
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[2])
	return mesh


## A cassette: a dark case with a cream label and two little windows, lying flat.
static func _cassette_mesh() -> Mesh:
	var case := StandardMaterial3D.new()
	case.albedo_color = Color(0.13, 0.13, 0.15)
	case.roughness = 0.5
	var label := StandardMaterial3D.new()
	label.albedo_color = Color(0.92, 0.86, 0.68)
	label.roughness = 0.8
	var reel := StandardMaterial3D.new()
	reel.albedo_color = Color(0.4, 0.3, 0.25)
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	var parts: Array[Array] = [
		[Vector3(0.108, 0.014, 0.068), Vector3(0.0, 0.007, 0.0), case],
		[Vector3(0.088, 0.002, 0.036), Vector3(0.0, 0.0145, -0.008), label],
		[Vector3(0.02, 0.002, 0.02), Vector3(-0.024, 0.0145, 0.016), reel],
		[Vector3(0.02, 0.002, 0.02), Vector3(0.024, 0.0145, 0.016), reel],
	]
	for part: Array in parts:
		var box := BoxMesh.new()
		box.size = part[0]
		st.clear()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.append_from(box, 0, Transform3D(Basis.IDENTITY, part[1]))
		st.set_material(part[2])
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, part[2])
	return mesh


## A little low-poly cylinder (a patty, a can), standing on its base.
static func _disc_mesh(radius: float, height: float, color: Color) -> Mesh:
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 10
	cyl.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(cyl, 0, Transform3D(Basis.IDENTITY, Vector3.UP * height * 0.5))
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	return mesh


## Recolours one item (a patty cooking) without touching the shared mesh.
static func tint(item: Item, color: Color) -> void:
	var mi := item.get_child(0) as MeshInstance3D
	var mat := mi.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.roughness = 0.7
		mi.material_override = mat
	mat.albedo_color = color


## A patty's colour for how cooked it is.
static func patty_color(cook: float) -> Color:
	if cook < PATTY_THAWED:
		return Color(0.85, 0.6, 0.6).lerp(Color(0.8, 0.35, 0.35), cook / PATTY_THAWED) # Frosty pink to raw.
	if cook < PATTY_COOKED:
		return Color(0.8, 0.35, 0.35).lerp(Color(0.45, 0.26, 0.15), (cook - PATTY_THAWED) / (PATTY_COOKED - PATTY_THAWED))
	if cook < PATTY_BURNT:
		return Color(0.45, 0.26, 0.15)
	return Color(0.12, 0.1, 0.09)


static func patty_name(cook: float) -> String:
	if cook < PATTY_THAWED:
		return "Frozen patty"
	if cook < PATTY_COOKED:
		return "Raw patty"
	if cook < PATTY_BURNT:
		return "Cooked patty"
	return "Burnt patty"
