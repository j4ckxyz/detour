class_name MainMenu
extends Control
## The title screen: your name and colour, your saved trips (carry on, host, start again or
## delete), then play solo (a new trip, or a seed: a seed code or any word or phrase, like
## Minecraft's), host a game (on this network / direct
## IP, or through a relay with a room code), or join one (LAN games are listed; or type an
## address or a room code).
##
## Launching with `-- --seed=CODE` (or `--play`) skips it and goes straight into a solo trip.

const PLAYGROUND := "res://src/game/playground.tscn"
const TEXT := Color(0.96, 0.93, 0.86)
const DIM := Color(0.96, 0.93, 0.86, 0.6)
const ACCENT := Color(0.95, 0.62, 0.25)
const TRIP_LENGTHS: Array[String] = ["Short trip", "Medium trip", "Long trip"]
## How many saved trips the menu lists.
const TRIPS_SHOWN := 8

var _name := LineEdit.new()
var _colors := HBoxContainer.new()
var _seed := LineEdit.new()
## Under the seed box: the seed code the text makes.
var _seed_note := Label.new()
var _length := OptionButton.new()
var _play := Button.new()
var _host_mode := OptionButton.new()
var _relay := LineEdit.new()
var _join_to := LineEdit.new()
var _lan := VBoxContainer.new()
var _trips := VBoxContainer.new()
var _status := Label.new()
var _busy := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed") or arg == "--play" or arg == "--new":
			get_tree().change_scene_to_file.call_deferred(PLAYGROUND)
			return
	Session.leave()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	Session.joined.connect(_on_joined)
	Session.failed.connect(_on_failed)
	Session.lan_games_changed.connect(_refresh_lan)
	Session.listen_lan()
	_refresh_play()
	if Session.last_message != "":
		_status.text = Session.last_message
		Session.last_message = ""


func _exit_tree() -> void:
	Session.stop_listening()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.16, 0.14)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PauseMenu._style(24))
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := _label("Detour", 44, TEXT)
	box.add_child(title)
	box.add_child(_label("A co-op RV road trip · %s" % BuildInfo.describe(), 14, DIM))

	box.add_child(_heading("You"))
	var you := HBoxContainer.new()
	you.add_theme_constant_override("separation", 8)
	_name.text = Session.player_name
	_name.max_length = 24
	_name.placeholder_text = "Your name"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.text_changed.connect(func(t: String) -> void: Session.player_name = t.strip_edges() if t.strip_edges() != "" else "Traveller")
	you.add_child(_name)
	you.add_child(_colors)
	box.add_child(you)
	_build_colors()

	_trips.add_theme_constant_override("separation", 6)
	box.add_child(_trips)
	_refresh_trips()

	box.add_child(_heading("Play solo"))
	var solo := HBoxContainer.new()
	solo.add_theme_constant_override("separation", 8)
	_seed.placeholder_text = "Seed: any word, or a code (blank: a new trip)"
	_seed.max_length = WorldGen.text_seed_max()
	_seed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed.text_changed.connect(func(_t: String) -> void: _refresh_play())
	_seed.text_submitted.connect(func(_t: String) -> void: _on_play())
	solo.add_child(_seed)
	for i: int in TRIP_LENGTHS.size():
		_length.add_item(TRIP_LENGTHS[i], i)
	_length.item_selected.connect(func(_i: int) -> void: _refresh_play())
	solo.add_child(_length)
	box.add_child(solo)
	_seed_note.add_theme_font_size_override("font_size", 13)
	_seed_note.add_theme_color_override("font_color", DIM)
	box.add_child(_seed_note)
	_play.pressed.connect(_on_play)
	box.add_child(_button(_play))

	box.add_child(_heading("Host a game"))
	var host := HBoxContainer.new()
	host.add_theme_constant_override("separation", 8)
	_host_mode.add_item("On this network / direct IP (port %d)" % Session.DEFAULT_PORT, 0)
	_host_mode.add_item("Through a relay server", 1)
	_host_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_mode.item_selected.connect(func(_i: int) -> void: _relay.visible = _host_mode.selected == 1)
	host.add_child(_host_mode)
	var host_button := Button.new()
	host_button.text = "Host"
	host_button.pressed.connect(_on_host)
	host.add_child(_button(host_button))
	box.add_child(host)
	_relay.placeholder_text = "Relay server address (e.g. relay.example.org)"
	_relay.text = Session.relay_address
	_relay.visible = false
	_relay.text_changed.connect(func(t: String) -> void: Session.relay_address = t.strip_edges())
	box.add_child(_relay)
	box.add_child(_label("Hosting uses the solo seed above (blank: a new trip). Friends join with your IP or the room code.", 13, DIM))

	box.add_child(_heading("Join a game"))
	box.add_child(_lan)
	var join := HBoxContainer.new()
	join.add_theme_constant_override("separation", 8)
	_join_to.placeholder_text = "Host IP (192.168.1.20) or room code"
	_join_to.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_join_to.text_submitted.connect(func(_t: String) -> void: _on_join())
	join.add_child(_join_to)
	var join_button := Button.new()
	join_button.text = "Join"
	join_button.pressed.connect(_on_join)
	join.add_child(_button(join_button))
	box.add_child(join)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", ACCENT)
	box.add_child(_status)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func() -> void: get_tree().quit())
	box.add_child(_button(quit))
	_refresh_lan()


func _build_colors() -> void:
	for c: Node in _colors.get_children():
		c.queue_free()
	for i: int in 6:
		var b := Button.new()
		b.custom_minimum_size = Vector2(28, 28)
		var style := StyleBoxFlat.new()
		style.bg_color = Session.COLORS[i]
		style.set_corner_radius_all(14)
		style.set_border_width_all(3 if i == Session.player_color else 0)
		style.border_color = TEXT
		for state: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, style)
		b.tooltip_text = "Jacket colour"
		b.pressed.connect(func() -> void:
			Session.player_color = i
			_build_colors())
		_colors.add_child(b)


static func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func _heading(text: String) -> Label:
	var l := _label(text, 18, ACCENT)
	return l


static func _button(b: Button) -> Button:
	b.custom_minimum_size = Vector2(110, 38)
	b.add_theme_font_size_override("font_size", 16)
	return b


## What the seed box makes: {code, error}; a blank box makes no code.
func _typed() -> Dictionary:
	return WorldGen.code_from_text(_seed.text, _length.selected)


## The seed to play: the one typed (a code, or any text turned into one), or a new one.
func _chosen_seed() -> String:
	var code: String = _typed()["code"]
	return code if code != "" else WorldGen.random_code(_length.selected)


func _refresh_play() -> void:
	var typed := _typed()
	var code: String = typed["code"]
	if typed["error"] != "":
		_play.text = "Start trip"
		_seed_note.text = ""
		_status.text = typed["error"]
		return
	_status.text = ""
	if code == "":
		_play.text = "Start a new trip"
		_seed_note.text = ""
		return
	var entered := _seed.text.strip_edges().to_upper().replace(" ", "-")
	_seed_note.text = "" if entered == code else "Seed code %s" % code
	_play.text = "Continue this trip" if Saves.can_continue(Saves.read(code)) else "Start this trip"


func _check_seed() -> bool:
	var error: String = _typed()["error"]
	if error != "":
		_status.text = error
		return false
	return true


func _on_play() -> void:
	if _check_seed():
		_play_code(_chosen_seed())


func _on_host() -> void:
	if _busy or not _check_seed():
		return
	Session.save_settings()
	Session.seed_code = _chosen_seed()
	var err: Error
	if _host_mode.selected == 1:
		if Session.relay_address == "":
			_status.text = "Type the relay server's address first."
			return
		var at := _split_address(Session.relay_address, RelayMultiplayerPeer.DEFAULT_PORT)
		err = Session.host_relay(at[0], at[1])
	else:
		err = Session.host_direct()
	if err != OK:
		_status.text = "Couldn't host: %s" % error_string(err)
		return
	get_tree().change_scene_to_file(PLAYGROUND)


func _on_join(address: String = "", port: int = 0) -> void:
	if _busy:
		return
	Session.save_settings()
	var to := address if address != "" else _join_to.text.strip_edges()
	if to == "":
		_status.text = "Type the host's address or a room code."
		return
	var err: Error
	if address == "" and _looks_like_code(to):
		if Session.relay_address == "":
			_status.text = "That looks like a room code: set the relay server under Host a game first."
			_host_mode.select(1)
			_relay.visible = true
			return
		var at := _split_address(Session.relay_address, RelayMultiplayerPeer.DEFAULT_PORT)
		err = Session.join_relay(at[0], to, at[1])
	else:
		var at := _split_address(to, port if port > 0 else Session.DEFAULT_PORT)
		err = Session.join_direct(at[0], at[1])
	if err != OK:
		_status.text = "Couldn't connect: %s" % error_string(err)
		return
	_busy = true
	_status.text = "Connecting..."


static func _looks_like_code(text: String) -> bool:
	return text.length() == 6 and not text.contains(".") and not text.contains(":")


static func _split_address(text: String, default_port: int) -> Array:
	var i := text.rfind(":")
	if i > 0 and text.substr(i + 1).is_valid_int():
		return [text.substr(0, i), int(text.substr(i + 1))]
	return [text, default_port]


func _on_joined() -> void:
	_status.text = "Joined! Loading the trip..."
	get_tree().change_scene_to_file(PLAYGROUND)


func _on_failed(message: String) -> void:
	_busy = false
	_status.text = message


## Saved trips, most recent first: carry on (solo or hosting), start a finished one again, or
## delete one (press twice).
func _refresh_trips() -> void:
	for c: Node in _trips.get_children():
		c.queue_free()
	var saves := Saves.list()
	if saves.is_empty():
		return
	_trips.add_child(_heading("Your trips"))
	for d: Dictionary in saves.slice(0, TRIPS_SHOWN):
		var code: String = d["code"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(code, 16, TEXT))
		info.add_child(_label(Saves.describe(d), 13, DIM))
		row.add_child(info)
		if Saves.is_current(d):
			var go := Button.new()
			go.text = "Continue" if Saves.can_continue(d) else "Again"
			go.tooltip_text = "Play it solo" if Saves.can_continue(d) else "Start this trip over"
			go.pressed.connect(func() -> void: _play_code(code))
			row.add_child(_button(go))
			var host := Button.new()
			host.text = "Host"
			host.tooltip_text = "Carry on together (set how to host below)"
			host.pressed.connect(func() -> void:
				_seed.text = code
				_on_host())
			row.add_child(_button(host))
		var del := Button.new()
		del.text = "Delete"
		del.pressed.connect(func() -> void:
			if del.text != "Sure?":
				del.text = "Sure?"
				return
			Saves.delete(code)
			_refresh_trips()
			_refresh_play())
		row.add_child(_button(del))
		_trips.add_child(row)


func _play_code(code: String) -> void:
	Session.leave()
	Session.seed_code = code
	Session.save_settings()
	get_tree().change_scene_to_file(PLAYGROUND)


func _refresh_lan() -> void:
	for c: Node in _lan.get_children():
		c.queue_free()
	if Session.lan_games.is_empty():
		_lan.add_child(_label("No games found on this network yet.", 13, DIM))
		return
	for key: String in Session.lan_games:
		var g: Dictionary = Session.lan_games[key]
		var b := Button.new()
		b.text = "Join %s's game (%d/%d players)  ·  %s" % [g["name"], g["players"], Session.MAX_PLAYERS, key]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: _on_join(String(g["address"]), int(g["port"])))
		_lan.add_child(b)
