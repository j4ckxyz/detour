class_name ItemLibrary
extends RefCounted
## Every item kind: name, model, mass, how it's held. `create()` builds a ready `Item`.
## Models come from `assets/models/props/` (built by tools/assets/blender/build_props.py).

const MODELS := "res://assets/models/props/%s.glb"
const SMALL_HOLD := Transform3D(Basis.IDENTITY, Vector3(0.24, -0.22, -0.45))

## kind → {name, model, mass, hold (camera-space transform), two_handed}
static var DEFS: Dictionary[StringName, Dictionary] = {
	&"plank": {"name": "Plank", "model": "plank", "mass": 8.0, "two_handed": true,
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
	&"winch_remote": {"name": "Winch remote", "model": "winchremote", "mass": 0.3, "hold": SMALL_HOLD},
}

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
	return Callable()


static func _mesh(model: String) -> Mesh:
	if not _meshes.has(model):
		var scene := load(MODELS % model) as PackedScene
		var root := scene.instantiate()
		var mi := root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		_meshes[model] = mi.mesh
		root.free()
	return _meshes[model]
