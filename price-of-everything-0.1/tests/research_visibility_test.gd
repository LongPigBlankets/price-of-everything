extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
	else:
		print("PASS: ", label)
func _ready() -> void:
	MatchState.reset()
	var panel = load("res://scripts/research_panel.gd").new()
	panel.call("_load_unlock_rows")
	var rows: Array = panel.get("_unlock_rows")
	for title in ["Methane Pyrolysis", "Enzyme Screening", "Bioplastic Precursors", "Cell Culture Automation", "Zero-Liquid Discharge"]:
		panel.set("_search_query", title)
		for exact in ["", title]:
			panel.set("_search_exact_title", exact)
			check(panel.call("_category_unlocks", "Extraction").is_empty(), "Hidden demo search: " + title + " exact=" + exact)
		MatchState.grant_unlock(title)
		check(not MatchState.is_unlocked(title), "Hidden grant: " + title)
	for row in rows:
		var title: String = row.title
		if row.category == "Recycling" or row.research_node_id in ["research_people_008", "research_people_009", "research_people_010", "research_people_011"]:
			panel.set("_search_query", title)
			for exact in ["", title]:
				panel.set("_search_exact_title", exact)
				check(panel.call("_category_unlocks", "Extraction").is_empty(), "Flagged search: " + title)
			check(not MatchState.is_node_available(title), "Flagged availability: " + title)
			MatchState.grant_unlock(title)
			check(not MatchState.is_unlocked(title), "Flagged grant: " + title)
	MatchState.recycling_unlocked = true
	MatchState.advisors_unlocked = true
	for row in rows:
		panel.set("_search_query", row.title)
		panel.set("_search_exact_title", row.title)
		check(panel.call("_category_unlocks", "Extraction").size() == 1, "Exact visible search: " + row.title)
	var counts := {}
	for row in rows:
		counts[row.category] = int(counts.get(row.category, 0)) + 1
	check(counts.get("Manufacturing") == 21 and counts.get("Vehicle Production") == 19, "Manufacturing / vehicle split")
	check(counts.get("Combustion Power") == 10 and counts.get("Renewable Power") == 31, "Power split")
	check(MatchState.get_unlock_def("Precision Machining").category == "Vehicle Production", "Gameplay uses new category")
	check(not MatchState.is_tier_available("Vehicle Production", "II"), "Vehicle tier II initially locked")
	MatchState.grant_unlock("Precision Machining")
	check(MatchState.is_tier_available("Vehicle Production", "II"), "Vehicle tier II opens at the configured one-node threshold")
	check(not MatchState.is_tier_available("Manufacturing", "II"), "Vehicle progress does not open manufacturing")
	for row in rows:
		var parts: PackedStringArray = panel.call("_requirement_details", row).split("\n")
		check(parts.size() >= 2 and parts[parts.size()-2].begins_with("Prerequisites:") and parts[parts.size()-1].begins_with("Tier "), "Separate requirements: " + row.title)
	for row in rows:
		if not MatchState.is_research_visible(row): continue
		var spec: Dictionary = panel.call("_presentation", row)
		check(not spec.is_empty() and not spec.get("effects", []).is_empty(), "Icon and effects: " + row.title)
		for effect in spec.get("effects", []):
			check(effect[0] != "merge" or effect[1] == "", "Recipe emblem has no plus or arrow: " + row.title)
		var wording: String = panel.call("_condition_text", row)
		check(not "_" in wording and not "|" in wording, "Readable condition: " + row.title)
		var compact: String = panel.call("_collapsed_condition", row)
		for phrase in ["straight", "consecutive", "at 100%", "full capacity"]:
			check(not phrase in compact and not phrase in wording, "Condition omits redundant running qualifier: " + row.title)
		var font_size: int = panel.call("_condition_font_size", row, 289.0)
		var lines: Array = panel.call("_wrapped_text_lines", panel.BODY_FONT, compact, 289.0, font_size)
		check(lines.size() <= 2, "Collapsed condition fits two lines: " + row.title + " / " + compact)
		var disclosure: Rect2 = panel.call("_requirement_row_rect", Rect2(Vector2.ZERO, panel.UNLOCK_SIZE), row)
		check(disclosure.size.y == (38.0 if lines.size() > 1 else 24.0), "Adaptive disclosure: " + row.title)
	var slot := Rect2(0, 0, 110, 80)
	var top: Rect2 = panel.call("_effect_badge_rect", slot, 0, 2)
	var bottom: Rect2 = panel.call("_effect_badge_rect", slot, 1, 2)
	var art: Rect2 = panel.call("_research_art_rect", slot)
	check(art.size == Vector2(66, 66), "Wider slot keeps original square artwork size")
	check(top.position.x >= art.end.x and bottom.position.x >= art.end.x and top.end.y < bottom.position.y, "Emblems stack beside the artwork")
	var arrow: Rect2 = panel.call("_effect_overlay_rect", top)
	check(arrow.intersects(top) and arrow.position.x < top.position.x and arrow.position.x >= art.end.x and slot.encloses(arrow), "Arrow overlaps emblem corner within its gutter")
	for category in panel.CATEGORIES:
		panel.set("_search_query", "")
		panel.set("_search_exact_title", "")
		panel.set("_selected_category", category)
		var category_rows: Array = panel.call("_category_unlocks", category)
		var layout: Dictionary = panel.call("_layout_unlocks", category_rows)
		var titles: Array = layout.keys()
		var no_overlap := true
		for i in titles.size():
			for j in range(i + 1, titles.size()):
				if layout[titles[i]].intersects(layout[titles[j]]): no_overlap = false
		check(no_overlap, "Subject lanes have no overlapping cards: " + category)
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	CostSolver.last_result = {"per_building": {}, "per_good": {}}
	var definition: Dictionary = MatchState.get_unlock_def("Pulverised Carbon Injection")
	check(MatchState.unlock_condition_text("Pulverised Carbon Injection") == "Run 10 buildings with steelmaking recipes profitably", "Carbon Injection wording")
	check(definition.action == "Run Recipe Profitable" and definition.qty == 10, "Carbon Injection uses recipe profitability gate")
	for i in 10:
		var iid := "steel_profit_" + str(i)
		MatchState.buildings[iid] = {"instance_id": iid, "building_id": "b_002", "recipe_id": "r_003", "owner": MatchState.LOCAL_PLAYER}
		Production.full_output_streak_by_building[iid] = 1
		CostSolver.last_result.per_building[iid] = {"unit_cost": 0.0, "output_good_id": "g_006"}
		if i == 8:
			check(not MatchState._live_condition_met(definition), "Nine profitable steelmaking buildings do not unlock")
	check(MatchState._live_condition_met(definition), "Ten profitable steelmaking buildings meet the condition")
	var last := "steel_profit_9"
	CostSolver.last_result.per_building[last].unit_cost = MarketState.get_price("g_006") + 1.0
	check(not MatchState._live_condition_met(definition), "Loss-making steel plant does not count")
	CostSolver.last_result.per_building[last].unit_cost = 0.0
	MatchState.buildings[last].recipe_id = "r_001"
	check(not MatchState._live_condition_met(definition), "Other profitable recipes do not count")
	MatchState.buildings[last].recipe_id = "r_003"
	MatchState.buildings[last].owner = "npc"
	check(not MatchState._live_condition_met(definition), "NPC steelmaking does not count")
	MatchState.buildings[last].owner = MatchState.LOCAL_PLAYER
	MatchState.paused_buildings[last] = true
	check(not MatchState._live_condition_met(definition), "Paused steelmaking does not count")
	MatchState.paused_buildings.clear()
	Production.full_output_streak_by_building[last] = 0
	check(not MatchState._live_condition_met(definition), "A steel recipe assigned to an idle plant does not count")
	panel.free()
	print("RESEARCH FAILURES: ", failures)
	get_tree().quit(1 if failures else 0)
