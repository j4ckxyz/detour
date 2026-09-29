class_name RVDamage
extends Node
## What state the RV is in (PLAN.md §4.2): body parts that dent and fall off, wheels whose
## bolts shake loose and tires that burst, an engine that burns fuel, leaks oil and
## overheats, and a frame that takes the big hits. Repairs: hammer + scrap metal for the
## body, a drill for wheel bolts, spare tires, motor oil, jerry cans and the pump for fuel,
## and the welder at gas stations for the frame.

signal part_lost(part: StringName)
signal wheel_lost(index: int)

const FULL := 100.0
## Contact impulse (N·s in one physics step) below which a knock does no harm. Parking, and
## rolling over bumps, stay well below it.
const IMPACT_THRESHOLD := 2600.0
## HP lost per N·s above the threshold, and the most one contact can do in a step (a head-on
## into a wall at speed dents the front and costs a part or two, not the whole RV).
const HP_PER_IMPULSE := 1.0 / 320.0
const MAX_HIT := 45.0
const BOLTS := 5
const TANK := 60.0
const START_FUEL := 40.0
## Parts close to a hit (RV space, metres from the part's centre) share the damage.
const PART_REACH := 1.7

var rv: RV
## name → Part.
var parts: Dictionary[StringName, Part] = {}
var frame := FULL
var engine := FULL
## Engine oil, 0..1 (full).
var oil := 1.0
## 0 (cold) .. 1 (seizing).
var temperature := 0.25
var fuel := START_FUEL
var tires: Array[float] = [FULL, FULL, FULL, FULL]
var bolts: Array[int] = [BOLTS, BOLTS, BOLTS, BOLTS]
var wheel_on: Array[bool] = [true, true, true, true]
## Seconds a freshly fitted wheel ignores knocks (the corner springing back up isn't a crash).
var _settle: Array[float] = [0.0, 0.0, 0.0, 0.0]
## How many parts have come off.
var parts_lost := 0
## Online, on a client simulating the RV: `func(kind: StringName, key: Variant, xf: Transform3D,
## velocity: Vector3)` asks the host to put a fallen part (&"part", id) or wheel (&"wheel",
## index) in the world. Unset, they're made here.
var spawn_loose: Callable

const PART_NAMES: Dictionary[StringName, String] = {
	&"Hood": "hood", &"Grille": "grille", &"BumperFront": "front bumper", &"BumperRear": "rear bumper",
	&"SkirtLF": "left front skirt", &"SkirtLM": "left middle skirt", &"SkirtLR": "left rear skirt",
	&"SkirtRF": "right front skirt", &"SkirtRM": "right middle skirt", &"SkirtRR": "right rear skirt",
	&"MirrorL": "left mirror", &"MirrorR": "right mirror", &"Step": "door step", &"RoofAC": "roof AC",
	&"Ladder": "ladder", &"Awning": "awning",
}
const WHEEL_NAMES: Array[String] = ["front left wheel", "front right wheel", "rear left wheels", "rear right wheels"]


class Part:
	var id: StringName
	var node: MeshInstance3D
	var rest := Transform3D.IDENTITY
	## Centre in RV space.
	var centre := Vector3.ZERO
	var radius := 0.5
	var hp := FULL
	var attached := true
	## The piece lying in the world after it came off.
	var debris: Item


func setup(owner_rv: RV) -> void:
	rv = owner_rv
	for n: Node in rv.model.find_children("Part_*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var part := Part.new()
		part.id = StringName(String(mi.name).trim_prefix("Part_"))
		part.node = mi
		part.rest = mi.transform
		part.centre = rv.to_local(mi.global_position)
		part.radius = maxf(0.35, mi.mesh.get_aabb().size.length() * 0.5)
		parts[part.id] = part


func part_name(id: StringName) -> String:
	return PART_NAMES.get(id, String(id))


func missing_parts() -> int:
	var n := 0
	for p: Part in parts.values():
		n += 0 if p.attached else 1
	return n


# --- damage --------------------------------------------------------------------------------------

## A collision contact: `local` in RV space, `impulse` its strength this step (N·s), `dir` the
## world direction the RV was pushed.
func hit(local: Vector3, impulse: float, dir: Vector3) -> void:
	var excess := impulse - IMPACT_THRESHOLD
	if excess <= 0.0:
		return
	var dmg := minf(excess * HP_PER_IMPULSE, MAX_HIT)
	frame = maxf(0.0, frame - dmg * 0.06)
	if local.z < -2.2:
		engine = maxf(0.0, engine - dmg * 0.1) # Head-on: the engine's up front.
	for p: Part in parts.values():
		if not p.attached:
			continue
		var d := p.centre.distance_to(local)
		if d > PART_REACH + p.radius:
			continue
		p.hp -= dmg * clampf(1.2 - d / (PART_REACH + p.radius), 0.2, 1.0)
		if p.hp <= 0.0:
			detach(p.id, dir)
	for i: int in 4:
		if not wheel_on[i]:
			continue
		var w := rv.wheels[i]
		var centre := w.position + Vector3.DOWN * w.length
		if centre.distance_to(local) < 1.0:
			damage_wheel(i, dmg)


## A wheel taking a hit (a rock, a hard landing): the tire suffers, and a big one shakes a
## bolt loose. With no bolts left the wheel comes off.
func damage_wheel(i: int, dmg: float) -> void:
	if _settle[i] > 0.0:
		return
	tires[i] = maxf(0.0, tires[i] - dmg * 0.6)
	var before := bolts[i]
	if dmg > 6.0:
		bolts[i] = maxi(0, bolts[i] - (2 if dmg > 25.0 else 1))
	if before > 0 and bolts[i] == 0:
		lose_wheel(i) # That shook the last bolt out. (A bolt-less wheel you just fitted
		# stays on until you drive off on it: see tick().)


func detach(id: StringName, dir: Vector3 = Vector3.ZERO) -> void:
	var p: Part = parts.get(id)
	if p == null or not p.attached:
		return
	p.attached = false
	p.hp = 0.0
	p.node.visible = false
	parts_lost += 1
	var velocity := rv.point_velocity(p.node.global_position) + dir * 2.0 + Vector3.UP * 1.5
	if spawn_loose.is_valid():
		spawn_loose.call(&"part", id, p.node.global_transform, velocity)
	else:
		p.debris = make_debris(id, p.node.global_transform, velocity)
	part_lost.emit(id)


## The piece of the RV that came off, as an item lying in the world.
func make_debris(id: StringName, xf: Transform3D, velocity: Vector3) -> Item:
	var p: Part = parts[id]
	var debris := ItemLibrary.create_from_mesh(&"rv_part", p.node.mesh, "RV part: %s" % part_name(id))
	debris.set_meta(&"part", id)
	rv.get_parent().add_child(debris)
	debris.global_transform = xf
	debris.linear_velocity = velocity
	return debris


## A wheel that came off, as an item lying in the world.
func make_wheel(i: int, xf: Transform3D, velocity: Vector3, tire_hp: float) -> Item:
	var w := rv.wheels[i]
	var loose := ItemLibrary.create_from_mesh(&"rv_wheel", (w.visual as MeshInstance3D).mesh, WHEEL_NAMES[i].capitalize())
	loose.set_meta(&"tire", tire_hp)
	loose.set_meta(&"wheel", i)
	rv.get_parent().add_child(loose)
	loose.global_transform = xf
	loose.linear_velocity = velocity
	return loose


func lose_wheel(i: int) -> void:
	if not wheel_on[i]:
		return
	wheel_on[i] = false
	var w := rv.wheels[i]
	w.detached = true
	w.visual.visible = false
	var velocity := rv.point_velocity(w.visual.global_position) + Vector3.UP
	if spawn_loose.is_valid():
		spawn_loose.call(&"wheel", i, w.visual.global_transform, velocity)
	else:
		make_wheel(i, w.visual.global_transform, velocity, tires[i])
	wheel_lost.emit(i)


# --- each tick -----------------------------------------------------------------------------------

## Fuel, oil and heat; returns the engine power factor (1 = healthy).
func tick(dt: float, throttle: float) -> float:
	var d := rv.drivetrain
	if d.running:
		var load := throttle * d.rpm / RVDrivetrain.REDLINE_RPM
		fuel = maxf(0.0, fuel - (0.0012 + 0.02 * load) * dt)
		var leak := 0.0004 + (0.002 if engine < 50.0 else 0.0) + (0.001 if not parts[&"Hood"].attached else 0.0)
		oil = maxf(0.0, oil - leak * dt)
		var target := 0.3 + 0.35 * load + (0.7 if oil < 0.12 else 0.0) + (0.2 if engine < 35.0 else 0.0)
		temperature = move_toward(temperature, clampf(target, 0.0, 1.0), 0.03 * dt)
		if temperature > 0.9:
			engine = maxf(0.0, engine - 2.0 * dt) # Cooking itself.
	else:
		temperature = move_toward(temperature, 0.2, 0.01 * dt)
	if d.running and (fuel <= 0.0 or engine <= 0.0):
		d.running = false
		d.stalled.emit()
	for i: int in 4:
		if wheel_on[i] and bolts[i] < 2 and absf(rv.forward_speed()) > 3.0:
			# Wobbling on its last bolt: it won't last long.
			if randf() < dt * (0.25 if bolts[i] == 1 else 1.0):
				bolts[i] = maxi(0, bolts[i] - 1)
				if bolts[i] == 0:
					lose_wheel(i)
	for i: int in 4:
		_settle[i] = maxf(0.0, _settle[i] - dt)
	var power := 1.0 - 0.6 * smoothstep(0.8, 1.0, temperature)
	if engine < 40.0:
		power *= 0.5 + engine / 80.0
	return power


func can_start() -> bool:
	return fuel > 0.0 and engine > 0.0


## Grip multiplier for a wheel (flat tires and wobbly wheels grip badly).
func wheel_grip(i: int) -> float:
	var g := 1.0
	if tires[i] <= 0.0:
		g *= 0.55
	if bolts[i] < 3:
		g *= 0.85
	return g


# --- repairs -------------------------------------------------------------------------------------

## Hammer + scrap: +50 HP to a dented part, or a whole new panel where one fell off.
func patch_part(id: StringName) -> void:
	var p: Part = parts[id]
	if not p.attached:
		_restore(p)
		p.hp = 60.0
	else:
		p.hp = minf(FULL, p.hp + 50.0)


## Putting the actual fallen part back (no scrap needed, just the hammer or bare hands).
func refit_part(id: StringName) -> void:
	var p: Part = parts[id]
	_restore(p)
	p.hp = 80.0


func _restore(p: Part) -> void:
	p.attached = true
	p.node.visible = true
	p.node.transform = p.rest
	if is_instance_valid(p.debris):
		p.debris.queue_free()
	p.debris = null


## Puts a wheel (a spare tire or the one that fell off) on an empty hub, bolts out.
func mount_wheel(i: int, tire_hp: float) -> void:
	wheel_on[i] = true
	tires[i] = tire_hp
	bolts[i] = 0
	_settle[i] = 2.0
	var w := rv.wheels[i]
	w.detached = false
	w.visual.visible = true


## Swaps a flat for a spare: the fresh wheel goes on with its bolts out.
func swap_tire(i: int) -> void:
	tires[i] = FULL
	bolts[i] = 0
	_settle[i] = 2.0


func tighten_bolt(i: int) -> void:
	bolts[i] = mini(BOLTS, bolts[i] + 1)


func add_oil() -> void:
	oil = 1.0


func add_fuel(litres: float) -> float:
	var take := minf(litres, TANK - fuel)
	fuel += take
	return take


## The gas-station welder: frame as new, and the engine looked over.
func weld() -> void:
	frame = FULL
	engine = maxf(engine, 80.0)


# --- network ---------------------------------------------------------------------------------

func snapshot() -> Array:
	var hp := PackedFloat32Array()
	var on := 0
	var k := 0
	for p: Part in parts.values():
		hp.append(p.hp)
		on |= (1 << k) if p.attached else 0
		k += 1
	var wheels_on := 0
	for i: int in 4:
		wheels_on |= (1 << i) if wheel_on[i] else 0
	return [hp, on, PackedFloat32Array([frame, engine, oil, temperature, fuel]), PackedFloat32Array(tires),
		PackedInt32Array(bolts), wheels_on, parts_lost]


func apply_snapshot(s: Array) -> void:
	var hp: PackedFloat32Array = s[0]
	var on: int = s[1]
	var k := 0
	for p: Part in parts.values():
		p.hp = hp[k]
		var attached := (on & (1 << k)) != 0
		if attached != p.attached:
			p.attached = attached
			p.node.visible = attached
			p.node.transform = p.rest
		k += 1
	var v: PackedFloat32Array = s[2]
	frame = v[0]
	engine = v[1]
	oil = v[2]
	temperature = v[3]
	fuel = v[4]
	var t: PackedFloat32Array = s[3]
	var b: PackedInt32Array = s[4]
	for i: int in 4:
		tires[i] = t[i]
		bolts[i] = b[i]
		var attached := (int(s[5]) & (1 << i)) != 0
		if attached != wheel_on[i]:
			wheel_on[i] = attached
			rv.wheels[i].detached = not attached
			rv.wheels[i].visual.visible = attached
	parts_lost = s[6]


# --- aiming ----------------------------------------------------------------------------------------

## What of the RV a view ray points at within `reach`: {kind: "part"|"wheel"|"engine"|"fuel",
## id / index, distance}, or {}.
func aim(origin: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	var candidates: Array[Array] = []
	for p: Part in parts.values():
		candidates.append(["part", p.id, p.centre, maxf(0.3, p.radius * 0.6)])
	for i: int in 4:
		var w := rv.wheels[i]
		candidates.append(["wheel", i, w.position + Vector3.DOWN * RV.RIDE_LENGTH, 0.5])
	candidates.append(["engine", 0, ENGINE_SPOT, 0.7])
	candidates.append(["fuel", 0, FUEL_CAP, 0.4])
	for c: Array in candidates:
		var world_pos := rv.to_global(c[2])
		var to := world_pos - origin
		var along := to.dot(dir)
		if along < 0.0 or along > reach:
			continue
		var miss := (to - dir * along).length()
		if miss > c[3]:
			continue
		var score := along + miss * 2.0
		if score < best_d:
			best_d = score
			best = {"kind": c[0], "id": c[1], "distance": along}
	return best


## Engine bay (under the hood) and the fuel filler (left side, above the tank), RV space.
const ENGINE_SPOT := Vector3(0.0, 1.0, -3.0)
const FUEL_CAP := Vector3(-1.22, 0.95, 0.3)
