class_name ItemLibrary
extends RefCounted
## Every item kind: name, model, mass, how it's held. `create()` builds a ready `Item`.
## Models come from `assets/models/props/` (built by tools/assets/blender/build_props.py).

const MODELS := "res://assets/models/props/%s.glb"
const SMALL_HOLD := Transform3D(Basis.IDENTITY, Vector3(0.24, -0.22, -0.45))

## kind → {name, model, mass, hold (camera-space transform), two_handed}
static var DEFS: Dictionary[StringName, Dictionary] = {
	&"plank": {"name": "Plank", "model": "plank", "mass": 8.0, "two_handed": true, "reach": 3.4,
		"hold": Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.28, -0.42, -1.3))},
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
	&"winch_hook": {"name": "Winch hook", "model": "@hook", "mass": 2.0,
		"hold": Transform3D(Basis.IDENTITY, Vector3(0.25, -0.3, -0.55))},
}
## How far ahead a plank can be placed, metres.
const PLANK_REACH := 4.5
const PLANK_LENGTH := 2.4

static var _meshes: Dictionary[String, Mesh] = {}


static func create(kind: StringName) -> Item:
	var def: Dictionary = DEFS[kind]
	var item := Item.new()
	item.kind = kind
	item.def = def
	item.name = String(kind)
	item.mass = def["mass"]
	var mesh := _mesh(def["model"])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	item.add_child(mi)
	var aabb := mesh.get_aabb()
	item.base_offset = -aabb.position.y
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.03)
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = aabb.get_center()
	item.add_child(shape)
	return item


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
		&"plank":
			return func(item: Item, player: Player) -> bool:
				var xf: Variant = plank_placement(player)
				if xf == null:
					return false
				player.held = null
				item.place(player.world_items, xf)
				return true
	return Callable()


## What Use would do right now, for the HUD ("" if nothing).
static func use_hint(item: Item, player: Player) -> String:
	match item.kind:
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
	var axis_x := (ends[1] - ends[0]).normalized()
	var up := axis_x.cross(Vector3.UP).cross(axis_x).normalized()
	if up.y < 0.0:
		up = -up
	var z := axis_x.cross(up)
	var mid := (ends[0] + ends[1]) * 0.5 + up * 0.03
	return Transform3D(Basis(axis_x, up, z), mid)


static func _mesh(model: String) -> Mesh:
	if model == "@hook" and not _meshes.has(model):
		_meshes[model] = _hook_mesh()
	if not _meshes.has(model):
		var scene := load(MODELS % model) as PackedScene
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
