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

# Per-phase human pacing delay. The whole-turn transition is this x the 5
# resolution phases, so the default 0.1 gives a ~0.5s turn (compute is a flat
# ~37ms on top) — Civ-like early-game snappiness that, thanks to the route cache,
# no longer grows with building count. Raise for a slower reveal; the per-phase
# split keeps each phase (SEND/AI/NARRATIVE/...) individually visible.
@export var phase_pause_duration: float = 0.1
# Compute-constrained mode: skip ALL pacing so turns resolve as fast as the engine
# can compute them. Set true for headless sims (no human watching) or an in-game
# "instant" speed. Overrides phase_pause_duration.
@export var fast_mode: bool = false
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
	# Deferred so every autoload exists before wiring (see _wire_sim_listeners).
	call_deferred("_wire_sim_listeners")
	if auto_start_first_turn:
		await get_tree().process_frame
		phase_started.emit(Phase.DECIDE)

## Sim systems' per-phase hooks run in the order they were CONNECTED to
## phase_started. That order used to fall out of autoload registration plus each
## system's own await/deferred connect — an implicit race where any autoload
## reorder silently changed turn semantics. TurnManager owns the wiring instead,
## so the intra-phase order is explicit:
##   PROCESS:   MatchState (survey ticks + battery fills — battery firming
##              capacity must exist before the production cascade's
##              intermittency pass) → Production (the cascade).
##   NARRATIVE: MatchState (unlock conditions over settled production)
##              → EventScheduler (narrative events) → Modifiers (prune expired)
##              → DecisionState (draw the next decision AFTER pruning, so a fresh
##                decision's modifiers can't be pruned in the same phase).
## Never reorder this list without checking those dependencies.
func _wire_sim_listeners() -> void:
	var hooks: Array = [
		Callable(MatchState, "_on_survey_phase_started"),
		Callable(Production, "_on_phase_started"),
		Callable(EventScheduler, "_on_phase_started"),
		Callable(Modifiers, "_on_phase_started"),
		Callable(DecisionState, "_on_phase_started"),
	]
	for hook: Callable in hooks:
		if not phase_started.is_connected(hook):
			phase_started.connect(hook)

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
	# A pending decision must be answered before the turn commits (the modal has no
	# dismiss; this is the belt-and-braces guard behind it). Non-interactive runs
	# resolve the default instead of blocking.
	if DecisionState.has_pending():
		if DecisionState.auto_resolve:
			DecisionState.auto_resolve_pending()
		else:
			return
	_run_resolution()

# --- Save/load (orchestrated by the SaveLoad autoload; docs/save_load_spec.md) ---

func export_state() -> Dictionary:
	return {"current_turn": current_turn, "game_ended": game_ended}

func import_state(d: Dictionary) -> void:
	# Saving is only allowed in DECIDE, so a load always lands back in DECIDE.
	current_turn = int(d.get("current_turn", 1))
	game_ended = bool(d.get("game_ended", false))
	current_phase = Phase.DECIDE
	is_resolving = false

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
		# Artificial inter-phase pacing for the human. Skipped entirely in fast_mode
		# (or when the pause is zero), leaving only the one process_frame yield above
		# so the turn is bounded purely by compute.
		if not fast_mode and phase_pause_duration > 0.0:
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
