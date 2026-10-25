extends "res://tests/test_base.gd"
## The People panel's DS2 look (docs/people-ds2-plan.md) and the figures it shows.

const FEATURE := "people"
## Tests that also belong to other features (run under any of their tags).
const TAGS := {
	"_test_people_ds2_panel": ["people", "ui"],
	"_test_labour_headcount": ["people", "production"],
	"_test_people_ds2_advisors": ["people", "advisors", "ui"],
	"_test_people_ds2_labour": ["people", "production", "ui"],
	"_test_people_ds2_shell": ["people", "ui"],
	"_test_cfo_worth_on_todays_loans": ["people", "advisors", "finance"],
	"_test_seat_card_shows_every_effect": ["people", "advisors", "ui"],
}


## The panel is the DS2 shell, no TabContainer, under its name, one width of 800.
func _test_people_ds2_panel() -> void:
	var pp: PanelContainer = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := pp.get_viewport_rect().size
	_check(pp.find_child("PeopleDs2", false, false) != null and pp.find_children("*", "TabContainer", true, false).is_empty()
		and pp.name == "PeoplePanel", "people ds2: the DS2 shell, no tabs")
	_check(is_equal_approx(pp.offset_right - pp.offset_left, minf(800.0, vp.x - 24.0)), "people ds2: one width of 800")
	pp.queue_free()
	await get_tree().process_frame


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
## council tab's confirm; the body is never wider than its scroll.
func _test_people_ds2_advisors() -> void:
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
	var pp: PanelContainer = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	pp.size = Vector2(800, 1000)
	await get_tree().process_frame
	await get_tree().process_frame
	var tab: Control = pp.find_child("AdvisorsDs2", true, false)
	var room: Control = pp.find_child("Boardroom", true, false)
	_check(tab != null and room != null, "people ds2 advisors: the boardroom is built")
	if tab == null or room == null:
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
		# The Expansion Director seat exists only while Andrew Keeler holds it.
		if not AdvisorState.FOUNDER_ONLY_SEATS.has(str(sid)):
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
	var count: Control = pp.find_child("CouncilCount", true, false)
	_check(count != null and str(count.get("text")) == "2/3 ADVISORS", "people ds2 advisors: the council plate reads 2/3 ADVISORS")
	var unopened: Control = room.find_child("Seat_vp_logistics", true, false)
	var open: Control = room.find_child("Seat_technical_director", true, false)
	var req: Label = unopened.find_child("Requirement", true, false)
	_check(str(unopened.get("state")) == "unopened" and _folder_locked(unopened) == 0 and req != null
		and req.text == "Opens with Executive Search", "people ds2 advisors: with a slot free, a seat not yet opened says what opens it, no padlock")
	_check(str(open.get("state")) == "open" and open.find_child("AssignSeat_technical_director", true, false) is Button
		and _folder_locked(open) == -1, "people ds2 advisors: with a slot free, an open seat has its Assign key and no folder")
	AdvisorState.max_advisor_slots = 2
	AdvisorState.advisors_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var padlocks := 0
	var empty := 0
	for place in pp.find_child("Boardroom", true, false).find_children("Seat_*", "", true, false):
		if AdvisorState.get_advisor_in_seat(str(place.name).trim_prefix("Seat_")) == "":
			empty += 1
			padlocks += 1 if _folder_locked(place) == 1 and str(place.get("state")) == "locked" else 0
	_check(empty == 8 and padlocks == 8, "people ds2 advisors: with no slot free, every empty seat has its padlock (%d of %d)" % [padlocks, empty])
	_check(str(pp.find_child("CouncilCount", true, false).get("text")) == "2/2 ADVISORS", "people ds2 advisors: a full council reads 2/2 ADVISORS")
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
	_check((pp.find_child("Candidates", true, false) as GridContainer).columns == 2, "people ds2 advisors: the picker files candidates two to a row")
	tab.call("_set_view", {"mode": "detail", "sel_id": "tom", "back": "roster"})
	await get_tree().process_frame
	var cols: Control = pp.find_child("DossierColumns", true, false)
	_check(cols != null and cols.get_child_count() == 2 and cols.get_child(0).find_child("AdvisorFinancialPreview", true, false) != null
		and cols.get_child(1).find_child("Skills", true, false) != null, "people ds2 advisors: the dossier in two columns, who and cost left, effects and skills right")
	var guard: Control = pp.find_child("DismissKey", true, false)
	_check(guard != null and str(guard.get("layer")) == "guard_dismiss" and not bool(guard.call("is_open")),
		"people ds2 advisors: Dismiss is a guarded cap with its boot, the cover down")
	var fired := [false]
	guard.connect("pressed", func() -> void: fired[0] = true)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = guard.size * 0.5
	click.pressed = true
	guard.call("_gui_input", click)
	click.pressed = false
	guard.call("_gui_input", click)
	_check(bool(guard.call("is_open")) and not fired[0] and AdvisorState.get_advisor_in_seat("coo") == "tom",
		"people ds2 advisors: the first click lifts Dismiss's cover and dismisses nobody")
	guard.call("drop")
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
## lamp is lit only at the floor; the doors carry the workforce by kind; eight knobs stand where the policies are and
## turning one sets the policy; the notice board pins each policy in force and, on hover, the option under the
## pointer; the lockers of policies not yet open are padlocked and their switches dead; the body fits its scroll.
func _test_people_ds2_labour() -> void:
	MatchState.reset()
	var ids: Array[String] = []
	for sp: Array in [["b_003", "r_004", "tile_10_2"], ["b_007", "r_009", "tile_13_2"]]:
		BuildingState.tile_land_owned[str(sp[2])] = 200
		ids.append(BuildingState.add_building(str(sp[0]), str(sp[1]), str(sp[2]), MatchState.LOCAL_PLAYER, ""))
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
	var knobs := ["effort", "idle", "safety", "pension", "bonus", "profit", "union", "week"]
	var all_knobs := true
	for k in knobs:
		all_knobs = all_knobs and pp.find_child("Knob_%s" % k, true, false) != null
	var effort: Control = pp.find_child("Knob_effort", true, false)
	_check(all_knobs and effort != null and int(effort.get("value")) == 2, "people ds2 labour: eight knobs, work effort at Standard")
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
	pp.queue_free()
	await get_tree().process_frame
	for iid in ids:
		BuildingState.remove_building(iid)
	MatchState.reset()


## Phase 1 satisfaction UX (docs/pacing-labour-mining-licensing-spec.md §4.8): the plate's dial, marks, screens,
## band card and ledger; eight knobs in two rows of four with the union and work week printed on their plates;
## stepping the union down asks first; Renege appears only when it is offered; the Advisors key lights while an
## advisor is disloyal.
func _test_people_ds2_satisfaction() -> void:
	MatchState.reset()
	LabourState.policy_throughput_enabled = true
	var pp: PanelContainer = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	pp.size = Vector2(800, 1000)
	await get_tree().process_frame
	pp.call("show_tab", 1)
	LabourState.satisfaction = 20.0
	LabourState.add_target_shift("test_event", "Building sold", -5.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var plate: Control = pp.find_child("Satisfaction", true, false)
	var dial: Control = pp.find_child("SatisfactionDial", true, false)
	var marks: Control = pp.find_child("DialMarks", true, false)
	var tab_script := load("res://scripts/people_ds2/labour_ds2.gd")
	var target := LabourState.target_satisfaction()
	_check(plate != null and dial != null and bool(dial.get("reverse_zones")) and is_equal_approx(float(dial.get("value")), tab_script.dial_value(20.0))
		and marks != null and is_equal_approx(float(marks.get("target_v")), tab_script.dial_value(target))
		and is_equal_approx(float(marks.get("ten_v")), tab_script.dial_value(LabourState.projected_satisfaction(10))),
		"AC4.3 people ds2 labour: the dial's needle, target marker and ten turn ghost")
	var now_screen: Control = pp.find_child("SatisfactionNow", true, false)
	var target_screen: Control = pp.find_child("SatisfactionTarget", true, false)
	_check(now_screen != null and int(now_screen.get_meta("value")) == 20 and target_screen != null
		and int(target_screen.get_meta("value")) == roundi(target), "AC4.3 people ds2 labour: the screens read now and target")
	var ledger: Control = pp.find_child("SatisfactionLedger", true, false)
	var lines := 0
	var sold := false
	for n: Node in ledger.find_children("LedgerLine_*", "", true, false):
		lines += 1
		sold = sold or str(n.get_meta("ledger", "")) == "Building sold, 10 turns|\u22125"
	_check(lines == LabourState.satisfaction_contributions().size() + LabourState.target_shifts.size() and sold,
		"AC4.3 people ds2 labour: the ledger lists every contribution and shift, signed")
	var band_card: Control = pp.find_child("BandCard", true, false)
	_check(band_card != null and (band_card.find_child("Title", true, false) as Label).text == str(LabourState.band_summary().title),
		"AC4.3 people ds2 labour: the band card names the band")
	var grid: GridContainer = pp.find_child("KnobGrid", true, false)
	var week: Control = pp.find_child("Knob_week", true, false)
	var union: Control = pp.find_child("Knob_union", true, false)
	var week_faces: Array = []
	for b: Button in (week.get("option_buttons") as Array):
		week_faces.append(str((b.get_child(0) as Control).get("text")))
	_check(grid != null and grid.columns == 4 and grid.get_child_count() == 8 and week_faces == ["35", "40", "45", "50"]
		and int(week.get("value")) == 3, "AC4.4 people ds2 labour: eight knobs in rows of four, the week's hours on its plates, 45 chosen")
	# Union up signs at once; down asks first.
	union.set("value", 3)
	await get_tree().process_frame
	_check(LabourState.union_tier() == LabourState.UNION_COMPREHENSIVE, "AC4.4 people ds2 labour: turning the union to Full signs Comprehensive")
	await get_tree().process_frame
	await get_tree().process_frame
	union = pp.find_child("Knob_union", true, false)
	union.set("value", 1)
	await get_tree().process_frame
	var dialog: ConfirmationDialog = pp.find_child("UnionStepDown", true, false)
	_check(dialog != null and LabourState.union_tier() == LabourState.UNION_COMPREHENSIVE, "AC2.18 people ds2 labour: stepping the union down asks first")
	MatchState.one_off_charges.clear()
	dialog.confirmed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(LabourState.union_tier() == LabourState.UNION_NONE and LabourState.can_renege(), "AC2.18 people ds2 labour: confirming steps the union down")
	var renege: Control = pp.find_child("RenegeKey", true, false)
	var halving: Control = pp.find_child("HalvingLine", true, false)
	_check(renege != null and halving != null, "AC4.5 people ds2 labour: Renege and the halving line appear once renege is offered")
	var sat_before: float = LabourState.satisfaction
	renege.emit_signal("pressed")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not LabourState.union_halving_active and is_equal_approx(LabourState.satisfaction, sat_before - 50.0)
		and pp.find_child("RenegeKey", true, false) == null, "AC4.5 people ds2 labour: Renege ends the halving and leaves the plate")
	# AC4.2: the Advisors key lights while a seated advisor is disloyal.
	var term := preload("res://scripts/debug_terminal.gd")
	var was_unlocked: bool = term._demo_unlocked
	term._demo_unlocked = true
	var seats_was: Dictionary = AdvisorState.advisor_seats.duplicate(true)
	var loyal_was: Dictionary = AdvisorState.advisor_loyalty.duplicate(true)
	AdvisorState.advisor_seats["cfo"] = "vera"
	AdvisorState.advisor_loyalty["vera"] = -6.0
	AdvisorState.advisor_loyalty_changed.emit("vera", -6.0)
	var key: Control = pp.find_child("TabKey_Advisors", true, false)
	var lit := key != null and (key.get("lamp") as Color).a > 0.0
	AdvisorState.advisor_loyalty["vera"] = 5.0
	AdvisorState.advisor_loyalty_changed.emit("vera", 5.0)
	_check(lit and (key.get("lamp") as Color).a == 0.0, "AC4.2 people ds2: the Advisors key lights while an advisor is disloyal, and goes dark after")
	AdvisorState.advisor_seats = seats_was
	AdvisorState.advisor_loyalty = loyal_was
	term._demo_unlocked = was_unlocked
	MatchState.one_off_charges.clear()
	pp.queue_free()
	await get_tree().process_frame
	MatchState.reset()


## The DS2 shell: two latching tab keys (the open one latched), Close asks the panel to close, the lamp's overlay
## is drawn last, and every label under the panel takes back part of its shade.
func _test_people_ds2_shell() -> void:
	var pp: PanelContainer = load("res://scripts/people_panel.gd").new()
	add_child(pp)
	pp.size = Vector2(800, 1000)
	await get_tree().process_frame
	var shell: Control = pp.find_child("PeopleDs2", false, false)
	var adv: Control = pp.find_child("TabKey_Advisors", true, false)
	var lab: Control = pp.find_child("TabKey_Labour", true, false)
	_check(shell != null and bool(adv.get("latched")) and not bool(lab.get("latched")) and (shell.call("body", 0) as Control).visible
		and not (shell.call("body", 1) as Control).visible, "people ds2 shell: Advisors open first, its key latched")
	lab.emit_signal("pressed")
	_check(bool(lab.get("latched")) and not bool(adv.get("latched")) and (shell.call("body", 1) as Control).visible,
		"people ds2 shell: the Labour key latches and shows Labour")
	var closed := [false]
	pp.connect("close_requested", func() -> void: closed[0] = true)
	(pp.find_child("CloseKey", true, false) as TextureButton).pressed.emit()
	_check(closed[0], "people ds2 shell: Close asks the panel to close")
	var Lamp = preload("res://scripts/ds2/lamp_overlay.gd")
	_check(Lamp.find(shell) != null and shell.find_child("PeopleShade", true, false) == null, "people ds2 shell: the lamp lights the panel part by part")
	var lit := true
	var text_light: Material = Lamp.text_material()
	for l in shell.find_children("*", "Label", true, false):
		lit = lit and (l as Label).material == text_light
	_check(lit, "people ds2 shell: every label takes back part of the lamp's shade")
	# The sheets (picker, dossier) lie under the same overlay, their print given back its light, their screens and
	# lamps undimmed.
	var tab: Control = shell.call("body", 0)
	tab.call("_set_view", {"mode": "detail", "sel_id": "vera", "back": "roster"})
	await get_tree().process_frame
	var sheet: Control = shell.find_child("DossierSheet", true, false)
	var sheet_lit := sheet != null and sheet.visible
	for l in sheet.find_children("*", "Label", true, false):
		sheet_lit = sheet_lit and (l as Label).material == text_light
	var screens_lit := true
	for seg in sheet.find_children("Segments", "", true, false):
		screens_lit = screens_lit and (seg as CanvasItem).material == null
	_check(sheet_lit and screens_lit and shell.is_ancestor_of(sheet),
		"people ds2 shell: the dossier sheet lies under the lamp, its print given back, its screens undimmed")
	tab.call("_set_view", {"mode": "roster"})
	shell.call("show_tab", 0)
	pp.queue_free()
	await get_tree().process_frame


## A CFO's loan interest cut is worth what it saves on the loans the company has now: nothing without loans; with
## a loan paying interest, the interest grossed up to the rate without the cut, less what is paid. Display only.
func _test_cfo_worth_on_todays_loans() -> void:
	var saved_loans: Array = LoanState.loans.duplicate(true)
	var saved_ids: Array = AdvisorState.permanent_advisor_ids.duplicate()
	var saved_seats: Dictionary = AdvisorState.advisor_seats.duplicate()
	var saved_money := MatchState.money
	LoanState.loans.clear()
	AdvisorState.permanent_advisor_ids = ["vera"]
	AdvisorState.advisor_seats.clear()
	AdvisorState.assign_advisor_to_seat("cfo", "vera")
	AdvisorState.reconcile_advisor_modifiers()
	var quiet := {"dividends_paid": 0.0}
	_check(is_zero_approx(AdvisorState.advisor_bonus_preview_per_turn("vera", "cfo", quiet)),
		"cfo worth: nothing without loans")
	LoanState.take_distress_loan(1000.0)
	var loan: Dictionary = LoanState.loans[-1]
	loan.grace_remaining = 0
	loan.principal_remaining = float(loan.total_repayment)
	loan.payment_per_turn = float(loan.total_repayment) / float(EconomyConfig.LOAN_TERM_TURNS)
	var rate := float(loan.interest_rate)
	var interest := float(loan.payment_per_turn) * rate / (1.0 + rate)
	var net := float(Modifiers.resolve_pct("loan_interest", "*", {}).get("net", 0.0))
	var cut := 0.0
	for eff in AdvisorState.advisor_seat_effect_list("vera", "cfo"):
		if str(eff.domain) == "loan_interest":
			cut = float(eff.pct)
	var want := interest * (1.0 + (net - cut) / 100.0) / (1.0 + net / 100.0) - interest
	var got := AdvisorState.advisor_bonus_preview_per_turn("vera", "cfo", quiet)
	_check(cut < 0.0 and want > 0.0 and absf(got - want) < 0.0001,
		"cfo worth: with a loan, the interest her cut saves today (£%.2f, want £%.2f)" % [got, want])
	LoanState.loans = saved_loans
	MatchState.money = saved_money
	AdvisorState.permanent_advisor_ids = saved_ids
	AdvisorState.advisor_seats = saved_seats
	AdvisorState.reconcile_advisor_modifiers()
