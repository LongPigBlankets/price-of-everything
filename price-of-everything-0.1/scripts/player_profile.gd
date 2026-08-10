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


func _ready() -> void:
	_load()
	_apply_window_size()  # honour the saved resolution before the menu is shown
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
	f.store_string(JSON.stringify({"games_completed": games_completed, "tutorial_completed": tutorial_completed, "wins": wins, "window_w": window_size.x, "window_h": window_size.y, "telemetry_opt_out": telemetry_opt_out, "telemetry_player_id": telemetry_player_id}, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(tmp_path, _path())
	if err != OK:
		push_warning("[PlayerProfile] could not finalise %s (%s)" % [_path(), error_string(err)])


## Persist and apply the window resolution chosen in Settings → Graphics.
func set_window_size(size: Vector2i) -> void:
	window_size = size
	_apply_window_size()
	_save()


## Apply the saved window size to the OS window, re-centred on the current screen with
## the top-left clamped on-screen (so an ultrawide pick on a smaller display can't push
## the title bar off the top-left). No-op when headless or when nothing is saved.
func _apply_window_size() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if window_size.x <= 0 or window_size.y <= 0:
		return
	DisplayServer.window_set_size(window_size)
	var screen := DisplayServer.window_get_current_screen()
	var origin := DisplayServer.screen_get_position(screen)
	var avail := DisplayServer.screen_get_size(screen)
	var pos := origin + (avail - window_size) / 2
	pos.x = maxi(pos.x, origin.x)
	pos.y = maxi(pos.y, origin.y)
	DisplayServer.window_set_position(pos)
