extends "res://tests/test_base.gd"
## The People panel's labour card: the labour it shows is what the turn charges, and its share of base and its
## ten-turn estimate come from the keys Production.labour_overview() returns.

const FEATURE := "production"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_labour_charge_is_the_turn_charge": ["people", "production"],
	"_test_labour_card_reads_the_overview": ["people", "production", "ui"],
}


## After a turn, every building's labour_charge (at that turn's wages and run state) sums to the summary's
## labour_paid, and labour_overview's `current` is that sum. A paused building carries no workforce; one that did
## not run is paid the idle share.
func _test_labour_charge_is_the_turn_charge() -> void:
	MatchState.reset()
	var saved_share: float = LabourState.idle_labour_pay_share
	LabourState.set_idle_labour_pay_share(0.5)
	var ids: Array[String] = []
	for sp: Array in [["b_003", "r_004", "tile_10_2"], ["b_007", "r_009", "tile_13_2"], ["b_001", "r_001", "tile_12_2"]]:
		BuildingState.tile_land_owned[str(sp[2])] = 200
		ids.append(BuildingState.add_building(str(sp[0]), str(sp[1]), str(sp[2]), MatchState.LOCAL_PLAYER, ""))
	BuildingWorks.set_building_paused(ids[2], true)
	var before: Array = Modifiers.active().map(func(m: Dictionary) -> String: return str(m.id))
	TurnManager.commit_turn()
	await _await_turn_settled()
	var paid := float(Production.last_turn_summary.get("labour_paid", 0.0))
	# A research node unlocked by doing during the turn (Operational Team Managers) cuts labour from the next
	# turn on; take any modifier the turn added off while the turn's own charge is worked out.
	var added: Array[Dictionary] = []
	for m: Dictionary in Modifiers.active():
		if not before.has(str(m.id)):
			added.append(m.duplicate())
	for m in added:
		Modifiers.remove(str(m.id))
	# The charge was worked out at the turn's wages; the counter has since moved on one.
	TurnManager.current_turn -= 1
	var charged := 0.0
	for iid in ids:
		charged += Production.labour_charge(BuildingState.get_building(iid), bool(Production.last_turn_run.get(iid, false)))
	var ov: Dictionary = Production.labour_overview()
	var idle := ids[1] if not Production.last_turn_run.has(ids[1]) else ids[0]
	var full := Production._calculate_labour_cost(BuildingState.get_building(idle))
	var idle_charge := Production.labour_charge(BuildingState.get_building(idle), false)
	TurnManager.current_turn += 1
	for m in added:
		Modifiers.add(m)
	_check(paid > 0.0 and absf(paid - charged) < 0.001, "labour: the turn paid what labour_charge quotes (£%.2f and £%.2f)" % [paid, charged])
	_check(absf(float(ov.current) - charged) < 0.001 and bool(ov.has_buildings),
		"labour: the People panel's figure is the turn's charge (£%.2f)" % float(ov.current))
	_check(Production.labour_charge(BuildingState.get_building(ids[2]), true) == 0.0, "labour: a paused building carries no workforce")
	_check(full > 0.0 and absf(idle_charge - full * 0.5) < 0.0001, "labour: a building that did not run is paid the idle share")
	LabourState.set_idle_labour_pay_share(saved_share)
	for iid in ids:
		BuildingState.remove_building(iid)
	MatchState.reset()


## The Labour tab reads the overview's own keys: with a COO seated (labour cost 10% lower) its share of base is
## no longer 100%, and its ten-turn estimate is est_10_turns.
func _test_labour_card_reads_the_overview() -> void:
	MatchState.reset()
	var iid := BuildingState.add_building("b_007", "r_009", "tile_13_2", MatchState.LOCAL_PLAYER, "")
	var saved_ids: Array = AdvisorState.permanent_advisor_ids.duplicate()
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate()
	AdvisorState.permanent_advisor_ids = ["tom"]
	AdvisorState.assign_advisor_to_seat("coo", "tom")
	AdvisorState.reconcile_advisor_modifiers()
	var ov: Dictionary = Production.labour_overview()
	var tab: Control = load("res://scripts/labour_policy_tab.gd").new()
	add_child(tab)
	await get_tree().process_frame
	_check(float(ov.factor_pct) < 99.9, "labour: a seated COO's labour cut moves the share of base (%.1f%%)" % float(ov.factor_pct))
	_check(_tree_has_label_text(tab, "%.0f%% of base" % float(ov.factor_pct)) and not _tree_has_label_text(tab, "100% of base"),
		"labour: the Labour tab shows the overview's share of base, not 100%")
	_check(_tree_has_label_text(tab, "10-turn estimate £%.2f" % float(ov.est_10_turns)),
		"labour: the Labour tab shows the overview's ten-turn estimate")
	tab.queue_free()
	AdvisorState.unassign_seat("coo")
	AdvisorState.permanent_advisor_ids = saved_ids
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.reconcile_advisor_modifiers()
	BuildingState.remove_building(iid)
	MatchState.reset()
