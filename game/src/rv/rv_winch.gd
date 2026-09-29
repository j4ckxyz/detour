class_name RVWinch
extends Node3D
## One of the RV's two winches (PLAN.md §4.2). Take the hook off the drum, carry it out up to
## `MAX_ROPE` metres, hook it onto a tree, rock, stump or log, then reel in with the winch
## remote. The rope only pulls when taut: a one-sided spring-damper at the mount, limited by
## the motor, and it snaps if something yanks far past that.
##
## The node sits at the mount (the fairlead) on the RV. The hook is an `Item` (&"winch_hook").

signal snapped

const MAX_ROPE := 40.0
## Motor pull limit (N) and reel speed at no load (m/s).
const MAX_PULL := 60000.0
const REEL_SPEED := 0.5
const PAYOUT_SPEED := 1.2
## Rope stiffness (N/m) and damping (N·s/m).
const STIFFNESS := 250000.0
const DAMPING := 30000.0
## Tension that parts the rope (a hard yank: driving away at full power, a falling RV).
const SNAP_TENSION := 160000.0
const SEGMENTS := 24
const ROPE_RADIUS := 0.022 # Drawn thicker than a real 10 mm line so it reads at a distance.

enum State { STOWED, HELD, LOOSE, ANCHORED }

var rv: RV
var label := "front"
var state := State.STOWED
var hook: Item
## Rope out, metres (paid out from the drum).
var rope_length := 0.0
## Current rope tension (N), for the HUD and sounds.
var tension := 0.0
## Total metres reeled in (for fun stats / achievements later).
var reeled_total := 0.0
## -1 reel in, +1 pay out, 0 hold: what the remotes ask for (see set_drive).
var drive := 0
## Who's pressing what on a winch remote (player peer id → -1/0/+1).
var _drives: Dictionary[int, int] = {}

var _anchor := Vector3.ZERO
var _drum: Node3D
var _drum_rest := Basis.IDENTITY
var _drum_angle := 0.0
var _segments: Array[MeshInstance3D] = []
var _prev_distance := 0.0
var _rope_material := StandardMaterial3D.new()


func setup(owner_rv: RV, which: String, drum: Node3D) -> void:
	rv = owner_rv
	label = which
	_drum = drum
	_drum_rest = drum.basis
	hook = ItemLibrary.create(&"winch_hook")
	hook.set_meta(&"winch", self)
	stow_hook()

	var handle := Interactable.new()
	handle.name = "Handle"
	handle.reach = 2.2
	handle.prompt_for = _prompt
	handle.used.connect(_on_used)
	add_child(handle)

	_rope_material.albedo_color = Color(0.12, 0.11, 0.1)
	_rope_material.roughness = 0.8
	var mesh := CylinderMesh.new()
	mesh.top_radius = ROPE_RADIUS
	mesh.bottom_radius = ROPE_RADIUS
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 1
	mesh.material = _rope_material
	for i: int in SEGMENTS:
		var seg := MeshInstance3D.new()
		seg.mesh = mesh
		seg.top_level = true
		seg.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		seg.visible = false
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(seg)
		_segments.append(seg)


func is_anchored() -> bool:
	return state == State.ANCHORED


## Where the rope leaves the RV, world space.
func mount_position() -> Vector3:
	return global_position


## Where the rope's far end is, world space.
func hook_position() -> Vector3:
	return _anchor if state == State.ANCHORED else hook.global_position


func _prompt(player: Player) -> String:
	if player.inside:
		return ""
	if state == State.STOWED and player.held == null:
		return "Take the %s winch hook" % label
	if player.held == hook:
		return "Put the %s winch hook back" % label
	return ""


func _on_used(player: Player) -> void:
	if state == State.STOWED and player.held == null:
		player.pick_up(hook)
	elif player.held == hook:
		player.held = null
		stow_hook()


## One player's remote: `d` -1 reel in, +1 pay out, 0 let go. Reel-in wins a tug of war.
func set_drive(who: int, d: int) -> void:
	if d == 0:
		_drives.erase(who)
	else:
		_drives[who] = d
	drive = 0
	for v: int in _drives.values():
		drive = v if drive == 0 or v < 0 else drive


## The hook left a hand (dropped or thrown): it now lies on the end of the rope.
func on_hook_released() -> void:
	if state == State.HELD:
		state = State.LOOSE


func on_hook_grabbed() -> void:
	if state == State.STOWED:
		rope_length = 1.0 # Off the drum.
	if state in [State.STOWED, State.LOOSE, State.ANCHORED]:
		state = State.HELD


## Hooks onto a fixed point in the world (a tree, rock, stump or log).
func anchor(point: Vector3) -> void:
	_anchor = point
	state = State.ANCHORED
	rope_length = minf(MAX_ROPE, mount_position().distance_to(point))
	_prev_distance = rope_length
	hook.freeze = true
	hook.reparent(rv.get_parent(), false)
	hook.global_position = point
	hook.collision_layer = 0
	hook.collision_mask = 0


## Where the hook is anchored (world space).
func anchor_point() -> Vector3:
	return _anchor


## Back on its drum.
func stow_hook() -> void:
	state = State.STOWED
	rope_length = 0.0
	tension = 0.0
	hook.holder = null
	if hook.get_parent():
		hook.reparent(self, false)
	else:
		add_child(hook)
	hook.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, 0.0))
	hook.freeze = true
	hook.collision_layer = 0
	hook.collision_mask = 0
	hook.visible = true


## Runs each physics tick from the RV: rope length, tension, and the pull on the RV.
func step(dt: float) -> void:
	tension = 0.0
	if state == State.STOWED:
		return
	var mount := mount_position()
	var far := hook_position()
	var d := far - mount
	var dist := d.length()
	match state:
		State.HELD:
			rope_length = minf(MAX_ROPE, maxf(rope_length, dist)) # Free-spooling as you walk.
			if dist > MAX_ROPE:
				var player := hook.holder
				if player:
					player.drop_held() # The cable ran out: it yanks the hook out of your hands.
		State.LOOSE:
			rope_length = minf(MAX_ROPE, maxf(rope_length, dist))
			if dist > MAX_ROPE and not hook.freeze:
				hook.apply_central_force(-d / dist * minf((dist - MAX_ROPE) * 2000.0, 4000.0)) # Dragged along.
		State.ANCHORED:
			_reel(dt)
			var stretch := dist - rope_length
			var rate := (dist - _prev_distance) / dt
			_prev_distance = dist
			if stretch > 0.0:
				tension = maxf(0.0, STIFFNESS * stretch + DAMPING * rate)
				if tension > SNAP_TENSION:
					_snap()
					return
				var pull := minf(tension, MAX_PULL * 1.5)
				rv.apply_force(d / dist * pull, mount - rv.global_position)
	_spin_drum(dt)


func _reel(dt: float) -> void:
	if drive < 0:
		# The motor slows as the load rises and stalls at its limit.
		var speed := REEL_SPEED * clampf(1.0 - tension / MAX_PULL, 0.0, 1.0)
		rope_length = maxf(0.5, rope_length - speed * dt)
		reeled_total += speed * dt
	elif drive > 0:
		rope_length = minf(MAX_ROPE, rope_length + PAYOUT_SPEED * dt)


func _snap() -> void:
	# The hook stays where it was anchored; the rope's end whips back to the RV.
	hook.freeze = false
	hook.collision_layer = Item.LAYER
	hook.collision_mask = TerrainStreamer.WORLD_LAYER | RV.VEHICLE_LAYER | Item.LAYER
	state = State.LOOSE
	tension = 0.0
	snapped.emit()


## On machines that don't simulate the RV: only the drum turns (the rest comes from snapshots).
func puppet_step(dt: float) -> void:
	_spin_drum(dt)


func _spin_drum(dt: float) -> void:
	if _drum and drive != 0 and state == State.ANCHORED:
		_drum_angle = wrapf(_drum_angle + drive * dt * 6.0, -PI, PI)
		_drum.basis = _drum_rest * Basis(Vector3.RIGHT, _drum_angle)


func _process(_dt: float) -> void:
	var show := state != State.STOWED
	for seg: MeshInstance3D in _segments:
		seg.visible = show
	if not show:
		return
	var a := rv.get_global_transform_interpolated() * rv.to_local(global_position)
	var b := hook_position()
	if state == State.HELD and hook.holder:
		b = hook.global_position
	var chord := a.distance_to(b)
	# Parabolic sag for the slack (small-sag cable approximation).
	var slack := maxf(0.0, rope_length - chord) if state == State.ANCHORED else minf(0.15 * chord, 2.0)
	var sag := sqrt(0.375 * chord * slack) if chord > 0.01 else 0.0
	var prev := a
	for i: int in SEGMENTS:
		var t := float(i + 1) / SEGMENTS
		var p := a.lerp(b, t) + Vector3.DOWN * (4.0 * sag * t * (1.0 - t))
		var seg := _segments[i]
		var mid := (prev + p) * 0.5
		var len := prev.distance_to(p)
		if len > 0.0001:
			var up := (p - prev) / len
			var side := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
			var fwd := side.cross(up)
			seg.global_transform = Transform3D(Basis(side, up * len, fwd), mid)
		prev = p
