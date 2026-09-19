extends RefCounted
## Ledger endpoints, resolved per good so mixed and split routes remain visible.
const Service := preload("res://scripts/middleman_service.gd")
const Readout := preload("res://scripts/building_readout.gd")

static func endpoints(b: Dictionary, side: String) -> Array:
	var result: Array = []
	var iid := str(b.instance_id)
	var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
	var sources: Array = Readout.input_sources(b, recipe) if side == "input" else []
	for item: Dictionary in recipe.get("inputs" if side == "input" else "outputs", []):
		var gid := str(item.good_id)
		if str(Catalog.get_good(gid).get("internal_name", "")) == "power":
			_add(result, "grid", "Electricity grid")
		elif Service.supplies_good(iid, gid) if side == "input" else Service.buys_output(iid, gid):
			_add(result, "middleman", "Logistics Intermediary")
		elif side == "input":
			var selected := str(b.get("logistics_input_sources", {}).get(gid, "auto"))
			if selected != "auto":
				_add(result, "stockpile", "Tile %s Stockpile" % tile_label(selected))
				continue
			var found := false
			for source: Dictionary in sources:
				if str(source.good_id) != gid: continue
				var producer := BuildingState.get_building(str(source.instance_id))
				_add(result, str(producer.get("building_id", "")), "%s on tile %s" % [source.building_name, tile_label(str(source.tile_id))])
				found = true
			if not found:
				if MatchState.is_input_tile_only(iid, gid) or not bool(Catalog.get_good(gid).get("is_buyable", false)):
					_add(result, "stockpile", "Tile %s Stockpile" % tile_label(str(b.tile_id)))
				else: _add(result, "port", "Global Market")
		else:
			var splits := MatchState.get_output_split_destinations(iid, gid)
			if not splits.is_empty():
				for destination: Dictionary in splits:
					_add(result, "stockpile", "Tile %s Stockpile" % tile_label(str(destination.tile_id)))
			else:
				var tile: Variant = Production._output_stockpile_coord(b, gid)
				if tile == null: _add(result, "port", "Global Market")
				else: _add(result, "stockpile", "Tile %s Stockpile" % tile_label(str(tile)))
	return result

static func _add(rows: Array, icon: String, label: String) -> void:
	if not rows.any(func(row: Dictionary) -> bool: return str(row.label) == label):
		rows.append({"icon":icon, "label":label})

static func tile_label(tile_id: String) -> String:
	var parts := tile_id.trim_prefix("tile_").split("_")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return "(%s, %s)" % [parts[0], parts[1]]
	return tile_id
