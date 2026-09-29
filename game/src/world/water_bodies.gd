class_name WaterBodies
extends Node3D
## Draws the trip's open water (PLAN.md §5): the rivers the road fords and the bayou ponds.
## Frozen lakes and ponds are just icy ground (the terrain colours them). The heights and
## extents match rvgen (route.rs: water_at).

const FORD := 4
const RIVER_BANK := 6.0
const RIVER_FADE := 18.0

static var _material: StandardMaterial3D


func build(trip: Dictionary) -> void:
	var river_half := float(trip.get("river_half", 60.0))
	for o: Dictionary in trip.get("obstacles", []):
		if int(o["kind"]) != FORD:
			continue
		var mesh := PlaneMesh.new()
		mesh.size = Vector2(float(o["length"]) + RIVER_BANK * 1.2, (river_half - RIVER_FADE * 0.5) * 2.0)
		mesh.material = _water()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var dir: Vector3 = o["dir"]
		var pos: Vector3 = o["pos"]
		# The plane's X runs along the road (the channel's width), Z across it (the river).
		mi.global_transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)), pos + Vector3.DOWN * 0.05)
	for l: Dictionary in trip.get("lakes", []):
		if bool(l["frozen"]):
			continue
		var disc := CylinderMesh.new()
		disc.top_radius = float(l["radius"])
		disc.bottom_radius = float(l["radius"])
		disc.height = 0.02
		disc.radial_segments = 28
		disc.rings = 1
		disc.material = _water()
		var mi := MeshInstance3D.new()
		mi.mesh = disc
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.global_position = l["pos"]


static func _water() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.18, 0.42, 0.55, 0.72)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.roughness = 0.08
		_material.metallic = 0.2
	return _material
