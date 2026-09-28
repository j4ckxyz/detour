class_name TerrainStreamer
extends Node3D
## Streams generated terrain chunks (with LOD), their trees and props around a focus node,
## and builds collision (terrain + trunks + rocks) near the `collision_foci`.
##
## Generation runs on native worker threads (rvcore `ChunkBuilder`); this node only uploads
## finished chunks, within a per-frame time budget, so streaming never hitches the frame.

## Emitted once every chunk in view has a mesh.
signal area_ready

const CHUNK_SIZE := 128.0
const HALF_DIAGONAL := 90.6 # Half of a chunk's diagonal, in metres.
## Ring limits (distance from focus to chunk centre) → mesh spacing in metres.
const LOD_RINGS: Array[Vector2] = [
	Vector2(200.0, 1.0), Vector2(400.0, 2.0), Vector2(800.0, 4.0), Vector2(INF, 8.0),
]
## Chunks at this spacing or finer cast shadows (shadow distance never reaches beyond).
const SHADOW_MAX_STEP := 2
## Re-evaluate LOD rings only after moving this far (squared metres) within a chunk.
const REFRESH_MOVE_SQ := 24.0 * 24.0
## Collision is dropped this far (metres) beyond `collision_distance`, so it doesn't flicker.
const COLLISION_HYSTERESIS := 64.0
## Physics layer of terrain and props. Vehicles and players collide with it.
const WORLD_LAYER := 1
const HEIGHTS_SIDE := 129
## Shape index of the terrain heightmap in each chunk's body (props come after it).
const GROUND_SHAPE := 0
const TREE_STRIDE := 6
const PROP_STRIDE := 14
## Roles of a chunk's decor MultiMeshes (they get different visibility ranges).
enum Decor { TREE_NEAR, TREE_FAR, PROP }

@export var view_distance := 900.0
@export var tree_distance := 450.0
## Real pine models out to here; cheap cones beyond.
@export var tree_detail_distance := 180.0
## Rocks, stumps, logs and saplings.
@export var decor_distance := 250.0
## Collision exists within this distance of any collision focus.
@export var collision_distance := 256.0
@export var upload_budget_usec := 2000
@export var worker_threads := 0 # 0 = one per spare core.

## Drives streaming and LOD (usually the camera).
var focus: Node3D
## Things that need solid ground under them: the RV, players.
var collision_foci: Array[Node3D] = []

var chunks_loaded := 0
var trees_loaded := 0
var props_loaded := 0
var bodies_loaded := 0
var avg_gen_usec := 0.0
var last_upload_usec := 0
var max_upload_usec := 0
## Slowest single upload of each kind, to find what blows the frame budget.
var max_mesh_usec := 0
var max_decor_usec := 0
var max_body_usec := 0
var last_refresh_usec := 0 # Only non-zero on frames that refreshed.

var _builder := ChunkBuilder.new()
var _library: PropLibrary
var _chunks: Dictionary[Vector2i, Chunk] = {}
var _center := Vector2i(1 << 30, 1 << 30)
var _refresh_timer := 0.0
var _last_refresh_pos := Vector3.INF
var _last_collision_pos: Array[Vector3] = []
var _area_ready_sent := false
var _terrain_material := StandardMaterial3D.new()
## Decor MultiMeshes waiting to enter the scene: [chunk, role, mesh, buffer]. Each add costs
## the renderer up to several ms in a big scene, so they trickle in within the budget.
var _decor_queue: Array[Array] = []


class Chunk:
	var coord: Vector2i
	var shown_step := 0 # 0 = no mesh yet.
	var wanted_step := 0
	var requested_step := 0 # 0 = nothing in flight.
	var decor_requested := false
	var decor_ready := false
	var heights_requested := false
	var hash := ""
	var mesh_instance: MeshInstance3D
	var tree_near: Array[MultiMeshInstance3D] = []
	var tree_far: Array[MultiMeshInstance3D] = []
	var prop_instances: Array[MultiMeshInstance3D] = []
	## Raw generator output, kept to build collision when the chunk comes into range.
	var trees := PackedFloat32Array()
	var props := PackedFloat32Array()
	var heights := PackedFloat32Array()
	var body: StaticBody3D

	func origin() -> Vector3:
		return Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)

	func center_xz() -> Vector2:
		return (Vector2(coord) + Vector2(0.5, 0.5)) * CHUNK_SIZE


func _init() -> void:
	# Everything streamed is static: skip physics interpolation for the whole subtree.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func start(seed_code: String) -> bool:
	_terrain_material.vertex_color_use_as_albedo = true
	_terrain_material.vertex_color_is_srgb = true
	_terrain_material.roughness = 0.92
	_library = PropLibrary.shared()
	return _builder.start(seed_code, worker_threads)


func pending() -> int:
	return _builder.pending()


func worker_count() -> int:
	return _builder.thread_count()


## True once the ground (and its props) under `pos` is solid.
func has_collision_at(pos: Vector3) -> bool:
	var chunk: Chunk = _chunks.get(_chunk_of(pos))
	return chunk != null and chunk.body != null


func _exit_tree() -> void:
	_builder.stop()


func _process(delta: float) -> void:
	if focus == null:
		return
	var pos := focus.global_position
	var center := _chunk_of(pos)
	_refresh_timer -= delta
	last_refresh_usec = 0
	if center != _center:
		# Moved to a new chunk: drop stale queued work and re-request in distance order.
		_center = center
		_builder.clear_queue()
		for chunk: Chunk in _chunks.values():
			chunk.requested_step = 0
			if not chunk.decor_ready:
				chunk.decor_requested = false # The job may have been dropped; ask again.
			if chunk.body == null and chunk.heights.is_empty():
				chunk.heights_requested = false
		_refresh()
	elif _refresh_timer <= 0.0 and (pos.distance_squared_to(_last_refresh_pos) > REFRESH_MOVE_SQ or _collision_foci_moved()):
		_refresh()
	_upload()


func _chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK_SIZE), floori(p.z / CHUNK_SIZE))


func _step_for(distance: float) -> int:
	for ring: Vector2 in LOD_RINGS:
		if distance < ring.x:
			return int(ring.y)
	return 8


func _collision_foci_moved() -> bool:
	if _last_collision_pos.size() != collision_foci.size():
		return true
	for i: int in collision_foci.size():
		if is_instance_valid(collision_foci[i]) and \
				collision_foci[i].global_position.distance_squared_to(_last_collision_pos[i]) > REFRESH_MOVE_SQ:
			return true
	return false


## Distance from a chunk centre to the nearest collision focus.
func _collision_distance_to(mid: Vector2) -> float:
	var best := INF
	for f: Node3D in collision_foci:
		if is_instance_valid(f):
			best = minf(best, mid.distance_to(Vector2(f.global_position.x, f.global_position.z)))
	return best


func _refresh() -> void:
	var started := Time.get_ticks_usec()
	_refresh_timer = 0.25
	_last_refresh_pos = focus.global_position
	_last_collision_pos.clear()
	for f: Node3D in collision_foci:
		_last_collision_pos.append(f.global_position if is_instance_valid(f) else Vector3.INF)
	var focus_xz := Vector2(focus.global_position.x, focus.global_position.z)
	var radius := ceili(view_distance / CHUNK_SIZE) + 1
	var wanted: Array[Array] = [] # [distance, coord, step]
	var keep: Dictionary[Vector2i, bool] = {}
	for dz: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			var coord := _center + Vector2i(dx, dz)
			var mid := (Vector2(coord) + Vector2(0.5, 0.5)) * CHUNK_SIZE
			var dist := focus_xz.distance_to(mid)
			if dist - HALF_DIAGONAL > view_distance:
				continue
			keep[coord] = true
			wanted.append([dist, coord, _step_for(dist)])

	for coord: Vector2i in _chunks.keys():
		if not keep.has(coord):
			_free_chunk(coord)

	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for w: Array in wanted:
		var coord: Vector2i = w[1]
		var step: int = w[2]
		var dist: float = w[0]
		var chunk: Chunk = _chunks.get(coord)
		if chunk == null:
			chunk = Chunk.new()
			chunk.coord = coord
			_chunks[coord] = chunk
		chunk.wanted_step = step

		var solid_dist := _collision_distance_to(chunk.center_xz()) - HALF_DIAGONAL
		if chunk.body and solid_dist > collision_distance + COLLISION_HYSTERESIS:
			_free_body(chunk)
		var need_collision := chunk.body == null and solid_dist < collision_distance
		var need_heights := need_collision and not chunk.heights_requested
		var need_decor := not chunk.decor_requested and (dist - HALF_DIAGONAL < tree_distance or need_collision)
		var need_mesh := chunk.shown_step != step and chunk.requested_step != step
		if need_mesh or need_decor or need_heights:
			var flags := (ChunkBuilder.DECOR if need_decor else 0) | (ChunkBuilder.HEIGHTS if need_heights else 0)
			_builder.request(coord.x, coord.y, step if need_mesh else 0, flags)
			if need_mesh:
				chunk.requested_step = step
			chunk.decor_requested = chunk.decor_requested or need_decor
			chunk.heights_requested = chunk.heights_requested or need_heights
	last_refresh_usec = Time.get_ticks_usec() - started


func _upload() -> void:
	var started := Time.get_ticks_usec()
	var elapsed := 0
	while elapsed < upload_budget_usec:
		var results := _builder.poll(1)
		if results.is_empty():
			break
		_apply(results[0])
		elapsed = Time.get_ticks_usec() - started
	# At least one decor node per frame so the queue always drains.
	var first := true
	while not _decor_queue.is_empty() and (first or elapsed < upload_budget_usec):
		first = false
		_add_queued_decor(_decor_queue.pop_front())
		elapsed = Time.get_ticks_usec() - started
	last_upload_usec = elapsed
	max_upload_usec = maxi(max_upload_usec, elapsed)

	if not _area_ready_sent and _builder.pending() == 0 and not _chunks.is_empty():
		for chunk: Chunk in _chunks.values():
			if chunk.shown_step == 0:
				return
		_area_ready_sent = true
		area_ready.emit()


func _apply(r: Dictionary) -> void:
	var coord := Vector2i(int(r["cx"]), int(r["cz"]))
	var chunk: Chunk = _chunks.get(coord)
	if chunk == null:
		return # Freed while generating.
	var step: int = r["step"]
	var gen_usec: int = r["gen_usec"]
	avg_gen_usec = lerpf(avg_gen_usec, float(gen_usec), 0.05) if avg_gen_usec > 0.0 else float(gen_usec)
	chunk.hash = r["hash"]

	if step > 0:
		if chunk.requested_step == step:
			chunk.requested_step = 0
		# Show the mesh if it is the LOD we want, or if we have nothing better yet.
		if step == chunk.wanted_step or chunk.shown_step == 0:
			var t0 := Time.get_ticks_usec()
			_show_mesh(chunk, step, r["arrays"])
			max_mesh_usec = maxi(max_mesh_usec, Time.get_ticks_usec() - t0)

	if r["tree_buffers"] != null and not chunk.decor_ready:
		var t1 := Time.get_ticks_usec()
		_build_decor(chunk, r)
		max_decor_usec = maxi(max_decor_usec, Time.get_ticks_usec() - t1)

	if r["heights"] != null and chunk.body == null:
		chunk.heights = r["heights"]
	if chunk.body == null and chunk.decor_ready and not chunk.heights.is_empty():
		var t2 := Time.get_ticks_usec()
		_build_body(chunk)
		max_body_usec = maxi(max_body_usec, Time.get_ticks_usec() - t2)


func _show_mesh(chunk: Chunk, step: int, arrays: Array) -> void:
	if chunk.mesh_instance == null:
		chunk.mesh_instance = MeshInstance3D.new()
		chunk.mesh_instance.position = chunk.origin()
		add_child(chunk.mesh_instance)
		chunks_loaded += 1
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_material)
	chunk.mesh_instance.mesh = mesh
	chunk.mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if step <= SHADOW_MAX_STEP
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	chunk.shown_step = step


func _build_decor(chunk: Chunk, r: Dictionary) -> void:
	chunk.decor_ready = true
	chunk.trees = r["trees"]
	chunk.props = r["props"]

	var buffers: Array = r["tree_buffers"]
	for kind: int in buffers.size():
		var buffer: PackedFloat32Array = buffers[kind]
		if buffer.is_empty():
			continue
		var k := mini(kind, _library.tree_kinds() - 1)
		_decor_queue.append([chunk, Decor.TREE_NEAR, _library.tree_meshes[k], buffer])
		_decor_queue.append([chunk, Decor.TREE_FAR, _library.tree_far_meshes[k], buffer])
	trees_loaded += int(r["tree_count"])

	# Props come mixed; group them by model so each model is one draw.
	var groups: Dictionary[int, Array] = {}
	var props := chunk.props
	for i: int in range(0, props.size(), PROP_STRIDE):
		var key := _library.mesh_key(int(props[i + 12]), int(props[i + 13]))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(i)
	for key: int in groups:
		var starts: Array = groups[key]
		var buffer := PackedFloat32Array()
		buffer.resize(starts.size() * 12)
		var j := 0
		for i: int in starts:
			for c: int in 12:
				buffer[j + c] = props[i + c]
			j += 12
		_decor_queue.append([chunk, Decor.PROP, _library.prop_meshes[key], buffer])
	props_loaded += int(r["prop_count"])


func _add_queued_decor(job: Array) -> void:
	var chunk: Chunk = job[0]
	if _chunks.get(chunk.coord) != chunk:
		return # Freed while queued.
	var role: Decor = job[1]
	var mmi := _add_multimesh(chunk, job[2], job[3], role != Decor.TREE_FAR)
	match role:
		Decor.TREE_NEAR:
			chunk.tree_near.append(mmi)
		Decor.TREE_FAR:
			chunk.tree_far.append(mmi)
		_:
			chunk.prop_instances.append(mmi)
	_apply_decor_ranges(chunk)


func _add_multimesh(chunk: Chunk, mesh: Mesh, buffer: PackedFloat32Array, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = buffer.size() / 12
	mm.buffer = buffer
	# Without a custom AABB, entering the scene computes one from the instance data, which
	# the renderer keeps on the GPU: a readback stall of several ms per chunk. The chunk's
	# footprint plus the instances' height range (and a generous model size) is enough.
	var lo := INF
	var hi := -INF
	for i: int in range(7, buffer.size(), 12):
		lo = minf(lo, buffer[i])
		hi = maxf(hi, buffer[i])
	var reach := mesh.get_aabb().size.length() * 4.0 # Largest scatter scale is < 4.
	mm.custom_aabb = AABB(Vector3(-reach, lo - reach, -reach), Vector3(CHUNK_SIZE + reach * 2.0, hi - lo + reach * 2.0, CHUNK_SIZE + reach * 2.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = chunk.origin()
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mmi.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	add_child(mmi)
	return mmi


func _apply_decor_ranges(chunk: Chunk) -> void:
	# Ranges are measured to each chunk's centre, so the near/far switch is per chunk.
	var detail := minf(tree_detail_distance, tree_distance)
	for mmi: MultiMeshInstance3D in chunk.tree_near:
		mmi.visibility_range_end = detail
		mmi.visibility_range_end_margin = 20.0
	for mmi: MultiMeshInstance3D in chunk.tree_far:
		mmi.visibility_range_begin = detail
		mmi.visibility_range_begin_margin = 20.0
		mmi.visibility_range_end = tree_distance
		mmi.visibility_range_end_margin = 40.0
		mmi.visible = tree_distance > detail
	for mmi: MultiMeshInstance3D in chunk.prop_instances:
		mmi.visibility_range_end = decor_distance
		mmi.visibility_range_end_margin = 20.0


func _build_body(chunk: Chunk) -> void:
	var body := StaticBody3D.new()
	body.name = "Ground_%d_%d" % [chunk.coord.x, chunk.coord.y]
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = chunk.origin()

	var ground := HeightMapShape3D.new()
	ground.map_width = HEIGHTS_SIDE
	ground.map_depth = HEIGHTS_SIDE
	ground.map_data = chunk.heights
	# The heightmap is centred on its transform.
	_add_shape(body, ground, Transform3D(Basis.IDENTITY, Vector3(CHUNK_SIZE, 0.0, CHUNK_SIZE) * 0.5))
	chunk.heights = PackedFloat32Array()

	var trees := chunk.trees
	for i: int in range(0, trees.size(), TREE_STRIDE):
		var k := int(trees[i + 5]) % _library.tree_kinds()
		var s := trees[i + 4]
		var xf := Transform3D(Basis.from_scale(Vector3.ONE * s), Vector3(trees[i], trees[i + 1], trees[i + 2]))
		_add_shape(body, _library.tree_shapes[k], xf.translated_local(_library.tree_shape_offsets[k]))

	var props := chunk.props
	for i: int in range(0, props.size(), PROP_STRIDE):
		var shape := _library.prop_shapes[_library.mesh_key(int(props[i + 12]), int(props[i + 13]))]
		if shape == null:
			continue
		var basis := Basis(
			Vector3(props[i], props[i + 4], props[i + 8]),
			Vector3(props[i + 1], props[i + 5], props[i + 9]),
			Vector3(props[i + 2], props[i + 6], props[i + 10]),
		)
		_add_shape(body, shape, Transform3D(basis, Vector3(props[i + 3], props[i + 7], props[i + 11])))

	add_child(body)
	chunk.body = body
	bodies_loaded += 1


static func _add_shape(body: CollisionObject3D, shape: Shape3D, xf: Transform3D) -> void:
	var owner := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner, shape)
	body.shape_owner_set_transform(owner, xf)


func _free_body(chunk: Chunk) -> void:
	chunk.body.queue_free()
	chunk.body = null
	chunk.heights = PackedFloat32Array()
	chunk.heights_requested = false
	bodies_loaded -= 1


func _free_chunk(coord: Vector2i) -> void:
	var chunk: Chunk = _chunks[coord]
	if chunk.mesh_instance:
		chunk.mesh_instance.queue_free()
		chunks_loaded -= 1
	for list: Array[MultiMeshInstance3D] in [chunk.tree_near, chunk.tree_far, chunk.prop_instances]:
		for mmi: MultiMeshInstance3D in list:
			mmi.queue_free()
	if chunk.decor_ready:
		trees_loaded -= chunk.trees.size() / TREE_STRIDE
		props_loaded -= chunk.props.size() / PROP_STRIDE
	if chunk.body:
		_free_body(chunk)
	_chunks.erase(coord)


## Updates distances after a preset change; chunks and decor re-stream as needed.
func set_distances(view: float, trees: float, decor: float) -> void:
	view_distance = view
	tree_distance = trees
	decor_distance = decor
	for chunk: Chunk in _chunks.values():
		_apply_decor_ranges(chunk)
	_refresh_timer = 0.0
	_last_refresh_pos = Vector3.INF
