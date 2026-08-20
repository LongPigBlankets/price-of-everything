extends Control
class_name AdvisorCouncilTab
## The People panel's Advisors tab, rebuilt around the ROLE-FIRST paradigm
## (docs: the "People Panel" Claude Design import): the roster is a grid of
## council SEATS. An empty seat's card starts the journey — pick the seat,
## then pick the advisor into it — instead of picking an advisor and hunting
## for a seat afterwards.
##
##   roster (seat grid) ──click empty seat──▶ picker ("Hiring for <seat>")
##        ▲    │click filled seat                    │click candidate
##        │    ▼                                     ▼
##        └── detail (seated: loyalty/agenda; candidate: Hire & assign)
##
## Read-only against the sim (rule #5): all mutations go through MatchState
## (hire_advisor / assign_advisor_to_seat / unassign_seat / fire_advisor).

const _DISC_NAMES := {"inf": "Influencing", "ops": "Operations", "lead": "Leadership", "inn": "Innovation", "fin": "Finance"}
# One colour per governing discipline; a seat is tinted by what it governs.
const _DISC_COLORS := {
	"fin": Color("#E6B34A"), "ops": Color("#C8702F"), "inf": Color("#5FA8E0"),
	"lead": Color("#D96AA0"), "inn": Color("#5FBF6B"),
}
const _ACCENT := Color("#D96AA0")          # the People pink
const _CARD_BG := Color("#122539")
const _CARD_BG2 := Color("#0C1A2A")
const _CARD_BORDER := Color("#1C3149")
const _GOOD := Color("#5FBF6B")
const _BAD := Color("#E2604A")
const _WARN := Color("#E6B34A")

# Friendly labels for the seat-effect modifier domains ("what they bring").
const _DOMAIN_LABELS := {
	"labour_headcount": "labour cost", "maintenance": "maintenance", "building_power": "building power",
	"grid_buy_price": "grid buy price", "grid_sell_price": "grid sell price",
	"transport_cost": "transport cost", "transport_throughput": "throughput",
	"loan_interest": "loan interest", "dividend_rate": "dividend pressure",
	"construction_rebate": "build rebate", "purchase_cost": "purchase cost",
	"tax_rate": "tax rate", "market_spread": "market spread", "market_price": "sale price",
}

# view = {mode: "roster"|"picker"|"detail", sel_id, hire_seat, back}
var _view: Dictionary = {"mode": "roster"}
var _root: VBoxContainer
var _refresh_queued := false

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 14)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_root)
	MatchState.advisors_changed.connect(_queue_refresh)
	MatchState.advisor_loyalty_changed.connect(func(_id: String, _v: float) -> void: _queue_refresh())
	visibility_changed.connect(_queue_refresh)   # catch up when the tab is shown
	# The tutorial advances from bonus inspection to hiring asynchronously. Rebuild the
	# candidate footer when that happens, so its confirmation button becomes available.
	if typeof(Tutorial) != TYPE_NIL and Tutorial.has_signal("step_changed"):
		Tutorial.step_changed.connect(func(_id: String) -> void: _queue_refresh())
	_rebuild()

# Coalesced (notification_bell pattern): loyalty/seat changes arrive in bursts.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")

func _apply_refresh() -> void:
	_refresh_queued = false
	if is_visible_in_tree():
		_rebuild()

func _set_view(v: Dictionary) -> void:
	_view = v
	_rebuild()

# ── loyalty helpers (sim range LOYALTY_MIN..MAX = −10..+10) ─────────────────
func _loyalty_tone(v: float) -> Dictionary:
	if v >= 3.4:
		return {"color": _GOOD, "label": "Loyal"}
	if v > -3.4:
		return {"color": _WARN, "label": "Wavering"}
	return {"color": _BAD, "label": "Disloyal"}

func _loyalty_frac(v: float) -> float:
	return clampf((v - MatchState.LOYALTY_MIN) / (MatchState.LOYALTY_MAX - MatchState.LOYALTY_MIN), 0.0, 1.0)

func _seat_color(seat_id: String) -> Color:
	var governs := str((MatchState.SEAT_DEFINITIONS.get(seat_id, {}) as Dictionary).get("governs", ""))
	return _DISC_COLORS.get(governs, Color("#B9C4D2"))

func _seat_name(seat_id: String) -> String:
	return str((MatchState.SEAT_DEFINITIONS.get(seat_id, {}) as Dictionary).get("seat_name", seat_id))

func _seated_ids() -> Array:
	return MatchState.advisor_seats.values()

## Candidates the picker offers: benched employees first (already on payroll),
## then recruited-but-unhired advisors.
func _picker_candidates() -> Array:
	var out: Array = []
	for a in MatchState.permanent_advisors():
		if not _seated_ids().has(str(a.get("id", ""))):
			out.append(a)
	out.append_array(MatchState.available_advisors())
	return out

# ── rebuild ─────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	match str(_view.get("mode", "roster")):
		"picker": _build_picker()
		"detail": _build_detail()
		_: _build_roster()

# ── ROSTER: the seat grid ───────────────────────────────────────────────────
func _build_roster() -> void:
	var seated := MatchState.advisor_seats.size()
	var cap := MatchState.max_advisor_slots
	var avg := 0.0
	for aid in _seated_ids():
		avg += MatchState.advisor_loyalty_value(str(aid))
	avg = avg / float(seated) if seated > 0 else 0.0
	var tone := _loyalty_tone(avg)

	# Council summary strip.
	var strip := _card_panel()
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 16)
	strip.add_child(srow)
	var mood_col := VBoxContainer.new()
	mood_col.add_theme_constant_override("separation", 2)
	srow.add_child(mood_col)
	mood_col.add_child(_sec_label("COUNCIL MOOD"))
	var mood_row := HBoxContainer.new()
	mood_row.add_theme_constant_override("separation", 8)
	mood_col.add_child(mood_row)
	mood_row.add_child(_big_number("%+.1f" % avg if seated > 0 else "—", tone.color, 26))
	mood_row.add_child(_dim_label(("%s · " % tone.label if seated > 0 else "") + "%d / %d seats filled" % [seated, cap], 13))
	var meter_holder := CenterContainer.new()
	meter_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(meter_holder)
	if seated > 0:
		var m := _meter(_loyalty_frac(avg), tone.color, 260.0, 9.0)
		meter_holder.add_child(m)
	var add_btn := Button.new()
	add_btn.name = "AdvisorAddNewButton"
	add_btn.text = "+ Add new advisor"
	add_btn.theme_type_variation = &"Primary"
	add_btn.pressed.connect(func() -> void: _set_view({"mode": "picker", "back": "roster"}))
	srow.add_child(add_btn)
	_root.add_child(strip)

	_root.add_child(_sec_label("COUNCIL SEATS"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(grid)
	var at_cap := seated >= cap
	for seat_id in MatchState.SEAT_DEFINITIONS:
		var sid := str(seat_id)
		var aid := MatchState.get_advisor_in_seat(sid)
		# Locked, empty seats are hidden until `unlock advisors` (a seated advisor still shows).
		if aid == "" and not MatchState.is_seat_available(sid):
			continue
		if aid != "":
			grid.add_child(_filled_seat_card(sid, aid))
		else:
			grid.add_child(_empty_seat_card(sid, at_cap))

func _filled_seat_card(seat_id: String, advisor_id: String) -> Control:
	var adv := MatchState.get_advisor(advisor_id)
	var loyalty := MatchState.advisor_loyalty_value(advisor_id)
	var tone := _loyalty_tone(loyalty)
	var scol := _seat_color(seat_id)

	var btn := _card_button()
	btn.pressed.connect(func() -> void: _set_view({"mode": "detail", "sel_id": advisor_id, "back": "roster"}))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	head.add_child(_portrait(adv, 52.0))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(_title_label(str(adv.get("name", advisor_id)), 19))
	head.add_child(_role_chip(seat_id, scol))

	var lrow := HBoxContainer.new()
	col.add_child(lrow)
	var ll := _dim_label("Loyalty", 11)
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(ll)
	lrow.add_child(_tone_label("%+.1f · %s" % [loyalty, tone.label], tone.color, 12))
	col.add_child(_meter(_loyalty_frac(loyalty), tone.color, 0.0, 8.0))

	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 10)
	col.add_child(frow)
	var effects: Array = MatchState.advisor_seat_effect_list(advisor_id, seat_id)
	frow.add_child(_dim_label(_effect_text(effects[0]) if not effects.is_empty() else "no seat effects", 11))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(spacer)
	frow.add_child(_tone_label("★".repeat(MatchState.advisor_star_by_id(advisor_id)), _WARN, 12))
	col.add_child(_financial_preview(advisor_id, seat_id, true))
	return btn

func _empty_seat_card(seat_id: String, locked: bool) -> Control:
	var scol := _seat_color(seat_id)
	var seat: Dictionary = MatchState.SEAT_DEFINITIONS.get(seat_id, {})
	var btn := _card_button(true, scol if not locked else Color("#3A4654"))
	btn.disabled = locked
	if locked:
		btn.tooltip_text = "Seat cap reached (%d). More seats unlock as your company grows." % MatchState.max_advisor_slots
	else:
		btn.pressed.connect(func() -> void: _set_view({"mode": "picker", "hire_seat": seat_id, "back": "roster"}))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)
	var glyph := _monogram(_seat_name(seat_id), scol, 42.0)
	var ctr := CenterContainer.new()
	ctr.add_child(glyph)
	col.add_child(ctr)
	var nm := _title_label(_seat_name(seat_id), 17)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nm)
	var levers: Array = seat.get("lever_kit", [])
	var blurb := _dim_label(", ".join(PackedStringArray(levers)).capitalize(), 11)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(blurb)
	var cta := _tone_label("Locked" if locked else "+ Assign advisor", Color("#5B6E84") if locked else _ACCENT, 12)
	cta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cta)
	return btn

# ── PICKER: candidates, optionally "hiring for <seat>" ──────────────────────
func _build_picker() -> void:
	var pool := _picker_candidates()
	_root.add_child(_back_row("Available advisors", "%d candidates for the council" % pool.size()))

	var hire_seat := str(_view.get("hire_seat", ""))
	if hire_seat != "":
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)
		row.add_child(_dim_label("Hiring for", 12))
		row.add_child(_role_chip(hire_seat, _seat_color(hire_seat)))
		var change := LinkButton.new()
		change.text = "change"
		change.add_theme_font_size_override("font_size", 12)
		change.pressed.connect(func() -> void:
			var v := _view.duplicate()
			v.erase("hire_seat")
			_set_view(v))
		row.add_child(change)
		_root.add_child(row)

	if pool.is_empty():
		var empty := _dim_label("No candidates right now — new advisors join as your company hits milestones.", 13)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_root.add_child(empty)
		return
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(grid)
	for adv in pool:
		grid.add_child(_candidate_card(adv))

func _candidate_card(adv: Dictionary) -> Control:
	var aid := str(adv.get("id", ""))
	var employed := MatchState.permanent_advisor_ids.has(aid)
	var btn := _card_button()
	btn.pressed.connect(func() -> void:
		_set_view({"mode": "detail", "sel_id": aid, "hire_seat": _view.get("hire_seat", ""), "back": "picker"}))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	head.add_child(_portrait(adv, 48.0))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(_title_label(str(adv.get("name", aid)), 19))
	var fee := VBoxContainer.new()
	fee.add_theme_constant_override("separation", 0)
	head.add_child(fee)
	var fee_text := ("unpaid" if not MatchState.advisor_is_payrolled(aid) else "on payroll") \
		if employed else "£%.1f/turn" % _salary(aid)
	var fee_v := _tone_label(fee_text, _WARN, 14)
	fee_v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fee.add_child(fee_v)
	var fee_c := _dim_label("family friend" if employed and not MatchState.advisor_is_payrolled(aid) else ("benched" if employed else "salary"), 10)
	fee_c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fee.add_child(fee_c)

	var pitch := _dim_label("“%s”" % str(adv.get("recommendation", adv.get("bonus", ""))), 12)
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(pitch)
	var hire_seat := str(_view.get("hire_seat", ""))
	if hire_seat != "":
		col.add_child(_financial_preview(aid, hire_seat, true))

	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	col.add_child(chips)
	for pair in _top_disciplines(aid, 2):
		chips.add_child(_stat_chip("%s %d/3" % [pair[0], pair[1]]))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chips.add_child(sp)
	chips.add_child(_tone_label("View ›", _ACCENT, 12))
	return btn

# ── DETAIL: one advisor, seated or candidate ────────────────────────────────
func _build_detail() -> void:
	var aid := str(_view.get("sel_id", ""))
	var adv := MatchState.get_advisor(aid)
	if adv.is_empty():
		_set_view({"mode": "roster"})
		return
	var seated_seat := ""
	for sid in MatchState.advisor_seats:
		if str(MatchState.advisor_seats[sid]) == aid:
			seated_seat = str(sid)
	var employed := MatchState.permanent_advisor_ids.has(aid)
	_root.add_child(_back_row("", ""))

	# Header.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	_root.add_child(head)
	head.add_child(_portrait(adv, 72.0))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(_title_label(str(adv.get("name", aid)), 26))
	names.add_child(_dim_label("★".repeat(MatchState.advisor_star_by_id(aid)), 13))
	if seated_seat != "":
		head.add_child(_role_chip(seated_seat, _seat_color(seated_seat)))
	else:
		var fee := VBoxContainer.new()
		head.add_child(fee)
		var fee_text := ("unpaid" if not MatchState.advisor_is_payrolled(aid) else "on payroll") \
			if employed else "£%.1f/turn" % _salary(aid)
		fee.add_child(_tone_label(fee_text, _WARN, 17))
		fee.add_child(_dim_label("family friend" if employed and not MatchState.advisor_is_payrolled(aid) else ("benched" if employed else "salary"), 11))

	# Loyalty strip (employed only).
	if employed:
		var loyalty := MatchState.advisor_loyalty_value(aid)
		var tone := _loyalty_tone(loyalty)
		var strip := _card_panel()
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 18)
		strip.add_child(lrow)
		var lcol := VBoxContainer.new()
		lcol.add_theme_constant_override("separation", 4)
		lrow.add_child(lcol)
		lcol.add_child(_sec_label("LOYALTY"))
		var lv := HBoxContainer.new()
		lv.add_theme_constant_override("separation", 8)
		lcol.add_child(lv)
		lv.add_child(_big_number("%+.1f" % loyalty, tone.color, 30))
		lv.add_child(_tone_label(tone.label, tone.color, 13))
		lcol.add_child(_meter(_loyalty_frac(loyalty), tone.color, 180.0, 9.0))
		var mcol := VBoxContainer.new()
		mcol.add_theme_constant_override("separation", 4)
		mcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lrow.add_child(mcol)
		mcol.add_child(_sec_label("MISSIONS"))
		var done := MatchState.advisor_missions_done(aid)
		mcol.add_child(_dim_label("%d / 5 complete" % done, 13))
		var rewards: Array = MatchState.advisor_mission_reward_labels(aid)
		if done < rewards.size():
			mcol.add_child(_dim_label("Next: %s" % str(rewards[done]), 11))
		_root.add_child(strip)

	# Choosing a position is a preview as well as an assignment. Keep the selector
	# above the bonus table, start with no implicit choice, and rebuild the preview
	# whenever the player picks a position.
	var choosing_position := seated_seat == "" or bool(_view.get("reassign", false))
	if choosing_position:
		_root.add_child(_seat_choice_row(aid, seated_seat))

	# Two-column body.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	_root.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	body.add_child(left)
	var bio := _dim_label(str(adv.get("bio", "")), 13)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(bio)
	left.add_child(_sec_label("SKILLSET"))
	for pair in _top_disciplines(aid, 5):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		left.add_child(row)
		var nm := _dim_label(str(pair[0]), 12)
		nm.custom_minimum_size = Vector2(90, 0)
		row.add_child(nm)
		var mtr := _meter(float(pair[1]) / 3.0, _DISC_COLORS.get(str(pair[2]), _WARN), 0.0, 7.0)
		mtr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(mtr)
		row.add_child(_tone_label("%d/3" % int(pair[1]), Color("#C7D4E3"), 12))
	# A seated advisor shows their current effects. Candidate/reassignment profiles
	# stay blank until the player explicitly chooses a position above.
	var focus_seat := seated_seat if not choosing_position else str(_view.get("selected_seat", ""))
	if focus_seat != "" and not MatchState.is_seat_available(focus_seat):
		focus_seat = ""
	var bonus_title := Label.new()
	bonus_title.add_theme_font_size_override("font_size", 20)
	bonus_title.add_theme_color_override("font_color", Color("#E9F1FA"))
	if focus_seat == "":
		bonus_title.text = "Choose a position to preview its bonuses"
		bonus_title.name = "AdvisorBonusPrompt"
	else:
		bonus_title.text = "Bonuses from this advisor's expertise — %s" % _seat_name(focus_seat)
		# A stable name lets the tutorial require an explicit position selection and
		# a visible seat-specific bonus preview before the player can hire.
		bonus_title.name = "AdvisorBonusSection"
	left.add_child(bonus_title)
	if focus_seat == "":
		left.add_child(_dim_label("Select one of the available positions above.", 12))
	else:
		left.add_child(_financial_preview(aid, focus_seat))
		left.add_child(_bonus_table(aid, focus_seat))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	body.add_child(right)
	right.add_child(_sec_label("AGENDA — SCORES LOYALTY EACH TURN"))
	var agenda_box := _card_panel()
	var acol := VBoxContainer.new()
	acol.add_theme_constant_override("separation", 7)
	agenda_box.add_child(acol)
	for r in MatchState.advisor_agenda_rows(aid):
		var rowd: Dictionary = r
		var benefit := bool(rowd.get("benefit", false))
		var arow := HBoxContainer.new()
		arow.add_theme_constant_override("separation", 8)
		acol.add_child(arow)
		arow.add_child(_tone_label("▲" if benefit else "▼", _GOOD if benefit else _BAD, 12))
		var txt := _dim_label(str(rowd.get("text", "")), 12)
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		arow.add_child(txt)
		var pts := float(rowd.get("points", 0.0))
		arow.add_child(_tone_label("%+.1f%s" % [pts, "/turn" if bool(rowd.get("per_turn", false)) else ""],
			_GOOD if benefit else _BAD, 11))
	right.add_child(agenda_box)

	# Footer actions.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	_root.add_child(foot)
	if seated_seat != "":
		var on_reassign := func() -> void:
			_set_view({"mode": "detail", "sel_id": aid, "reassign": true, "back": _view.get("back", "roster")})
		var on_unseat := func() -> void:
			MatchState.unassign_seat(seated_seat)
			_set_view({"mode": "roster"})
		var on_dismiss := func() -> void:
			MatchState.fire_advisor(aid)
			_set_view({"mode": "roster"})
		foot.add_child(_action_btn("Reassign seat", on_reassign))
		foot.add_child(_action_btn("Unseat (keep on payroll)", on_unseat))
		foot.add_child(_action_btn("Dismiss advisor", on_dismiss, _BAD))

## The bonuses table: one row per standing effect this advisor brings in this seat, sourced
## from the sim (advisor_seat_effect_list) so it can never drift from what is actually applied.
func _bonus_table(advisor_id: String, seat_id: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var rows := _advisor_bonus_rows(advisor_id, seat_id)
	if rows.is_empty():
		box.add_child(_dim_label("No mechanical effects in this seat.", 12))
		return box
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 3)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	grid.add_child(_dim_label("Bonus", 11))
	grid.add_child(_dim_label("Effect", 11))
	for r: Dictionary in rows:
		var name_label := _dim_label(str(r.get("name", "")), 12)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		grid.add_child(name_label)
		grid.add_child(_tone_label(str(r.get("effect", "")), _GOOD if bool(r.get("good", true)) else _BAD, 12))
	return box


## Side-by-side value test for a position, based on the last completed turn.
## It remains visible after hiring so the player can reassess whether the seat pays.
func _financial_preview(advisor_id: String, seat_id: String, compact: bool = false) -> Control:
	var box := VBoxContainer.new()
	box.name = "AdvisorFinancialPreview"
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bonus := MatchState.advisor_bonus_preview_per_turn(advisor_id, seat_id)
	var salary := _salary(advisor_id)
	var font_size := 11 if compact else 13
	var bonus_label := _tone_label("Preview bonuses: £%.2f per turn" % bonus, _GOOD, font_size)
	bonus_label.name = "AdvisorBonusValue"
	var salary_label := _tone_label("Salary: £%.2f per turn" % salary, _WARN, font_size)
	salary_label.name = "AdvisorSalaryValue"
	var explanation := "Snapshot from the last completed turn. It changes with revenue and costs."
	bonus_label.tooltip_text = explanation
	salary_label.tooltip_text = explanation
	box.add_child(bonus_label)
	box.add_child(salary_label)
	return box


## One row per standing effect, plus the founder's one-off gift where it applies.
func _advisor_bonus_rows(advisor_id: String, seat_id: String) -> Array:
	var rows: Array = []
	if seat_id != "":
		for eff in MatchState.advisor_seat_effect_list(advisor_id, seat_id):
			var pct := float(eff.get("pct", 0.0))
			var domain := str(eff.get("domain", ""))
			rows.append({
				"name": str(_DOMAIN_LABELS.get(domain, domain)).capitalize(),
				"effect": "%+.0f%%" % pct,
				"good": _effect_is_beneficial(eff),
			})
	if advisor_id == MatchState.FOUNDER_ADVISOR_ID:
		if seat_id == "cfo":
			rows.append({"name": "Signing gift — a one-off loan on favourable terms",
				"effect": "£200 at 5%", "good": true})
		elif seat_id == "coo":
			rows.append({"name": "Signing gift — pre-paid domestic freight, and cheaper haulage",
				"effect": "1000 units · −20%", "good": true})
		rows.append({"name": "Serves for nothing — no salary for his tenure",
			"effect": "£0 for %d turns" % MatchState.FOUNDER_TENURE_TURNS, "good": true})
	return rows


## The "Assign to <seat chips> · Hire & assign" row for candidates (and the
## reassign flow). Selection is explicit: profiles open with no position chosen,
## and each choice rebuilds the seat-specific bonus preview below this row.
func _seat_choice_row(advisor_id: String, current_seat: String) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	var open_seats: Array[String] = []
	for sid in MatchState.SEAT_DEFINITIONS:
		# Posts the company has not opened yet are not offered here either — the panel must
		# not be a way around the gate the rest of the game enforces.
		if not MatchState.is_seat_available(str(sid)):
			continue
		# The family friend sits where he was asked to sit. He is a favour in one of two
		# chairs, not a hire who can be moved around the org chart.
		if advisor_id == MatchState.FOUNDER_ADVISOR_ID \
				and not MatchState.STARTING_SEATS.has(str(sid)):
			continue
		var holder := MatchState.get_advisor_in_seat(str(sid))
		if holder == "" or holder == advisor_id:
			open_seats.append(str(sid))
	var seated := MatchState.advisor_seats.size()
	var can_take_new_seat := current_seat != "" or seated < MatchState.max_advisor_slots
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)
	# Nobody is hired before the family friend has made his offer — that decision is the
	# player's introduction to the council, and a hire beforehand pre-empts it.
	if TurnManager.current_turn < DecisionState.FOUNDER_DECISION_TURN:
		wrap.add_child(_tone_label(
			"You have no board yet. An old friend of your father's is expected by turn %d."
				% DecisionState.FOUNDER_DECISION_TURN, _BAD, 12))
		return wrap
	row.add_child(_dim_label("Assign to", 12))
	if not can_take_new_seat:
		row.add_child(_tone_label("Council is full (%d/%d) — unseat someone first." % [seated, MatchState.max_advisor_slots], _BAD, 12))
		return wrap
	var selected_seat := str(_view.get("selected_seat", ""))
	if not open_seats.has(selected_seat):
		selected_seat = ""
	var chip_holder := HFlowContainer.new()
	chip_holder.add_theme_constant_override("h_separation", 6)
	chip_holder.add_theme_constant_override("v_separation", 6)
	chip_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(chip_holder)
	var confirm := Button.new()
	for sid in open_seats:
		var b := Button.new()
		b.name = "AdvisorSeatChoice_%s" % sid
		b.toggle_mode = true
		b.text = _seat_name(sid)
		b.add_theme_font_size_override("font_size", 12)
		var selected := sid == selected_seat
		b.button_pressed = selected
		b.theme_type_variation = &"ChoiceSelected" if selected else &""
		b.pressed.connect(func() -> void:
			var next_view := _view.duplicate(true)
			next_view["selected_seat"] = sid
			_set_view(next_view))
		chip_holder.add_child(b)
	var employed := MatchState.permanent_advisor_ids.has(advisor_id)
	confirm.name = "AdvisorHireAssignButton"
	confirm.text = "Assign to seat" if employed else "Hire & assign"
	confirm.theme_type_variation = &"Primary"
	confirm.disabled = selected_seat == "" or _tutorial_bonus_inspection_required()
	if selected_seat == "":
		confirm.tooltip_text = "Choose a position first."
	elif _tutorial_bonus_inspection_required():
		confirm.tooltip_text = "Inspect What They Bring before hiring."
	confirm.pressed.connect(func() -> void:
		if not MatchState.permanent_advisor_ids.has(advisor_id):
			if not MatchState.hire_advisor(advisor_id):
				MatchState.request_toast("Could not hire — council is full or they refuse to return.", "warning")
				return
		var who := str(MatchState.get_advisor(advisor_id).get("name", advisor_id))
		if MatchState.assign_advisor_to_seat(selected_seat, advisor_id):
			MatchState.request_toast("%s assigned as %s" % [who, _seat_name(selected_seat)], "success")
		else:
			# A refused assignment used to fall through silently and return to the roster, so
			# the advisor appeared in whatever seat they were in before and it read as the game
			# choosing a different role. Say so instead.
			MatchState.request_toast("Could not seat %s as %s — the council is full." % [who, _seat_name(selected_seat)], "warning")
		_set_view({"mode": "roster"}))
	row.add_child(confirm)
	# Cost sits BELOW the button, not inside its label: it is two numbers plus a percentage and
	# it changes every turn, which made for a button caption that was mostly arithmetic.
	if not employed:
		var cost := _tone_label(_cost_breakdown(), _WARN, 12)
		cost.name = "AdvisorHireCostLine"
		wrap.add_child(cost)
	return wrap


func _tutorial_bonus_inspection_required() -> bool:
	return typeof(Tutorial) != TYPE_NIL and Tutorial.has_method("is_active_step") \
		and Tutorial.is_active_step("advisors_inspect")

# ── shared atoms ─────────────────────────────────────────────────────────────
func _back_row(title: String, subtitle: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var back := Button.new()
	back.text = "‹"
	back.custom_minimum_size = Vector2(34, 34)
	back.pressed.connect(func() -> void: _set_view({"mode": str(_view.get("back", "roster"))}))
	row.add_child(back)
	if title != "":
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 1)
		row.add_child(col)
		col.add_child(_title_label(title, 21))
		if subtitle != "":
			col.add_child(_dim_label(subtitle, 12))
	return row

func _card_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0E2034")
	sb.border_color = _CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return p

# Clickable card. A Button can't auto-size to a child container (its children
# don't contribute minimum size), so cards are PanelContainers — which DO size
# to content — with click + hover wired by hand.
func _card_button(dashed: bool = false, border: Color = _CARD_BORDER) -> _ClickCard:
	var card := _ClickCard.new()
	card.custom_minimum_size = Vector2(0, 150)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = _CARD_BG2 if dashed else _CARD_BG
	sb.border_color = border if not dashed else Color(border, 0.45)
	sb.set_border_width_all(1 if not dashed else 2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(14)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.border_color = _ACCENT if not dashed else border
	var dis := sb.duplicate() as StyleBoxFlat
	dis.bg_color = Color("#0B141F")
	card.setup(sb, hover, dis)
	return card

## Minimal clickable PanelContainer: emits `pressed` on left-click release,
## swaps to the hover stylebox under the mouse, greys out when disabled.
class _ClickCard extends PanelContainer:
	signal pressed
	var disabled := false:
		set(v):
			disabled = v
			_apply_style()
	var _normal: StyleBoxFlat
	var _hover: StyleBoxFlat
	var _disabled_sb: StyleBoxFlat
	var _hovered := false

	func setup(normal: StyleBoxFlat, hover: StyleBoxFlat, disabled_sb: StyleBoxFlat) -> void:
		_normal = normal
		_hover = hover
		_disabled_sb = disabled_sb
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			_hovered = true
			_apply_style())
		mouse_exited.connect(func() -> void:
			_hovered = false
			_apply_style())
		_apply_style()

	func _apply_style() -> void:
		if _normal == null:
			return
		var sb := _normal
		if disabled:
			sb = _disabled_sb
		elif _hovered:
			sb = _hover
		add_theme_stylebox_override("panel", sb)

	func _gui_input(event: InputEvent) -> void:
		if disabled:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			accept_event()
			pressed.emit()

func _portrait(adv: Dictionary, px: float) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(px, px)
	holder.clip_contents = true
	var sb := StyleBoxFlat.new()
	var accent: Color = adv.get("portrait_color", Color("#53687A"))
	sb.bg_color = accent.darkened(0.45)
	sb.border_color = Color(accent, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(px / 5.0))
	holder.add_theme_stylebox_override("panel", sb)
	var path := str(adv.get("portrait_path", ""))
	if path != "" and ResourceLoader.exists(path):
		var img := TextureRect.new()
		img.texture = load(path) as Texture2D
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		holder.add_child(img)
	else:
		var initials := _tone_label(str(adv.get("initials", "?")), Color("#E9F1FA"), int(px * 0.34))
		initials.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		initials.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		holder.add_child(initials)
	return holder

func _monogram(seat_name: String, color: Color, px: float) -> Control:
	var holder := PanelContainer.new()
	holder.custom_minimum_size = Vector2(px, px)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.08)
	sb.border_color = Color(color, 0.27)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	holder.add_theme_stylebox_override("panel", sb)
	var parts := seat_name.split(" ")
	var mono := parts[0].substr(0, 1) + (parts[1].substr(0, 1) if parts.size() > 1 else "")
	var lbl := _tone_label(mono.to_upper(), color, int(px * 0.4))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(lbl)
	return holder

func _role_chip(seat_id: String, color: Color) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.11)
	sb.border_color = Color(color, 0.27)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	chip.add_child(_tone_label(_seat_name(seat_id), color, 11))
	return chip

func _stat_chip(text: String) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0A1623")
	sb.border_color = _CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	chip.add_child(_tone_label("★ " + text, Color("#C7D4E3"), 11))
	return chip

func _effect_chip(text: String, color: Color) -> Control:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color, 0.10)
	sb.border_color = Color(color, 0.30)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	chip.add_child(_tone_label(text, color, 11))
	return chip

func _meter(frac: float, color: Color, width: float, height: float) -> Control:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(frac, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#0A1623")
	bg.border_color = _CARD_BORDER
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(int(height / 2.0))
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(int(height / 2.0))
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar

func _sec_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	return l

func _title_label(text: String, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"BuildingName"
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color("#EEF4FB"))
	return l

func _dim_label(text: String, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	return l

func _tone_label(text: String, color: Color, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	return l

func _big_number(text: String, color: Color, fs: int) -> Label:
	var l := _tone_label(text, color, fs)
	l.theme_type_variation = &"Numeric"
	return l

func _action_btn(text: String, handler: Callable, tint: Color = Color("#DBE6F2")) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_color_override("font_color", tint)
	b.pressed.connect(handler)
	return b

# ── data helpers ─────────────────────────────────────────────────────────────
func _archetype(advisor_id: String) -> String:
	var entry := MatchState._roster_entry(advisor_id)
	return str((entry.get("traits", {}) as Dictionary).get("specialty_name", ""))

## What one more advisor costs per turn under the live model — a flat base that inflates at
## double the labour rate, plus 1% of company revenue each (EconomyConfig, owner 2026-08-01).
## Not the roster's old per-advisor `salary` field, which the model replaced.
func _salary(advisor_id: String) -> float:
	return MatchState.advisor_cost_for(advisor_id, MatchState.advisor_revenue_basis())


## The cost broken out, for the line that sits UNDER the hire button.
func _cost_breakdown() -> String:
	var rev := MatchState.advisor_revenue_basis()
	var base := MatchState.advisor_cost_per_advisor(0.0)
	var share := rev * EconomyConfig.ADVISOR_REVENUE_SHARE
	return "\u00a3%.1f/turn \u2014 \u00a3%.1f base + %.0f%% of revenue (\u00a3%.1f)" % [base + share, base, EconomyConfig.ADVISOR_REVENUE_SHARE * 100.0, share]

## [ [display_name, value 1-3, disc_key], ... ] sorted by value desc, top n.
func _top_disciplines(advisor_id: String, n: int) -> Array:
	var entry := MatchState._roster_entry(advisor_id)
	var pairs: Array = []
	for key in _DISC_NAMES:
		pairs.append([str(_DISC_NAMES[key]), int(entry.get(key, 0)), str(key)])
	pairs.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[1]) != int(b[1]):
			return int(a[1]) > int(b[1])
		return str(a[0]) < str(b[0]))
	return pairs.slice(0, n)

func _effect_text(eff: Dictionary) -> String:
	var pct := float(eff.get("pct", 0.0))
	var label := str(_DOMAIN_LABELS.get(str(eff.get("domain", "")), str(eff.get("domain", ""))))
	return "%+.0f%% %s" % [pct, label]

## Whether an effect helps the player (sign alone isn't enough: −10% labour
## cost is good, −10% throughput would be bad).
func _effect_is_beneficial(eff: Dictionary) -> bool:
	return MatchState.advisor_effect_is_beneficial(eff)
