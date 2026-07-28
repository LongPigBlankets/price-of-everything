extends Node
## Prints the carbon figures the ENGINE actually derives, so the offline model in
## tools/carbon_intensity.py can be checked against the thing that ships.
func _ready() -> void:
	await get_tree().process_frame
	print("=== ENGINE CARBON ===")
	print("%-22s %8s %10s %10s %10s" % ["good", "levy", "embodied", "price now", "price P3"])
	for name in ["coal", "pet_coke", "crude_oil", "processed_oil", "ethylene", "biomass",
			"graphite", "power", "steel", "plastics", "pvc", "fuels", "concrete", "ice_car"]:
		var g: Dictionary = Catalog.get_good_by_internal_name(name)
		if g.is_empty():
			print("%-22s MISSING" % name)
			continue
		var gid := str(g.get("id", ""))
		var emb := Catalog.embodied_carbon(gid)
		var base := float(g.get("base_price", 0.0))
		print("%-22s %8.2f %10.3f %10.3f %10.3f" % [name,
			float(g.get("co2_tax_multiplier", 0.0)), emb, base,
			base + emb * EconomyConfig.CO2_TAX_RATE * 3.5])
	print("")
	print("=== GRID CARBON INTENSITY x CARBON LEVY -> price of imported power ===")
	var pw := str(Catalog.get_good_by_internal_name("power").get("id", ""))
	var emb := Catalog.embodied_carbon(pw)
	print("%-8s %10s %10s %12s %12s" % ["turn", "grid mix", "levy x", "carbon/MW", "grid £/MW"])
	for t in [1, 70, 91, 101, 150, 165, 230, 300]:
		var mix := PolicyState.grid_carbon_intensity(t)
		var sc := PolicyState.co2_tax_scale(t)
		var carbon := emb * EconomyConfig.CO2_TAX_RATE * sc * mix
		print("%-8d %10.2f %10.2f %12.4f %12.4f"
			% [t, mix, sc, carbon, EconomyConfig.GRID_BUY_PRICE + carbon])
	get_tree().quit()
