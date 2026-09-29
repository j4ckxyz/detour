class_name TreeMesh
## Procedural low-poly pine (~70 triangles). Stands in for the real pine models far away,
## where only the silhouette reads.

const TRUNK := Color(0.36, 0.25, 0.17)
const NEEDLES_DARK := Color(0.12, 0.25, 0.14)
const NEEDLES_LIGHT := Color(0.27, 0.44, 0.22)

static var _material: StandardMaterial3D


## Builds a pine `height` metres tall (the design is 10.2 m; other heights scale it).
## `dark`/`light` colour the needles (snowy firs pass white for `light`).
static func build(height: float = 10.2, segments: int = 7, dark: Color = NEEDLES_DARK, light: Color = NEEDLES_LIGHT) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := height / 10.2
	_frustum(st, 0.0, 2.4 * k, 0.30 * k, 0.18 * k, segments, TRUNK, TRUNK, false)
	_frustum(st, 1.6 * k, 6.2 * k, 2.4 * k, 0.0, segments, dark, dark.lerp(light, 0.5), true)
	_frustum(st, 3.9 * k, 8.4 * k, 1.9 * k, 0.0, segments, dark.lerp(light, 0.3), light.lerp(dark, 0.2), true)
	_frustum(st, 6.0 * k, height, 1.3 * k, 0.0, segments, dark.lerp(light, 0.5), light, true)
	return _finish(st)


## A bayou tree: a thick, flared trunk under a wide, flat, drooping olive crown.
static func bayou(height: float = 8.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := height / 8.0
	var bark := Color(0.30, 0.25, 0.19)
	var leaf := Color(0.30, 0.38, 0.16)
	var moss := Color(0.42, 0.47, 0.30)
	_frustum(st, 0.0, 1.2 * k, 0.75 * k, 0.35 * k, 7, bark, bark, false)
	_frustum(st, 1.2 * k, 5.2 * k, 0.35 * k, 0.22 * k, 7, bark, bark, false)
	_frustum(st, 4.2 * k, 6.4 * k, 3.4 * k, 2.2 * k, 8, moss, leaf, true)
	_frustum(st, 6.4 * k, height, 2.2 * k, 0.0, 8, leaf, leaf.lightened(0.1), false)
	return _finish(st)


## A dead snag: a bare grey trunk with a couple of broken limbs.
static func snag(height: float = 7.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := height / 7.0
	var grey := Color(0.45, 0.42, 0.38)
	_frustum(st, 0.0, height, 0.32 * k, 0.06 * k, 6, grey.darkened(0.2), grey, false)
	_frustum(st, 3.0 * k, 5.0 * k, 0.1 * k, 0.03 * k, 5, grey, grey, false, Vector3(0.6 * k, 0.0, 0.0))
	_frustum(st, 4.2 * k, 5.8 * k, 0.08 * k, 0.02 * k, 5, grey, grey, false, Vector3(-0.5 * k, 0.0, 0.3 * k))
	return _finish(st)


## A saguaro cactus: a green column with two arms.
static func cactus(height: float = 4.5) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := height / 4.5
	var green := Color(0.30, 0.48, 0.25)
	var tip := green.lightened(0.15)
	_frustum(st, 0.0, height, 0.28 * k, 0.24 * k, 8, green.darkened(0.1), tip, false)
	for arm: Array in [[1.6, 0.62, 1.2], [2.3, -0.55, 0.9]]:
		var y: float = arm[0] * k
		var x: float = arm[1] * k
		_frustum(st, y - 0.15 * k, y + 0.15 * k, 0.16 * k, 0.16 * k, 6, green, green, false, Vector3(x * 0.5, 0.0, 0.0))
		_frustum(st, y, y + float(arm[2]) * k, 0.17 * k, 0.15 * k, 7, green, tip, true, Vector3(x, 0.0, 0.0))
	return _finish(st)


## A juniper: a short twisted trunk and a rounded, dusty blue-green crown.
static func juniper(height: float = 4.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := height / 4.0
	var bark := Color(0.40, 0.30, 0.22)
	var leaf := Color(0.35, 0.45, 0.36)
	_frustum(st, 0.0, 1.4 * k, 0.22 * k, 0.12 * k, 6, bark, bark, false)
	_frustum(st, 1.0 * k, 2.4 * k, 0.9 * k, 1.4 * k, 7, leaf.darkened(0.15), leaf, true)
	_frustum(st, 2.4 * k, height, 1.4 * k, 0.2 * k, 7, leaf, leaf.lightened(0.1), false)
	return _finish(st)


static func _finish(st: SurfaceTool) -> ArrayMesh:
	var mesh := st.commit()
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.92
	mesh.surface_set_material(0, _material)
	return mesh


## Adds a (truncated) cone around the Y axis; `r1 == 0` makes a pointed cone.
static func _frustum(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, segments: int,
		bottom_color: Color, top_color: Color, bottom_cap: bool, at: Vector3 = Vector3.ZERO) -> void:
	var height := y1 - y0
	for i: int in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var am := (a0 + a1) * 0.5
		var p0 := at + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := at + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var q0 := at + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var q1 := at + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var n0 := Vector3(cos(a0) * height, r0 - r1, sin(a0) * height).normalized()
		var n1 := Vector3(cos(a1) * height, r0 - r1, sin(a1) * height).normalized()
		var nm := Vector3(cos(am) * height, r0 - r1, sin(am) * height).normalized()
		var out := Vector3(cos(am), 0.0, sin(am))
		if r1 <= 0.0:
			_tri(st, [p0, p1, q0], [n0, n1, nm], [bottom_color, bottom_color, top_color], out)
		else:
			_tri(st, [p0, p1, q1], [n0, n1, n1], [bottom_color, bottom_color, top_color], out)
			_tri(st, [p0, q1, q0], [n0, n1, n0], [bottom_color, top_color, top_color], out)
		if bottom_cap:
			var c := at + Vector3(0.0, y0, 0.0)
			var shade := bottom_color.darkened(0.25)
			_tri(st, [c, p0, p1], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], [shade, shade, shade], Vector3.DOWN)


## Emits one triangle, reordering it so it faces `outward` (Godot: clockwise = front).
static func _tri(st: SurfaceTool, p: Array[Vector3], n: Array[Vector3], c: Array[Color], outward: Vector3) -> void:
	var order: Array[int] = [0, 1, 2]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(outward) > 0.0:
		order = [0, 2, 1]
	for i: int in order:
		st.set_color(c[i])
		st.set_normal(n[i])
		st.add_vertex(p[i])
