class_name TripStops
extends RefCounted
## Builds the trip's places: the start camp, gas stations and home, plus roadside warning
## signs. Low-poly: CC0 Kenney models (assets/models/kenney/, see CREDITS.md) where they fit,
## simple blocks for the rest. Each stop's frame has its -Z facing the road.

const KENNEY := "res://assets/models/kenney/%s.glb"
const SIGN_TEXT := Color(0.12, 0.1, 0.08)
## Along-the-road thickness of a bridge abutment, metres.
const ABUTMENT_DEPTH := 1.4

static var _cache: Dictionary[String, PackedScene] = {}


static func build(kind: int, index: int, stations: int) -> Node3D:
	match kind:
		Trip.PAD_CAMP:
			return _camp()
		Trip.PAD_HOME:
			return _home()
	return _station(index, stations)


## A Kenney model scaled so its largest dimension (or `axis` if given: 0 x, 1 y, 2 z) is `size`.
static func model(path: String, size: float, axis: int = -1) -> Node3D:
	if not _cache.has(path):
		_cache[path] = load(KENNEY % path)
	var node := _cache[path].instantiate() as Node3D
	var aabb := _aabb(node)
	var extent := aabb.size[axis] if axis >= 0 else maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	node.scale = Vector3.ONE * (size / maxf(extent, 0.001))
	return node


static func _aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for n: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var box := mi.transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


static func _place(parent: Node3D, child: Node3D, pos: Vector3, yaw: float = 0.0) -> Node3D:
	parent.add_child(child)
	child.position = pos
	child.rotation.y = yaw
	return child


static func _block(size: Vector3, color: Color, solid: bool = true) -> Node3D:
	var root := StaticBody3D.new() if solid else Node3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position.y = size.y * 0.5
	root.add_child(mi)
	if solid:
		var body := root as StaticBody3D
		body.collision_layer = TerrainStreamer.WORLD_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position.y = size.y * 0.5
		body.add_child(shape)
	return root


static func _label(text: String, size: int, color: Color = SIGN_TEXT) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.pixel_size = 0.01
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	label.rotation.y = PI # Face -Z, towards the road.
	return label


static func _camp() -> Node3D:
	var camp := Node3D.new()
	camp.name = "Camp"
	_place(camp, model("nature/tent", 2.3, 1), Vector3(-6.0, 0.0, 9.0), 0.4)
	_place(camp, model("nature/campfire", 1.3), Vector3(-2.0, 0.0, 7.5))
	_place(camp, model("nature/log_stack", 1.4), Vector3(0.5, 0.0, 9.5), 1.2)
	_place(camp, model("survival/bedroll", 1.9, 2), Vector3(-4.0, 0.02, 6.5), 0.2)
	var fire := OmniLight3D.new()
	fire.light_color = Color(1.0, 0.6, 0.3)
	fire.light_energy = 1.5
	fire.omni_range = 6.0
	_place(camp, fire, Vector3(-2.0, 0.6, 7.5))
	_place(camp, _block(Vector3(0.8, 0.04, 0.6), Color(0.15, 0.15, 0.15), false), Vector3(-2.0, 0.5, 7.5)) # Grate.
	_place(camp, Grill.new(), Vector3(-2.0, 0.54, 7.5))
	_place(camp, model("survival/signpost_single", 2.2, 1), Vector3(6.0, 0.0, 5.5))
	var text := _label("CAMP\nHome is down the road", 40)
	text.position = Vector3(6.0, 1.55, 5.43)
	camp.add_child(text)
	return camp


static func _station(index: int, stations: int) -> Node3D:
	var st := Node3D.new()
	st.name = "Station%d" % index
	# The shop behind, a canopy over two pumps in front of it.
	_place(st, _block(Vector3(9.0, 3.6, 6.0), Color(0.93, 0.88, 0.74)), Vector3(0.0, 0.0, 8.0))
	_place(st, _block(Vector3(9.4, 0.5, 6.4), Color(0.75, 0.2, 0.15), false), Vector3(0.0, 3.6, 8.0))
	_place(st, _block(Vector3(1.2, 2.1, 0.08), Color(0.35, 0.25, 0.18), false), Vector3(-2.0, 0.0, 4.98)) # Door.
	_place(st, _block(Vector3(3.0, 1.2, 0.06), Color(0.5, 0.65, 0.75), false), Vector3(1.8, 1.0, 4.98)) # Window.
	var name := _label("GAS  ·  DINER\nStation %d of %d" % [index, stations], 96, Color(0.98, 0.95, 0.85))
	name.position = Vector3(0.0, 4.4, 4.7)
	st.add_child(name)
	_place(st, _block(Vector3(11.0, 0.35, 7.0), Color(0.9, 0.9, 0.88), false), Vector3(0.0, 4.6, -1.5)) # Canopy.
	for x: float in [-4.8, 4.8]:
		for z: float in [-4.3, 1.3]:
			_place(st, _block(Vector3(0.3, 4.6, 0.3), Color(0.85, 0.85, 0.82)), Vector3(x, 0.0, z))
	for x: float in [-1.8, 1.8]:
		_place(st, _block(Vector3(0.7, 0.2, 1.4), Color(0.6, 0.6, 0.58)), Vector3(x, 0.0, -1.5)) # Island.
		_place(st, _block(Vector3(0.55, 1.6, 0.4), Color(0.8, 0.18, 0.12)), Vector3(x, 0.2, -1.5)) # Pump.
		_place(st, _block(Vector3(0.45, 0.35, 0.42), Color(0.95, 0.95, 0.9), false), Vector3(x, 1.8, -1.5))
		var pump := Interactable.new()
		pump.name = "Pump%d" % roundi(x)
		pump.reach = 2.4
		pump.add_to_group(&"fuel_pumps")
		_place(st, pump, Vector3(x, 1.2, -1.5))
	_place(st, model("survival/workbench", 1.1, 1), Vector3(6.2, 0.0, 6.0), -PI / 2.0)
	var welder := Interactable.new()
	welder.name = "Welder"
	welder.reach = 2.4
	welder.add_to_group(&"welders")
	_place(st, welder, Vector3(6.2, 1.0, 6.0))
	var weld := _label("WELDER", 48)
	weld.position = Vector3(6.2, 1.7, 5.4)
	st.add_child(weld)
	for p: Vector3 in [Vector3(-5.6, 0, 6.2), Vector3(-5.9, 0, 7.1), Vector3(5.8, 0, 9.8)]:
		_place(st, model("survival/barrel", 1.0, 1), p)
	_place(st, model("survival/crate", 0.9, 1), Vector3(-5.2, 0.0, 9.6), 0.3)
	_place(st, _block(Vector3(0.9, 0.9, 0.6), Color(0.12, 0.12, 0.13)), Vector3(-6.8, 0.0, 3.2)) # Barbecue.
	_place(st, Grill.new(), Vector3(-6.8, 0.9, 3.2), PI / 2.0)
	var bbq := _label("GRILL", 40)
	bbq.position = Vector3(-6.8, 1.5, 2.85)
	st.add_child(bbq)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 2.0
	lamp.omni_range = 12.0
	lamp.light_color = Color(1.0, 0.95, 0.85)
	_place(st, lamp, Vector3(0.0, 4.2, -1.5))
	return st


static func _home() -> Node3D:
	var home := Node3D.new()
	home.name = "Home"
	_place(home, model("suburban/house", 11.0), Vector3(0.0, 0.0, 9.0), PI)
	for x: float in [-9.0, -3.2, 3.2, 9.0]:
		_place(home, model("suburban/fence", 6.0, 0), Vector3(x, 0.0, 1.5))
	var sign := _label("HOME\nYou made it!", 128, Color(0.98, 0.9, 0.55))
	sign.position = Vector3(0.0, 7.5, 3.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	home.add_child(sign)
	return home


## One end of a washed-out bridge: a concrete block whose top is at road level (origin at the
## top centre), reaching well down into the trench, with a snapped timber sticking out.
static func abutment(width: float) -> Node3D:
	var root := Node3D.new()
	root.name = "Abutment"
	var block := _block(Vector3(width, 4.0, ABUTMENT_DEPTH), Color(0.62, 0.6, 0.56))
	block.position.y = -4.0
	root.add_child(block)
	var beam := _block(Vector3(0.25, 0.25, 1.1), Color(0.35, 0.26, 0.17), false)
	beam.position = Vector3(width * 0.3, -0.3, -ABUTMENT_DEPTH * 0.5 - 0.4)
	beam.rotation = Vector3(0.35, 0.1, 0.0)
	root.add_child(beam)
	return root


## A cave in a clearing off the road (its frame's -Z faces the road): a horseshoe of rock
## walls under a slab roof, timber props at the mouth, a lantern, and a crate. The trip puts
## supplies inside. `canyon` colours it red rock.
static func cave(canyon: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Cave"
	var rock := Color(0.62, 0.36, 0.25) if canyon else Color(0.45, 0.44, 0.42)
	# Walls round the back and sides, open towards the road.
	for i: int in 9:
		var a := lerpf(-PI * 0.78, PI * 0.78, i / 8.0) + PI # 0 faces the road (-Z).
		var at := Vector3(sin(a), 0.0, cos(a)) * -5.6
		var wall := _block(Vector3(3.2, 4.8, 1.6), rock.darkened(0.08 * (i % 3)))
		_place(root, wall, at + Vector3(0.0, -0.3, 0.0), a)
	var roof := _block(Vector3(13.0, 1.4, 12.0), rock.darkened(0.15))
	_place(root, roof, Vector3(0.0, 4.2, 0.6))
	# A mine-style timber frame at the mouth.
	var wood := Color(0.40, 0.28, 0.17)
	for x: float in [-2.6, 2.6]:
		_place(root, _block(Vector3(0.35, 3.6, 0.35), wood), Vector3(x, 0.0, -4.4))
	_place(root, _block(Vector3(5.9, 0.4, 0.45), wood), Vector3(0.0, 3.6, -4.4))
	_place(root, model("survival/crate", 0.9, 1), Vector3(-2.4, 0.0, 2.2), 0.4)
	_place(root, model("survival/barrel", 1.0, 1), Vector3(2.6, 0.0, 2.6))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.75, 0.45)
	lamp.light_energy = 1.6
	lamp.omni_range = 8.0
	_place(root, lamp, Vector3(0.0, 2.8, 1.0))
	var text := _label("CAVE", 40)
	text.position = Vector3(0.0, 4.1, -4.72)
	root.add_child(text)
	return root
