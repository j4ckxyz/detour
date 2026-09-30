class_name Cosmetics
extends RefCounted
## What your person wears: a hat and glasses, picked on the main menu (remembered) and seen by
## everyone you play with. A few are free; the rest are earned (each names the achievement that
## unlocks it, see `Achievements`). Nothing here changes how the game plays.

const DEFAULT_HAT := &"beanie"
const DEFAULT_GLASSES := &"shades"

## id, name, and the achievement that unlocks it (none: free).
const HATS: Array[Dictionary] = [
	{"id": &"beanie", "name": "Beanie"},
	{"id": &"cap", "name": "Baseball cap"},
	{"id": &"bucket", "name": "Bucket hat"},
	{"id": &"none", "name": "No hat"},
	{"id": &"cowboy", "name": "Cowboy hat", "unlock": &"km_25"},
	{"id": &"hardhat", "name": "Hard hat", "unlock": &"mechanic"},
	{"id": &"chef", "name": "Chef's hat", "unlock": &"fast_food"},
	{"id": &"tophat", "name": "Top hat", "unlock": &"home"},
	{"id": &"antlers", "name": "Antlers", "unlock": &"bear_off"},
]
const GLASSES: Array[Dictionary] = [
	{"id": &"shades", "name": "Dark glasses"},
	{"id": &"round", "name": "Round glasses"},
	{"id": &"none", "name": "No glasses"},
	{"id": &"goggles", "name": "Driving goggles", "unlock": &"top_gear"},
]


## The list for `kind` (&"hat" or &"glasses").
static func list(kind: StringName) -> Array[Dictionary]:
	return HATS if kind == &"hat" else GLASSES


static func ids(kind: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for d: Dictionary in list(kind):
		out.append(d["id"])
	return out


static func is_valid(kind: StringName, id: StringName) -> bool:
	return ids(kind).has(id)


static func name_of(kind: StringName, id: StringName) -> String:
	for d: Dictionary in list(kind):
		if d["id"] == id:
			return String(d["name"])
	return String(id)


## Whether `id` is yours to wear (free, or its achievement is earned).
static func is_unlocked(kind: StringName, id: StringName) -> bool:
	for d: Dictionary in list(kind):
		if d["id"] == id:
			return not d.has("unlock") or Achievements.is_earned(d["unlock"])
	return false


## What unlocks it ("Reach 100 km/h"), or "" for a free one.
static func how_to_unlock(kind: StringName, id: StringName) -> String:
	for d: Dictionary in list(kind):
		if d["id"] == id and d.has("unlock"):
			var a := Achievements.definition(d["unlock"])
			return "%s: %s" % [a.get("title", ""), a.get("desc", "")]
	return ""


## `id` if it's a real one, else the default.
static func valid_or_default(kind: StringName, id: StringName) -> StringName:
	if is_valid(kind, id):
		return id
	return DEFAULT_HAT if kind == &"hat" else DEFAULT_GLASSES


## `id` if you may wear it, else the default (a hat whose achievement was reset).
static func wearable(kind: StringName, id: StringName) -> StringName:
	if is_valid(kind, id) and is_unlocked(kind, id):
		return id
	return DEFAULT_HAT if kind == &"hat" else DEFAULT_GLASSES
