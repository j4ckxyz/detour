class_name Weather
extends Node3D
## The weather (PLAN.md §4, atmosphere): spells of a few game hours, each clear, cloudy, wet,
## foggy or stormy, picked from the seed and the time, so everyone playing together sees the
## same sky without sending it. Wet weather is rain in the woods and the bayou, snow in the
## mountain pass; the canyon stays dry (clouds instead). Rain and snow fall around the camera;
## rain wets the ground (less grip) and storms bring lightning and gusts.

enum Kind { CLEAR, CLOUDY, RAIN, STORM, SNOW, FOG }

const NAMES: Array[String] = ["Clear", "Cloudy", "Rain", "Storm", "Snow", "Fog"]
## Game hours per weather spell.
const SPELL_HOURS := 3.0
## Biomes (see rvgen::biome).
const CANYON := 2
const PASS := 3

var kind := Kind.CLEAR
## 0..1: how strongly this spell is on (it builds up and clears at the ends of a spell).
var intensity := 0.0
## 0..1: how overcast, how foggy, how wet the ground is (wetness lags the rain).
var cloud := 0.0
var fog := 0.0
var wetness := 0.0
## A lightning flash, 0..1, fading fast.
var flash := 0.0
## Storm gusts: a sideways push for the RV (N per kg-ish, see RV.wind).
var wind := Vector3.ZERO

var _seed_text := ""
var _rain: GPUParticles3D
var _snow: GPUParticles3D
var _next_flash := 5.0


func setup(seed_text: String) -> void:
	_seed_text = seed_text


func _ready() -> void:
	_rain = _particles(2400, 1.2, Vector3(40.0, 1.0, 40.0), 16.0, 14.0, Color(0.75, 0.82, 0.9, 0.55), Vector2(0.025, 0.55), 0.0)
	_snow = _particles(1800, 7.0, Vector3(50.0, 1.0, 50.0), 12.0, 1.4, Color(1.0, 1.0, 1.0, 0.9), Vector2(0.09, 0.09), 1.2)
	for p: GPUParticles3D in [_rain, _snow]:
		add_child(p)


## The weather everywhere at `hours` (game hours since the trip began, not wrapped), before
## the local biome changes it.
func base_kind(hours: float) -> Kind:
	var spell := int(floor(hours / SPELL_HOURS))
	if spell <= 3:
		return Kind.CLEAR # Every trip starts on a fine morning (until noon on day one).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:weather:%d" % [_seed_text, spell])
	var roll := rng.randf()
	if roll < 0.38:
		return Kind.CLEAR
	if roll < 0.6:
		return Kind.CLOUDY
	if roll < 0.84:
		return Kind.RAIN
	if roll < 0.94:
		return Kind.FOG
	return Kind.STORM


## The weather at a biome: wet spells snow in the pass, the canyon stays dry.
static func local_kind(base: Kind, biome: int) -> Kind:
	match base:
		Kind.RAIN, Kind.STORM:
			if biome == PASS:
				return Kind.SNOW
			if biome == CANYON:
				return Kind.CLOUDY if base == Kind.RAIN else Kind.STORM
		Kind.FOG:
			if biome == CANYON:
				return Kind.CLEAR
	return base


## Updates for game time `hours` at `at` (the camera), in biome `biome`.
func update(hours: float, at: Vector3, biome: int, dt: float) -> void:
	kind = local_kind(base_kind(hours), biome)
	var phase := fposmod(hours, SPELL_HOURS) / SPELL_HOURS
	intensity = 0.0 if kind == Kind.CLEAR else smoothstep(0.0, 0.12, phase) * smoothstep(1.0, 0.88, phase)
	var target_cloud := 0.0
	var target_fog := 0.0
	match kind:
		Kind.CLOUDY:
			target_cloud = 0.6
		Kind.RAIN:
			target_cloud = 0.8
			target_fog = 0.25
		Kind.STORM:
			target_cloud = 1.0
			target_fog = 0.3
		Kind.SNOW:
			target_cloud = 0.75
			target_fog = 0.45
		Kind.FOG:
			target_cloud = 0.35
			target_fog = 0.85
	cloud = move_toward(cloud, target_cloud * intensity, dt * 0.05)
	fog = move_toward(fog, target_fog * intensity, dt * 0.05)
	var raining := kind == Kind.RAIN or kind == Kind.STORM
	wetness = move_toward(wetness, intensity if raining else 0.0, dt * (0.02 if raining else 0.004))
	_rain.global_position = at + Vector3.UP * 14.0
	_snow.global_position = at + Vector3.UP * 11.0
	_rain.emitting = raining and intensity > 0.05
	_rain.amount_ratio = clampf(intensity * (1.0 if kind == Kind.STORM else 0.6), 0.05, 1.0)
	_snow.emitting = kind == Kind.SNOW and intensity > 0.05
	_snow.amount_ratio = clampf(intensity, 0.05, 1.0)
	flash = move_toward(flash, 0.0, dt * 4.0)
	wind = Vector3.ZERO
	if kind == Kind.STORM and intensity > 0.3:
		_next_flash -= dt
		if _next_flash <= 0.0:
			flash = 1.0
			_next_flash = randf_range(6.0, 20.0)
		var gust := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.0007) * sin(Time.get_ticks_msec() * 0.0013)
		wind = Vector3(1.0, 0.0, 0.35).normalized() * gust * intensity


func describe() -> String:
	return NAMES[kind] if intensity > 0.2 or kind == Kind.CLEAR else "%s coming" % NAMES[kind]


static func _particles(amount: int, lifetime: float, box: Vector3, _height: float, speed: float, color: Color,
		size: Vector2, turbulence: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40.0, -40.0, -40.0), Vector3(80.0, 60.0, 80.0))
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = box * 0.5
	m.direction = Vector3.DOWN
	m.spread = 4.0
	m.initial_velocity_min = speed * 0.9
	m.initial_velocity_max = speed * 1.1
	m.gravity = Vector3(0.0, -9.8 if turbulence == 0.0 else -0.4, 0.0)
	if turbulence > 0.0:
		m.turbulence_enabled = true
		m.turbulence_noise_strength = turbulence
	p.process_material = m
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if size.y > size.x * 2.0 else BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	p.draw_pass_1 = quad
	return p
