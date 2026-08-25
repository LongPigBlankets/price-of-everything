extends Node
## Dev tool: which BUILDINGS are locked behind research, and at what tier.
##
## Not "which research unlocks a recipe" — most of those add a second or third recipe to a
## building that already exists. This asks the question that matters for pacing: is there any
## recipe you can build this building for WITHOUT research? If not, the building does not
## appear in the Construct panel until that research lands, and its tier is the real cost.
##
##   Godot --headless --path . res://tools/building_gate_audit.tscn --quit-after 400

func _ready() -> void:
	await _settle(4)
	var tier_of: Dictionary = {}      # research title -> "I" / "II" / "III"
	var cat_of: Dictionary = {}
	var title_of: Dictionary = {}
	for d_variant: Variant in MatchState._unlock_defs:
		var d: Dictionary = d_variant
		# Recipes name their gate by research_node_id, buildings by title (and one legacy
		# short key, "hydro"), so index every handle a gate might use.
		for handle: String in [str(d.get("title", "")), str(d.get("node_id", "")),
				str(d.get("research_node_id", "")), str(d.get("id", ""))]:
			if handle == "":
				continue
			tier_of[handle] = str(d.get("rank", "?"))
			cat_of[handle] = str(d.get("category", "?"))
			title_of[handle] = str(d.get("title", ""))

	var rank_order := {"I": 1, "II": 2, "III": 3}
	var gated: Array = []
	var open_count := 0
	for b_variant: Variant in Catalog.all_buildings():
		var b: Dictionary = b_variant
		var bid := str(b.get("id", ""))
		var name := str(b.get("display_name", bid))
		if str(b.get("category", "")) == "infrastructure":
			continue

		# The building's own gate, if it has one.
		var building_req := str(b.get("required_research", ""))

		# Its recipes, and which of them need research.
		var recipes: Array = []
		var free_recipes: Array = []
		for r_variant: Variant in Catalog.all_recipes():
			var r: Dictionary = r_variant
			if str(r.get("building_id", "")) != bid:
				continue
			recipes.append(r)
			if str(r.get("tech_unlock_req", "")) == "":
				free_recipes.append(str(r.get("display_name", "")))

		if recipes.is_empty():
			continue   # no recipes at all (batteries, port) — not a production gate

		if building_req == "" and not free_recipes.is_empty():
			open_count += 1
			continue

		# Locked. The cheapest way in is the lowest-tier research among its gates.
		var gates: Array = []
		if building_req != "":
			gates.append(building_req)
		if free_recipes.is_empty():
			for r_variant: Variant in recipes:
				var req := str((r_variant as Dictionary).get("tech_unlock_req", ""))
				if req != "" and not gates.has(req):
					gates.append(req)
		var best := ""
		var best_rank := 99
		for g: String in gates:
			var rank: int = int(rank_order.get(str(tier_of.get(g, "?")), 99))
			if rank < best_rank:
				best_rank = rank
				best = g
		gated.append({
			"name": name, "id": bid, "gate": str(title_of.get(best, best)),
			"tier": str(tier_of.get(best, "?")), "cat": str(cat_of.get(best, "?")),
			"rank": best_rank, "gates": gates.size(), "recipes": recipes.size(),
		})

	gated.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rank"]) != int(b["rank"]):
			return int(a["rank"]) > int(b["rank"])
		return str(a["name"]) < str(b["name"]))

	print("[GATE] %d production buildings need no research at all" % open_count)
	print("[GATE] %d are locked behind research:" % gated.size())
	print("[GATE] %-6s %-28s %-38s %-22s %s" % ["TIER", "BUILDING", "CHEAPEST UNLOCK", "CATEGORY", "WAYS IN"])
	for row_variant: Variant in gated:
		var row: Dictionary = row_variant
		print("[GATE] %-6s %-28s %-38s %-22s %d of %d recipes" % [
			str(row["tier"]), str(row["name"]), str(row["gate"]), str(row["cat"]),
			int(row["gates"]), int(row["recipes"])])
	get_tree().quit(0)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
