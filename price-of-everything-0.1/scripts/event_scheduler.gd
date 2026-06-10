extends Node
##
## Centralised event ledger. One place owns:
##   - immediate events (existing signals route here as a translator layer),
##   - turn-scheduled events with optional forewarning (politics, carbon tax,
##     the Era-1 AI competitor's turn 80/95 beats),
##   - condition-watched events (predicate becomes true → fire once),
##   - auto-clear ("this starvation cured itself") + auto-dismiss timing,
##   - the per-turn aggregator (sales arrived at port → one "12 sales, £4,300"
##     event instead of N spammy ones).
##
## Toasts and modals keep their existing wiring; the EventScheduler is the LOG
## and the persistent-notifications surface that the bell-icon top-bar widget
## reads from. Future modifier-source events (carbon tax raises transport cost,
## advisor "+10% output for 20 turns") carry a `modifiers` payload that the
## modifier pipeline will read when it lands.
##
## SEVERITY = "info" | "warning" | "critical"  (green / amber / red)
## STATE    = "active" | "dismissed" | "cleared"
##   active     - in the bell, counts toward unread
##   dismissed  - removed from the bell, still in history if persistent
##   cleared    - the auto-clear condition flipped (e.g. starvation cured)
##                — also drops out of the bell, kept in history with a flag

const HISTORY_CAP := 200       # bounds save size and per-turn iteration cost
const STARVATION_RAMP_TURNS := 3  # amber on turn 1, critical from turn 3+

const SEVERITY_INFO := "info"
const SEVERITY_WARNING := "warning"
const SEVERITY_CRITICAL := "critical"

const STATE_ACTIVE := "active"
const STATE_DISMISSED := "dismissed"
const STATE_CLEARED := "cleared"

# Hot-path templates — hoisted from the per-signal handlers so the per-turn
# storm of sale/construction signals doesn't allocate a fresh dict per call.
const _SALES_AGG_TEMPLATE := {
	"kind": "sales_aggregate",
	"severity": SEVERITY_INFO,
	"title_template": "{count} sales arrived — £{value}",
	"body_template": "{count} shipments unloaded at ports this turn.",
	"source": "production",
	"deeplink": {"panel": "money"},
	"persistent": false,
	"auto_dismiss_turns": 3,
}
const _CONSTRUCTION_AGG_TEMPLATE := {
	"kind": "construction_completed",
	"severity": SEVERITY_INFO,
	"title_template": "{count} buildings completed",
	"body_template": "Constructions finished this turn.",
	"source": "construction",
	"deeplink": {"panel": "tile"},
	"persistent": false,
	"auto_dismiss_turns": 3,
}

# A new event landed in the bell. UI listens here for the flash and badge update.
signal event_fired(event: Dictionary)
# An event left the bell (dismissed by player, or auto-cleared).
signal event_dismissed(event_id: String)
# The list of active events changed (any add/remove). UI uses this for a coarse
# refresh so it doesn't need to track 3 different signals.
signal active_events_changed()

# Live events the bell shows. Keyed by id.
var _active: Dictionary = {}
# Fired-event history (capped FIFO). One dict per fired event; useful for the
# bell's "Show cleared" footer and for the future tutorial telemetry.
var _history: Array = []
# Future scheduled events. {turn: int, event: Dictionary}, evaluated each turn.
var _scheduled: Array = []
# Condition watches. {condition: Dictionary, event: Dictionary, one_shot: bool, armed: bool}
var _watches: Array = []
# Per-turn aggregators. {bucket_id: {event_template, count, total_value}}
# Flushed at end of NARRATIVE so the bell shows one rolled-up entry per turn.
var _aggregators: Dictionary = {}
# Per-instance consecutive-turn counter for starvation severity ramp.
# {instance_id: turns_starved}
var _starvation_streaks: Dictionary = {}
# Per-instance last-turn-starved tracker so we know when to auto-clear.
var _starvation_last_turn: Dictionary = {}

# Monotonic id counter for events created without an explicit id.
var _next_event_seq: int = 1


func _ready() -> void:
	await get_tree().process_frame
	TurnManager.phase_started.connect(_on_phase_started)
	# Subscribe to the existing emitters as a translator layer. The old signals
	# stay in use (toasts, modals); this is an ADDITIONAL listener.
	if Production.has_signal("building_starved"):
		Production.building_starved.connect(_on_building_starved)
	if MatchState.has_signal("deposit_exhausted"):
		MatchState.deposit_exhausted.connect(_on_deposit_exhausted)
	if MatchState.has_signal("unlock_granted"):
		MatchState.unlock_granted.connect(_on_unlock_granted)
	if MatchState.has_signal("market_sale_arrived_at_port"):
		MatchState.market_sale_arrived_at_port.connect(_on_sale_arrived)
	if MatchState.has_signal("tile_survey_completed"):
		MatchState.tile_survey_completed.connect(_on_survey_completed)
	if Stockpile.has_signal("tile_reached_capacity"):
		Stockpile.tile_reached_capacity.connect(_on_tile_reached_capacity)
	if LoanState.has_signal("bankruptcy_warning"):
		LoanState.bankruptcy_warning.connect(_on_bankruptcy_warning)
	if Construction.has_signal("construction_completed"):
		Construction.construction_completed.connect(_on_construction_completed)
	# A clean slate when the game resets (new game, scenario start, etc).
	MatchState.state_reset.connect(reset)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Fire an event NOW. Returns the canonical event dict (with `id`, `turn_fired`).
func emit_event(event: Dictionary) -> Dictionary:
	var canon := _canonicalise(event)
	_fire(canon)
	return canon

## Fire an event on the given turn. If `forewarn_turns` is set on the event,
## ALSO fires a forewarning event N turns earlier. Returns the scheduled id.
func schedule(turn: int, event: Dictionary) -> String:
	var canon := _canonicalise(event)
	_scheduled.append({"turn": turn, "event": canon})
	return canon.id

## Convenience: relative-turn scheduling. delta_turns=5 → fires 5 turns from now.
func schedule_in(delta_turns: int, event: Dictionary) -> String:
	return schedule(int(TurnManager.current_turn) + maxi(0, delta_turns), event)

## Watch a condition. The event fires the first turn the predicate evaluates true.
## With `one_shot=false`, it can re-fire on the rising edge after the condition
## goes false again. Conditions mirror the research_unlocks.csv style:
##   {type: "money_below", value: 0.0}
##   {type: "turn_reached", value: 80}
##   {type: "good_sold", good_id: "g_012", value: 250}
##   {type: "building_count_at_least", value: 5, owner: "player_1"}
## Returns the watch id; pass to `unwatch` to remove early.
func watch(condition: Dictionary, event: Dictionary, one_shot: bool = true) -> String:
	var canon := _canonicalise(event)
	_watches.append({
		"id": canon.id,
		"condition": condition,
		"event": canon,
		"one_shot": one_shot,
		"armed": true,
		"last_true": false,
	})
	return canon.id

func unwatch(watch_id: String) -> void:
	for i in range(_watches.size() - 1, -1, -1):
		if str(_watches[i].id) == watch_id:
			_watches.remove_at(i)

## Aggregate counter for "12 sales, £4,300"-style rollups. Call as many times
## as needed during a turn; one event is emitted at end of NARRATIVE.
func aggregate(bucket_id: String, template: Dictionary, count: int = 1, value: float = 0.0) -> void:
	if not _aggregators.has(bucket_id):
		_aggregators[bucket_id] = {"template": template, "count": 0, "value": 0.0}
	_aggregators[bucket_id].count += count
	_aggregators[bucket_id].value += value

## Dismiss an active event (player clicks ×, or "Mark all read" clears the badge
## but doesn't dismiss). The event stays in history if `persistent`.
func dismiss(event_id: String) -> bool:
	if not _active.has(event_id):
		return false
	var ev: Dictionary = _active[event_id]
	ev.state = STATE_DISMISSED
	ev.dismissed_turn = int(TurnManager.current_turn)
	_active.erase(event_id)
	event_dismissed.emit(event_id)
	active_events_changed.emit()
	return true

func dismiss_all() -> void:
	var ids := _active.keys().duplicate()
	for id in ids:
		dismiss(str(id))

## All currently-active events, newest first. The bell renders this.
func active_events() -> Array:
	var rows: Array = _active.values()
	rows.sort_custom(func(a, b): return int(a.get("turn_fired", 0)) > int(b.get("turn_fired", 0)))
	return rows

func active_count() -> int:
	return _active.size()

## Worst-severity reading across active events ("" if none). Drives the bell colour.
func max_severity() -> String:
	var rank := {SEVERITY_INFO: 1, SEVERITY_WARNING: 2, SEVERITY_CRITICAL: 3}
	var best := 0
	var best_sev := ""
	for ev in _active.values():
		var r: int = int(rank.get(str(ev.get("severity", "")), 0))
		if r > best:
			best = r
			best_sev = str(ev.severity)
	return best_sev

## Read the historical log. Includes dismissed + cleared. UI footer "Show all"
## reveals these.
func history() -> Array:
	return _history.duplicate()

## Hard reset (state_reset, scenario start, load).
func reset() -> void:
	_active.clear()
	_history.clear()
	_scheduled.clear()
	_watches.clear()
	_aggregators.clear()
	_starvation_streaks.clear()
	_starvation_last_turn.clear()
	active_events_changed.emit()


# ---------------------------------------------------------------------------
# Per-turn processing
# ---------------------------------------------------------------------------

func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.NARRATIVE:
		_tick_narrative()

# Deterministic per-turn order so weekly-seed leaderboards stay reproducible:
#   1. auto-clear starvations whose buildings ran last turn (cured)
#   2. fire matured scheduled events (incl. their forewarnings)
#   3. evaluate watches and fire on the rising edge
#   4. flush per-turn aggregators into single rolled-up events
func _tick_narrative() -> void:
	var turn := int(TurnManager.current_turn)
	_auto_clear_starvations(turn)
	_fire_scheduled_for_turn(turn)
	_evaluate_watches()
	_flush_aggregators()

func _auto_clear_starvations(turn: int) -> void:
	var to_clear: Array = []
	for inst_id in _starvation_last_turn.keys():
		# A building that didn't starve last turn is back online — clear its event.
		if int(_starvation_last_turn[inst_id]) < turn - 1:
			to_clear.append(inst_id)
	for inst_id in to_clear:
		var ev_id := "starvation:%s" % str(inst_id)
		if _active.has(ev_id):
			var ev: Dictionary = _active[ev_id]
			ev.state = STATE_CLEARED
			ev.cleared_turn = turn
			_active.erase(ev_id)
			event_dismissed.emit(ev_id)
		_starvation_streaks.erase(inst_id)
		_starvation_last_turn.erase(inst_id)
	if not to_clear.is_empty():
		active_events_changed.emit()

func _fire_scheduled_for_turn(turn: int) -> void:
	var ready: Array = []
	var keep: Array = []
	for entry in _scheduled:
		var fire_turn := int(entry.turn)
		var ev: Dictionary = entry.event
		var forewarn := int(ev.get("forewarn_turns", 0))
		# Stable: forewarnings fire first (and at most once per scheduled event).
		if forewarn > 0 and turn == fire_turn - forewarn and not bool(ev.get("forewarn_emitted", false)):
			var warn := _forewarn_event(ev, fire_turn - turn)
			_fire(warn)
			ev.forewarn_emitted = true
		if turn >= fire_turn:
			ready.append(ev)
		else:
			keep.append(entry)
	for ev in ready:
		_fire(ev)
	_scheduled = keep

func _evaluate_watches() -> void:
	var keep: Array = []
	for w in _watches:
		var truthy := _check_condition(w.condition)
		if truthy and not bool(w.last_true) and bool(w.armed):
			_fire(_canonicalise(w.event.duplicate(true)))
			if bool(w.one_shot):
				continue  # drop the watch
			w.armed = false  # re-arms on a falling edge below
		if not truthy and bool(w.last_true):
			w.armed = true
		w.last_true = truthy
		keep.append(w)
	_watches = keep

func _flush_aggregators() -> void:
	for bucket_id in _aggregators.keys():
		var agg: Dictionary = _aggregators[bucket_id]
		var template: Dictionary = agg.template
		var count: int = int(agg.count)
		var total: float = float(agg.value)
		if count <= 0:
			continue
		var ev := template.duplicate(true)
		ev.title = str(ev.get("title_template", str(ev.get("title", "")))) \
			.replace("{count}", str(count)) \
			.replace("{value}", "%.0f" % total)
		ev.body = str(ev.get("body_template", str(ev.get("body", "")))) \
			.replace("{count}", str(count)) \
			.replace("{value}", "%.0f" % total)
		ev.payload = ev.get("payload", {}).duplicate(true) if ev.has("payload") else {}
		ev.payload["count"] = count
		ev.payload["total_value"] = total
		_fire(_canonicalise(ev))
	_aggregators.clear()


# ---------------------------------------------------------------------------
# Condition predicates (data-driven, mirroring research_unlocks.csv)
# ---------------------------------------------------------------------------

func _check_condition(c: Dictionary) -> bool:
	match str(c.get("type", "")):
		"turn_reached":
			return int(TurnManager.current_turn) >= int(c.get("value", 0))
		"money_below":
			return float(MatchState.money) < float(c.get("value", 0.0))
		"money_above":
			return float(MatchState.money) > float(c.get("value", 0.0))
		"building_count_at_least":
			var owner_filter := str(c.get("owner", ""))
			var n := 0
			for inst in MatchState.buildings.values():
				if owner_filter == "" or str(inst.get("owner", "")) == owner_filter:
					n += 1
			return n >= int(c.get("value", 0))
		"good_in_stockpile_at_least":
			var gid := str(c.get("good_id", ""))
			if gid == "":
				return false
			return Stockpile.get_total(gid) >= int(c.get("value", 0))
		_:
			return false


# ---------------------------------------------------------------------------
# Existing-signal translators (the bell's input layer)
# ---------------------------------------------------------------------------

func _on_building_starved(record: Dictionary) -> void:
	var inst_id := str(record.get("instance_id", ""))
	if inst_id == "":
		return
	var turn := int(TurnManager.current_turn)
	# Ramp severity: amber for the first STARVATION_RAMP_TURNS, then critical.
	_starvation_streaks[inst_id] = int(_starvation_streaks.get(inst_id, 0)) + 1
	_starvation_last_turn[inst_id] = turn
	var streak: int = int(_starvation_streaks[inst_id])
	var severity := SEVERITY_CRITICAL if streak >= STARVATION_RAMP_TURNS else SEVERITY_WARNING

	var ev_id := "starvation:%s" % inst_id
	var building_id := str(record.get("building_id", ""))
	var tile_id := str(record.get("tile_id", ""))
	var name := str(Catalog.get_building(building_id).get("display_name", building_id))

	if _active.has(ev_id):
		# Update in place (re-fires on severity change so the bell flashes).
		var ev: Dictionary = _active[ev_id]
		ev.severity = severity
		ev.streak = streak
		ev.title = "%s starved (%d turn%s)" % [name, streak, "" if streak == 1 else "s"]
		event_fired.emit(ev)
		active_events_changed.emit()
		return
	emit_event({
		"id": ev_id,
		"kind": "building_starved",
		"severity": severity,
		"title": "%s starved" % name,
		"body": "Missing inputs — production halted. Click to inspect.",
		"source": "production",
		"deeplink": {"panel": "tile", "tile_id": tile_id, "building_id": inst_id},
		"streak": streak,
		"persistent": true,
	})

func _on_deposit_exhausted(tile_id: String, token: String) -> void:
	if token == "water":
		return  # infinite, not really exhausted
	emit_event({
		"id": "deposit_exhausted:%s:%s" % [tile_id, token],
		"kind": "deposit_exhausted",
		"severity": SEVERITY_CRITICAL,
		"title": "%s deposit exhausted" % token.capitalize(),
		"body": "The %s deposit on %s has run dry." % [token, Catalog.tile_label(tile_id)],
		"source": "match_state",
		"deeplink": {"panel": "tile", "tile_id": tile_id},
		"persistent": true,
	})

func _on_unlock_granted(title: String, _description: String, via_condition: bool) -> void:
	if not via_condition:
		return
	emit_event({
		"kind": "research_unlocked",
		"severity": SEVERITY_INFO,
		"title": "Unlocked: %s" % title,
		"body": "A new research entry is available.",
		"source": "match_state",
		"deeplink": {"panel": "research"},
		"persistent": false,
		"auto_dismiss_turns": 5,
	})

func _on_sale_arrived(_port_tile_id: String, revenue: float) -> void:
	# Aggregated: one rolled-up "12 sales, £4,300" event per turn.
	aggregate("sales_arrived", _SALES_AGG_TEMPLATE, 1, revenue)

func _on_survey_completed(tile_id: String, deposit_goods: Array) -> void:
	var body := "Survey complete."
	if not deposit_goods.is_empty():
		var names: Array = []
		for d in deposit_goods:
			names.append(str(d.get("internal_name", "")))
		body = "Revealed: %s." % ", ".join(names)
	emit_event({
		"id": "survey:%s" % tile_id,
		"kind": "survey_completed",
		"severity": SEVERITY_INFO,
		"title": "Survey complete — %s" % Catalog.tile_label(tile_id),
		"body": body,
		"source": "match_state",
		"deeplink": {"panel": "tile", "tile_id": tile_id},
		"persistent": false,
		"auto_dismiss_turns": 3,
	})

func _on_tile_reached_capacity(tile_id: String) -> void:
	emit_event({
		"id": "capacity:%s" % tile_id,
		"kind": "tile_at_capacity",
		"severity": SEVERITY_WARNING,
		"title": "%s at capacity" % Catalog.tile_label(tile_id),
		"body": "Incoming goods are being dropped — clear space.",
		"source": "stockpile",
		"deeplink": {"panel": "tile", "tile_id": tile_id},
		"persistent": true,
	})

func _on_bankruptcy_warning(money: float, floor: float) -> void:
	emit_event({
		"id": "bankruptcy_warning",
		"kind": "bankruptcy_warning",
		"severity": SEVERITY_CRITICAL,
		"title": "Bankruptcy imminent",
		"body": "Cash £%.0f, floor £%.0f. Sell, borrow, or cut costs." % [money, floor],
		"source": "loan_state",
		"deeplink": {"panel": "money"},
		"persistent": true,
	})

func _on_construction_completed(_instance_id: String, _tile_id: String) -> void:
	# Aggregated: typical late-game turn finishes many constructions at once.
	# (No payload — the rolled-up event is a count, not a specific tile.)
	aggregate("construction_completed", _CONSTRUCTION_AGG_TEMPLATE, 1, 0.0)


# ---------------------------------------------------------------------------
# Save / load (orchestrated by SaveLoad — docs/save_load_spec.md)
# ---------------------------------------------------------------------------

func export_state() -> Dictionary:
	return {
		"active": _active.duplicate(true),
		"history": _history.duplicate(true),
		"scheduled": _scheduled.duplicate(true),
		"watches": _watches.duplicate(true),
		"starvation_streaks": _starvation_streaks.duplicate(true),
		"starvation_last_turn": _starvation_last_turn.duplicate(true),
		"next_event_seq": _next_event_seq,
	}

func import_state(d: Dictionary) -> void:
	_active = d.get("active", {}).duplicate(true)
	_history = d.get("history", []).duplicate(true)
	_scheduled = d.get("scheduled", []).duplicate(true)
	_watches = d.get("watches", []).duplicate(true)
	_starvation_streaks = d.get("starvation_streaks", {}).duplicate(true)
	_starvation_last_turn = d.get("starvation_last_turn", {}).duplicate(true)
	_next_event_seq = int(d.get("next_event_seq", 1))
	# Aggregators are mid-turn ephemera; intentionally not persisted.
	_aggregators.clear()
	active_events_changed.emit()


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func _fire(event: Dictionary) -> void:
	event.state = STATE_ACTIVE
	event.turn_fired = int(TurnManager.current_turn)
	_active[str(event.id)] = event
	_history.append(event.duplicate(true))
	while _history.size() > HISTORY_CAP:
		_history.pop_front()
	event_fired.emit(event)
	active_events_changed.emit()

func _canonicalise(event: Dictionary) -> Dictionary:
	var ev := event.duplicate(true)
	if not ev.has("id") or str(ev.id) == "":
		ev.id = "ev_%d" % _next_event_seq
		_next_event_seq += 1
	if not ev.has("severity"):
		ev.severity = SEVERITY_INFO
	if not ev.has("title"):
		ev.title = ""
	if not ev.has("body"):
		ev.body = ""
	if not ev.has("persistent"):
		ev.persistent = true
	return ev

func _forewarn_event(target: Dictionary, turns_until: int) -> Dictionary:
	return _canonicalise({
		"id": "%s:forewarn" % str(target.id),
		"kind": "forewarn",
		"severity": SEVERITY_WARNING,
		"title": "Coming in %d turns: %s" % [turns_until, str(target.get("title", "event"))],
		"body": str(target.get("forewarn_body", target.get("body", ""))),
		"source": str(target.get("source", "")),
		"deeplink": target.get("deeplink", {}),
		"persistent": false,
		"auto_dismiss_turns": turns_until + 1,
		"forewarn_of": str(target.id),
	})
