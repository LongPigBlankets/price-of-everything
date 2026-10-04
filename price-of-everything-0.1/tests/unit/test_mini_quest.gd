extends "res://tests/test_base.gd"

const FEATURE := "middleman"

func _test_modular_logistics_and_metal_magnate_trees_are_parallel() -> void:
	var ruleset := MatchState.ruleset.duplicate(true)
	var old_chain := MiniQuest.chain
	var old_done := MiniQuest.done.duplicate(true)
	var old_generic_done := MiniQuest.generic_done.duplicate(true)
	var old_generic_granted := MiniQuest.generic_granted.duplicate(true)
	MatchState.ruleset["start_id"] = "metal_magnate"
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	MiniQuest.chain = ""
	MiniQuest.done = {}
	var trees: Array = MiniQuest.mission_trees()
	_check(trees.size() == 2, "mission panel exposes generic and Metal Magnate trees together")
	_check(str((trees[0] as Dictionary).get("id", "")) == "logistics"
		and str((trees[1] as Dictionary).get("id", "")) == "magnate",
		"mission trees keep the generic branch separate from the start branch")
	var magnate_nodes: Array = (trees[1] as Dictionary).get("nodes", [])
	_check(magnate_nodes.size() == 2 and str((magnate_nodes[1] as Dictionary).get("parent", "")) == "steel",
		"Metal Magnate nodes render as a parent-child sequence")
	var generic_nodes: Array = (trees[0] as Dictionary).get("nodes", [])
	_check(generic_nodes.size() == 4 and (generic_nodes[3] as Dictionary).get("parents", []).size() == 2,
		"global surplus node joins tile stockpile and license prerequisites")
	MiniQuest.generic_done["middleman_contracts"] = true
	var mission_snapshot := MiniQuest.export_fields()
	MiniQuest.generic_done = {}
	MiniQuest.import_fields(mission_snapshot)
	_check(bool(MiniQuest.generic_done.get("middleman_contracts", false)), "modular mission progress survives its match-state round trip")
	MatchState.ruleset = ruleset
	MiniQuest.chain = old_chain
	MiniQuest.done = old_done
	MiniQuest.generic_done = old_generic_done
	MiniQuest.generic_granted = old_generic_granted


## The Logistics missions: their tile-stockpile reward is granted, and outside the intermediary ruleset (where
## every route is open from the start) they stay locked instead of all completing on turn one.
func _test_logistics_missions_grant_and_gate() -> void:
	var ruleset := MatchState.ruleset.duplicate(true)
	var old_generic_done := MiniQuest.generic_done.duplicate(true)
	var old_generic_granted := MiniQuest.generic_granted.duplicate(true)
	Modifiers.remove(MiniQuest.GENERIC_STOCKPILE_REWARD_ID)
	MiniQuest._grant_generic("tile_stockpile")
	var granted := false
	for m: Dictionary in Modifiers.active():
		if str(m.get("id", "")) == MiniQuest.GENERIC_STOCKPILE_REWARD_ID:
			granted = str(m.get("domain", "")) == "recipe_output" and is_equal_approx(float(m.get("pct", 0.0)), 5.0)
	_check(granted, "logistics: the tile stockpile mission grants its +5% output")
	Modifiers.remove(MiniQuest.GENERIC_STOCKPILE_REWARD_ID)
	MatchState.ruleset["logistics_model"] = "legacy"
	MiniQuest.generic_done = {}
	MiniQuest.generic_granted = {}
	MiniQuest._eval_generic({})
	_check(MiniQuest.generic_done.is_empty() and MiniQuest.generic_granted.is_empty(),
		"logistics: a game without the intermediary completes none of its missions on turn one")
	MatchState.ruleset = ruleset
	MiniQuest.generic_done = old_generic_done
	MiniQuest.generic_granted = old_generic_granted


func _test_mission_progress_counts_steps_and_research() -> void:
	var ruleset := MatchState.ruleset.duplicate(true)
	var old_chain := MiniQuest.chain
	var old_done := MiniQuest.done.duplicate(true)
	var old_shipped: Dictionary = ResearchState._middleman_shipments_by_good.duplicate(true)
	var old_profits: Array = ResearchState._recent_profits.duplicate()
	MatchState.ruleset["start_id"] = "metal_magnate"
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	MiniQuest.chain = "magnate"
	MiniQuest.done = {"steel": [true, false]}
	_check(MiniQuest.progress("steel") == Vector2i(1, 2), "a mission of two steps counts its steps")
	ResearchState._middleman_shipments_by_good = {"g_001": 500, "g_002": 120, "g_004": 40, "g_006": 10}
	_check(MiniQuest.progress("middleman_contracts") == Vector2i(460, 900),
		"Contracts counts each of the three best goods up to 300 units")
	ResearchState._recent_profits = [90.0, 20.0, 80.0, 76.0]
	_check(MiniQuest.progress("global_license") == Vector2i(2, 3), "the License counts profitable turns in a row")
	_check(MiniQuest.progress("tile_stockpile") == Vector2i.ZERO, "a mission asking for one thing shows no count")
	MatchState.ruleset = ruleset
	MiniQuest.chain = old_chain
	MiniQuest.done = old_done
	ResearchState._middleman_shipments_by_good = old_shipped
	ResearchState._recent_profits = old_profits


func _test_mission_slot_caps_its_title_and_collapses() -> void:
	var Slot := preload("res://scripts/ds2/mission_slot.gd")
	var slot: Control = Slot.new()
	var fs := roundi(22 * Slot.KEY_SCALE)
	slot.call("set_mission", Slot.REFERENCE_TITLE, Vector2i(0, 4))
	var ref_w: float = slot.call("ideal_width")
	slot.call("set_mission", "Ship your coal from the new mine to every tile that burns it", Vector2i(3, 10))
	_check(is_equal_approx(float(slot.call("ideal_width")), ref_w), "a title longer than the reference is capped at the reference's width")
	slot.call("set_mission", "Produce Steel", Vector2i(1, 2))
	_check(float(slot.call("ideal_width")) < ref_w, "a short title takes a narrower key")
	_check(Slot.ellipsize(Slot.REFERENCE_TITLE, 4000.0, fs) == Slot.REFERENCE_TITLE, "a title with room is printed whole")
	_check(str(Slot.ellipsize(Slot.REFERENCE_TITLE, 80.0, fs)).ends_with("…"), "a title without room is cut short with an ellipsis")
	slot.call("set_collapsed", true, 30.0)
	_check(is_equal_approx(float(slot.call("ideal_width")), ceilf(30.0 + Slot.GAP + Slot.track_size().x)),
		"collapsed, the slot is the icon's room and the track")
	slot.free()


func _test_mission_boards_data_is_sound() -> void:
	var known_domains := ["building_power", "maintenance", "market_price", "recipe_output", "transport_cost", "construction_rebate",
		"grid_buy_price", "grid_sell_price", "labour_headcount", "loan_interest", "purchase_cost", "road_rail_transport_cost", "tax_rate",
		"construction_materials", "transport_throughput"]
	var mission_verbs := MiniQuest.COUNTED_VERBS + ["Acquire", "Fast To Port", "Faster To Port", "Build Any Of", "Own Recipe", "Research",
		"Supply", "Sell On Market", "Mine Infinite", "Supply From Infinite", "Upgrade"]
	var ids := {}
	for raw: Variant in MiniQuest.board_definitions():
		var board := raw as Dictionary
		var groups := {}
		for node: Variant in board.get("nodes", []) as Array:
			var n := node as Dictionary
			var id := str(n.get("id", ""))
			_check(not ids.has(id), "station id %s is unique across boards" % id)
			ids[id] = true
			var cond: Dictionary = MiniQuest._station_condition(n)
			_check(mission_verbs.has(str(cond.action)) or ResearchState.condition_text(cond) != "", "station %s has a condition the game can check" % id)
			var reward := n.get("reward", {}) as Dictionary
			var mods: Array = (reward.get("modifiers", []) as Array).duplicate()
			if reward.has("modifier"):
				mods.append(reward.modifier)
			for m: Variant in mods:
				_check(known_domains.has(str((m as Dictionary).get("domain", ""))), "station %s rewards a modifier domain the game reads" % id)
			var g := str(n.get("choice", ""))
			if g != "":
				groups[g] = (groups.get(g, []) as Array) + [n.get("parents", [])]
		for g: Variant in groups:
			var alts: Array = groups[g]
			_check(alts.size() >= 2 and alts.all(func(p: Variant) -> bool: return p == alts[0]), "choice %s offers alternatives from one junction" % str(g))
	for raw: Variant in MiniQuest.board_definitions():
		for node: Variant in (raw as Dictionary).get("nodes", []) as Array:
			for parent: Variant in (node as Dictionary).get("parents", []) as Array:
				_check(ids.has(str(parent)), "station %s waits on a station that exists" % str((node as Dictionary).get("id", "")))


func _test_metal_magnate_plays_its_two_boards() -> void:
	var ruleset := MatchState.ruleset.duplicate(true)
	MatchState.ruleset["start_id"] = "metal_magnate"
	var boards: Array = MiniQuest.match_boards()
	_check(boards.size() == 2 and str((boards[0] as Dictionary).id) == "tutorial" and str((boards[1] as Dictionary).id) == "magnate",
		"Metal Magnate plays the Tutorial and its own board, nothing else")
	MatchState.ruleset["start_id"] = "glass_merchant"
	_check(not MiniQuest.has_match_boards(), "a start without boards keeps its own missions")
	MatchState.ruleset = ruleset


func _test_mission_board_choice_closes_the_other_branch() -> void:
	var old_done := MiniQuest.board_done.duplicate(true)
	var old_choices := MiniQuest.board_choices.duplicate(true)
	MiniQuest.board_done = {"gp_solar": true}
	MiniQuest.board_choices = {}
	_check(MiniQuest.board_node_state("gp_battery") == "active", "a station whose parents are done is open")
	_check(MiniQuest.board_node_state("gp_wind") == "locked", "a choice waits on its junction's station")
	MiniQuest.board_done["gp_battery"] = true
	_check(MiniQuest.board_node_state("gp_wind") == "choice" and MiniQuest.board_node_state("gp_firm") == "choice",
		"both branches wait on the points once the junction is reached")
	_check(MiniQuest.choose("gp_firm"), "throwing the points takes a branch")
	_check(MiniQuest.board_node_state("gp_wind") == "closed" and MiniQuest.board_node_state("gp_wind_run") == "closed",
		"the branch not taken closes, with every station after it")
	_check(not MiniQuest.choose("gp_wind"), "a choice is made once")
	var snap := MiniQuest.export_fields()
	MiniQuest.board_choices = {}
	MiniQuest.import_fields(snap)
	_check(str(MiniQuest.board_choices.get("gp_path", "")) == "gp_firm", "the choice survives its save round trip")
	MiniQuest.board_done = old_done
	MiniQuest.board_choices = old_choices


func _test_tutorial_counts_from_the_station_opening() -> void:
	var ruleset := MatchState.ruleset.duplicate(true)
	var old := MiniQuest.export_fields()
	var old_tutorial: bool = Tutorial.active
	Tutorial.active = false
	MatchState.ruleset["start_id"] = "metal_magnate"
	MatchState.ruleset["tutorial_enabled"] = false
	MiniQuest.board_done = {}
	MiniQuest.board_granted = {}
	MiniQuest.board_baseline = {}
	MiniQuest.units_sold_total = 40
	MiniQuest.buildings_opened = 0
	_check(MiniQuest.effective_followed_board() == "tutorial" and MiniQuest.active_mission() == "t_open",
		"the top bar starts on the Tutorial's first station")
	MiniQuest.note_building_opened()
	_check(MiniQuest.board_node_state("t_open") == "complete", "opening a building finishes the first station")
	_check(float(MiniQuest.board_baseline.get("t_sell", -1.0)) == 40.0, "the sales station counts from the turn it opened")
	MiniQuest.units_sold_total = 120
	MiniQuest._eval_boards({})
	_check(MiniQuest.progress("t_sell") == Vector2i(80, 100), "its count is what was sold since")
	MiniQuest.units_sold_total = 140
	MiniQuest._eval_boards({})
	_check(MiniQuest.board_node_state("t_sell") == "complete" and Modifiers.has(MiniQuest.BOARD_REWARD_PREFIX + "t_sell"),
		"selling 100 units finishes the station and grants its reward")
	Modifiers.remove(MiniQuest.BOARD_REWARD_PREFIX + "t_sell")
	# The last station gives a free unlock.
	var bonus := ResearchState.bonus_free_unlocks
	MiniQuest._grant_station(MiniQuest._board_node("t_research"))
	_check(ResearchState.bonus_free_unlocks == bonus + 1, "unlocking five research gives a free unlock")
	ResearchState.bonus_free_unlocks = bonus
	MiniQuest.import_fields(old)
	MatchState.ruleset = ruleset
	Tutorial.active = old_tutorial


func _test_discounted_kit_is_repaid_on_refund() -> void:
	var id := "mq_discount_probe"
	Modifiers.add({"id": id, "domain": "construction_materials", "target": "*", "pct": -10.0})
	_check(is_equal_approx(Construction.materials_price_factor(), 0.9), "the build reward takes 10% off a construction kit")
	Modifiers.remove(id)
	var iid := "inst_probe_discount"
	BuildingState.buildings[iid] = {"instance_id": iid, "building_id": "b_002", "recipe_id": "r_003", "tile_id": "tile_9_9",
		"owner": MatchState.LOCAL_PLAYER, "materials_discount": 40.0}
	var old_money := MatchState.money
	var old_loans := LoanState.loans.size()
	MatchState.money = 10.0
	_check(is_equal_approx(Construction.repay_materials_discount(iid), 40.0), "a refund gives the discount back")
	_check(LoanState.loans.size() == old_loans + 1, "what cash cannot cover is borrowed")
	_check(not (BuildingState.buildings[iid] as Dictionary).has("materials_discount"), "a discount is repaid once")
	_check(EventScheduler.active_events().any(func(ev: Dictionary) -> bool: return str(ev.get("kind", "")) == "discount_repaid"),
		"the briefing says the discount was repaid")
	while LoanState.loans.size() > old_loans:
		LoanState.loans.pop_back()
	BuildingState.buildings.erase(iid)
	MatchState.money = old_money


func _test_new_games_open_with_the_tutorials_first_steps() -> void:
	var Steps := preload("res://scripts/tutorial/tutorial_steps.gd")
	var ids: Array = Steps.opener_steps().map(func(st: Dictionary) -> String: return str(st.get("id", "")))
	_check(ids == Steps.OPENER_IDS, "the opener plays the welcome, the screen tour, tiles and the recipe diagram, in order")
	_check(str((Steps.opener_steps()[0] as Dictionary).paragraphs[1]).contains("missions"), "the welcome says the missions take over")
	var ruleset := MatchState.ruleset.duplicate(true)
	MatchState.ruleset["opener_done"] = true
	Tutorial.start_opener()
	_check(not Tutorial.opener, "a match whose opener is done never plays it again")
	MatchState.ruleset = ruleset
