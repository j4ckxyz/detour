class_name UpdateLogic
extends RefCounted
## How a release build replaces itself, per platform. No networking here (that's `Updater`),
## so tests can drive every step with local files.
##
## Updates are swapped in place, next to the install, so the next launch runs the new version
## even if the player just quits:
## - macOS: the new `Detour.app` takes the old bundle's place (the running copy keeps its
##   open files until it exits).
## - Linux AppImage: the new file is renamed over the old one (atomic on the same volume).
## - Linux tarball: each file is renamed over; files in use are first moved aside into the
##   staging folder.
## - Windows portable folder: the running game holds its own exe open (the game data is
##   inside it), so nothing can be swapped while it runs. The new version is unpacked into
##   `.detour-update/pending`; on restart (or, if the player just quits, as the game exits or
##   on its next launch) the *new* exe is started with `--finish-update`: it waits for the old
##   one to exit, copies itself and its files over the install, and starts it.
## - Windows run straight from the zip (Explorer unpacks it to a temp folder that's thrown
##   away): the update installs a copy in %LOCALAPPDATA%\Programs\Detour instead, and from
##   then on the copy in the zip hands over to it.
## - Windows, when the install folder isn't writable (an all-users install): the installer
##   runs silently on restart instead.
## Leftovers live in a `.detour-update` staging folder and are deleted on the next launch.

enum Mode { UNSUPPORTED, MAC_BUNDLE, APPIMAGE, FOLDER_TAR, FOLDER_ZIP, WINDOWS_INSTALLER }

## Release asset used by each mode (see .github/workflows/build.yml).
const ASSETS: Dictionary[Mode, String] = {
	Mode.MAC_BUNDLE: "Detour-macos-universal.zip",
	Mode.APPIMAGE: "Detour-x86_64.AppImage",
	Mode.FOLDER_TAR: "Detour-linux-x86_64.tar.gz",
	Mode.FOLDER_ZIP: "Detour-windows-x86_64.zip",
	Mode.WINDOWS_INSTALLER: "Detour-Setup-x86_64.exe",
}
const SUMS_ASSET := "SHA256SUMS"
const STAGING := ".detour-update"
## Windows portable: where the unpacked update waits, and the file saying it's complete.
const PENDING := "pending"
const PENDING_READY := "ready.txt"
## Arguments (after `--`) that make a new version finish installing itself.
const FINISH_ARG := "--finish-update="
const WAIT_ARG := "--wait-pid="
const THEN_ARG := "--then-run="


## Where and how this copy of the game is installed.
class Install:
	var mode := Mode.UNSUPPORTED
	## What gets replaced: the .app bundle, the AppImage file, or the install folder.
	var target := ""
	## Scratch folder, on the same volume as `target` so renames are cheap and atomic.
	var staging := ""
	## What to run to restart into the new version.
	var launch := ""
	## Why updating can't work here, in words for the player (empty if it can).
	var problem := ""
	## Windows portable: files can't be swapped while the game runs (see `finish`).
	var deferred := false
	## Running straight from a zip: updates install to `target`, a folder of its own.
	var relocated := false

	func asset() -> String:
		return ASSETS.get(mode, "")


## Works out the install from the running executable. `appimage` is $APPIMAGE (set by the
## AppImage runtime), `user_dir` a writable fallback for the Windows installer; on Windows,
## `temp_dir` is %TEMP% and `programs_dir` %LOCALAPPDATA%\Programs.
static func detect(os_name: String, exe_path: String, appimage: String, user_dir: String,
		temp_dir: String = "", programs_dir: String = "") -> Install:
	var inst := Install.new()
	match os_name:
		"macOS":
			var marker := ".app/Contents/MacOS/"
			var at := exe_path.find(marker)
			if at < 0:
				inst.problem = "This copy isn't an app bundle."
				return inst
			inst.mode = Mode.MAC_BUNDLE
			inst.target = exe_path.left(at + 4)
			inst.staging = inst.target.get_base_dir().path_join(STAGING)
			inst.launch = inst.target
			if inst.target.contains("/AppTranslocation/"):
				inst.problem = "Move Detour.app to your Applications folder, then open it from there to enable updates."
			elif not writable(inst.target.get_base_dir()):
				inst.problem = "No permission to replace %s." % inst.target
		"Linux", "FreeBSD":
			if appimage != "":
				inst.mode = Mode.APPIMAGE
				inst.target = appimage
				inst.staging = appimage.get_base_dir().path_join(STAGING)
				inst.launch = appimage
			else:
				inst.mode = Mode.FOLDER_TAR
				inst.target = exe_path.get_base_dir()
				inst.staging = inst.target.path_join(STAGING)
				inst.launch = exe_path
			if not writable(inst.staging.get_base_dir()):
				inst.problem = "No permission to write to %s." % inst.staging.get_base_dir()
		"Windows":
			inst.target = exe_path.get_base_dir()
			inst.launch = exe_path
			if temp_dir != "" and programs_dir != "" and _is_inside(exe_path, temp_dir):
				# Run from inside the zip: Explorer's temp copy is thrown away, so updates go to
				# a folder of its own.
				inst.mode = Mode.FOLDER_ZIP
				inst.deferred = true
				inst.relocated = true
				inst.target = programs_dir.path_join("Detour")
				inst.launch = inst.target.path_join(exe_path.get_file())
				inst.staging = inst.target.path_join(STAGING)
			elif writable(inst.target):
				inst.mode = Mode.FOLDER_ZIP
				inst.deferred = true
				inst.staging = inst.target.path_join(STAGING)
			else:
				inst.mode = Mode.WINDOWS_INSTALLER
				inst.staging = user_dir.path_join(STAGING)
		_:
			inst.problem = "Updates aren't supported on %s." % os_name
	return inst


static func _is_inside(path: String, dir: String) -> bool:
	var p := path.replace("\\", "/").to_lower()
	var d := dir.replace("\\", "/").to_lower().trim_suffix("/") + "/"
	return p.begins_with(d)


static func writable(dir: String) -> bool:
	var probe := dir.path_join(".detour-write-test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


## Whether `release` (GitHub API JSON) is newer than this build. Nightlies compare commits,
## and only move forward in time; stable builds compare version numbers.
static func is_newer(release: Dictionary, channel: String, version: String, commit: String, built: String) -> bool:
	if channel == "nightly":
		var remote := str(release.get("target_commitish", ""))
		if remote == "" or remote == commit:
			return false
		return str(release.get("published_at", "")) > built
	return compare_versions(str(release.get("tag_name", "")).trim_prefix("v"), version) > 0


## Compares "1.2.3" style versions; a pre-release ("1.2.3-beta") sorts before its release.
## Returns -1, 0 or 1.
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split("-", true, 1)
	var pb := b.split("-", true, 1)
	var na := pa[0].split(".")
	var nb := pb[0].split(".")
	for i: int in maxi(na.size(), nb.size()):
		var x := int(na[i]) if i < na.size() else 0
		var y := int(nb[i]) if i < nb.size() else 0
		if x != y:
			return 1 if x > y else -1
	var ra := pa[1] if pa.size() > 1 else ""
	var rb := pb[1] if pb.size() > 1 else ""
	if ra == rb:
		return 0
	if ra == "":
		return 1
	if rb == "":
		return -1
	return 1 if ra > rb else -1


## A short name for a release, for the menu.
static func release_label(release: Dictionary) -> String:
	var tag := str(release.get("tag_name", ""))
	if tag == "nightly":
		return "nightly %s" % str(release.get("target_commitish", "")).left(7)
	return tag.trim_prefix("v")


static func find_asset(release: Dictionary, asset_name: String) -> Dictionary:
	for a: Variant in release.get("assets", []):
		if a is Dictionary and str(a.get("name", "")) == asset_name:
			return a
	return {}


## Parses `sha256sum` output into {file name: hex digest}.
static func parse_sums(text: String) -> Dictionary[String, String]:
	var out: Dictionary[String, String] = {}
	for line: String in text.split("\n", false):
		var parts := line.strip_edges().split(" ", false, 1)
		if parts.size() == 2:
			out[parts[1].strip_edges().trim_prefix("*")] = parts[0].to_lower()
	return out


## Installs the downloaded `file` (already verified). Returns "" or an error for the player.
## Blocking: run it off the main thread.
static func apply(inst: Install, file: String) -> String:
	match inst.mode:
		Mode.MAC_BUNDLE:
			return _apply_bundle(inst, file)
		Mode.APPIMAGE:
			return _apply_appimage(inst, file)
		Mode.FOLDER_TAR:
			return _apply_archive(inst, PackedStringArray(["tar", "-xzf", file, "-C"]), "linux")
		Mode.FOLDER_ZIP:
			# Windows 10+ ships bsdtar, which reads zips; elsewhere (tests) use unzip.
			var extract := PackedStringArray(["tar", "-xf", file, "-C"]) if OS.get_name() == "Windows" \
				else PackedStringArray(["unzip", "-q", "-o", file, "-d"])
			if inst.deferred:
				return _unpack_pending(inst, extract)
			return _apply_archive(inst, extract, "")
		Mode.WINDOWS_INSTALLER:
			return "" # The installer runs on restart.
	return "Updates aren't supported on this platform."


## Starts the new version (or the Windows installer). The caller quits right after.
static func launch(inst: Install, installer: String) -> int:
	match inst.mode:
		Mode.MAC_BUNDLE:
			return OS.create_process("open", ["-n", inst.launch])
		Mode.WINDOWS_INSTALLER:
			return OS.create_process(installer, ["/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART"])
	if inst.deferred:
		return finish_in_background(inst, OS.get_process_id(), true)
	return OS.create_process(inst.launch, [])


## Deletes what an earlier update left behind (the previous version, spent downloads), but
## not an update still waiting to be swapped in.
static func cleanup(inst: Install) -> void:
	if inst.staging == "" or not DirAccess.dir_exists_absolute(inst.staging):
		return
	if has_pending(inst):
		for f: String in DirAccess.get_files_at(inst.staging):
			DirAccess.remove_absolute(inst.staging.path_join(f)) # The spent download.
		return
	remove_tree(inst.staging)


# --- Windows portable: finishing the swap once the game has exited ---------------------------

## Whether an unpacked update is waiting to be swapped in.
static func has_pending(inst: Install) -> bool:
	return inst.deferred and FileAccess.file_exists(inst.staging.path_join(PENDING).path_join(PENDING_READY))


## Starts the new version (waiting in `pending`) to swap itself in once process `pid` has
## exited, then start the game (if `relaunch`).
static func finish_in_background(inst: Install, pid: int, relaunch: bool) -> int:
	var pending := inst.staging.path_join(PENDING)
	var args := PackedStringArray(["--", FINISH_ARG + inst.target, WAIT_ARG + str(pid)])
	if relaunch:
		args.append(THEN_ARG + inst.launch)
	return OS.create_process(pending.path_join(inst.launch.get_file()), args)


## The work of `--finish-update`: waits (up to a minute) for process `wait_pid` to exit, then
## copies everything in `source` (the pending update, where this copy runs from) over
## `target`, retrying a few times while antivirus scanners let go of files. Returns "" or an
## error. `source`'s ready marker is removed once it's done, so it isn't applied twice.
static func finish(source: String, target: String, wait_pid: int) -> String:
	var waited := 0
	while wait_pid > 0 and OS.is_process_running(wait_pid) and waited < 600:
		OS.delay_msec(100)
		waited += 1
	for rel: String in _files(source, ""):
		if rel == PENDING_READY:
			continue
		var dst := target.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		var ok := false
		for attempt: int in 40:
			if DirAccess.copy_absolute(source.path_join(rel), dst) == OK:
				ok = true
				break
			OS.delay_msec(250)
		if not ok:
			return "Couldn't replace %s (is Detour still running?)." % rel
	DirAccess.remove_absolute(source.path_join(PENDING_READY))
	return ""


static func _unpack_pending(inst: Install, extract: PackedStringArray) -> String:
	var pending := inst.staging.path_join(PENDING)
	remove_tree(pending)
	DirAccess.make_dir_recursive_absolute(pending)
	var args := extract.slice(1)
	args.append(pending)
	if OS.execute(extract[0], args) != 0:
		return "Couldn't unpack the update."
	if not FileAccess.file_exists(pending.path_join(inst.launch.get_file())):
		return "The update doesn't contain %s." % inst.launch.get_file()
	var marker := FileAccess.open(pending.path_join(PENDING_READY), FileAccess.WRITE)
	if marker == null:
		return "Couldn't finish unpacking the update."
	marker.store_line(Time.get_datetime_string_from_system())
	marker.close()
	return ""


static func _apply_bundle(inst: Install, file: String) -> String:
	var fresh := inst.staging.path_join("new")
	remove_tree(fresh)
	DirAccess.make_dir_recursive_absolute(fresh)
	# ditto keeps the bundle's permissions, symlinks and signature intact.
	if OS.execute("ditto", ["-x", "-k", file, fresh]) != 0:
		return "Couldn't unpack the update."
	var app := ""
	for d: String in DirAccess.get_directories_at(fresh):
		if d.ends_with(".app"):
			app = fresh.path_join(d)
	if app == "":
		return "The update doesn't contain an app."
	var old := inst.staging.path_join("old-%d.app" % Time.get_unix_time_from_system())
	if DirAccess.rename_absolute(inst.target, old) != OK:
		return "Couldn't move the current version aside."
	if DirAccess.rename_absolute(app, inst.target) != OK:
		DirAccess.rename_absolute(old, inst.target)
		return "Couldn't put the new version in place."
	return ""


static func _apply_appimage(inst: Install, file: String) -> String:
	if OS.execute("chmod", ["+x", file]) != 0:
		return "Couldn't make the update executable."
	if DirAccess.rename_absolute(file, inst.target) != OK:
		return "Couldn't replace %s." % inst.target
	return ""


## Unpacks with `extract` + the destination folder, then swaps the files in. The archive's
## files sit under `subdir` (the Linux tarball has a `linux/` folder; the zip has none).
static func _apply_archive(inst: Install, extract: PackedStringArray, subdir: String) -> String:
	var fresh := inst.staging.path_join("new")
	remove_tree(fresh)
	DirAccess.make_dir_recursive_absolute(fresh)
	var args := extract.slice(1)
	args.append(fresh)
	if OS.execute(extract[0], args) != 0:
		return "Couldn't unpack the update."
	var root := fresh.path_join(subdir) if subdir != "" else fresh
	return replace_tree(root, inst.target, inst.staging.path_join("old"))


## Moves every file under `source` into `target` (same relative paths). Files it replaces go
## to `aside` first, which works even for a running executable on Windows.
static func replace_tree(source: String, target: String, aside: String) -> String:
	for rel: String in _files(source, ""):
		var src := source.path_join(rel)
		var dst := target.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
		if FileAccess.file_exists(dst):
			var moved := aside.path_join(rel)
			DirAccess.make_dir_recursive_absolute(moved.get_base_dir())
			if FileAccess.file_exists(moved):
				DirAccess.remove_absolute(moved)
			if DirAccess.rename_absolute(dst, moved) != OK:
				return "Couldn't move %s aside." % rel
		if DirAccess.rename_absolute(src, dst) != OK:
			return "Couldn't install %s." % rel
	return ""


static func _files(root: String, rel: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := root.path_join(rel)
	for f: String in DirAccess.get_files_at(dir):
		out.append(rel.path_join(f) if rel != "" else f)
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_files(root, rel.path_join(d) if rel != "" else d))
	return out


## Deletes a folder and everything in it (symlinks are removed, not followed).
static func remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for f: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d: String in dir.get_directories():
		var sub := path.path_join(d)
		if dir.is_link(d):
			DirAccess.remove_absolute(sub)
		else:
			remove_tree(sub)
	DirAccess.remove_absolute(path)
