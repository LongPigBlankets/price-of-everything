extends "res://tests/test_base.gd"
## The People panel's DS2 look (docs/people-ds2-plan.md, UiPrefs.use_people_ds2) and the figures it shows.

const FEATURE := "people"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_people_ds2_switch": ["people", "ui"],
	"_test_labour_charge_is_the_turn_charge": ["people", "production"],
	"_test_labour_card_reads_the_overview": ["people", "production", "ui"],
	"_test_seat_card_shows_every_effect": ["people", "advisors", "ui"],
}


## Off, today's panel exactly: the copper pipe frame, the title, a TabContainer with Advisors then Labour, the
## old tabs' scripts and the tutorial's handles, 1220 wide. On, the DS2 shell in their place. Off again, back.
func _test_people_ds2_switch() -> void:
	var was: bool = UiPrefs.use_people_ds2
	UiPrefs.set_use_people_ds2(false)
	var pp: PanelContainer = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	await get_tree().process_frame
	_check(_is_v2(pp), "people ds2: off, today's panel (pipe frame, TabContainer Advisors then Labour, the old tabs)")
	_check(pp.find_child("AdvisorAddNewButton", true, false) != null and pp.name == "PeoplePanel",
		"people ds2: off, the tutorial's handles are where they were")
	var vp := pp.get_viewport_rect().size
	_check(is_equal_approx(pp.offset_right - pp.offset_left, minf(1220.0, vp.x - 60.0)), "people ds2: off, today's width")
	UiPrefs.set_use_people_ds2(true)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(pp.find_child("PeopleDs2", false, false) != null and pp.find_children("*", "TabContainer", true, false).is_empty()
		and pp.name == "PeoplePanel", "people ds2: on, the DS2 shell in place of the tabs")
	_check(is_equal_approx(pp.offset_right - pp.offset_left, minf(800.0, vp.x - 24.0)), "people ds2: on, one width of 800")
	UiPrefs.set_use_people_ds2(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_is_v2(pp) and pp.find_child("PeopleDs2", false, false) == null, "people ds2: off again, today's panel back")
	UiPrefs.set_use_people_ds2(was)
	pp.queue_free()
	await get_tree().process_frame


func _is_v2(pp: PanelContainer) -> bool:
	var sb := pp.get_theme_stylebox("panel")
	var tabs := pp.find_children("*", "TabContainer", true, false)
	if tabs.size() != 1 or sb == null or sb is StyleBoxEmpty:
		return false
	var tc := tabs[0] as TabContainer
	return tc.get_tab_count() == 2 and tc.get_tab_title(0) == "Advisors" and tc.get_tab_title(1) == "Labour" \
		and (tc.get_child(0).get_script() as Script).resource_path == "res://scripts/advisor_council_tab.gd" \
		and (tc.get_child(1).get_script() as Script).resource_path == "res://scripts/labour_policy_tab.gd" \
		and _tree_has_label_text(pp, "People")


## The labour the People panel shows is the labour the turn charges: after a turn, every building's
## labour_charge (at that turn's wages and run state) sums to the summary's labour_paid, and labour_overview's
## `current` is that sum. A paused building carries no workforce; one that did not run is paid the idle share.
## The headcount counts the same buildings.
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
	var heads := Vector3i.ZERO
	for iid in ids:
		var b := BuildingState.get_building(iid)
		charged += Production.labour_charge(b, bool(Production.last_turn_run.get(iid, false)))
		if iid != ids[2]:
			heads += Production.labour_heads(b)
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
	_check(full > 0.0 and absf(idle_charge - full * 0.5) < 0.0001,
		"labour: a building that did not run is paid the idle share")
	var hc: Dictionary = Production.labour_headcount()
	_check(int(hc.unskilled) == heads.x and int(hc.skilled) == heads.y and int(hc.high_skilled) == heads.z and heads != Vector3i.ZERO,
		"labour: the headcount counts the running buildings' workforce, none for a paused one (%s)" % str(hc))
	LabourState.set_idle_labour_pay_share(saved_share)
	for iid in ids:
		BuildingState.remove_building(iid)
	MatchState.reset()


## The Labour tab reads the overview's own keys: its percentage is factor_pct (a COO's labour cut shows) and its
## ten-turn estimate is est_10_turns.
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
	_check(_tree_has_label_text(tab, "%.0f%% of base" % float(ov.factor_pct))
		and _tree_has_label_text(tab, "10-turn estimate £%.2f" % float(ov.est_10_turns)),
		"labour: the Labour tab shows the overview's share of base and ten-turn estimate")
	tab.queue_free()
	AdvisorState.unassign_seat("coo")
	AdvisorState.permanent_advisor_ids = saved_ids
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.reconcile_advisor_modifiers()
	BuildingState.remove_building(iid)
	MatchState.reset()


## A seated advisor's card names every effect of the seat, not only the first.
func _test_seat_card_shows_every_effect() -> void:
	var saved_ids: Array = AdvisorState.permanent_advisor_ids.duplicate()
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate()
	AdvisorState.permanent_advisor_ids = ["tom"]
	AdvisorState.assign_advisor_to_seat("coo", "tom")
	var tab: Control = load("res://scripts/advisor_council_tab.gd").new()
	add_child(tab)
	await get_tree().process_frame
	var effects: Array = AdvisorState.advisor_seat_effect_list("tom", "coo")
	var all_named := effects.size() > 1
	for eff in effects:
		all_named = all_named and _tree_has_label_text(tab, tab.call("_effect_text", eff))
	_check(all_named, "advisors: the COO's card names all %d of its effects" % effects.size())
	tab.queue_free()
	AdvisorState.unassign_seat("coo")
	AdvisorState.permanent_advisor_ids = saved_ids
	AdvisorState.advisor_seats = saved_seats
