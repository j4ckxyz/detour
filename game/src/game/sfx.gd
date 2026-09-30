class_name Sfx
extends RefCounted
## Small helpers for sound: the game's Ogg Vorbis files (`assets/audio/`, credited in
## `assets/CREDITS.md`), loops, and one-shots at a place in the world. The buses are
## `Effects` (the RV, tools, footsteps, animals, chimes) and `Ambience` (birds, wind, rain);
## their volumes are the player's (see `Settings`).

const DIR := "res://assets/audio/"
const EFFECTS := &"Effects"
const AMBIENCE := &"Ambience"
## A source's `volume_db` is what's heard within its `unit_size` metres (`max_db` is set to the
## same, so it doesn't get louder up close), and it falls off 6 dB per doubling beyond that.
## Silence for a level: below it a loop is stopped.
const SILENT_DB := -80.0
const HAMMER_CLANKS: Array[String] = ["tools/hammer_clank_1", "tools/hammer_clank_2", "tools/hammer_clank_3"]

## Whether a trip is under way. Loading one (things going into hands and pockets, animals
## settling) is silent; the playground sets this once it's running.
static var armed := false


## A sound by its path under `assets/audio/` (no extension). Loops repeat seamlessly.
static func stream(path: String, loops := false) -> AudioStream:
	var s := load(DIR + path + ".ogg") as AudioStreamOggVorbis
	assert(s != null, "missing sound %s" % path)
	if loops:
		s.loop = true
	return s


## One of `variants` numbered files ("steps/step_grass" → "steps/step_grass_3").
static func pick(base: String, variants: int) -> String:
	return "%s_%d" % [base, 1 + randi() % variants]


## A 3D sound source on `bus`, added to `parent` (not playing yet).
static func source(parent: Node, name: String, path: String, loops: bool, bus: StringName, unit_size: float, max_distance: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = name
	p.stream = stream(path, loops)
	p.bus = bus
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.volume_db = SILENT_DB
	parent.add_child(p)
	return p


## Sets a looping source's loudness from a linear `level` (plus `base_db`): starts it when it
## becomes audible, stops it when it fades to nothing.
static func set_level(p: AudioStreamPlayer3D, level: float, base_db: float) -> void:
	if level < 0.003:
		if p.playing:
			p.stop()
		p.volume_db = SILENT_DB
		return
	p.volume_db = base_db + linear_to_db(level)
	p.max_db = p.volume_db
	if not p.playing:
		p.play()


## Plays a sound once where it happened. `unit_size` is how far it carries at full volume.
static func play_at(parent: Node, path: String, at: Vector3, volume_db := 0.0, pitch := 1.0, bus: StringName = EFFECTS, unit_size := 8.0, max_distance := 120.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(path)
	p.bus = bus
	p.unit_size = unit_size
	p.max_distance = max_distance
	p.max_db = volume_db
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	return p


## Like `play_at`, but only while a trip is under way (see `armed`) and with a little natural
## variety in the pitch: for the many small things that happen as you play.
static func cue(parent: Node, path: String, at: Vector3, volume_db := 0.0, unit_size := 6.0, max_distance := 60.0) -> void:
	if not armed or not parent.is_inside_tree():
		return
	play_at(parent, path, at, volume_db, randf_range(0.94, 1.06), EFFECTS, unit_size, max_distance)


## A sound with no place (a chime, a toast): on the Effects bus, heard even while paused.
static func play_ui(parent: Node, path: String, volume_db := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream(path)
	p.bus = EFFECTS
	p.volume_db = volume_db
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	return p
