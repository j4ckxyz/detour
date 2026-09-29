class_name PropLibrary
extends RefCounted
## Meshes and collision shapes for scattered trees and props, loaded once from
## `assets/models/*.glb` (built by `tools/assets/build_assets.py`).
##
## The generator (rvgen) decides *what* goes where: tree kinds `0..TREE_KINDS`, and props as
## (kind, variant). This class maps those onto whatever models exist. A prop's mesh key is
## an index into `prop_meshes` / `prop_shapes`.

## Prop kinds, matching `rvgen::scatter::PropKind`.
const ROCK := 0
const STUMP := 1
const LOG := 2
const SAPLING := 3

## Tree kinds 0..2 use Pine_1..Pine_3; Pine_0 (the small one) is the sapling prop.
const TREE_MODELS: Array[String] = ["Pine_1", "Pine_2", "Pine_3"]
## Trees per biome (matches rvgen::scatter::TREES_PER_BIOME): kinds 3..5 bayou, 6..8
## canyon, 9..11 mountain pass. Procedural low-poly stand-ins for now.
const TREES_PER_BIOME := 3

var tree_meshes: Array[Mesh] = []
## Cheap stand-ins drawn beyond `TerrainStreamer.tree_detail_distance`.
var tree_far_meshes: Array[Mesh] = []
## Trunk colliders per tree kind, with the offset from the tree's base to the shape centre.
var tree_shapes: Array[Shape3D] = []
var tree_shape_offsets: Array[Vector3] = []

var prop_meshes: Array[Mesh] = []
## `null` where the prop has no collision (saplings).
var prop_shapes: Array[Shape3D] = []

var _rock_count := 0

static var _shared: PropLibrary


## The library, loaded on first use.
static func shared() -> PropLibrary:
	if _shared == null:
		_shared = PropLibrary.new()
		_shared._load()
	return _shared


func mesh_key(kind: int, variant: int) -> int:
	match kind:
		ROCK:
			return variant % _rock_count
		STUMP:
			return _rock_count
		LOG:
			return _rock_count + 1
		_:
			return _rock_count + 2


func tree_kinds() -> int:
	return tree_meshes.size()


func _load() -> void:
	var pines := _meshes("res://assets/models/pines.glb")
	for name: String in TREE_MODELS:
		var mesh: Mesh = pines[name]
		tree_meshes.append(mesh)
		var height := mesh.get_aabb().size.y
		tree_far_meshes.append(TreeMesh.build(height))
		# Matches build_nature.py: trunk base radius 0.06 + 0.018 h. The collider covers the
		# lower half, where the RV can actually hit it.
		var trunk := CylinderShape3D.new()
		trunk.radius = (0.06 + 0.018 * height) * 0.85
		trunk.height = height * 0.5
		tree_shapes.append(trunk)
		tree_shape_offsets.append(Vector3(0.0, height * 0.25, 0.0))

	var snowy_dark := Color(0.10, 0.20, 0.14)
	var snow := Color(0.9, 0.93, 0.96)
	# (mesh, trunk radius, collider height)
	var extra: Array[Array] = [
		[TreeMesh.bayou(8.0), 0.45, 4.0], [TreeMesh.bayou(6.5), 0.38, 3.2], [TreeMesh.snag(7.0), 0.28, 3.5],
		[TreeMesh.cactus(4.5), 0.26, 4.5], [TreeMesh.cactus(3.4), 0.22, 3.4], [TreeMesh.juniper(4.0), 0.2, 1.4],
		[TreeMesh.build(9.0, 7, snowy_dark, snow), 0.2, 4.5], [TreeMesh.build(11.5, 7, snowy_dark, snow), 0.24, 5.5],
		[TreeMesh.build(7.0, 7, snowy_dark, snow.darkened(0.1)), 0.17, 3.5],
	]
	for e: Array in extra:
		var mesh: Mesh = e[0]
		tree_meshes.append(mesh)
		tree_far_meshes.append(mesh)
		var trunk := CylinderShape3D.new()
		trunk.radius = e[1]
		trunk.height = e[2]
		tree_shapes.append(trunk)
		tree_shape_offsets.append(Vector3(0.0, float(e[2]) * 0.5, 0.0))

	var rocks := _meshes("res://assets/models/rocks.glb")
	var names := rocks.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	for name: String in names:
		var mesh: Mesh = rocks[name]
		prop_meshes.append(mesh)
		prop_shapes.append(mesh.create_convex_shape(true, true))
	_rock_count = prop_meshes.size()

	for path: String in ["res://assets/models/stump.glb", "res://assets/models/log.glb"]:
		var mesh: Mesh = _meshes(path).values()[0]
		prop_meshes.append(mesh)
		prop_shapes.append(mesh.create_convex_shape(true, true))

	prop_meshes.append(pines["Pine_0"])
	prop_shapes.append(null)


## Every mesh in a glTF scene, by node name.
static func _meshes(path: String) -> Dictionary[String, Mesh]:
	var out: Dictionary[String, Mesh] = {}
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("PropLibrary: missing %s (run tools/assets/build_assets.py)" % path)
		return out
	var root := scene.instantiate()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		out[String(node.name)] = (node as MeshInstance3D).mesh
	root.free()
	return out
