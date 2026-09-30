class_name RVAudio
extends Node3D
## What the RV sounds like (bus Effects): the engine (four loops made at different rpm,
## crossfaded and re-pitched to the engine's speed, louder under throttle), the starter's crank,
## the engine catching and stalling, the gearbox clunking into gear, tires humming and
## crunching with speed, wind rushing past, the door, landings and knocks.
##
## Everything is worked out from what the network snapshots carry (rpm, running, gear,
## throttle, wheels on the ground, velocity, the door), so a machine following someone else's
## RV hears the same as the driver does. Sounds only start once the playground says the trip
## is under way (`arm`), so a loading trip and a restored save are silent.
##
## The sounds are made by tools/audio/make_sounds.py (see assets/CREDITS.md).

const ENGINE_LOOPS: Array[String] = ["rv/engine_idle", "rv/engine_low", "rv/engine_mid", "rv/engine_high"]
## The rpm each engine loop was made at (tools/audio/make_sounds.py).
const ENGINE_RPMS: Array[float] = [750.0, 1320.0, 2100.0, 3400.0]
## The engine is at the front (RV space), and the wheels' noise comes from underneath.
const ENGINE_AT := Vector3(0.0, 0.9, -2.9)
const UNDER_AT := Vector3(0.0, 0.3, 0.0)
## How loud the engine is (dB at its `unit_size`) coasting and at full throttle.
const ENGINE_COAST_DB := -4.0
const ENGINE_LOAD_DB := -1.0
const TIRE_ROAD_DB := -4.0
const TIRE_GRAVEL_DB := -6.0
const WIND_RUSH_DB := -3.0
## Speed (m/s) at which tire and wind noise reach their loudest.
const FULL_SPEED := 26.0
## A landing from a fall faster than this (m/s) is heard; the fastest counts fully.
const LANDING_SPEED := Vector2(3.0, 11.0)
## Harder than this (m/s of speed lost in a frame) is a crash, when following someone else's RV.
const PUPPET_CRASH_DROP := 3.5
const KNOCK_COOLDOWN := 0.3
## Impulse (N·s over the damage threshold) of the hardest knock (see RVDamage.MAX_HIT).
const FULL_KNOCK := 14000.0

var rv: RV
var engine_players: Array[AudioStreamPlayer3D] = []
var crank_player: AudioStreamPlayer3D
var tire_road: AudioStreamPlayer3D
var tire_gravel: AudioStreamPlayer3D
var wind_rush: AudioStreamPlayer3D
## Whether the trip is under way (see `arm`).
var armed := false

var _engine_on := 0.0 # 0..1: the engine's sound fading in and out with `running`.
var _rpm := 0.0
var _rpm_lag := 0.0
var _load := 0.0
var _crank := 0.0
var _ground := 1.0
var _was_running := true
var _gear := 0
var _door_open := false
var _air_time := 0.0
var _fall_speed := 0.0
var _last_speed := 0.0
var _knock_wait := 0.0


func setup(owner_rv: RV) -> void:
	rv = owner_rv
	# Sounds go on while the game is paused, so the volume sliders in the pause menu can be heard.
	process_mode = Node.PROCESS_MODE_ALWAYS
	position = Vector3.ZERO
	for i: int in ENGINE_LOOPS.size():
		var p := Sfx.source(self, "Engine%d" % i, ENGINE_LOOPS[i], true, Sfx.EFFECTS, 7.0, 160.0)
		p.position = ENGINE_AT
		engine_players.append(p)
	crank_player = Sfx.source(self, "Crank", "rv/starter_crank", true, Sfx.EFFECTS, 6.0, 90.0)
	crank_player.position = ENGINE_AT
	tire_road = Sfx.source(self, "TireRoad", "rv/tire_road", true, Sfx.EFFECTS, 6.0, 110.0)
	tire_gravel = Sfx.source(self, "TireGravel", "rv/tire_gravel", true, Sfx.EFFECTS, 6.0, 110.0)
	wind_rush = Sfx.source(self, "WindRush", "ambience/wind_bed", true, Sfx.EFFECTS, 6.0, 90.0)
	for p: AudioStreamPlayer3D in [tire_road, tire_gravel, wind_rush]:
		p.position = UNDER_AT
	rv.damage.hit_taken.connect(_on_knocked)


## The trip is under way: sounds start, and what's already going on (the engine running, a
## gear in, the door open) isn't announced.
func arm() -> void:
	armed = true
	_sync()
	var d := rv.drivetrain
	_rpm = d.rpm
	_rpm_lag = d.rpm
	_engine_on = 1.0 if d.running else 0.0


func _sync() -> void:
	_was_running = rv.drivetrain.running
	_gear = rv.drivetrain.gear
	_door_open = rv.door_open
	_last_speed = rv.linear_velocity.length()


func _process(dt: float) -> void:
	if not armed:
		return
	var d := rv.drivetrain
	apply_engine(d.rpm, rv.throttle, d.running, _is_cranking(d, dt), dt)
	var grounded := 0
	for wheel: RVWheel in rv.wheels:
		grounded += 1 if wheel.grounded else 0
	var velocity := rv.linear_velocity
	apply_tires(velocity.length(), float(grounded) / maxf(1.0, float(rv.wheels.size())), velocity.y, dt)
	_events(dt)


## Whether the starter is turning the engine over. Driving the RV: the drivetrain knows.
## Following someone else's: only the rpm comes across, so it's an engine that isn't running
## but is turning at cranking speed and not slowing down (a stall dies away quickly).
func _is_cranking(d: RVDrivetrain, dt: float) -> bool:
	_rpm_lag = lerpf(_rpm_lag, d.rpm, 1.0 - exp(-dt * 4.0))
	if rv.is_simulated:
		return d.is_cranking()
	return not d.running and d.rpm > 90.0 and d.rpm > _rpm_lag - 15.0


## How much of each engine loop to hear at `rpm`: neighbouring loops crossfade (equal power)
## between the rpm they were made at, so no loop is stretched far from its own pitch.
static func loop_weights(rpm: float) -> Array[float]:
	var w: Array[float] = []
	w.resize(ENGINE_RPMS.size())
	w.fill(0.0)
	if rpm <= ENGINE_RPMS[0]:
		w[0] = 1.0
		return w
	for i: int in range(1, ENGINE_RPMS.size()):
		if rpm <= ENGINE_RPMS[i]:
			var t := log(rpm / ENGINE_RPMS[i - 1]) / log(ENGINE_RPMS[i] / ENGINE_RPMS[i - 1])
			w[i - 1] = cos(t * PI * 0.5)
			w[i] = sin(t * PI * 0.5)
			return w
	w[w.size() - 1] = 1.0
	return w


## The engine: `rpm`, the pedal, whether it runs, and whether it's being cranked.
func apply_engine(rpm: float, throttle: float, running: bool, cranking: bool, dt: float) -> void:
	_engine_on = move_toward(_engine_on, 1.0 if running else 0.0, dt * (3.0 if running else 4.0))
	_rpm = lerpf(_rpm, clampf(rpm, 0.0, 4600.0), 1.0 - exp(-dt * 18.0))
	_load = lerpf(_load, clampf(throttle, 0.0, 1.0), 1.0 - exp(-dt * 6.0))
	var weights := loop_weights(_rpm)
	var base := lerpf(ENGINE_COAST_DB, ENGINE_LOAD_DB, _load)
	for i: int in engine_players.size():
		engine_players[i].pitch_scale = clampf(_rpm / ENGINE_RPMS[i], 0.4, 2.2)
		Sfx.set_level(engine_players[i], weights[i] * _engine_on, base)
	_crank = move_toward(_crank, 1.0 if cranking else 0.0, dt * 8.0)
	Sfx.set_level(crank_player, _crank, -3.0)


## Tires and wind: how fast the RV goes, how many of its wheels are on the ground (0..1) and
## its vertical speed (for landings).
func apply_tires(speed: float, grounded: float, vertical: float, dt: float) -> void:
	_ground = move_toward(_ground, grounded, dt * 6.0)
	var s := clampf(absf(speed) / FULL_SPEED, 0.0, 1.0)
	tire_road.pitch_scale = 0.75 + 0.6 * s
	tire_gravel.pitch_scale = 0.8 + 0.45 * s
	Sfx.set_level(tire_road, pow(s, 0.9) * _ground, TIRE_ROAD_DB)
	Sfx.set_level(tire_gravel, smoothstep(0.02, 0.4, s) * (1.0 - 0.45 * s) * _ground, TIRE_GRAVEL_DB)
	Sfx.set_level(wind_rush, pow(s, 2.2), WIND_RUSH_DB)
	# A landing: airborne for a moment, coming down fast, then the wheels touch.
	if grounded < 0.01:
		_air_time += dt
		_fall_speed = -vertical
	else:
		if _air_time > 0.3 and _fall_speed > LANDING_SPEED.x:
			land(inverse_lerp(LANDING_SPEED.x, LANDING_SPEED.y, _fall_speed))
		_air_time = 0.0


## Gear changes, the engine starting and stalling, the door, knocks.
func _events(dt: float) -> void:
	var d := rv.drivetrain
	_knock_wait = maxf(0.0, _knock_wait - dt)
	if d.running != _was_running:
		_was_running = d.running
		Sfx.play_at(self, "rv/engine_start" if d.running else "rv/engine_stall", to_global(ENGINE_AT), -3.0)
	if d.gear != _gear:
		# Into neutral is softer than into gear; an automatic shifts gently.
		var soft := (-9.0 if d.gear == 0 else -3.0) - (4.0 if d.automatic else 0.0)
		_gear = d.gear
		Sfx.play_at(self, "rv/gear_clunk", to_global(rv.driver_eye.origin + Vector3(0.3, -0.5, -0.3)), soft, randf_range(0.94, 1.06))
	if rv.door_open != _door_open:
		_door_open = rv.door_open
		var door := Vector3(rv.interior.door_x_outer, rv.interior.floor_y + 1.0, (rv.interior.door_z.x + rv.interior.door_z.y) * 0.5)
		Sfx.play_at(self, "rv/door_open" if _door_open else "rv/door_close", to_global(door), -2.0, randf_range(0.96, 1.04))
	# Following someone else's RV nobody tells us about collisions, but its speed drops at once.
	var speed := rv.linear_velocity.length()
	if not rv.is_simulated and _last_speed - speed > PUPPET_CRASH_DROP:
		knock(clampf((_last_speed - speed) / 12.0, 0.2, 1.0))
	_last_speed = speed


## A hard landing (0..1 how hard): the body thumping down on its springs.
func land(strength: float) -> void:
	Sfx.play_at(self, "rv/landing_thud", to_global(UNDER_AT), lerpf(-14.0, -2.0, clampf(strength, 0.0, 1.0)), randf_range(0.92, 1.08))


## A collision (0..1 how hard): a thump and crumpling metal.
func knock(strength: float) -> void:
	if not armed or _knock_wait > 0.0:
		return
	_knock_wait = KNOCK_COOLDOWN
	Sfx.play_at(self, "rv/crash", global_position, lerpf(-14.0, 0.0, clampf(strength, 0.0, 1.0)), randf_range(0.94, 1.06))


func _on_knocked(impulse_over_threshold: float) -> void:
	# Called from the physics step: the sound starts just after it.
	knock.call_deferred(clampf(impulse_over_threshold / FULL_KNOCK, 0.15, 1.0))
