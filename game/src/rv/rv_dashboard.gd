class_name RVDashboard
extends Node3D
## The dashboard's working gauges, on the three dials modelled in the cab (rv.glb `Gauge0..2`):
## the speedometer (left, 0–120 km/h), the rev counter (behind the wheel, 0–5000 rpm, red
## from the redline) and the fuel gauge (right, E–F), each with a needle that swings to its
## reading, plus a row of warning lights above them: oil, temperature, charge (engine off) and
## a "check" light for wheels that need attention or missing parts. Built in code.

## Needle sweep: from -SWEEP (zero) clockwise to +SWEEP (full scale), radians from straight up.
const SWEEP := deg_to_rad(120.0)
const FUEL_SWEEP := deg_to_rad(60.0)
const MAX_KMH := 120.0
const MAX_RPM := 5000.0
## How fast needles move, full scale per second.
const NEEDLE_RATE := 2.5
const LIGHT_OIL := Color(1.0, 0.6, 0.1)
const LIGHT_HOT := Color(1.0, 0.15, 0.1)
const LIGHT_CHARGE := Color(1.0, 0.15, 0.1)
const LIGHT_CHECK := Color(1.0, 0.75, 0.1)

var rv: RV
## Each gauge's needle position, 0 (rest) .. 1 (full scale).
var readings: PackedFloat32Array = [0.0, 0.0, 0.0]
## Warning light name → lit.
var lights: Dictionary[StringName, bool] = {&"oil": false, &"hot": false, &"charge": false, &"check": false}

var _needles: Array[Node3D] = []
var _lamps: Dictionary[StringName, MeshInstance3D] = {}
var _lamp_colors: Dictionary[StringName, Color] = {&"oil": LIGHT_OIL, &"hot": LIGHT_HOT, &"charge": LIGHT_CHARGE, &"check": LIGHT_CHECK}


## The dials' faces in RV space (centres, facing +Z toward the driver): where
## tools/assets/blender/build_rv.py puts `Gauge0..2` (Blender (x, 2.215, 1.22), 5 cm radius,
## 1 cm deep), in Godot's axes. They're merged into the interior mesh, so there's no node.
const DIALS: Array[Vector3] = [Vector3(-0.68, 1.22, -2.205), Vector3(-0.52, 1.22, -2.205), Vector3(-0.36, 1.22, -2.205)]
const DIAL_RADIUS := 0.05


## Puts a needle (and markings) on each dial, and the warning lights above them.
func setup(on: RV) -> void:
	rv = on
	name = "Dashboard"
	on.add_child(self)
	var needle_mat := _mat(Color(0.9, 0.2, 0.1), 0.6)
	var tick_mat := _mat(Color(0.12, 0.12, 0.12), 0.0)
	var red_mat := _mat(Color(0.8, 0.12, 0.08), 0.0)
	var face_mat := _mat(Color(0.92, 0.9, 0.84), 0.0)
	var centres: Array[Vector3] = []
	var radius := DIAL_RADIUS
	for i: int in DIALS.size():
		var centre := on.to_local(on.model.global_transform * DIALS[i])
		centres.append(centre)
		var dial := Node3D.new()
		dial.name = "Dial%d" % i
		dial.position = centre
		add_child(dial)
		var face := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = radius * 0.94
		disc.bottom_radius = radius * 0.94
		disc.height = 0.002
		disc.radial_segments = 20
		face.mesh = disc
		face.material_override = face_mat
		face.basis = Basis(Vector3.RIGHT, PI / 2.0)
		dial.add_child(face)
		var sweep := FUEL_SWEEP if i == 2 else SWEEP
		var ticks := 5 if i == 2 else 7
		for t: int in ticks:
			var f := float(t) / float(ticks - 1)
			var red := (i == 1 and f * MAX_RPM >= RVDrivetrain.REDLINE_RPM) or (i == 2 and t == 0)
			var tick := _bar(Vector3(0.003, radius * 0.22, 0.002), red_mat if red else tick_mat)
			tick.position = Vector3(0.0, radius * 0.72, 0.002)
			var holder := Node3D.new()
			holder.rotation.z = -lerpf(-sweep, sweep, f)
			holder.add_child(tick)
			dial.add_child(holder)
		var needle := Node3D.new()
		needle.name = "Needle"
		needle.position.z = 0.005
		var bar := _bar(Vector3(0.004, radius * 0.85, 0.002), needle_mat)
		bar.position.y = radius * 0.35
		needle.add_child(bar)
		dial.add_child(needle)
		_needles.append(needle)
		var label := Label3D.new()
		label.text = ["km/h", "rpm", "E     F"][mini(i, 2)]
		label.font_size = 24
		label.pixel_size = 0.0004
		label.modulate = Color(0.1, 0.1, 0.1)
		label.outline_size = 0
		label.position = Vector3(0.0, -radius * 0.45, 0.004)
		dial.add_child(label)
	# The warning lights, in a row above the dials.
	if not centres.is_empty():
		var left := centres[0]
		var right := centres[centres.size() - 1]
		var names: Array[StringName] = [&"oil", &"hot", &"charge", &"check"]
		for k: int in names.size():
			var lamp := MeshInstance3D.new()
			var m := SphereMesh.new()
			m.radius = 0.008
			m.height = 0.008
			m.radial_segments = 8
			m.rings = 4
			lamp.mesh = m
			lamp.material_override = _mat(_lamp_colors[names[k]].darkened(0.75), 0.0)
			lamp.position = left.lerp(right, (float(k) + 0.5) / float(names.size())) + Vector3(0.0, 0.075, 0.0)
			lamp.name = "Lamp_" + String(names[k])
			add_child(lamp)
			_lamps[names[k]] = lamp


func _process(dt: float) -> void:
	if rv == null or _needles.is_empty():
		return
	var d := rv.drivetrain
	var dmg := rv.damage
	var target: PackedFloat32Array = [
		clampf(absf(rv.forward_speed()) * 3.6 / MAX_KMH, 0.0, 1.0),
		clampf(d.rpm / MAX_RPM, 0.0, 1.0) if d.running else 0.0,
		clampf(dmg.fuel / RVDamage.TANK, 0.0, 1.0),
	]
	for i: int in mini(_needles.size(), 3):
		readings[i] = move_toward(readings[i], target[i], NEEDLE_RATE * dt)
		var sweep := FUEL_SWEEP if i == 2 else SWEEP
		_needles[i].rotation.z = -lerpf(-sweep, sweep, readings[i])
	var loose := false
	for i: int in 4:
		if not dmg.wheel_on[i] or dmg.bolts[i] < RVDamage.BOLTS or dmg.tires[i] <= 0.0:
			loose = true
	lights[&"oil"] = dmg.oil < 0.15
	lights[&"hot"] = dmg.temperature > 0.8
	lights[&"charge"] = not d.running
	lights[&"check"] = loose or dmg.missing_parts() > 0
	for k: StringName in _lamps:
		var mat := _lamps[k].material_override as StandardMaterial3D
		var on := lights[k]
		mat.albedo_color = _lamp_colors[k] if on else _lamp_colors[k].darkened(0.75)
		mat.emission_enabled = on
		mat.emission = _lamp_colors[k]
		mat.emission_energy_multiplier = 2.0


static func _mat(c: Color, emission: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	return m


static func _bar(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	return mi
