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
