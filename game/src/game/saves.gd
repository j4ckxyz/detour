class_name Saves
## Saved trips on disk: one file per seed code in `user://saves` (what the trip writes, see
## `Trip.save`). The main menu lists them to carry on or start again.

const DIR := "user://saves"


static func path(code: String) -> String:
	return DIR.path_join("%s.json" % code)


static func exists(code: String) -> bool:
	return FileAccess.file_exists(path(code))


## The save for `code` as written, or {} if there's none (or it's unreadable).
static func read(code: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path(code))
	var d: Variant = JSON.parse_string(text) if text != "" else null
	return d if d is Dictionary else {}


static func write(code: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	# Write then rename, so a crash mid-save never leaves half a file.
	var tmp := path(code) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, path(code)) == OK


static func delete(code: String) -> void:
	if exists(code):
		DirAccess.remove_absolute(path(code))


## Whether a save can be carried on with this build (made by the same world generator, and
## not finished).
static func can_continue(d: Dictionary) -> bool:
	return is_current(d) and not d.get("finished", false)


static func is_current(d: Dictionary) -> bool:
	return int(d.get("gen", 0)) == WorldGen.gen_version()


## Every saved trip, most recently played first: the save's contents plus `code`.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for file: String in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var code := file.trim_suffix(".json")
		var d := read(code)
		if d.is_empty():
			continue
		d["code"] = code
		out.append(d)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("saved_at", 0.0)) > float(b.get("saved_at", 0.0)))
	return out


## One line about a save for the menu: "Short trip · gas station 1 of 2 · 40% of the way ·
## day 1, 14:05 · 12 min played · 3 min ago".
static func describe(d: Dictionary, now: float = Time.get_unix_time_from_system()) -> String:
	var bits: PackedStringArray = []
	var stations := int(d.get("stations", 0))
	bits.append({2: "Short trip", 5: "Medium trip", 11: "Long trip"}.get(stations, "Trip"))
	if not is_current(d):
		bits.append("made by an older version: can't be continued")
	elif d.get("finished", false):
		bits.append("home in %s" % Trip.clock_of(float(d.get("elapsed", 0.0))))
	else:
		var checkpoint := int(d.get("checkpoint", 0))
		bits.append("left the camp" if checkpoint == 0 else "past gas station %d of %d" % [checkpoint, stations])
		if d.has("progress"):
			bits.append("%d%% of the way" % roundi(float(d["progress"]) * 100.0))
		var hours := float(d.get("hours", Trip.START_HOUR))
		bits.append("day %d, %02d:%02d" % [int(hours / 24.0) + 1, int(fposmod(hours, 24.0)), int(fposmod(hours * 60.0, 60.0))])
		bits.append("%d min played" % maxi(1, roundi(float(d.get("elapsed", 0.0)) / 60.0)))
	if d.has("completed") and not d.get("finished", false):
		bits.append("made it home before")
	if d.has("saved_at"):
		bits.append(ago(now - float(d["saved_at"])))
	return " · ".join(bits)


static func ago(seconds: float) -> String:
	if seconds < 90.0:
		return "just now"
	if seconds < 90.0 * 60.0:
		return "%d min ago" % roundi(seconds / 60.0)
	if seconds < 36.0 * 3600.0:
		return "%d h ago" % roundi(seconds / 3600.0)
	return "%d days ago" % roundi(seconds / 86400.0)
