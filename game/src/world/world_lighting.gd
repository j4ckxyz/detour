class_name WorldLighting
extends Node3D
## Sky, sun, fog and tonemapping shared by every outdoor scene, with the time of day (the
## sun and moon move, dawn and dusk tint the sky, nights are dark blue) and the weather
## (clouds dim and grey the sky, fog closes in, lightning flashes).

const DAY_TOP := Color(0.36, 0.54, 0.80)
const DAY_HORIZON := Color(0.78, 0.80, 0.78)
const NIGHT_TOP := Color(0.02, 0.03, 0.08)
const NIGHT_HORIZON := Color(0.06, 0.08, 0.14)
const DUSK := Color(0.95, 0.58, 0.34)
const OVERCAST := Color(0.58, 0.6, 0.62)

var environment := Environment.new()
var sun := DirectionalLight3D.new()
var moon := DirectionalLight3D.new()
## 0 at night .. 1 in daylight (for lights and hints).
var daylight := 1.0

var _sky_material := ProceduralSkyMaterial.new()
var _view := 1000.0


func _ready() -> void:
	var horizon := DAY_HORIZON
	var sky_material := _sky_material
	sky_material.sky_top_color = DAY_TOP
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = Color(0.30, 0.31, 0.27)
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.fog_enabled = true
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_light_color = horizon
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.4
	environment.fog_depth_curve = 1.6
	environment.glow_enabled = true
	environment.glow_intensity = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun.rotation_degrees = Vector3(-38.0, -35.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.0
	moon.shadow_enabled = false
	add_child(moon)


## Sets the sky for `hours` (0..24, 6 = sunrise, 18 = sunset) and the weather.
func set_conditions(hours: float, cloud: float, fog: float, flash: float) -> void:
	# The sun rises in the east (+x), is highest at noon, sets in the west.
	var elevation := sin((hours - 6.0) / 12.0 * PI) * 62.0
	var azimuth := lerpf(-90.0, 90.0, clampf((hours - 6.0) / 12.0, 0.0, 1.0))
	daylight = smoothstep(-6.0, 10.0, elevation)
	var low_sun := smoothstep(-4.0, 3.0, elevation) * smoothstep(22.0, 4.0, elevation)
	sun.rotation_degrees = Vector3(-maxf(elevation, 2.0), -azimuth, 0.0) # Light heads west at dawn.
	sun.light_energy = 1.25 * smoothstep(-2.0, 12.0, elevation) * (1.0 - 0.7 * cloud) + 2.5 * flash
	sun.light_color = Color(1.0, 0.95, 0.86).lerp(Color(1.0, 0.62, 0.38), low_sun)
	sun.visible = sun.light_energy > 0.01
	moon.rotation_degrees = Vector3(-40.0, 180.0 - azimuth, 0.0)
	moon.light_energy = 0.14 * (1.0 - daylight) * (1.0 - 0.6 * cloud)
	moon.visible = moon.light_energy > 0.01
	var top := NIGHT_TOP.lerp(DAY_TOP, daylight)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight).lerp(DUSK, low_sun * 0.7)
	top = top.lerp(OVERCAST * lerpf(0.15, 1.0, daylight), cloud * 0.8)
	horizon = horizon.lerp(OVERCAST * lerpf(0.2, 1.0, daylight), cloud * 0.6)
	top = top.lerp(Color.WHITE, flash * 0.6)
	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_horizon_color = horizon
	environment.fog_light_color = horizon
	environment.ambient_light_energy = lerpf(0.25, 1.0, daylight) * (1.0 - 0.25 * cloud) + flash
	environment.fog_depth_begin = _view * lerpf(0.3, 0.02, fog)
	environment.fog_depth_end = _view * lerpf(0.95, 0.18, fog)


## Applies a graphics preset to the viewport, lights and the streamer's distances.
func apply_preset(preset: StringName, viewport: Viewport, streamer: TerrainStreamer, camera: Camera3D) -> void:
	Graphics.apply(preset, viewport, environment, sun)
	var s := Graphics.settings()
	var view: float = s["view_distance"]
	streamer.set_distances(view, s["tree_distance"], s["decor_distance"])
	camera.far = view + 200.0
	# Fade to the horizon colour before the streaming edge (set_conditions thickens it).
	_view = view
	environment.fog_depth_begin = view * 0.3
	environment.fog_depth_end = view * 0.95
