extends Node
## Verifies the Metal Magnate (port layout) runs from turn 1 with money rising
## every turn, then dumps the FULL cost decomposition at steady state.

const START := "res://data/starts/metal_magnate.json"
const FURN_TILE := "tile_5_10"

func _f(v) -> float: return float(v)

func _ready() -> void:
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var frames := 0
	while frames < 4000 and main.get("build_complete") != true:
		await get_tree().process_frame
		frames += 1
	# realistic DECIDE settle
	for _i in range(30):
		await get_tree().process_frame

	# label player buildings
	var labels := {}
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(b): continue
		labels[iid] = "%s/%s@%s" % [str(b.get("building_id","")), str(b.get("recipe_id","")), str(b.get("tile_id",""))]

	print("=== buildings ===")
	for iid in labels: print("  ", labels[iid])
	print("start money = ", int(MatchState.money))

	var prev := int(MatchState.money)
	var min_delta := 999999
	for t in range(30):
		TurnManager.commit_turn()
		var g := 0
		while g < 300 and TurnManager.is_resolving:
			await get_tree().process_frame
			g += 1
		await get_tree().process_frame
		var m := int(MatchState.money)
		var ran := 0
		for iid in labels:
			if Production.last_turn_run.has(iid): ran += 1
		if t >= 1:
			min_delta = mini(min_delta, m - prev)
		print("[T%02d] money=%d (d%+d) ran=%d/4 | ore@f=%d coal@f=%d water@f=%d" % [
			int(TurnManager.current_turn), m, m - prev, ran,
			int(Stockpile.get_at_tile(FURN_TILE, "g_002")),
			int(Stockpile.get_at_tile(FURN_TILE, "g_001")),
			int(Stockpile.get_at_tile(FURN_TILE, "g_009"))])
		if int(TurnManager.current_turn) == 11 or int(TurnManager.current_turn) == 29:
			_dump_costs()
		prev = m
	print("MIN per-turn delta over run = %+d (>=0 means never dips)" % min_delta)
	get_tree().quit(0)

func _dump_costs() -> void:
	var s: Dictionary = Production.last_turn_summary
	print("\n=== STEADY-STATE COST DECOMPOSITION (turn %d) ===" % int(TurnManager.current_turn - 1))
	print("  money_in  = %.2f" % _f(s.get("money_in", 0.0)))
	print("    goods_sales_revenue = %.2f" % _f(s.get("goods_sales_revenue", 0.0)))
	print("    power_sales_revenue = %.2f" % _f(s.get("power_sales_revenue", 0.0)))
	print("    green_subsidy_recv  = %.2f" % _f(s.get("green_subsidy_received", 0.0)))
	print("  money_out = %.2f" % _f(s.get("money_out", 0.0)))
	var comps := {
		"maintenance_paid": s.get("maintenance_paid", 0.0),
		"labour_paid": s.get("labour_paid", 0.0),
		"goods_purchased_cost (market inputs)": s.get("goods_purchased_cost", 0.0),
		"transport_paid": s.get("transport_paid", 0.0),
		"power_purchase_cost (grid)": s.get("power_purchase_cost", 0.0),
		"warehousing_paid (storage fee)": s.get("warehousing_paid", 0.0),
		"advisor_paid": s.get("advisor_paid", 0.0),
		"interest_paid": s.get("interest_paid", 0.0),
		"taxes_paid": s.get("taxes_paid", 0.0),
		"dividends_paid": s.get("dividends_paid", 0.0),
		"profit_sharing_paid": s.get("profit_sharing_paid", 0.0),
		"carbon_tax_paid": s.get("carbon_tax_paid", 0.0),
	}
	var total := 0.0
	for k in comps:
		print("    %-38s = %.2f" % [k, _f(comps[k])])
		total += _f(comps[k])
	print("    %-38s = %.2f" % ["SUM of components", total])
	print("  net = money_in - money_out = %.2f" % (_f(s.get("money_in",0.0)) - _f(s.get("money_out",0.0))))

	print("  --- per-building maintenance ---")
	var mbt: Dictionary = s.get("maintenance_by_type", {})
	for bt in mbt: print("    %s: count=%d amount=%.2f" % [bt, int((mbt[bt] as Dictionary).get("count",0)), _f((mbt[bt] as Dictionary).get("amount",0.0))])
	print("  --- per-building labour ---")
	var lbt: Dictionary = s.get("labour_by_type", {})
	for bt in lbt: print("    %s: count=%d amount=%.2f" % [bt, int((lbt[bt] as Dictionary).get("count",0)), _f((lbt[bt] as Dictionary).get("amount",0.0))])
	print("  --- market input purchases by type ---")
	var gbt: Dictionary = s.get("goods_purchased_by_type", {})
	for bt in gbt: print("    %s: %.2f" % [bt, _f((gbt[bt] as Dictionary).get("amount", gbt[bt])) if typeof(gbt[bt])==TYPE_DICTIONARY else _f(gbt[bt])])
	print("  --- purchased_cost by good ---")
	var pc: Dictionary = s.get("purchased_cost", {})
	for gid in pc: print("    %s: %.2f" % [str(gid), _f(pc[gid])])
	print("  power: supply=%d demand=%d grid_bought=%d grid_sold=%d\n" % [
		int(s.get("power_supply",0)), int(s.get("power_demand",0)),
		int(s.get("grid_bought",0)), int(s.get("grid_sold",0))])
