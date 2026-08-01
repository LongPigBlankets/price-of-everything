extends Node
## Dev probe: does the new 1x price-impact band actually BITE in play?
##
## The e2e harness showed zero change from adding it (748/2 before and after, coal runway
## identical at -9.2), which is consistent either with "no regression" OR with "the band is
## inert". This distinguishes them: drive a good's net volume to a fixed multiple of its base
## output for 20 turns and read the accumulated impact back.
##   <godot> --headless --path . res://tools/price_impact_probe.tscn --quit-after 900

func _ready() -> void:
	await get_tree().process_frame
	var gid := ""
	var base := 0
	for g in Catalog.all_goods():
		var b: int = Catalog.base_output_for_good(str((g as Dictionary).get("id", "")))
		if b >= 20:
			gid = str((g as Dictionary).get("id", ""))
			base = b
			break
	if gid == "":
		print("PROBE: no good with a usable base output")
		get_tree().quit(1)
		return
	print("good=%s base_output=%d  bands: 1x=%d 2x=%d 4x=%d 10x=%d"
		% [gid, base, base, base * 2, base * 4, base * 10])
	for mult in [0.9, 1.5, 2.5, 5.0]:
		var qty := int(round(float(base) * mult))
		MarketState.impact_pct.erase(gid)
		for _t in 20:
			MarketState._turn_sold = {gid: qty}
			MarketState._turn_bought = {}
			MarketState._tick_impact(gid)
		var sold := MarketState.get_impact_pct(gid)
		# Same volume, bought instead of sold — the deficit side must mirror it.
		MarketState.impact_pct.erase(gid)
		for _t in 20:
			MarketState._turn_sold = {}
			MarketState._turn_bought = {gid: qty}
			MarketState._tick_impact(gid)
		var bought := MarketState.get_impact_pct(gid)
		print("  %4.1fx base (%3d u/turn) x20 turns -> selling %+6.2f%%   buying %+6.2f%%"
			% [mult, qty, sold, bought])
	MarketState.impact_pct.erase(gid)
	MarketState._turn_sold = {}
	MarketState._turn_bought = {}
	get_tree().quit(0)
