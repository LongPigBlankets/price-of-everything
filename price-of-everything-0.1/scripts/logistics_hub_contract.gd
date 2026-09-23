extends RefCounted
## Pure P4 workload and operating-supply contract. No game state, funding or stock mutation.
## The live scheduler must supply only physically reachable, equipment-compatible edges.
const PAYLOAD := 100
const VEHICLE_LC := 10
const ROAD_RECIPE_LC := 125
const WEIGHTS := {"solid_light": 1, "solid_heavy": 2, "ultra_heavy": 5,
	"liquid": 2, "safe_liquid": 2, "hazard_liquid": 4, "gas": 3}
const RECIPES := {
	"diesel": {"hydraulic_components": 2, "tyres": 4, "fuels": 6},
	"lithium_electric": {"hydraulic_components": 2, "tyres": 4, "lithium_battery": 1},
	"sodium_electric": {"hydraulic_components": 2, "tyres": 4, "sodium_battery": 1},
}
const BULK_GOODS := ["coal", "iron_ore", "copper_ore", "bauxite", "limestone", "sand", "lithium_ore"]

static func equipment_class(transport_class: String, internal_name: String) -> String:
	# Weights are not equipment permissions. Tankers/gases remain outside road P4.
	if transport_class not in ["solid_light", "solid_heavy", "ultra_heavy"]:
		return ""
	return "bulk" if internal_name in BULK_GOODS or internal_name.ends_with("_ore") else "general"

## Each row is one cargo quantity available at one directed adjacent edge:
## {hub, tile, next_tile, available_turn, good_id, internal_name, transport_class, qty,
## connected}. Optional owner/dispatch identifiers are deliberately ignored for grouping;
## the scheduler must already have selected player-owned cargo for this operator.
## Returns stable groups with separate good quantities; never merges their ownership records.
static func consolidate(rows: Array) -> Dictionary:
	var groups := {}
	var rejected: Array = []
	for index in rows.size():
		var row: Dictionary = rows[index]
		var qty := int(row.get("qty", 0))
		var cargo_class := str(row.get("transport_class", ""))
		var equipment := equipment_class(cargo_class, str(row.get("internal_name", "")))
		var origin := str(row.get("tile", ""))
		var destination := str(row.get("next_tile", ""))
		var hub := str(row.get("hub", ""))
		var good := str(row.get("good_id", ""))
		if qty <= 0 or equipment == "" or hub == "" or good == "" or origin == "" or destination == "" or origin == destination or not bool(row.get("connected", false)):
			rejected.append(index)
			continue
		# JSON tuple encoding avoids key collisions from arbitrary IDs containing delimiters.
		var key := JSON.stringify([hub, origin, destination, int(row.get("available_turn", 0)), equipment])
		if not groups.has(key):
			groups[key] = {"hub": hub, "tile": origin, "next_tile": destination,
				"available_turn": int(row.get("available_turn", 0)), "equipment": equipment,
				"goods": {}, "weighted_units": 0, "lc": 0, "rows": []}
		var group: Dictionary = groups[key]
		group.goods[good] = int(group.goods.get(good, 0)) + qty
		group.weighted_units += qty * int(WEIGHTS[cargo_class])
		group.rows.append(index)
	var ordered: Array = []
	var keys: Array = groups.keys()
	keys.sort()
	var total_lc := 0
	for key in keys:
		var group: Dictionary = groups[key]
		group.lc = ceili(float(group.weighted_units) / PAYLOAD)
		total_lc += int(group.lc)
		ordered.append(group)
	return {"groups": ordered, "lc": total_lc, "rejected": rejected}

## Loaded adjacent-edge work only. Handling/return occupancy belongs to the scheduler.
static func installed_loaded_capacity(vehicles: int) -> int:
	return maxi(0, vehicles) * VEHICLE_LC

## Whole recipes are secured BEFORE their work. Stored credit is already-paid service,
## not goods, and cannot be sold or used by another hub. No per-turn minimum draw.
static func supplies_for_work(loaded_lc: int, saved_credit: int, variant: String = "diesel") -> Dictionary:
	if loaded_lc < 0 or saved_credit < 0 or not RECIPES.has(variant):
		return {"ok": false, "reason": "Invalid workload, service credit or equipment variant."}
	var recipes := ceili(float(maxi(0, loaded_lc - saved_credit)) / ROAD_RECIPE_LC)
	var goods := {}
	for good: String in RECIPES[variant]:
		var qty := recipes * int(RECIPES[variant][good])
		if qty > 0: goods[good] = qty
	return {"ok": true, "recipes": recipes, "goods": goods,
		"credit_after": saved_credit + recipes * ROAD_RECIPE_LC - loaded_lc}

## Admission check only: callers must atomically consume the complete basket before
## applying credit_after or dispatching. A rejected basket leaves old credit intact.
static func admit_stock_work(loaded_lc: int, saved_credit: int, stock: Dictionary, variant: String = "diesel") -> Dictionary:
	var quote := supplies_for_work(loaded_lc, saved_credit, variant)
	if not bool(quote.ok): return quote
	var missing := {}
	for good: String in quote.goods:
		var deficit := int(quote.goods[good]) - int(stock.get(good, 0))
		if deficit > 0: missing[good] = deficit
	if not missing.is_empty():
		return {"ok": false, "reason": "Missing operating supplies.", "missing": missing,
			"credit_after": saved_credit, "goods": {}}
	return quote

## Deterministic one-edge scheduling pass. Fleets supply {vehicles, credit, stock, variant}.
## Allocations reference original row indexes, so the live owner can split cargo and its
## liabilities once without inventing a second inventory. Queues retain all unallocated units.
## Handling and return are included in the selected ten loaded LC per vehicle.
static func schedule_stock_work(rows: Array, fleets: Dictionary) -> Dictionary:
	var pooled := consolidate(rows)
	var hubs := {}
	var allocations: Array = []
	var waiting: Array = []
	for index in rows.size(): waiting.append(maxi(0, int(rows[index].get("qty", 0))))
	for group: Dictionary in pooled.groups:
		var id := str(group.hub)
		if not fleets.has(id): continue
		var fleet: Dictionary = fleets[id]
		if not hubs.has(id):
			hubs[id] = {"used_lc": 0, "goods": {}, "credit_after": int(fleet.get("credit", 0)), "blocked": ""}
		var state: Dictionary = hubs[id]
		var free_lc := maxi(0, installed_loaded_capacity(int(fleet.get("vehicles", 0))) - int(state.used_lc))
		var target := mini(free_lc, int(group.lc))
		if target <= 0:
			state.blocked = "Fleet capacity exhausted."
			continue
		var variant := str(fleet.get("variant", "diesel"))
		if not RECIPES.has(variant) or int(fleet.get("credit", 0)) < 0:
			state.blocked = "Invalid service configuration."
			continue
		# Bound admission by complete baskets up front, rather than retrying one LC at
		# a time for an arbitrarily large shipment. Earlier groups share the same budget.
		var stock: Dictionary = fleet.get("stock", {})
		var complete_recipes := 2147483647
		for good: String in RECIPES[variant]:
			complete_recipes = mini(complete_recipes, maxi(0, int(floor(float(stock.get(good, 0)) / int(RECIPES[variant][good])))))
		var funded_lc := int(fleet.get("credit", 0)) + complete_recipes * ROAD_RECIPE_LC
		target = mini(target, maxi(0, funded_lc - int(state.used_lc)))
		if target <= 0:
			state.blocked = "Missing operating supplies."
			continue
		var payload_left := target * PAYLOAD
		var used_weight := 0
		for index: int in group.rows:
			var row_data: Dictionary = rows[index]
			var weight := int(WEIGHTS[str(row_data.transport_class)])
			var units := mini(int(row_data.qty), int(floor(float(payload_left) / weight)))
			if units <= 0: continue
			allocations.append({"row": index, "qty": units, "hub": id})
			waiting[index] -= units
			payload_left -= units * weight
			used_weight += units * weight
		state.used_lc += ceili(float(used_weight) / PAYLOAD)
		var final_quote := supplies_for_work(int(state.used_lc), int(fleet.get("credit", 0)), variant)
		state.goods = final_quote.goods
		state.credit_after = final_quote.credit_after
	return {"allocations": allocations, "waiting": waiting, "hubs": hubs, "rejected": pooled.rejected}
