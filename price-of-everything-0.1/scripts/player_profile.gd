extends Node
## Persistent player profile / meta-progression — separate from match saves. Tracks
## cross-game state like how many games the player has finished, which gates unlocks
## (e.g. the Very Hard difficulty). Stored as a small JSON at user://profile.json.
##
## A game counts as "completed" when it ends — won or reached the turn cap — which is
## exactly when TurnManager emits game_ended_signal.

const AppPaths := preload("res://scripts/app_paths.gd")

# The profile lives alongside the save slots in <base>/savegames/.
static func _path() -> String:
	return AppPaths.saves_dir().path_join("profile.json")

var games_completed: int = 0
# True once the player has reached the END of the tutorial (the integration_done step),
# not merely started or skipped it. Gates the "play without the tutorial?" prompt on
# New Game.
var tutorial_completed: bool = false
# Hall of Records: every VICTORY, newest first. Losses are not recorded. Each entry:
# {"date": "YYYY-MM-DD", "title": <victory name>, "turn": int, "secured": int, "epithet": String}
var wins: Array = []
# Display preference chosen in Settings → Graphics (persisted, applied at startup).
# Vector2i.ZERO = never set → keep the project.godot default window size.
var window_size: Vector2i = Vector2i.ZERO
# Telemetry (docs/telemetry-spec.md): remembered state of the "send metrics"
# opt-out checkbox (false = metrics on, the default) and the anonymous
# per-install player id (16 random bytes, hex — never personal information).
var telemetry_opt_out: bool = false
var telemetry_player_id: String = ""
# Display mode chosen in Settings → Graphics (persisted, applied at startup). Fullscreen
# fills the current monitor via the project's canvas_items/expand stretch; it is the only
# reliable "fill the whole screen" control, since a windowed pick smaller than the monitor
# just floats centred. Defaults on so the game fills the screen out of the box.
var fullscreen: bool = true
# Which monitor the game runs on (Settings → Graphics), for laptop-plus-external setups.
# -1 = auto (whichever screen the window opened on). Fullscreen fills that screen; windowed
# is clamped to its usable area so the window can never be taller/wider than the monitor
# (which stranded buttons off-screen for a playtester on a 1080p external display).
var screen_index: int = -1
# Audio volumes chosen in Settings → Audio (persisted, applied at startup). Bus name
# ("Master"/"Music"/"SFX") → 0–100 slider percent. Empty = never set → keep Audio's boot
# defaults (the 40 %-headroom seat).
var audio_levels: Dictionary = {}


func _ready() -> void:
	_load()
	_apply_display()        # honour the saved resolution / fullscreen before the menu is shown
	_apply_audio_levels()   # honour the saved volumes (buses exist — Audio autoloads earlier)
	# Registered after TurnManager in [autoload], so the singleton already exists.
	if TurnManager != null and TurnManager.has_signal("game_ended_signal"):
		if not TurnManager.game_ended_signal.is_connected(_on_game_ended):
			TurnManager.game_ended_signal.connect(_on_game_ended)


func has_completed_game() -> bool:
	return games_completed > 0


func has_done_tutorial() -> bool:
	return tutorial_completed


## Mark the tutorial as finished (the Tutorial engine calls this from the terminal
## End tutorial button). Idempotent; reaching the card or skipping early does NOT count.
func mark_tutorial_completed() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if tutorial_completed:
		return
	tutorial_completed = true
	_save()


func get_wins() -> Array:
	return wins


## Record a victory for the Hall of Records. Also counts the game as completed:
## a win ends the game without game_ended_signal (bottom_menu sets game_ended
## directly), so without this bump winning would never unlock the hard difficulties.
func record_win(entry: Dictionary) -> void:
	if DisplayServer.get_name() == "headless":
		return
	wins.push_front(entry)
	games_completed += 1
	_save()


## Test/debug hook: force the completed count and persist it.
func set_games_completed(n: int) -> void:
	games_completed = maxi(0, n)
	_save()


## Remember the "send metrics" checkbox so the next New Game / Tutorial screen
## defaults to the player's last choice (true = they unticked it).
func set_telemetry_opt_out(v: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if telemetry_opt_out == v:
		return
	telemetry_opt_out = v
	_save()


## Anonymous per-install telemetry id, minted on first use.
func get_telemetry_player_id() -> String:
	if telemetry_player_id == "":
		telemetry_player_id = Crypto.new().generate_random_bytes(16).hex_encode()
		if DisplayServer.get_name() != "headless":
			_save()
	return telemetry_player_id


func _on_game_ended(_reason: String) -> void:
	# Don't count automated/headless runs (tests, balance harness) toward unlocks.
	if DisplayServer.get_name() == "headless":
		return
	games_completed += 1
	_save()


## Where the profile lived BEFORE AppPaths moved the game's data next to the project/executable.
## Anything written prior to that is still sitting in the OS user-data dir, orphaned.
static func _legacy_path() -> String:
	return OS.get_user_data_dir().path_join("profile.json")


## Fold an orphaned pre-AppPaths profile into the current one. When the data folder moved, every
## victory recorded up to that point was left behind at the old path — the Hall of Records simply
## stopped showing them, which reads exactly like "it isn't recording my wins any more".
## Wins are merged by identity (date + title + turn) so running twice cannot duplicate them, and
## games_completed takes the larger count so the difficulty unlocks are not rolled back either.
func _merge_legacy() -> void:
	var old := _legacy_path()
	if old == _path() or not FileAccess.file_exists(old):
		return
	var f := FileAccess.open(old, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		return
	var seen := {}
	for w in wins:
		seen["%s|%s|%d" % [str((w as Dictionary).get("date", "")), str((w as Dictionary).get("title", "")),
			int((w as Dictionary).get("turn", 0))]] = true
	var added := 0
	for w in ((parsed as Dictionary).get("wins", []) as Array):
		var key := "%s|%s|%d" % [str((w as Dictionary).get("date", "")), str((w as Dictionary).get("title", "")),
			int((w as Dictionary).get("turn", 0))]
		if not seen.has(key):
			seen[key] = true
			wins.append(w)
			added += 1
	var legacy_games := int((parsed as Dictionary).get("games_completed", 0))
	var bumped := legacy_games > games_completed
	games_completed = maxi(games_completed, legacy_games)
	if added > 0 or bumped:
		wins.sort_custom(func(a, b): return str((a as Dictionary).get("date", "")) > str((b as Dictionary).get("date", "")))
		print("[PlayerProfile] recovered %d win(s) from the pre-move profile at %s" % [added, old])
		_save()


func _load() -> void:
	if not FileAccess.file_exists(_path()):
		_merge_legacy()
		return
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		games_completed = int((parsed as Dictionary).get("games_completed", 0))
		tutorial_completed = bool((parsed as Dictionary).get("tutorial_completed", false))
		var recorded: Variant = (parsed as Dictionary).get("wins", [])
		wins = recorded if recorded is Array else []
		window_size = Vector2i(int((parsed as Dictionary).get("window_w", 0)), int((parsed as Dictionary).get("window_h", 0)))
		fullscreen = bool((parsed as Dictionary).get("fullscreen", true))
		screen_index = int((parsed as Dictionary).get("screen_index", -1))
		var lv: Variant = (parsed as Dictionary).get("audio_levels", {})
		audio_levels = (lv as Dictionary) if lv is Dictionary else {}
		telemetry_opt_out = bool((parsed as Dictionary).get("telemetry_opt_out", false))
		telemetry_player_id = str((parsed as Dictionary).get("telemetry_player_id", ""))
	_merge_legacy()


func _save() -> void:
	# Temp-file + rename so a crash mid-write can't corrupt the profile.
	var tmp_path := _path() + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_warning("[PlayerProfile] could not write %s" % tmp_path)
		return
	f.store_string(JSON.stringify({"games_completed": games_completed, "tutorial_completed": tutorial_completed, "wins": wins, "window_w": window_size.x, "window_h": window_size.y, "fullscreen": fullscreen, "screen_index": screen_index, "audio_levels": audio_levels, "telemetry_opt_out": telemetry_opt_out, "telemetry_player_id": telemetry_player_id}, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(tmp_path, _path())
	if err != OK:
		push_warning("[PlayerProfile] could not finalise %s (%s)" % [_path(), error_string(err)])


## Persist and apply the display mode + windowed resolution + target monitor chosen in
## Settings → Graphics. `screen` is a monitor index, or -1 for auto (keep the current screen).
func set_display(is_fullscreen: bool, size: Vector2i, screen: int = -1) -> void:
	fullscreen = is_fullscreen
	if size.x > 0 and size.y > 0:
		window_size = size
	screen_index = screen
	_apply_display()
	_save()


## Back-compat shim: set just the windowed resolution, keeping the current mode + screen.
func set_window_size(size: Vector2i) -> void:
	set_display(fullscreen, size, screen_index)


## The monitor the game should use: the saved index when it still exists, else the screen the
## window is currently on (so unplugging the external display can't strand the game off-screen).
func _target_screen() -> int:
	if screen_index >= 0 and screen_index < DisplayServer.get_screen_count():
		return screen_index
	return DisplayServer.window_get_current_screen()


## Apply the saved display prefs to the OS window. Fullscreen fills the chosen monitor
## (borderless; the project's canvas_items/expand stretch scales the UI to fit) — the only
## reliable way to fill a display when the picked size differs from it. Windowed is clamped
## to that monitor's USABLE area (work area minus taskbar) and centred there, so the window
## can never be larger/taller than the screen — which had stranded buttons off the bottom on
## a 1080p external display. No-op headless.
func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target := _target_screen()
	if fullscreen:
		# Must be windowed to move between monitors; then fill the target.
		if DisplayServer.window_get_current_screen() != target:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_current_screen(target)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable := DisplayServer.screen_get_usable_rect(target)
	# Clamp the requested size to what the monitor can actually show (fall back to the
	# monitor's usable size when nothing sensible is saved).
	var want := window_size if window_size.x > 0 and window_size.y > 0 else usable.size
	var size := Vector2i(mini(want.x, usable.size.x), mini(want.y, usable.size.y))
	DisplayServer.window_set_size(size)
	var pos := usable.position + (usable.size - size) / 2
	pos.x = maxi(pos.x, usable.position.x)
	pos.y = maxi(pos.y, usable.position.y)
	DisplayServer.window_set_position(pos)


## Persist and apply the audio volumes chosen in Settings → Audio. `levels` maps bus
## name ("Master"/"Music"/"SFX") → 0–100 percent, so the player's choice survives a restart.
func set_audio_levels(levels: Dictionary) -> void:
	audio_levels = levels.duplicate()
	_apply_audio_levels()  # no-op headless; buses are live otherwise
	_save()                # a settings choice, so persist even in headless (like set_window_size)


## Re-apply the saved audio volumes to the live Audio buses (already created — Audio
## autoloads before PlayerProfile). No-op headless or when nothing is saved.
func _apply_audio_levels() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if audio_levels.is_empty() or Audio == null:
		return
	for bus: String in audio_levels:
		Audio.set_bus_percent(StringName(bus), float(audio_levels[bus]))
