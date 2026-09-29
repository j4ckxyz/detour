class_name RVWheel
extends Node3D
## One wheel: a sphere shape-cast suspension (so it rolls over terrain edges instead of
## snagging on them) with a spring and damper, and a tire that grips within a friction
## circle (PLAN.md §4.2). The node sits at the top of the suspension travel; `RV` calls
## `probe()` then `apply_forces()` every physics tick.

## Peak tire grip on dry dirt. Terrain surface types scale it later (Phase 3).
const GRIP := 1.0
## Slip angle (radians) where lateral grip peaks; beyond it the tire slides.
const PEAK_SLIP := 0.12
## Rolling resistance as a fraction of the load.
const ROLLING := 0.015
## Below this speed (m/s) the tire holds like static friction instead of using slip angles.
const CREEP_SPEED := 2.0
## The cast starts this far above the mount. A sphere that starts inside the ground reports
## no hit (Jolt skips initial overlaps), which would read as full droop just when the
## suspension is fully compressed and drop that corner through the terrain.
const CAST_LIFT := 0.6

@export var radius := 0.4
## Distance from the mount (top of travel) to the wheel centre at full droop.
@export var travel := 0.45
@export var spring_rate := 50000.0
@export var bump_damping := 5000.0
@export var rebound_damping := 7000.0
@export var driven := false
@export var steered := false
@export var has_handbrake := false
## Share of the RV's brake force this wheel takes.
@export var brake_share := 0.25

## The model's wheel node, moved to follow the suspension and spin.
var visual: Node3D
var visual_rest := Basis.IDENTITY
var steer_angle := 0.0
var grounded := false
## Spring length: mount to wheel centre.
var length := 0.0
var load := 0.0
var contact := Vector3.ZERO
var normal := Vector3.UP
## Contact-patch speed along the wheel's heading, m/s (+ = forward).
var ground_speed := 0.0
## 0 = gripping, towards 1 = sliding.
var slip := 0.0
## Drive force the tire could not put down (N); spins the axle up.
var excess_drive := 0.0
## Angular speed for visuals, rad/s (+ = rolling forward).
var spin_speed := 0.0
var surface_grip := 1.0
## 0..1: how muddy the ground under the tire is (less grip, much more drag).
var mud := 0.0
## Off the RV (bolts shaken out): no contact, no forces.
var detached := false
## Speed (m/s) this wheel hit the ground at this tick: set on touching down after being in
## the air, or when the suspension bottoms out hard. 0 otherwise. RVDamage decides if it hurt.
var impact_speed := 0.0

var _cast := ShapeCast3D.new()
var _prev_length := -1.0
var _spin_angle := 0.0
var _forward := Vector3.FORWARD
var _side := Vector3.RIGHT


func _ready() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	_cast.shape = sphere
	_cast.position = Vector3.UP * CAST_LIFT
	_cast.target_position = Vector3.DOWN * (travel + CAST_LIFT)
	_cast.collision_mask = TerrainStreamer.WORLD_LAYER
	_cast.max_results = 1
	_cast.enabled = false # Updated by hand, in step with the RV.
	add_child(_cast)
	length = travel


## Finds the ground under the wheel and its speed relative to it.
func probe(body: RV) -> void:
	_cast.force_shapecast_update()
	grounded = _cast.is_colliding() and not detached
	if grounded:
		contact = _cast.get_collision_point(0)
		normal = _cast.get_collision_normal(0)
		var reach := travel + CAST_LIFT
		length = clampf(reach * _cast.get_closest_collision_safe_fraction() - CAST_LIFT, 0.0, travel)
		# Belt and braces: if the contact is well above where the tire's bottom would be, the
		# sphere started inside something; trust the contact instead.
		var above := (global_position - contact).dot(body.global_basis.y) - radius
		if above < length - 0.1:
			length = maxf(0.0, above)
	else:
		length = travel
		contact = global_position + body.global_basis.y * -(travel + radius)
		normal = body.global_basis.y
	var heading := body.global_basis * Basis(Vector3.UP, steer_angle)
	_forward = _on_plane(-heading.z, normal)
	_side = _on_plane(heading.x, normal)
	ground_speed = body.point_velocity(contact).dot(_forward)


## Applies suspension and tire forces to `body`. `drive` is this wheel's share of the
## engine's force at the contact patch, `brake` the most braking force it may use.
func apply_forces(body: RV, dt: float, drive: float, brake: float) -> void:
	excess_drive = 0.0
	slip = 0.0
	impact_speed = 0.0
	if not grounded:
		load = 0.0
		_prev_length = -1.0
		return
	var up := body.global_basis.y
	var compression := travel - length
	# How fast the wheel meets the ground along the suspension (+ = closing).
	var closing := maxf(0.0, -body.point_velocity(contact).dot(normal))
	var speed: float
	if _prev_length < 0.0:
		speed = closing # Just touched down: the real closing speed, not a jump from full droop.
		impact_speed = closing
	else:
		speed = (_prev_length - length) / dt # + = compressing
		if length < 0.04 and speed > 0.0:
			impact_speed = minf(speed, closing + 1.0) # Bottomed out.
	_prev_length = length
	var damper := (bump_damping if speed > 0.0 else rebound_damping) * speed
	var bump_stop := maxf(0.0, 0.05 - length) * spring_rate * 20.0
	load = maxf(0.0, spring_rate * compression + damper + bump_stop)
	body.apply_force(up * load, global_position - body.global_position)

	var v := body.point_velocity(contact)
	var v_long := v.dot(_forward)
	var v_lat := v.dot(_side)
	var fz := load * clampf(normal.dot(up), 0.0, 1.0)
	var max_force := GRIP * surface_grip * fz
	# This corner's share of the RV, and of gravity along the ground (so a parked RV holds
	# on a slope instead of creeping).
	var corner_mass := body.mass * 0.25
	var gravity := body.get_gravity() * corner_mass

	# Lateral: slip-angle curve at speed; at a crawl, hold like static friction instead
	# (slip angles are meaningless near zero speed and would jitter).
	var alpha := atan2(v_lat, maxf(absf(v_long), 0.5))
	var sliding := lerpf(1.0, 0.8, clampf((absf(alpha) - PEAK_SLIP) / 0.4, 0.0, 1.0))
	var curve := minf(absf(alpha) / PEAK_SLIP, 1.0) * sliding
	var f_slip := -signf(alpha) * max_force * curve
	var f_hold := clampf(-v_lat * corner_mass / dt * 0.5 - gravity.dot(_side), -max_force, max_force)
	var f_lat := lerpf(f_hold, f_slip, clampf((absf(v_long) - CREEP_SPEED) / 4.0, 0.0, 1.0))

	# Longitudinal: brakes and rolling resistance work against the drive and gravity, up to
	# stopping the wheel this step, but never push it backwards.
	var resist := brake + ROLLING * (1.0 + 9.0 * mud) * fz
	var to_stop := -v_long * corner_mass / dt - gravity.dot(_forward)
	var f_long := drive + clampf(to_stop - drive, -resist, resist)

	var total := Vector2(f_long, f_lat).length()
	if total > max_force and total > 0.0:
		var k := max_force / total
		slip = 1.0 - k
		excess_drive = drive * (1.0 - k)
		f_long *= k
		f_lat *= k

	var at := contact + up * body.tire_force_height
	body.apply_force(_forward * f_long + _side * f_lat, at - body.global_position)


## Moves and spins the model's wheel. `extra_spin` is wheelspin on driven wheels (rad/s).
func update_visual(body: RV, dt: float, extra_spin: float) -> void:
	if visual == null:
		return
	if grounded:
		spin_speed = ground_speed / radius + extra_spin
	else:
		spin_speed = move_toward(spin_speed, extra_spin, 2.0 * dt)
	_spin_angle = wrapf(_spin_angle - spin_speed * dt, -PI, PI)
	var center := position + Vector3.DOWN * length
	var local := Transform3D(Basis(Vector3.UP, steer_angle) * Basis(Vector3.RIGHT, _spin_angle) * visual_rest, center)
	visual.global_transform = body.global_transform * local


static func _on_plane(v: Vector3, n: Vector3) -> Vector3:
	var p := v - n * v.dot(n)
	return p.normalized() if p.length_squared() > 1e-8 else v
