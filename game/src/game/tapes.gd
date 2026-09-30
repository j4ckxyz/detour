class_name Tapes
extends RefCounted
## The cassettes: Dot's road-trip tapes, eight of them, left in the places along the road.
## Each has a tune (made for the game, `assets/audio/music/tape_N.ogg`, see
## tools/audio/make_music.py) and what Dot says over it, shown as subtitles while it plays:
## `[seconds in, what she says]`. Find them, put them in the deck on the dashboard, listen.

const COUNT := 8
const DIR := "music/tape_%d"

## title, what Dot says.
const TAPES: Array[Dictionary] = [
	{"title": "Dust and Gravel", "lines": [
		[3.0, "Testing, testing. Is this thing on? It is. Hello, whoever's got Bertha now."],
		[13.0, "If you've found my tapes, you've found the good stuff. The radio's rubbish out here."],
		[25.0, "She stalls if you look at her wrong. Go easy on the clutch and she'll love you for it."],
		[37.0, "Follow the road home. Everything in between is optional. Mostly."],
		[48.0, "Side A. Enjoy the ride."]]},
	{"title": "Highway Hum", "lines": [
		[3.0, "Day two. Wally wanted a shortcut. There is no shortcut. There's only the road."],
		[15.0, "The engine sounds happy today. Or maybe that's me, humming along."],
		[28.0, "Folk leave things behind, out here. Look around. You'll be surprised what's useful."],
		[42.0, "Fifth gear at last. Bertha's shaking like a leaf, but she's smiling."],
		[55.0, "Keep the horn handy. You never know who's listening."]]},
	{"title": "Gas Station Waltz", "lines": [
		[3.0, "We found a diner with a sign so bright you could see it from space."],
		[12.0, "The burgers were terrible. We had two each."],
		[21.0, "Wally fixed the frame while I stood guard against a very determined eagle."],
		[31.0, "Fill her up, fix her up, and we're back on the road before the coffee's cold."]]},
	{"title": "Night Drive", "lines": [
		[4.0, "Driving at night. The headlights make a little tunnel and we all fit in it."],
		[16.0, "Wally's asleep in the passenger seat. Somebody has to stay awake for the both of us."],
		[30.0, "Keep a flashlight in your pocket. The dark out here is the real thing."],
		[44.0, "Every mile a star goes by. I've stopped counting, and it's a relief."],
		[57.0, "Not far now."]]},
	{"title": "Bayou Blues", "lines": [
		[4.0, "Mud. So much mud. Bertha weighs more than my patience."],
		[17.0, "The frogs out here are louder than the engine. I think they're laughing at us."],
		[31.0, "Momentum, Wally said. Momentum, I said. We sat in the middle of it for an hour."],
		[46.0, "But there's a kind of quiet in the wet that I'll miss."],
		[62.0, "We got out. Eventually."]]},
	{"title": "Canyon Sunrise", "lines": [
		[4.0, "Red rock as far as I can see, and the sun coming up over all of it."],
		[18.0, "Made a cup of tea on the back step and forgot to drink it."],
		[33.0, "I can see why people stay in places like this. And why they leave."],
		[47.0, "Right. Enough gawping. The road's waiting."]]},
	{"title": "Frostpeak", "lines": [
		[4.0, "It's cold. Properly cold. The kind of cold that gets into the tape."],
		[17.0, "Bertha doesn't love ice, and I don't love Bertha on ice."],
		[32.0, "The trick is to keep something solid under the wheels. Anything solid."],
		[47.0, "Snow on the pines. If I could bottle it I'd send it to my sister."],
		[59.0, "Nearly home."]]},
	{"title": "Home Again", "lines": [
		[4.0, "If you can hear this, you made it. I knew you would."],
		[15.0, "That's my house, there, with the fence and the big sign. Yes, that one."],
		[28.0, "Thank you for looking after her. She's not much, but she's mine."],
		[41.0, "Come in. The kettle's on."]]},
]


static func title(id: int) -> String:
	return String(TAPES[clampi(id, 0, COUNT - 1)]["title"])


## The tune's file under assets/audio.
static func file(id: int) -> String:
	return DIR % (clampi(id, 0, COUNT - 1) + 1)


## Dot's lines for a tape: [[seconds in, text], ...].
static func lines(id: int) -> Array:
	return TAPES[clampi(id, 0, COUNT - 1)]["lines"]


## What Dot's saying `seconds` into a tape (the latest line so far, for as long as it takes to
## read it), or "".
static func line_at(id: int, seconds: float) -> String:
	var text := ""
	var lines_of := lines(id)
	for i: int in lines_of.size():
		var at: float = lines_of[i][0]
		if seconds < at:
			break
		var until: float = lines_of[i + 1][0] if i + 1 < lines_of.size() else at + 10.0
		if seconds < minf(until, at + 9.0):
			text = String(lines_of[i][1])
	return text
