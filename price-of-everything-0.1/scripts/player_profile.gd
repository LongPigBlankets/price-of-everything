extends Node
## Persistent player profile / meta-progression — separate from match saves. Tracks
## cross-game state like how many games the player has finished, which gates unlocks
## (e.g. the Very Hard difficulty). Stored as a small JSON at user://profile.json.
##
## A game counts as "completed" when it ends — won or reached the turn cap — which is
## exactly when TurnManager emits game_ended_signal.

const PATH := "user://profile.json"

var games_completed: int = 0
# True once the player has reached the END of the tutorial (the integration_done step),
# not merely started or skipped it. Gates the "play without the tutorial?" prompt on
# New Game.
var tutorial_completed: bool = false
# Hall of Records: every VICTORY, newest first. Losses are not recorded. Each entry:
# {"date": "YYYY-MM-DD", "title": <victory name>, "turn": int, "secured": int, "epithet": String}
var wins: Array = []


func _ready() -> void:
	_load()
	# Registered after TurnManager in [autoload], so the singleton already exists.
	if TurnManager != null and TurnManager.has_signal("game_ended_signal"):
		if not TurnManager.game_ended_signal.is_connected(_on_game_ended):
			TurnManager.game_ended_signal.connect(_on_game_ended)


func has_completed_game() -> bool:
	return games_completed > 0


func has_done_tutorial() -> bool:
	return tutorial_completed


## Mark the tutorial as finished (the Tutorial engine calls this when the player
## reaches the terminal step). Idempotent; skipped mid-tutorial does NOT count.
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


func _on_game_ended(_reason: String) -> void:
	# Don't count automated/headless runs (tests, balance harness) toward unlocks.
	if DisplayServer.get_name() == "headless":
		return
	games_completed += 1
	_save()


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		games_completed = int((parsed as Dictionary).get("games_completed", 0))
		tutorial_completed = bool((parsed as Dictionary).get("tutorial_completed", false))
		var recorded: Variant = (parsed as Dictionary).get("wins", [])
		wins = recorded if recorded is Array else []


func _save() -> void:
	# Temp-file + rename so a crash mid-write can't corrupt the profile.
	var tmp_path := PATH + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_warning("[PlayerProfile] could not write %s" % tmp_path)
		return
	f.store_string(JSON.stringify({"games_completed": games_completed, "tutorial_completed": tutorial_completed, "wins": wins}, "\t"))
	f.close()
	var err := DirAccess.rename_absolute(tmp_path, PATH)
	if err != OK:
		push_warning("[PlayerProfile] could not finalise %s (%s)" % [PATH, error_string(err)])
