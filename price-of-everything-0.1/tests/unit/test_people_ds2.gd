extends "res://tests/test_base.gd"
## The People panel's DS2 look (docs/people-ds2-plan.md, UiPrefs.use_people_ds2) and the figures it shows.

const FEATURE := "people"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_people_ds2_switch": ["people", "ui"],
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
