extends Node
## Graphics quality presets (PLAN.md §9.3), applied at runtime.
##
## The renderer itself (Forward+ / Mobile / Compatibility) is fixed at startup and needs a
## restart to change; pass `--rendering-method <name>` on the command line to compare them.

signal preset_changed(preset: StringName)

## upscaler: &"spatial" (MetalFX spatial / FSR1) or &"temporal" (MetalFX temporal / FSR2).
const PRESETS: Dictionary[StringName, Dictionary] = {
	&"potato": {
		"render_scale": 0.6, "upscaler": &"spatial",
		"view_distance": 380.0, "tree_distance": 160.0, "decor_distance": 100.0,
		"shadow_distance": 40.0, "shadow_splits": 1, "shadow_size": 1024, "ssao": false,
	},
	&"low": {
		"render_scale": 0.67, "upscaler": &"spatial",
		"view_distance": 560.0, "tree_distance": 260.0, "decor_distance": 150.0,
		"shadow_distance": 70.0, "shadow_splits": 2, "shadow_size": 2048, "ssao": false,
	},
	&"medium": {
		"render_scale": 0.77, "upscaler": &"temporal",
		"view_distance": 900.0, "tree_distance": 450.0, "decor_distance": 250.0,
		"shadow_distance": 120.0, "shadow_splits": 2, "shadow_size": 2048, "ssao": false,
	},
	&"high": {
		"render_scale": 0.87, "upscaler": &"temporal",
		"view_distance": 1400.0, "tree_distance": 700.0, "decor_distance": 350.0,
		"shadow_distance": 200.0, "shadow_splits": 4, "shadow_size": 4096, "ssao": true,
	},
}

var current: StringName = &"medium"


func settings() -> Dictionary:
	return PRESETS[current]


func renderer() -> String:
	return RenderingServer.get_current_rendering_method()


func driver() -> String:
	return RenderingServer.get_current_rendering_driver_name()


func is_metal() -> bool:
	return driver() == "metal"


## Starting preset for this machine. Real auto-detection + benchmark comes in Phase 9.
func detect_default() -> StringName:
	if renderer() == "gl_compatibility":
		return &"potato"
	if OS.get_name() == "macOS" and Engine.get_architecture_name() == "arm64":
		# Even the entry A18 Pro holds 120 fps at 2560x1600 on high (docs/perf.md).
		return &"high"
	if RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		return &"low"
	return &"medium"


func apply(preset: StringName, viewport: Viewport, env: Environment, sun: DirectionalLight3D) -> void:
	if not PRESETS.has(preset):
		push_error("Unknown graphics preset '%s'" % preset)
		return
	current = preset
	var s: Dictionary = PRESETS[preset]

	var scale: float = s["render_scale"]
	viewport.scaling_3d_scale = scale
	viewport.scaling_3d_mode = _scaling_mode(s["upscaler"], scale)

	env.ssao_enabled = bool(s["ssao"]) and renderer() == "forward_plus"

	var splits: int = s["shadow_splits"]
	if splits <= 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	elif splits == 2:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = s["shadow_distance"]
	RenderingServer.directional_shadow_atlas_set_size(s["shadow_size"], true)

	preset_changed.emit(preset)


func _scaling_mode(upscaler: StringName, scale: float) -> Viewport.Scaling3DMode:
	var method := renderer()
	if method == "gl_compatibility":
		return Viewport.SCALING_3D_MODE_BILINEAR
	# Temporal upscalers need motion vectors, which only Forward+ provides. They also act as
	# anti-aliasing, so they stay on even at scale 1.0.
	if upscaler == &"temporal" and method == "forward_plus":
		return Viewport.SCALING_3D_MODE_METALFX_TEMPORAL if is_metal() else Viewport.SCALING_3D_MODE_FSR2
	if scale >= 1.0:
		return Viewport.SCALING_3D_MODE_BILINEAR
	return Viewport.SCALING_3D_MODE_METALFX_SPATIAL if is_metal() else Viewport.SCALING_3D_MODE_FSR
