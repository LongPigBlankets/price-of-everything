extends RefCounted
## The Resources panel's figures, a good at a time, read from the engine so the panel holds no sums of its
## own (docs/resources-ds2-plan.md §6). Presentation lives in scripts/resources_ds2/.
##
## The counts are last turn's, from Production.last_turn_summary, beside what is held now:
##   produced, used, sold   what your buildings made and used, and what was sold (market or intermediary)
##   stored                 what sits in your stockpiles, less what construction and upgrades have claimed
##   transit                what is on the road between tiles or to a port. The intermediary's own
##                          deliveries never travel as shipments, so they are not counted
## The costs are what the turn charged on the good (Production.note_good_cost), each a total and a unit:
##   transport, storage, intermediary

const MODE_ORDER := ["rail", "roads", "pipes", "reinf_pipes"]
const MODE_LABELS := {"roads": "Road", "rail": "Rail", "pipes": "Pipe", "reinf_pipes": "Reinforced pipe"}
const COST_KINDS := ["transport", "storage", "intermediary"]


## Every good the table lists: the goods in play, power left out (the top bar and the tile view show it).
static func goods() -> Array:
	var out: Array = []
	for good: Dictionary in MatchState.visible_goods():
		if str(good.get("internal_name", "")) == "power" or str(good.get("transport_class", "")) == "power":
			continue
		out.append(good)
	return out


## A row for each good: {good_id, name, produced, used, sold, stored, transit, cost (a unit, -1 when you made
## none), market (what a sale fetches), carbon (the levy a unit pays, 0 before it is in force)}.
static func rows() -> Array:
	var summary: Dictionary = Production.last_turn_summary
	var produced: Dictionary = summary.get("produced", {})
	var used: Dictionary = summary.get("consumed", {})
	var sold: Dictionary = summary.get("sold", {})
	var reserved := reserved_units()
	var moving := transit_units()
	var turn := int(TurnManager.current_turn)
	var out: Array = []
	for good: Dictionary in goods():
		var gid := str(good.get("id", ""))
		out.append({
			"good_id": gid,
			"name": str(good.get("display_name", gid)),
			"produced": int(produced.get(gid, 0)),
			"used": int(used.get(gid, 0)),
			"sold": int((sold.get(gid, {}) as Dictionary).get("qty", 0)),
			"stored": maxi(0, Stockpile.get_total(gid) - int(reserved.get(gid, 0))),
			"transit": int(moving.get(gid, 0)),
			"cost": CostSolver.get_good_unit_cost(gid),
			"market": MarketState.get_sale_price(gid),
			"carbon": PolicyState.carbon_charge(gid, 1, turn),
		})
	return out


## True once the carbon levy charges anything, which is when the table gains its Carbon tax column.
static func carbon_in_force() -> bool:
	return PolicyState.co2_tax_scale(int(TurnManager.current_turn)) > 0.0


## Units of each good that construction and upgrades have gathered on your tiles: good_id -> units.
static func reserved_units() -> Dictionary:
	var out := {}
	for tile in Stockpile.tiles_with_stock():
		var held: Dictionary = BuildingWorks.reserved_materials_on_tile(str(tile))
		for gid in held:
			out[str(gid)] = int(out.get(str(gid), 0)) + int(held[gid])
	return out


## Units of each good on the road: good_id -> units. Shipments between tiles and sales on their way to a
## port; a delivery ordered for a building site is the site's, not stock on the move.
static func transit_units() -> Dictionary:
	var out := {}
	for s: Dictionary in TransportState.get_pending_transport_shipments():
		if bool(s.get("is_sale", false)):
			for item: Dictionary in (s.get("sale_record", {}) as Dictionary).get("items", []):
				var sold_gid := str(item.get("good_id", ""))
				out[sold_gid] = int(out.get(sold_gid, 0)) + int(item.get("qty", 0))
			continue
		if Production._shipment_reserved_outside_input_pipeline(s):
			continue
		var gid := str(s.get("good_id", ""))
		if gid != "":
			out[gid] = int(out.get(gid, 0)) + int(s.get("qty", 0))
	return out


## What last turn charged on a good: {transport, storage, intermediary}, each {total, units, per_unit}.
## Storage's unit figure is the fee a stored unit pays a turn, whether or not any was held.
static func costs(good_id: String) -> Dictionary:
	var booked: Dictionary = (Production.last_turn_summary.get("good_costs", {}) as Dictionary).get(good_id, {})
	var out := {}
	for kind: String in COST_KINDS:
		var total := float(booked.get(kind, 0.0))
		var units := int(booked.get(kind + "_units", 0))
		out[kind] = {"total": total, "units": units, "per_unit": total / float(units) if units > 0 else 0.0}
	out.storage.per_unit = EconomyConfig.warehousing_cost_per_unit(good_id)
	return out


## What a unit costs to move one tile, by the modes the good may use: [{mode, label, levels: [L1, L2, L3]}].
static func freight_rates(good_id: String) -> Array:
	var allowed: Array = Catalog.modes_for_good(good_id)
	var out: Array = []
	for mode: String in MODE_ORDER:
		if not allowed.has(mode):
			continue
		var levels: Array = []
		for level: int in [1, 2, 3]:
			levels.append(TransportService.freight_per_tile(good_id, mode, level))
		out.append({"mode": mode, "label": str(MODE_LABELS.get(mode, mode)), "levels": levels})
	return out


## The port's charge on a unit shipped: {cost, rate}.
static func port_charge(good_id: String) -> Dictionary:
	return TransportService.port_ad_valorem_per_unit(good_id)
