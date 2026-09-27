extends "res://tests/test_base.gd"
## The People panel's DS2 look (docs/people-ds2-plan.md, UiPrefs.use_people_ds2) and the figures it shows.

const FEATURE := "people"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_people_ds2_switch": ["people", "ui"],
	"_test_labour_headcount": ["people", "production"],
	"_test_people_ds2_advisors": ["people", "advisors", "ui"],
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


## The DS2 Advisors tab: ten places in the council's seat order, each in the state seat_status.gd gives it (the lamp
## green when the seat returns more than it costs, amber otherwise; every effect in words; the bonus, salary and
## net on screens by the owner's rule), a padlock only on a seat not yet opened, an open seat's Assign key; Add
## advisor slides the picker in over the table; a candidate's dossier takes a seat key and hires through the
## same confirm as today's tab; the body is never wider than its scroll.
func _test_people_ds2_advisors() -> void:
	var was: bool = UiPrefs.use_people_ds2
	var saved := {"ids": AdvisorState.permanent_advisor_ids.duplicate(), "seats": AdvisorState.advisor_seats.duplicate(),
		"recruited": AdvisorState.recruited_advisor_ids.duplicate(), "all": AdvisorState.all_seats_unlocked,
		"cap": AdvisorState.max_advisor_slots, "turn": TurnManager.current_turn}
	TurnManager.current_turn = maxi(TurnManager.current_turn, DecisionState.FOUNDER_DECISION_TURN)
	AdvisorState.advisor_seats.clear()
	AdvisorState.permanent_advisor_ids = ["vera", "tom"]
	AdvisorState.recruited_advisor_ids = ["gerald"]
	AdvisorState.all_seats_unlocked = false
	AdvisorState.max_advisor_slots = 3
	AdvisorState.assign_advisor_to_seat("cfo", "vera")
	AdvisorState.assign_advisor_to_seat("coo", "tom")
	UiPrefs.set_use_people_ds2(true)
	var pp: PanelContainer = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	pp.size = Vector2(800, 1000)
	await get_tree().process_frame
	await get_tree().process_frame
	var tab: Control = pp.find_child("AdvisorsDs2", true, false)
	var room: Control = pp.find_child("Boardroom", true, false)
	_check(tab != null and room != null, "people ds2 advisors: the boardroom is built")
	if tab == null or room == null:
		UiPrefs.set_use_people_ds2(was)
		pp.queue_free()
		return
	var status := preload("res://scripts/people_ds2/seat_status.gd")
	var order: Array[String] = []
	var states_ok := true
	for place in room.find_children("Seat_*", "", true, false):
		var sid := str(place.name).trim_prefix("Seat_")
		order.append(sid)
		states_ok = states_ok and str(place.get("state")) == str(status.seat(sid).state)
	var want: Array[String] = []
	for sid in AdvisorState.SEAT_DEFINITIONS:
		want.append(str(sid))
	_check(order == want, "people ds2 advisors: all ten seats, in the council's order (%s)" % ", ".join(order))
	_check(states_ok, "people ds2 advisors: each place is in its seat_status state")
	for sid in ["cfo", "coo"]:
		var st: Dictionary = status.seat(sid)
		var place: Control = room.find_child("Seat_%s" % sid, true, false)
		var lamp: Control = place.find_child("SeatLamp", true, false)
		var tone := "ok" if float(st.net) > 0.0 else "warn"
		_check(lamp != null and str(lamp.get_meta("tone", "")) == tone,
			"people ds2 advisors: %s's lamp is %s for a net of %.2f" % [sid, tone, float(st.net)])
		var effects: Control = place.find_child("SeatEffects", true, false)
		_check(effects != null and effects.get_child_count() == AdvisorState.advisor_seat_effect_list(str(st.advisor), sid).size(),
			"people ds2 advisors: %s shows every effect of the seat" % sid)
		var figs := [str(place.find_child("AdvisorBonusValue", true, false).get_meta("figure")),
			str(place.find_child("AdvisorSalaryValue", true, false).get_meta("figure")),
			str(place.find_child("AdvisorNetBenefitValue", true, false).get_meta("figure"))]
		var parts := preload("res://scripts/people_ds2/parts.gd")
		_check(figs == [parts.money_text(float(st.bonus)), parts.money_text(float(st.salary)), parts.money_text(float(st.net))],
			"people ds2 advisors: %s's bonus, salary and net are the council's figures (%s)" % [sid, ", ".join(figs)])
	var locked: Control = room.find_child("Seat_vp_logistics", true, false)
	var open: Control = room.find_child("Seat_technical_director", true, false)
	_check(str(locked.get("state")) == "locked" and _folder_locked(locked) == 1, "people ds2 advisors: a seat not yet opened has its padlock")
	_check(str(open.get("state")) == "open" and open.find_child("AssignSeat_technical_director", true, false) is Button
		and _folder_locked(open) == -1, "people ds2 advisors: an open seat has its Assign key and no folder")
	AdvisorState.max_advisor_slots = 2
	AdvisorState.advisors_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var full: Control = pp.find_child("Seat_technical_director", true, false)
	_check(full != null and str(full.get("state")) == "full" and _folder_locked(full) == 0,
		"people ds2 advisors: on a full council an opened seat's folder is closed without a padlock")
	AdvisorState.max_advisor_slots = 3
	AdvisorState.advisors_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var scroll: ScrollContainer = pp.find_child("AdvisorsScroll", true, false)
	var body: Control = pp.find_child("AdvisorsBody", true, false)
	_check(body.get_combined_minimum_size().x <= scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x + 0.5,
		"people ds2 advisors: the body (min %.0f) fits its scroll (%.0f)" % [body.get_combined_minimum_size().x, scroll.size.x])
	var add := pp.find_child("AdvisorAddNewButton", true, false) as Button
	_check(add != null, "people ds2 advisors: Add advisor keeps its name")
	add.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	# The roster is rebuilt under the sheet (the boardroom held above is freed): look it up again.
	_check(bool(tab.call("sheet_open")) and pp.find_child("Candidate_gerald", true, false) != null
		and pp.find_child("Boardroom", true, false) != null,
		"people ds2 advisors: Add advisor slides the picker over the table, the table kept")
	tab.call("_set_view", {"mode": "detail", "sel_id": "gerald", "back": "picker"})
	await get_tree().process_frame
	var confirm := pp.find_child("AdvisorHireAssignButton", true, false) as Button
	_check(pp.find_child("AdvisorBonusPrompt", true, false) != null and confirm != null and confirm.disabled,
		"people ds2 advisors: a candidate's dossier opens with no seat chosen and Hire disabled")
	var key := pp.find_child("AdvisorSeatChoice_technical_director", true, false) as Button
	_check(key != null and pp.find_child("AdvisorSeatChoice_vp_logistics", true, false) == null,
		"people ds2 advisors: only opened, free seats are offered")
	if key != null:
		key.pressed.emit()
		await get_tree().process_frame
		confirm = pp.find_child("AdvisorHireAssignButton", true, false) as Button
		_check(pp.find_child("AdvisorBonusSection", true, false) != null and pp.find_child("AdvisorNetBenefitValue", true, false) != null
			and bool((pp.find_child("AdvisorSeatChoice_technical_director", true, false) as Button).get("chosen"))
			and confirm != null and not confirm.disabled, "people ds2 advisors: choosing a seat shows what they bring and enables Hire")
		confirm.pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(AdvisorState.get_advisor_in_seat("technical_director") == "gerald" and not bool(tab.call("sheet_open")),
			"people ds2 advisors: Hire and assign seats the advisor and the sheet goes")
	UiPrefs.set_use_people_ds2(was)
	pp.queue_free()
	await get_tree().process_frame
	AdvisorState.advisor_seats = saved.seats
	AdvisorState.permanent_advisor_ids = saved.ids
	AdvisorState.recruited_advisor_ids = saved.recruited
	AdvisorState.all_seats_unlocked = saved.all
	AdvisorState.max_advisor_slots = saved.cap
	TurnManager.current_turn = saved.turn
	AdvisorState.reconcile_advisor_modifiers()
	AdvisorState.advisors_changed.emit()


## 1 when a place has its padlocked folder, 0 its folder without the padlock, -1 no folder.
func _folder_locked(place: Node) -> int:
	var folder := place.find_child("Folder", true, false)
	if folder == null:
		return -1
	return 1 if bool(folder.get("locked")) else 0
