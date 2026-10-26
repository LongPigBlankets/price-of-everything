extends "res://tests/test_base.gd"
## Phase 5 of docs/pacing-labour-mining-licensing-spec.md: output bonuses become throughput, timed mission rewards
## and the Original Furnace legacy (scripts/legacy_perk.gd). Each test names the acceptance criteria (AC…) it checks.

const FEATURE := "output"
const TAGS := {
	"_test_stale_research_modifiers_pruned": ["output", "save"],
}

const FURNACE := "b_002"
const STEEL := "r_003"
const PIG_IRON := "r_005"
const LegacyPerk := preload("res://scripts/legacy_perk.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

## Buildings whose output bonuses stay: extraction (mines, wells, the water pump) and buildings with no material
## inputs (solar, wind, offshore wind, hydro, battery storage, hidden water recycling).
const OUTPUT_KEPT_BUILDINGS := ["b_001", "b_032", "b_033", "b_034", "b_037", "b_024", "b_025", "b_026", "b_027", "b_028", "b_022"]
## Goods dug or pumped: mining yield research keeps its output.
const EXTRACTED := ["coal", "iron_ore", "copper_ore", "limestone", "sand", "basic_salt", "ree_ore", "alloy_ore", "sulphur",
	"bauxite_ore", "crude_oil"]
const CAPSTONES := ["rn_advanced_elastomers", "rn_modular_factory_cells", "rn_continuous_improvement"]


func _fresh() -> void:
	Modifiers.reset()
	MatchState.reset()
	Stockpile.clear_all()
	TurnManager.current_turn = 1


func _player(building_id: String, recipe_id: String, tile: String) -> String:
	BuildingState.tile_land_owned[tile] = 2000
	var iid: String = BuildingState.add_building(building_id, recipe_id, tile, MatchState.LOCAL_PLAYER, "")
	BuildingState.get_building(iid).erase("staff_fill")
	return iid


func _specs(node_id: String) -> Array:
	var spec: Variant = Modifiers.unlock_spec_for(node_id)
	return spec if spec is Array else ([spec] if spec is Dictionary and not (spec as Dictionary).is_empty() else [])


## AC26.1: a throughput, recipe input or power modifier scoped `makes: steel` reaches the steel recipe only.
func _test_makes_scope() -> void:
	_fresh()
	var steel := BuildingState.get_building(_player(FURNACE, STEEL, "tile_9_9"))
	var pig := BuildingState.get_building(_player(FURNACE, PIG_IRON, "tile_9_9"))
	var base_steel := MatchState.throughput_multiplier(steel)
	Modifiers.add({"id": "t_mk", "domain": "throughput", "target_match": {"makes": "steel"}, "pct": 10.0})
	_check(is_equal_approx(MatchState.throughput_multiplier(steel), base_steel + 0.10) and is_equal_approx(MatchState.throughput_multiplier(pig), base_steel),
		"AC26.1 throughput scoped to steel reaches the steel recipe, not pig iron")
	Modifiers.add({"id": "t_in", "domain": "recipe_input", "target_match": {"makes": "steel", "good_internal": "coal"}, "pct": -20.0})
	var coal_in: Dictionary = (Catalog.get_recipe(STEEL).inputs as Array).filter(func(i: Dictionary) -> bool: return str(i.good_id) == "g_001")[0]
	var coal_pig: Dictionary = (Catalog.get_recipe(PIG_IRON).inputs as Array).filter(func(i: Dictionary) -> bool: return str(i.good_id) == "g_001")[0]
	_check(is_equal_approx(Production._modified_input_qty(coal_in, steel), float(coal_in.qty) * 0.8)
		and is_equal_approx(Production._modified_input_qty(coal_pig, pig), float(coal_pig.qty)),
		"AC26.1 a coal input cut scoped to steel spares pig iron")
	var power_before := Production._effective_energy_req_f(steel, Catalog.get_recipe(STEEL))
	Modifiers.add({"id": "t_pw", "domain": "building_power", "target_match": {"makes": "steel"}, "pct": 5.0})
	_check(absf(Production._effective_energy_req_f(steel, Catalog.get_recipe(STEEL)) - power_before * 1.05) < 0.01,
		"AC26.1 power scoped to steel draws 5% more on the steel recipe")
	_fresh()


## AC26.2–AC26.5: the table's conversions, node by node.
func _test_research_conversions() -> void:
	var want := [
		["research_inorg_013", "throughput", 7.5, "building_id", "b_012"],
		["research_mining_004", "throughput", 7.5, "makes", "copper_ingots"],
		["research_inorg_003", "throughput", 15.0, "makes", "glass"],
		["research_mfg_024", "throughput", 15.0, "building_id", "b_010"],
		["research_inorg_021", "throughput", 30.0, "building_id", "b_021"],
		["research_petro_005", "recipe_output", 5.0, "good_internal", "rubber"],
		["research_mining_001", "recipe_output", 15.0, "good_internal", "coal"],
		["research_renew_001", "recipe_output", 5.0, "building_id", "b_024"],
		["research_hcpower_001", "recipe_input", -15.0, "good_internal", "coal"],
		["research_hcpower_002", "throughput", 10.0, "building_id", "b_003"],
		["research_hcpower_008", "maintenance", -10.0, "building_id", "b_003"],
		["research_metal_001", "throughput", 10.0, "building_id", "b_002"],
		["research_metal_002", "recipe_input", -10.0, "makes", "steel"],
		["research_metal_010", "building_power", 5.0, "makes", "steel"],
		["research_petro_002", "recipe_input", -10.0, "good_internal", "crude_oil"],
		["research_petro_021", "building_power", -15.0, "building_id", "b_011"],
		["research_mfg_014", "labour_headcount", 10.0, "building_id", "b_007"],
		["research_metal_008", "building_power", 10.0, "building_id", "b_008"],
		["research_metal_014", "building_power", -10.0, "building_id", "b_008"],
	]
	var wrong := PackedStringArray()
	for w: Array in want:
		var hit := false
		for m: Dictionary in _specs(str(w[0])):
			hit = hit or (str(m.get("domain", "")) == str(w[1]) and is_equal_approx(float(m.get("pct", 0.0)), float(w[2]))
				and str((m.get("target_match", {}) as Dictionary).get(str(w[3]), "")) == str(w[4]))
		if not hit:
			wrong.append(str(w[0]))
	_check(wrong.is_empty(), "AC26.2–AC26.5 each node carries its converted effect (wrong: %s)" % ", ".join(wrong))
	var haulage: Dictionary = _specs("research_mining_014")[0]
	_check(str(haulage.domain) == "extraction_cap_cost" and is_equal_approx(float(haulage.pct), -25.0),
		"AC26.5 Bulk Haulage Fleets cuts the over-cap cost to +75% a working")


## AC26.2–AC26.4, stance A2: no research output bonus is left on a processing building, apart from the capstones.
func _test_no_processing_output_left() -> void:
	var left := PackedStringArray()
	for key: String in Modifiers.UNLOCK_MODIFIERS.keys():
		for m: Dictionary in _specs(key):
			if str(m.get("domain", "")) != "recipe_output" or str(m.get("id", "")) in CAPSTONES:
				continue
			var match_d: Dictionary = m.get("target_match", {})
			if str(match_d.get("building_id", "")) in OUTPUT_KEPT_BUILDINGS or str(match_d.get("good_internal", "")) in EXTRACTED:
				continue
			left.append("%s (%s)" % [key, str(m.get("id", ""))])
	_check(left.is_empty(), "AC26.2 no research output bonus on a processing building but the capstones (left: %s)" % ", ".join(left))
	var capstones_ok := CAPSTONES.all(func(id: String) -> bool:
		for key: String in Modifiers.UNLOCK_MODIFIERS.keys():
			for m: Dictionary in _specs(key):
				if str(m.get("id", "")) == id:
					return str(m.domain) == "recipe_output" and is_equal_approx(float(m.pct), 5.0)
		return false)
	_check(capstones_ok, "AC26.4 the tier III capstones give +5% output")


## AC26.2 in play: Basic Blast Furnaces raises furnace throughput 10%, not its output modifier.
func _test_research_throughput_in_play() -> void:
	_fresh()
	var b := BuildingState.get_building(_player(FURNACE, PIG_IRON, "tile_9_9"))
	var run0 := MatchState.throughput_multiplier(b)
	var out0 := float(BuildingStatus.net_output_modifier(b, Catalog.get_recipe(PIG_IRON)).get("parts", []).size())
	for m: Dictionary in _specs("research_metal_001"):
		Modifiers.add(m)
	_check(is_equal_approx(MatchState.throughput_multiplier(b), run0 + 0.10), "AC26.2 Basic Blast Furnaces: furnace throughput +10%")
	var mod := BuildingStatus.net_output_modifier(b, Catalog.get_recipe(PIG_IRON))
	_check(float((mod.get("parts", []) as Array).size()) == out0 and (mod.get("throughput_parts", []) as Array).size() == 1,
		"AC26.2 the output modifier tooltip lists it as throughput, not output")
	_check(BuildingStatus._modifier_tooltip(mod).contains("Throughput (inputs and outputs together):"), "AC26.2 under its own heading")
	_fresh()


## AC26.6: the research panel's words say throughput where the node now gives throughput.
func _test_descriptions() -> void:
	var csv := FileAccess.get_file_as_string("res://data/research_unlocks.csv")
	_check(csv.contains("Increases Furnace throughput by 10% permanently.") and csv.contains("Coal Power Plants burn 15% less coal permanently.")
		and csv.contains("Increases rubber output by 5% permanently.") and not csv.contains("Increases Chemical Plant output by 5% permanently."),
		"AC26.6 node descriptions say what they now do")


## AC26.7: a save from before P5 loses converted output bonuses, old ids included, and gains the new effects.
func _test_stale_research_modifiers_pruned() -> void:
	_fresh()
	Modifiers.add({"id": "rn_reheat_turbine_cycles", "domain": "recipe_output", "target_match": {"building_id": "b_003"}, "pct": 10.0, "source": "research_node"})
	Modifiers.add({"id": "cfr_chem_output", "domain": "recipe_output", "target_match": {"building_id": "b_012"}, "pct": 5.0, "source": "research:continuous_flow_reactors"})
	Modifiers.add({"id": "quest_kept", "domain": "recipe_output", "pct": 5.0, "source": "quest:mm_ship_coal"})
	Modifiers.prune_stale_unlock_modifiers()
	Modifiers.reapply_unlock_modifiers({"Reheat Turbine Cycles": true, "Continuous-Flow Reactors": true})
	var by_id := {}
	for m: Dictionary in Modifiers.active():
		by_id[str(m.id)] = m
	_check(not by_id.has("rn_reheat_turbine_cycles") and by_id.has("rn_reheat_turbine_labour") and by_id.has("rn_reheat_turbine_maint"),
		"AC26.7 a node rebuilt under new ids drops its old output bonus")
	_check(str((by_id.get("cfr_chem_output", {}) as Dictionary).get("domain", "")) == "throughput", "AC26.7 a node keeping its id is re-derived as throughput")
	_check(by_id.has("quest_kept"), "AC27.2 an earned mission reward is left as it was saved")
	_fresh()


## AC27.1: the output mission rewards are timed, and say so.
func _test_mission_rewards_timed() -> void:
	var boards: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/mission_boards.json"))
	var want := {"mm_ship_coal": 20, "t_port": 15, "gp_firm": 20, "ef_scale": 20, "br_factory": 20, "br_chemistry": 20}
	var nodes := {}
	for board: Dictionary in boards.boards:
		for n: Dictionary in board.get("nodes", []):
			nodes[str(n.get("id", ""))] = n
	var wrong := PackedStringArray()
	for id: String in want:
		var reward: Dictionary = (nodes.get(id, {}) as Dictionary).get("reward", {})
		var m: Dictionary = reward.get("modifier", {})
		if int(m.get("turns", 0)) != int(want[id]) or not str(reward.get("text", "")).ends_with("for %d turns" % int(want[id])):
			wrong.append(id)
	_check(wrong.is_empty(), "AC27.1 each output reward lasts its turns and says so (wrong: %s)" % ", ".join(wrong))
	var furnace_reward: Dictionary = (nodes.get("mm_furnace", {}) as Dictionary).get("reward", {})
	_check((furnace_reward.get("modifiers", []) as Array).all(func(m: Dictionary) -> bool: return int(m.get("turns", 0)) == 0),
		"AC27.1 mm_furnace stays permanent (extraction)")
	_fresh()
	MiniQuest._grant_station(nodes["mm_ship_coal"])
	var granted := Modifiers.active().filter(func(m: Dictionary) -> bool: return str(m.get("source", "")) == "quest:mm_ship_coal")
	_check(granted.size() == 1 and int(granted[0].expires_turn) > 0, "AC27.1 the granted reward expires")
	_fresh()


## AC28.1: the start files name the Original Furnace and mark the anchor; the expanded snapshot carries both.
func _test_start_anchor() -> void:
	for start: String in ["metal_magnate", "glass_merchant"]:
		var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/starts/%s.json" % start))
		var snap := SaveLoad.expand_start_config(cfg)
		var anchors := ((snap.match as Dictionary).buildings as Dictionary).values().filter(func(b: Dictionary) -> bool:
			return bool(b.get("legacy_anchor", false)) and str(b.get("name", "")) == "Original Furnace" and str(b.building_id) == FURNACE)
		var mods: Array = ((snap.modifiers as Dictionary).modifiers as Dictionary).values()
		_check(anchors.size() == 1 and mods.all(func(m: Dictionary) -> bool: return str(m.get("condition", "")) == LegacyPerk.CONDITION),
			"AC28.1 %s: one Original Furnace anchor and every perk held by it" % start)


## AC28.1–AC28.2: the anchor's name; the perk holds while it is the player's and ends for good once it is sold.
func _test_perk_follows_the_furnace() -> void:
	_fresh()
	var iid := _player(FURNACE, PIG_IRON, "tile_9_9")
	var b := BuildingState.get_building(iid)
	b["legacy_anchor"] = true
	b["name"] = "Original Furnace"
	Modifiers.add({"id": "start_metals_magnate_steel", "domain": "recipe_output", "target_match": {"good_internal": "steel"}, "pct": 10.0,
		"label": "Legacy of Metal: +10% steel output", "source": "start:metals_magnate", "condition": LegacyPerk.CONDITION})
	_check(BuildingNaming.of(b) == "Original Furnace" and BuildingNaming.label_for_tile("tile_9_9", iid, FURNACE, PIG_IRON) == "Original Furnace",
		"AC28.1 the anchor is named Original Furnace")
	LegacyPerk.reconcile()
	_check(Modifiers.has("start_metals_magnate_steel"), "AC28.2 the perk holds while the Original Furnace is the player's")
	b["owner"] = "npc_buyer"
	LegacyPerk.reconcile()
	_check(not Modifiers.has("start_metals_magnate_steel"), "AC28.2 sold, the perk ends")
	b["owner"] = MatchState.LOCAL_PLAYER
	LegacyPerk.reconcile()
	_check(not Modifiers.has("start_metals_magnate_steel"), "AC28.2 buying it back does not restore it")
	_fresh()


## AC28.2: a save from before the anchor ties its perk to the start furnace it still owns.
func _test_old_save_migrates() -> void:
	_fresh()
	var iid := _player(FURNACE, PIG_IRON, "tile_9_9")
	Modifiers.add({"id": "start_metals_magnate_iron", "domain": "recipe_output", "target_match": {"good_internal": "iron_ingots"}, "pct": 10.0,
		"label": "Legacy of Metal: +10% iron ingot output", "source": "start:metals_magnate"})
	LegacyPerk.migrate("metal_magnate")
	var b := BuildingState.get_building(iid)
	var condition := ""
	for m: Dictionary in Modifiers.active():
		if str(m.id) == "start_metals_magnate_iron":
			condition = str(m.get("condition", ""))
	_check(bool(b.get("legacy_anchor", false)) and str(b.get("name", "")) == "Original Furnace" and condition == LegacyPerk.CONDITION,
		"AC28.2 an old save's start furnace becomes the anchor and its perk is held by it")
	LegacyPerk.reconcile()
	_check(Modifiers.has("start_metals_magnate_iron"), "AC28.2 and the perk carries on")
	_fresh()


## AC28.3: the condition reads the same wherever the perk is shown.
func _test_condition_copy() -> void:
	var tip := BuildingStatus._modifier_tooltip({"parts": [{"pct": 10.0, "label": "Legacy of Metal: +10% steel output", "condition": LegacyPerk.CONDITION}], "text": "+10%"})
	_check(tip.contains("While the original furnace is still owned"), "AC28.3 the output modifier tooltip prints the condition")
	for f: String in ["res://scripts/metal_magnate_intro.gd", "res://scripts/glass_merchant_intro.gd"]:
		_check(FileAccess.get_file_as_string(f).contains("legacy_perk.gd\").CONDITION_TEXT"), "AC28.3 %s prints it under the bonus" % f.get_file())
