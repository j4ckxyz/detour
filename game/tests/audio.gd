extends Node
## Headless sound test (the dummy audio driver plays nothing, so this checks what the game asks
## of the speakers): the Master, Effects and Ambience buses exist and the player's volumes reach
## them; the RV's engine is silent when it's off and plays when it runs, follows the rpm and the
## pedal, cranks and stalls; tires get louder with speed and go quiet in the air; birds sing only
## by day and in fair weather, crickets after dark, rain follows the rain, thunder follows
## lightning, the RV muffles the outdoors; and every sound file is credited.
##
##   godot --headless --path game --fixed-fps 60 res://tests/audio.tscn

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60
const AUDIO_DIR := "res://assets/audio"
const CREDITS := "res://assets/CREDITS.md"
## All the sounds together stay small (MB).
const MAX_SIZE_MB := 8.0

var _pg: Playground
var _failures: PackedStringArray = []
var _saved := ""


func _ready() -> void:
	_run()


func _run() -> void:
	if FileAccess.file_exists(Settings.PATH): # Put the player's own settings back after.
		_saved = FileAccess.get_file_as_string(Settings.PATH)
	Settings.reset()
	_buses()
	_credits()
	Session.seed_code = Playground.DEFAULT_SEED
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	var waited := 0
	while not _pg.is_spawned and waited < HZ * 60:
		await get_tree().physics_frame
		waited += 1
	_check(_pg.is_spawned, "a trip starts")
	await _hold(0.5)
	_engine()
	_tires()
	await _rv_events()
	_birds_and_night()
	_weather_beds()
	_muffled_indoors()
	_thunder()
	_pg.trip.clear_save()
	_pg.queue_free()
	Session.seed_code = ""
	await get_tree().process_frame
	Settings.reset()
	if _saved != "":
		var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f.store_string(_saved)
		f.close()
	else:
		DirAccess.remove_absolute(Settings.PATH)
	_finish()


func _buses() -> void:
	for bus: String in ["Master", "Effects", "Ambience"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "the %s bus exists" % bus)
	_check(ProjectSettings.get_setting("audio/buses/default_bus_layout") == "res://default_bus_layout.tres", "the project uses the bus layout")
	for bus: String in ["Effects", "Ambience"]:
		_check(AudioServer.get_bus_send(AudioServer.get_bus_index(bus)) == &"Master", "%s goes through Master" % bus)
	var volumes := Settings.volumes.duplicate()
	volumes["Master"] = 0.5
	volumes["Effects"] = 0.25
	volumes["Ambience"] = 0.0
	Settings.set_value(&"volumes", volumes)
	var master := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	var effects := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Effects"))
	_check(is_equal_approx(master, linear_to_db(0.5)), "Master volume 50 %% reaches its bus (%.1f dB)" % master)
	_check(is_equal_approx(effects, linear_to_db(0.25)), "Effects volume 25 %% reaches its bus (%.1f dB)" % effects)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")), "Ambience at 0 mutes its bus")
	Settings.reset()
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Ambience")), "and resetting brings it back")


## Every sound file is credited in CREDITS.md, and every credited file exists.
func _credits() -> void:
	var text := FileAccess.get_file_as_string(CREDITS)
	var files: PackedStringArray = _ogg_files(AUDIO_DIR)
	_check(files.size() >= 30, "the sounds are there (%d files)" % files.size())
	var missing: PackedStringArray = []
	var bytes := 0
	for path: String in files:
		var rel := path.trim_prefix("res://assets/")
		if not text.contains("`%s`" % rel):
			missing.append(rel)
		bytes += FileAccess.get_file_as_bytes(path).size()
	_check(missing.is_empty(), "every sound file is credited in CREDITS.md (missing: %s)" % ", ".join(missing))
	var stale: PackedStringArray = []
	var re := RegEx.create_from_string("`(audio/[a-z0-9_/]+\\.ogg)`")
	for m: RegExMatch in re.search_all(text):
		if not FileAccess.file_exists("res://assets/" + m.get_string(1)):
			stale.append(m.get_string(1))
	_check(stale.is_empty(), "and CREDITS.md names no sound that isn't there (%s)" % ", ".join(stale))
	_check(bytes < MAX_SIZE_MB * 1048576.0, "the sounds are %.1f MB, under %.0f" % [bytes / 1048576.0, MAX_SIZE_MB])


func _ogg_files(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for name: String in DirAccess.get_files_at(dir):
		if name.ends_with(".ogg"):
			out.append(dir.path_join(name))
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_ogg_files(dir.path_join(sub)))
	return out


func _engine() -> void:
	var audio := _pg.rv.audio
	_check(audio.armed, "the RV's sounds are on once the trip starts")
	_check(_pg.rv.drivetrain.running and audio.engine_players[0].playing and audio.engine_players[0].volume_db > -30.0,
		"the engine idles (%.1f dB)" % audio.engine_players[0].volume_db)
	_check(audio.engine_players[0].bus == &"Effects", "on the Effects bus")

	# Off: silent.
	audio.apply_engine(750.0, 0.0, false, false, 5.0)
	_check(_playing(audio.engine_players) == 0, "engine off: no engine sound")
	# Running: plays, at the pitch it was made at.
	audio.apply_engine(750.0, 0.0, true, false, 5.0)
	_check(audio.engine_players[0].playing and absf(audio.engine_players[0].pitch_scale - 1.0) < 0.05, "engine running at idle: plays at its own pitch (%.2f)" % audio.engine_players[0].pitch_scale)
	# The pitch rises with the rpm (inside a loop's range), and the loop played moves up.
	var pitches: Array[float] = []
	for rpm: float in [750.0, 900.0, 1050.0, 1200.0]:
		audio.apply_engine(rpm, 0.0, true, false, 5.0)
		pitches.append(audio.engine_players[0].pitch_scale)
	_check(pitches[0] < pitches[1] and pitches[1] < pitches[2] and pitches[2] < pitches[3], "pitch rises with rpm (%.2f, %.2f, %.2f, %.2f)" % [pitches[0], pitches[1], pitches[2], pitches[3]])
	var ok_order := true
	var stretched := ""
	var last := -1
	for step: int in range(700, 4200, 50):
		var rpm := float(step)
		audio.apply_engine(rpm, 0.5, true, false, 5.0)
		var loudest := 0
		for i: int in audio.engine_players.size():
			if audio.engine_players[i].playing and audio.engine_players[i].volume_db > audio.engine_players[loudest].volume_db:
				loudest = i
		for i: int in audio.engine_players.size():
			var p := audio.engine_players[i]
			# No loop is far from its own pitch while it's a real part of the mix.
			if p.playing and p.volume_db > audio.engine_players[loudest].volume_db - 12.0 and (p.pitch_scale > 1.8 or p.pitch_scale < 0.5):
				stretched = "%d rpm: loop %d at x%.2f" % [step, i, p.pitch_scale]
		ok_order = ok_order and loudest >= last
		last = loudest
	_check(ok_order and last == 3, "louder loops go from idle to high as the rpm climbs (ends on loop %d)" % last)
	_check(stretched == "", "no audible loop is stretched far (%s)" % stretched)
	# The pedal opens it up.
	audio.apply_engine(2000.0, 0.0, true, false, 5.0)
	var coasting := _loudest_db(audio.engine_players)
	audio.apply_engine(2000.0, 1.0, true, false, 5.0)
	var pulling := _loudest_db(audio.engine_players)
	_check(pulling > coasting + 2.0, "the engine is louder under throttle (%.1f -> %.1f dB)" % [coasting, pulling])
	# Cranking.
	audio.apply_engine(210.0, 0.0, false, true, 5.0)
	_check(audio.crank_player.playing and _playing(audio.engine_players) == 0, "cranking: the starter runs, the engine loops don't")
	audio.apply_engine(750.0, 0.0, true, false, 5.0)
	_check(not audio.crank_player.playing, "and stops when it catches")
	var mix := RVAudio.loop_weights(1700.0)
	_check(is_equal_approx(mix[1] * mix[1] + mix[2] * mix[2], 1.0) and mix[0] == 0.0 and mix[3] == 0.0, "loops crossfade with constant power")


func _tires() -> void:
	var audio := _pg.rv.audio
	audio.apply_tires(0.0, 1.0, 0.0, 5.0)
	_check(not audio.tire_road.playing and not audio.tire_gravel.playing and not audio.wind_rush.playing, "standing still: no tire or wind noise")
	audio.apply_tires(6.0, 1.0, 0.0, 5.0)
	var slow_road := audio.tire_road.volume_db
	var slow_pitch := audio.tire_road.pitch_scale
	var slow_wind := audio.wind_rush.volume_db
	audio.apply_tires(20.0, 1.0, 0.0, 5.0)
	_check(audio.tire_road.playing and audio.tire_road.volume_db > slow_road + 3.0, "tire noise rises with speed (%.1f -> %.1f dB)" % [slow_road, audio.tire_road.volume_db])
	_check(audio.tire_road.pitch_scale > slow_pitch, "and its pitch (%.2f -> %.2f)" % [slow_pitch, audio.tire_road.pitch_scale])
	_check(audio.wind_rush.playing and audio.wind_rush.volume_db > slow_wind, "and the wind rushing by")
	_check(audio.tire_gravel.playing and audio.tire_road.bus == &"Effects", "gravel crunch too, on the Effects bus")
	audio.apply_tires(20.0, 0.0, -1.0, 5.0)
	_check(not audio.tire_road.playing and not audio.tire_gravel.playing, "in the air the tires go quiet")
	audio.apply_tires(0.0, 1.0, 0.0, 5.0)


## The real RV, through its own events: stalling, starting, cranking, shifting, a knock.
func _rv_events() -> void:
	var rv := _pg.rv
	var audio := rv.audio
	await _hold(0.3)
	var before := _one_shots("engine_stall")
	rv.drivetrain.running = false
	await _hold(0.6)
	_check(_one_shots("engine_stall") == before + 1, "the engine stalling makes the stall sound")
	_check(_playing(audio.engine_players) == 0, "and the engine loops fade out (rpm %d)" % roundi(rv.drivetrain.rpm))
	rv.drivetrain.gear = 0
	rv.start_engine()
	await _hold(0.25)
	_check(rv.drivetrain.is_cranking() and audio.crank_player.playing, "cranking plays the starter")
	before = _one_shots("engine_start")
	await _hold(1.2)
	_check(rv.drivetrain.running, "the engine caught")
	_check(_one_shots("engine_start") == before + 1 and not audio.crank_player.playing and audio.engine_players[0].playing, "catching plays the start, the starter stops, the engine idles")
	before = _one_shots("gear_clunk")
	rv.drivetrain.gear = 1
	await _hold(0.2)
	_check(_one_shots("gear_clunk") == before + 1, "shifting into gear clunks")
	rv.drivetrain.gear = 0
	before = _one_shots("crash")
	rv.damage.hit_taken.emit(9000.0)
	await _hold(0.2)
	_check(_one_shots("crash") == before + 1, "a hard knock crashes")
	before = _one_shots("door_open")
	rv.door_open = true
	await _hold(0.2)
	_check(_one_shots("door_open") == before + 1, "the door opening is heard")
	rv.door_open = false
	before = _one_shots("landing_thud")
	audio.land(1.0)
	_check(_one_shots("landing_thud") == before + 1, "a landing thumps")


func _birds_and_night() -> void:
	var amb := _pg.ambience
	var light := _pg.lighting
	var weather := _pg.weather
	# What the hour and the weather ask for.
	_check(Ambience.bird_activity(0.0, Weather.Kind.CLEAR, 0.0) == 0.0, "no birds at night")
	_check(Ambience.bird_activity(1.0, Weather.Kind.CLEAR, 0.0) == 1.0, "birds by day in clear weather")
	_check(Ambience.bird_activity(0.5, Weather.Kind.CLEAR, 0.0) < 1.0 and Ambience.bird_activity(0.5, Weather.Kind.CLEAR, 0.0) > 0.0, "fewer at dawn and dusk")
	_check(Ambience.bird_activity(1.0, Weather.Kind.RAIN, 1.0) == 0.0 and Ambience.bird_activity(1.0, Weather.Kind.SNOW, 1.0) == 0.0 and Ambience.bird_activity(1.0, Weather.Kind.STORM, 1.0) == 0.0, "none in heavy rain, storms or snow")
	_check(Ambience.bird_activity(1.0, Weather.Kind.RAIN, 0.0) > 0.9, "but a spell of rain that's only just starting doesn't stop them")
	_check(Ambience.cricket_level(0.0, Weather.Kind.CLEAR, 0.0) > 0.9 and Ambience.cricket_level(1.0, Weather.Kind.CLEAR, 0.0) == 0.0, "crickets after dark, not by day")

	# On the nodes (set and read within a frame: the playground would reset them next).
	weather.kind = Weather.Kind.CLEAR
	weather.intensity = 0.0
	weather.flash = 0.0
	weather.wind = Vector3.ZERO
	light.daylight = 0.0
	amb.update(60.0)
	for p: AudioStreamPlayer3D in amb.bird_players:
		p.stop()
	for i: int in 20:
		amb._bird_wait = 0.0
		amb.update(0.1)
	_check(_playing(amb.bird_players) == 0, "night: no bird sings")
	_check(amb.crickets.playing and amb.crickets.volume_db > -30.0, "night: the crickets chirp (%.1f dB)" % amb.crickets.volume_db)
	light.daylight = 1.0
	amb.update(60.0)
	for p: AudioStreamPlayer3D in amb.bird_players:
		p.stop()
	amb._bird_wait = 0.0
	amb.update(0.1)
	_check(_playing(amb.bird_players) == 1, "day, clear: a bird sings")
	_check(not amb.crickets.playing, "day: no crickets")
	var bird := amb.bird_players.filter(func(p: AudioStreamPlayer3D) -> bool: return p.playing)[0] as AudioStreamPlayer3D
	var cam := get_viewport().get_camera_3d()
	var away := bird.global_position.distance_to(cam.global_position)
	_check(away > 10.0 and away < 60.0 and bird.bus == &"Ambience", "from a place round the listener (%.0f m away), on the Ambience bus" % away)
	weather.kind = Weather.Kind.RAIN
	weather.intensity = 1.0
	for p: AudioStreamPlayer3D in amb.bird_players:
		p.stop()
	for i: int in 20:
		amb._bird_wait = 0.0
		amb.update(0.1)
	_check(_playing(amb.bird_players) == 0, "day, heavy rain: none")
	weather.kind = Weather.Kind.CLEAR
	weather.intensity = 0.0


func _weather_beds() -> void:
	var amb := _pg.ambience
	var weather := _pg.weather
	_pg.lighting.daylight = 1.0
	weather.kind = Weather.Kind.CLEAR
	weather.intensity = 0.0
	amb.update(60.0)
	_check(not amb.rain.playing, "fair weather: no rain")
	_check(amb.wind_bed.playing and amb.wind_bed.volume_db < -3.0, "a light breeze (%.1f dB)" % amb.wind_bed.volume_db)
	var breeze := amb.wind_bed.volume_db
	weather.kind = Weather.Kind.RAIN
	weather.intensity = 0.3
	amb.update(60.0)
	var light_rain := amb.rain.volume_db
	_check(amb.rain.playing, "rain: the rain sound plays")
	weather.intensity = 1.0
	amb.update(60.0)
	_check(amb.rain.volume_db > light_rain + 3.0, "heavier rain is louder (%.1f -> %.1f dB)" % [light_rain, amb.rain.volume_db])
	_check(amb.rain.bus == &"Ambience" and amb.rain_roof.bus == &"Ambience", "on the Ambience bus")
	_check(not amb.rain_roof.playing, "no drumming on the roof outdoors")
	weather.kind = Weather.Kind.STORM
	weather.wind = Vector3(1.0, 0.0, 0.35).normalized() * 0.9
	amb.update(60.0)
	_check(amb.wind_bed.volume_db > breeze + 6.0, "a storm's wind is louder than a breeze (%.1f -> %.1f dB)" % [breeze, amb.wind_bed.volume_db])
	var storm_rain := amb.rain.volume_db
	weather.kind = Weather.Kind.SNOW
	weather.wind = Vector3.ZERO
	amb.update(60.0)
	_check(not amb.rain.playing and storm_rain > light_rain, "snow: no rain sound")
	weather.kind = Weather.Kind.CLEAR
	weather.intensity = 0.0
	amb.update(60.0)
	_check(not amb.rain.playing, "and it stops when the rain does")


func _muffled_indoors() -> void:
	var amb := _pg.ambience
	var weather := _pg.weather
	var player := _pg.player
	var bus := AudioServer.get_bus_index("Ambience")
	var filter := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	_check(filter != null, "the Ambience bus has a low-pass filter")
	amb.update(60.0)
	_check(not AudioServer.is_bus_effect_enabled(bus, 0), "outdoors: the filter is off")
	weather.kind = Weather.Kind.RAIN
	weather.intensity = 1.0
	player.inside = true
	var door := _pg.rv.door_open
	_pg.rv.door_open = false
	amb.update(60.0)
	_check(AudioServer.is_bus_effect_enabled(bus, 0) and filter.cutoff_hz < 2000.0, "inside the RV: muffled (%.0f Hz)" % filter.cutoff_hz)
	_check(amb.rain_roof.playing and amb.rain_roof.volume_db > -12.0, "and the rain drums on the roof (%.1f dB)" % amb.rain_roof.volume_db)
	_pg.rv.door_open = true
	amb.update(60.0)
	_check(filter.cutoff_hz > 3000.0 and filter.cutoff_hz < 6000.0, "with the door open it's less muffled (%.0f Hz)" % filter.cutoff_hz)
	player.inside = false
	_pg.rv.door_open = door
	weather.kind = Weather.Kind.CLEAR
	weather.intensity = 0.0
	amb.update(60.0)
	_check(not AudioServer.is_bus_effect_enabled(bus, 0), "stepping out opens it up again")


func _thunder() -> void:
	var amb := _pg.ambience
	var weather := _pg.weather
	weather.kind = Weather.Kind.STORM
	weather.intensity = 1.0
	weather.flash = 0.0
	amb.update(0.1)
	_check(not _any(amb.thunder_players), "no thunder without lightning")
	weather.flash = 1.0
	amb.update(0.05)
	_check(amb._thunder_wait > 0.0 and not _any(amb.thunder_players), "a flash: the thunder comes a moment later")
	amb.update(10.0)
	_check(_any(amb.thunder_players), "and rumbles")
	weather.flash = 0.0
	weather.kind = Weather.Kind.CLEAR
	weather.intensity = 0.0
	amb.update(60.0)


func _hold(seconds: float) -> void:
	for i: int in int(seconds * HZ):
		await get_tree().physics_frame


static func _playing(players: Array) -> int:
	var n := 0
	for p: Node in players:
		n += 1 if p.playing else 0
	return n


static func _any(players: Array) -> bool:
	return _playing(players) > 0


static func _loudest_db(players: Array[AudioStreamPlayer3D]) -> float:
	var best := -INF
	for p: AudioStreamPlayer3D in players:
		if p.playing:
			best = maxf(best, p.volume_db)
	return best


## How many one-shot sounds of a file the RV's sounds are playing.
func _one_shots(file: String) -> int:
	var n := 0
	for c: Node in _pg.rv.audio.get_children():
		var p := c as AudioStreamPlayer3D
		if p and p.stream and p.stream.resource_path.ends_with("/%s.ogg" % file):
			n += 1
	return n


func _finish() -> void:
	if _failures.is_empty():
		print("audio: all checks passed")
		get_tree().quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failures.append(what)
