extends Node
# Autoload. Single source of truth for map-overlay (mapmode) selection state.

enum Mode {
	NONE,
	TILES_PRODUCING,
	TILES_CONSUMING,
	DEPOSITS,
	WATER,
	POWER_BALANCE,
	LOGISTICS,
	SURVEYING,
	INFRASTRUCTURE,
}

const POWER_SENTINEL := "power_balance_sentinel"
const LOGISTICS_SENTINEL := "logistics_sentinel"
const SURVEYING_SENTINEL := "surveying_sentinel"
const DEPOSITS_SENTINEL := "deposits_sentinel"
const WATER_SENTINEL := "water_sentinel"
const INFRASTRUCTURE_SENTINEL := "infrastructure_sentinel"

# Per-good modes (Producing / Consuming): the player ticks up to MAX_SELECTIONS
# goods, each shown on the map with its own icon (clustered when a tile has more
# than one). The colour cycles through PALETTE.
const PALETTE: Array[Color] = [Color.RED, Color.BLUE, Color.YELLOW, Color.HOT_PINK]
const MAX_SELECTIONS := 6

# Modes driven by a single sentinel selection (whole-map overlays, no good picker).
const SENTINEL_MODES: Array = [
	Mode.DEPOSITS, Mode.WATER, Mode.POWER_BALANCE, Mode.LOGISTICS, Mode.SURVEYING,
	Mode.INFRASTRUCTURE,
]

var current_mode: Mode = Mode.NONE
var selections: Array = []  # [{good_id: String, color: Color}, ...]
# Infrastructure mapmode: the single infrastructure type being shown on the map
# ("" = none picked yet). Set from the Infrastructure panel's radio buttons.
var infrastructure_selection: String = ""
# Deposits the player has un-ticked in the Deposits panel (good_id -> true); the
# deposits mapmode hides these. Empty = show all (the default).
var deposit_hidden: Dictionary = {}

signal selections_changed(mode: Mode, selections: Array)
signal mode_cleared()
## A deposit good's visibility was toggled in the Deposits panel.
signal deposit_filter_changed()
## The Infrastructure panel's single-pick changed (including back to "").
signal infrastructure_selection_changed()

func add_selection(mode: Mode, good_id: String) -> bool:
	# Reject if a different mode is already locked
	if current_mode != Mode.NONE and current_mode != mode:
		return false
	# Reject if already selected (use toggle_selection to flip)
	for s in selections:
		if s.good_id == good_id:
			return false
	# Reject if cap reached
	if selections.size() >= MAX_SELECTIONS:
		return false

	var slot := selections.size()
	selections.append({"good_id": good_id, "color": PALETTE[slot % PALETTE.size()]})
	if current_mode == Mode.NONE:
		current_mode = mode
	selections_changed.emit(current_mode, selections)
	return true

# Remove a single good from the active selection. Clears the mode entirely when
# the last selection is removed.
func remove_selection(good_id: String) -> void:
	var removed := false
	for i in range(selections.size() - 1, -1, -1):
		if selections[i].good_id == good_id:
			selections.remove_at(i)
			removed = true
	if not removed:
		return
	if selections.is_empty():
		clear_all()
		return
	# Re-assign palette colours so they stay slot-stable after a removal.
	for i in selections.size():
		selections[i].color = PALETTE[i % PALETTE.size()]
	selections_changed.emit(current_mode, selections)

# Toggle a good for a per-good mode: add if absent (switching modes if needed),
# remove if present. Returns true when the good ends up selected.
func toggle_selection(mode: Mode, good_id: String) -> bool:
	if current_mode == mode and is_selected(good_id):
		remove_selection(good_id)
		return false
	# Switching from another mode clears the previous selection set.
	if current_mode != Mode.NONE and current_mode != mode:
		clear_all()
	return add_selection(mode, good_id)

# Activate a whole-map sentinel mode (Deposits / Power / Logistics / Surveying).
# Toggles off when the same mode is already active. Returns true when activated.
func set_sentinel_mode(mode: Mode, sentinel: String) -> bool:
	if current_mode == mode:
		clear_all()
		return false
	clear_all()
	return add_selection(mode, sentinel)

# Pick the single infrastructure type the Infrastructure mapmode shows;
# re-picking the current one deselects it (back to backdrop only).
func set_infrastructure_selection(infra_key: String) -> void:
	if current_mode != Mode.INFRASTRUCTURE:
		return
	infrastructure_selection = "" if infrastructure_selection == infra_key else infra_key
	infrastructure_selection_changed.emit()

func clear_all() -> void:
	if current_mode == Mode.NONE and selections.is_empty():
		return
	selections.clear()
	infrastructure_selection = ""
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

# ── Deposits visibility filter (driven by the Deposits panel tickboxes) ───────
func set_deposit_hidden(good_id: String, hidden: bool) -> void:
	if good_id == "":
		return
	if hidden:
		deposit_hidden[good_id] = true
	else:
		deposit_hidden.erase(good_id)
	deposit_filter_changed.emit()

func is_deposit_hidden(good_id: String) -> bool:
	return deposit_hidden.has(good_id)

# Hide every listed deposit good in one shot (the Deposits panel's "Clear all"),
# emitting the filter-changed signal a single time.
func hide_all_deposits(good_ids: Array) -> void:
	for gid in good_ids:
		if str(gid) != "":
			deposit_hidden[str(gid)] = true
	deposit_filter_changed.emit()
