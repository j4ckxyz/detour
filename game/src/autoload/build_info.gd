class_name BuildInfo
extends RefCounted
## What this build is, as stamped by CI into `res://build_info.cfg`
## (`tools/ci/write_build_info.sh`). Runs from the editor or a source checkout have no stamp:
## they are development builds and never update themselves.

const PATH := "res://build_info.cfg"

## "nightly", "stable", or "dev".
static var channel := "dev"
static var version := ""
static var commit := ""
## UTC build time, ISO 8601 (e.g. 2026-09-28T16:51:02Z).
static var date := ""

static var _loaded := false


static func load_stamp() -> void:
	if _loaded:
		return
	_loaded = true
	version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	channel = str(cfg.get_value("build", "channel", "dev"))
	version = str(cfg.get_value("build", "version", version))
	commit = str(cfg.get_value("build", "commit", ""))
	date = str(cfg.get_value("build", "date", ""))


## True for builds that came from a GitHub release and can update themselves. Never when
## running from the editor or a checkout: the "install" there is the Godot editor itself.
static func can_update() -> bool:
	load_stamp()
	return OS.has_feature("template") and channel in ["nightly", "stable"] and commit != ""


## e.g. "0.0.1-nightly.12 (64ebf5b)" or "0.0.1 (development build)".
static func describe() -> String:
	load_stamp()
	if commit == "":
		return "%s (development build)" % version
	return "%s (%s)" % [version, commit.left(7)]
