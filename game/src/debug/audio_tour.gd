extends Node
## Scripted tour of the game's sounds, for listening (or measuring the real mix): dawn and day at
## the camp, inside the RV with the door shut and open, the engine stalling and cranking, driving,
## rain (inside, then out), a storm and a night. Each stage prints `STAGE <name> <seconds>`.
##
##   godot --path game res://src/debug/audio_tour.tscn
##   godot --headless --path game res://src/debug/audio_tour.tscn -- --capture=/tmp/tour.f32
##
## With `--capture=FILE` the Master bus's output (after its limiter, before the Master volume,
## which the tour sets to full) is written as raw 32-bit float stereo at the mix rate, in real
## time; `tools/audio/check_mix.py` measures it (loudness and peaks per stage, spectrogram).

const PLAYGROUND := preload("res://src/game/playground.tscn")
const HZ := 60.0

var _pg: Playground
var _start := 0
var _capture: AudioEffectCapture
var _out: FileAccess
var _captured := 0
var _saved_master := 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			_start_capture(arg.trim_prefix("--capture="))
	_pg = PLAYGROUND.instantiate()
	_pg.fresh_start = true
	_pg.peaceful = true
	add_child(_pg)
	_tour()


func _start_capture(path: String) -> void:
	_saved_master = Settings.volumes["Master"]
	var volumes := Settings.volumes.duplicate()
	volumes["Master"] = 1.0
	Settings.volumes = volumes
	Settings.apply()
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 2.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), _capture)
	_out = FileAccess.open(path, FileAccess.WRITE)
	print("CAPTURE %s at %d Hz" % [path, roundi(AudioServer.get_mix_rate())])


func _process(_dt: float) -> void:
	if _capture == null:
		return
	var n := _capture.get_frames_available()
	if n > 0:
		_out.store_buffer(_capture.get_buffer(n).to_byte_array())
		_captured += n


func _tour() -> void:
	while not _pg.is_spawned:
		await get_tree().process_frame
	Engine.max_fps = 60 # Real time, so the audio and the game run together.
	var rv := _pg.rv
	var player := _pg.player
	_start = Engine.get_process_frames()
	await _stage("camp_dawn", 6.4, 8.0)
	await _stage("camp_day", 10.0, 10.0)
	player.board(rv.to_local(player.global_position))
	rv.door_open = false
	await _stage("inside_door_shut", 10.0, 6.0)
	rv.door_open = true
	await _stage("inside_door_open", 10.0, 4.0)
	rv.door_open = false
	rv.drivetrain.running = false
	await _stage("engine_stalled", 10.0, 2.5)
	rv.start_engine()
	await _stage("cranking_then_idle", 10.0, 6.0)
	player.take_wheel()
	_pg.driver.enabled = false # The tour holds the pedals.
	rv.set_automatic(true)
	rv.parking_brake = false
	rv.throttle = 0.5
	await _stage("driving_gently", 10.0, 10.0)
	rv.throttle = 0.95
	await _stage("driving_hard", 10.0, 18.0)
	rv.throttle = 0.0
	rv.brake = 0.7
	await _stage("braking", 10.0, 5.0)
	rv.brake = 0.0
	rv.parking_brake = true
	rv.set_automatic(false)
	rv.drivetrain.shift_to_neutral() # Parked, idling.
	await _stage("rain_inside", _spell(Weather.Kind.RAIN), 8.0)
	player.stand_up()
	player.leave_rv()
	await _stage("rain_outside", _spell(Weather.Kind.RAIN), 8.0)
	await _stage("storm", _spell(Weather.Kind.STORM), 14.0)
	await _stage("night", 2.0, 10.0)
	print("TOUR done in %.1f s" % _seconds())
	if _out:
		_out.close()
		Settings.volumes["Master"] = _saved_master
		Settings.apply()
	get_tree().quit()


## Seconds into the tour: by the audio captured, else by frames.
func _seconds() -> float:
	if _capture:
		return _captured / AudioServer.get_mix_rate()
	return (Engine.get_process_frames() - _start) / HZ


## The clock at the middle of a spell of `kind` (full strength), by the trip's seed.
func _spell(kind: Weather.Kind) -> float:
	var at := _pg.rv.global_position
	for spell: int in range(4, 200):
		var hours := spell * Weather.SPELL_HOURS + Weather.SPELL_HOURS * 0.5
		if Weather.local_kind(_pg.weather.base_kind(hours), _pg.world.biome_at(at.x, at.z)) == kind:
			return hours
	return 10.0


## Sets the clock to `hours` (held there) and lets it play for `seconds`.
func _stage(stage: String, hours: float, seconds: float) -> void:
	print("STAGE %s %.1f" % [stage, _seconds()])
	print("  (RV %.1f m/s, %d rpm, gear %d)" % [_pg.rv.linear_velocity.length(), roundi(_pg.rv.drivetrain.rpm), _pg.rv.drivetrain.gear])
	var until := _seconds() + seconds
	while _seconds() < until:
		_pg.trip.hours = hours
		await get_tree().process_frame
