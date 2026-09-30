class_name Sfx
extends RefCounted
## Small helpers for sound: the game's Ogg Vorbis files (`assets/audio/`, credited in
## `assets/CREDITS.md`), loops, and one-shots at a place in the world. The buses are
## `Effects` (the RV, tools) and `Ambience` (birds, wind, rain); their volumes are the
## player's (see `Settings`).

const DIR := "res://assets/audio/"
const EFFECTS := &"Effects"
const AMBIENCE := &"Ambience"
## A source's `volume_db` is what's heard within its `unit_size` metres (`max_db` is set to the
## same, so it doesn't get louder up close), and it falls off 6 dB per doubling beyond that.
## Silence for a level: below it a loop is stopped.
const SILENT_DB := -80.0
const HAMMER_CLANKS: Array[String] = ["tools/hammer_clank_1", "tools/hammer_clank_2", "tools/hammer_clank_3"]


## A sound by its path under `assets/audio/` (no extension). Loops repeat seamlessly.
static func stream(path: String, loops := false) -> AudioStream:
	var s := load(DIR + path + ".ogg") as AudioStreamOggVorbis
	assert(s != null, "missing sound %s" % path)
	if loops:
		s.loop = true
	return s


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


## Plays a sound once where it happened.
static func play_at(parent: Node, path: String, at: Vector3, volume_db := 0.0, pitch := 1.0, bus: StringName = EFFECTS) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(path)
	p.bus = bus
	p.unit_size = 8.0
	p.max_distance = 120.0
	p.max_db = volume_db
	p.volume_db = volume_db
	p.pitch_scale = pitch
	parent.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
	return p
