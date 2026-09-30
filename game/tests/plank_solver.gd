extends Node
## Headless test of where a plank goes, on hand-built ground (banks either side of a trench):
## over a gap in front of you it lies across it at the ground's level (not down in it, where
## you're pointing), centred, however far back you stand or crooked you aim, and every gap the
## generator makes (up to 4.2 m) holds it securely; a barely-on plank is marked risky and laid
## loose; nothing's offered when it wouldn't rest on anything; on flat or sloping ground it
## lies along the ground. A loose plank settles on the banks and turns into solid ground, or,
## with nothing under it, falls in.
##
##   godot --headless --path game --fixed-fps 60 res://tests/plank_solver.tscn

const BANK := 40.0

var _failures: PackedStringArray = []
var _bodies: Array[Node] = []


func _ready() -> void:
	_run()


func _run() -> void:
	await _ground(4.0)
	_flat_ground()
	_gap_across()
	_where_you_stand()
	_crooked()
	await _every_generated_gap()
	await _too_wide()
	_pointing_into_the_trench()
	await _sloping()
	await _settling()
	_finish()


## Two banks with their tops at y = 0 and a trench `width` wide between them, 3 m deep,
## along x = -width/2 .. width/2, on the world layer (as terrain and abutments are).
func _ground(width: float) -> void:
	for b: Node in _bodies:
		b.queue_free()
	_bodies.clear()
	await get_tree().physics_frame
	for spec: Array in [
		[Vector3(-BANK * 0.5 - width * 0.5, -2.0, 0.0), Vector3(BANK, 4.0, BANK)],
		[Vector3(BANK * 0.5 + width * 0.5, -2.0, 0.0), Vector3(BANK, 4.0, BANK)],
		[Vector3(0.0, -3.5, 0.0), Vector3(width + 2.0, 1.0, BANK)],
	]:
		var body := StaticBody3D.new()
		body.collision_layer = TerrainStreamer.WORLD_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[1]
		shape.shape = box
		body.add_child(shape)
		add_child(body)
		body.global_position = spec[0]
		_bodies.append(body)
	for i: int in 3:
		await get_tree().physics_frame


func _space() -> PhysicsDirectSpaceState3D:
	return get_viewport().world_3d.direct_space_state


## Lays a plank from where `back` metres before the trench's near edge, along `yaw` (0 =
## straight across), pointing at `aim`.
func _plan(width: float, back: float, yaw: float = 0.0, aim: Vector3 = Vector3.INF) -> Dictionary:
	var origin := Vector3(-width * 0.5 - back, 0.0, 0.0)
	var dir := Vector3.RIGHT.rotated(Vector3.UP, yaw)
	var at := aim if aim != Vector3.INF else Vector3(0.0, -2.5, 0.0) # Down into the trench, as you'd look.
	return ItemLibrary._plank_along(_space(), origin, dir, at)


func _tips(plan: Dictionary) -> Array[Vector3]:
	var xf: Transform3D = plan["xf"]
	var half := xf.basis.x * ItemLibrary.PLANK_LENGTH * 0.5
	return [xf.origin - half, xf.origin + half]


func _flat_ground() -> void:
	var plan := _plan(4.0, 8.0, 0.0, Vector3(-3.5, 0.0, 0.0)) # Well short of the gap, looking at the ground.
	_check(not plan.is_empty() and not plan["bridging"], "on flat ground, well short of a gap: it just lies on the ground")
	if plan.is_empty():
		return
	var xf: Transform3D = plan["xf"]
	var tips := _tips(plan)
	_check(absf(xf.basis.x.y) < 0.01 and absf(xf.origin.y - 0.04) < 0.05, "level, on the ground (y %.2f)" % xf.origin.y)
	_check(absf(xf.origin.x - -5.0) < 1.0 and tips[1].x < -1.5, "about where it's pointing (centre x %.1f, far end x %.1f)" % [xf.origin.x, tips[1].x])


func _gap_across() -> void:
	var plan := _plan(4.0, 1.5)
	_check(not plan.is_empty() and plan["bridging"] and plan["secure"], "a 4 m gap in front of you: the plank bridges it, securely")
	if plan.is_empty():
		return
	var xf: Transform3D = plan["xf"]
	var tips := _tips(plan)
	_check(absf(xf.origin.x) < 0.3, "centred on the gap (x %.2f)" % xf.origin.x)
	_check(tips[0].x < -2.0 - 0.6 and tips[1].x > 2.0 + 0.6, "resting at least 0.6 m on each side (%.2f to %.2f)" % [tips[0].x, tips[1].x])
	_check(absf(xf.basis.x.y) < 0.02 and xf.origin.y > 0.0 and xf.origin.y < 0.15, "level, at the ground's height, not in the trench (y %.2f, slope %.3f)" % [xf.origin.y, xf.basis.x.y])


func _where_you_stand() -> void:
	for back: float in [0.0, 0.5, 1.5, 3.0, 4.5]:
		var plan := _plan(4.0, back)
		var ok: bool = not plan.is_empty() and plan["bridging"]
		var centred: bool = ok and absf((plan["xf"] as Transform3D).origin.x) < 0.5
		_check(ok and centred and plan["secure"], "standing %.1f m back it's laid across, centred and secure" % back)


func _crooked() -> void:
	for degrees: float in [10.0, 20.0, 25.0]:
		for sign: float in [-1.0, 1.0]:
			var plan := _plan(4.0, 1.5, deg_to_rad(degrees * sign))
			_check(not plan.is_empty() and plan["bridging"] and plan["secure"], "aimed %.0f° off square it still bridges securely" % (degrees * sign))
	var plan := _plan(4.0, 1.5, deg_to_rad(36.0))
	_check(not plan.is_empty() and plan["bridging"] and not plan["secure"], "36° off it's on, but barely: risky")
	plan = _plan(4.0, 1.5, deg_to_rad(60.0))
	_check(plan.is_empty() or not plan["bridging"], "60° off it can't reach across")


## Every gap the generator makes is at most PLANK_LENGTH - 2 * 0.8 wide; lay it on each.
func _every_generated_gap() -> void:
	for width: float in [3.5, 3.6, 3.9, 4.2, 4.4]:
		await _ground(width)
		for back: float in [0.5, 2.0]:
			var plan := _plan(width, back)
			_check(not plan.is_empty() and plan["bridging"] and plan["secure"], "a %.1f m gap, standing %.1f m back: bridged securely" % [width, back])


func _too_wide() -> void:
	await _ground(5.6)
	var plan := _plan(5.6, 1.5)
	_check(plan.is_empty() or not plan["bridging"], "a 5.6 m gap: only 0.2 m each side, not offered as a bridge")
	await _ground(4.0)


func _pointing_into_the_trench() -> void:
	# The view ray, pointing down into the trench, hits its floor: the plank still goes across.
	var plan := _plan(4.0, 1.0, 0.0, Vector3(0.0, -3.0, 0.0))
	_check(not plan.is_empty() and plan["bridging"] and (plan["xf"] as Transform3D).origin.y > -0.05, "pointing at the trench's floor, the plank goes across the top, not down in it")


func _sloping() -> void:
	await _ground(4.0)
	# A slope rising 1 m in 6, its surface through (-32, 0) and above the bank from there on.
	var angle := atan(1.0 / 6.0)
	var ramp := StaticBody3D.new()
	ramp.collision_layer = TerrainStreamer.WORLD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.4, 10.0)
	shape.shape = box
	ramp.add_child(shape)
	add_child(ramp)
	var up := Vector3(-sin(angle), cos(angle), 0.0)
	ramp.global_transform = Transform3D(Basis(Vector3.BACK, angle), Vector3(-32.0, 0.0, 0.0) - up * 0.2)
	_bodies.append(ramp)
	for i: int in 3:
		await get_tree().physics_frame
	var plan := ItemLibrary._plank_along(_space(), Vector3(-30.0, 0.0, 0.0), Vector3.RIGHT, Vector3(-27.0, 0.5, 0.0))
	_check(not plan.is_empty() and not plan["bridging"], "on a slope: it lies on it")
	if not plan.is_empty():
		var slope := (plan["xf"] as Transform3D).basis.x.y
		_check(slope > 0.12 and slope < 0.2, "following its slope (%.3f, want %.3f)" % [slope, tan(angle)])


func _settling() -> void:
	await _ground(4.0)
	# Laid where it's secure: placed as solid ground.
	var plank := ItemLibrary.create(&"plank")
	add_child(plank)
	var plan := _plan(4.0, 1.0)
	plank.place(self, plan["xf"])
	_check(plank.is_placed() and plank.collision_layer == TerrainStreamer.WORLD_LAYER, "a secure plank is placed at once")
	plank.queue_free()
	# Laid loose across the gap with only a little on each side: it settles and becomes solid.
	await _ground(5.2)
	plank = ItemLibrary.create(&"plank")
	add_child(plank)
	plan = _plan(5.2, 1.0)
	_check(not plan.is_empty() and plan["bridging"] and not plan["secure"], "a 5.2 m gap: only 0.4 m each side, risky")
	if plan.is_empty():
		return
	plank.lay_loose(self, plan["xf"])
	_check(plank.get_meta(&"settling", false) and not plank.freeze, "laid loose, it's left to physics")
	for i: int in 200:
		await get_tree().physics_frame
	_check(plank.is_placed() and absf(plank.global_position.x) < 0.5 and plank.global_position.y > -0.1, "it held: solid ground across the gap (%s at %s)" % [plank.is_placed(), plank.global_position])
	plank.queue_free()
	# Dropped with its middle over the gap and only one end on a bank: it falls in and stays
	# a loose plank (one for fetching), not solid ground.
	await _ground(4.0)
	plank = ItemLibrary.create(&"plank")
	add_child(plank)
	plank.lay_loose(self, Transform3D(Basis.IDENTITY, Vector3(1.6, 0.3, 0.0)))
	for i: int in 300:
		await get_tree().physics_frame
	_check(not plank.is_placed() and plank.global_position.y < -0.3, "with nothing under its middle it falls into the trench and stays a loose plank (y %.2f)" % plank.global_position.y)
	plank.queue_free()
	await get_tree().physics_frame


func _finish() -> void:
	for b: Node in _bodies:
		b.queue_free()
	if _failures.is_empty():
		print("plank solver: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
