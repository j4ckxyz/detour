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
## nothing but its shadow (your own body, seen from inside it). `hat` and `glasses` are what's
## worn (see `Cosmetics`).
static func build(color: Color, tag: String = "", shadow_only: bool = false, hat: StringName = Cosmetics.DEFAULT_HAT, glasses: StringName = Cosmetics.DEFAULT_GLASSES) -> Node3D:
	var root := Node3D.new()
	root.name = "Avatar"
	var vest := _material(color)
	# The pill: skin all the way up (the top is the face), trousers over the bottom.
	_capsule(root, RADIUS, 1.62, Vector3(0.0, 0.93, 0.0), _material(SKIN))
	_capsule(root, RADIUS + 0.006, 0.9, Vector3(0.0, 0.57, 0.0), _material(TROUSERS))
	# The vest round the middle, open at the front over the shirt.
	_cylinder(root, RADIUS + 0.014, RADIUS + 0.014, 0.52, Vector3(0.0, 0.87, 0.0), vest)
	_box(root, Vector3(0.2, 0.5, 0.05), Vector3(0.0, 0.87, -RADIUS - 0.01), _material(SHIRT))
	var top := _add_glasses(root, glasses)
	top = maxf(top, _add_hat(root, hat, color))
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
		label.position = Vector3(0.0, maxf(2.15, top + 0.3), 0.0)
		label.font_size = 40
		label.outline_size = 10
		label.no_depth_test = true
		label.pixel_size = 0.004
		root.add_child(label)
	return root


## Glasses on the face. Returns how high the highest part reaches.
static func _add_glasses(root: Node3D, glasses: StringName) -> float:
	var dark := _material(DARK)
	match glasses:
		&"shades":
			for x: float in [-0.1, 0.1]:
				var lens := _sphere(root, 0.065, Vector3(x, 1.42, -RADIUS + 0.04), dark)
				lens.scale = Vector3(1.1, 0.85, 0.45)
			_box(root, Vector3(0.08, 0.02, 0.02), Vector3(0.0, 1.44, -RADIUS - 0.005), dark)
		&"round":
			var wire := _material(Color(0.55, 0.5, 0.35))
			for x: float in [-0.1, 0.1]:
				var ring := TorusMesh.new()
				ring.inner_radius = 0.052
				ring.outer_radius = 0.066
				ring.rings = 12
				ring.ring_segments = 6
				ring.material = wire
				var mi := _add(root, ring, Vector3(x, 1.43, -RADIUS - 0.005))
				mi.rotation.x = PI / 2.0
			_box(root, Vector3(0.05, 0.012, 0.012), Vector3(0.0, 1.45, -RADIUS - 0.005), wire)
		&"goggles":
			var strap := _material(Color(0.25, 0.2, 0.15))
			_cylinder(root, RADIUS + 0.012, RADIUS + 0.012, 0.07, Vector3(0.0, 1.44, 0.0), strap)
			var lens_material := _material(Color(0.95, 0.6, 0.15))
			for x: float in [-0.1, 0.1]:
				var lens := _sphere(root, 0.075, Vector3(x, 1.44, -RADIUS + 0.03), lens_material)
				lens.scale = Vector3(1.15, 0.95, 0.5)
			_box(root, Vector3(0.06, 0.03, 0.03), Vector3(0.0, 1.44, -RADIUS + 0.01), strap)
	return 1.5


## A hat on the head. Returns how high it reaches (metres above the feet).
static func _add_hat(root: Node3D, hat: StringName, color: Color) -> float:
	match hat:
		&"beanie":
			# A hemisphere with a turned-up brim, in a darker shade of the player's colour.
			var beanie := _material(color.darkened(0.35))
			var cap := _sphere(root, RADIUS - 0.005, Vector3(0.0, 1.5, 0.0), beanie)
			(cap.mesh as SphereMesh).is_hemisphere = true
			(cap.mesh as SphereMesh).height = RADIUS
			_cylinder(root, RADIUS + 0.015, RADIUS + 0.015, 0.07, Vector3(0.0, 1.53, 0.0), beanie)
			return 1.86
		&"cap":
			var cloth := _material(color)
			var crown := _sphere(root, RADIUS, Vector3(0.0, 1.5, 0.0), cloth)
			(crown.mesh as SphereMesh).is_hemisphere = true
			(crown.mesh as SphereMesh).height = RADIUS * 0.9
			var peak := _box(root, Vector3(0.3, 0.02, 0.24), Vector3(0.0, 1.53, -RADIUS - 0.08), cloth)
			peak.rotation.x = 0.15
			return 1.84
		&"bucket":
			var cloth := _material(Color(0.78, 0.74, 0.55))
			_cylinder(root, 0.29, 0.36, 0.22, Vector3(0.0, 1.63, 0.0), cloth)
			_cylinder(root, 0.5, 0.5, 0.025, Vector3(0.0, 1.52, 0.0), cloth)
			return 1.75
		&"cowboy":
			var felt := _material(Color(0.5, 0.33, 0.18))
			_cylinder(root, 0.66, 0.66, 0.03, Vector3(0.0, 1.55, 0.0), felt)
			_cylinder(root, 0.27, 0.34, 0.3, Vector3(0.0, 1.7, 0.0), felt)
			_cylinder(root, 0.345, 0.345, 0.05, Vector3(0.0, 1.6, 0.0), _material(Color(0.25, 0.15, 0.1)))
			return 1.86
		&"hardhat":
			var yellow := _material(Color(0.95, 0.75, 0.1))
			var dome := _sphere(root, RADIUS + 0.03, Vector3(0.0, 1.5, 0.0), yellow)
			(dome.mesh as SphereMesh).is_hemisphere = true
			(dome.mesh as SphereMesh).height = RADIUS + 0.04
			_cylinder(root, RADIUS + 0.09, RADIUS + 0.09, 0.025, Vector3(0.0, 1.5, 0.0), yellow)
			_box(root, Vector3(0.05, 0.04, 0.5), Vector3(0.0, 1.87, 0.0), yellow)
			return 1.9
		&"chef":
			var white := _material(Color(0.97, 0.97, 0.95))
			_cylinder(root, 0.3, 0.3, 0.26, Vector3(0.0, 1.66, 0.0), white)
			_sphere(root, 0.36, Vector3(0.0, 1.98, 0.0), white)
			return 2.34
		&"tophat":
			var black := _material(Color(0.08, 0.08, 0.1))
			_cylinder(root, 0.5, 0.5, 0.03, Vector3(0.0, 1.6, 0.0), black)
			_cylinder(root, 0.29, 0.31, 0.42, Vector3(0.0, 1.8, 0.0), black)
			_cylinder(root, 0.315, 0.315, 0.07, Vector3(0.0, 1.66, 0.0), _material(Color(0.6, 0.12, 0.12)))
			return 2.03
		&"antlers":
			var horn := _material(Color(0.62, 0.5, 0.36))
			for side: float in [-1.0, 1.0]:
				var stem := _cylinder(root, 0.02, 0.03, 0.5, Vector3(side * 0.22, 1.9, 0.0), horn)
				stem.rotation.z = -side * 0.5
				for k: int in 2:
					var tine := _cylinder(root, 0.012, 0.02, 0.22, Vector3(side * (0.3 + 0.08 * k), 1.95 + 0.16 * k, 0.0), horn)
					tine.rotation.z = side * 0.7
			return 2.2
	return 0.0


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
