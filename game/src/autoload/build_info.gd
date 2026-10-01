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


## What a client tells the host it runs: the version, plus the commit when stamped
## (e.g. "0.2.1+905aa57..."). The nightly and the stable release of one commit carry
## different versions but are the same game, so the handshake goes by commit.
static func handshake() -> String:
	load_stamp()
	return version if commit == "" else "%s+%s" % [version, commit]


## Whether a client that sent `theirs` (see `handshake`) runs the same game as a host on
## `host_version` at `host_commit`. Same commit: yes, whatever the channels call it.
## Otherwise (or with an unstamped side) the versions have to match.
static func same_game(host_version: String, host_commit: String, theirs: String) -> bool:
	var plus := theirs.find("+")
	var their_version := theirs if plus < 0 else theirs.left(plus)
	var their_commit := "" if plus < 0 else theirs.substr(plus + 1)
	if host_commit != "" and their_commit != "":
		return host_commit == their_commit
	return their_version == host_version


## The version part of a `handshake` string, for messages.
static func handshake_version(theirs: String) -> String:
	var plus := theirs.find("+")
	return theirs if plus < 0 else theirs.left(plus)
