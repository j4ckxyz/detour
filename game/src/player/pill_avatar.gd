class_name PillAvatar
## A player's body, made of primitives until there's a Blender model: a stubby pill-shaped
## person (one rounded body whose top is the head) in dark glasses, a beanie and a vest in
## the player's colour over a white shirt, light trousers, stubby arms and feet. Faces -Z;
## feet at y = 0, about 1.85 m to the top of the beanie.

const SKIN := Color(0.93, 0.76, 0.62)
const SHIRT := Color(0.95, 0.95, 0.93)
const TROUSERS := Color(0.68, 0.84, 0.72)
const DARK := Color(0.12, 0.12, 0.14)
const RADIUS := 0.36


## Builds the body. `tag` is a name floating above (empty for none). `shadow_only` draws
## nothing but its shadow (your own body, seen from inside it).
static func build(color: Color, tag: String = "", shadow_only: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "Avatar"
	var vest := _material(color)
	var beanie := _material(color.darkened(0.35))
	# The pill: skin all the way up (the top is the face), trousers over the bottom.
	_capsule(root, RADIUS, 1.62, Vector3(0.0, 0.93, 0.0), _material(SKIN))
	_capsule(root, RADIUS + 0.006, 0.9, Vector3(0.0, 0.57, 0.0), _material(TROUSERS))
	# The vest round the middle, open at the front over the shirt.
	_cylinder(root, RADIUS + 0.014, RADIUS + 0.014, 0.52, Vector3(0.0, 0.87, 0.0), vest)
	_box(root, Vector3(0.2, 0.5, 0.05), Vector3(0.0, 0.87, -RADIUS - 0.01), _material(SHIRT))
	# Glasses.
	var glass := _material(DARK)
	for x: float in [-0.1, 0.1]:
		var lens := _sphere(root, 0.065, Vector3(x, 1.42, -RADIUS + 0.04), glass)
		lens.scale = Vector3(1.1, 0.85, 0.45)
	_box(root, Vector3(0.08, 0.02, 0.02), Vector3(0.0, 1.44, -RADIUS - 0.005), glass)
	# Beanie, with a turned-up brim.
	var cap := _sphere(root, RADIUS - 0.005, Vector3(0.0, 1.5, 0.0), beanie)
	(cap.mesh as SphereMesh).is_hemisphere = true
	(cap.mesh as SphereMesh).height = RADIUS
	_cylinder(root, RADIUS + 0.015, RADIUS + 0.015, 0.07, Vector3(0.0, 1.53, 0.0), beanie)
	# Stubby arms: a white sleeve, a mitten of a hand.
	for side: float in [-1.0, 1.0]:
		var arm := _capsule(root, 0.09, 0.42, Vector3(side * (RADIUS + 0.07), 0.93, 0.0), _material(SHIRT))
		arm.rotation.z = side * 0.18
		_sphere(root, 0.095, Vector3(side * (RADIUS + 0.11), 0.68, -0.02), _material(SKIN))
	# Feet.
	for side: float in [-1.0, 1.0]:
		var foot := _sphere(root, 0.12, Vector3(side * 0.15, 0.06, -0.06), _material(DARK))
		foot.scale = Vector3(1.0, 0.55, 1.45)
	if shadow_only:
		for c: Node in root.get_children():
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	if tag != "":
		var label := Label3D.new()
		label.text = tag
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0.0, 2.15, 0.0)
		label.font_size = 40
		label.outline_size = 10
		label.no_depth_test = true
		label.pixel_size = 0.004
		root.add_child(label)
	return root


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m


static func _add(root: Node3D, mesh: Mesh, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	root.add_child(mi)
	return mi


static func _capsule(root: Node3D, radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 6
	mesh.material = material
	return _add(root, mesh, pos)


static func _cylinder(root: Node3D, top: float, bottom: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.material = material
	return _add(root, mesh, pos)


static func _sphere(root: Node3D, radius: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = material
	return _add(root, mesh, pos)


static func _box(root: Node3D, size: Vector3, pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	return _add(root, mesh, pos)
