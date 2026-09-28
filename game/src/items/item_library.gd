class_name ItemLibrary
extends RefCounted
## Every item kind: name, model, mass, how it's held. `create()` builds a ready `Item`.
## Models come from `assets/models/props/` (built by tools/assets/blender/build_props.py).

const MODELS := "res://assets/models/props/%s.glb"
const SMALL_HOLD := Transform3D(Basis.IDENTITY, Vector3(0.24, -0.22, -0.45))

## kind → {name, model, mass, hold (camera-space transform), two_handed}
static var DEFS: Dictionary[StringName, Dictionary] = {
	&"plank": {"name": "Plank", "model": "plank", "mass": 15.0, "two_handed": true, "reach": 4.5,
		"hold": Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.28, -0.42, -2.5))},
	&"jerrycan": {"name": "Jerry can", "model": "jerrycan", "mass": 20.0, "two_handed": true,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.3, -0.62, -0.5))},
	&"spare_tire": {"name": "Spare tire", "model": "sparetire", "mass": 25.0, "two_handed": true,
		"hold": Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0.0, -0.4, -0.8))},
	&"scrap_metal": {"name": "Scrap metal", "model": "scrapmetal", "mass": 3.0,
		"hold": Transform3D(Basis(Vector3.RIGHT, 0.9), Vector3(0.22, -0.3, -0.6))},
	&"motor_oil": {"name": "Motor oil", "model": "oilbottle", "mass": 1.0, "hold": SMALL_HOLD},
	&"burger": {"name": "Burger", "model": "burger", "mass": 0.3, "hold": SMALL_HOLD},
	&"antidote": {"name": "Antidote", "model": "antidote", "mass": 0.2, "hold": SMALL_HOLD},
	&"epipen": {"name": "EpiPen", "model": "epipen", "mass": 0.1, "hold": SMALL_HOLD},
	&"bear_spray": {"name": "Bear spray", "model": "bearspray", "mass": 0.4, "hold": SMALL_HOLD},
	&"first_aid": {"name": "First-aid kit", "model": "firstaidkit", "mass": 1.5,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.25, -0.38, -0.55))},
	&"winch_remote": {"name": "Winch remote", "model": "winchremote", "mass": 0.3, "hold": SMALL_HOLD,
		"no_throw": true, "seated": true},
	&"hammer": {"name": "Repair hammer", "model": "kenney:survival/hammer", "mass": 1.2, "scale": 2.6,
		"hold": Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0.26, -0.3, -0.5))},
	&"drill": {"name": "Power drill", "model": "drill", "mass": 1.8,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.24, -0.38, -0.45)) * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)},
	&"rv_part": {"name": "RV part", "model": "", "mass": 12.0, "two_handed": true,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.0, -0.5, -1.0))},
	&"rv_wheel": {"name": "Wheel", "model": "", "mass": 30.0, "two_handed": true,
		"hold": Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, -0.5, -0.9))},
	&"winch_hook": {"name": "Winch hook", "model": "@hook", "mass": 2.0,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.25, -0.3, -0.55))},
}
## A full jerry can, litres.
const JERRY_CAN_LITRES := 20.0
## How far ahead a plank can be placed, metres.
const PLANK_REACH := 5.5
## Must match rvgen::route::PLANK_LENGTH and the plank model.
const PLANK_LENGTH := 5.0

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


static func create(kind: StringName) -> Item:
	var def: Dictionary = DEFS[kind].duplicate() # Per item: some change (a jerry can's fill).
	var item := Item.new()
	item.kind = kind
	item.def = def
	item.name = String(kind)
	item.mass = def["mass"]
	_dress(item, _mesh(def["model"]), def.get("scale", 1.0))
	return item


## Gives an item its look and a box collider fitted to the mesh.
static func _dress(item: Item, mesh: Mesh, scale: float = 1.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * scale
	item.add_child(mi)
	var aabb := mesh.get_aabb()
	aabb = AABB(aabb.position * scale, aabb.size * scale)
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
		&"burger":
			return func(item: Item, player: Player) -> bool:
				player.eat(item)
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
				var aim := player.aim_rv()
				if aim.get("kind") != "part":
					return false
				var d := player.rv.damage
				var part: RVDamage.Part = d.parts[aim["id"]]
				if part.attached and part.hp >= RVDamage.FULL:
					return false
				var scrap := player.find_item(&"scrap_metal")
				if scrap == null:
					player.say("You need scrap metal in your pockets to patch that.")
					return false
				player.consume(scrap)
				d.patch_part(aim["id"])
				return true
		&"rv_part":
			return func(item: Item, player: Player) -> bool:
				var aim := player.aim_rv()
				var id: StringName = item.get_meta(&"part", &"")
				if aim.get("kind") != "part" or aim["id"] != id or player.rv.damage.parts[id].attached:
					return false
				player.held = null
				item.holder = null
				player.rv.damage.parts[id].debris = item # _restore frees it.
				player.rv.damage.refit_part(id)
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
					d.mount_wheel(i, tire)
				elif d.tires[i] <= 0.0:
					d.swap_tire(i)
				else:
					return false
				player.consume(item)
				player.say("Wheel on. Now drill its bolts in.")
				return true
		&"motor_oil":
			return func(item: Item, player: Player) -> bool:
				if player.aim_rv().get("kind") != "engine" or player.rv.damage.oil > 0.95:
					return false
				player.rv.damage.add_oil()
				player.consume(item)
				return true
		&"jerrycan":
			return func(item: Item, player: Player) -> bool:
				var litres := float(item.get_meta(&"fuel", JERRY_CAN_LITRES))
				if player.aim_rv().get("kind") != "fuel" or litres <= 0.0:
					return false
				var poured := player.rv.damage.add_fuel(litres)
				item.set_meta(&"fuel", litres - poured)
				item.def["name"] = "Jerry can (%d L)" % roundi(litres - poured) if litres - poured > 0.5 else "Empty jerry can"
				return poured > 0.0
		&"plank":
			return func(item: Item, player: Player) -> bool:
				var xf: Variant = plank_placement(player)
				if xf == null:
					return false
				player.held = null
				item.place(player.world_items, xf)
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
			d.tighten_bolt(i)
			return 0.45 # One bolt at a time.
	return Callable()


## What Use would do right now, for the HUD ("" if nothing).
static func use_hint(item: Item, player: Player) -> String:
	var aim := player.aim_rv() if player.rv else {}
	var d: RVDamage = player.rv.damage if player.rv else null
	match item.kind:
		&"hammer":
			if aim.get("kind") == "part":
				var part: RVDamage.Part = d.parts[aim["id"]]
				var what := d.part_name(aim["id"])
				if not part.attached:
					return "LMB rebuild the %s (1 scrap)" % what
				if part.hp < RVDamage.FULL:
					return "LMB patch the %s, %d%% (1 scrap)" % [what, roundi(part.hp)]
				return "the %s is fine" % what
			return "look at a dented or missing part"
		&"rv_part":
			return "LMB fit it back on" if aim.get("kind") == "part" and aim["id"] == item.get_meta(&"part", &"") else "take it back to where it came off"
		&"spare_tire", &"rv_wheel":
			if aim.get("kind") == "wheel":
				var i: int = aim["id"]
				if not d.wheel_on[i]:
					return "LMB mount it on the empty hub"
				if d.tires[i] <= 0.0:
					return "LMB swap the flat"
			return "look at an empty hub or a flat"
		&"drill":
			if aim.get("kind") == "wheel":
				var i: int = aim["id"]
				if d.wheel_on[i]:
					return "hold LMB to drill bolts in (%d/%d)" % [d.bolts[i], RVDamage.BOLTS]
			return "look at a wheel"
		&"motor_oil":
			return "LMB top up the oil (%d%%)" % roundi(d.oil * 100.0) if aim.get("kind") == "engine" else "look at the engine (front, under the hood)"
		&"jerrycan":
			var litres := float(item.get_meta(&"fuel", JERRY_CAN_LITRES))
			if litres <= 0.0:
				return "empty: fill it at a gas station pump"
			return "LMB pour %d L into the tank" % roundi(litres) if aim.get("kind") == "fuel" else "look at the fuel cap (left side)"
		&"burger":
			return "LMB eat"
		&"winch_hook":
			var anchor: Variant = find_anchor(player)
			return "LMB hook onto the %s" % anchor["what"] if anchor != null else "look at a tree, rock or stump to hook on"
		&"plank":
			return "LMB place plank" if plank_placement(player) != null else "aim at the ground to place"
		&"winch_remote":
			return "hold LMB reel in · RMB pay out · R switch winch"
	return ""


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


## Where a held plank would go: along the view, resting on the ground (or on another plank)
## at both ends. Returns a Transform3D, or null if it wouldn't rest on anything.
static func plank_placement(player: Player) -> Variant:
	if player.inside:
		return null
	var space := player.get_world_3d().direct_space_state
	var cam := player.camera.global_transform
	var query := PhysicsRayQueryParameters3D.create(cam.origin, cam.origin - cam.basis.z * PLANK_REACH, TerrainStreamer.WORLD_LAYER)
	query.exclude = [player.held.get_rid()] if player.held else []
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return null
	var forward := -cam.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var center: Vector3 = hit["position"]
	var other := hit["collider"] as Item
	if other and other.is_placed() and other.kind == &"plank":
		# Carry on from the end of the plank we're looking at, in its direction.
		var axis := other.global_basis.x.normalized()
		if axis.dot(forward) < 0.0:
			axis = -axis
		var end := other.global_position + axis * (PLANK_LENGTH * 0.5)
		forward = Vector3(axis.x, 0.0, axis.z).normalized()
		center = end + forward * (PLANK_LENGTH * 0.5 - 0.05)
	var half := forward * (PLANK_LENGTH * 0.5 - 0.1)
	var ends: Array[Vector3] = []
	for e: Vector3 in [center - half, center + half]:
		var down := PhysicsRayQueryParameters3D.create(e + Vector3.UP * 1.2, e + Vector3.DOWN * 2.5, TerrainStreamer.WORLD_LAYER)
		down.exclude = query.exclude
		var h := space.intersect_ray(down)
		if h.is_empty():
			return null # That end would hang in the air.
		ends.append(h["position"])
	# A board rests on the highest points under it: lift it over any bump between the ends.
	var lift := 0.0
	for k: int in range(1, 6):
		var t := k / 6.0
		var along := ends[0].lerp(ends[1], t)
		var probe := PhysicsRayQueryParameters3D.create(along + Vector3.UP * 1.5, along + Vector3.DOWN * 1.0, TerrainStreamer.WORLD_LAYER)
		probe.exclude = query.exclude
		var h := space.intersect_ray(probe)
		if not h.is_empty():
			lift = maxf(lift, (h["position"] as Vector3).y - along.y)
	var axis_x := (ends[1] - ends[0]).normalized()
	var up := axis_x.cross(Vector3.UP).cross(axis_x).normalized()
	if up.y < 0.0:
		up = -up
	var z := axis_x.cross(up)
	var mid := (ends[0] + ends[1]) * 0.5 + Vector3.UP * lift + up * 0.04
	return Transform3D(Basis(axis_x, up, z), mid)


static func _mesh(model: String) -> Mesh:
	if model == "@hook" and not _meshes.has(model):
		_meshes[model] = _hook_mesh()
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
