extends Node
## Tutorial "Coach" engine (autoload `Tutorial`): the opening steps every new game plays before the missions
## take over (TutorialSteps.opener_steps). Inert until world_map starts it, so it costs nothing otherwise. It
## rides existing signals for step detection (a signal or the poll only WAKES a check; live state DECIDES it
## via tutorial_detectors) and drives the coach overlay.
##
## Registered AFTER MatchState/BuildMode/MapMode/TurnManager so their signals exist at
## _ready. Cross-references use preload (no class_name) for headless.

const CoachOverlayScript := preload("res://scripts/tutorial/coach_overlay.gd")
const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")
const TutorialDetectors := preload("res://scripts/tutorial/tutorial_detectors.gd")

const POLL_INTERVAL := 0.25   # s; re-evaluates the active step's decide predicate

signal step_changed(id: String)
## The opening steps of a new game finished or were skipped: the missions take over.
signal opener_finished

var active: bool = false
## True while the opening steps run.
var opener := false
var hard_gate: bool = false  # true while a lock_panel step is up: Esc is swallowed (world_map)
var _steps: Array = []
var _index: int = -1
var _entry_turn: int = 0     # turn number when the current step was entered (for turn-gated beats)
var _overlay: Control = null
var _poll: Timer = null
var _wired: bool = false
var _visited := 0            # countable steps entered, for the "Step N" number


# ── Lifecycle ──────────────────────────────────────────────────────────────────────

## Every fresh new game opens with the opening steps, then hands over to the missions. Nothing in the
## match changes. Once per match (ruleset.opener_done, saved), never twice.
func start_opener() -> void:
	if active or not is_inside_tree() or bool(MatchState.ruleset.get("opener_done", false)):
		return
	var wm := get_tree().current_scene
	if wm == null or wm.get("build_complete") != true:
		return
	_teardown_overlay()
	_steps = TutorialSteps.opener_steps()
	if _steps.is_empty():
		return
	opener = true
	active = true
	_index = -1
	_visited = 0
	MiniQuest.quest_changed.emit()   # the missions stand aside until the opener ends
	_ensure_overlay()
	_wire_signals()
	_ensure_poll()
	_enter(0)


func _enter(i: int) -> void:
	_index = i
	if _index < 0 or _index >= _steps.size():
		_finish()
		return
	_entry_turn = TurnManager.current_turn
	var step: Dictionary = _steps[_index]
	step_changed.emit(str(step.get("id", "")))
	hard_gate = bool(step.get("lock_panel", false))   # swallow Esc while this step's panel is up
	_run_setup(step.get("setup", []))
	if bool(step.get("count_step", true)):
		_visited += 1
	if _overlay != null:
		_overlay.show_step(step, maxi(0, _visited - 1), _visited + _remaining_after(_index))
	# A step whose event already fired before entry should still complete.
	call_deferred("_maybe_advance")


func _advance() -> void:
	_enter(_index + 1)


## Countable steps still to come after `i`.
func _remaining_after(i: int) -> int:
	var n := 0
	for j in range(i + 1, _steps.size()):
		if bool((_steps[j] as Dictionary).get("count_step", true)):
			n += 1
	return n


func _index_of_id(id: String) -> int:
	for i in _steps.size():
		if str((_steps[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func _finish() -> void:
	active = false
	hard_gate = false
	_index = -1
	step_changed.emit("")
	if _poll != null:
		_poll.stop()
	_teardown_overlay()
	if opener:
		opener = false
		MatchState.ruleset["opener_done"] = true
		MiniQuest.quest_changed.emit()
		opener_finished.emit()


# ── Setup dispatch ──────────────────────────────────────────────────────────────────

func _run_setup(actions: Array) -> void:
	for a in actions:
		if not (a is Dictionary):
			continue
		match str(a.get("action", "")):
			"close_tile_panel":
				var tile_panel := _find("TileInfoPanel")
				if tile_panel != null and tile_panel is Control:
					(tile_panel as Control).hide()
			_:
				pass


## Find a named node anywhere in the live scene (nil if absent).
func _find(node_name: String) -> Node:
	var scene := get_tree().current_scene
	return scene.find_child(node_name, true, false) if scene != null else null


# ── Detection (wake + state-verified poll) ───────────────────────────────────────────

func _wire_signals() -> void:
	if _wired:
		return
	_wired = true   # persists across runs; every wake signal just re-evaluates the step
	var wake := func(_a = null, _b = null, _c = null, _d = null, _e = null) -> void: _maybe_advance()
	TurnManager.turn_advanced.connect(wake)
	Production.turn_processed.connect(wake)


func _ensure_poll() -> void:
	if _poll == null:
		_poll = Timer.new()
		_poll.wait_time = POLL_INTERVAL
		_poll.timeout.connect(_maybe_advance)
		add_child(_poll)
	_poll.start()


func _maybe_advance() -> void:
	if not active or _index < 0 or _index >= _steps.size():
		return
	var step: Dictionary = _steps[_index]
	var decide: Dictionary = (step.get("done", {}) as Dictionary).get("decide", {})
	# Evaluate completion first (info steps have no decide and advance via Next).
	if not decide.is_empty():
		var done := false
		if str(decide.get("kind", "")) == "turn_advanced":
			done = TurnManager.current_turn > _entry_turn   # needs engine state
		else:
			done = TutorialDetectors.poll(decide)
		if done:
			_advance()
			return
	# Not yet done: a locked step keeps its panel open (re-opens it if the player
	# closed it — the mouse is already blocked outside the spotlight, Esc is swallowed).
	if bool(step.get("lock_panel", false)):
		_ensure_locked_panel_open(step)


func _ensure_locked_panel_open(step: Dictionary) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var kind := str((step.get("spotlight", {}) as Dictionary).get("kind", "none"))
	if kind != "node_path" and kind != "node_name":
		return   # only panel/card spotlights are "keep open"
	if _overlay.spotlight_ok():
		return
	_run_setup(step.get("setup", []))     # re-open the panel
	# refresh_spotlight, NOT show_step: show_step rebuilds the card, so this would destroy the
	# Next button the player was clicking on every 0.25s poll.
	_overlay.refresh_spotlight()


# ── Overlay plumbing ─────────────────────────────────────────────────────────────────

func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = CoachOverlayScript.new()
	_overlay.name = "CoachOverlay"
	_overlay.advanced.connect(_on_overlay_advanced)
	_overlay.skipped.connect(_on_overlay_skipped)
	var host := _overlay_host()
	if host != null:
		host.add_child(_overlay)


func _overlay_host() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var ui := scene.get_node_or_null("UILayer")
	return ui if ui != null else scene


func _teardown_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


func _on_overlay_advanced() -> void:
	# Next pressed on an info card.
	if active and _index >= 0 and _index < _steps.size():
		_advance()


func _on_overlay_skipped() -> void:
	_finish()


## True while the opener runs and has not reached the step that hands over End Turn.
func end_turn_locked() -> bool:
	if not active or not opener:
		return false
	var at := _index_of_id(TutorialSteps.OPENER_END_TURN_STEP)
	return at < 0 or _index < at


func is_active_step(id: String) -> bool:
	return active and _index >= 0 and _index < _steps.size() \
		and str((_steps[_index] as Dictionary).get("id", "")) == id


## How many countable steps the player has entered this run (the "Step N" display number).
func steps_visited() -> int:
	return _visited
