extends "res://tests/test_base.gd"
## Research unlocks, modifiers and tech gating.

const FEATURE := "research"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_coal_prohibition": ["decisions", "research"],
	"_test_scheduled_coal_prohibition": ["decisions", "research"],
	"_test_unlock_dialog_groups_multiple_unlocks": ["research", "ui"],
	"_test_modifiers_production_recipe_output": ["production", "research", "stockpile"],
	"_test_live_unlock_conditions": ["market", "production", "research", "stockpile"],
	"_test_embodied_carbon": ["decisions", "research"],
}

func _csv_dicts(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var headers := f.get_csv_line()
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < 2 or line[0] == "":
			continue
		var row := {}
		for i in headers.size():
			row[headers[i].strip_edges()] = line[i].strip_edges() if i < line.size() else ""
		out.append(row)
	return out


func _construct_panel_has_recipe(panel: Node, building_id: String, recipe_id: String) -> bool:
	var by_building: Dictionary = panel.get("recipes_by_building")
	for recipe in by_building.get(building_id, []):
		if str(recipe.get("recipe_id", "")) == recipe_id:
			return true
	return false

## The coal prohibition: the `ban coal` cheat and a scheduled ban share one code path.
## Covers both halves — production stops, and EVERY purchase route is refused — plus
## the guarantee that lifting it restores the status quo.
func _test_coal_prohibition() -> void:
	var turn: int = TurnManager.current_turn
	var was: int = PolicyState.coal_ban_override_turn()

	# Baseline: not banned, and the coal-mining recipe is selectable + runnable.
	PolicyState.cheat_set_coal_ban(false, turn)
	_check(not PolicyState.produce_banned("coal", turn), "coal ban: production legal by default")
	_check(not PolicyState.import_banned("coal", turn), "coal ban: imports legal by default")
	# recipes_producing keys on the catalog ID, not the internal name.
	var coal_gid: String = str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	_check(coal_gid != "", "coal ban: the catalog resolves the coal good")
	var coal_recipes: Array = Catalog.recipes_producing(coal_gid)
	_check(coal_recipes.size() > 0, "coal ban: the catalog has at least one coal recipe to prohibit")
	var coal_recipe: Dictionary = coal_recipes[0] if coal_recipes.size() > 0 else {}
	_check(not Catalog.is_recipe_prohibited(coal_recipe), "coal ban: coal recipe not prohibited by default")
	var mine_id: String = str(coal_recipe.get("building_id", ""))
	var before: int = Catalog.get_recipes_for_building(mine_id).size()

	# Engage it.
	PolicyState.cheat_set_coal_ban(true, turn)
	_check(PolicyState.produce_banned("coal", turn), "coal ban: production prohibited once engaged")
	_check(PolicyState.import_banned("coal", turn), "coal ban: imports prohibited once engaged")
	_check(Catalog.is_recipe_prohibited(coal_recipe), "coal ban: the coal recipe reads as prohibited")
	_check(Catalog.get_recipes_for_building(mine_id).size() < before,
		"coal ban: the prohibited recipe drops out of the building's selectable list")
	# A non-banned good is untouched — the ban is per-good, not a blanket stop.
	_check(not PolicyState.import_banned("iron_ore", turn), "coal ban: other goods still importable")

	# The prohibition is time-indexed, not a global switch: turns before the ban
	# engaged are still legal, which is what keeps it a pure function of the turn.
	_check(not PolicyState.produce_banned("coal", turn - 1), "coal ban: turns before it engaged stay legal")
	_check(PolicyState.any_ban_active(turn), "coal ban: any_ban_active reports the live prohibition")

	# Lifting it restores everything.
	PolicyState.cheat_set_coal_ban(false, turn)
	_check(not PolicyState.produce_banned("coal", turn), "coal ban: lifting restores production")
	_check(not PolicyState.import_banned("coal", turn), "coal ban: lifting restores imports")
	_check(Catalog.get_recipes_for_building(mine_id).size() == before,
		"coal ban: lifting restores the selectable recipe list")

	# The override survives a save/load round trip.
	PolicyState.cheat_set_coal_ban(true, turn)
	var exported: Dictionary = PolicyState.export_state()
	PolicyState.cheat_set_coal_ban(false, turn)
	PolicyState.import_state(exported)
	_check(PolicyState.coal_ban_override_turn() == turn, "coal ban: the override round-trips through save state")
	# Old saves (no key) must not resurrect a ban.
	PolicyState.import_state({"seeded": true, "insider_tip_fired": false})
	_check(PolicyState.coal_ban_override_turn() == -1, "coal ban: a pre-ban save loads with no prohibition")

	PolicyState.cheat_set_coal_ban(was >= 0, was if was >= 0 else turn)

## The SCHEDULED coal prohibition: the phase-2 ban is data on the policy schedule, so
## it must be live from its effective turn and absent the turn before, with no cheat
## engaged. Guards against the schedule entry being silently emptied.
func _test_scheduled_coal_prohibition() -> void:
	var was: int = PolicyState.coal_ban_override_turn()
	PolicyState.cheat_set_coal_ban(false, TurnManager.current_turn)

	var ban_turn: int = -1
	for e in PolicyState.Schedule.SCHEDULE:
		var bans: Dictionary = e.get("bans", {})
		if (bans.get("produce", []) as Array).has("coal"):
			ban_turn = int(e.effective_turn)
			break
	_check(ban_turn > 0, "scheduled coal ban: the schedule carries a coal prohibition")
	if ban_turn <= 0:
		PolicyState.cheat_set_coal_ban(was >= 0, was if was >= 0 else TurnManager.current_turn)
		return

	_check(not PolicyState.produce_banned("coal", ban_turn - 1), "scheduled coal ban: legal the turn before it lands")
	_check(not PolicyState.import_banned("coal", ban_turn - 1), "scheduled coal ban: imports legal the turn before")
	_check(PolicyState.produce_banned("coal", ban_turn), "scheduled coal ban: production prohibited from its effective turn")
	_check(PolicyState.import_banned("coal", ban_turn), "scheduled coal ban: imports prohibited from its effective turn")
	_check(PolicyState.produce_banned("coal", ban_turn + 50), "scheduled coal ban: stays in force afterwards")
	# It must land WITH the phase-2 doubling, not drift apart from it.
	_check(PolicyState.co2_tax_level(ban_turn) >= 2, "scheduled coal ban: lands with the phase-2 levy")

	PolicyState.cheat_set_coal_ban(was >= 0, was if was >= 0 else TurnManager.current_turn)


func _test_unlock_dialog_groups_multiple_unlocks() -> void:
	var dlg: Control = load("res://scripts/unlock_dialog.gd").new()
	add_child(dlg)
	dlg.call("show_unlocks", [
		{"title": "Improved Coal Mining", "description": "Coal mines output more."},
		{"title": "Copper Recovery", "description": "Copper chain improves."},
	])
	_check(dlg.visible
		and _tree_has_label_text(dlg, "2 unlocks")
		and _tree_has_label_text(dlg, "Improved Coal Mining")
		and _tree_has_label_text(dlg, "Copper Recovery"),
		"unlock dialog groups multiple unlocks in one panel")
	var unlock_list: Node = dlg.find_child("UnlockList", true, false)
	_check(unlock_list != null and unlock_list.get_child_count() == 2,
		"unlock dialog renders one box per unlock")
	await get_tree().process_frame
	var scroll: Control = dlg.find_child("UnlockScroll", true, false) as Control
	var first_card: Control = unlock_list.get_child(0) as Control if unlock_list != null and unlock_list.get_child_count() > 0 else null
	_check(scroll != null and scroll.size.y >= 180.0 and first_card != null and first_card.size.y >= 80.0,
		"unlock dialog reserves visible space for grouped unlock boxes")
	dlg.call("_close")
	_check(not dlg.visible, "unlock dialog closes")
	PanelStack.remove(dlg)
	dlg.queue_free()

## Green means "in the player's favour", which is NOT the same as positive. Output wants to go
## up; power draw and maintenance are costs and want to go down, so a research node that cuts a
## furnace's draw by 10% must not be painted as damage (owner, 25 Aug).
func _test_modifier_sign_convention() -> void:
	var panel_script: Variant = load("res://scripts/building_detail_panel_v2.gd")
	var ok: Color = DS.PALETTE["OK"]
	var bad: Color = DS.PALETTE["DANGER"]
	_check(panel_script._mod_tone(12.0, true) == ok and panel_script._mod_tone(-5.0, true) == bad,
		"modifier colour: more output is good, less output is bad")
	_check(panel_script._mod_tone(-10.0, false) == ok and panel_script._mod_tone(10.0, false) == bad,
		"modifier colour: LESS power draw or maintenance is good, more is bad")
	_check(panel_script._mod_tone(0.0, true) == DS.PALETTE["TEXT"]
		and panel_script._mod_tone(0.0, false) == DS.PALETTE["TEXT"],
		"modifier colour: a modifier that nets to nothing is neither")
	_check(panel_script._mod_pct_text(7.0) == "+7%" and panel_script._mod_pct_text(-7.0) == "\u22127%",
		"modifier text: signed, with a real minus sign")
	var cats: Array = panel_script.MOD_CATEGORIES
	var costs_invert := true
	for entry_value: Variant in cats:
		var entry: Dictionary = entry_value
		if str(entry.get("cat", "")) in ["Power draw", "Maintenance"]:
			costs_invert = costs_invert and not bool(entry.get("good_up", true))
	_check(cats.size() == 4 and costs_invert,
		"modifier colour: the cost categories are the ones that read upside down")


func _test_research_recipe_and_level_tiers() -> void:
	var graphitisation: Dictionary = Catalog.get_recipe("r_042")
	# Gates store research_node_ids now; assert on the id the title resolves to, so the
	# test keeps naming the node the designer knows while checking what the data holds.
	_check(str(graphitisation.get("tech_unlock_req", ""))
			== ResearchState.research_node_id_for_title("Biomass Cracking"),
		"bio-graphitisation is gated by Biochemistry's Biomass Cracking")
	var has_biomass_node := false
	for unlock in ResearchState._unlock_defs:
		if str(unlock.get("title", "")) == "Biomass Cracking":
			has_biomass_node = str(unlock.get("category", "")) == "Farming & Forestry"
	_check(has_biomass_node, "Biomass Cracking belongs to the Farming & Forestry tree")

	var file := FileAccess.open("res://data/research_unlocks.csv", FileAccess.READ)
	var level2_ok := file != null
	var level2_count := 0
	var warehouse_level2_ok := true
	if file != null:
		var header := file.get_csv_line()
		var indices := {}
		for index in header.size():
			indices[header[index]] = index
		while not file.eof_reached():
			var row := file.get_csv_line()
			if row.is_empty() or row[0].strip_edges() == "":
				continue
			var icon_index: int = int(indices.get("icon", -1))
			var rank_index: int = int(indices.get("rank", -1))
			var title_index_l2: int = int(indices.get("title", -1))
			if icon_index >= 0 and rank_index >= 0 and icon_index < row.size() and row[icon_index] == "level2":
				level2_count += 1
				var l2_title: String = row[title_index_l2] if (title_index_l2 >= 0 and title_index_l2 < row.size()) else ""
				# Furnace Level 2 (Hot Blast Stoves) is a deliberate Tier-I unlock (owner 2026-09):
				# owning 3 furnaces unlocks it with no steel prereq, so any furnace business —
				# glass merchant included — can level its furnaces without a Metallurgy detour.
				var l2_expected_rank: String = "I" if l2_title == "Hot Blast Stoves" else "II"
				if rank_index >= row.size() or row[rank_index] != l2_expected_rank:
					level2_ok = false
			var title_index: int = int(indices.get("title", -1))
			var description_index: int = int(indices.get("description", -1))
			if title_index >= 0 and description_index >= 0 and title_index < row.size() and description_index < row.size() and row[title_index] == "Pallet Racking Systems" and "warehouse level 2" in row[description_index] and (rank_index < 0 or rank_index >= row.size() or row[rank_index] != "II"):
				warehouse_level2_ok = false
		file.close()
	_check(level2_ok and level2_count == 21, "all 21 Level 2 building unlocks are Tier II (bar Furnace's Hot Blast Stoves, a deliberate Tier-I unlock)")
	_check(warehouse_level2_ok, "warehouse Level 2 unlock is Tier II")

func _test_retrofit_mechanic() -> void:
	# Find a building type with at least two recipes to retrofit between.
	var by_b: Dictionary = {}
	for r in Catalog.all_recipes():
		var b := str(r.get("building_id", ""))
		if b == "":
			continue
		if not by_b.has(b):
			by_b[b] = []
		(by_b[b] as Array).append(str(r.get("recipe_id", "")))
	var bid := ""
	var recs: Array = []
	for b in by_b:
		if (by_b[b] as Array).size() >= 2:
			bid = str(b)
			recs = by_b[b]
			break
	if bid == "":
		_check(true, "retrofit: skipped (no multi-recipe building in catalog)")
		return

	var saved_seats := AdvisorState.advisor_seats.duplicate(true)
	var saved_money := MatchState.money
	var saved_buildings := BuildingState.buildings.duplicate(true)
	var saved_retro := BuildingWorks.pending_retrofits.duplicate(true)
	AdvisorState.advisor_seats = {}
	MatchState.money = 1000.0
	BuildingWorks.pending_retrofits = []
	var iid := "test_retrofit_1"
	BuildingState.buildings[iid] = {"instance_id": iid, "building_id": bid, "recipe_id": str(recs[0]), "tile_id": "tile_0_0", "level": 1}

	var tier: Dictionary = BuildingWorks.retrofit_cost_tier()
	_check(is_equal_approx(float(tier["labour"]), 0.50) and int(tier["turns"]) == 2,
		"retrofit: base tier (no COO) = 50% labour, 2 turns")

	var before := MatchState.money
	var res: Dictionary = BuildingWorks.start_retrofit(iid, str(recs[1]))
	_check(bool(res["ok"]) and BuildingWorks.is_retooling(iid)
		and is_equal_approx(MatchState.money, before - 25.0)
		and is_equal_approx(BuildingWorks.retooling_labour_fraction(iid), 0.50),
		"retrofit: start charges the fee, marks retooling, applies reduced labour")
	_check(not bool(BuildingWorks.start_retrofit(iid, str(recs[0]))["ok"]),
		"retrofit: blocked while already retooling")

	BuildingWorks.tick_retrofits()
	_check(BuildingWorks.is_retooling(iid), "retrofit: still retooling after 1 tick (base = 2 turns)")
	BuildingWorks.tick_retrofits()
	_check(not BuildingWorks.is_retooling(iid) and str(BuildingState.buildings[iid]["recipe_id"]) == str(recs[1]),
		"retrofit: completes after 2 turns and swaps in the new recipe")

	AdvisorState.advisor_seats = {"coo": "tom"}   # Ops 3
	var t3: Dictionary = BuildingWorks.retrofit_cost_tier()
	_check(int(t3["turns"]) == 1 and is_equal_approx(float(t3["labour"]), 0.30),
		"retrofit: Ops-3 COO = 1 turn, 30% labour")
	AdvisorState.advisor_seats = {"coo": "rufus"}   # Ops 1 malus
	var t1: Dictionary = BuildingWorks.retrofit_cost_tier()
	_check(is_equal_approx(float(t1["labour"]), 0.75) and is_equal_approx(float(t1["fee"]), 40.0),
		"retrofit: Ops-1 COO malus = 75% labour, £40 (worse than base)")

	AdvisorState.advisor_seats = {}
	BuildingWorks.start_retrofit(iid, str(recs[0]))
	_check((MatchState.export_state().get("pending_retrofits", []) as Array).size() >= 1,
		"retrofit: pending_retrofits is written to the save state")

	AdvisorState.advisor_seats = saved_seats
	MatchState.money = saved_money
	BuildingState.buildings = saved_buildings
	BuildingWorks.pending_retrofits = saved_retro

func _test_research_unlock_promotes_construct_panel_recipes() -> void:
	var recipe := Catalog.get_recipe("r_020")
	var building_id := str(recipe.get("building_id", ""))
	var saved_unlocks := ResearchState.unlocked_titles.duplicate(true)
	var saved_land := BuildingState.tile_land_owned.duplicate(true)
	var saved_construct_v2 := UiPrefs.use_construct_panel_v2
	# This fixture explicitly instantiates the legacy panel and calls its tile-open
	# API, so do not let the live v2 routing toggle make that API return early.
	UiPrefs.use_construct_panel_v2 = false
	# r_020 is gated on Flash Copper Smelting (its own node since 2026-09-06), which
	# auto-unlocks on Produce All 200 industrial acids + 300 copper ingots; a fresh fixture
	# has produced neither, so it stays unmet while this test isolates panel filtering.
	# (tile_land_owned cleared too, harmless, in case an owned-land gate returns.)
	BuildingState.tile_land_owned.clear()
	ResearchState.unlocked_titles.erase("Flash Copper Smelting")
	var packed: PackedScene = load("res://scenes/construct_panel.tscn")
	if packed == null or recipe.is_empty() or building_id == "":
		_check(false, "research unlock: construct panel fixture resolves")
		_replace_dict(ResearchState.unlocked_titles, saved_unlocks)
		_replace_dict(BuildingState.tile_land_owned, saved_land)
		UiPrefs.use_construct_panel_v2 = saved_construct_v2
		return
	var panel: Control = packed.instantiate() as Control
	if panel == null:
		_check(false, "research unlock: construct panel instantiates as Control")
		_replace_dict(ResearchState.unlocked_titles, saved_unlocks)
		_replace_dict(BuildingState.tile_land_owned, saved_land)
		UiPrefs.use_construct_panel_v2 = saved_construct_v2
		return
	add_child(panel)
	await get_tree().process_frame

	panel.show()
	await get_tree().process_frame
	_check(not _construct_panel_has_recipe(panel, building_id, "r_020"),
		"construct panel hides recipe-gated research before unlock")
	ResearchState.grant_unlock("Flash Copper Smelting")
	await get_tree().process_frame
	_check(_construct_panel_has_recipe(panel, building_id, "r_020"),
		"construct panel promotes recipe when research unlocks")

	ResearchState.unlocked_titles.erase("Flash Copper Smelting")
	panel.call("open_for_tile", "tile_test_research_unlock", {})
	await get_tree().process_frame
	_check(not _construct_panel_has_recipe(panel, building_id, "r_020"),
		"tile build panel hides recipe-gated research before unlock")
	ResearchState.grant_unlock("Flash Copper Smelting")
	await get_tree().process_frame
	_check(_construct_panel_has_recipe(panel, building_id, "r_020"),
		"tile build panel promotes recipe when research unlocks")

	panel.queue_free()
	await get_tree().process_frame
	_replace_dict(ResearchState.unlocked_titles, saved_unlocks)
	_replace_dict(BuildingState.tile_land_owned, saved_land)
	UiPrefs.use_construct_panel_v2 = saved_construct_v2

func _test_limestone_concrete() -> void:
	_check(not Catalog.get_good_by_internal_name("limestone").is_empty(), "limestone good exists")
	_check(not Catalog.get_good_by_internal_name("concrete").is_empty(), "concrete good exists")
	var found := false
	for r in Catalog.all_recipes():
		if str(r.get("output_name", "")) == "limestone" and str(r.get("building_id", "")) != "":
			found = true
			var gated := false
			for req in r.get("requirements", []):
				if str(req.get("type", "")) == "deposit" and str(req.get("value", "")) == "limestone":
					gated = true
			_check(gated, "limestone mining is gated on a limestone deposit")
	_check(found, "a mine recipe produces limestone")

# --- Modifiers ---------------------------------------------------------------
func _test_modifiers_basic() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 1
	# No active modifiers → base passes through untouched.
	_check(Modifiers.apply("recipe_output", "r_001", 20.0) == 20.0,
		"apply with empty registry returns base unchanged")
	# Add a +5% recipe_output modifier on r_001.
	var mid := Modifiers.add({"id": "test_a", "domain": "recipe_output",
		"target": "r_001", "mult": 1.05, "label": "Test +5%"})
	_check(mid == "test_a" and Modifiers.has("test_a"),
		"add registers the modifier with the supplied id")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0) - 21.0) < 0.001,
		"applied to r_001: 20 * 1.05 = 21")
	# Different target → unchanged.
	_check(absf(Modifiers.apply("recipe_output", "r_002", 20.0) - 20.0) < 0.001,
		"r_001-targeted modifier does NOT affect r_002")
	# Different domain → unchanged even for the same target.
	_check(absf(Modifiers.apply("transport_cost", "r_001", 20.0) - 20.0) < 0.001,
		"recipe_output modifier does NOT affect the transport_cost domain")
	_check(Modifiers.remove("test_a") and not Modifiers.has("test_a"),
		"remove drops the modifier")
	Modifiers.reset()

func _test_modifiers_stacking() -> void:
	Modifiers.reset()
	# Add-then-mult stacking: (base + adds) * prod(mults).
	# base = 10, +2 (add) and +3 (add) → 15; then *1.5 and *1.2 → 27.
	Modifiers.add({"id": "a", "domain": "recipe_output", "target": "*", "add": 2.0})
	Modifiers.add({"id": "b", "domain": "recipe_output", "target": "*", "add": 3.0})
	Modifiers.add({"id": "c", "domain": "recipe_output", "target": "*", "mult": 1.5})
	Modifiers.add({"id": "d", "domain": "recipe_output", "target": "*", "mult": 1.2})
	var got: float = Modifiers.apply("recipe_output", "r_001", 10.0)
	_check(absf(got - 27.0) < 0.001,
		"stacking: (10+2+3)*1.5*1.2 = 27 (got %.3f)" % got)
	Modifiers.reset()

func _test_modifiers_target_match() -> void:
	Modifiers.reset()
	# target_match: only fires when ctx provides the required keys.
	Modifiers.add({"id": "extraction_only", "domain": "recipe_output",
		"target_match": {"recipe_type": "extraction"}, "mult": 1.10})
	var ctx_ext := {"recipe_type": "extraction"}
	var ctx_smelt := {"recipe_type": "smelting"}
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0, ctx_ext) - 22.0) < 0.001,
		"target_match recipe_type=extraction applies to extraction ctx")
	_check(absf(Modifiers.apply("recipe_output", "r_003", 20.0, ctx_smelt) - 20.0) < 0.001,
		"target_match recipe_type=extraction does NOT apply to a smelting ctx")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 20.0) - 20.0) < 0.001,
		"target_match modifier inert when ctx is missing the key")
	Modifiers.reset()

func _test_modifiers_expiry() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 10
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	Modifiers.add({"id": "tempo", "domain": "recipe_output",
		"target": "*", "mult": 2.0, "duration_turns": 5})
	# Added in DECIDE of turn 10 → it already applies to turn 10's PROCESS, so a
	# 5-turn duration covers PROCESS 10..14 and expires at 10 + 5 - 1 = 14.
	_check(int(Modifiers._modifiers["tempo"]["expires_turn"]) == 14,
		"duration_turns is converted into an absolute expires_turn")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 10.0) - 20.0) < 0.001,
		"modifier active before expiry")
	# Tick NARRATIVE phases up to and past expiry.
	TurnManager.current_turn = 13
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame
	_check(Modifiers.has("tempo"), "still active one turn before expiry")
	TurnManager.current_turn = 14
	TurnManager.phase_started.emit(TurnManager.Phase.NARRATIVE)
	await get_tree().process_frame
	_check(not Modifiers.has("tempo"), "pruned on the turn it expires")
	_check(absf(Modifiers.apply("recipe_output", "r_001", 10.0) - 10.0) < 0.001,
		"expired modifier no longer affects apply")
	# NARRATIVE-granted (condition unlock): first application is NEXT turn's
	# PROCESS, so the same 5-turn duration expires one turn later (11..15).
	TurnManager.current_turn = 10
	TurnManager.current_phase = TurnManager.Phase.NARRATIVE
	Modifiers.add({"id": "tempo2", "domain": "recipe_output",
		"target": "*", "mult": 2.0, "duration_turns": 5})
	_check(int(Modifiers._modifiers["tempo2"]["expires_turn"]) == 15,
		"NARRATIVE-granted duration expires one turn later")
	TurnManager.current_phase = TurnManager.Phase.DECIDE
	Modifiers.reset()

func _test_modifiers_production_recipe_output() -> void:
	# Drives a coal mine through Production once with no modifier (baseline),
	# then a second time with +5% extraction. Asserts the +5% takes effect end
	# to end: not just in Modifiers.apply but in what lands in the stockpile.
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	var tile := "tile_6_8"  # has a coal deposit
	var inst: String = BuildingState.add_building("b_001", "r_001", tile)
	# Force-allow the mine to run (deposit is seeded from the live tile map,
	# which a clean test environment doesn't have — drop the depletion gate by
	# revealing + topping up the deposit).
	MatchState.reveal_deposit(tile, "coal")
	MatchState.deposit_remaining[tile] = {"coal": 999}
	# Coal carries a standing −30% deposit-penalty modifier (re-seeded by the reset
	# above); drop it so this test isolates the +5% extraction modifier on a clean
	# 60-unit baseline.
	Modifiers.remove("deposit_penalty_coal")

	var summary := _fresh_production_summary()
	Production._produce_outputs(BuildingState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var base_produced: int = int(summary.produced.get("g_001", 0))
	_check(base_produced == 60, "baseline: coal recipe produces 60 (got %d)" % base_produced)

	# Now with the Mining Mastery modifier active: mining recipes +5%.
	Stockpile.clear_all()
	Modifiers.add({"id": "mining_mastery_bonus", "domain": "recipe_output",
		"target_match": {"recipe_type": "mineral mining"}, "mult": 1.05})
	summary = _fresh_production_summary()
	Production._produce_outputs(BuildingState.get_building(inst), Catalog.get_recipe("r_001"), summary)
	Production._flush_output_buffer()
	var boosted_produced: int = int(summary.produced.get("g_001", 0))
	_check(boosted_produced == 63, "with +5%% mining modifier: 60 → 63 (got %d)" % boosted_produced)
	_check(Stockpile.get_at_tile(tile, "g_001") == 63,
		"the boosted output lands in the tile stockpile (got %d)" % Stockpile.get_at_tile(tile, "g_001"))
	Modifiers.reset()
	BuildingState.remove_building(inst)

## Research nodes are referenced BY TITLE from three places, and only one of those was
## covered: the unlock-audit test already checks title uniqueness and prereq resolution
## (see "every research prerequisite resolves to an unlock title"). The OTHER two edges of
## the graph had nothing enforcing them — a renamed node silently deadens its
## UNLOCK_MODIFIERS entry (this is how five authored oil effects sat inert), and a renamed
## node silently orphans any recipe gated on it. Those two are what this covers.
func _test_research_reference_integrity() -> void:
	var rows := _csv_dicts("res://data/research_unlocks.csv")
	_check(not rows.is_empty(), "research CSV loaded (%d rows)" % rows.size())
	var titles := {}
	var node_ids := {}
	var missing_ids: Array = []
	var dupe_ids: Array = []
	for r in rows:
		# Mirror the loader: demo-hidden rows stay in the CSV but are never loaded, so
		# their titles must not be expected to resolve (see MatchState.HIDDEN_RESEARCH_IDS).
		if ResearchState.HIDDEN_RESEARCH_IDS.has(str(r.get("research_node_id", "")).strip_edges()):
			continue
		var t := str(r.get("title", "")).strip_edges()
		if t != "":
			titles[t] = true
		var nid := str(r.get("research_node_id", "")).strip_edges()
		if nid == "":
			missing_ids.append(t)
		elif node_ids.has(nid):
			dupe_ids.append(nid)
		else:
			node_ids[nid] = true
	# Ids are permanent handles: every node must have one and no two may share one,
	# or a modifier/save reference silently binds to the wrong node.
	_check(missing_ids.is_empty(), "every research node has a research_node_id (%s)" % str(missing_ids))
	_check(dupe_ids.is_empty(), "research_node_ids are unique (%s)" % str(dupe_ids))

	var unwired: Array = []
	for key in Modifiers.UNLOCK_MODIFIERS:
		if not node_ids.has(str(key)):
			unwired.append(str(key))
	_check(unwired.is_empty(),
		"every UNLOCK_MODIFIERS key is a real research_node_id (%s)" % str(unwired))

	# The title↔id resolution every gate and modifier lookup depends on must round-trip
	# in BOTH directions.
	var unresolved: Array = []
	var no_reverse: Array = []
	for t in titles:
		var nid2 := ResearchState.research_node_id_for_title(str(t))
		if nid2 == "":
			unresolved.append(str(t))
		elif ResearchState.research_title_for_node_id(nid2) != str(t):
			no_reverse.append(str(t))
	_check(unresolved.is_empty(),
		"every research title resolves to its node id (%s)" % str(unresolved))
	_check(no_reverse.is_empty(),
		"title→id→title round-trips for every node (%s)" % str(no_reverse))

	# Phase 3: prereq columns store research_node_ids, not titles. A title left in one
	# would still LOOK right in the CSV while silently failing every prereq check.
	var title_prereqs: Array = []
	for r in rows:
		for col in ["prereq_1", "prereq_2", "prereq_3", "prereq_othercategory"]:
			var p := str(r.get(col, "")).strip_edges()
			if p == "":
				continue
			if node_ids.has(p):
				continue
			title_prereqs.append("%s.%s = '%s'" % [r.get("title", "?"), col, p])
	_check(title_prereqs.is_empty(),
		"every prereq is a research_node_id, not a title (%s)" % str(title_prereqs))

	# Recipe gates. `consumer` and `hydro` are long-standing content gaps (verified against
	# git history — they have never been titles); they are excluded so this test fails only
	# on a NEW break, not on the pre-existing backlog.
	# Recipe gates now store research_node_ids too. `consumer` and `hydro` are deliberate
	# bare cheat tokens (b_027 hydro is gated by the `unlock hydro` cheat, not by a node),
	# so they are expected to resolve to nothing.
	var known_gaps := ["consumer", "hydro"]
	var bad_gates: Array = []
	for r in _csv_dicts("res://data/recipes_all.csv"):
		# Mirror Catalog.is_recipe_visible: a demo-hidden recipe may legitimately gate on a
		# demo-hidden node (both stay in the CSVs to return post-demo), so skip it here.
		if Catalog.HIDDEN_RECIPE_IDS.has(str(r.get("recipe_id", "")).strip_edges()):
			continue
		var gate := str(r.get("tech_unlock_req", "")).strip_edges()
		if gate == "" or node_ids.has(gate) or gate in known_gaps:
			continue
		bad_gates.append("%s → '%s'" % [r.get("recipe_id", "?"), gate])
	_check(bad_gates.is_empty(),
		"every recipe gate is a research_node_id (%s)" % str(bad_gates))


func _test_modifiers_roundtrip() -> void:
	Modifiers.reset()
	TurnManager.current_turn = 50
	Modifiers.add({"id": "a", "domain": "recipe_output", "target": "*",
		"mult": 1.07, "expires_turn": 100, "label": "A"})
	Modifiers.add({"id": "b", "domain": "transport_cost",
		"target_match": {"good_id": "g_001"}, "add": 0.5, "expires_turn": 80})
	var snap: Dictionary = Modifiers.export_state()
	Modifiers.reset()
	_check(Modifiers.active_count() == 0, "reset clears the registry")
	Modifiers.import_state(snap)
	_check(Modifiers.has("a") and Modifiers.has("b"),
		"round-trip restores both modifiers")
	_check(absf(Modifiers.apply("recipe_output", "anything", 10.0) - 10.7) < 0.001,
		"restored 'a' still applies (10 * 1.07 = 10.7)")
	_check(absf(Modifiers.apply("transport_cost", "g_001", 1.0, {"good_id": "g_001"}) - 1.5) < 0.001,
		"restored 'b' still applies (1 + 0.5)")
	Modifiers.reset()

func _test_live_unlock_conditions() -> void:
	Modifiers.reset()
	MatchState.reset()
	MarketState.import_state({})
	Stockpile.clear_all()
	Production.produced_by_building.clear()
	Production.full_output_streak_by_building.clear()

	# Research conditions are encoded as internal_name Objects: a good_id for the
	# "Produce" verb, a building internal_name for the "Run …" verbs.
	var def := {}
	for d in ResearchState._unlock_defs:
		if str(d.title) == "Improved Coal Mining":
			def = d
	_check(not def.is_empty() and str(def.action) == "Produce" and str(def.object) == "coal",
		"Improved Coal Mining now uses a Produce|coal condition")

	# --- "Produce N units" verb: lifetime production across all buildings ---
	# Production records under the catalog good_id (e.g. g_001), NOT the internal
	# name; the condition Object is the internal name "coal", so lifetime_total must
	# resolve it. Seed the ledger under the real good_id to exercise that path.
	var coal_gid: String = str(Catalog.get_good_by_internal_name("coal").get("id", "coal"))
	_check(coal_gid != "coal", "coal resolves to a catalog good_id (got %s)" % coal_gid)
	# 499 coal: below the 500 threshold, stays locked.
	Production.produced_by_building["bX"] = {coal_gid: 499}
	ResearchState._check_unlock_conditions()
	_check(not ResearchState.is_unlocked("Improved Coal Mining"),
		"Produce condition unmet at 499/500 coal")
	# Cross-building total reaches 500 → the lifetime sum trips the unlock.
	Production.produced_by_building["bY"] = {coal_gid: 1}
	ResearchState._check_unlock_conditions()
	_check(ResearchState.is_unlocked("Improved Coal Mining"),
		"Produce condition met once lifetime coal hits 500 (summed across buildings)")
	# Generated power uses its internal name in the production ledger, unlike
	# material outputs. The live condition must accept that form too.
	Production.produced_by_building.clear()
	Production.produced_by_building["generator"] = {"power": 250}
	_check(ResearchState._live_condition_met({"action": "Produce", "object": "Power", "qty": 250}),
		"Produce condition resolves display-name casing and internal-key power output")

	# --- "Produce Any" verb: 500 of EITHER good in an a|b list unlocks it (OR) ---
	Production.produced_by_building.clear()
	var sand_gid := str(Catalog.get_good_by_internal_name("sand").get("id", "sand"))
	var produce_any := {"action": "Produce Any", "object": "limestone|sand", "qty": 500, "quantity_raw": "500"}
	_check(not ResearchState._live_condition_met(produce_any),
		"Produce Any stays locked at 0 of both goods")
	Production.produced_by_building["sandpit"] = {sand_gid: 500}
	_check(ResearchState._live_condition_met(produce_any),
		"Produce Any fires on 500 sand alone (does not require limestone or both)")

	# --- "Run Same Tile" / "Own On Tiles": co-location and reach, not fleet size ---
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	var same_tile_ids: Array = []
	for _i in range(3):
		same_tile_ids.append(BuildingState.add_building("b_001", "", "tile_same_1"))
	BuildingState.add_building("b_001", "", "tile_same_2")   # a 4th mine, but on another tile
	for iid_s in same_tile_ids:
		Production.full_output_streak_by_building[iid_s] = 15
	var same_tile := {"action": "Run Same Tile", "object": "mine", "qty": 4, "unit": "15 turns"}
	_check(not ResearchState._live_condition_met(same_tile),
		"Run Same Tile: 3 running mines on one tile + 1 elsewhere does not satisfy 4-on-a-tile")
	var fourth := BuildingState.add_building("b_001", "", "tile_same_1")
	_check(not ResearchState._live_condition_met(same_tile),
		"Run Same Tile: a 4th mine on the tile with no run-streak does not count yet")
	Production.full_output_streak_by_building[fourth] = 15
	_check(ResearchState._live_condition_met(same_tile),
		"Run Same Tile: 4 mines on one tile all at full output for 15 turns satisfies it")
	_check(ResearchState._live_condition_met({"action": "Own On Tiles", "object": "mine", "qty": 2}),
		"Own On Tiles: mines on 2 distinct tiles satisfies 2")
	_check(not ResearchState._live_condition_met({"action": "Own On Tiles", "object": "mine", "qty": 3}),
		"Own On Tiles: 5 mines spread over only 2 tiles does not satisfy 3 (reach, not count)")
	MatchState.reset()

	# --- "Run Producing" (by output good) / "Run Distinct Recipes" / "Own All" ---
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	var chlor := BuildingState.add_building("b_012", "r_012", "tile_chem_1")   # chlor-alkali -> chlorine
	Production.full_output_streak_by_building[chlor] = 15
	_check(ResearchState._live_condition_met({"action": "Run Producing", "object": "chlorine", "qty": 1, "unit": "15 turns"}),
		"Run Producing: a chem plant on chlor-alkali at full output 15 turns counts as making chlorine")
	_check(not ResearchState._live_condition_met({"action": "Run Producing", "object": "chlorine", "qty": 1, "unit": "20 turns"}),
		"Run Producing: the same plant does not yet satisfy a 20-turn streak")
	_check(not ResearchState._live_condition_met({"action": "Run Distinct Recipes", "object": "chem_plant", "qty": 3}),
		"Run Distinct Recipes: one running chem plant is not three distinct recipes")
	var air := BuildingState.add_building("b_012", "r_086", "tile_chem_1")     # oxygen air separation
	Production.full_output_streak_by_building[air] = 1
	var chlor2 := BuildingState.add_building("b_012", "r_012", "tile_chem_2")  # a second chlor-alkali
	Production.full_output_streak_by_building[chlor2] = 1
	_check(not ResearchState._live_condition_met({"action": "Run Distinct Recipes", "object": "chem_plant", "qty": 3}),
		"Run Distinct Recipes: three plants on only two recipes does not satisfy 3")
	var calc := BuildingState.add_building("b_012", "r_082", "tile_chem_2")    # electric calcination alumina
	Production.full_output_streak_by_building[calc] = 1
	_check(ResearchState._live_condition_met({"action": "Run Distinct Recipes", "object": "chem_plant", "qty": 3}),
		"Run Distinct Recipes: three different chem-plant recipes running satisfies 3")
	var own_all := {"action": "Own All", "object": "chem_plant|power_plant", "qty": 1, "quantity_raw": "1|1"}
	_check(not ResearchState._live_condition_met(own_all),
		"Own All: chem plants alone do not satisfy chem plant AND power plant")
	BuildingState.add_building("b_003", "", "tile_chem_3")
	_check(ResearchState._live_condition_met(own_all),
		"Own All: one chem plant and one power plant satisfies it")
	MatchState.reset()

	# --- "All Of" (compound AND of clauses) / "Produce Per Turn" (a rate, not lifetime) ---
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	Production.produced_by_building.clear()
	var all_of := {"action": "All Of", "object": "Own|power_plant|1|units;Produce|steel|100|units", "qty": 1, "unit": "conditions"}
	_check(not ResearchState._live_condition_met(all_of), "All Of: neither clause met -> false")
	BuildingState.add_building("b_003", "", "tile_all_1")
	_check(not ResearchState._live_condition_met(all_of), "All Of: one clause met is not enough")
	var steel_rate_gid := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	Production.produced_by_building["mill"] = {steel_rate_gid: 100}
	_check(ResearchState._live_condition_met(all_of), "All Of: both clauses met -> true")
	_check(ResearchState._research_condition_issue(all_of) == "", "All Of: the audit validates each clause")
	Production.last_turn_summary = {"produced": {steel_rate_gid: 299}}
	_check(not ResearchState._live_condition_met({"action": "Produce Per Turn", "object": "steel", "qty": 300}),
		"Produce Per Turn: 299 steel last turn does not satisfy 300/turn")
	Production.last_turn_summary = {"produced": {steel_rate_gid: 300}}
	_check(ResearchState._live_condition_met({"action": "Produce Per Turn", "object": "steel", "qty": 300}),
		"Produce Per Turn: 300 steel last turn satisfies 300/turn (a rate, not lifetime volume)")
	# --- "Produce Per Turn Any" (rate on EITHER good), nested inside All Of with a "|" object ---
	var coke_gid := str(Catalog.get_good_by_internal_name("pet_coke").get("id", ""))
	var biomass_gid := str(Catalog.get_good_by_internal_name("carbonised_biomass").get("id", ""))
	Production.last_turn_summary = {"produced": {coke_gid: 29, biomass_gid: 0}}
	_check(not ResearchState._live_condition_met({"action": "Produce Per Turn Any", "object": "pet_coke|carbonised_biomass", "qty": 30, "quantity_raw": "30"}),
		"Produce Per Turn Any: 29 coke / 0 biomass last turn does not reach 30 of either")
	Production.last_turn_summary = {"produced": {coke_gid: 0, biomass_gid: 30}}
	_check(ResearchState._live_condition_met({"action": "Produce Per Turn Any", "object": "pet_coke|carbonised_biomass", "qty": 30, "quantity_raw": "30"}),
		"Produce Per Turn Any: 30 biomass alone satisfies the OR")
	# The Carbon Substitution gate: 500 steel lifetime AND (30 coke/turn OR 30 biomass/turn).
	var carbon_gate := {"action": "All Of", "object": "Produce|steel|500|units;Produce Per Turn Any|pet_coke|carbonised_biomass|30|units per turn", "qty": 1, "unit": "conditions"}
	var nested := ResearchState._parse_sub_condition("Produce Per Turn Any|pet_coke|carbonised_biomass|30|units per turn")
	_check(str(nested.get("object", "")) == "pet_coke|carbonised_biomass" and int(nested.get("qty", 0)) == 30,
		"All Of clause parser keeps a '|' good-list object intact (last two fields are qty/unit)")
	_check(not ResearchState._live_condition_met(carbon_gate), "Carbon Substitution: biomass rate alone (no steel) is not enough")
	Production.produced_by_building["mill"] = {steel_rate_gid: 500}
	_check(ResearchState._live_condition_met(carbon_gate), "Carbon Substitution: 500 steel AND 30 biomass/turn unlocks it")
	_check(ResearchState._research_condition_issue(carbon_gate) == "", "Carbon Substitution gate passes the audit")
	Production.last_turn_summary = {}
	Production.produced_by_building.clear()
	MatchState.reset()

	# --- "Ship Multimodal": last turn's freight >= N AND carried by more than one mode ---
	MatchState.reset()
	var mm_gate := {"action": "Ship Multimodal", "object": "freight", "qty": 100}
	TransportState._last_transit_shipments = [
		{"qty": 70, "good_id": "g_001", "legs": [{"to": "t2", "mode": "roads"}]},
		{"qty": 60, "good_id": "g_002", "legs": [{"to": "t3", "mode": "roads"}]},
	]
	_check(not ResearchState._live_condition_met(mm_gate), "Ship Multimodal: 130 freight all by road is one mode — not multimodal")
	TransportState._last_transit_shipments = [
		{"qty": 40, "good_id": "g_001", "legs": [{"to": "t2", "mode": "roads"}]},
		{"qty": 30, "good_id": "g_002", "legs": [{"to": "t3", "mode": "rail"}]},
	]
	_check(not ResearchState._live_condition_met(mm_gate), "Ship Multimodal: two modes but only 70 freight does not reach 100")
	TransportState._last_transit_shipments = [
		{"qty": 70, "good_id": "g_001", "legs": [{"to": "t2", "mode": "roads"}, {"to": "t3", "mode": "rail"}]},
		{"qty": 30, "good_id": "g_002", "legs": [{"to": "t4", "mode": "roads"}]},
	]
	_check(ResearchState._live_condition_met(mm_gate), "Ship Multimodal: 100 freight with a road+rail route satisfies it (units count once per mode, never per link)")
	_check(ResearchState._research_condition_issue(mm_gate) == "", "Ship Multimodal gate passes the audit")
	TransportState._last_transit_shipments = []
	MatchState.reset()

	# --- "Sell N units": saved lifetime volume across ordinary/special/grid paths ---
	var steel_gid := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	MarketState.record_lifetime_sale_volume(steel_gid, 249)
	_check(not ResearchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"Sell condition remains unmet one unit below its lifetime threshold")
	MarketState.record_lifetime_sale_volume(steel_gid, 1)
	_check(ResearchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"Sell condition resolves a display name and trips at the lifetime threshold")
	_check(ResearchState._live_condition_met({"action": "Sell", "object": "Freight", "qty": 250}),
		"Sell Freight resolves to aggregate lifetime shipment volume")
	var market_sale_snapshot := MarketState.export_state()
	MarketState.import_state({})
	_check(not ResearchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"a fresh market state clears lifetime research sale volume")
	MarketState.import_state(market_sale_snapshot)
	_check(ResearchState._live_condition_met({"action": "Sell", "object": "Steel", "qty": 250}),
		"lifetime research sale volume survives a save/load round-trip")

	# --- Display-name/case resolver: the original live-game casing regression ---
	MatchState.reset()
	for i in range(3):
		BuildingState.add_building("b_002", "", "tile_furnace_%d" % i)
	# Building additions mark research progress dirty; it is evaluated in the
	# NARRATIVE phase, so invoke the shared evaluator for this synchronous unit test.
	ResearchState._check_unlock_conditions()
	_check(ResearchState.is_unlocked("Basic Blast Furnaces"),
		"Build Furnace unlock fires with the CSV display name (case-insensitive)")

	# --- Plain Run and concept aliases: one building, sustained full-output streak ---
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	var refinery_iid := BuildingState.add_building("b_011", "", "tile_refinery")
	Production.full_output_streak_by_building[refinery_iid] = 12
	_check(ResearchState._live_condition_met({"action": "Run", "object": "Oil Refinery", "qty": 12}),
		"Run condition resolves Oil Refinery to petro_refinery and its run streak")
	var factory_iid := BuildingState.add_building("b_007", "", "tile_factory")
	Production.full_output_streak_by_building[factory_iid] = 15
	_check(ResearchState._live_condition_met({"action": "Run", "object": "Modular Factory Cells", "qty": 15}),
		"Run condition resolves a research-concept alias to its live building")

	# --- Own land and Sustain verbs ---
	BuildingState.tile_land_owned.clear()
	for i in range(5):
		BuildingState.tile_land_owned["tile_owned_%d" % i] = 1
	_check(ResearchState._live_condition_met({"action": "Own", "object": "land", "qty": 5}),
		"Own land condition counts explicitly owned tiles")
	AdvisorState._advisor_profit_streak = 3
	_check(ResearchState._live_condition_met({"action": "Sustain", "object": "1000+ profit/turn", "qty": 3}),
		"Sustain condition reads the saved advisor profit streak")

	# --- "Run L1 … for N turns": level + run-streak filter ---
	MatchState.reset()
	Production.full_output_streak_by_building.clear()
	var iid := BuildingState.add_building("b_003", "", "tile_lv_1")  # Coal Power Plant, Level 1
	_check(ResearchState._count_buildings("power_plant", 1, false, 20) == 0,
		"a fresh L1 building (streak 0) does not count toward a 20-turn gate")
	Production.full_output_streak_by_building[iid] = 20
	_check(ResearchState._count_buildings("power_plant", 1, false, 20) == 1,
		"the L1 building counts once its run-streak reaches 20 turns")

	# --- Level filter: this fixture contains no Level-2 buildings ---
	_check(ResearchState._count_buildings("power_plant", 2, false, 0) == 0,
		"Level-2 gates stay unmet when the owned building is only Level 1")
	# --- Profitability filter: a building with no costed output isn't profitable ---
	_check(ResearchState._count_buildings("power_plant", -1, true, 0) == 0,
		"the profitable filter excludes buildings with no known unit cost")

	# Every non-placeholder research row must either resolve to a live metric or
	# appear in this explicit content-gap allowlist. This catches new casing,
	# identifier and unsupported-verb regressions across the full CSV.
	var expected_content_gaps: Array = []
	var actual_content_gaps: Array = []
	for issue in ResearchState.research_condition_issues():
		actual_content_gaps.append(str(issue.title))
	actual_content_gaps.sort()
	_check(actual_content_gaps == expected_content_gaps,
		"research condition audit has no unexpected unresolved targets (got %s)" % [actual_content_gaps])
	var research_titles: Dictionary = {}
	var duplicate_titles: Array = []
	for unlock_def in ResearchState._unlock_defs:
		var unlock_title := str(unlock_def.get("title", ""))
		if research_titles.has(unlock_title):
			duplicate_titles.append(unlock_title)
		research_titles[unlock_title] = true
	# Prereqs are research_node_ids since the id migration, so resolve against ids.
	var research_node_ids: Dictionary = {}
	for unlock_def in ResearchState._unlock_defs:
		var nid := str(unlock_def.get("research_node_id", ""))
		if nid != "":
			research_node_ids[nid] = true
	var missing_prereqs: Array = []
	for unlock_def in ResearchState._unlock_defs:
		for prereq in unlock_def.get("prereqs", []):
			if not research_node_ids.has(str(prereq)):
				missing_prereqs.append("%s -> %s" % [unlock_def.title, prereq])
	_check(duplicate_titles.is_empty(),
		"research dataset has no duplicate unlock titles (got %s)" % [duplicate_titles])
	_check(missing_prereqs.is_empty(),
		"every research prerequisite resolves to a research_node_id (got %s)" % [missing_prereqs])

	Modifiers.reset()
	MatchState.reset()
	MarketState.import_state({})
	Production.produced_by_building.clear()
	Production.full_output_streak_by_building.clear()

func _test_research_tier_gating() -> void:
	MatchState.reset()
	MatchState.recycling_unlocked = true # This fixture tests progression in enabled content.
	# Tier I is always open; a higher tier opens on >= min(TIER_UNLOCK_THRESHOLD,
	# prior-tier-count) unlocked in the prior tier of the SAME category. Written against the
	# CONSTANT rather than a literal: the threshold moved 3 -> 2 (owner 2026-08-23) and this
	# test was the only thing that had to change, which is the point of pinning it this way.
	_check(ResearchState.TIER_UNLOCK_THRESHOLD == 1,
		"tier gate: a tier opens on one of the tier below")
	_check(ResearchState.is_tier_available("Metallurgy", "I"), "tier gate: Tier I always open")
	_check(not ResearchState.is_tier_available("Metallurgy", "II"),
		"tier gate: Metallurgy II locked with 0 Tier-I unlocked")
	ResearchState.grant_unlock("Basic Blast Furnaces")
	_check(ResearchState.is_tier_available("Metallurgy", "II"),
		"tier gate: Metallurgy II opens at %d Tier-I unlocked" % ResearchState.TIER_UNLOCK_THRESHOLD)
	# Softlock clamp: min(TIER_UNLOCK_THRESHOLD, prior-tier-count) — a category opens even with
	# fewer prior-tier nodes than the threshold. Recycling III opens once a Tier-II node is unlocked.
	_check(not ResearchState.is_tier_available("Recycling", "III"),
		"tier gate: Recycling III locked before any Tier-II node")
	ResearchState.grant_unlock("Membrane Bioreactors")
	_check(ResearchState.is_tier_available("Recycling", "III"),
		"tier gate: Recycling III opens after a Tier-II node")
	MatchState.reset()

func _test_mining_mastery_free_unlock() -> void:
	Modifiers.reset()
	MatchState.reset()
	# Regular Shaft Draining (ex Mining Mastery) grants two permanent mine modifiers;
	# the maintenance one is the sentinel here.
	_check(not Modifiers.has("rn_shaft_draining_maint"), "no bonus before free pick")
	ResearchState.grant_unlock("Regular Shaft Draining", false)
	_check(ResearchState.is_unlocked("Regular Shaft Draining"), "free pick unlocks the tech")
	_check(Modifiers.has("rn_shaft_draining_maint"),
		"free-picking the tech also grants the modifier")
	Modifiers.reset()
	MatchState.reset()

# Free-pick path: spending a free unlock on Mining Mastery (via_condition=false)
# also routes through grant_unlock → unlock_granted, so the bonus still lands.
# Free-unlock cadence (owner, 2026-08-19): one at turns 1/12/36/60/84, then two every
# 48 turns. The schedule is a pure static function on the panel, so it tests without UI.
func _test_free_unlock_cadence() -> void:
	var RP := preload("res://scripts/research_panel.gd")
	var sched: Dictionary = RP.free_unlock_schedule(TurnManager.MAX_TURNS)
	for t in [1, 12, 36, 60, 84]:
		_check(int(sched.get(t, 0)) == 1, "one free unlock at turn %d" % t)
	for t in [132, 180, 228, 276]:
		_check(int(sched.get(t, 0)) == 2, "two free unlocks at turn %d (48-turn cadence)" % t)
	_check(not sched.has(84 + FREE_UNLOCK_OFFCADENCE), "no grant on an off-cadence turn")
	_check(not sched.has(276 + 48), "the recurring grants stop at MAX_TURNS (no turn 324)")
	# Cumulative opening balance a panel would show at each turn.
	_check(RP.free_unlocks_earned_by(0, TurnManager.MAX_TURNS) == 0, "nothing earned before turn 1")
	_check(RP.free_unlocks_earned_by(1, TurnManager.MAX_TURNS) == 1, "1 earned by turn 1")
	_check(RP.free_unlocks_earned_by(11, TurnManager.MAX_TURNS) == 1, "still 1 the turn before 12")
	_check(RP.free_unlocks_earned_by(12, TurnManager.MAX_TURNS) == 2, "2 earned by turn 12")
	_check(RP.free_unlocks_earned_by(84, TurnManager.MAX_TURNS) == 5, "5 earned by turn 84 (the five singles)")
	_check(RP.free_unlocks_earned_by(132, TurnManager.MAX_TURNS) == 7, "7 earned by turn 132 (first pair)")
	_check(RP.free_unlocks_earned_by(TurnManager.MAX_TURNS, TurnManager.MAX_TURNS) == 5 + 2 * 4,
		"13 earned by turn 300 (five singles + four pairs at 132/180/228/276)")

const FREE_UNLOCK_OFFCADENCE := 1

# Percentage modifiers add (not chain): a −10% and a +15% on the same domain/target
# net to +5%, applied as ×1.05. And resolve_pct hands the UI that net + the parts.
func _test_modifiers_pct_additive_and_resolve() -> void:
	Modifiers.reset()
	Modifiers.add({"id": "down", "domain": "recipe_output", "target": "*",
		"pct": -10.0, "label": "Tax productivity hit"})
	Modifiers.add({"id": "up", "domain": "recipe_output", "target": "*",
		"pct": 15.0, "label": "Process upgrade"})
	# 100 → (100)*(1 + 5/100) = 105, because −10 and +15 SUM to +5 (not 0.90×1.15).
	_check(absf(Modifiers.apply("recipe_output", "r_001", 100.0) - 105.0) < 0.001,
		"pct modifiers add: −10% and +15% net +5% (→105, not 103.5)")
	var res: Dictionary = Modifiers.resolve_pct("recipe_output", "r_001", {})
	_check(absf(float(res.get("net", 0.0)) - 5.0) < 0.001,
		"resolve_pct returns the summed net (+5%)")
	_check((res.get("parts", []) as Array).size() == 2,
		"resolve_pct lists both contributing multipliers for the hover")
	# Domain isolation: a building_power pct doesn't bleed into recipe_output's net.
	Modifiers.add({"id": "pwr", "domain": "building_power", "target": "*", "pct": -20.0})
	_check(absf(float(Modifiers.resolve_pct("recipe_output", "r_001", {}).get("net", 0.0)) - 5.0) < 0.001,
		"resolve_pct ignores other domains")
	_check(absf(Modifiers.apply("building_power", "b_002", 100.0) - 80.0) < 0.001,
		"a −20% building_power pct drops a 100-energy draw to 80")
	Modifiers.reset()

# The promoted research nodes register their modifiers on unlock, across all four
# wired domains — including Lights-Out Automation, whose one node hits TWO buildings.
func _test_modifiers_new_domain_unlocks() -> void:
	Modifiers.reset()
	MatchState.reset()
	# recipe_output: Continuous-Flow Reactors → +5% at the chem plant (b_012) only.
	ResearchState.grant_unlock("Continuous-Flow Reactors")
	_check(Modifiers.has("cfr_chem_output"), "Continuous-Flow Reactors registers its modifier")
	_check(absf(Modifiers.apply("recipe_output", "any", 100.0, {"building_id": "b_012"}) - 105.0) < 0.001,
		"chem plant (b_012) gets +5% output")
	_check(absf(Modifiers.apply("recipe_output", "any", 100.0, {"building_id": "b_010"}) - 100.0) < 0.001,
		"a different building (b_010) is untouched by the chem bonus")
	# building_power: Energy-Recovery Devices → −50% at desal (b_021).
	ResearchState.grant_unlock("Energy-Recovery Devices")
	_check(absf(Modifiers.apply("building_power", "b_021", 100.0, {"building_id": "b_021"}) - 50.0) < 0.001,
		"desal (b_021) power draw halved")
	# maintenance: Combined Heat & Power → −5% everywhere.
	ResearchState.grant_unlock("Combined Heat & Power")
	_check(absf(Modifiers.apply("maintenance", "b_002", 100.0, {"building_id": "b_002"}) - 95.0) < 0.001,
		"Combined Heat & Power cuts maintenance 5% empire-wide")
	# labour_headcount: ONE Lights-Out node, TWO buildings (high-tech b_010 + assembly b_009).
	ResearchState.grant_unlock("Lights-Out Automation")
	_check(Modifiers.has("lo_hightech_labour") and Modifiers.has("lo_assembly_labour"),
		"Lights-Out Automation registers BOTH building modifiers from one unlock")
	_check(absf(Modifiers.apply("labour_headcount", "b_010", 100.0, {"building_id": "b_010"}) - 80.0) < 0.001,
		"high-tech (b_010) labour −20%")
	_check(absf(Modifiers.apply("labour_headcount", "b_009", 100.0, {"building_id": "b_009"}) - 80.0) < 0.001,
		"assembly (b_009) labour −20%")
	Modifiers.reset()
	MatchState.reset()

# An upgrade tech may only stand on a tech from a LOWER tier.
#
# Industrial Goods Factory L2 (rank II) was gated behind a rank III node, so the upgrade that
# should open the middle game sat behind the late one (owner, 25 Aug). Same-tier prereqs are
# caught too: they make a tier a queue rather than a set of choices.
func _test_upgrade_techs_stand_on_lower_tiers() -> void:
	const RANK_ORDER := {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5}
	var rows := _research_rows()
	_check(not rows.is_empty(), "research: research_unlocks.csv parses")
	var rank_of: Dictionary = {}
	for row_value: Variant in rows:
		var row: Dictionary = row_value
		rank_of[str(row.get("research_node_id", ""))] = str(row.get("rank", ""))
	var offenders: Array[String] = []
	for row_value: Variant in rows:
		var row: Dictionary = row_value
		if not str(row.get("icon", "")) in ["level2", "level3"]:
			continue
		var mine: int = int(RANK_ORDER.get(str(row.get("rank", "")), 0))
		for key in ["prereq_1", "prereq_2", "prereq_3", "prereq_othercategory"]:
			var prereq := str(row.get(key, "")).strip_edges()
			if prereq == "":
				continue
			_check(rank_of.has(prereq), "research: %s names a real prereq (%s)" % [
				str(row.get("research_node_id", "")), prereq])
			if int(RANK_ORDER.get(str(rank_of.get(prereq, "")), 9)) >= mine:
				offenders.append("%s(%s)<-%s(%s)" % [str(row.get("research_node_id", "")),
					str(row.get("rank", "")), prereq, str(rank_of.get(prereq, ""))])
	_check(offenders.is_empty(),
		"research: no upgrade tech stands on its own tier or above (%s)" % ", ".join(offenders))


func _test_embodied_carbon() -> void:
	# A fossil fuel carries its own point-of-combustion figure and is NOT re-derived from its
	# feedstock — processed_oil is 2.7 while the crude it comes from is 0.1, and letting the
	# DAG flatten that would gut the policy.
	var oil := str(Catalog.get_good_by_internal_name("processed_oil").get("id", ""))
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var pet := str(Catalog.get_good_by_internal_name("pet_coke").get("id", ""))
	var eth := str(Catalog.get_good_by_internal_name("ethylene").get("id", ""))
	var pwr := str(Catalog.get_good_by_internal_name("power").get("id", ""))
	_check(float(Catalog.get_good(pet).get("co2_tax_multiplier", 0.0)) > 0.0,
		"pet coke now carries a carbon levy (it is a petroleum product)")
	# THE LOOPHOLE: making ethylene pays the levy on the oil it cracks, so buying it must cost
	# the same. Cracking 9 processed_oil at 2.7 yields 12 ethylene -> 2.03 carried per unit.
	# A good's own levy is NOT its embodied figure: its consumer pays that directly.
	var oil_levy := float(Catalog.get_good(oil).get("co2_tax_multiplier", 0.0))
	_check(Catalog.embodied_carbon(eth) > oil_levy * 0.5,
		"loophole closed: ethylene carries the oil levy that cracking it incurred (%.2f)" % Catalog.embodied_carbon(eth))
	_check(Catalog.embodied_carbon(eth) > float(Catalog.get_good(eth).get("co2_tax_multiplier", 0.0)),
		"loophole closed: ethylene's carried carbon exceeds its own levy, so buying cannot undercut making")
	_check(Catalog.embodied_carbon(pwr) > 0.0,
		"loophole closed: power carries the carbon of the coal burned to make it")
	# A manufactured good carries the carbon of the fossil that made it.
	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	_check(Catalog.embodied_carbon(steel) > 0.0, "embodied carbon: steel carries the coal that made it")
	# ...and one made from nothing fossil carries none. biomass is the clean feedstock.
	var bio := str(Catalog.get_good_by_internal_name("biomass").get("id", ""))
	_check(absf(Catalog.embodied_carbon(bio)) < 0.001, "embodied carbon: biomass carries none")
	# The levy is NOT charged on manufactured goods, so one tonne of carbon is taxed once.
	# This is the property that stops a deep chain paying for the same coal at every step.
	_check(absf(float(Catalog.get_good(steel).get("co2_tax_multiplier", 0.0))) < 0.001,
		"no double count: steel carries embodied carbon but is not itself levied")
	_check(float(Catalog.get_good(coal).get("co2_tax_multiplier", 0.0)) > 0.0,
		"no double count: the levy lands on the coal instead")
	# Market price: zero carbon component before the levy starts, positive once it is in force.
	var t_before: int = PolicyState.CO2_RAMP_FIRST_TURN - 1
	_check(absf(PolicyState.co2_tax_scale(t_before)) < 0.001, "carbon price: no component before the levy starts")
	_check(PolicyState.co2_tax_scale(PolicyState.CO2_P1_TURN) > 0.0, "carbon price: the levy scale is live at P1")
	# --- national grid decarbonises on its own ---
	var full: int = EconomyConfig.GRID_CARBON_FULL_TURN
	_check(absf(PolicyState.grid_carbon_intensity(1) - 1.0) < 0.001, "grid carbon: fully fossil at turn 1")
	_check(absf(PolicyState.grid_carbon_intensity(full) - 1.0) < 0.001, "grid carbon: still fully fossil at turn %d" % full)
	_check(absf(PolicyState.grid_carbon_intensity(TurnManager.MAX_TURNS) - EconomyConfig.GRID_CARBON_FLOOR) < 0.001,
		"grid carbon: reaches the %d%% floor on the last turn" % int(EconomyConfig.GRID_CARBON_FLOOR * 100.0))
	var mid := PolicyState.grid_carbon_intensity((full + TurnManager.MAX_TURNS) / 2)
	_check(mid < 1.0 and mid > EconomyConfig.GRID_CARBON_FLOOR, "grid carbon: decays monotonically in between (%.2f)" % mid)
	_check(PolicyState.grid_carbon_intensity(TurnManager.MAX_TURNS + 50) >= EconomyConfig.GRID_CARBON_FLOOR - 0.001,
		"grid carbon: never falls below the floor past the last turn")
	# The curve cleans the GRID, not a coal plant: coal's levy is a fixed per-unit charge and
	# must not inherit the grid's decarbonisation, or burning coal would get cheaper over time.
	var coal_levy_early := PolicyState.carbon_charge(coal, 100, PolicyState.CO2_P1_TURN)
	var coal_levy_late := PolicyState.carbon_charge(coal, 100, TurnManager.MAX_TURNS)
	_check(coal_levy_late >= coal_levy_early,
		"grid carbon: burning coal yourself does NOT get cleaner as the grid does")


# ── Recycling gate (owner 2026-08-23: out of the demo, behind `unlock recycling`) ──
func _test_recycling_gate() -> void:
	var terminal := preload("res://scripts/debug_terminal.gd")
	var demo_was_unlocked: bool = terminal._demo_unlocked
	terminal._demo_unlocked = false
	var was_unlocked: bool = MatchState.recycling_unlocked
	MatchState.recycling_unlocked = false
	var visible: Dictionary = {}
	for good_variant: Variant in MatchState.visible_goods():
		visible[str((good_variant as Dictionary).get("id", ""))] = true
	var hidden_ok := true
	for gid in MatchState.RECYCLING_GOOD_IDS:
		if visible.has(str(gid)) or MatchState.is_good_available(str(gid)):
			hidden_ok = false
	_check(hidden_ok, "recycling: the waste goods are hidden by default")
	_check(not MatchState.is_building_available("b_022")
		and not MatchState.is_building_available("b_036"),
		"recycling: both recycling plants are hidden by default")
	_check(MatchState.visible_goods().size()
		== Catalog.all_goods().size() - MatchState.RECYCLING_GOOD_IDS.size(),
		"recycling: exactly the waste goods are removed, nothing else")
	_check(MatchState.is_good_available("g_001") and MatchState.is_building_available("b_001"),
		"recycling: ordinary goods and buildings are untouched")

	MatchState.cheat_unlock_recycling()
	_check(MatchState.visible_goods().size() == Catalog.all_goods().size()
		and MatchState.is_building_available("b_036"),
		"recycling: `unlock recycling` puts the chain and its plants back")
	MatchState.recycling_unlocked = false
	for gid: String in MatchState.RECYCLING_GOOD_IDS:
		_check(not Catalog.is_good_buyable(gid) and not Catalog.is_good_sellable(gid), "demo waste cannot be traded: " + gid)
		_check(not Catalog.is_recipe_visible({"inputs": [{"good_id": gid}]}), "demo hides recipes consuming " + gid)
		_check(not Catalog.is_recipe_visible({"output_good_id": gid}), "demo hides recipes producing " + gid)
	_check(Catalog.get_recipe("r_209").get("outputs", []).all(func(item: Dictionary) -> bool: return str(item.get("good_id")) != "g_063"), "demo farming omits wastewater byproduct")
	var blocked: Array = []
	for recipe: Dictionary in Catalog._all_recipes:
		if not Catalog.is_recipe_demo_available(recipe):
			blocked.append(recipe)
	_check(not blocked.is_empty(), "demo gate covers loaded recycling recipes")
	terminal._demo_unlocked = true
	_check(MatchState.is_building_available("b_036") and MatchState.is_building_available("b_022"), "unlock demo restores both recycling plants")
	for recipe: Dictionary in blocked:
		_check(Catalog.is_recipe_visible(recipe), "unlock demo restores waste recipe " + str(recipe.get("recipe_id")))
	_check(MatchState.visible_goods().size() == Catalog.all_goods().size(), "unlock demo restores waste goods")
	terminal._demo_unlocked = demo_was_unlocked
	MatchState.recycling_unlocked = was_unlocked

# ── Petrochemistry additions (owner 2026-08-23) ─────────────────────────────
func _test_petrochemistry_changes() -> void:
	MatchState.reset()
	# A fourth Tier I node, so the tier is a CHOICE of two from four rather than a queue.
	# Post-regroup the refining half of the old Petrochemistry tree lives under Chemistry.
	var node: Dictionary = {}
	for d_variant: Variant in ResearchState._unlock_defs:
		var d: Dictionary = d_variant
		if str(d.get("title", "")) == "Specialised Petrochemical Pipelines":
			node = d
	_check(str(node.get("category", "")) == "Chemistry" and str(node.get("rank", "")) == "I",
		"petrochem: the pipelines node is a Tier I Chemistry node")
	# Owner 2026-09-06: pipelines are earned by breadth of refining — two refineries on
	# different recipes — not by a run-streak that duplicated Fractional Distillation's.
	_check(str(node.get("action", "")) == "Run Distinct Recipes" and int(node.get("qty", 0)) == 2,
		"petrochem: the pipelines node is earned by running 2 refineries on different recipes")
	_check(ResearchState.research_condition_issues().is_empty(),
		"petrochem: every research row still resolves to a live condition")

	# ...and it pays out on the Petrochemical Refinery.
	Modifiers.reset()
	var before: float = Modifiers.apply("recipe_output", "r", 100.0, {"building_id": "b_011"})
	ResearchState.grant_unlock("Specialised Petrochemical Pipelines")
	var after: float = Modifiers.apply("recipe_output", "r", 100.0, {"building_id": "b_011"})
	_check(absf(after - before - 5.0) < 0.001,
		"petrochem: the pipelines node adds +5%% refinery output (%.1f -> %.1f)" % [before, after])
	_check(absf(Modifiers.apply("recipe_output", "r", 100.0, {"building_id": "b_001"}) - 100.0) < 0.001,
		"petrochem: it does not touch other buildings")
	Modifiers.reset()

	# Offshore drilling is earned on an offshore OIL FIELD, not on land anywhere.
	MatchState.reset()
	var offshore: Dictionary = {}
	for d_variant: Variant in ResearchState._unlock_defs:
		var d: Dictionary = d_variant
		if str(d.get("title", "")) == "Offshore Drilling Platforms":
			offshore = d
	_check(str(offshore.get("action", "")) == "Own"
		and str(offshore.get("object", "")) == "offshore_oil_land"
		and int(offshore.get("qty", 0)) == 50,
		"offshore: earned by owning 50 land on a sea tile with oil")

	# Land on an ordinary tile does not count, however much of it there is.
	BuildingState.tile_land_owned["tile_5_10"] = 200
	_check(ResearchState._owned_offshore_oil_land() == 0,
		"offshore: inland acreage does not count toward the offshore gate")
	# A sea tile carrying oil does.
	var oil_tile := ""
	for tid: String in ["tile_1_1", "tile_2_8", "tile_11_19", "tile_28_19", "tile_29_9"]:
		if not (Catalog.tile_type(tid) in ["sea", "deep_sea"]):
			continue
		if "oil" in Catalog.tile_deposits_raw(tid).to_lower():
			oil_tile = tid
			break
	_check(oil_tile != "", "offshore: the map has a sea tile with an oil deposit")
	BuildingState.tile_land_owned[oil_tile] = 50
	_check(ResearchState._owned_offshore_oil_land() == 50,
		"offshore: acreage on an offshore oil field counts")
	MatchState.reset()

# ── Research deep link (owner 2026-08-23: the blocking tech is a link, not flat text) ──
func _test_research_link_is_exact() -> void:
	var panel: Object = (load("res://scripts/research_panel.gd") as GDScript).new()
	var rows: Array = panel.get("_unlock_rows")
	if rows == null or rows.is_empty():
		panel.call("_load_unlock_rows")
		rows = panel.get("_unlock_rows")
	_check(rows != null and rows.size() > 0, "research link: the unlock table loads")
	for row: Dictionary in rows:
		if str(row.get("title", "")) == "Bauxite Carbochlorination":
			_check(panel._unlock_matches(row, "aluminium"), "tutorial research search finds processes by their output")

	# The ORDINARY search matches title, description and category by substring, which is
	# right for hunting and wrong for a link: several techs mention another tech in their
	# description. Count how often an exact title pulls in extras, so the exact mode below
	# is demonstrably needed rather than assumed.
	var ambiguous := 0
	for row_variant: Variant in rows:
		var title := str((row_variant as Dictionary).get("title", ""))
		if title == "":
			continue
		var loose := 0
		for other_variant: Variant in rows:
			if bool(panel.call("_unlock_matches", other_variant, title.to_lower())):
				loose += 1
		if loose > 1:
			ambiguous += 1

	# Exact links return the named tech only when its content flags permit it.
	var exact_ok := true
	var checked := 0
	for row_variant: Variant in rows:
		var title := str((row_variant as Dictionary).get("title", ""))
		if title == "":
			continue
		checked += 1
		panel.set("_search_query", title)
		panel.set("_search_exact_title", title)
		var hits: Array = panel.call("_category_unlocks", "")
		if not ResearchState.is_research_visible(row_variant):
			if not hits.is_empty():
				exact_ok = false
		elif hits.size() != 1 or str((hits[0] as Dictionary).get("title", "")) != title:
			exact_ok = false
	_check(checked > 20 and exact_ok,
		"research link: an exact-title link returns that tech and nothing else (%d techs, %d of which are ambiguous under the loose search)" % [checked, ambiguous])
	panel.free()
