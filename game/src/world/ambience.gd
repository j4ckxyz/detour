class_name Ambience
extends Node
## The sounds of the outdoors (bus Ambience), all quiet and soft: birdsong by day (a call now
## and then from a random direction, rarer at dawn and dusk, none in heavy rain or snow),
## crickets at night, a wind bed that swells with the weather and storm gusts, rain that
## follows the rain, and a rumble of thunder some seconds after each flash.
##
## Inside the RV the world is muffled (a low-pass on the bus, opened up a little with the
## door open) and rain drums on the roof. Nothing sounds until the playground says the trip
## is under way (`arm`).
##
## The sounds are real CC0 birdsong and our own synthesized ones (assets/CREDITS.md).

const BIRDS: Array[String] = [
	"birds/blackbird_1", "birds/blackbird_2", "birds/blackbird_3", "birds/blackbird_4", "birds/blackbird_5",
	"birds/blackbird_6", "birds/blackbird_7", "birds/blackbird_8", "birds/blackbird_9", "birds/blackbird_10",
	"birds/blackbird_11", "birds/blackcap_1", "birds/blackcap_2", "birds/blackcap_3",
]
const THUNDER: Array[String] = ["ambience/thunder_1", "ambience/thunder_2"]
## Birds sing from a ring this far round the listener (m) and this high up.
const BIRD_RING := Vector2(14.0, 45.0)
const BIRD_HEIGHT := Vector2(2.0, 12.0)
const BIRD_POOL := 4
## How loud a bird is heard within 22 m of it (dB); farther it fades.
const BIRD_DB := -14.0
## Mean seconds between calls at the busiest (full daylight, fair weather) and the quietest.
const BIRD_GAP := Vector2(7.0, 28.0)
## The bus's low-pass (Hz) inside the RV with the door shut and open; outside it's off.
const MUFFLED_HZ := 1400.0
const DOOR_OPEN_HZ := 4200.0
const OPEN_HZ := 20500.0
const BUS := &"Ambience"

var weather: Weather
var lighting: WorldLighting
var player: Player
## Whether the trip is under way (see `arm`).
var armed := false

var wind_bed: AudioStreamPlayer
var wind_trees: AudioStreamPlayer
var rain: AudioStreamPlayer
var rain_roof: AudioStreamPlayer
var crickets: AudioStreamPlayer
var bird_players: Array[AudioStreamPlayer3D] = []
var thunder_players: Array[AudioStreamPlayer] = []

var _levels: Dictionary[StringName, float] = {}
var _bird_wait := 5.0
var _last_bird := -1
var _thunder_wait := -1.0
var _prev_flash := 0.0
var _cutoff := OPEN_HZ
var _bus := -1
var _birds: Array[AudioStream] = []


func setup(the_weather: Weather, the_lighting: WorldLighting, the_player: Player) -> void:
	weather = the_weather
	lighting = the_lighting
	player = the_player
	# Sounds go on while the game is paused, so the volume sliders in the pause menu can be heard.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus = AudioServer.get_bus_index(BUS)
	wind_bed = _bed("WindBed", "ambience/wind_bed")
	wind_trees = _bed("WindTrees", "ambience/wind_trees")
	rain = _bed("Rain", "ambience/rain_loop")
	rain_roof = _bed("RainRoof", "ambience/rain_roof")
	crickets = _bed("Crickets", "ambience/crickets_loop")
	for path: String in BIRDS:
		_birds.append(Sfx.stream(path))
	for i: int in BIRD_POOL:
		var p := AudioStreamPlayer3D.new()
		p.name = "Bird%d" % i
		p.bus = BUS
		p.unit_size = 22.0
		p.max_distance = 130.0
		add_child(p)
		bird_players.append(p)
	for path: String in THUNDER:
		var t := AudioStreamPlayer.new()
		t.name = path.get_file().capitalize().replace(" ", "")
		t.stream = Sfx.stream(path)
		t.bus = BUS
		add_child(t)
		thunder_players.append(t)


func _bed(node_name: String, path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = Sfx.stream(path, true)
	p.bus = BUS
	p.volume_db = Sfx.SILENT_DB
	add_child(p)
	return p


## The trip is under way: the sounds start from where the weather is now.
func arm() -> void:
	armed = true
	_prev_flash = weather.flash
	update(60.0)


func _process(dt: float) -> void:
	if armed:
		update(dt)


# --- what the weather and the hour ask for -------------------------------------------------------

## How fair the weather is for outdoor creatures, 0..1: heavy rain and snow silence them.
static func fair_weather(kind: Weather.Kind, intensity: float) -> float:
	match kind:
		Weather.Kind.CLOUDY:
			return 0.85
		Weather.Kind.FOG:
			return 0.65
		Weather.Kind.RAIN, Weather.Kind.STORM, Weather.Kind.SNOW:
			return 1.0 - smoothstep(0.05, 0.45, intensity)
	return 1.0


## How busy the birds are, 0..1: none at night, few at dawn and dusk, most by day.
static func bird_activity(daylight: float, kind: Weather.Kind, intensity: float) -> float:
	return smoothstep(0.3, 0.9, daylight) * fair_weather(kind, intensity)


## How loud the crickets are, 0..1: after dark, in fair weather.
static func cricket_level(daylight: float, kind: Weather.Kind, intensity: float) -> float:
	if kind == Weather.Kind.SNOW:
		return 0.0
	return smoothstep(0.5, 0.05, daylight) * fair_weather(kind, intensity)


## How loud the rain is, 0..1.
static func rain_level(kind: Weather.Kind, intensity: float) -> float:
	match kind:
		Weather.Kind.RAIN:
			return 0.75 * smoothstep(0.02, 0.5, intensity)
		Weather.Kind.STORM:
			return smoothstep(0.02, 0.6, intensity)
	return 0.0


## How loud the wind is, 0..1: a breath in fair weather, more in wet and stormy spells, and
## the gusts (`gust`: the length of the weather's wind vector) on top.
static func wind_level(kind: Weather.Kind, intensity: float, gust: float) -> float:
	var spell := 0.25
	match kind:
		Weather.Kind.CLOUDY:
			spell = 0.4
		Weather.Kind.RAIN:
			spell = 0.5
		Weather.Kind.STORM:
			spell = 0.85
		Weather.Kind.SNOW:
			spell = 0.5
		Weather.Kind.FOG:
			spell = 0.18
	return clampf(lerpf(0.25, spell, intensity) + gust * 0.35, 0.0, 1.0)


## The low-pass on the bus (Hz) for someone inside the RV or out.
static func muffle_hz(inside: bool, door_open: bool) -> float:
	if not inside:
		return OPEN_HZ
	return DOOR_OPEN_HZ if door_open else MUFFLED_HZ


# --- following them ------------------------------------------------------------------------------

## Follows the weather and the hour for `dt` seconds.
func update(dt: float) -> void:
	var kind := weather.kind
	var intensity := weather.intensity
	var inside := is_instance_valid(player) and player.inside
	var wind := wind_level(kind, intensity, weather.wind.length())
	var rain_now := rain_level(kind, intensity)
	var roof := 1.0 if inside else 0.0
	_bed_level(wind_bed, &"wind", wind, -3.0, dt)
	_bed_level(wind_trees, &"trees", 0.25 + wind * 0.75, -3.0, dt)
	_bed_level(rain, &"rain", rain_now, 3.0, dt)
	_bed_level(rain_roof, &"roof", rain_now * _smooth(&"inside", roof, dt, 0.5), 3.0, dt)
	_bed_level(crickets, &"crickets", cricket_level(lighting.daylight, kind, intensity), 3.0, dt)
	_muffle(inside, dt)
	_birds_step(dt)
	_thunder_step(dt)


func _smooth(key: StringName, target: float, dt: float, tau: float) -> float:
	var now := lerpf(_levels.get(key, 0.0), target, 1.0 - exp(-dt / tau))
	_levels[key] = now
	return now


func _bed_level(p: AudioStreamPlayer, key: StringName, target: float, base_db: float, dt: float) -> void:
	var level := _smooth(key, target, dt, 2.5)
	if level < 0.003:
		if p.playing:
			p.stop()
		p.volume_db = Sfx.SILENT_DB
		return
	p.volume_db = base_db + linear_to_db(level)
	if not p.playing:
		p.play(randf() * p.stream.get_length()) # Somewhere in the loop, so it isn't always the same start.


func _muffle(inside: bool, dt: float) -> void:
	var door := is_instance_valid(player) and player.rv != null and player.rv.door_open
	var target := muffle_hz(inside, door)
	_cutoff = exp(lerpf(log(_cutoff), log(target), 1.0 - exp(-dt * 3.0)))
	if _bus < 0:
		return
	var open := _cutoff > OPEN_HZ * 0.9
	var filter := AudioServer.get_bus_effect(_bus, 0) as AudioEffectLowPassFilter
	if filter:
		filter.cutoff_hz = _cutoff
		AudioServer.set_bus_effect_enabled(_bus, 0, not open)


func _birds_step(dt: float) -> void:
	_bird_wait -= dt
	if _bird_wait > 0.0:
		return
	var activity := bird_activity(lighting.daylight, weather.kind, weather.intensity)
	if activity < 0.05:
		_bird_wait = 2.0
		return
	_bird_wait = lerpf(BIRD_GAP.y, BIRD_GAP.x, activity) * randf_range(0.5, 1.5)
	sing()


## One bird sings from somewhere round the listener (if there's a free voice).
func sing() -> void:
	for p: AudioStreamPlayer3D in bird_players:
		if p.playing:
			continue
		var pick := randi() % _birds.size()
		if pick == _last_bird:
			pick = (pick + 1) % _birds.size()
		_last_bird = pick
		var cam := get_viewport().get_camera_3d()
		var here := cam.global_position if cam else Vector3.ZERO
		var angle := randf() * TAU
		var away := randf_range(BIRD_RING.x, BIRD_RING.y)
		p.stream = _birds[pick]
		p.global_position = here + Vector3(cos(angle) * away, randf_range(BIRD_HEIGHT.x, BIRD_HEIGHT.y), sin(angle) * away)
		p.volume_db = BIRD_DB + randf_range(-4.0, 1.5)
		p.max_db = p.volume_db
		p.pitch_scale = randf_range(0.94, 1.06)
		p.play()
		return


func _thunder_step(dt: float) -> void:
	if weather.flash > 0.8 and _prev_flash <= 0.8:
		_thunder_wait = randf_range(0.6, 5.0) # The farther the strike, the longer the wait.
	_prev_flash = weather.flash
	if _thunder_wait < 0.0:
		return
	_thunder_wait -= dt
	if _thunder_wait >= 0.0:
		return
	_thunder_wait = -1.0
	var t := thunder_players[randi() % thunder_players.size()]
	t.volume_db = randf_range(-9.0, -3.0)
	t.pitch_scale = randf_range(0.9, 1.05)
	t.play()
