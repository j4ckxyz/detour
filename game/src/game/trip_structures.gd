class_name TripStructures
extends RefCounted
## What the trip builds along and beside the road, from the generator's plan: old wooden
## bridges (with a hole in the deck), two-beam crossings, telephone poles that follow the road
## (up the hills too, never down the side tracks), and places off the road worth a look: a
## log cabin, a fire lookout tower, a rusting wreck, a bench on a hill with a view.
##
## Crossings are built in a road frame (`frame()`): origin on the road at the obstacle's
## centre, +X to the right of travel, -Z the way you're driving. Everything solid is on the
## world layer, so planks rest on it and winch hooks catch on it.

const WOOD := Color(0.42, 0.3, 0.19)
const WOOD_DARK := Color(0.3, 0.21, 0.13)
const WOOD_GREY := Color(0.52, 0.47, 0.4)
const RUST := Color(0.5, 0.27, 0.16)
## A bridge deck's half-width and its top above the road (m).
const DECK_HALF := 2.3
const DECK_TOP := 0.04
const DECK_THICK := 0.3
## How far a crossing's deck or beams reach onto the road either side of the ravine.
const LANDING := 3.0
const BOARD := 0.32
const POLE_HEIGHT := 8.0
## Telephone poles stand this far right of the centreline, this far apart along the road.
const POLE_OFFSET := 5.8
const POLE_SPACING := 48.0

static var _materials: Dictionary[Color, StandardMaterial3D] = {}


## The road frame at obstacle `o`.
static func frame(o: Dictionary) -> Transform3D:
	var dir: Vector3 = o["dir"]
	dir = Vector3(dir.x, 0.0, dir.z).normalized()
	return Transform3D(Basis(dir.cross(Vector3.UP), Vector3.UP, -dir), o["pos"])


## A timber bridge over a ravine `o.length` wide and `o.size` deep, on two stone abutments,
## with a hole `o.hole` long in its deck `o.hole_at` along it, and a low kicker board just
## before the hole (`kicker`: height, length). Take it fast off the kicker, or lay planks.
static func bridge(o: Dictionary, kicker: Vector2) -> Node3D:
	var root := Node3D.new()
	root.name = "Bridge"
	var half := float(o["length"]) * 0.5
	var depth := float(o["size"])
	var hole := float(o["hole"])
	var hole_a := float(o["hole_at"]) - hole * 0.5
	var hole_b := float(o["hole_at"]) + hole * 0.5
	var end := half + LANDING
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bridge:%.2f:%.2f" % [float(o["s"]), hole])
	# The deck, either side of the hole: solid slabs under rows of boards.
	for span: Vector2 in [Vector2(-end, hole_a), Vector2(hole_b, end)]:
		_slab(root, Vector3(DECK_HALF * 2.0, DECK_THICK, span.y - span.x), Vector3(0.0, DECK_TOP - DECK_THICK * 0.5, -(span.x + span.y) * 0.5))
		_boards(root, span, rng, span.x < 0.0)
	# Broken boards hanging into the hole.
	for k: int in 3:
		var at := lerpf(hole_a, hole_b, rng.randf_range(0.1, 0.9))
		var b := _box(root, Vector3(rng.randf_range(0.8, 2.2), 0.06, BOARD - 0.03), Vector3(rng.randf_range(-1.5, 1.5), -0.7, -at), WOOD_GREY, false)
		b.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.4, 0.4), rng.randf_range(0.6, 1.2) * (1.0 if k % 2 == 0 else -1.0))
	# The kicker: a board ramped up to the hole's near edge.
	var run := kicker.y
	var rise := kicker.x
	var angle := atan2(rise, run)
	var ramp := _box(root, Vector3(DECK_HALF * 2.0 - 0.3, 0.12, sqrt(run * run + rise * rise)), Vector3.ZERO, WOOD, true)
	ramp.rotation.x = angle
	ramp.position = Vector3(0.0, DECK_TOP + rise * 0.5, -(hole_a - run * 0.5)) - Vector3(0.0, cos(angle), sin(angle)) * 0.06
	# Stringers under the deck (broken at the hole), rails along the sides.
	for x: float in [-1.6, 1.6]:
		for span: Vector2 in [Vector2(-end, hole_a - 0.3), Vector2(hole_b + 0.3, end)]:
			_box(root, Vector3(0.3, 0.4, span.y - span.x), Vector3(x, DECK_TOP - DECK_THICK - 0.2, -(span.x + span.y) * 0.5), WOOD_DARK, false)
	for side: float in [-1.0, 1.0]:
		_rail(root, side * (DECK_HALF + 0.08), -end, end, 2.0)
	# Stone abutments at the ravine's edges and timber trestles down into it.
	for side: float in [-1.0, 1.0]:
		var abut := TripStops.abutment(DECK_HALF * 2.0 + 0.6)
		root.add_child(abut)
		abut.position = Vector3(0.0, -DECK_THICK + DECK_TOP, -side * (half + TripStops.ABUTMENT_DEPTH * 0.5))
		abut.rotation.y = PI if side > 0.0 else 0.0
	var bents := maxi(1, int(half * 2.0 / 7.0))
	for k: int in bents:
		var along := lerpf(-half, half, (k + 1.0) / (bents + 1.0))
		if along > hole_a - 0.4 and along < hole_b + 0.4:
			continue # The bent under the hole went with it.
		_bent(root, -along, depth + 1.5)
	return root


## Two narrow beams across a ravine, one under each wheel track (`width` wide at ±`offset`
## from the centreline), on abutments. Line up and creep.
static func beams(o: Dictionary, width: float, offset: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Beams"
	var half := float(o["length"]) * 0.5
	var end := half + LANDING
	for x: float in [-offset, offset]:
		_slab(root, Vector3(width, 0.4, end * 2.0), Vector3(x, DECK_TOP - 0.2, 0.0), WOOD_DARK)
		# Bolted planks along the top, for looks.
		for k: int in 3:
			_box(root, Vector3(width * 0.3, 0.03, end * 2.0 - 0.1), Vector3(x + (k - 1) * width * 0.33, DECK_TOP + 0.005, 0.0), WOOD.darkened(0.08 * k), false)
	for side: float in [-1.0, 1.0]:
		var abut := TripStops.abutment(offset * 2.0 + width + 1.2)
		root.add_child(abut)
		abut.position = Vector3(0.0, DECK_TOP - 0.4, -side * (half + TripStops.ABUTMENT_DEPTH * 0.5))
		abut.rotation.y = PI if side > 0.0 else 0.0
	if half > 5.0:
		_bent(root, 0.0, float(o["size"]) + 1.5, offset + width * 0.5)
	return root


## Telephone poles along the road at `spots` (world positions on the ground, with the road
## direction there as each one's basis -Z), wired pole to pole where they're close enough.
static func poles(spots: Array[Transform3D]) -> Node3D:
	var root := Node3D.new()
	root.name = "Poles"
	var wood := _material(WOOD_GREY.darkened(0.2))
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.11
	pole_mesh.bottom_radius = 0.15
	pole_mesh.height = POLE_HEIGHT
	pole_mesh.radial_segments = 8
	pole_mesh.material = wood
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(1.8, 0.12, 0.12)
	arm_mesh.material = wood
	var shape := CylinderShape3D.new()
	shape.radius = 0.15
	shape.height = POLE_HEIGHT
	var tips: Array = [] # Per pole: its two wire ends (world space).
	for xf: Transform3D in spots:
		var body := StaticBody3D.new()
		body.collision_layer = TerrainStreamer.WORLD_LAYER
		body.collision_mask = 0
		root.add_child(body)
		body.transform = xf.translated_local(Vector3(0.0, POLE_HEIGHT * 0.5 - 0.4, 0.0))
		var mi := MeshInstance3D.new()
		mi.mesh = pole_mesh
		body.add_child(mi)
		var arm := MeshInstance3D.new()
		arm.mesh = arm_mesh
		arm.position.y = POLE_HEIGHT * 0.5 - 0.7
		body.add_child(arm)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var top := xf.origin + Vector3.UP * (POLE_HEIGHT - 1.1)
		var across := xf.basis.x.normalized()
		tips.append([top - across * 0.75, top + across * 0.75])
	# Wires, sagging a little between neighbours.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in tips.size() - 1:
		for w: int in 2:
			var a: Vector3 = tips[i][w]
			var b: Vector3 = tips[i + 1][w]
			if a.distance_to(b) > POLE_SPACING * 1.6:
				continue
			_wire(st, a, b)
	var wires := MeshInstance3D.new()
	wires.name = "Wires"
	wires.mesh = st.commit()
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.08, 0.08, 0.08)
	wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wires.material_override = wire_mat
	wires.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wires)
	return root


## A place off the road (its frame's -Z faces the road). Returns the node and, as its
## `loot_spots` meta, local points where things can be left.
static func poi(kind: int) -> Node3D:
	match kind:
		0:
			return _cabin()
		1:
			return _tower()
		2:
			return _wreck()
	return _lookout()


static func _cabin() -> Node3D:
	var root := Node3D.new()
	root.name = "Cabin"
	var w := 6.0
	var d := 5.0
	var h := 2.6
	var logs := WOOD.lightened(0.05)
	# Walls: back, sides, and the front either side of the door.
	_box(root, Vector3(w, h, 0.3), Vector3(0.0, h * 0.5, d * 0.5), logs, true)
	for x: float in [-w * 0.5, w * 0.5]:
		_box(root, Vector3(0.3, h, d), Vector3(x, h * 0.5, 0.0), logs, true)
	for x: float in [-(w * 0.5 + 0.7) * 0.5 - 0.35, (w * 0.5 + 0.7) * 0.5 + 0.35]:
		_box(root, Vector3(w * 0.5 - 0.7, h, 0.3), Vector3(x, h * 0.5, -d * 0.5), logs, true)
	_box(root, Vector3(1.4, 0.5, 0.3), Vector3(0.0, h - 0.25, -d * 0.5), logs, true)
	# Log courses, for looks.
	for k: int in 6:
		_box(root, Vector3(w + 0.3, 0.06, d + 0.3), Vector3(0.0, 0.3 + k * 0.42, 0.0), WOOD_DARK, false)
	# A pitched roof and a stone chimney.
	for side: float in [-1.0, 1.0]:
		var slab := _box(root, Vector3(w * 0.5 + 0.9, 0.18, d + 1.2), Vector3(side * (w * 0.25 + 0.1), h + 0.95, 0.0), Color(0.3, 0.24, 0.2), true)
		slab.rotation.z = -side * 0.62
	_box(root, Vector3(0.8, 4.4, 0.8), Vector3(w * 0.5 - 0.6, 2.2, 1.3), Color(0.5, 0.49, 0.46), true)
	# A porch step and a table inside.
	_box(root, Vector3(2.0, 0.2, 1.0), Vector3(0.0, 0.1, -d * 0.5 - 0.6), WOOD_DARK, true)
	_box(root, Vector3(1.4, 0.08, 0.8), Vector3(-1.5, 0.78, 1.2), WOOD, true)
	for p: Vector3 in [Vector3(-2.1, 0.37, 0.9), Vector3(-0.9, 0.37, 0.9), Vector3(-2.1, 0.37, 1.5), Vector3(-0.9, 0.37, 1.5)]:
		_box(root, Vector3(0.08, 0.74, 0.08), p, WOOD_DARK, false)
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.72, 0.4)
	lamp.light_energy = 0.8
	lamp.omni_range = 5.0
	lamp.position = Vector3(0.0, 2.1, 0.5)
	root.add_child(lamp)
	root.set_meta(&"loot_spots", [Vector3(-1.5, 0.9, 1.2), Vector3(1.8, 0.1, 1.6), Vector3(1.9, 0.1, -0.8), Vector3(-2.0, 0.1, -1.2)])
	return root


static func _tower() -> Node3D:
	var root := Node3D.new()
	root.name = "Tower"
	var top := 12.0
	var steel := Color(0.55, 0.55, 0.52)
	for x: float in [-1.8, 1.8]:
		for z: float in [-1.8, 1.8]:
			_box(root, Vector3(0.25, top, 0.25), Vector3(x, top * 0.5, z), steel, true)
	for k: int in 3:
		var y := 2.5 + k * 3.6
		for z: float in [-1.8, 1.8]:
			_box(root, Vector3(3.6, 0.12, 0.12), Vector3(0.0, y, z), steel, false)
		for x: float in [-1.8, 1.8]:
			_box(root, Vector3(0.12, 0.12, 3.6), Vector3(x, y, 0.0), steel, false)
	# The cab: walls with a band of windows, a roof.
	_box(root, Vector3(4.6, 0.3, 4.6), Vector3(0.0, top + 0.15, 0.0), WOOD_DARK, true)
	_box(root, Vector3(4.4, 1.0, 4.4), Vector3(0.0, top + 0.8, 0.0), Color(0.78, 0.74, 0.62), false)
	_box(root, Vector3(4.42, 1.0, 4.42), Vector3(0.0, top + 1.8, 0.0), Color(0.16, 0.2, 0.24), false)
	var roof := _box(root, Vector3(5.4, 0.3, 5.4), Vector3(0.0, top + 2.45, 0.0), Color(0.55, 0.18, 0.12), false)
	roof.rotation.y = PI / 4.0
	# A shed at the foot, where the ranger left supplies.
	_box(root, Vector3(2.6, 2.0, 2.0), Vector3(3.8, 1.0, 1.0), WOOD_GREY, true)
	_box(root, Vector3(3.0, 0.14, 2.4), Vector3(3.8, 2.07, 1.0), Color(0.3, 0.3, 0.3), false)
	root.set_meta(&"loot_spots", [Vector3(3.8, 0.1, -0.6), Vector3(2.4, 0.1, -0.5), Vector3(0.0, 0.1, 0.0)])
	return root


static func _wreck() -> Node3D:
	var root := Node3D.new()
	root.name = "Wreck"
	var car := Node3D.new()
	car.rotation = Vector3(0.05, 0.5, 0.12)
	root.add_child(car)
	_box(car, Vector3(1.8, 0.9, 4.3), Vector3(0.0, 0.55, 0.0), RUST, true)
	_box(car, Vector3(1.6, 0.7, 2.0), Vector3(0.0, 1.35, 0.3), RUST.darkened(0.1), true)
	_box(car, Vector3(1.62, 0.45, 1.2), Vector3(0.0, 1.4, 0.2), Color(0.12, 0.14, 0.15), false) # Empty windows.
	for x: float in [-0.95, 0.95]:
		for z: float in [-1.4, 1.4]:
			if x > 0.0 and z > 0.0:
				continue # That one's lying beside it.
			var tire := _cylinder(car, 0.36, 0.25, Vector3(x, 0.3, z), Color(0.1, 0.1, 0.1))
			tire.rotation.z = PI / 2.0
	var loose := _cylinder(root, 0.36, 0.25, Vector3(2.4, 0.13, 1.6), Color(0.1, 0.1, 0.1))
	loose.rotation.x = 0.1
	_box(root, Vector3(1.2, 0.05, 0.9), Vector3(-2.0, 0.03, -1.4), RUST.lightened(0.1), false) # A door, off.
	root.set_meta(&"loot_spots", [Vector3(-1.9, 0.1, 1.5), Vector3(2.2, 0.1, -1.0), Vector3(-2.3, 0.15, -1.4)])
	return root


## The top of a hill with a view: a bench, a cairn, a picnic left behind.
static func _lookout() -> Node3D:
	var root := Node3D.new()
	root.name = "Lookout"
	_box(root, Vector3(1.8, 0.08, 0.45), Vector3(0.0, 0.45, 0.0), WOOD, true)
	_box(root, Vector3(1.8, 0.4, 0.06), Vector3(0.0, 0.75, 0.22), WOOD, false)
	for x: float in [-0.75, 0.75]:
		_box(root, Vector3(0.08, 0.45, 0.4), Vector3(x, 0.22, 0.0), WOOD_DARK, false)
	for k: int in 5:
		var r := 0.5 - k * 0.08
		var stone := _box(root, Vector3(r, 0.25, r * 0.9), Vector3(2.2, 0.12 + k * 0.23, 0.6), Color(0.52, 0.5, 0.47), k == 0)
		stone.rotation.y = k * 0.7
	root.set_meta(&"loot_spots", [Vector3(-0.5, 0.55, 0.0), Vector3(1.2, 0.1, -0.8), Vector3(-1.6, 0.1, -0.6)])
	return root


# --- pieces --------------------------------------------------------------------------------

## A solid slab (deck, beam): collision and a mesh, centred at `center`.
static func _slab(parent: Node3D, size: Vector3, center: Vector3, color: Color = WOOD_DARK) -> Node3D:
	return _box(parent, size, center, color, true)


## Rows of boards across a deck span (along the road from `span.x` to `span.y`), each a
## slightly different grey-brown; at the hole's edge a couple are snapped short.
static func _boards(parent: Node3D, span: Vector2, rng: RandomNumberGenerator, before_hole: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var board := BoxMesh.new()
	board.size = Vector3(DECK_HALF * 2.0, 0.05, BOARD - 0.03)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	board.material = mat
	mm.mesh = board
	var count := int((span.y - span.x) / BOARD)
	mm.instance_count = count
	for k: int in count:
		var along := span.x + (k + 0.5) * BOARD
		var near_hole := (before_hole and k >= count - 2) or (not before_hole and k < 2)
		var length := rng.randf_range(0.45, 0.8) if near_hole else 1.0
		var shift := (1.0 - length) * DECK_HALF * (1.0 if rng.randf() < 0.5 else -1.0)
		var basis := Basis.from_scale(Vector3(length, 1.0, 1.0))
		mm.set_instance_transform(k, Transform3D(basis, Vector3(shift, DECK_TOP + 0.005, -along)))
		mm.set_instance_color(k, WOOD_GREY.lerp(WOOD, rng.randf()).darkened(rng.randf_range(0.0, 0.15)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)


## A rail along one side of a deck: posts every `spacing` m, a top rail, and a solid (unseen)
## kerb the height of the rail so nothing rolls off.
static func _rail(parent: Node3D, x: float, from: float, to: float, spacing: float) -> void:
	var along := from
	while along <= to + 0.01:
		_box(parent, Vector3(0.14, 0.95, 0.14), Vector3(x, DECK_TOP + 0.47, -along), WOOD_DARK, false)
		along += spacing
	_box(parent, Vector3(0.12, 0.12, to - from), Vector3(x, DECK_TOP + 0.9, -(from + to) * 0.5), WOOD, false)
	var kerb := StaticBody3D.new()
	kerb.collision_layer = TerrainStreamer.WORLD_LAYER
	kerb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.14, 0.95, to - from)
	cs.shape = box
	kerb.add_child(cs)
	kerb.position = Vector3(x, DECK_TOP + 0.47, -(from + to) * 0.5)
	parent.add_child(kerb)


## A trestle bent at `z` (local): two legs down `depth` metres with a cross-brace.
static func _bent(parent: Node3D, z: float, depth: float, half_width: float = 1.8) -> void:
	for x: float in [-half_width, half_width]:
		_box(parent, Vector3(0.3, depth, 0.3), Vector3(x, -DECK_THICK - depth * 0.5, z), WOOD_DARK, false)
	var brace_len := sqrt(4.0 * half_width * half_width + depth * depth * 0.25)
	var brace := _box(parent, Vector3(0.18, brace_len, 0.18), Vector3(0.0, -DECK_THICK - depth * 0.3, z), WOOD, false)
	brace.rotation.z = atan2(2.0 * half_width, depth * 0.5)
	_box(parent, Vector3(half_width * 2.0 + 0.4, 0.25, 0.25), Vector3(0.0, -DECK_THICK - 0.15, z), WOOD, false)


static func _wire(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var segments := 6
	var width := 0.035
	for k: int in segments:
		var p0 := _sag(a, b, float(k) / segments)
		var p1 := _sag(a, b, float(k + 1) / segments)
		for up: Vector3 in [Vector3.UP * width, (b - a).cross(Vector3.UP).normalized() * width]:
			st.add_vertex(p0 - up)
			st.add_vertex(p1 - up)
			st.add_vertex(p1 + up)
			st.add_vertex(p0 - up)
			st.add_vertex(p1 + up)
			st.add_vertex(p0 + up)


static func _sag(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, t) + Vector3.DOWN * 0.7 * 4.0 * t * (1.0 - t)


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.88
		_materials[color] = m
	return _materials[color]


## A box centred at `center`, solid (a StaticBody3D on the world layer) or just a mesh.
static func _box(parent: Node3D, size: Vector3, center: Vector3, color: Color, solid: bool) -> Node3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if not solid:
		parent.add_child(mi)
		mi.position = center
		return mi
	var body := StaticBody3D.new()
	body.collision_layer = TerrainStreamer.WORLD_LAYER
	body.collision_mask = 0
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	parent.add_child(body)
	body.position = center
	return body


static func _cylinder(parent: Node3D, radius: float, height: float, center: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = _material(color)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)
	mi.position = center
	return mi
