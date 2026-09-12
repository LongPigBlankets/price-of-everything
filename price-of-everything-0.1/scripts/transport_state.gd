extends Node
## TransportState: goods in motion — the pending shipment list and its ids, arrivals and the
## overflow queue for full destinations, the per-link flow/congestion snapshot and history,
## arrival history for the empire view, special-order shipment resolution, and the player's
## one-off/scheduled/recurring stockpile moves with their movement ledger. Extracted from
## MatchState on 2026-09-12; the save keys are unchanged and still live under the "match"
## section (MatchState.export_state merges export_fields(), import_state calls
## import_fields() early and _requote_shipment_routes() last, reset() calls reset()).
##
## TransportService (routing, costs, capacities) stays a separate, stateless service; this
## autoload owns the STATE. Production drives advance_transport_shipments() and
## update_transport_congestion() at their fixed PROCESS points. Market orders (queue_buy,
## queue_sell, recurring sells) stay in MatchState and hand their shipments to
## queue_transport_shipment(); arrivals pay sales out through MatchState's ledger.


# Which turns a (destination tile, good) actually RECEIVED a shipment. The empire view
# reports how reliably a supply line delivers, and nothing else in the sim remembers a
# delivery once its goods are in the stockpile — so this is recorded here rather than
# derived. Storing the turn numbers (not a per-turn bitmask shift) means a quiet line
# costs nothing per turn; the list is trimmed on write, so it stays tiny.
const ARRIVAL_HISTORY_TURNS := 10
const LARGE_SHIPMENT_THRESHOLD := 500
const LARGE_SHIPMENT_SURCHARGE := 2.0   # >500 units in one move costs 2x transport (tunable)
# Route geometry (tiles/path/legs) is stripped from shipments on save — it can hold
# Vector2s (not JSON-safe) and is purely visual; it is re-quoted from the live route
# graph on import so paths stay valid even if infrastructure changed.
const _SHIPMENT_ROUTE_KEYS: Array = ["tiles", "path", "legs"]
# ── Transport throughput congestion (soft cap) ─────────────────────────────
# A tile-link's per-turn flow on a mode = total units of in-transit shipments
# crossing that tile on that mode (same convention as the infra hover readout).
# When flow exceeds the link's capacity (base mode cap × infra level × throughput
# research), goods still move but pay a transport-cost penalty: +100% over capacity,
# +200% once over capacity plus the base L1 cap. Last turn's flow drives this turn's
# costs (route_congestion_tier), so it's stable rather than self-referential.
const _CAPPED_MODES := ["roads", "rail", "pipes", "reinf_pipes"]
## How many turns of over-capacity history the transport panel reports on.
const LINK_HISTORY_TURNS := 10

signal transport_shipments_changed
## A shipment arrived at a full tile and is now waiting to unload.
signal overflow_shipment_held(record: Dictionary)
## A special-order delivery reached port with units beyond the completed order's
## demand. The UI must ask whether to sell those units or stockpile them at port.
signal special_order_overflow_ready(record: Dictionary)

var pending_transport_shipments: Array = []
var arrival_turns: Dictionary = {}          # "tile|good" -> PackedInt32Array of turn numbers
# Last turn's per-link flow ("tile|mode"->units) — drives this turn's congestion cost.
var _last_link_flow: Dictionary = {}
# Shallow snapshot of pending_transport_shipments from the same moment _last_link_flow
# is captured (before advance_transport_shipments() removes arrivals / decrements the
# rest). Shipment DICTS are shared with the live list — advance_transport_shipments()
# only ever mutates turns_remaining in place, which nothing here reads — but the ARRAY
# is this snapshot's own, so later arrivals falling out of pending_transport_shipments
# don't fall out of this too. Read by tile_good_breakdown() for the infra building
# detail panel's "Breakdown" table, so a tile still reports what transited it this turn
# even after arrivals have been paid out and removed from the live list.
var _last_transit_shipments: Array = []
var _has_transport_snapshot: bool = false
# Per-link congestion HISTORY, for the transport panel's "at cap N of last 10 turns"
# column: "tile|mode" -> Array[bool], newest last, capped at LINK_HISTORY_TURNS.
# Appended once per turn from the same snapshot that prices congestion, so the two
# can never disagree about whether a link was over.
var _link_over_history: Dictionary = {}
# Cumulative congestion surcharge attributed to each link, "tile|mode" -> float.
# Diagnosis only — nothing prices off it. See note_congestion_surcharge().
var _link_congestion_paid: Dictionary = {}
# Shipments that arrived at a destination tile whose stockpile was full and so
# couldn't unload. They wait here and retry each turn until there's room.
# Record: {source_tile, destination_tile, good_id, qty, turns_waiting, construction_instance_id}
var overflow_shipments: Array = []
var _shipment_id_counter: int = 0
var recurring_moves: Array = []   # [{source, dest, goods}] re-issued every turn
var scheduled_moves: Array = []   # [{source, dest, goods}] one-shot, fired next turn (e.g. split)
var move_log: Array = []


# --- Seaport subscriptions, sea freight and freight credits (moved from MatchState 2026-09-12) ---
# A subscribed good transfers through a seaport in one turn. Its cost is charged when it
# actually ships, rather than as the old standing subscription fee.
var seaport_auto_subscribe: bool = false
var seaport_subscribed: Dictionary = {}
var _sea_shipping_turn: int = -1
var _sea_port_usage_this_turn: Dictionary = {} # port tile -> transport class -> units
var _sea_port_charges_this_turn: Dictionary = {} # port tile -> good -> charge breakdown
# The port panel shows the latest completed traffic when a fresh turn has no
# bookings yet. Keep this separate from the live ledgers: throughput quotes must
# always start at zero on a new turn.
var _last_sea_shipping_turn: int = -1
var _last_sea_port_usage: Dictionary = {}
var _last_sea_port_charges: Dictionary = {}
## Domestic freight the founder pre-paid: units of overland haulage that cost the player
## nothing. Consumed by TransportService before any charge is raised, so it shows up as
## genuinely free movement rather than a rebate. The COO gift.
var freight_credit_units: int = 0

## Match-scoped: cleared by MatchState.reset() (new game / scenario start).
func reset() -> void:
	pending_transport_shipments.clear()
	arrival_turns.clear()
	_last_link_flow.clear()
	_last_transit_shipments.clear()
	_has_transport_snapshot = false
	_link_over_history.clear()
	_link_congestion_paid.clear()
	overflow_shipments.clear()
	recurring_moves.clear()
	scheduled_moves.clear()
	move_log.clear()
	_sea_shipping_turn = -1
	_sea_port_usage_this_turn.clear()
	_sea_port_charges_this_turn.clear()
	_last_sea_shipping_turn = -1
	_last_sea_port_usage.clear()
	_last_sea_port_charges.clear()
	freight_credit_units = 0


## Saved under MatchState's "match" section (keys unchanged from before the extraction).
func export_fields() -> Dictionary:
	return {
		"shipment_id_counter": _shipment_id_counter,
		"recurring_moves": recurring_moves.duplicate(true),
		"scheduled_moves": scheduled_moves.duplicate(true),
		"pending_transport_shipments": _shipments_for_save(),
		"transport_usage_snapshot": {"flow": _last_link_flow.duplicate(), "shipments": _last_transit_shipments.duplicate(true)} if _has_transport_snapshot else {},
		"arrival_turns": _arrival_turns_for_save(),
		"link_over_history": _link_over_history.duplicate(true),
		"link_congestion_paid": _link_congestion_paid.duplicate(),
		"overflow_shipments": overflow_shipments.duplicate(true),
		"move_log": move_log.duplicate(true),
		"freight_credit_units": freight_credit_units,
		"seaport_auto_subscribe": seaport_auto_subscribe,
		"seaport_subscribed": seaport_subscribed.duplicate(true),
		"last_sea_shipping_turn": _last_sea_shipping_turn,
		"last_sea_port_usage": _last_sea_port_usage.duplicate(true),
		"last_sea_port_charges": _last_sea_port_charges.duplicate(true),
	}


func import_fields(d: Dictionary) -> void:
	_shipment_id_counter = int(d.get("shipment_id_counter", 0))
	recurring_moves = (d.get("recurring_moves", []) as Array).duplicate(true)
	scheduled_moves = (d.get("scheduled_moves", []) as Array).duplicate(true)
	pending_transport_shipments = (d.get("pending_transport_shipments", []) as Array).duplicate(true)
	var usage: Dictionary = d.get("transport_usage_snapshot", {})
	_has_transport_snapshot = usage.has("flow")
	_last_link_flow = (usage.get("flow", {}) as Dictionary).duplicate()
	_last_transit_shipments = (usage.get("shipments", []) as Array).duplicate(true)
	# Pre-history saves simply start with no record — the readout says "no data yet"
	# rather than lying, and fills in as deliveries land.
	arrival_turns = _arrival_turns_from_save(d.get("arrival_turns", {}))
	_link_over_history = (d.get("link_over_history", {}) as Dictionary).duplicate(true)
	_link_congestion_paid = (d.get("link_congestion_paid", {}) as Dictionary).duplicate()
	overflow_shipments = (d.get("overflow_shipments", []) as Array).duplicate(true)
	move_log = (d.get("move_log", []) as Array).duplicate(true)
	freight_credit_units = int(d.get("freight_credit_units", 0))
	seaport_auto_subscribe = bool(d.get("seaport_auto_subscribe", false))
	seaport_subscribed = (d.get("seaport_subscribed", {}) as Dictionary).duplicate(true)
	_last_sea_shipping_turn = int(d.get("last_sea_shipping_turn", -1))
	_last_sea_port_usage = (d.get("last_sea_port_usage", {}) as Dictionary).duplicate(true)
	_last_sea_port_charges = (d.get("last_sea_port_charges", {}) as Dictionary).duplicate(true)


## PackedInt32Array does not survive the JSON round trip, so the history saves as plain
## arrays of ints and is rebuilt on load.
func _arrival_turns_for_save() -> Dictionary:
	var out: Dictionary = {}
	for key in arrival_turns:
		var plain: Array = []
		for t in (arrival_turns[key] as PackedInt32Array):
			plain.append(int(t))
		out[key] = plain
	return out

func _arrival_turns_from_save(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not (raw is Dictionary):
		return out
	for key in (raw as Dictionary):
		var packed := PackedInt32Array()
		for t in ((raw as Dictionary)[key] as Array):
			packed.append(int(t))
		out[str(key)] = packed
	return out

func _shipments_for_save() -> Array:
	var out: Array = []
	for shipment in pending_transport_shipments:
		var s: Dictionary = shipment.duplicate(true)
		for key in _SHIPMENT_ROUTE_KEYS:
			s.erase(key)
		out.append(s)
	return out

func _requote_shipment_routes() -> void:
	# Restore the visual route geometry stripped on save. Countdown fields
	# (turns_remaining / transport_turns) are the saved truth and stay untouched.
	for shipment in pending_transport_shipments:
		var src := str(shipment.get("source_tile", ""))
		var dst := str(shipment.get("destination_tile", ""))
		if src == "" or dst == "":
			continue
		var route: Dictionary = TransportService.route(src, dst, str(shipment.get("good_id", "")))
		for key in _SHIPMENT_ROUTE_KEYS:
			shipment[key] = route.get(key, [])

func queue_transport_shipment(shipment: Dictionary) -> void:
	var s := shipment.duplicate(true)
	if not s.has("id"):
		_shipment_id_counter += 1
		s["id"] = _shipment_id_counter  # stable id so the overlay can track it across turns
	pending_transport_shipments.append(s)
	_note_shipment_congestion(s)
	transport_shipments_changed.emit()

## Book the congestion share of a real shipment's freight against the link that caused
## it. Done HERE, at the one funnel every committed shipment passes through, rather than
## in transport_cost_for_route — that function is shared with quotes, previews and the
## build forecast, so attributing there would count charges the player never paid (the
## same trap land_cost_after_credit's `commit` flag exists to avoid).
##
## The surcharge is recovered from the multiplier the cost was priced with: only the
## units past the binding link's headroom pay it, so mult = (within + over*rate)/qty and
## the surcharge share of the final cost is (1 - 1/mult).
func _note_shipment_congestion(s: Dictionary) -> void:
	var cost := float(s.get("transport_cost", 0.0))
	if cost <= 0.0:
		return
	var qty := _shipment_total_units(s)
	if qty <= 0:
		return
	var cong := route_congestion({"tiles": s.get("tiles", []), "legs": s.get("legs", [])})
	var tier := int(cong.get("tier", 0))
	var key := str(cong.get("key", ""))
	if tier <= 0 or key == "":
		return
	var rate: float = 2.0 if tier == 1 else 3.0
	var over: int = maxi(0, qty - int(cong.get("headroom", 0)))
	var mult := (float(qty - over) + float(over) * rate) / float(qty)
	if mult <= 1.0:
		return
	note_congestion_surcharge(key, cost * (1.0 - 1.0 / mult))

func queue_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary, log_oneoff: bool = true, extra: Dictionary = {}) -> Dictionary:
	# Move goods from one tile to another: quote first, then consume only goods with a
	# legal route. Pipe-only goods must never vanish into an impossible fallback route.
	if source_tile == "" or dest_tile == "" or source_tile == dest_tile:
		return {}
	var manifest: Dictionary = {}
	var requested_qty := 0
	for good_id in goods_qtys.keys():
		var want := int(goods_qtys[good_id])
		if want <= 0:
			continue
		var available := mini(want, Stockpile.get_at_tile(source_tile, str(good_id)))
		if available <= 0:
			continue
		requested_qty += available
		manifest[str(good_id)] = int(manifest.get(str(good_id), 0)) + available
	if manifest.is_empty():
		return {}
	var surcharge := LARGE_SHIPMENT_SURCHARGE if requested_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var quote := TransportService.quote_manifest(source_tile, dest_tile, manifest, {"surcharge": surcharge})
	if quote.is_empty():
		return {}
	var items: Array = []
	var total_qty := 0
	var total_cost := 0.0
	var turns := 0
	for quoted in quote.get("items", []):
		var it: Dictionary = quoted
		var good_key := str(it.get("good_id", ""))
		var quoted_qty := int(it.get("qty", 0))
		if good_key == "" or quoted_qty <= 0:
			continue
		var moved := Stockpile.consume(source_tile, good_key, quoted_qty)
		if moved <= 0:
			continue
		var item := it.duplicate(true)
		if moved != quoted_qty:
			item["qty"] = moved
			item["cost"] = float(it.get("cost", 0.0)) * (float(moved) / float(maxi(quoted_qty, 1)))
		items.append(item)
		total_qty += moved
		total_cost += float(item.get("cost", 0.0))
		turns = maxi(turns, int(item.get("turns", quote.get("turns", 0))))
	if items.is_empty():
		return {}
	if total_cost > 0.0:
		MatchState.add_money(-total_cost)
	for it in items:
		var item_route: Dictionary = it.get("route", quote.get("route", {}))
		var item_turns := int(it.get("turns", turns))
		if item_turns >= 1:
			var shipment: Dictionary = {
				"source_tile": source_tile,
				"destination_tile": dest_tile,
				"good_id": it.good_id,
				"qty": it.qty,
				"turns_remaining": item_turns,
				"transport_turns": item_turns,
				"transport_cost": it.cost,
				"tiles": item_route.get("tiles", []),
				"path": item_route.get("path", []),
				"legs": item_route.get("legs", []),
			}
			shipment.merge(extra, true)  # optional tags, e.g. construction_instance_id
			queue_transport_shipment(shipment)
		else:
			Stockpile.add(dest_tile, it.good_id, it.qty)
	if log_oneoff:
		for it in items:
			log_move_shipment(source_tile, dest_tile, str(it.good_id), int(it.qty), turns)
	# Victory feed: a tile-to-tile move is one goods movement (manifest counts once).
	# Moves never break the Autarkic streak (you may relocate your own goods freely).
	MatchState.goods_movement_recorded.emit("move", "", turns)
	return {"items": items, "total_qty": total_qty, "turns": turns,
		"cost": total_cost, "source": source_tile, "dest": dest_tile, "surcharged": surcharge > 1.0}

func preview_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> Dictionary:
	# Cost/turns for a move WITHOUT consuming — used to populate the large-shipment dialog.
	var manifest: Dictionary = {}
	var total_qty := 0
	for good_id in goods_qtys.keys():
		var qty := mini(int(goods_qtys[good_id]), Stockpile.get_at_tile(source_tile, str(good_id)))
		if qty > 0:
			manifest[str(good_id)] = qty
			total_qty += qty
	var surcharge := LARGE_SHIPMENT_SURCHARGE if total_qty > LARGE_SHIPMENT_THRESHOLD else 1.0
	var quote := TransportService.quote_manifest(source_tile, dest_tile, manifest, {"surcharge": surcharge})
	if quote.is_empty():
		return {"turns": 0, "cost": 0.0, "total_qty": 0, "per_turn": 0.0, "surcharged": surcharge > 1.0}
	var turns: int = int(quote.get("turns", 0))
	var total_cost := float(quote.get("cost", 0.0))
	return {"turns": turns, "cost": total_cost, "total_qty": int(quote.get("total_qty", 0)),
		"per_turn": total_cost / float(maxi(turns, 1)), "surcharged": surcharge > 1.0}

func add_recurring_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> void:
	recurring_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true), "turn_started": MatchState._ledger_turn()})
	MatchState.recurring_orders_changed.emit()

# UI holds the exact entry dict, so this removes that standing order. ------------------
func remove_recurring_move(entry: Dictionary) -> bool:
	if not recurring_moves.has(entry):
		return false
	recurring_moves.erase(entry)
	MatchState.recurring_orders_changed.emit()
	return true

func add_scheduled_move(source_tile: String, dest_tile: String, goods_qtys: Dictionary) -> void:
	scheduled_moves.append({"source": source_tile, "dest": dest_tile, "goods": goods_qtys.duplicate(true)})

func _log_move(entry: Dictionary) -> void:
	move_log.append(entry)
	if move_log.size() > MatchState.LEDGER_MAX:
		move_log = move_log.slice(move_log.size() - MatchState.LEDGER_MAX)

func log_move_shipment(source_tile: String, dest_tile: String, good_id: String, qty: int, turns: int) -> void:
	# Production calls this when output is routed to ANOTHER tile's stockpile (a tile-to-tile move).
	if qty <= 0:
		return
	var started := MatchState._ledger_turn()
	_log_move({
		"good_id": str(good_id), "qty": int(qty),
		"tile_from": source_tile, "tile_to": dest_tile,
		"turn_started": started, "turn_ended": started + maxi(0, turns),
	})

func get_oneoff_move_rows() -> Array:
	var rows: Array = []
	for m in move_log:
		rows.append(MatchState._move_row(Catalog.get_display_name(str(m.get("good_id", ""))), int(m.get("qty", 0)),
			str(m.get("tile_from", "")), str(m.get("tile_to", "")),
			int(m.get("turn_started", 0)), int(m.get("turn_ended", -1))))
	return rows

func get_recurring_move_rows() -> Array:
	var rows: Array = []
	for m in recurring_moves:
		for gid in m.get("goods", {}).keys():
			rows.append(MatchState._move_row(Catalog.get_display_name(str(gid)), int(m.goods[gid]),
				str(m.get("source", "")), str(m.get("dest", "")), int(m.get("turn_started", 0)), -1))
	return rows

## A shipment couldn't fully unload at a full tile — hold the remainder so the
## goods aren't lost; it retries each turn.
func hold_overflow_shipment(record: Dictionary) -> void:
	var rec := record.duplicate(true)
	rec["turns_waiting"] = int(rec.get("turns_waiting", 0))
	overflow_shipments.append(rec)
	overflow_shipment_held.emit(rec)
	transport_shipments_changed.emit()

func get_overflow_shipments_for_tile(tile_id: String) -> Array:
	var out: Array = []
	for r in overflow_shipments:
		if str(r.get("destination_tile", "")) == tile_id:
			out.append(r)
	return out

## Retry unloading every waiting shipment into its destination stockpile. Fully
## unloaded ones drop off the list; the rest wait another turn. Call this before
## construction claims materials so unloaded build materials are picked up.
func retry_overflow_unload() -> void:
	if overflow_shipments.is_empty():
		return
	var remaining: Array = []
	for r in overflow_shipments:
		var dest := str(r.get("destination_tile", ""))
		var gid := str(r.get("good_id", ""))
		var qty := int(r.get("qty", 0))
		var added := Stockpile.add(dest, gid, qty) if (dest != "" and gid != "" and qty > 0) else 0
		if added >= qty:
			continue  # fully unloaded — drop it
		r["qty"] = qty - added
		r["turns_waiting"] = int(r.get("turns_waiting", 0)) + 1
		remaining.append(r)
	overflow_shipments = remaining
	transport_shipments_changed.emit()

func get_pending_transport_shipments() -> Array:
	return pending_transport_shipments.duplicate(true)

func offer_special_order_overflow(record: Dictionary) -> void:
	var rec := record.duplicate(true)
	if int(rec.get("qty", 0)) <= 0:
		return
	special_order_overflow_ready.emit(rec)

func special_order_overflow_can_stockpile(record: Dictionary) -> bool:
	var port_tile := str(record.get("port_tile", record.get("destination_tile", "")))
	var qty := int(record.get("qty", 0))
	if port_tile == "" or qty <= 0:
		return false
	return Stockpile.get_free_capacity(port_tile) >= qty

func sell_special_order_overflow(record: Dictionary) -> Dictionary:
	var good_id := str(record.get("good_id", ""))
	var qty := int(record.get("qty", 0))
	var revenue := float(record.get("total_revenue", 0.0))
	if good_id == "" or qty <= 0:
		return {}
	var source_tile := str(record.get("source_tile", record.get("tile_id", "")))
	var port_tile := str(record.get("port_tile", record.get("destination_tile", "")))
	var sale_record := {
		"tile_id": source_tile,
		"items": [{"good_id": good_id, "qty": qty, "revenue": revenue}],
		"total_qty": qty,
		"total_revenue": revenue,
	}
	if revenue > 0.0:
		MatchState.add_money(revenue)
		MatchState.record_tile_sale(source_tile, qty, revenue)
		MatchState.emit_stockpile_market_sale_completed(sale_record)
		if port_tile != "":
			MatchState.market_sale_arrived_at_port.emit(port_tile, revenue)
	return sale_record

func stockpile_special_order_overflow(record: Dictionary) -> bool:
	if not special_order_overflow_can_stockpile(record):
		return false
	var port_tile := str(record.get("port_tile", record.get("destination_tile", "")))
	var good_id := str(record.get("good_id", ""))
	var qty := int(record.get("qty", 0))
	return Stockpile.add(port_tile, good_id, qty) == qty

func take_pending_special_order_shipments(order_id: String) -> Array:
	if order_id == "":
		return []
	var taken: Array = []
	var remaining: Array = []
	for shipment in pending_transport_shipments:
		var s: Dictionary = shipment
		if bool(s.get("is_sale", false)) and str(s.get("special_order_id", "")) == order_id:
			taken.append(s.duplicate(true))
		else:
			remaining.append(s)
	if taken.is_empty():
		return []
	pending_transport_shipments = remaining
	transport_shipments_changed.emit()
	return taken

func special_order_shipments_manifest(shipments: Array) -> Dictionary:
	var manifest: Dictionary = {}
	for shipment in shipments:
		for item in _shipment_sale_items(shipment as Dictionary):
			var good_id := str(item.get("good_id", ""))
			var qty := int(item.get("qty", 0))
			if good_id != "" and qty > 0:
				manifest[good_id] = int(manifest.get(good_id, 0)) + qty
	return manifest

func can_store_special_order_shipments_at_ports(shipments: Array) -> bool:
	var required_by_port: Dictionary = {}
	for shipment in shipments:
		var s: Dictionary = shipment
		var port_tile := str(s.get("destination_tile", ""))
		if port_tile == "":
			return false
		var total := 0
		for item in _shipment_sale_items(s):
			total += int(item.get("qty", 0))
		required_by_port[port_tile] = int(required_by_port.get(port_tile, 0)) + total
	for port in required_by_port.keys():
		if Stockpile.get_free_capacity(str(port)) < int(required_by_port[port]):
			return false
	return true

func resolve_special_order_shipments(shipments: Array, action: String, destination_tile: String = "") -> Dictionary:
	var resolved: Array = []
	var total_qty := 0
	var total_revenue := 0.0
	match action:
		"sell":
			for shipment in shipments:
				var sell_shipment: Dictionary = (shipment as Dictionary).duplicate(true)
				sell_shipment.erase("special_order_id")
				sell_shipment.erase("special_order_source_mode")
				queue_transport_shipment(sell_shipment)
				resolved.append(sell_shipment)
				total_qty += _shipment_total_units(sell_shipment)
				total_revenue += float(sell_shipment.get("sale_record", {}).get("total_revenue", 0.0))
		"stockpile_port":
			if not can_store_special_order_shipments_at_ports(shipments):
				return {"ok": false, "reason": "port_capacity"}
			for shipment in shipments:
				var s: Dictionary = shipment
				var port_tile := str(s.get("destination_tile", ""))
				for item in _shipment_sale_items(s):
					var stock_shipment := _stockpile_shipment_from_sale_item(s, port_tile, item as Dictionary)
					_queue_or_store_resolved_shipment(stock_shipment)
					resolved.append(stock_shipment)
					total_qty += int(stock_shipment.get("qty", 0))
		"reroute":
			if destination_tile == "":
				return {"ok": false, "reason": "missing_destination"}
			for shipment in shipments:
				var s: Dictionary = shipment
				var source_tile := str(s.get("source_tile", ""))
				var manifest := _shipment_sale_manifest(s)
				if manifest.is_empty():
					continue
				var route_good_id := ""
				for good_key in manifest.keys():
					route_good_id = str(good_key)
					break
				var quote := TransportService.quote_manifest(source_tile, destination_tile, manifest, {"route_good_id": route_good_id})
				if quote.is_empty():
					continue
				for item in quote.get("items", []):
					var route: Dictionary = item.get("route", quote.get("route", {}))
					var turns := int(item.get("turns", quote.get("turns", 0)))
					var stock_shipment := {
						"source_tile": source_tile,
						"destination_tile": destination_tile,
						"good_id": str(item.get("good_id", "")),
						"qty": int(item.get("qty", 0)),
						"transport_cost": 0.0,
						"tile_distance": int(route.get("tile_distance", 0)),
						"transport_turns": turns,
						"turns_remaining": turns,
						"tiles": route.get("tiles", []),
						"path": route.get("path", []),
						"legs": route.get("legs", []),
					}
					_queue_or_store_resolved_shipment(stock_shipment)
					resolved.append(stock_shipment)
					total_qty += int(stock_shipment.get("qty", 0))
		_:
			return {"ok": false, "reason": "unknown_action"}
	return {"ok": true, "action": action, "shipments": resolved, "total_qty": total_qty, "total_revenue": total_revenue}

func get_inbound_transport_shipments(destination_tile: String, good_id: String = "") -> Array:
	var result: Array = []
	for shipment in pending_transport_shipments:
		if shipment.get("destination_tile", "") != destination_tile:
			continue
		if good_id != "" and shipment.get("good_id", "") != good_id:
			continue
		# Shallow copy: callers only read scalar fields (qty, turns_remaining). Avoids
		# deep-cloning the heavy path/tiles/legs/sale_record arrays every call (this runs
		# per building, per market input, every turn).
		result.append(shipment.duplicate())
	return result

func advance_transport_shipments() -> Array:
	var arrived: Array = []
	var remaining: Array = []
	# Decrement in place — Dictionaries are references, and the only mutation is the
	# countdown. The previous deep-copy of every shipment (with its path/tiles arrays)
	# every turn was a top sim hot-spot. Arrived shipments are read-only consumed by the
	# caller and then discarded; remaining keep their identity in the live list.
	for shipment in pending_transport_shipments:
		shipment.turns_remaining = int(shipment.get("turns_remaining", 0)) - 1
		if int(shipment.turns_remaining) <= 0:
			arrived.append(shipment)
		else:
			remaining.append(shipment)
	pending_transport_shipments = remaining
	if not arrived.is_empty():
		for shipment in arrived:
			_record_arrival(str((shipment as Dictionary).get("destination_tile", "")),
				str((shipment as Dictionary).get("good_id", "")))
		transport_shipments_changed.emit()
	return arrived

## Note that `good_id` reached `tile_id` this turn. Idempotent within a turn: several
## shipments of the same good landing together are one delivering turn, which is what
## "arrived 7 of the last 10 turns" has to mean.
func _record_arrival(tile_id: String, good_id: String) -> void:
	if tile_id == "" or good_id == "":
		return
	var key := "%s|%s" % [tile_id, good_id]
	var turn := MatchState._ledger_turn()
	var hist: PackedInt32Array = arrival_turns.get(key, PackedInt32Array())
	if hist.size() > 0 and hist[hist.size() - 1] == turn:
		return
	hist.append(turn)
	var cutoff := turn - ARRIVAL_HISTORY_TURNS
	var trimmed := PackedInt32Array()
	for t in hist:
		if t > cutoff:
			trimmed.append(t)
	arrival_turns[key] = trimmed

## How many of the last `window` turns delivered `good_id` to `tile_id` (0..window).
func arrivals_in_window(tile_id: String, good_id: String, window: int = ARRIVAL_HISTORY_TURNS) -> int:
	var hist: PackedInt32Array = arrival_turns.get("%s|%s" % [tile_id, good_id], PackedInt32Array())
	if hist.is_empty():
		return 0
	var floor_turn := MatchState._ledger_turn() - window
	var n := 0
	for t in hist:
		if t > floor_turn:
			n += 1
	return n

## "tile_id|mode" -> total units crossing it this turn (capped modes only).
func transport_link_flow() -> Dictionary:
	var flow: Dictionary = {}
	for s in pending_transport_shipments:
		var tiles: Array = s.get("tiles", [])
		var legs: Array = s.get("legs", [])
		if tiles.is_empty() or legs.is_empty():
			continue
		var qty := _shipment_total_units(s)
		if qty <= 0:
			continue
		# Walk legs once; each leg owns the slice of `tiles` up to its `to` tile.
		# `start := idx` reuses the previous leg's END index without advancing past
		# it, so consecutive legs sharing the SAME mode would credit that boundary
		# tile twice (once as the tail of leg N, once as the head of leg N+1) —
		# `counted` guards against exactly that, scoped to this one shipment. A mode
		# SWITCH at a boundary is not this bug: the tile legitimately draws on two
		# separate capacity pools there, so it correctly gets a key per mode — this
		# only dedupes repeat credit to the SAME (tile, mode) pair. _bfs_route()
		# (catalog.gd) produces simple shortest paths, so a real route is not
		# expected to revisit a (tile, mode) pair outside of this adjacent-leg
		# overlap; if that ever changes, this dedupe would need to change with it.
		var idx := 0
		var counted := {}
		for leg in legs:
			var start := idx
			while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
				idx += 1
			var mode := str(leg.get("mode", ""))
			if mode in _CAPPED_MODES:
				for i in range(start, idx + 1):
					var key := "%s|%s" % [str(tiles[i]), mode]
					if counted.has(key):
						continue
					counted[key] = true
					flow[key] = int(flow.get(key, 0)) + qty
	return flow

func _shipment_total_units(s: Dictionary) -> int:
	if bool(s.get("is_sale", false)):
		var total := 0
		for item in s.get("sale_record", {}).get("items", []):
			total += int(item.get("qty", 0))
		return total
	return int(s.get("qty", 0))

## Per-turn capacity of one tile-link: configured mode/level cap × the
## transport_throughput research multiplier. 0 means the mode is uncapped.
func tile_mode_capacity(mode: String, level: int) -> float:
	var cap: float = TransportService.link_capacity(mode, level)
	if cap <= 0.0:
		return 0.0
	return Modifiers.apply("transport_throughput", mode, cap, {"mode": mode})

# A tile's installed infra level for a mode (from the HexMap terrain). Defaults to
# Level 1 when there's no map (headless tests) or the tile lacks that infra. The
# level dict is keyed by infra SLOT key, so the "rail" mode maps to slot "rails".
func _tile_infra_level(tile_id: String, mode: String) -> int:
	var tree := get_tree()
	if tree == null:
		return 1
	var hm = tree.get_first_node_in_group("hex_map")
	if hm == null:
		return 1
	var coord = hm.id_to_coord(tile_id)
	if not hm.tiles.has(coord):
		return 1
	var slot_key := "rails" if mode == "rail" else mode
	return int((hm.tiles[coord] as Dictionary).get("infrastructure_levels", {}).get(slot_key, 1))

## Units of in-transit goods using one tile's infra of one mode this turn — what the
## tile-view infra readout shows. Counts both pass-through on a networked leg AND goods
## that originate/terminate on the tile (their first/last mile uses the tile's infra,
## even when the long haul is overland), matched by the good's transport class.
func settled_transport_shipments() -> Array:
	return _last_transit_shipments if _has_transport_snapshot else pending_transport_shipments

func tile_mode_flow(tile_id: String, mode: String, settled: bool = false) -> int:
	var total := 0
	var tolerated: Array = Catalog.infra(mode).get("good_types_tolerated", [])
	for s in (settled_transport_shipments() if settled else pending_transport_shipments):
		var tiles: Array = s.get("tiles", [])
		var legs: Array = s.get("legs", [])
		if not tiles.is_empty() and not legs.is_empty():
			# Networked route: count where it crosses this tile on a leg of `mode`.
			var idx := 0
			var hit := false
			for leg in legs:
				var start := idx
				while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
					idx += 1
				if str(leg.get("mode", "")) == mode:
					for i in range(start, idx + 1):
						if str(tiles[i]) == tile_id:
							hit = true
							break
				if hit:
					break
			if hit:
				total += _shipment_total_units(s)
			continue
		# Overland (no leg data): goods still enter/leave via THIS tile's infra for
		# their first/last mile — count those whose class this mode carries.
		if str(s.get("source_tile", "")) == tile_id or str(s.get("destination_tile", "")) == tile_id:
			var goods := _shipment_goods_dict(s)
			for good_id in goods:
				if not tolerated.has(Catalog.get_transport_class(str(good_id))):
					continue
				# A fluid with no leg data is attributed to its PIPE network only. Road and
				# rail also tolerate fluids, so without
				# this a leg-less fluid shipment would load BOTH networks and be charged
				# congestion twice for one delivery. Legged routes are attributed exactly by
				# the branch above; this only covers the first/last-mile fallback.
				if Catalog.requires_pipeline(str(good_id)) and not EconomyConfig.PIPE_MODES.has(mode):
					continue
				total += int(goods[good_id])
	return total

# {good_id: qty} a shipment carries (sale shipments may carry several goods).
func _shipment_goods_dict(s: Dictionary) -> Dictionary:
	var g: Dictionary = {}
	if bool(s.get("is_sale", false)):
		for item in s.get("sale_record", {}).get("items", []):
			g[str(item.get("good_id", ""))] = int(item.get("qty", 0))
	else:
		var gid := str(s.get("good_id", ""))
		if gid != "":
			g[gid] = int(s.get("qty", 0))
	return g

## Per-good units/cost/penalty for everything that touched one tile's infra of one
## `mode` this turn — the infrastructure building detail panel's "Breakdown" table.
## Same tile-touch rule as tile_mode_flow(): a shipment counts here if it crosses this
## tile on a `mode` leg, or — when it has no leg data (a straight overland haul) — if
## this tile is its source/destination and the good's transport class is one `mode`
## tolerates. Reads _last_transit_shipments (this turn's pre-advance snapshot, same
## moment as _last_link_flow), not the live pending_transport_shipments, so a tile
## still reports what transited it even after arrivals there have since been paid out
## and removed from the live list.
##
## cost/penalty are read-only RE-QUOTES of each touching shipment's own stored route,
## via TransportService.transport_cost_for_route()/route_congestion() — never
## land_cost_after_credit(), which CONSUMES the founder freight credit; a details panel
## must never spend anything just by being opened. They therefore reflect what moving
## these units would cost against THIS turn's congestion, not necessarily what was
## actually charged when the shipment was first queued (possibly turns ago, against a
## different flow) — the same "attribute the whole charge, don't split it per tile"
## approximation route_congestion()'s own doc comment already accepts for its binding
## link, applied here per shipment instead. Diagnostic only: nothing prices off this.
func tile_good_breakdown(tile_id: String, mode: String) -> Array:
	var by_good: Dictionary = {}   # good_id -> {qty:int, cost:float, penalty:float}
	var tolerated: Array = Catalog.infra(mode).get("good_types_tolerated", [])
	for s in settled_transport_shipments():
		var tiles: Array = s.get("tiles", [])
		var legs: Array = s.get("legs", [])
		var overland := tiles.is_empty() or legs.is_empty()
		var touches := false
		if overland:
			touches = str(s.get("source_tile", "")) == tile_id or str(s.get("destination_tile", "")) == tile_id
		else:
			var idx := 0
			for leg in legs:
				var start := idx
				while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
					idx += 1
				if str(leg.get("mode", "")) == mode:
					for i in range(start, idx + 1):
						if str(tiles[i]) == tile_id:
							touches = true
							break
				if touches:
					break
		if not touches:
			continue
		var route_data := {
			"tile_distance": int(s.get("tile_distance", 0)),
			"turns": int(s.get("transport_turns", 0)),
			"reachable": true,
			"path": s.get("path", []),
			"legs": legs,
			"tiles": tiles,
		}
		var cong := route_congestion(route_data)
		var tier := int(cong.get("tier", 0))
		var headroom := int(cong.get("headroom", 0))
		for good_id in _shipment_goods_dict(s):
			# The overland fallback has no leg to read a mode off, so — exactly like
			# tile_mode_flow's first/last-mile rule — it's credited to THIS mode only
			# when the good's transport class actually rides it; without this a
			# leg-less fluid delivery would double up on both its pipe network and
			# whatever overland mode this tile happens to be.
			if overland:
				if not tolerated.has(Catalog.get_transport_class(str(good_id))):
					continue
				if Catalog.requires_pipeline(str(good_id)) and not EconomyConfig.PIPE_MODES.has(mode):
					continue
			var qty := int(_shipment_goods_dict(s)[good_id])
			if qty <= 0:
				continue
			var cost: float = TransportService.transport_cost_for_route(str(good_id), qty, route_data)
			var penalty := 0.0
			if tier > 0:
				var over: int = maxi(0, qty - headroom)
				var within: int = qty - over
				var mult: float = 2.0 if tier == 1 else 3.0
				var denom := float(within) + float(over) * mult
				if denom > 0.0:
					penalty = cost * (1.0 - float(qty) / denom)
			var row: Dictionary = by_good.get(str(good_id), {"qty": 0, "cost": 0.0, "penalty": 0.0})
			row.qty = int(row.qty) + qty
			row.cost = float(row.cost) + cost
			row.penalty = float(row.penalty) + penalty
			by_good[str(good_id)] = row
	var out: Array = []
	for good_id in by_good:
		var row: Dictionary = by_good[good_id]
		out.append({
			"good_id": good_id,
			"qty": int(row.qty),
			"cost": float(row.cost),
			"penalty": float(row.penalty),
		})
	out.sort_custom(func(a, b): return int(a.qty) > int(b.qty))
	return out

func _shipment_sale_items(s: Dictionary) -> Array:
	if not bool(s.get("is_sale", false)):
		return []
	return (s.get("sale_record", {}).get("items", []) as Array)

func _shipment_sale_manifest(s: Dictionary) -> Dictionary:
	var manifest: Dictionary = {}
	for item in _shipment_sale_items(s):
		var good_id := str(item.get("good_id", ""))
		var qty := int(item.get("qty", 0))
		if good_id != "" and qty > 0:
			manifest[good_id] = int(manifest.get(good_id, 0)) + qty
	return manifest

func _stockpile_shipment_from_sale_item(s: Dictionary, destination_tile: String, item: Dictionary) -> Dictionary:
	return {
		"source_tile": str(s.get("source_tile", "")),
		"destination_tile": destination_tile,
		"good_id": str(item.get("good_id", "")),
		"qty": int(item.get("qty", 0)),
		"transport_cost": 0.0,
		"tile_distance": int(s.get("tile_distance", 0)),
		"transport_turns": int(s.get("transport_turns", 0)),
		"turns_remaining": int(s.get("turns_remaining", 0)),
		"tiles": s.get("tiles", []),
		"path": s.get("path", []),
		"legs": s.get("legs", []),
	}

func _queue_or_store_resolved_shipment(shipment: Dictionary) -> void:
	var dest := str(shipment.get("destination_tile", ""))
	var good_id := str(shipment.get("good_id", ""))
	var qty := int(shipment.get("qty", 0))
	if dest == "" or good_id == "" or qty <= 0:
		return
	if int(shipment.get("turns_remaining", 0)) >= 1:
		queue_transport_shipment(shipment)
	else:
		Stockpile.add(dest, good_id, qty)

## Snapshot this turn's per-link flow so next turn's transport costs can read it.
## Called each PROCESS turn. The penalty itself is a transport-cost surcharge applied
## in TransportService.transport_cost_for_route via route_congestion_tier().
func update_transport_congestion() -> void:
	_has_transport_snapshot = true
	_last_link_flow = transport_link_flow()
	_last_transit_shipments = pending_transport_shipments.duplicate()
	_roll_link_history()

## Record, for every link carrying freight this turn, whether it was over capacity.
## Rolled here rather than in the cost path so a link is sampled once per turn no
## matter how many shipments cross it.
func _roll_link_history() -> void:
	for key in _last_link_flow.keys():
		var parts := str(key).split("|")
		if parts.size() != 2:
			continue
		var cap := tile_mode_capacity(parts[1], _tile_infra_level(parts[0], parts[1]))
		var over: bool = cap > 0.0 and float(_last_link_flow[key]) > cap
		var hist: Array = _link_over_history.get(key, [])
		hist.append(over)
		if hist.size() > LINK_HISTORY_TURNS:
			hist = hist.slice(hist.size() - LINK_HISTORY_TURNS)
		_link_over_history[key] = hist

## Turns in the last LINK_HISTORY_TURNS this link ran over capacity.
func link_turns_over(link_key: String) -> int:
	var n := 0
	for over in (_link_over_history.get(link_key, []) as Array):
		if bool(over):
			n += 1
	return n

## Total congestion surcharge this link has been charged across the run (0 if never).
func link_congestion_paid(link_key: String) -> float:
	return float(_link_congestion_paid.get(link_key, 0.0))

## Book a route's congestion surcharge against the link that caused it. The surcharge
## is priced per ROUTE (marginally, against the tightest congested link's headroom),
## so there is no exact per-link split to recover — attributing the whole charge to
## the binding link is the honest approximation, and it is the link the player has to
## upgrade to make the charge go away. Diagnostic only: nothing prices off this.
func note_congestion_surcharge(link_key: String, amount: float) -> void:
	if link_key == "" or amount <= 0.0:
		return
	_link_congestion_paid[link_key] = float(_link_congestion_paid.get(link_key, 0.0)) + amount

## Every link currently over its capacity, worst first by utilisation. Rows are
## {key, tile_id, mode, flow, cap, level, ratio} — the transport panel's Infra column
## and the top bar's freight readout both read this.
func congested_links() -> Array:
	return active_links(true)

## Links carrying freight this turn, worst-first by utilisation. `only_over` keeps
## just the ones past capacity.
func active_links(only_over: bool = false) -> Array:
	var rows: Array = []
	var visible_flow := _last_link_flow if _has_transport_snapshot or not _last_link_flow.is_empty() else transport_link_flow()
	for key in visible_flow.keys():
		var parts := str(key).split("|")
		if parts.size() != 2:
			continue
		var flow := float(visible_flow[key])
		if flow <= 0.0:
			continue
		var level := _tile_infra_level(parts[0], parts[1])
		var cap := tile_mode_capacity(parts[1], level)
		if cap <= 0.0:
			continue   # uncapped mode — it can never be "over"
		var ratio := flow / cap
		if only_over and ratio <= 1.0:
			continue
		rows.append({
			"key": str(key), "tile_id": parts[0], "mode": parts[1],
			"flow": flow, "cap": cap, "level": level, "ratio": ratio,
		})
	rows.sort_custom(func(a, b): return float(a.ratio) > float(b.ratio))
	return rows

## Congestion tier of a route, from last turn's flow on the links it crosses:
##   0 = clear · 1 = any link over its capacity · 2 = any link over capacity PLUS its
## base Level-1 cap (a fixed buffer, regardless of the tile's infra level). Drives the
## +100% (tier 1) / +200% (tier 2) transport-cost penalty.
func route_congestion_tier(route_data: Dictionary) -> int:
	return int(route_congestion(route_data).get("tier", 0))

## Congestion tier PLUS the headroom that governs how many units escape the penalty.
## MARGINAL pricing: only the units ABOVE a congested link's
## remaining capacity pay the surcharge, not the whole shipment. The old whole-route
## multiplier was a cliff — 301 units on a 300-cap link doubled the cost of all 301, and
## a single congested leg penalised every other leg of the journey. Upgrading infra does
## NOT make freight cheaper per unit; it raises the cap, so more of the
## shipment rides at the base rate. Returns {tier, headroom}: headroom is the tightest
## remaining capacity across the route's capped links (0 when already at or over cap).
func route_congestion(route_data: Dictionary) -> Dictionary:
	var clear := {"tier": 0, "headroom": 0, "key": ""}
	if _last_link_flow.is_empty():
		return clear
	var tiles: Array = route_data.get("tiles", [])
	var legs: Array = route_data.get("legs", [])
	if tiles.is_empty() or legs.is_empty():
		return clear
	var worst := 0
	var headroom := -1.0
	var binding := ""   # the link whose headroom governs — what a surcharge is charged for
	var idx := 0
	for leg in legs:
		var start := idx
		while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
			idx += 1
		var mode := str(leg.get("mode", ""))
		if mode in _CAPPED_MODES:
			for i in range(start, idx + 1):
				var tile_id := str(tiles[i])
				var flow := float(_last_link_flow.get("%s|%s" % [tile_id, mode], 0))
				if flow <= 0.0:
					continue
				var cap := tile_mode_capacity(mode, _tile_infra_level(tile_id, mode))
				if cap <= 0.0:
					continue
				var l1_buffer := float(EconomyConfig.TRANSPORT_LINK_CAP_BY_MODE.get(mode, 0))
				if flow > cap + l1_buffer:
					worst = maxi(worst, 2)
				elif flow > cap:
					worst = maxi(worst, 1)
				var link_headroom := maxf(0.0, cap - flow)
				if headroom < 0.0 or link_headroom < headroom:
					binding = "%s|%s" % [tile_id, mode]
				headroom = link_headroom if headroom < 0.0 else minf(headroom, link_headroom)
	if worst == 0:
		return clear
	return {"tier": worst, "headroom": int(maxf(0.0, headroom)), "key": binding}


func seaport_covers(good_id: String) -> bool:
	if seaport_auto_subscribe:
		seaport_subscribed[good_id] = true
		return true
	return seaport_subscribed.has(good_id)

func seaport_would_cover(good_id: String) -> bool:
	return seaport_auto_subscribe or seaport_subscribed.has(good_id)

func subscribe_seaport(good_id: String) -> void:
	seaport_subscribed[good_id] = true

func seaport_subscription_fee() -> float:
	return 0.0

func _ensure_sea_shipping_turn() -> void:
	var turn := int(TurnManager.current_turn) if TurnManager != null else 1
	if turn == _sea_shipping_turn:
		return
	if _sea_shipping_turn >= 0 and not _sea_port_charges_this_turn.is_empty():
		_last_sea_shipping_turn = _sea_shipping_turn
		_last_sea_port_usage = _sea_port_usage_this_turn.duplicate(true)
		_last_sea_port_charges = _sea_port_charges_this_turn.duplicate(true)
	_sea_shipping_turn = turn
	_sea_port_usage_this_turn.clear()
	_sea_port_charges_this_turn.clear()

func sea_shipping_growth_factor() -> float:
	var turn := int(TurnManager.current_turn) if TurnManager != null else 1
	return pow(1.0 + EconomyConfig.SEAPORT_FEE_GROWTH_PER_TURN, maxf(0.0, float(turn - 1)))

func seaport_throughput_cap(good_id: String) -> int:
	var transport_class := Catalog.get_transport_class(good_id)
	var base := EconomyConfig.SEAPORT_THROUGHPUT_RESTRICTED if EconomyConfig.SEAPORT_RESTRICTED_TRANSPORT_CLASSES.has(transport_class) else EconomyConfig.SEAPORT_THROUGHPUT_STANDARD
	return maxi(1, int(round(Modifiers.apply("port_throughput", "port", float(base), {"transport_class": transport_class}))))

func seaport_base_fee(port_tile: String) -> float:
	if is_seaport_player_owned(port_tile):
		return 0.0
	return maxf(0.0, Modifiers.apply("port_per_turn_fee", "port", EconomyConfig.SEAPORT_BASE_FEE_PER_GOOD))

func keeps_introductory_port_rate() -> bool:
	# The saved origin survives completing the coach, which clears tutorial_enabled.
	return str(MatchState.ruleset.get("name", "")) == "tutorial" or bool(MatchState.ruleset.get("tutorial_enabled", false))

func seaport_insurance_rate(port_tile: String) -> float:
	# Tutorial games retain the introductory rate permanently. Ownership and research apply.
	var base := EconomyConfig.seaport_ad_valorem_rate(TurnManager.current_turn, keeps_introductory_port_rate())
	if is_seaport_player_owned(port_tile):
		base *= EconomyConfig.OWNED_SEAPORT_AD_VALOREM_SHARE
	return maxf(0.0, Modifiers.apply("port_ad_valorem_fee", "port", base))

func is_seaport_player_owned(port_tile: String) -> bool:
	if port_tile == "":
		return false
	for building in BuildingState.get_buildings_on_tile(port_tile):
		if str(building.get("building_id", "")) == "b_004" and BuildingState.is_player_owned(building):
			return true
	return false

func _owned_port_count() -> int:
	var count := 0
	for building in BuildingState.buildings.values():
		if str(building.get("building_id", "")) == "b_004" and BuildingState.is_player_owned(building):
			count += 1
	return count

func preview_sea_shipping(port_tile: String, good_id: String, qty: int) -> Dictionary:
	if port_tile == "" or good_id == "" or qty <= 0:
		return {}
	_ensure_sea_shipping_turn()
	var transport_class := Catalog.get_transport_class(good_id)
	var cap := seaport_throughput_cap(good_id)
	var usage: Dictionary = _sea_port_usage_this_turn.get(port_tile, {})
	var used_before := int(usage.get(transport_class, 0))
	var projected := used_before + qty
	# This is a soft throughput cap: traffic can still pass, but the whole shipment costs double.
	var at_cap := projected >= cap
	var surcharge := 2.0 if at_cap else 1.0
	var owned := is_seaport_player_owned(port_tile)
	var existing_goods: Dictionary = _sea_port_charges_this_turn.get(port_tile, {})
	var first_shipment_of_good := not existing_goods.has(good_id)
	var growth := sea_shipping_growth_factor()
	var fixed_fee := seaport_base_fee(port_tile) * growth * surcharge if (not owned and first_shipment_of_good) else 0.0
	var insurance_rate := seaport_insurance_rate(port_tile)
	var insured_value := float(qty) * MarketState.get_buy_price(good_id)
	var insurance_fee := insured_value * insurance_rate * growth * surcharge
	return {
		"port": port_tile, "good_id": good_id, "qty": qty, "transport_class": transport_class,
		"capacity": cap, "used_before": used_before, "projected_usage": projected,
		"at_cap": at_cap, "surcharge": surcharge, "owned": owned, "growth": growth,
		"base_fee": fixed_fee, "insurance_fee": insurance_fee, "total": fixed_fee + insurance_fee,
	}

func commit_sea_shipping(port_tile: String, good_id: String, qty: int, direction: String) -> Dictionary:
	var charge := preview_sea_shipping(port_tile, good_id, qty)
	if charge.is_empty():
		return charge
	var transport_class := str(charge.get("transport_class", ""))
	var usage: Dictionary = _sea_port_usage_this_turn.get(port_tile, {}).duplicate()
	usage[transport_class] = int(charge.get("projected_usage", qty))
	_sea_port_usage_this_turn[port_tile] = usage
	var by_good: Dictionary = _sea_port_charges_this_turn.get(port_tile, {}).duplicate(true)
	var row: Dictionary = by_good.get(good_id, {
		"good_id": good_id, "buy_qty": 0, "sell_qty": 0, "total_qty": 0,
		"base_fee": 0.0, "insurance_fee": 0.0, "total": 0.0,
		"transport_class": transport_class, "capacity": int(charge.get("capacity", 0)), "at_cap": false,
	})
	if direction == "sell":
		row["sell_qty"] = int(row.get("sell_qty", 0)) + qty
		ResearchState.note_port_sale(transport_class, port_tile, qty)
	else:
		row["buy_qty"] = int(row.get("buy_qty", 0)) + qty
	row["total_qty"] = int(row.get("total_qty", 0)) + qty
	row["base_fee"] = float(row.get("base_fee", 0.0)) + float(charge.get("base_fee", 0.0))
	row["insurance_fee"] = float(row.get("insurance_fee", 0.0)) + float(charge.get("insurance_fee", 0.0))
	row["total"] = float(row.get("total", 0.0)) + float(charge.get("total", 0.0))
	row["at_cap"] = bool(row.get("at_cap", false)) or bool(charge.get("at_cap", false))
	by_good[good_id] = row
	_sea_port_charges_this_turn[port_tile] = by_good
	if direction == "sell":
		# One large manifest may contain many goods.  Its port-sale totals are
		# accumulated immediately, but research reads them once in NARRATIVE.
		ResearchState._mark_research_progress_dirty()
	TransportState.transport_shipments_changed.emit() # Refresh the open port readout after a shipment is booked.
	return charge

func seaport_shipping_summary(port_tile: String) -> Dictionary:
	_ensure_sea_shipping_turn()
	var current_rows: Dictionary = _sea_port_charges_this_turn.get(port_tile, {})
	var use_latest_completed_turn := current_rows.is_empty()
	var source_rows: Dictionary = _last_sea_port_charges.get(port_tile, {}) if use_latest_completed_turn else current_rows
	var source_usage: Dictionary = _last_sea_port_usage.get(port_tile, {}) if use_latest_completed_turn else _sea_port_usage_this_turn.get(port_tile, {})
	var rows: Array = []
	for row in source_rows.values():
		rows.append((row as Dictionary).duplicate(true))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Catalog.get_display_name(str(a.get("good_id", ""))) < Catalog.get_display_name(str(b.get("good_id", ""))))
	var owned := is_seaport_player_owned(port_tile)
	return {
		"owned": owned, "growth": sea_shipping_growth_factor(),
		"base_fee": seaport_base_fee(port_tile),
		"insurance_rate": seaport_insurance_rate(port_tile),
		"usage": source_usage.duplicate(),
		"activity_turn": _last_sea_shipping_turn if use_latest_completed_turn else _sea_shipping_turn,
		"is_current_turn": not use_latest_completed_turn,
		"rows": rows,
	}

func add_freight_credit(units: int) -> void:
	if units <= 0:
		return
	freight_credit_units += units
	AdvisorState.advisors_changed.emit()

## Spend up to `units` of credit; returns how many were covered (0 when exhausted).
func consume_freight_credit(units: int) -> int:
	if freight_credit_units <= 0 or units <= 0:
		return 0
	var used := mini(freight_credit_units, units)
	freight_credit_units -= used
	return used

## How much WOULD be covered, without spending it. Quotes, previews and the build forecast
## must use this — they call the same costing path as a real shipment, and consuming there
## would drain the gift by looking at it.
func peek_freight_credit(units: int) -> int:
	if freight_credit_units <= 0 or units <= 0:
		return 0
	return mini(freight_credit_units, units)
