extends Node
## Keeps release builds current from GitHub Releases. Nightly builds follow the `nightly`
## pre-release; tagged builds follow the latest stable release. Development builds (no CI
## stamp, see `BuildInfo`) never update.
##
## `update_now()` checks, downloads, verifies against the release's SHA256SUMS and installs
## in place (`UpdateLogic`); `restart()` then starts the new version. With auto-update on
## (the default), the same runs a few seconds after launch.

signal changed

enum State { DISABLED, IDLE, CHECKING, UP_TO_DATE, DOWNLOADING, INSTALLING, READY, FAILED }

const REPO := "j4ckxyz/detour"
const SETTINGS_PATH := "user://settings.cfg"
const AUTO_CHECK_DELAY := 3.0
const HEADERS: PackedStringArray = [
	"Accept: application/vnd.github+json",
	"User-Agent: Detour-updater",
	"X-GitHub-Api-Version: 2022-11-28",
]

var state := State.IDLE
## One line for the menu, in words for the player.
var status := ""
## Download progress 0..1, or -1 when not downloading.
var progress := -1.0
## The version being installed or ready, e.g. "nightly 1a2b3c4".
var new_version := ""
var release_page := "https://github.com/%s/releases" % REPO
## True when the finished update came from the automatic check (for the toast).
var was_automatic := false
var auto_update := true:
	set(on):
		auto_update = on
		_save_settings()

var _install: UpdateLogic.Install
var _api := HTTPRequest.new()
var _download := HTTPRequest.new()
var _download_path := ""
var _busy := false
var _apply_error := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Keep downloading while the game is paused.
	_api.timeout = 30.0
	add_child(_api)
	_download.use_threads = true
	add_child(_download)
	_load_settings()
	if not BuildInfo.can_update():
		_set_state(State.DISABLED, "Development build: updates are off.")
		return
	_install = UpdateLogic.detect(OS.get_name(), OS.get_executable_path(), OS.get_environment("APPIMAGE"),
		ProjectSettings.globalize_path("user://"))
	UpdateLogic.cleanup(_install)
	if _install.mode == UpdateLogic.Mode.UNSUPPORTED:
		_set_state(State.DISABLED, _install.problem)
		return
	_set_state(State.IDLE, "")
	if auto_update:
		get_tree().create_timer(AUTO_CHECK_DELAY, true).timeout.connect(_auto_check)


func _process(_delta: float) -> void:
	if state == State.DOWNLOADING:
		var total := _download.get_body_size()
		var now := _download.get_downloaded_bytes()
		progress = float(now) / total if total > 0 else 0.0
		status = "Downloading %s… %d%% (%d of %d MB)" % [new_version, roundi(progress * 100.0), now >> 20, maxi(total, 0) >> 20]
		changed.emit()


## What the menu's update button should say.
func button_text() -> String:
	match state:
		State.CHECKING:
			return "Checking…"
		State.DOWNLOADING:
			return "Downloading… %d%%" % roundi(maxf(progress, 0.0) * 100.0)
		State.INSTALLING:
			return "Installing…"
		State.READY:
			return "Restart to update"
	return "Update now"


func can_press() -> bool:
	return state in [State.IDLE, State.UP_TO_DATE, State.FAILED, State.READY]


## The menu's button: restart into a ready update, or check and install one.
func press() -> void:
	if state == State.READY:
		restart()
	else:
		update_now()


func update_now() -> void:
	was_automatic = false
	_run()


func restart() -> void:
	if state != State.READY:
		return
	var err := UpdateLogic.launch(_install, _download_path)
	if err < 0:
		_set_state(State.FAILED, "Couldn't start the new version. Please start Detour again.")
		return
	get_tree().quit()


func _auto_check() -> void:
	if auto_update and not _busy and state == State.IDLE:
		was_automatic = true
		_run()


func _run() -> void:
	if _busy or state in [State.DISABLED, State.READY]:
		return
	_busy = true
	await _check_and_install()
	_busy = false


func _check_and_install() -> void:
	_set_state(State.CHECKING, "Checking for updates…")
	var which := "tags/nightly" if BuildInfo.channel == "nightly" else "latest"
	var reply := await _get_text("https://api.github.com/repos/%s/releases/%s" % [REPO, which])
	if reply.is_empty():
		return
	var release: Variant = JSON.parse_string(reply)
	if not release is Dictionary:
		_set_state(State.FAILED, "GitHub sent something unexpected. Try again later.")
		return
	release_page = str(release.get("html_url", release_page))
	if not UpdateLogic.is_newer(release, BuildInfo.channel, BuildInfo.version, BuildInfo.commit, BuildInfo.date):
		_set_state(State.UP_TO_DATE, "You have the latest version.")
		return
	new_version = UpdateLogic.release_label(release)
	if _install.problem != "":
		_set_state(State.FAILED, "%s is out, but %s" % [new_version, _install.problem.to_lower()])
		return

	var asset := UpdateLogic.find_asset(release, _install.asset())
	var sums_asset := UpdateLogic.find_asset(release, UpdateLogic.SUMS_ASSET)
	if asset.is_empty() or sums_asset.is_empty():
		_set_state(State.FAILED, "%s has no download for this system yet." % new_version)
		return
	var sums_text := await _get_text(str(sums_asset["browser_download_url"]))
	if sums_text.is_empty():
		return
	var expected: String = UpdateLogic.parse_sums(sums_text).get(_install.asset(), "")
	if expected == "":
		_set_state(State.FAILED, "The release has no checksum for %s." % _install.asset())
		return

	DirAccess.make_dir_recursive_absolute(_install.staging)
	_download_path = _install.staging.path_join(_install.asset())
	_download.download_file = _download_path
	progress = 0.0
	_set_state(State.DOWNLOADING, "Downloading %s…" % new_version)
	if _download.request(str(asset["browser_download_url"]), HEADERS) != OK:
		_set_state(State.FAILED, "Couldn't start the download.")
		return
	var result: Array = await _download.request_completed
	progress = -1.0
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		_set_state(State.FAILED, "The download failed (%s). Try again later." % _describe(result))
		return

	_set_state(State.INSTALLING, "Installing %s…" % new_version)
	var task := WorkerThreadPool.add_task(_verify_and_apply.bind(expected), false, "Detour update")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	if _apply_error != "":
		_set_state(State.FAILED, _apply_error)
		return
	_set_state(State.READY, "%s is installed. Restart to play it." % new_version)


## Runs on a worker thread: hashing and unpacking a 150 MB download takes a few seconds.
func _verify_and_apply(expected: String) -> void:
	if FileAccess.get_sha256(_download_path) != expected:
		_apply_error = "The download was damaged (checksum mismatch). Try again."
		DirAccess.remove_absolute(_download_path)
		return
	_apply_error = UpdateLogic.apply(_install, _download_path)


## GETs a small text resource; on failure sets FAILED and returns "".
func _get_text(url: String) -> String:
	if _api.request(url, HEADERS) != OK:
		_set_state(State.FAILED, "Couldn't reach GitHub.")
		return ""
	var result: Array = await _api.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] != 200:
		_set_state(State.FAILED, "Couldn't check for updates (%s)." % _describe(result))
		return ""
	return (result[3] as PackedByteArray).get_string_from_utf8()


static func _describe(result: Array) -> String:
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return "no connection" if result[0] in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE] else "error %d" % result[0]
	return "HTTP %d" % result[1]


func _set_state(s: State, text: String) -> void:
	state = s
	status = text
	if text != "":
		print("[updater] ", text) # Lands in the log file, for bug reports.
	changed.emit()


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		auto_update = bool(cfg.get_value("updates", "auto", true))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH) # Keep any other sections.
	cfg.set_value("updates", "auto", auto_update)
	cfg.save(SETTINGS_PATH)
