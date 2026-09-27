extends "res://tests/test_base.gd"
## The People panel's DS2 look (docs/people-ds2-plan.md, UiPrefs.use_people_ds2) and the figures it shows.

const FEATURE := "people"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_people_ds2_switch": ["people", "ui"],
	"_test_labour_headcount": ["people", "production"],
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


## The workforce by kind counts every running player building's headcount, none for a paused one.
func _test_labour_headcount() -> void:
	MatchState.reset()
	var ids: Array[String] = []
	for sp: Array in [["b_003", "r_004", "tile_10_2"], ["b_007", "r_009", "tile_13_2"], ["b_001", "r_001", "tile_12_2"]]:
		BuildingState.tile_land_owned[str(sp[2])] = 200
		ids.append(BuildingState.add_building(str(sp[0]), str(sp[1]), str(sp[2]), MatchState.LOCAL_PLAYER, ""))
	BuildingWorks.set_building_paused(ids[2], true)
	var heads := Vector3i.ZERO
	for iid in ids.slice(0, 2):
		heads += Production.labour_heads(BuildingState.get_building(iid))
	var hc: Dictionary = Production.labour_headcount()
	_check(int(hc.unskilled) == heads.x and int(hc.skilled) == heads.y and int(hc.high_skilled) == heads.z and heads != Vector3i.ZERO,
		"labour: the headcount counts the running buildings' workforce, none for a paused one (%s)" % str(hc))
	for iid in ids:
		BuildingState.remove_building(iid)
	MatchState.reset()
