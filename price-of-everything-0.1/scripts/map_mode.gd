extends Node
# Autoload. Single source of truth for resource overlay selection state.

enum Mode {
	NONE,
	POTENTIALS,
	TILES_PRODUCING,
	TILES_CONSUMING,
	POWER_BALANCE,
}

const POWER_SENTINEL := "power_balance_sentinel"

const PALETTE: Array[Color] = [Color.RED, Color.BLUE, Color.YELLOW, Color.HOT_PINK]
const MAX_SELECTIONS := 4

var current_mode: Mode = Mode.NONE
var selections: Array = []  # [{good_id: String, color: Color}, ...]

signal selections_changed(mode: Mode, selections: Array)
signal mode_cleared()

func add_selection(mode: Mode, good_id: String) -> bool:
	# Reject if a different mode is already locked
	if current_mode != Mode.NONE and current_mode != mode:
		return false
	# Reject if already selected (no toggle in MVP)
	for s in selections:
		if s.good_id == good_id:
			return false
	# Reject if cap reached
	if selections.size() >= MAX_SELECTIONS:
		return false
	
	var slot := selections.size()
	selections.append({"good_id": good_id, "color": PALETTE[slot]})
	if current_mode == Mode.NONE:
		current_mode = mode
	selections_changed.emit(current_mode, selections)
	return true

func clear_all() -> void:
	if current_mode == Mode.NONE and selections.is_empty():
		return
	selections.clear()
	current_mode = Mode.NONE
	mode_cleared.emit()

func can_select_in_mode(mode: Mode) -> bool:
	# Used for greying out: can we add anything to this mode right now?
	if selections.size() >= MAX_SELECTIONS:
		return false
	if current_mode != Mode.NONE and current_mode != mode:
		return false
	return true

func is_selected(good_id: String) -> bool:
	for s in selections:
		if s.good_id == good_id:
			return true
	return false

func is_active() -> bool:
	return current_mode != Mode.NONE

func exit_mode() -> void:
	clear_all()
