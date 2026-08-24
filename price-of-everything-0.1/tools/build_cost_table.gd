extends Node
## Dev tool: every building's construction cost at TURN 1 market prices, the way the
## Construct panel computes it — cash leg + the resolved material kit valued at the buy
## price. Freight and warehousing are site-dependent and excluded, exactly as the panel's
## "+ freight and warehousing" label says.
##   Godot --headless --path . res://tools/build_cost_table.tscn --quit-after 400
## Writes a TSV to user://build_costs_turn1.tsv and prints it.

func _ready() -> void:
	await _settle(6)
	var rows: Array = []
	for b_variant: Variant in Catalog.all_buildings():
		var b: Dictionary = b_variant
		var bid := str(b.get("id", ""))
		if bid == "":
			continue
		var cash := maxf(0.0, float(b.get("base_price", 0.0)))
		var kit := Construction.requirements_for(bid)
		var materials := Construction.market_purchase_value(bid)
		var parts: Array = []
		var units := 0
		for gid_variant: Variant in kit:
			var gid := str(gid_variant)
			var qty := int(kit[gid_variant])
			units += qty
			var unit_price := MarketState.get_buy_price(gid)
			if unit_price <= 0.0:
				unit_price = Catalog.get_base_price(gid)
			parts.append("%dx %s @%.2f = %.0f" % [
				qty, Catalog.get_display_name(gid), unit_price, float(qty) * unit_price])
		rows.append({
			"name": str(b.get("display_name", bid)),
			"id": bid,
			"category": str(b.get("category", "")),
			"land": int(round(float(b.get("tile_size_used", 1)))),
			"cash": cash,
			"materials": materials,
			"total": cash + materials,
			"units": units,
			"kit": ", ".join(parts),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["total"]) > float(b["total"]))

	var out := "name\tid\tcategory\tland\tcash\tmaterials\ttotal\tcash_pct\tkit_units\tkit\n"
	print("[COST] %-30s %8s %10s %10s %6s %5s %5s" % [
		"BUILDING", "CASH", "MATERIALS", "TOTAL", "CASH%", "UNITS", "LAND"])
	for row_variant: Variant in rows:
		var r: Dictionary = row_variant
		var pct := 100.0 * float(r.cash) / maxf(1.0, float(r.total))
		print("[COST] %-30s %8.0f %10.0f %10.0f %5.1f%% %5d %5d" % [
			str(r.name), float(r.cash), float(r.materials), float(r.total), pct,
			int(r.units), int(r.land)])
		out += "%s\t%s\t%s\t%d\t%.2f\t%.2f\t%.2f\t%.1f\t%d\t%s\n" % [
			str(r.name), str(r.id), str(r.category), int(r.land), float(r.cash),
			float(r.materials), float(r.total), pct, int(r.units), str(r.kit)]
	var f := FileAccess.open("user://build_costs_turn1.tsv", FileAccess.WRITE)
	if f != null:
		f.store_string(out)
		f.close()
	print("[COST] %d buildings; wrote user://build_costs_turn1.tsv" % rows.size())
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
