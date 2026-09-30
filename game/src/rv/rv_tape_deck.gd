class_name RVTapeDeck
extends Node3D
## The tape deck on the dashboard: a storage slot (`TapeDeck1`) that plays whatever cassette is
## put in it, on the Music bus, and shows what Dot says over it (see `Tapes`). Take the cassette
## out (pick it up) and it stops. Because a cassette is an ordinary item stowed in a slot, the
## deck works the same for everyone in a co-op game without any messages of its own: each
## machine sees the tape go in and plays it.
##
## A tape already in the deck when a trip loads stays quiet until it's taken out and put back.

signal tape_started(id: int)
signal tape_ended(id: int)

const SLOT := &"TapeDeck1"
## Where the deck is on the dashboard (RV space), and how loud the music is there.
const AT := Vector3(0.55, 1.36, -2.3)
const MUSIC_DB := -10.0
## The title shows for this long when a tape goes in (s).
const TITLE_TIME := 5.0

var rv: RV
var slot: StorageSlot
var speaker: AudioStreamPlayer3D
## The tape in the deck (-1 for none) and how far into it (s).
var tape := -1
var seconds := 0.0
var playing := false

var _watching := 0 # Instance id of the cassette last seen in the slot.
var _wait := 0.0
var _length := 0.0


func setup(owner_rv: RV) -> void:
	rv = owner_rv
	slot = rv.storage[SLOT]
	position = AT
	speaker = AudioStreamPlayer3D.new()
	speaker.name = "Speaker"
	speaker.bus = Sfx.MUSIC
	speaker.unit_size = 5.0
	speaker.max_distance = 45.0
	speaker.volume_db = MUSIC_DB
	speaker.max_db = MUSIC_DB
	add_child(speaker)
	process_mode = Node.PROCESS_MODE_ALWAYS # Sounds while the game's paused, like the other audio.


func _process(dt: float) -> void:
	if rv == null:
		return
	_wait -= dt
	if _wait <= 0.0:
		_wait = 0.2
		_look()
	if playing:
		seconds += dt
		if seconds >= _length + 0.5:
			_end()


## Whatever cassette is in the slot now.
func _look() -> void:
	var item := slot.stored()
	if item == null or item.kind != &"tape":
		if _watching != 0:
			_watching = 0
			eject()
		return
	if item.get_instance_id() == _watching:
		return
	_watching = item.get_instance_id()
	if Sfx.armed:
		insert(int(item.get_meta(&"tape", 0)))


## A cassette went in: it starts from the top.
func insert(id: int) -> void:
	tape = clampi(id, 0, Tapes.COUNT - 1)
	seconds = 0.0
	speaker.stream = Sfx.stream(Tapes.file(tape))
	_length = speaker.stream.get_length()
	playing = true
	speaker.play()
	Sfx.cue(self, "rv/tape_insert", global_position, -6.0, 4.0, 30.0)
	tape_started.emit(tape)


## The cassette came out (or the tape ran out).
func eject() -> void:
	if not playing and tape < 0:
		return
	var id := tape
	playing = false
	tape = -1
	speaker.stop()
	tape_ended.emit(id)


func _end() -> void:
	playing = false
	speaker.stop()
	tape_ended.emit(tape)
	tape = -1
	# The click of the tape finishing (the cassette stays in until someone takes it out).
	Sfx.cue(self, "rv/gear_clunk", global_position, -14.0, 3.0, 20.0)


## What Dot's saying now, or "" (a title for the first few seconds).
func subtitle() -> String:
	if not playing:
		return ""
	if seconds < TITLE_TIME:
		return "♪ %s" % Tapes.title(tape)
	return Tapes.line_at(tape, seconds)


## The music's loudness right now, for the tests.
func is_audible() -> bool:
	return playing and speaker.playing
