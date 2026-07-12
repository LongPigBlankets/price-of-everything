extends Node
## SessionLog — captures verbose turn logs to a timestamped .txt in the savegame
## folder. Armed on the FIRST End Turn of turn 1 (see world_map._on_end_turn_pressed),
## which also flips MatchState.debug_turn_logs_enabled so the scattered verbose
## print()s in production.gd / cost_solver.gd start flowing. A custom Logger tees
## Godot's stdout into an in-memory buffer while capturing; the buffer is written
## out on game close (window X or "Exit to Desktop"). Debug/UI only — no sim, save,
## or determinism impact (never calls randi/randf; the flag is session-only and
## never serialized). No-op under --headless so unit/e2e runs write no stray files.

const SAVE_DIR := "user://saves"  # mirrors SaveLoad.SAVE_DIR; hardcoded so flush()
                                  # is robust to autoload teardown ordering.

var armed := false
var _flushed := false
var _tee: TeeLogger


## Tees every Godot log message into its own buffer while `capturing`. Kept inside
## the logger (not the autoload) so append() mutates the array in place, sidestepping
## PackedArray copy-on-write surprises.
class TeeLogger extends Logger:
	var capturing := false
	var buffer := PackedStringArray()

	func _log_message(message: String, _error: bool) -> void:
		if capturing:
			buffer.append(message)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if capturing:
			buffer.append("[diag:%d] %s (%s:%d) %s\n" % [error_type, code, file, line, rationale])


func _ready() -> void:
	# Register the tee up front; appends are gated on `capturing`, so boot/build
	# spam is never buffered — only turn-1-onward verbose output lands in the file.
	if _is_headless():
		return
	_tee = TeeLogger.new()
	OS.add_logger(_tee)


## Turn on capture (idempotent). Called on the first End Turn of turn 1.
func arm() -> void:
	if armed or _is_headless() or _tee == null:
		return
	armed = true
	MatchState.debug_turn_logs_enabled = true
	_tee.buffer.append("=== Carbon and Capital session log — armed %s ===\n"
		% Time.get_datetime_string_from_system())
	_tee.capturing = true


## Write the captured buffer to <SAVE_DIR>/session_log_<timestamp>.txt. Idempotent
## across the two close paths (WM_CLOSE_REQUEST from the window X, and _exit_tree /
## "Exit to Desktop" which calls get_tree().quit()).
func flush() -> void:
	if _flushed or not armed or _tee == null or _tee.buffer.is_empty():
		return
	_flushed = true
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/session_log_%s.txt" % [SAVE_DIR, stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("SessionLog: could not open %s for writing" % path)
		return
	f.store_string("".join(_tee.buffer))
	f.close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func _exit_tree() -> void:
	flush()


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"
