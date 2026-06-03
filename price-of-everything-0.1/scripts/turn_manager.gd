extends Node

# Autoload singleton: drives turn-based game flow.
# Player lives in DECIDE; commit_turn() runs PROCESS -> SEND -> AI -> NARRATIVE -> RECEIVE,
# increments the turn counter, then re-enters DECIDE.

enum Phase { DECIDE, PROCESS, SEND, AI, NARRATIVE, RECEIVE }

# Last playable turn. The player gets MAX_TURNS decision phases (turns 1..MAX_TURNS).
# After committing the final turn, current_turn ticks to MAX_TURNS + 1 and the game
# soft-ends: DECIDE still fires so UI can show victory/defeat overlays, but
# commit_turn() becomes a no-op. Edit this constant to lengthen or shorten the game.
const MAX_TURNS := 300

const _RESOLUTION_PHASES: Array = [
	Phase.PROCESS,
	Phase.SEND,
	Phase.AI,
	Phase.NARRATIVE,
	Phase.RECEIVE,
]

signal turn_resolution_started
signal turn_resolution_completed
signal phase_started(phase: int)
signal phase_completed(phase: int)
signal turn_advanced(new_turn: int)
signal game_ended_signal(reason: String)

@export var phase_pause_duration: float = 0.5
@export var auto_start_first_turn: bool = true

var current_turn: int = 1
var current_phase: int = Phase.DECIDE
var is_resolving: bool = false
var game_ended: bool = false

func _ready() -> void:
	current_turn = 1
	current_phase = Phase.DECIDE
	is_resolving = false
	game_ended = false
	if auto_start_first_turn:
		await get_tree().process_frame
		phase_started.emit(Phase.DECIDE)

func get_phase_name(phase: int) -> String:
	match phase:
		Phase.DECIDE: return "Decide"
		Phase.PROCESS: return "Process"
		Phase.SEND: return "Send"
		Phase.AI: return "AI"
		Phase.NARRATIVE: return "Narrative"
		Phase.RECEIVE: return "Receive"
		_: return ""

func commit_turn() -> void:
	if is_resolving or game_ended:
		return
	if current_phase != Phase.DECIDE:
		return
	_run_resolution()

# Test hook: reset to a clean DECIDE state on turn 1 without re-emitting startup signals.
func reset_for_test() -> void:
	current_turn = 1
	current_phase = Phase.DECIDE
	is_resolving = false
	game_ended = false

func _run_resolution() -> void:
	is_resolving = true
	turn_resolution_started.emit()

	# Profiler: which turn this resolution belongs to (current_turn ticks up below).
	var profiled_turn: int = current_turn

	for phase in _RESOLUTION_PHASES:
		current_phase = phase
		# Time only the synchronous work of the phase: the listener bodies run
		# inside phase_started.emit() (no awaits). The create_timer pause that
		# follows is the artificial inter-phase delay we want to measure AGAINST,
		# so it is deliberately excluded from the bracket.
		TurnProfiler.phase_begin(phase)
		phase_started.emit(phase)
		TurnProfiler.phase_end(phase)
		await get_tree().process_frame
		phase_completed.emit(phase)
		await get_tree().create_timer(phase_pause_duration).timeout

	# Flush this turn's profile (per-phase + PROCESS sub-step durations + scale).
	TurnProfiler.finalize_turn(profiled_turn)

	current_turn += 1
	if current_turn > MAX_TURNS:
		game_ended = true
		game_ended_signal.emit("turn_cap_reached")

	turn_advanced.emit(current_turn)
	current_phase = Phase.DECIDE
	phase_started.emit(Phase.DECIDE)
	is_resolving = false
	turn_resolution_completed.emit()
