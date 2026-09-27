extends "res://tests/test_base.gd"
## The People panel's DS2 look (docs/people-ds2-plan.md, UiPrefs.use_people_ds2) and the figures it shows.

const FEATURE := "people"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_people_ds2_switch": ["people", "ui"],
	"_test_labour_headcount": ["people", "production"],
	"_test_people_ds2_advisors": ["people", "advisors", "ui"],
	"_test_people_ds2_labour": ["people", "production", "ui"],
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


## The DS2 Labour tab: the time clock shows the overview's figures (cost, share of base, ten turns) and its bell's
## lamp is lit only at the floor; the doors carry the workforce by kind; six knobs stand where the policies are and
## turning one sets the policy; the notice board pins each policy in force and, on hover, the option under the
## pointer; the lockers of policies not yet open are padlocked and their switches dead; the body fits its scroll.
func _test_people_ds2_labour() -> void:
	MatchState.reset()
	var was: bool = UiPrefs.use_people_ds2
	var ids: Array[String] = []
	for sp: Array in [["b_003", "r_004", "tile_10_2"], ["b_007", "r_009", "tile_13_2"]]:
		BuildingState.tile_land_owned[str(sp[2])] = 200
		ids.append(BuildingState.add_building(str(sp[0]), str(sp[1]), str(sp[2]), MatchState.LOCAL_PLAYER, ""))
	UiPrefs.set_use_people_ds2(true)
	var pp: PanelContainer = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	pp.size = Vector2(800, 1000)
	await get_tree().process_frame
	var shell: Control = pp.find_child("PeopleDs2", false, false)
	shell.call("show_tab", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var tab: Control = pp.find_child("LabourDs2", true, false)
	var clock: Control = pp.find_child("TimeClock", true, false)
	var ov: Dictionary = Production.labour_overview()
	var figs: Dictionary = clock.get_meta("figures", {}) if clock != null else {}
	_check(clock != null and is_equal_approx(float(figs.get("current", -1.0)), float(ov.current))
		and is_equal_approx(float(figs.get("factor_pct", -1.0)), float(ov.factor_pct))
		and is_equal_approx(float(figs.get("est_10_turns", -1.0)), float(ov.est_10_turns)),
		"people ds2 labour: the clock shows the overview's cost, share of base and ten turn figure")
	var led: Control = clock.find_child("LabourCostNow", true, false).find_child("Led", true, false) if clock != null else null
	var parts := preload("res://scripts/people_ds2/parts.gd")
	_check(led != null and str(led.call("figure")).strip_edges() == str(preload("res://scripts/ds2/money_figure.gd").screen(float(ov.current)).figure),
		"people ds2 labour: the cost's screen reads %s" % (str(led.call("figure")) if led != null else "none"))
	_check(not bool(clock.find_child("FloorLamp", true, false).get_meta("lit")), "people ds2 labour: the bell's lamp is dark above the floor")
	var hc: Dictionary = Production.labour_headcount()
	var doors_ok := true
	for kind in ["unskilled", "skilled", "high_skilled"]:
		var door: Control = pp.find_child("Door_%s" % kind, true, false)
		doors_ok = doors_ok and door != null and int(door.get("count")) == int(hc[kind])
	_check(doors_ok and int(hc.unskilled) > 0, "people ds2 labour: each door carries its kind's headcount (%s)" % str(hc))
	var knobs := ["effort", "idle", "safety", "pension", "bonus", "profit"]
	var all_knobs := true
	for k in knobs:
		all_knobs = all_knobs and pp.find_child("Knob_%s" % k, true, false) != null
	var effort: Control = pp.find_child("Knob_effort", true, false)
	_check(all_knobs and effort != null and int(effort.get("value")) == 2, "people ds2 labour: six knobs, work effort at Standard")
	_check(pp.find_child("Notice_effort", true, false) != null and str(pp.find_child("Notice_effort", true, false).get_meta("notice")) == "Work effort|Standard",
		"people ds2 labour: the notice board pins the effort in force")
	var lean: Button = (effort.get("option_buttons") as Array)[0]
	lean.mouse_entered.emit()
	var hover: Control = pp.find_child("HoverCard", true, false)
	_check(hover != null and hover.visible and str(hover.get_meta("notice")) == "Work effort|Lean", "people ds2 labour: hovering an option pins its card on top")
	lean.mouse_exited.emit()
	effort.set("value", 1)
	_check(is_equal_approx(LabourState.labour_multiplier, 0.8), "people ds2 labour: turning the knob to Lean sets the effort")
	LabourState.set_labour_multiplier(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var tenure: Control = pp.find_child("Locker_%s" % LabourState.WORKFORCE_POLICY_LONG_TENURE, true, false)
	var leave: Control = pp.find_child("Locker_%s" % LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, true, false)
	_check(tenure != null and bool(tenure.get("locked")) and (tenure.find_child("Switch", true, false) as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE
		and leave != null and not bool(leave.get("locked")), "people ds2 labour: a policy not yet open is padlocked, its switch dead")
	var sw: Control = leave.find_child("Switch", true, false)
	sw.emit_signal("toggled", true)
	_check(LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE), "people ds2 labour: a locker's switch sets its policy")
	LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, false)
	var scroll: ScrollContainer = pp.find_child("LabourScroll", true, false)
	var body: Control = pp.find_child("LabourBody", true, false)
	_check(body.get_combined_minimum_size().x <= scroll.size.x - scroll.get_v_scroll_bar().get_combined_minimum_size().x + 0.5,
		"people ds2 labour: the body (min %.0f) fits its scroll (%.0f)" % [body.get_combined_minimum_size().x, scroll.size.x])
	# At the floor: a labour cut deep enough that every building's factor bottoms out.
	Modifiers.add({"id": "test_people_floor", "domain": "labour_headcount", "pct": -90.0, "label": "test", "source": "test", "target": "*"})
	TurnManager.turn_resolution_completed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var floor_lamp: Control = pp.find_child("FloorLamp", true, false)
	_check(bool(Production.labour_overview().at_floor) and floor_lamp != null and bool(floor_lamp.get_meta("lit")),
		"people ds2 labour: at the floor the bell's lamp is lit")
	Modifiers.remove("test_people_floor")
	UiPrefs.set_use_people_ds2(was)
	pp.queue_free()
	await get_tree().process_frame
	for iid in ids:
		BuildingState.remove_building(iid)
	MatchState.reset()
