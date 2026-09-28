extends SceneTree
## Updater logic without the network: version checks, install detection, and installing real
## archives the way each platform does it (CI runs this on Linux, macOS and Windows).
##   godot --headless --path game --script res://tests/updater_units.gd

var _failures: PackedStringArray = []
var _root := OS.get_user_data_dir().path_join("updater_test")


func _initialize() -> void:
	UpdateLogic.remove_tree(_root)
	DirAccess.make_dir_recursive_absolute(_root)
	_versions()
	_release_parsing()
	_detection()
	_replace_tree()
	_folder_zip()
	if OS.get_name() != "Windows":
		_folder_tar()
		_appimage()
	if OS.get_name() == "macOS":
		_mac_bundle()
	UpdateLogic.remove_tree(_root)
	_check(not DirAccess.dir_exists_absolute(_root), "remove_tree cleans up")
	if _failures.is_empty():
		print("updater units: all checks passed")
		quit(0)
	else:
		for f: String in _failures:
			printerr("FAIL: ", f)
		quit(1)


func _versions() -> void:
	_check(UpdateLogic.compare_versions("0.2.0", "0.1.9") == 1, "minor beats patch")
	_check(UpdateLogic.compare_versions("0.10.0", "0.9.0") == 1, "numeric, not string, compare")
	_check(UpdateLogic.compare_versions("1.0.0", "1.0.0") == 0, "equal")
	_check(UpdateLogic.compare_versions("1.0.0-beta", "1.0.0") == -1, "pre-release sorts first")
	_check(UpdateLogic.compare_versions("1.0", "1.0.0") == 0, "missing parts are zero")

	var nightly := {"tag_name": "nightly", "target_commitish": "bbbb", "published_at": "2026-09-29T10:00:00Z"}
	_check(UpdateLogic.is_newer(nightly, "nightly", "", "aaaa", "2026-09-28T10:00:00Z"), "newer nightly")
	_check(not UpdateLogic.is_newer(nightly, "nightly", "", "bbbb", "2026-09-28T10:00:00Z"), "same commit is current")
	_check(not UpdateLogic.is_newer(nightly, "nightly", "", "cccc", "2026-09-30T10:00:00Z"), "older nightly ignored")
	var stable := {"tag_name": "v0.2.0"}
	_check(UpdateLogic.is_newer(stable, "stable", "0.1.0", "x", ""), "newer stable")
	_check(not UpdateLogic.is_newer(stable, "stable", "0.2.0", "x", ""), "same stable")


func _release_parsing() -> void:
	var release := {
		"tag_name": "nightly", "target_commitish": "0123456789abcdef",
		"assets": [{"name": "SHA256SUMS", "browser_download_url": "u1"}, {"name": "Detour-x86_64.AppImage", "browser_download_url": "u2"}],
	}
	_check(UpdateLogic.release_label(release) == "nightly 0123456", "nightly label")
	_check(UpdateLogic.release_label({"tag_name": "v1.2.0"}) == "1.2.0", "stable label")
	_check(UpdateLogic.find_asset(release, "Detour-x86_64.AppImage").get("browser_download_url") == "u2", "find asset")
	_check(UpdateLogic.find_asset(release, "nope").is_empty(), "missing asset")
	var sums := UpdateLogic.parse_sums("ABCDEF  Detour-x86_64.AppImage\n123abc *Detour-macos-universal.zip\n\n")
	_check(sums.get("Detour-x86_64.AppImage") == "abcdef", "sha256sum line (lower-cased)")
	_check(sums.get("Detour-macos-universal.zip") == "123abc", "binary-mode sha256sum line")


func _detection() -> void:
	var apps := _root.path_join("Apps")
	DirAccess.make_dir_recursive_absolute(apps)
	var mac := UpdateLogic.detect("macOS", apps.path_join("Detour.app/Contents/MacOS/Detour"), "", _root)
	_check(mac.mode == UpdateLogic.Mode.MAC_BUNDLE and mac.target == apps.path_join("Detour.app"), "mac bundle: %s" % mac.target)
	_check(mac.staging == apps.path_join(".detour-update") and mac.problem == "", "mac staging next to the bundle")
	var moved := UpdateLogic.detect("macOS", "/private/var/folders/x/AppTranslocation/y/d/Detour.app/Contents/MacOS/Detour", "", _root)
	_check(moved.problem.contains("Applications"), "translocated app asks to be moved")

	var image := UpdateLogic.detect("Linux", "/tmp/.mount_x/usr/bin/detour.x86_64", _root.path_join("Detour.AppImage"), _root)
	_check(image.mode == UpdateLogic.Mode.APPIMAGE and image.asset() == "Detour-x86_64.AppImage", "AppImage")
	var folder := UpdateLogic.detect("Linux", _root.path_join("detour.x86_64"), "", _root)
	_check(folder.mode == UpdateLogic.Mode.FOLDER_TAR and folder.target == _root, "Linux folder")

	var win := UpdateLogic.detect("Windows", _root.path_join("Detour.exe"), "", _root)
	_check(win.mode == UpdateLogic.Mode.FOLDER_ZIP, "writable Windows folder updates in place")
	var locked := UpdateLogic.detect("Windows", _root.path_join("missing/Detour.exe"), "", _root)
	_check(locked.mode == UpdateLogic.Mode.WINDOWS_INSTALLER and locked.staging.begins_with(_root), "read-only Windows install uses the installer")


func _replace_tree() -> void:
	var target := _dir("tree/target")
	var fresh := _dir("tree/new")
	_write(target.path_join("game.exe"), "old exe")
	_write(target.path_join("keep.txt"), "untouched")
	_write(fresh.path_join("game.exe"), "new exe")
	_write(fresh.path_join("sub/extra.dat"), "new file")
	var err := UpdateLogic.replace_tree(fresh, target, _root.path_join("tree/aside"))
	_check(err == "", "replace_tree: %s" % err)
	_check(_read(target.path_join("game.exe")) == "new exe", "file replaced")
	_check(_read(target.path_join("sub/extra.dat")) == "new file", "new file added in a subfolder")
	_check(_read(target.path_join("keep.txt")) == "untouched", "other files kept")
	_check(_read(_root.path_join("tree/aside/game.exe")) == "old exe", "old file moved aside")


func _folder_zip() -> void:
	var target := _dir("zip/install")
	_write(target.path_join("Detour.exe"), "v1")
	_write(target.path_join("rvcore.x86_64.dll"), "v1 lib")
	var archive := _root.path_join("zip/Detour-windows-x86_64.zip")
	var zip := ZIPPacker.new()
	zip.open(archive)
	for pair: Array in [["Detour.exe", "v2"], ["rvcore.x86_64.dll", "v2 lib"]]:
		zip.start_file(pair[0])
		zip.write_file((pair[1] as String).to_utf8_buffer())
		zip.close_file()
	zip.close()
	var inst := _install(UpdateLogic.Mode.FOLDER_ZIP, target, target.path_join(UpdateLogic.STAGING))
	var err := UpdateLogic.apply(inst, archive)
	_check(err == "", "zip install: %s" % err)
	_check(_read(target.path_join("Detour.exe")) == "v2" and _read(target.path_join("rvcore.x86_64.dll")) == "v2 lib", "zip contents installed")
	UpdateLogic.cleanup(inst)
	_check(not DirAccess.dir_exists_absolute(inst.staging), "zip leftovers cleaned up")


func _folder_tar() -> void:
	var target := _dir("tar/install")
	_write(target.path_join("detour.x86_64"), "v1")
	var src := _dir("tar/src/linux")
	_write(src.path_join("detour.x86_64"), "v2")
	_write(src.path_join("librvcore.x86_64.so"), "v2 lib")
	var archive := _root.path_join("tar/Detour-linux-x86_64.tar.gz")
	OS.execute("tar", ["-czf", archive, "-C", src.get_base_dir(), "linux"])
	var inst := _install(UpdateLogic.Mode.FOLDER_TAR, target, target.path_join(UpdateLogic.STAGING))
	var err := UpdateLogic.apply(inst, archive)
	_check(err == "", "tarball install: %s" % err)
	_check(_read(target.path_join("detour.x86_64")) == "v2" and _read(target.path_join("librvcore.x86_64.so")) == "v2 lib", "tarball contents installed")


func _appimage() -> void:
	var dir := _dir("appimage")
	var target := dir.path_join("Detour-x86_64.AppImage")
	_write(target, "v1")
	var inst := _install(UpdateLogic.Mode.APPIMAGE, target, dir.path_join(UpdateLogic.STAGING))
	DirAccess.make_dir_recursive_absolute(inst.staging)
	var download := inst.staging.path_join("Detour-x86_64.AppImage")
	_write(download, "v2")
	var err := UpdateLogic.apply(inst, download)
	_check(err == "", "AppImage install: %s" % err)
	_check(_read(target) == "v2", "AppImage replaced")
	_check(OS.execute("test", ["-x", target]) == 0, "AppImage is executable")


func _mac_bundle() -> void:
	var apps := _dir("mac/Applications")
	var old := apps.path_join("Detour.app")
	_write(old.path_join("Contents/MacOS/Detour"), "v1")
	var build := _dir("mac/build")
	_write(build.path_join("Detour.app/Contents/MacOS/Detour"), "v2")
	_write(build.path_join("Detour.app/Contents/Info.plist"), "plist")
	var archive := _root.path_join("mac/Detour-macos-universal.zip")
	OS.execute("ditto", ["-c", "-k", "--keepParent", build.path_join("Detour.app"), archive])
	var inst := UpdateLogic.detect("macOS", old.path_join("Contents/MacOS/Detour"), "", _root)
	DirAccess.make_dir_recursive_absolute(inst.staging)
	var err := UpdateLogic.apply(inst, archive)
	_check(err == "", "bundle install: %s" % err)
	_check(_read(old.path_join("Contents/MacOS/Detour")) == "v2", "new bundle in place")
	_check(_read(old.path_join("Contents/Info.plist")) == "plist", "whole bundle replaced")
	UpdateLogic.cleanup(inst)
	_check(not DirAccess.dir_exists_absolute(inst.staging), "old bundle cleaned up")


func _install(mode: UpdateLogic.Mode, target: String, staging: String) -> UpdateLogic.Install:
	var inst := UpdateLogic.Install.new()
	inst.mode = mode
	inst.target = target
	inst.staging = staging
	inst.launch = target
	return inst


func _dir(rel: String) -> String:
	var path := _root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path)
	return path


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
