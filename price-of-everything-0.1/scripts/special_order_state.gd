extends Node
## Match-scoped state for short-lived market premium contracts.
## Owns order templates, active/closed bookkeeping, generation cadence,
## commitment accounting, re-entry gating, deterministic RNG state, and save/load.

const STATUS_AVAILABLE := "available"
const STATUS_FULFILLED := "fulfilled"
const STATUS_EXPIRED := "expired"

const MIN_TARGET_TURNS := 5
const MAX_TARGET_TURNS := 10
const DEFAULT_TARGET_TURNS := 5
const DURATION_BUFFER_TURNS := 10
const REENTRY_FULFILLED_ORDERS_REQUIRED := 2
const DEFAULT_RNG_SEED := 5060301
const FIRST_SPAWN_TURN := 5
const LAST_SPAWN_TURN := 50
const SPAWN_INTERVAL_TURNS := 5
const RANDOM_SPAWN_MIN := 2
const RANDOM_SPAWN_MAX := 3
const WARNING_TURNS_LEFT := 2

const RAW_PREMIUM_PCT := 0.40
const INTERMEDIATE_PREMIUM_PCT := 0.30
const FINISHED_PREMIUM_PCT := 0.25
const ADVANCED_PREMIUM_PCT := 0.25

const SPECIAL_ORDER_GOOD_INTERNALS := [
	"iron_ore",
	"iron_ingots",
	"coal",
	"steel",
	"copper_ore",
	"copper_ingots",
	"motor",
	"copper_wiring",
	"crude_oil",
	"ethylene",
	"plastics",
	"rubber",
	"sand",
	"concrete",
	"glass",
	"ice_car",
]

const GUARANTEED_TURN5_GOODS := [
	"coal",
	"iron_ore",
	"glass",
	"ice_car",
]

const GOOD_ALIASES := {
	"motors": "motor",
	"motor": "motor",
	"plastic": "plastics",
	"plastics": "plastics",
	"cars": "ice_car",
	"car": "ice_car",
	"ice": "ice_car",
	"ice_car": "ice_car",
	"diesel_car": "ice_car",
}

const PRODUCER_RANK := {
	"mine": 0,
	"oil_well": 1,
	"fracking_oil_well": 2,
	"offshore_oil_platform": 3,
	"furnace": 4,
	"eaf": 5,
	"industrial_factory": 6,
	"factory": 7,
	"assembly_plant": 8,
	"petro_refinery": 9,
	"poly_plant": 10,
	"chem_plant": 11,
}

var active_orders: Array = []
var fulfilled_count: int = 0
var fulfilled_count_when_removed_by_good: Dictionary = {}
var last_spawn_turn: int = 0

var _next_order_counter: int = 1
var _rng := RandomNumberGenerator.new()
var _rng_seed: int = DEFAULT_RNG_SEED

signal order_added(order: Dictionary)
signal order_updated(order: Dictionary)
signal order_closed(order: Dictionary, reason: String)
signal orders_changed
signal state_reset

func _ready() -> void:
	reset()
	call_deferred("_wire_match_reset")
	call_deferred("_wire_turn_signals")

func _wire_match_reset() -> void:
	if MatchState != null and not MatchState.state_reset.is_connected(reset):
		MatchState.state_reset.connect(reset)

func _wire_turn_signals() -> void:
	if TurnManager != null and not TurnManager.turn_advanced.is_connected(_on_turn_advanced):
		TurnManager.turn_advanced.connect(_on_turn_advanced)

func _on_turn_advanced(new_turn: int) -> void:
	advance_turn(new_turn)

func reset() -> void:
	active_orders.clear()
	fulfilled_count = 0
	fulfilled_count_when_removed_by_good.clear()
	last_spawn_turn = 0
	_next_order_counter = 1
	set_rng_seed(DEFAULT_RNG_SEED)
	orders_changed.emit()
	state_reset.emit()

func set_rng_seed(seed_value: int) -> void:
	_rng_seed = seed_value
	_rng.seed = seed_value

func random_int(max_exclusive: int) -> int:
	if max_exclusive <= 0:
		return 0
	return int(_rng.randi_range(0, max_exclusive - 1))

func random_float() -> float:
	return _rng.randf()

func export_state() -> Dictionary:
	return {
		"active_orders": active_orders.duplicate(true),
		"fulfilled_count": fulfilled_count,
		"fulfilled_count_when_removed_by_good": fulfilled_count_when_removed_by_good.duplicate(true),
		"last_spawn_turn": last_spawn_turn,
		"next_order_counter": _next_order_counter,
		"rng_seed": _rng_seed,
		"rng_state": _rng.state,
	}

func import_state(d: Dictionary) -> void:
	if d.is_empty():
		reset()
		return
	active_orders = (d.get("active_orders", []) as Array).duplicate(true)
	fulfilled_count = int(d.get("fulfilled_count", 0))
	fulfilled_count_when_removed_by_good = (
		d.get("fulfilled_count_when_removed_by_good", {}) as Dictionary).duplicate(true)
	last_spawn_turn = int(d.get("last_spawn_turn", 0))
	_next_order_counter = maxi(1, int(d.get("next_order_counter", 1)))
	_rng_seed = int(d.get("rng_seed", DEFAULT_RNG_SEED))
	_rng.seed = _rng_seed
	_rng.state = int(d.get("rng_state", _rng.state))
	orders_changed.emit()

func advance_turn(turn: int) -> Dictionary:
	var closed := expire_orders_for_turn(turn)
	var warned := warn_orders_for_turn(turn)
	var added := spawn_orders_for_turn(turn)
	return {"closed": closed, "warned": warned, "added": added}

func expire_orders_for_turn(turn: int) -> Array:
	var ids: Array = []
	for order in active_orders:
		var d: Dictionary = order
		if str(d.get("status", STATUS_AVAILABLE)) != STATUS_AVAILABLE:
			continue
		if int(d.get("expires_turn", 0)) < turn:
			ids.append(str(d.get("id", "")))
	var closed: Array = []
	for order_id in ids:
		var order := close_order(str(order_id), STATUS_EXPIRED)
		if not order.is_empty():
			closed.append(order)
	return closed

func spawn_orders_for_turn(turn: int) -> Array:
	if not _is_spawn_turn(turn) or turn <= last_spawn_turn:
		return []
	var added: Array = []
	if turn == FIRST_SPAWN_TURN:
		for internal in GUARANTEED_TURN5_GOODS:
			var order := create_order(str(internal), turn, DEFAULT_TARGET_TURNS)
			if not order.is_empty():
				added.append(order)
	else:
		var count := _random_spawn_count()
		for internal in _random_eligible_goods(count):
			var order := create_order(str(internal), turn, _random_target_turns())
			if not order.is_empty():
				added.append(order)
	last_spawn_turn = turn
	return added

func eligible_goods_for_spawn() -> Array:
	var out: Array = []
	for internal in SPECIAL_ORDER_GOOD_INTERNALS:
		if can_good_enter_cycle(str(internal)):
			out.append(str(internal))
	return out

func all_order_templates() -> Array:
	var out: Array = []
	for internal in SPECIAL_ORDER_GOOD_INTERNALS:
		var template := template_for_good(str(internal))
		if not template.is_empty():
			out.append(template)
	return out

func template_for_good(good_ref: String) -> Dictionary:
	var good := _resolve_good(good_ref)
	if good.is_empty():
		return {}
	var good_id := str(good.get("id", ""))
	var recipe := _baseline_recipe_for_good(good_id)
	var building_id := str(recipe.get("building_id", ""))
	var output_qty := Catalog.recipe_output_qty(recipe, good_id) if not recipe.is_empty() else 1
	return {
		"good_id": good_id,
		"good_internal": str(good.get("internal_name", "")),
		"display_name": str(good.get("display_name", good_id)),
		"baseline_recipe_id": str(recipe.get("recipe_id", "")),
		"baseline_building_id": building_id,
		"baseline_building_internal": str(Catalog.get_building(building_id).get("internal_name", "")),
		"baseline_output_qty": maxi(1, output_qty),
		"premium_pct": _premium_pct_for_good(good),
		"min_target_turns": MIN_TARGET_TURNS,
		"max_target_turns": MAX_TARGET_TURNS,
		"duration_buffer_turns": DURATION_BUFFER_TURNS,
	}

func create_order(
	good_ref: String,
	created_turn: int = -1,
	target_turns: int = DEFAULT_TARGET_TURNS,
	qty_required: int = 0,
	premium_pct: float = -1.0
) -> Dictionary:
	var template := template_for_good(good_ref)
	if template.is_empty():
		return {}
	var good_internal := str(template.get("good_internal", ""))
	if not can_good_enter_cycle(good_internal):
		return {}
	var turn := created_turn
	if turn < 0:
		turn = int(TurnManager.current_turn) if TurnManager != null else 1
	var production_turns := clampi(target_turns, MIN_TARGET_TURNS, MAX_TARGET_TURNS)
	var required := qty_required
	if required <= 0:
		required = maxi(1, int(template.get("baseline_output_qty", 1)) * production_turns)
	var premium := premium_pct if premium_pct >= 0.0 else float(template.get("premium_pct", INTERMEDIATE_PREMIUM_PCT))
	var order := {
		"id": _next_order_id(good_internal),
		"good_id": str(template.get("good_id", "")),
		"good_internal": good_internal,
		"display_name": str(template.get("display_name", good_internal)),
		"qty_required": required,
		"qty_committed": 0,
		"qty_delivered": 0,
		"base_revenue_delivered": 0.0,
		"premium_paid": 0.0,
		"premium_pct": premium,
		"created_turn": turn,
		"expires_turn": turn + production_turns + DURATION_BUFFER_TURNS,
		"target_production_turns": production_turns,
		"warning_sent": false,
		"status": STATUS_AVAILABLE,
		"source_mode_counts": {},
		"committed_shipments": [],
		"baseline_recipe_id": str(template.get("baseline_recipe_id", "")),
		"baseline_building_id": str(template.get("baseline_building_id", "")),
		"baseline_output_qty": int(template.get("baseline_output_qty", 1)),
	}
	active_orders.append(order)
	order_added.emit(order.duplicate(true))
	orders_changed.emit()
	return order.duplicate(true)

func get_active_orders() -> Array:
	return active_orders.duplicate(true)

func get_order(order_id: String) -> Dictionary:
	var idx := _order_index(order_id)
	if idx < 0:
		return {}
	return (active_orders[idx] as Dictionary).duplicate(true)

func get_active_order_for_good(good_ref: String) -> Dictionary:
	var idx := _active_order_index_for_internal(canonical_good_internal(good_ref))
	if idx < 0:
		return {}
	return (active_orders[idx] as Dictionary).duplicate(true)

func active_orders_for_good(good_ref: String) -> Array:
	var internal := canonical_good_internal(good_ref)
	var out: Array = []
	for order in active_orders:
		if str((order as Dictionary).get("good_internal", "")) == internal:
			out.append((order as Dictionary).duplicate(true))
	return out

func remaining_uncommitted(order: Dictionary) -> int:
	return maxi(0, int(order.get("qty_required", 0)) - int(order.get("qty_committed", 0)))

func queue_from_tile(tile_id: String, order_id: String, good_ref: String, qty: int, log_oneoff: bool = true) -> Dictionary:
	if tile_id == "" or order_id == "" or qty <= 0:
		return {}
	var order := get_order(order_id)
	if order.is_empty():
		return {}
	var good_id := canonical_good_id(good_ref)
	if good_id == "" or str(order.get("good_id", "")) != good_id:
		return {}
	var send_qty := mini(qty, remaining_uncommitted(order))
	if send_qty <= 0:
		return {}
	return MarketState.execute_sale(tile_id, {good_id: send_qty}, {
		"log_oneoff": log_oneoff,
		"good_id_hint": good_id,
		"special_order_id": order_id,
		"special_order_source_mode": "tile_view",
	})

func can_good_enter_cycle(good_ref: String) -> bool:
	var internal := canonical_good_internal(good_ref)
	if internal == "":
		return false
	var good := _resolve_good(internal)
	if good.is_empty():
		return false
	if _active_order_index_for_internal(internal) >= 0:
		return false
	if not fulfilled_count_when_removed_by_good.has(internal):
		return true
	var removed_at := int(fulfilled_count_when_removed_by_good.get(internal, 0))
	return fulfilled_count - removed_at >= REENTRY_FULFILLED_ORDERS_REQUIRED

func commit_units(order_id: String, qty: int, source_mode: String = "", good_ref: String = "") -> Dictionary:
	if qty <= 0:
		return {}
	var idx := _order_index(order_id)
	if idx < 0:
		return {}
	var order: Dictionary = active_orders[idx]
	var good_id := canonical_good_id(good_ref)
	if good_id != "" and str(order.get("good_id", "")) != good_id:
		return {}
	order["qty_committed"] = int(order.get("qty_committed", 0)) + qty
	if source_mode != "":
		var counts: Dictionary = (order.get("source_mode_counts", {}) as Dictionary).duplicate(true)
		counts[source_mode] = int(counts.get(source_mode, 0)) + qty
		order["source_mode_counts"] = counts
	active_orders[idx] = order
	order_updated.emit(order.duplicate(true))
	if not _maybe_emit_warning_for_order(idx, int(TurnManager.current_turn) if TurnManager != null else 0):
		orders_changed.emit()
	return order.duplicate(true)

func deliver_units(order_id: String, qty: int) -> Dictionary:
	if qty <= 0:
		return {}
	var idx := _order_index(order_id)
	if idx < 0:
		return {}
	var order: Dictionary = active_orders[idx]
	order["qty_delivered"] = int(order.get("qty_delivered", 0)) + qty
	if int(order.get("qty_delivered", 0)) > int(order.get("qty_committed", 0)):
		order["qty_committed"] = int(order.get("qty_delivered", 0))
	active_orders[idx] = order
	if int(order.get("qty_delivered", 0)) >= int(order.get("qty_required", 0)):
		return close_order(order_id, STATUS_FULFILLED)
	order_updated.emit(order.duplicate(true))
	orders_changed.emit()
	return order.duplicate(true)

func settle_delivery(order_id: String, good_ref: String, qty: int, base_revenue: float = 0.0) -> Dictionary:
	if qty <= 0:
		return {}
	var idx := _order_index(order_id)
	if idx < 0:
		return {}
	var order: Dictionary = active_orders[idx]
	var good_id := canonical_good_id(good_ref)
	if good_id != "" and str(order.get("good_id", "")) != good_id:
		return {}
	var before_delivered := int(order.get("qty_delivered", 0))
	var required := int(order.get("qty_required", 0))
	var required_units_in_delivery := mini(qty, maxi(0, required - before_delivered))
	var unit_revenue := 0.0
	if base_revenue > 0.0:
		unit_revenue = base_revenue / float(qty)
	var base_for_premium := unit_revenue * float(required_units_in_delivery)
	order["base_revenue_delivered"] = float(order.get("base_revenue_delivered", 0.0)) + base_for_premium
	order["qty_delivered"] = before_delivered + qty
	if int(order.get("qty_delivered", 0)) > int(order.get("qty_committed", 0)):
		order["qty_committed"] = int(order.get("qty_delivered", 0))
	active_orders[idx] = order
	if int(order.get("qty_delivered", 0)) >= required:
		var base_revenue_for_premium := float(order.get("base_revenue_delivered", 0.0))
		var premium_due := maxf(0.0, base_revenue_for_premium * float(order.get("premium_pct", 0.0)) - float(order.get("premium_paid", 0.0)))
		if premium_due > 0.0 and MatchState != null:
			MatchState.add_money(premium_due)
		order["premium_paid"] = float(order.get("premium_paid", 0.0)) + premium_due
		active_orders[idx] = order
		var closed := close_order(order_id, STATUS_FULFILLED)
		return {
			"order": closed,
			"fulfilled": true,
			"premium_bonus": premium_due,
			"base_revenue_for_premium": base_revenue_for_premium,
			"qty_counted_for_premium": required_units_in_delivery,
		}
	order_updated.emit(order.duplicate(true))
	orders_changed.emit()
	return {
		"order": order.duplicate(true),
		"fulfilled": false,
		"premium_bonus": 0.0,
		"base_revenue_for_premium": float(order.get("base_revenue_delivered", 0.0)),
		"qty_counted_for_premium": required_units_in_delivery,
	}

func warn_orders_for_turn(turn: int) -> Array:
	var warned: Array = []
	for i in range(active_orders.size()):
		if _maybe_emit_warning_for_order(i, turn):
			warned.append((active_orders[i] as Dictionary).duplicate(true))
	return warned

func mark_warning_sent(order_id: String) -> bool:
	var idx := _order_index(order_id)
	if idx < 0:
		return false
	var order: Dictionary = active_orders[idx]
	order["warning_sent"] = true
	active_orders[idx] = order
	order_updated.emit(order.duplicate(true))
	orders_changed.emit()
	return true

func expire_order(order_id: String) -> Dictionary:
	return close_order(order_id, STATUS_EXPIRED)

func close_order(order_id: String, reason: String) -> Dictionary:
	var idx := _order_index(order_id)
	if idx < 0:
		return {}
	var order: Dictionary = active_orders[idx]
	active_orders.remove_at(idx)
	var status := STATUS_FULFILLED if reason == STATUS_FULFILLED else STATUS_EXPIRED
	order["status"] = status
	order["close_reason"] = reason
	order["closed_turn"] = int(TurnManager.current_turn) if TurnManager != null else int(order.get("expires_turn", 0))
	if status == STATUS_FULFILLED:
		fulfilled_count += 1
	var internal := str(order.get("good_internal", ""))
	if internal != "":
		fulfilled_count_when_removed_by_good[internal] = fulfilled_count
	if status == STATUS_FULFILLED:
		_emit_fulfilled_notification(order)
	elif int(order.get("qty_committed", 0)) > 0 or int(order.get("qty_delivered", 0)) > 0:
		_emit_expired_notification(order)
	order_closed.emit(order.duplicate(true), reason)
	orders_changed.emit()
	return order.duplicate(true)

func canonical_good_id(good_ref: String) -> String:
	var good := _resolve_good(good_ref)
	return str(good.get("id", ""))

func canonical_good_internal(good_ref: String) -> String:
	var raw := good_ref.strip_edges().to_lower()
	if raw == "":
		return ""
	var by_id := Catalog.get_good(raw)
	if not by_id.is_empty():
		return str(by_id.get("internal_name", ""))
	return str(GOOD_ALIASES.get(raw, raw))

func _resolve_good(good_ref: String) -> Dictionary:
	var raw := good_ref.strip_edges()
	if raw == "":
		return {}
	var by_id := Catalog.get_good(raw)
	if not by_id.is_empty():
		return by_id
	return Catalog.get_good_by_internal_name(canonical_good_internal(raw))

func _baseline_recipe_for_good(good_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_rank := 1 << 30
	for recipe in Catalog.recipes_producing(good_id):
		var r: Dictionary = recipe
		if str(r.get("tech_unlock_req", "")) != "":
			continue
		var building_id := str(r.get("building_id", ""))
		var building_internal := str(Catalog.get_building(building_id).get("internal_name", ""))
		var rank := int(PRODUCER_RANK.get(building_internal, 1000))
		if rank < best_rank:
			best = r
			best_rank = rank
	if not best.is_empty():
		return best
	var fallback := Catalog.recipes_producing(good_id)
	return {} if fallback.is_empty() else (fallback[0] as Dictionary)

func _premium_pct_for_good(good: Dictionary) -> float:
	var base := INTERMEDIATE_PREMIUM_PCT
	var internal := str(good.get("internal_name", ""))
	if internal == "motor" or internal == "ice_car":
		base = ADVANCED_PREMIUM_PCT
	else:
		var good_type := str(good.get("good_type", ""))
		if good_type == "raw":
			base = RAW_PREMIUM_PCT
		elif good_type != "intermediate":
			base = FINISHED_PREMIUM_PCT
	# Spot Price Reporting compounds the existing premium, rather than adding
	# a flat 25 percentage points (e.g. 40% becomes 50%, not 65%).
	return Modifiers.apply("special_order_premium", internal, base, {"good_internal": internal})

func _next_order_id(good_internal: String) -> String:
	var id := "so_%s_%06d" % [good_internal, _next_order_counter]
	_next_order_counter += 1
	return id

func _order_index(order_id: String) -> int:
	for i in range(active_orders.size()):
		if str((active_orders[i] as Dictionary).get("id", "")) == order_id:
			return i
	return -1

func _active_order_index_for_internal(good_internal: String) -> int:
	for i in range(active_orders.size()):
		if str((active_orders[i] as Dictionary).get("good_internal", "")) == good_internal:
			return i
	return -1

func _is_spawn_turn(turn: int) -> bool:
	return turn >= FIRST_SPAWN_TURN \
		and turn <= LAST_SPAWN_TURN \
		and turn % SPAWN_INTERVAL_TURNS == 0

func _random_spawn_count() -> int:
	return _rng.randi_range(RANDOM_SPAWN_MIN, RANDOM_SPAWN_MAX)

func _random_target_turns() -> int:
	return _rng.randi_range(MIN_TARGET_TURNS, MAX_TARGET_TURNS)

func _random_eligible_goods(count: int) -> Array:
	var pool := eligible_goods_for_spawn()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		var idx := random_int(pool.size())
		picked.append(pool[idx])
		pool.remove_at(idx)
	return picked

func _maybe_emit_warning_for_order(idx: int, turn: int) -> bool:
	if idx < 0 or idx >= active_orders.size():
		return false
	var order: Dictionary = active_orders[idx]
	if str(order.get("status", STATUS_AVAILABLE)) != STATUS_AVAILABLE:
		return false
	if bool(order.get("warning_sent", false)):
		return false
	if int(order.get("qty_committed", 0)) <= 0:
		return false
	var turns_left := int(order.get("expires_turn", 0)) - turn
	if turns_left < 0 or turns_left > WARNING_TURNS_LEFT:
		return false
	order["warning_sent"] = true
	active_orders[idx] = order
	_emit_warning_notification(order, turns_left)
	order_updated.emit(order.duplicate(true))
	orders_changed.emit()
	return true

func _emit_warning_notification(order: Dictionary, turns_left: int) -> void:
	var display := _order_display_name(order)
	if EventScheduler != null:
		EventScheduler.emit_event({
			"id": "special_order_warning:%s" % str(order.get("id", "")),
			"kind": "special_order_warning",
			"severity": EventScheduler.SEVERITY_WARNING,
			"title": "Special order deadline close",
			"body": "%s has %d turn%s left and already has committed units." % [
				display,
				turns_left,
				"" if turns_left == 1 else "s",
			],
			"source": "special_orders",
			"deeplink": {"panel": "market", "tab": "special_orders"},
			"persistent": false,
			"auto_dismiss_turns": 3,
		})
	if MatchState != null:
		MatchState.request_toast("Special order deadline close: %s" % display, "warning")

func _emit_fulfilled_notification(order: Dictionary) -> void:
	var display := _order_display_name(order)
	var premium := float(order.get("premium_paid", 0.0))
	if EventScheduler != null:
		EventScheduler.emit_event({
			"id": "special_order_fulfilled:%s" % str(order.get("id", "")),
			"kind": "special_order_fulfilled",
			"severity": EventScheduler.SEVERITY_INFO,
			"title": "Special order fulfilled",
			"body": "Delivered %d %s and earned a %s premium." % [
				int(order.get("qty_required", 0)),
				display,
				_money_label(premium),
			],
			"source": "special_orders",
			"deeplink": {"panel": "market", "tab": "special_orders"},
			"persistent": false,
			"auto_dismiss_turns": 4,
		})
	if MatchState != null:
		MatchState.request_toast("Special order fulfilled: %s" % display, "success")

func _emit_expired_notification(order: Dictionary) -> void:
	var display := _order_display_name(order)
	if EventScheduler != null:
		EventScheduler.emit_event({
			"id": "special_order_expired:%s" % str(order.get("id", "")),
			"kind": "special_order_expired",
			"severity": EventScheduler.SEVERITY_WARNING,
			"title": "Special order expired",
			"body": "%s expired after %d of %d units were delivered." % [
				display,
				int(order.get("qty_delivered", 0)),
				int(order.get("qty_required", 0)),
			],
			"source": "special_orders",
			"deeplink": {"panel": "market", "tab": "special_orders"},
			"persistent": false,
			"auto_dismiss_turns": 4,
		})
	if MatchState != null:
		MatchState.request_toast("Special order expired: %s" % display, "warning")

func _order_display_name(order: Dictionary) -> String:
	var display := str(order.get("display_name", ""))
	if display != "":
		return display
	var good_id := str(order.get("good_id", ""))
	var good := Catalog.get_good(good_id)
	return str(good.get("display_name", good_id))

func _money_label(value: float) -> String:
	return "GBP %.0f" % value
