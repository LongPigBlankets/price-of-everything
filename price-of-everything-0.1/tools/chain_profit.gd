extends Node
## Rebalance harness. Per recipe, at turn-1 base prices/costs:
##   NAKED   = sell(out) - buy(in)x1.05 - transport(1-turn road, in+out) - run_cost - energy(grid £1)
##             -> design target: NEGATIVE for the bulk (raw/intermediate)
##   INTEGRATED margin = own the whole input tree (no markup/transport) + own power (coal-power cost,
##             not grid) + colocated; margin = profit / total_cost.
##   Target margin SCALES BY TIER: raw thin -> apex (cars/chips) immense. K_TIER drives it.
## Mines also shown with the -50% deposit-exhaustion penalty (should be negative at start).
##   <godot> --headless --path . res://tools/chain_profit.tscn --quit-after 200
const GRID := 1.0
const R_U := 0.0032
const R_S := 0.0096
const R_H := 0.032
# running cost captures K of value_add; LOWER K -> fatter integrated margin. margin ~= (1-K)/K, plus
# deep chains compound (you also capture every upstream tier's left-behind margin).
const K_RAW := 0.85         # ~18%
const K_INTER := 0.75       # ~33%
const K_FINISHED := 0.65    # ~54%   (basic finished: plastics, glass, fuels, frame)
const K_APEX := 0.45        # ~120%+ (cars, chips, vehicles, panels, batteries — the reward)
const K_OTHER := 0.82       # power, waste, fallback
const APEX_PRICE := 40.0    # a 'finished' good at/above this base_price is treated as apex
const COST_FLOOR := 1.0
const USE_FORMULA := false   # true = override labour+maint with the formula; false = use the data
const GRID_SELL := 0.60     # a standalone plant sells power to the grid at this, not base £1.00
# NEW COST MODEL: labour + maintenance are both a % of the building's build-material market value.
# maintenance flat 5%; labour 2-10% (per-recipe lever — flat for this first pass, varied later).
const MAINT_PCT := 0.05
const LABOUR_PCT := 0.05
const SINGLE_LOSS_FRAC := 0.07  # ungated intermediates: size so the lone building loses this % of its cost
const FULL_FLOOR_MARGIN := 0.10  # ...but never let full integration drop below this margin (low-lift floor)
var _producers := {}        # good_id -> [recipes]
var _own_power_per_unit := 0.0
var _ucost := {}            # good_id -> cheapest integrated unit cost (memo)

func _ready() -> void:
	for r in Catalog.all_recipes():
		for o in r.get("outputs", []):
			var gid := str(o.get("good_id", ""))
			if gid != "":
				if not _producers.has(gid): _producers[gid] = []
				_producers[gid].append(r)
	_own_power_per_unit = _compute_own_power_cost()
	print("\n[own coal-power cost: £%.3f / power-unit  (vs grid £1.00)]" % _own_power_per_unit)

	var naked_rows := []; var integ_rows := []; var mine_rows := []; var tier_data := {}; var naked_tier := {}
	for r in Catalog.all_recipes():
		var tier := _tier(r)
		var nk := _naked(r, 0.5 if _is_mining(r) else 1.0)
		if not naked_tier.has(tier): naked_tier[tier] = [0, 0]
		naked_tier[tier][1] += 1
		if nk > 0: naked_tier[tier][0] += 1
		var lbl := "%-28s [%-12s] out:%-15s" % [str(r.get("display_name","?")), tier, "%s x%d" % [str(r.get("output_name","?")), int(r.get("output_qty",0))]]
		naked_rows.append([nk, "%s NAKED %+8.2f%s" % [lbl, nk, " [gated]" if str(r.get("tech_unlock_req",""))!="" else ""]])
		if _is_mining(r):
			mine_rows.append([nk, "%-28s base %+7.2f   start(-50%%) %+7.2f" % [str(r.get("display_name","?")), _naked(r, 1.0), _naked(r, 0.5)]])
		var cost := _recipe_cost(r)
		var rev := _revenue(r)
		if cost > 0.01:
			var margin := (rev - cost) / cost * 100.0
			if not tier_data.has(tier): tier_data[tier] = []
			tier_data[tier].append(margin)
			integ_rows.append([margin, "%-28s [%-12s] profit %+8.2f / cost %7.2f = %+8.1f%%" % [str(r.get("display_name","?")), tier, rev-cost, cost, margin]])
	naked_rows.sort_custom(func(a,b): return a[0] > b[0])
	integ_rows.sort_custom(func(a,b): return a[0] > b[0])
	var npos := 0; for x in naked_rows: if x[0] > 0: npos += 1
	print("\n===== NAKED (turn-1, +1-turn road transport) — bulk should be NEGATIVE; %d/%d POSITIVE =====" % [npos, naked_rows.size()])
	for t in ["raw", "intermediate", "finished", "apex", "power", "waste", "other"]:
		if naked_tier.has(t): print("    %-12s %d/%d positive" % [t, naked_tier[t][0], naked_tier[t][1]])
	for x in naked_rows: print(x[1])
	print("\n===== FULL INTEGRATION margin by recipe (high -> low) =====")
	for x in integ_rows: print(x[1])
	print("\n--- integrated margin BY TIER (the gradient: raw thin -> apex immense) ---")
	for t in ["raw", "intermediate", "finished", "apex", "power", "waste", "other"]:
		if tier_data.has(t):
			var arr: Array = tier_data[t]
			var s := 0.0
			for m in arr: s += m
			print("  %-12s n=%2d   avg %+8.1f%%   range %+.0f%% .. %+.0f%%" % [t, arr.size(), s/arr.size(), arr.min(), arr.max()])
	print("\n===== MINES — should be NEGATIVE at start (with -50%% deposit penalty) =====")
	mine_rows.sort_custom(func(a,b): return a[0] > b[0])
	for x in mine_rows: print(x[1])
	print("\n===== BACKSOLVE: per-building target run_cost (labour+maint) — power/storage excluded =====")
	var bt := {}
	for r in Catalog.all_recipes():
		var bid := str(r.get("building_id",""))
		if bid == "": continue
		var is_pwr := false
		for o in r.get("outputs", []):
			if _is_power(str(o.good_id)): is_pwr = true
		if is_pwr: continue   # never size labour off power recipes (keeps own-power cheap)
		if not bt.has(bid): bt[bid] = {"sum": 0.0, "n": 0, "tiers": {}}
		bt[bid].sum += _run_cost(r)
		bt[bid].n += 1
		var tr := _tier(r)
		bt[bid].tiers[tr] = int(bt[bid].tiers.get(tr, 0)) + 1
	for bid in bt:
		var d = bt[bid]
		if int(d.n) == 0: continue
		var best_t := "intermediate"; var best_c := -1
		for t in d.tiers:
			if int(d.tiers[t]) > best_c:
				best_c = int(d.tiers[t]); best_t = str(t)
		var bname := str(Catalog.get_building(bid).get("internal_name", "?"))
		print("BACKSOLVE|%s|%s|%s|%.3f|%d" % [bid, bname, best_t, d.sum / d.n, d.n])
	print("\n===== QTYSOLVE: target primary output_qty per recipe (pins integrated margin to tier) =====")
	for r in Catalog.all_recipes():
		var outs: Array = r.get("outputs", [])
		if outs.is_empty(): continue
		var primary := str(r.get("output_good_id", str(outs[0].good_id)))
		if _is_power(primary): continue          # power output fixed at 100
		var price := _sell(primary)
		if price <= 0.01: continue
		var b := _bld(r)
		var tier3 := _good_tier(primary)
		var gated3 := str(r.get("tech_unlock_req","")) != ""
		var byval := 0.0                          # byproducts credited at full price (kept fixed)
		for o in outs:
			if str(o.good_id) != primary: byval += float(o.qty) * _sell(str(o.good_id))
		var newq: float
		if (not gated3) and tier3 == "intermediate":
			# Ungated intermediate available at game start: size so the LONE building (market inputs,
			# grid power) runs at a small loss — profit must come from integration. But never let full
			# integration drop below the floor margin; for low-lift recipes that floor wins (they end up
			# ~break-even single, can't be both). Gated routes keep their tier margin, staying better.
			var scost := _input_buy(r) + _labour(b) + _maint(b) + float(r.get("energy_req",0)) * GRID + _transport(r)
			var q_single := (scost * (1.0 - SINGLE_LOSS_FRAC) - byval) / price
			# floor uses the ACTUAL cheapest-route integrated cost (matches the table's `full` column)
			var q_full := ((1.0 + FULL_FLOOR_MARGIN) * _recipe_cost(r) + _transport_out(r) - byval) / price
			newq = maxf(q_single, q_full)
		else:
			# raw extractors sized on GRID base (game-start, so base-profitable + -50% tips them
			# negative); everything else pins its integrated (own-power) margin to its tier.
			var e_rate := GRID if tier3 == "raw" else _own_power_per_unit
			var cost := _labour(b) + _maint(b) + float(r.get("energy_req",0)) * e_rate
			for i in r.get("inputs", []):
				cost += float(i.qty) * _unit_cost_pinned(str(i.good_id))
			newq = (cost * (1.0 + _tier_margin(tier3)) - byval) / price
		print("QTYSOLVE|%s|%s|%.3f|%d" % [str(r.get("recipe_id","")), primary, newq, int(r.get("output_qty",0))])
	# INPUT PASS: match each input quantity to 0.5/1/1.5/2x the producer's batch (the output_qty of
	# whatever makes that good). Under-sized inputs get raised toward the batch, which fattens the
	# integration lift of low-lift recipes; well-sized inputs barely move. Patched, then outputs re-solved.
	print("\n===== INPUTSOLVE: input_qty -> nearest 0.5/1/1.5/2x of producer batch =====")
	var batch := {}
	for r in Catalog.all_recipes():
		for o in r.get("outputs", []):
			var g := str(o.good_id)
			batch[g] = maxf(float(batch.get(g, 0.0)), float(o.qty))
	for r in Catalog.all_recipes():
		var ins: Array = r.get("inputs", [])
		if ins.is_empty(): continue
		var parts: Array = []
		for i in ins:
			var b: float = float(batch.get(str(i.good_id), 0.0))
			var cur := float(i.qty)
			var nq := cur
			if b > 0.0:
				var best := 1.0e18
				for k in [0.5, 1.0, 1.5, 2.0]:
					if absf(b * k - cur) < best:
						best = absf(b * k - cur); nq = b * k
			parts.append("%s:%d" % [str(i.get("internal_name", "")), int(round(nq))])
		print("INPUTSOLVE|%s|%s" % [str(r.get("recipe_id","")), ",".join(parts)])
	# Per-recipe profitability under each lever (full output; power sold to grid in the standalone
	# columns, self-supplied at base in the integrated ones). Mines also carry a -50% start penalty.
	print("\nRECIPECSV|recipe_id|recipe|building|tier|output|qty|out_value|single|single_with_power|two_building|full_integration|gated")
	for r in Catalog.all_recipes():
		var outs2: Array = r.get("outputs", [])
		if outs2.is_empty(): continue
		var prim := str(r.get("output_good_id", str(outs2[0].good_id)))
		var bb := _bld(r)
		var lm := _run_cost(r)
		var en := float(r.get("energy_req", 0))
		var rev_g := _out_value(r, true)
		var rev_b := _out_value(r, false)
		var ibuy := _input_buy(r)
		var iown := _input_own(r)
		var single := rev_g - ibuy - _transport(r) - lm - en * GRID
		var wpow := rev_g - ibuy - _transport(r) - lm - en * _own_power_per_unit
		var twob := rev_b - iown - _transport_out(r) - lm - en * GRID
		var full := rev_b - iown - _transport_out(r) - lm - en * _own_power_per_unit
		print("RECIPECSV|%s|%s|%s|%s|%s|%d|%.2f|%.2f|%.2f|%.2f|%.2f|%s" % [str(r.get("recipe_id","")), str(r.get("display_name","?")), str(bb.get("internal_name","?")), _good_tier(prim), str(outs2[0].get("internal_name", prim)), int(r.get("output_qty",0)), rev_b, single, wpow, twob, full, "Y" if str(r.get("tech_unlock_req",""))!="" else ""])
	# PRICESOLVE: output price that makes the LONE building break even (single=0). Ungated, non-mine.
	# flatprice < current => good is OVERPRICED -> its base recipe profits standalone (rule violation).
	print("\nPRICESOLVE|recipe|good|flat_price|current_price|tier")
	for r in Catalog.all_recipes():
		if str(r.get("tech_unlock_req","")) != "": continue
		if _is_mining(r): continue
		var outs3: Array = r.get("outputs", [])
		if outs3.is_empty(): continue
		var prim3 := str(r.get("output_good_id", str(outs3[0].good_id)))
		if _is_power(prim3): continue
		var oq := 0.0
		for o in outs3:
			if str(o.good_id) == prim3: oq += float(o.qty)
		if oq <= 0.0: continue
		var byval3 := 0.0
		for o in outs3:
			if str(o.good_id) != prim3: byval3 += float(o.qty) * _sell(str(o.good_id))
		var cost3 := _input_buy(r) + _run_cost(r) + float(r.get("energy_req",0))*GRID + _transport(r)
		print("PRICESOLVE|%s|%s|%.3f|%.3f|%s" % [str(r.get("display_name","")), prim3, (cost3 - byval3)/oq, _sell(prim3), _good_tier(prim3)])
	# motor-chain net under the new model
	var chain := {"Coal Mining":1,"Iron Mining":1,"Copper Mining":1,"Pig Iron Smelting":1,"Steelmaking":1,"Copper Blistering":1,"Copper Wire Drawing":1,"Motor Manufacture":2,"Power Production":1,"Water Pumping":1}
	var ctot := 0.0
	for r in Catalog.all_recipes():
		var nm := str(r.get("display_name",""))
		if not chain.has(nm): continue
		var cnt: int = chain[nm]
		ctot += _run_cost(r) * cnt
		print("CHAINROW|%s|x%d|pct=%.0f|labour=%.1f|maint=%.1f|runcost=%.1f" % [nm, cnt, _pct(r)*100.0, _labour_r(r), _maint(_bld(r)), _run_cost(r)])
	print("CHAINTOTAL|runcost=%.1f" % ctot)
	get_tree().quit(0)

func _sell(g: String) -> float: return float(Catalog.get_good(g).get("base_price", 0.0))
func _buy(g: String) -> float: return _sell(g) * 1.05
func _bld(r: Dictionary) -> Dictionary: return Catalog.get_building(str(r.get("building_id","")))
func _transport_out(r: Dictionary) -> float:
	var t := 0.0
	for o in r.get("outputs", []): t += float(o.qty) * _tclass_rate(str(o.good_id))
	return t
func _out_value(r: Dictionary, grid_sell_power: bool) -> float:
	var v := 0.0
	for o in r.get("outputs", []):
		var g := str(o.good_id)
		v += float(o.qty) * (GRID_SELL if (_is_power(g) and grid_sell_power) else _sell(g))
	return v
func _input_buy(r: Dictionary) -> float:
	var c := 0.0
	for i in r.get("inputs", []): c += float(i.qty) * _buy(str(i.good_id))
	return c
func _input_own(r: Dictionary) -> float:
	var c := 0.0
	for i in r.get("inputs", []): c += float(i.qty) * _unit_cost(str(i.good_id))
	return c
func _labour(b: Dictionary) -> float:
	return LABOUR_PCT * _build_mat_value(b)
func _maint(b: Dictionary) -> float:
	return MAINT_PCT * _build_mat_value(b)
func _build_mat_value(b: Dictionary) -> float:
	var v := 0.0
	for m in b.get("materials", []):
		var gid := str(Catalog.get_good_by_internal_name(str(m.get("name",""))).get("id",""))
		if gid != "": v += float(m.get("qty",0)) * _sell(gid)
	return v
func _tier(r: Dictionary) -> String:
	var outs: Array = r.get("outputs", [])
	if outs.is_empty(): return "other"
	var gid := str(r.get("output_good_id", str(outs[0].good_id)))
	var g := Catalog.get_good(gid)
	var gt := str(g.get("good_type", ""))
	if gt == "finished" and float(g.get("base_price", 0.0)) >= APEX_PRICE: return "apex"
	return gt if gt != "" else "other"
func _k(r: Dictionary) -> float:
	match _tier(r):
		"raw": return K_RAW
		"intermediate": return K_INTER
		"finished": return K_FINISHED
		"apex": return K_APEX
		_: return K_OTHER
func _value_add(r: Dictionary) -> float:
	var v := 0.0
	for o in r.get("outputs", []): v += float(o.qty) * _sell(str(o.good_id))
	for i in r.get("inputs", []): v -= float(i.qty) * _sell(str(i.good_id))
	return v
func _good_tier(gid: String) -> String:
	var g := Catalog.get_good(gid)
	var gt := str(g.get("good_type", ""))
	if gt == "finished" and float(g.get("base_price", 0.0)) >= APEX_PRICE: return "apex"
	return gt if gt != "" else "other"
func _tier_margin(t: String) -> float:   # target integrated margin per tier (the gradient)
	match t:
		"raw": return 0.15
		"intermediate": return 0.25
		"finished": return 0.40
		"apex": return 1.00
		_: return 0.20
# A good's integrated unit cost = its price discounted by its own tier's margin (because every
# producer is pinned to that margin). Deterministic, so QTYSOLVE needs no fixpoint iteration.
func _unit_cost_pinned(gid: String) -> float:
	return _sell(gid) / (1.0 + _tier_margin(_good_tier(gid)))
# Running cost (labour+maint). With the formula on, derive it; else read the building data.
func _run_cost(r: Dictionary) -> float:
	return _labour_r(r) + _maint(_bld(r))
func _pct(r: Dictionary) -> float:
	for o in r.get("outputs", []):
		if _is_power(str(o.good_id)): return 0.05   # power stays cheap — it's the integration lever
	if _is_mining(r): return 0.05                    # mines base-profitable; -50% deposit penalty controls start
	for o in r.get("outputs", []):                   # crude + processed oil are the profitable refining tier (deposit+glut governed)
		if str(Catalog.get_good(str(o.good_id)).get("internal_name","")) in ["processed_oil", "refined_ree", "lithium_carbonate"]: return 0.05
	var bm := _build_mat_value(_bld(r))
	if bm <= 0.0: return 0.05
	# labour % that breaks the LONE building even at market prices (single ~ 0), clamped 5-25%
	var target := (_out_value(r, true) - _input_buy(r) - float(r.get("energy_req",0))*GRID - _transport(r)) / bm - MAINT_PCT
	return clampf(target, 0.05, 0.25)
func _labour_r(r: Dictionary) -> float:
	return _pct(r) * _build_mat_value(_bld(r))
func _tclass_rate(g: String) -> float:
	var cls: String = Catalog.get_transport_class(g) if Catalog.has_method("get_transport_class") else "standard"
	return float(EconomyConfig.TRANSPORT_COST_PER_UNIT_PER_TURN_BY_WEIGHT_CLASS.get(cls, 0.02)) * float(EconomyConfig.TRANSPORT_MODE_COST_MULT.get("roads", 1.0))
func _transport(r: Dictionary) -> float:
	var t := 0.0
	for i in r.get("inputs", []): t += float(i.qty) * _tclass_rate(str(i.good_id))
	for o in r.get("outputs", []): t += float(o.qty) * _tclass_rate(str(o.good_id))
	return t
func _revenue(r: Dictionary, out_mult := 1.0) -> float:
	var v := 0.0
	for o in r.get("outputs", []): v += float(o.qty) * out_mult * _sell(str(o.good_id))
	return v
func _is_mining(r: Dictionary) -> bool:
	return str(r.get("recipe_type","")).to_lower().contains("mining") or str(r.get("requirements","")).contains("deposit")
func _is_power(g: String) -> bool:
	return (Catalog.get_transport_class(g) if Catalog.has_method("get_transport_class") else "") == "electricity"
func _naked(r: Dictionary, out_mult := 1.0) -> float:
	var rev := 0.0
	for o in r.get("outputs", []):
		var g := str(o.good_id)
		rev += float(o.qty) * out_mult * (GRID_SELL if _is_power(g) else _sell(g))
	var inc := 0.0
	for i in r.get("inputs", []): inc += float(i.qty) * _buy(str(i.good_id))
	return rev - inc - _transport(r) - _run_cost(r) - float(r.get("energy_req",0))*GRID

func _compute_own_power_cost() -> float:
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id",""))
	var water := str(Catalog.get_good_by_internal_name("pure_water").get("id",""))
	var pp := Catalog.get_building_by_internal_name("power_plant") if Catalog.has_method("get_building_by_internal_name") else Catalog.get_building("b_003")
	return (20.0*_buy(coal) + 20.0*_buy(water) + _labour(pp) + _maint(pp)) / 100.0

# Cheapest integrated unit cost of a good, memoised. Seeding the memo with the market price both
# breaks recipe cycles and supplies the fallback when nothing produces the good on-site.
func _unit_cost(gid: String) -> float:
	if _ucost.has(gid): return _ucost[gid]
	_ucost[gid] = _buy(gid)
	var best: float = _buy(gid)
	for f in _producers.get(gid, []):
		var fout := 0.0
		for o in f.get("outputs", []):
			if str(o.good_id) == gid: fout += float(o.qty)
		if fout <= 0.0: continue
		var c := _recipe_cost(f) / fout
		if c < best: best = c
	_ucost[gid] = best
	return best
func _recipe_cost(r: Dictionary) -> float:
	# this building's run cost + own power + the cheapest integrated cost of every input
	var cost := _run_cost(r) + float(r.get("energy_req",0)) * _own_power_per_unit
	for i in r.get("inputs", []):
		cost += float(i.qty) * _unit_cost(str(i.good_id))
	return cost
