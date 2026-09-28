class_name WorldLighting
extends Node3D
## Sky, sun, fog and tonemapping shared by every outdoor scene.

var environment := Environment.new()
var sun := DirectionalLight3D.new()


func _ready() -> void:
	var horizon := Color(0.78, 0.80, 0.78)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.54, 0.80)
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


## Applies a graphics preset to the viewport, lights and the streamer's distances.
func apply_preset(preset: StringName, viewport: Viewport, streamer: TerrainStreamer, camera: Camera3D) -> void:
	Graphics.apply(preset, viewport, environment, sun)
	var s := Graphics.settings()
	var view: float = s["view_distance"]
	streamer.set_distances(view, s["tree_distance"], s["decor_distance"])
	camera.far = view + 200.0
	# Fade to the horizon colour before the streaming edge.
	environment.fog_depth_begin = view * 0.3
	environment.fog_depth_end = view * 0.95
