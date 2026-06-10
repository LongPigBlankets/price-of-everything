extends Node
##
## Central modifier registry. One pipe carries every "+X% recipe output",
## "+15% transport cost", "-£2 maintenance/turn" effect produced by advisors,
## research, carbon tax events, special market orders, and pollution.
##
## Two ways modifiers arrive:
##   1. Programmatic - Modifiers.add({...})
##   2. Event payload - any EventScheduler event with a `modifiers` array gets
##      its entries auto-added when it fires (turn-stamped on arrival).
##
## Resolution: callers ask `Modifiers.apply(domain, target, base, ctx)`. Stacking
## is (base + sum_of_adds) * product_of_mults — additive deltas first, then a
## chained multiplier. With no active modifiers `apply` is one dict-emptiness
## check, so it stays cheap on the production hot path.
##
## Each TurnManager NARRATIVE phase prunes expired modifiers (those whose
## `expires_turn` has passed).
##
## All of this is data: SaveLoad's export_state/import_state round-trip the
## registry; the future top-bar Modifiers UI reads `active()` directly; a
## carbon-tax event arriving via the EventScheduler is functionally identical
## to a unit-test calling Modifiers.add().

const HISTORY_CAP := 50

signal modifiers_changed()

# id -> modifier dict
var _modifiers: Dictionary = {}
# Pruned/expired modifiers, capped FIFO — the bell + future top-bar history.
var _history: Array = []
# Monotonic id when the caller doesn't supply one.
var _next_id: int = 1


func _ready() -> void:
	await get_tree().process_frame
	TurnManager.phase_started.connect(_on_phase_started)
	EventScheduler.event_fired.connect(_on_event_fired)
	MatchState.state_reset.connect(reset)


# ── Public API ────────────────────────────────────────────────────────────

## Add or replace a modifier. Returns the canonical id.
## Modifier shape (every field optional except domain):
##   id, label, source            display + bookkeeping
##   domain                       e.g. "recipe_output", "transport_cost",
##                                "market_price", "construction_cost",
##                                "maintenance", "recipe_input"
##   target                       specific key, or "*" (default) for "all
##                                in this domain"
##   target_match                 Dictionary of {ctx_key: required_value}
##                                evaluated against the caller's ctx; the
##                                modifier applies only when every entry matches
##   mult                         multiplier (default 1.0)
##   add                          additive delta (default 0.0)
##   expires_turn                 absolute turn (0 = never expires)
##   duration_turns               convenience: set expires_turn from now
func add(modifier: Dictionary) -> String:
	var m := modifier.duplicate(true)
	if not m.has("id") or str(m.id) == "":
		m.id = "mod_%d" % _next_id
		_next_id += 1
	m["mult"] = float(m.get("mult", 1.0))
	m["add"] = float(m.get("add", 0.0))
	m["domain"] = str(m.get("domain", ""))
	m["target"] = str(m.get("target", "*"))
	if not m.has("target_match"):
		m["target_match"] = {}
	# duration_turns convenience.
	if m.has("duration_turns") and not m.has("expires_turn"):
		var dur := int(m.duration_turns)
		if dur > 0:
			m["expires_turn"] = int(TurnManager.current_turn) + dur
	if not m.has("expires_turn"):
		m["expires_turn"] = 0
	m["added_turn"] = int(TurnManager.current_turn)
	_modifiers[str(m.id)] = m
	modifiers_changed.emit()
	return str(m.id)

## Remove a modifier early. Returns false if it wasn't active.
func remove(id: String) -> bool:
	if not _modifiers.has(id):
		return false
	_modifiers.erase(id)
	modifiers_changed.emit()
	return true

## Snapshot of active modifiers — for the future top-bar surface, the bell row
## tooltips, the recipe-card hover, the construction-cost breakdown.
func active() -> Array:
	return _modifiers.values()

func active_count() -> int:
	return _modifiers.size()

func history() -> Array:
	return _history.duplicate()

func has(id: String) -> bool:
	return _modifiers.has(id)

## Wipe every modifier (state_reset, scenario start, load fallback).
func reset() -> void:
	_modifiers.clear()
	_history.clear()
	_next_id = 1
	modifiers_changed.emit()

## Resolve all modifiers in `domain` matching `target`/`ctx` against a base value.
## Returns (base + sum_adds) * prod_mults. Hot path: empty registry short-circuits.
func apply(domain: String, target: String, base: float, ctx: Dictionary = {}) -> float:
	if _modifiers.is_empty():
		return base
	var add_sum := 0.0
	var mult := 1.0
	for m in _modifiers.values():
		if str(m.domain) != domain:
			continue
		if not _target_matches(m, target, ctx):
			continue
		add_sum += float(m.add)
		mult *= float(m.mult)
	if add_sum == 0.0 and mult == 1.0:
		return base
	return (base + add_sum) * mult


# ── EventScheduler wiring (events can carry modifier payloads) ────────────

func _on_event_fired(event: Dictionary) -> void:
	if not event.has("modifiers"):
		return
	var mods = event.get("modifiers", [])
	if not (mods is Array):
		return
	for m in mods:
		if m is Dictionary:
			add(m)


# ── Per-turn pruning ──────────────────────────────────────────────────────

func _on_phase_started(phase: int) -> void:
	if phase == TurnManager.Phase.NARRATIVE:
		_prune_expired()

func _prune_expired() -> void:
	var turn := int(TurnManager.current_turn)
	var to_drop: Array = []
	for id in _modifiers.keys():
		var m: Dictionary = _modifiers[id]
		var exp := int(m.get("expires_turn", 0))
		if exp > 0 and turn >= exp:
			to_drop.append(id)
	if to_drop.is_empty():
		return
	for id in to_drop:
		var dropped: Dictionary = _modifiers[id].duplicate(true)
		dropped["dropped_turn"] = turn
		_history.append(dropped)
		while _history.size() > HISTORY_CAP:
			_history.pop_front()
		_modifiers.erase(id)
	modifiers_changed.emit()


# ── Matching ──────────────────────────────────────────────────────────────

func _target_matches(m: Dictionary, target: String, ctx: Dictionary) -> bool:
	var mod_target := str(m.get("target", "*"))
	if mod_target != "*" and mod_target != target:
		return false
	var match_dict: Dictionary = m.get("target_match", {})
	if match_dict.is_empty():
		return true
	for key in match_dict.keys():
		if str(ctx.get(key, "")) != str(match_dict[key]):
			return false
	return true


# ── Save / load (orchestrated by SaveLoad) ────────────────────────────────

func export_state() -> Dictionary:
	return {
		"modifiers": _modifiers.duplicate(true),
		"history": _history.duplicate(true),
		"next_id": _next_id,
	}

func import_state(d: Dictionary) -> void:
	_modifiers = d.get("modifiers", {}).duplicate(true)
	_history = d.get("history", []).duplicate(true)
	_next_id = int(d.get("next_id", 1))
	modifiers_changed.emit()
