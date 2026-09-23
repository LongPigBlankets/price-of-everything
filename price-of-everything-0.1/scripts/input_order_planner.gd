extends RefCounted
## Shared, pure building-first allocator. All input dictionaries are copied before allocation.
static func allocate(entries: Array, leads: Dictionary, supply: Dictionary, stock_pool: Dictionary, under_supplied: Dictionary, storage_budget: int, safety_margin: float, trace: bool = false) -> Dictionary:
	var local_pool := supply.duplicate()
	var pool := stock_pool.duplicate()
	var budget := storage_budget
	var orders: Dictionary = {}   # good_id -> units to order this turn
	var wanted: Dictionary = {}   # good_id -> units we WOULD order uncapped
	var by_instance: Dictionary = {}
	for e2 in entries:
		for good_id in (e2.inputs as Dictionary):
			if str((leads[good_id] as Dictionary).get("port", "")) == "":
				continue
			var need: int = int(e2.inputs[good_id])
			var covered_local: int = mini(need, int(local_pool.get(good_id, 0)))
			local_pool[good_id] = int(local_pool.get(good_id, 0)) - covered_local
			var net_need: int = need - covered_local
			var lead: int = int((leads[good_id] as Dictionary).get("lead", 1))
			# A HANDOVER good has the Logistics Intermediary as its fallback: the intermediary
			# buys whatever the tile lacks at production time, so the market pipeline needs no
			# safety buffer and never catches up in a burst. It keeps exactly `lead` turns on
			# the road and adds at most one turn's need per turn, so switching supplier bills
			# one batch per turn instead of the whole pipeline on the first arrival.
			var handover: bool = bool((e2.get("handover", {}) as Dictionary).get(good_id, false))
			var want: int = net_need * (lead if handover else lead + 1)
			# SAFETY MARGIN. Same-tile production lands at end of turn (flush_outputs), AFTER this
			# consumer runs, so a SAME-TILE UNDER-SUPPLIED chain (local makes some but not all of the
			# demand) starves on the intra-turn lag while the pipeline -- crediting that local output
			# at full value -- buys too little. Keep ~1 turn of the locally-covered amount in the
			# market pipeline to bridge it. Gated on `under_supplied`: a self-sufficient same-tile
			# chain (local >= demand) never starves and needs no buffer; a cross-tile consumer has
			# local_rate 0 so it already buys the full need. Measured +£21/turn (+30%) on the
			# 2-desal/2-chem water chain, price impact <0.5%. POE_INPUT_SAFETY_MARGIN overrides the
			# turn count (default 1) for A/B / rollback.
			if covered_local > 0 and bool(under_supplied.get(good_id, false)) and not handover:
				want += int(ceil(float(covered_local) * safety_margin))
			var from_pool: int = mini(want, int(pool.get(good_id, 0)))
			pool[good_id] = int(pool.get(good_id, 0)) - from_pool
			var to_order: int = want - from_pool
			if handover:
				to_order = mini(to_order, net_need)
			if to_order <= 0:
				continue
			wanted[good_id] = int(wanted.get(good_id, 0)) + to_order
			var placed: int = mini(to_order, budget)
			budget -= placed
			if placed > 0:
				orders[good_id] = int(orders.get(good_id, 0)) + placed
				if trace:
					var iid := str(e2.get("instance_id", ""))
					if not by_instance.has(iid):
						by_instance[iid] = {}
					by_instance[iid][good_id] = int(by_instance[iid].get(good_id, 0)) + placed
	return {"orders": orders, "wanted": wanted, "by_instance": by_instance}
