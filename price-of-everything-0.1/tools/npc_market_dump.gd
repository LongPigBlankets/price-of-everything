extends Node
## Dump everything the offline NPC-market price model needs, as JSON:
##   <godot> --headless --path . res://tools/npc_market_dump.tscn --quit-after 600
## Written for the 2026-08 "what if rival production hit the market" analysis.
## Uses the engine's own Catalog / CompanyRankings / EconomyConfig so the offline
## model can't drift from ground truth (base outputs, seeded rival draws, bands).

const SEEDS: Array[int] = [1337, 90210, 555777]
const TURN_STEP := 5
const MAX_TURN := 300
const OUT_PATH := "/private/tmp/claude-501/-Users-crisu-Price-of-Everything/71201fef-5a6c-411c-8536-247bee2cf9ec/scratchpad/npc_market_dump.json"

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var goods: Array = []
	for g in Catalog.all_goods():
		var gid := str(g.get("id", ""))
		var base_out: int = Catalog.base_output_for_good(gid)
		# The recipe that defines base_out: largest-output visible recipe producing the good.
		var best: Dictionary = {}
		for r in Catalog.recipes_producing(gid):
			if Catalog.recipe_output_qty(r, gid) == base_out:
				best = r
				break
		var inputs: Array = []
		for inp in best.get("inputs", []):
			inputs.append({
				"good_id": str(inp.good_id),
				"internal_name": str(inp.internal_name),
				"qty": int(inp.qty),
			})
		goods.append({
			"id": gid,
			"internal_name": str(g.get("internal_name", "")),
			"display_name": str(g.get("display_name", "")),
			"base_price": float(g.get("base_price", 1.0)),
			"decay_rate": float(g.get("decay_rate", 0.0)),
			"goods_graph_tier": str(g.get("goods_graph_tier", "")),
			"base_output": base_out,
			"base_recipe_id": str(best.get("recipe_id", "")),
			"base_recipe_building": str(best.get("building_id", "")),
			"base_recipe_output_qty": (Catalog.recipe_output_qty(best, gid) if not best.is_empty() else 0),
			"base_recipe_energy": int(best.get("energy_req", 0)),
			"base_recipe_inputs": inputs,
		})
	var rivals: Dictionary = {}
	for seed in SEEDS:
		var per_good: Dictionary = {}
		for g in Catalog.all_goods():
			var gid := str(g.get("id", ""))
			if str(g.get("goods_graph_tier", "")) == "apex":
				continue
			if Catalog.base_output_for_good(gid) <= 0:
				continue
			var series: Array = []
			for i in range(CompanyRankings.RIVAL_COUNT):
				var row: Array = []
				var t := 0
				while t <= MAX_TURN:
					row.append(CompanyRankings._rival_good_output_for(int(seed), gid, i, t))
					t += TURN_STEP
				series.append(row)
			per_good[gid] = series
		rivals[str(seed)] = per_good
	var out := {
		"turn_step": TURN_STEP,
		"max_turn": MAX_TURN,
		"rival_count": CompanyRankings.RIVAL_COUNT,
		"increment_turns": CompanyRankings.GOODS_INCREMENT_TURNS,
		"increment_factors": CompanyRankings.GOODS_INCREMENT_FACTORS,
		"goods": goods,
		"rivals": rivals,
		"config": {
			"PRICE_IMPACT_LADDER": EconomyConfig.PRICE_IMPACT_LADDER,
			"FLOOR_PCT": EconomyConfig.PRICE_IMPACT_FLOOR_PCT,
			"CEILING_PCT": EconomyConfig.PRICE_IMPACT_CEILING_PCT,
			"RECOVERY_TURNS": EconomyConfig.PRICE_IMPACT_RECOVERY_TURNS,
			"THRESHOLD_INFLATION_STEP": EconomyConfig.IMPACT_THRESHOLD_INFLATION_STEP,
			"THRESHOLD_INFLATION_TURNS": EconomyConfig.IMPACT_THRESHOLD_INFLATION_TURNS,
			"MARKET_BUY_MARKUP": EconomyConfig.MARKET_BUY_MARKUP,
		},
	}
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[NPCDUMP] cannot open %s" % OUT_PATH)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(out))
	f.close()
	print("[NPCDUMP] wrote %s (%d goods, %d seeds)" % [OUT_PATH, goods.size(), SEEDS.size()])
	get_tree().quit()
