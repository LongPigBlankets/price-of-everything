extends "res://scripts/advisor_council_tab.gd"
## The People panel's Advisors tab in DS2 (docs/people-ds2-plan.md §5.1): the boardroom.
##
## The council's figures on a gunmetal plate (seats filled on a drum, the payroll on an LED, Add advisor), then
## the boardroom from above: an oxblood carpet, a walnut table with a brass inlay, five places a side in the
## council's seat order. Each place carries its role's brass nameplate. A filled place is green leather with the
## chair pulled out: the portrait under glass in a brass frame, the seat's lamp (green when it returns more than it
## costs, amber when not), the name, the stars in brass, every effect of the seat in words, and the bonus, salary
## and net on LEDs. An open place is bare leather and an Assign advisor key; a place on a full council has its
## folder closed; a seat not yet opened has a padlock through its folder. Each place's lamp and words come from
## scripts/people_ds2/seat_status.gd.
##
## The picker and an advisor's dossier are steel sheets that slide in over the table, not views that replace it.
## The view state, the candidates, the tutorial's checks and the hire itself are today's tab's
## (advisor_council_tab.gd), so both looks hire the same way; the node names the tutorial and tests look up
## (AdvisorAddNewButton, AdvisorSeatChoice_<seat>, AdvisorBonusPrompt, AdvisorBonusSection,
## AdvisorFinancialPreview, AdvisorBonusValue, AdvisorSalaryValue, AdvisorNetBenefitValue,
## AdvisorChooseCandidateButton, AdvisorHireAssignButton, AdvisorHireCostLine) are kept.

const Parts := preload("res://scripts/people_ds2/parts.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const SeatStatus := preload("res://scripts/people_ds2/seat_status.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const GuardKey := preload("res://scripts/ds2/guard_key.gd")

## The body keeps the scroll rail's room whether it shows or not, so nothing reflows when it does.
const RAIL_ROOM := 24
## The boardroom, in logical px (the study's layout px over 1.875): the carpet's edge beyond the table at each
## side, the room above and below the table for the chairs, the table's padding round its places, the gap
## between places, and between the two rows.
const BAY_SIDE := 9.0
const BAY_EDGE := 100.0
const TABLE_PAD := 7.0
const PLACE_GAP := 5.0
const ROW_GAP := 13.0
## Where a chair's seat sits against the table's edge: pulled out (a place in use) or pushed in under it.
const CHAIR_OUT := 33.0
const CHAIR_IN := -11.0
## The place's padding inside its leather, and the nameplate's height.
const PLACE_PAD := 5.0
const NAMEPLATE_H := 33.0
## The portrait (the frame's hole, 120 x 150 layout px) and the stars.
const PORTRAIT := Vector2(56, 70)
const STAR_PX := 8.0
## Layout numbers from layout.json (people_*).
const CARPET := {"margin": 16.0, "foot": 120.0}
const TABLE := {"margin": 16.0, "foot": 80.0}
const CHAIR := {"size": Vector2(270, 250), "up": Vector2(135, 150), "down": Vector2(135, 100)}
const BLOTTER := {"margin": 12.0, "corner": 40.0}
const NAMEPLATE := {"margin": 10.0, "cap": 34.0}
const FRAME := {"margin": 16.0, "rim": 8.0}
const FOLDER := {"margin": 18.0, "size": Vector2(208, 170)}
const STAR := {"size": 44.0, "star": 30.0}
## The dossier sheet (Building Detail's steel sheet) and how long it takes to slide in.
const SHEET_PAD := 18
## The dark sheet's render (layout.json people_sheet_dark): its shadow room and the foot drawn whole.
const SHEET_DARK := {"margin": 12.0, "foot": 160.0}
## The key bed round the dossier's seat keys (the tile view's), and the two columns' gap.
const KEYBED: Texture2D = preload("res://assets/ui/bdp_v3/tile_keybed.png")
const KEYBED_MARGIN := 14.0
const KEYBED_CORNER := 40.0
const COLUMN_GAP := 18
const SLIDE_SECONDS := 0.26
## How long an armed Dismiss key waits for its second press.
const DISARM_SECONDS := 4.0
## The Dismiss guard's cap.
const DISMISS_PX := 46.0

var _scroll: ScrollContainer
var _sheet: PanelContainer
var _sheet_head: HBoxContainer
var _sheet_root: VBoxContainer
var _sheet_scroll: ScrollContainer
var _sheet_shown := false
var _room: Control


func _ready() -> void:
	name = "AdvisorsDs2"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	_scroll = ScrollContainer.new()
	_scroll.name = "AdvisorsScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Scroll.apply(_scroll, true)
	add_child(_scroll)
	var col := MarginContainer.new()
	col.name = "AdvisorsBody"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("margin_right", RAIL_ROOM)
	col.add_theme_constant_override("margin_top", 4)
	col.add_theme_constant_override("margin_bottom", 12)
	_scroll.add_child(col)
	_root = VBoxContainer.new()
	_root.name = "Council"
	_root.add_theme_constant_override("separation", 10)
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_root)
	_sheet = _make_sheet()
	add_child(_sheet)
	AdvisorState.advisors_changed.connect(_queue_refresh)
	AdvisorState.advisor_loyalty_changed.connect(func(_id: String, _v: float) -> void: _queue_refresh())
	TurnManager.turn_resolution_completed.connect(_queue_refresh)
	visibility_changed.connect(_queue_refresh)
	if typeof(Tutorial) != TYPE_NIL and Tutorial.has_signal("step_changed"):
		Tutorial.step_changed.connect(func(_id: String) -> void: _queue_refresh())
	resized.connect(_fit_sheet)
	_rebuild()


## The roster always stands; the picker and the dossier are a sheet over it.
func _rebuild() -> void:
	for c in _root.get_children():
		_root.remove_child(c)
		c.queue_free()
	_build_roster()
	var mode := str(_view.get("mode", "roster"))
	if mode == "picker" or mode == "detail":
		for c in _sheet_root.get_children():
			_sheet_root.remove_child(c)
			c.queue_free()
		for c in _sheet_head.get_children():
			if c.name != "BackKey":
				_sheet_head.remove_child(c)
				c.queue_free()
		if mode == "picker":
			_build_picker()
		else:
			_build_detail()
		_show_sheet(true)
	else:
		_show_sheet(false)


# --- the roster: the council strip and the boardroom ---------------------------------------------

func _build_roster() -> void:
	_root.add_child(Parts.heading("Council"))
	_root.add_child(_council_strip())
	_room = Boardroom.new()
	_room.name = "Boardroom"
	_root.add_child(_room)
	var rows: Array = [[], []]
	var ids: Array = AdvisorState.SEAT_DEFINITIONS.keys()
	for i in ids.size():
		rows[0 if i < 5 else 1].append(str(ids[i]))
	for r in 2:
		var line := HBoxContainer.new()
		line.name = "Row%d" % r
		line.add_theme_constant_override("separation", int(PLACE_GAP))
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(_room as Boardroom).rows.add_child(line)
		for sid: String in rows[r]:
			line.add_child(_place(sid, r == 0))


## The council's figures on a gunmetal slab: the advisors seated of the most the company can seat now on a
## dot matrix ("2/3 ADVISORS"), the payroll on an LED, Add advisor.
func _council_strip() -> Control:
	var slab: Control = Section.new()
	slab.name = "CouncilStrip"
	slab.set("style", "slab")
	var content: VBoxContainer = slab.get("content")
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 28)
	content.add_child(line)
	var seats := VBoxContainer.new()
	seats.add_theme_constant_override("separation", 4)
	line.add_child(seats)
	seats.add_child(_row_title("Council"))
	var count: Control = DotMatrix.new()
	count.name = "CouncilCount"
	count.set("pitch", 2.0)
	count.set("text", SeatStatus.council_count())
	count.tooltip_text = "Advisors seated, of the most you can seat now."
	count.mouse_filter = Control.MOUSE_FILTER_PASS
	seats.add_child(count)
	var pay := VBoxContainer.new()
	pay.add_theme_constant_override("separation", 4)
	line.add_child(pay)
	pay.add_child(_row_title("Payroll"))
	var payroll := Parts.money(AdvisorState.advisor_payroll_per_turn(), Parts.RED, "/turn")
	payroll.name = "Payroll"
	pay.add_child(payroll)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(gap)
	var add: Button = CreamKey.make("AdvisorAddNewButton", "Add advisor", "", 170.0)
	add.pressed.connect(func() -> void: _set_view({"mode": "picker", "back": "roster"}))
	line.add_child(add)
	return slab


func _row_title(text: String) -> Label:
	var l := Parts.title(text)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = 0
	return l


## One place at the table.
func _place(seat_id: String, top_row: bool) -> Control:
	var st := SeatStatus.seat(seat_id)
	var place := Place.new()
	place.name = "Seat_%s" % seat_id
	place.state = str(st.state)
	place.top_row = top_row
	place.tooltip_text = str(st.words)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place.add_child(col)
	var plate := Nameplate.new()
	plate.text = _seat_name(seat_id)
	col.add_child(plate)
	match str(st.state):
		"filled":
			_filled_place(col, seat_id, st)
			var aid := str(st.advisor)
			Kit.on_click(place, func() -> void: _set_view({"mode": "detail", "sel_id": aid, "back": "roster"}))
		"open":
			col.add_child(Parts.spacer(0, 6))
			var assign: Button = CreamKey.make("AssignSeat_%s" % seat_id, "Assign advisor", "", 0.0, false, false, 0.7)
			assign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			assign.pressed.connect(func() -> void: _set_view({"mode": "picker", "hire_seat": seat_id, "back": "roster"}))
			col.add_child(assign)
			col.add_child(_levers(seat_id))
			Kit.on_click(place, func() -> void: _set_view({"mode": "picker", "hire_seat": seat_id, "back": "roster"}))
		_:
			var folder := Folder.new()
			folder.name = "Folder"
			folder.locked = str(st.state) == "locked"
			col.add_child(folder)
			if str(st.state) == "unopened":
				var req := _small(SeatStatus.requirement(seat_id))
				req.name = "Requirement"
				req.add_theme_font_override("font", Kit.FONT_TITLE)
				col.add_child(req)
			col.add_child(_levers(seat_id))
	return place


func _filled_place(col: VBoxContainer, seat_id: String, st: Dictionary) -> void:
	var aid := str(st.advisor)
	var adv := AdvisorState.get_advisor(aid)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	var portrait := Portrait.new()
	portrait.name = "AdvisorPortrait"
	portrait.set_advisor(adv)
	head.add_child(portrait)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 3)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(who)
	var lamp: Control = Lamp.new()
	lamp.name = "SeatLamp"
	lamp.set("lamp_scale", 0.62)
	lamp.call("set_tone", str(st.tone))
	lamp.set_meta("tone", str(st.tone))
	lamp.size_flags_horizontal = Control.SIZE_SHRINK_END
	who.add_child(lamp)
	for part in str(adv.get("name", aid)).split(" "):
		var n := Parts.title(part)
		n.custom_minimum_size.x = 0
		n.autowrap_mode = TextServer.AUTOWRAP_OFF
		n.clip_text = true
		who.add_child(n)
	var stars := Stars.new()
	stars.count = AdvisorState.advisor_star_by_id(aid)
	who.add_child(stars)
	var effects := VBoxContainer.new()
	effects.name = "SeatEffects"
	effects.add_theme_constant_override("separation", 1)
	effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(effects)
	var said := SeatStatus.effects(aid, seat_id)
	if said.is_empty():
		said.append("No effect in this seat")
	for words in said:
		var l := _small(words)
		effects.add_child(l)
	col.add_child(Parts.spacer(0, 2))
	var money := VBoxContainer.new()
	money.name = "AdvisorFinancialPreview"
	money.add_theme_constant_override("separation", 5)
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(money)
	money.add_child(_money_row("Bonus", float(st.bonus), Parts.GREEN, "AdvisorBonusValue"))
	money.add_child(_money_row("Salary", float(st.salary), Parts.RED, "AdvisorSalaryValue"))
	var net := float(st.net)
	money.add_child(_money_row("Net", net, Parts.GREEN if net >= 0.0 else Parts.RED, "AdvisorNetBenefitValue"))


## A caption and a compact money screen, the caption to the left, the screen to the right.
func _money_row(caption: String, value: float, colour: Color, node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := Parts.caption(caption, 12)
	c.uppercase = false
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(c)
	var m := Parts.money(value, colour, "", 13)
	var led: Control = m.get_node("Led")
	led.set("compact", true)
	led.call("set_figure", str(led.call("figure")), colour)
	row.add_child(m)
	row.set_meta("figure", Parts.money_text(value))
	return row


func _levers(seat_id: String) -> Label:
	var l := _small(SeatStatus.levers(seat_id))
	l.name = "Levers"
	return l


## Body text at the place's size (13 px: a place is a compact column, never under 12).
func _small(text: String) -> Label:
	var l := Parts.body(text)
	l.add_theme_font_size_override("font_size", 13)
	l.custom_minimum_size.x = 40
	return l


# --- the sheet over the table -----------------------------------------------------------------

func _make_sheet() -> PanelContainer:
	var sheet := PanelContainer.new()
	sheet.name = "DossierSheet"
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(SHEET_PAD)
	sheet.add_theme_stylebox_override("panel", pad)
	sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	# Dark gunmetal (people_sheet_dark), so the print on it is white on dark: cropped from the top, its foot whole.
	sheet.draw.connect(func() -> void:
		Parts.crop_v(sheet, Parts.tex("people_sheet_dark"), Rect2(Vector2.ZERO, sheet.size), SHEET_DARK.margin, SHEET_DARK.foot))
	sheet.visible = false
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	sheet.add_child(col)
	_sheet_head = HBoxContainer.new()
	_sheet_head.name = "SheetHead"
	_sheet_head.add_theme_constant_override("separation", 12)
	col.add_child(_sheet_head)
	var back: TextureButton = Key.make("back", 34.0)
	back.name = "BackKey"
	back.pressed.connect(func() -> void:
		var to := str(_view.get("back", "roster"))
		if to == "picker":
			_set_view({"mode": "picker", "hire_seat": _view.get("hire_seat", ""), "back": "roster"})
		else:
			_set_view({"mode": "roster"}))
	_sheet_head.add_child(back)
	_sheet_scroll = ScrollContainer.new()
	_sheet_scroll.name = "SheetScroll"
	_sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Scroll.apply(_sheet_scroll, true)
	col.add_child(_sheet_scroll)
	var body := MarginContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("margin_right", RAIL_ROOM)
	_sheet_scroll.add_child(body)
	_sheet_root = VBoxContainer.new()
	_sheet_root.name = "SheetBody"
	_sheet_root.add_theme_constant_override("separation", 12)
	_sheet_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_sheet_root)
	return sheet


func _fit_sheet() -> void:
	if _sheet == null:
		return
	_sheet.size = size
	if not _sheet_shown or _sheet.position.x == 0.0:
		_sheet.position = Vector2(0.0 if _sheet_shown else size.x, 0.0)


## The sheet slides in from the right over the table (0.26 s), or goes.
func _show_sheet(on: bool) -> void:
	if on == _sheet_shown:
		if on:
			_sheet_scroll.scroll_vertical = _sheet_scroll.scroll_vertical
		return
	_sheet_shown = on
	_sheet.size = size
	if not on:
		_sheet.visible = false
		return
	_sheet.visible = true
	_sheet_scroll.scroll_vertical = 0
	_sheet.position = Vector2(size.x, 0.0)
	var tw := create_tween()
	tw.tween_property(_sheet, "position:x", 0.0, SLIDE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func sheet_open() -> bool:
	return _sheet_shown


# --- the picker: candidates as files -----------------------------------------------------------

## The candidates two to a row on the dark sheet, each on a raised plastic module: portrait, name, stars, the
## pitch, the salary and (hiring for a seat) the net.
func _build_picker() -> void:
	var pool := _picker_candidates()
	_sheet_head.add_child(Parts.heading("Available advisors"))
	var hire_seat := str(_view.get("hire_seat", ""))
	if hire_seat != "":
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		_sheet_root.add_child(line)
		var for_l := Parts.body("Hiring for %s." % _seat_name(hire_seat))
		for_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		for_l.custom_minimum_size.x = 0
		for_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(for_l)
		var any: Button = CreamKey.make("AnySeat", "Any seat", "", 110.0, false, false, 0.7)
		any.pressed.connect(func() -> void:
			var v := _view.duplicate()
			v.erase("hire_seat")
			_set_view(v))
		line.add_child(any)
	if pool.is_empty():
		_sheet_root.add_child(Parts.body("No candidates yet. New advisors join as the company grows."))
		return
	var grid := GridContainer.new()
	grid.name = "Candidates"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_root.add_child(grid)
	for adv in pool:
		grid.add_child(_candidate(adv, hire_seat))


func _candidate(adv: Dictionary, hire_seat: String) -> Control:
	var aid := str(adv.get("id", ""))
	var m := Kit.module("Candidate_%s" % aid)
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.on_click(m, func() -> void:
		_set_view({"mode": "detail", "sel_id": aid, "hire_seat": _view.get("hire_seat", ""), "back": "picker"}))
	var row := Kit.row_of(m)
	var p := Portrait.new()
	p.set_advisor(adv)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(p)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 4)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(who)
	var name_l := Parts.title(str(adv.get("name", aid)))
	name_l.custom_minimum_size.x = 60
	who.add_child(name_l)
	var stars := Stars.new()
	stars.count = AdvisorState.advisor_star_by_id(aid)
	who.add_child(stars)
	var pitch := _small(_plain(str(adv.get("recommendation", adv.get("bonus", "")))))
	who.add_child(pitch)
	who.add_child(_money_row("Salary", _salary(aid), Parts.RED, "CandidateSalary"))
	if hire_seat != "":
		var net := AdvisorState.advisor_bonus_preview_per_turn(aid, hire_seat) - _salary(aid)
		who.add_child(_money_row("Net", net, Parts.GREEN if net >= 0.0 else Parts.RED, "CandidateNet"))
	if AdvisorState.permanent_advisor_ids.has(aid):
		who.add_child(_small("Unpaid" if not AdvisorState.advisor_is_payrolled(aid) else "On the payroll, benched"))
	return m


# --- the dossier: one advisor, seated or a candidate ---------------------------------------------

## The dossier on the dark sheet in two columns: on the left who they are (portrait, name, stars, standing, bio)
## and what they cost and bring in the seat on LEDs; on the right the seat's effects in words and their skills
## on lamps. Under both, the seat keys and Hire on a key bed while a seat is being chosen, and the seated
## advisor's keys (Reassign, Unseat, and Dismiss under its guard).
func _build_detail() -> void:
	var aid := str(_view.get("sel_id", ""))
	var adv := AdvisorState.get_advisor(aid)
	if adv.is_empty():
		_view = {"mode": "roster"}
		_show_sheet(false)
		return
	var seated_seat := ""
	for sid in AdvisorState.advisor_seats:
		if str(AdvisorState.advisor_seats[sid]) == aid:
			seated_seat = str(sid)
	var employed := AdvisorState.permanent_advisor_ids.has(aid)
	_sheet_head.add_child(Parts.heading("Dossier"))
	var choosing := seated_seat == "" or bool(_view.get("reassign", false))
	var focus_seat := seated_seat if not choosing else str(_view.get("selected_seat", ""))
	if focus_seat != "" and not AdvisorState.is_seat_available(focus_seat):
		focus_seat = ""

	var cols := HBoxContainer.new()
	cols.name = "DossierColumns"
	cols.add_theme_constant_override("separation", COLUMN_GAP)
	_sheet_root.add_child(cols)
	var left := VBoxContainer.new()
	left.name = "Who"
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.name = "Brings"
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	left.add_child(head)
	var p := Portrait.new()
	p.name = "AdvisorPortrait"
	p.portrait_size = Vector2(80, 100)
	p.set_advisor(adv)
	head.add_child(p)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 5)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(who)
	var nm := Parts.title(str(adv.get("name", aid)))
	nm.add_theme_font_size_override("font_size", 19)
	nm.custom_minimum_size.x = 60
	who.add_child(nm)
	var stars := Stars.new()
	stars.star_px = 14.0
	stars.count = AdvisorState.advisor_star_by_id(aid)
	who.add_child(stars)
	var standing := "Candidate."
	if seated_seat != "":
		standing = "Seated as %s." % _seat_name(seated_seat)
	elif employed:
		standing = "Serves unpaid." if not AdvisorState.advisor_is_payrolled(aid) else "On the payroll, benched."
	var st_l := Parts.body(standing)
	st_l.custom_minimum_size.x = 60
	who.add_child(st_l)
	var bio := Parts.body(_plain(str(adv.get("bio", ""))))
	bio.custom_minimum_size.x = 60
	left.add_child(bio)
	if employed and preload("res://scripts/debug_terminal.gd").demo_is_unlocked():
		var loyalty := AdvisorState.advisor_loyalty_value(aid)
		left.add_child(Parts.body("Loyalty %+.1f, %s. %d of 5 missions done." % [loyalty, str(_loyalty_tone(loyalty).label), AdvisorState.advisor_missions_done(aid)]))
	var bring := Parts.title("")
	bring.custom_minimum_size.x = 60
	if focus_seat == "":
		bring.text = "Choose a seat to see what they bring."
		bring.name = "AdvisorBonusPrompt"
		left.add_child(bring)
	else:
		bring.text = "What they bring as %s" % _seat_name(focus_seat)
		bring.name = "AdvisorBonusSection"
		left.add_child(bring)
		left.add_child(_dossier_money(aid, focus_seat))

	right.add_child(Parts.heading("Effects"))
	right.add_child(_dossier_effects(aid, focus_seat))
	right.add_child(Parts.heading("Skills"))
	var skills := GridContainer.new()
	skills.name = "Skills"
	skills.columns = 2
	skills.add_theme_constant_override("h_separation", 14)
	skills.add_theme_constant_override("v_separation", 6)
	right.add_child(skills)
	for pair in _top_disciplines(aid, 5):
		var l := Parts.body(str(pair[0]))
		l.custom_minimum_size.x = 110
		l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		skills.add_child(l)
		var lamps := HBoxContainer.new()
		lamps.name = "Skill_%s" % str(pair[2])
		lamps.add_theme_constant_override("separation", 3)
		for i in 3:
			var lamp: Control = Lamp.new()
			lamp.set("lamp_scale", 0.5)
			lamp.call("set_tone", "ok" if i < int(pair[1]) else "")
			lamps.add_child(lamp)
		lamps.set_meta("level", int(pair[1]))
		skills.add_child(lamps)

	if choosing:
		_sheet_root.add_child(_seat_keys(aid, seated_seat))
	if seated_seat != "":
		var foot := HBoxContainer.new()
		foot.name = "DossierKeys"
		foot.add_theme_constant_override("separation", 12)
		_sheet_root.add_child(foot)
		var reassign: Button = CreamKey.make("ReassignKey", "Reassign seat", "", 150.0, false, false, 0.8)
		reassign.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reassign.pressed.connect(func() -> void:
			_set_view({"mode": "detail", "sel_id": aid, "reassign": true, "back": _view.get("back", "roster")}))
		foot.add_child(reassign)
		var unseat: Button = CreamKey.make("UnseatKey", "Unseat", "", 110.0, false, false, 0.8)
		unseat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unseat.tooltip_text = "Keeps them on the payroll."
		unseat.pressed.connect(func() -> void:
			AdvisorState.unassign_seat(seated_seat)
			_set_view({"mode": "roster"}))
		foot.add_child(unseat)
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(gap)
		foot.add_child(_dismiss_key(aid))


## Dismiss under a guard: the red cap with a work boot under its clear cover (guard_dismiss). The first press
## lifts the cover, the second dismisses; a cover left alone drops after a few seconds. Its name printed beside.
func _dismiss_key(advisor_id: String) -> Control:
	var box := HBoxContainer.new()
	box.name = "Dismiss"
	box.add_theme_constant_override("separation", 10)
	var guard: Control = GuardKey.new(DISMISS_PX)
	guard.name = "DismissKey"
	guard.set("layer", "guard_dismiss")
	guard.set("glow", "lamp_glow_red")
	guard.tooltip_text = "Dismiss. Lift the cover, then press."
	guard.connect("pressed", func() -> void:
		AdvisorState.fire_advisor(advisor_id)
		_set_view({"mode": "roster"}))
	var room := Control.new()
	room.custom_minimum_size = Vector2(DISMISS_PX, DISMISS_PX + GuardKey.overhang(DISMISS_PX))
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_child(guard)
	guard.position = Vector2(0, GuardKey.overhang(DISMISS_PX))
	guard.size = Vector2(DISMISS_PX, DISMISS_PX)
	box.add_child(room)
	var l := Parts.caption("Dismiss", 18)
	l.size_flags_vertical = Control.SIZE_SHRINK_END
	l.custom_minimum_size.y = DISMISS_PX
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


## The seat keys (a cream key a seat, the chosen one latched), then the confirm key and what hiring costs.
## Today's rules: nobody is hired before the founder's decision, a full council takes no new seat, the
## founder sits only in the two starting seats, and seats the company has not opened are not offered.
func _seat_keys(advisor_id: String, current_seat: String) -> Control:
	var bed := PanelContainer.new()
	bed.name = "SeatChoiceBed"
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(14)
	bed.add_theme_stylebox_override("panel", pad)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Section.Nine.paint(bed, KEYBED, Rect2(Vector2.ZERO, bed.size).grow(KEYBED_MARGIN / Parts.LAYOUT), (KEYBED_MARGIN + KEYBED_CORNER) * Parts.TEXELS))
	var wrap := VBoxContainer.new()
	wrap.name = "SeatChoice"
	wrap.add_theme_constant_override("separation", 10)
	bed.add_child(wrap)
	if TurnManager.current_turn < DecisionState.FOUNDER_DECISION_TURN:
		wrap.add_child(Parts.body("You have no board yet. A retired shipping director is expected by turn %d." % DecisionState.FOUNDER_DECISION_TURN))
		return bed
	var seated := AdvisorState.advisor_seats.size()
	if not (current_seat != "" or seated < AdvisorState.max_advisor_slots):
		wrap.add_child(Parts.body("The council is full at %d of %d. Unseat someone first." % [seated, AdvisorState.max_advisor_slots]))
		return bed
	var open_seats: Array[String] = []
	for sid in AdvisorState.SEAT_DEFINITIONS:
		if not AdvisorState.is_seat_available(str(sid)):
			continue
		if advisor_id == AdvisorState.FOUNDER_ADVISOR_ID and not AdvisorState.STARTING_SEATS.has(str(sid)):
			continue
		var holder := AdvisorState.get_advisor_in_seat(str(sid))
		if holder == "" or holder == advisor_id:
			open_seats.append(str(sid))
	var selected := str(_view.get("selected_seat", ""))
	if not open_seats.has(selected):
		selected = ""
	wrap.add_child(Parts.heading("Seat"))
	var keys := HFlowContainer.new()
	keys.add_theme_constant_override("h_separation", 8)
	keys.add_theme_constant_override("v_separation", 8)
	wrap.add_child(keys)
	for sid in open_seats:
		var k := 0.72
		var key: Button = CreamKey.make("AdvisorSeatChoice_%s" % sid, _seat_name(sid), "", 0.0, false, false, k)
		key.custom_minimum_size.x = CreamKey.width_for(_seat_name(sid), "", false, false, k)
		key.set("chosen", sid == selected)
		key.toggle_mode = false
		key.pressed.connect(func() -> void:
			var next := _view.duplicate(true)
			next["selected_seat"] = sid
			_set_view(next))
		keys.add_child(key)
	var employed := AdvisorState.permanent_advisor_ids.has(advisor_id)
	var inspecting := _tutorial_bonus_inspection_required()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	wrap.add_child(line)
	var words := "Choose this advisor" if inspecting else ("Assign to seat" if employed else "Hire and assign")
	var confirm: Button = CreamKey.make("AdvisorChooseCandidateButton" if inspecting else "AdvisorHireAssignButton", words, "", 0.0)
	confirm.custom_minimum_size.x = CreamKey.width_for(words, "", false, false) + 20.0
	confirm.disabled = selected == ""
	confirm.set("spent", selected == "")
	if selected == "":
		confirm.tooltip_text = "Choose a seat first."
	var chosen := selected
	confirm.pressed.connect(func() -> void: _confirm_choice(advisor_id, chosen, inspecting))
	line.add_child(confirm)
	if not employed:
		var cost := Parts.body(_cost_words())
		cost.name = "AdvisorHireCostLine"
		cost.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(cost)
	return bed


## The bonus, salary and net for the seat on LEDs.
func _dossier_money(advisor_id: String, seat_id: String) -> Control:
	var money := VBoxContainer.new()
	money.name = "AdvisorFinancialPreview"
	money.add_theme_constant_override("separation", 6)
	money.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bonus := AdvisorState.advisor_bonus_preview_per_turn(advisor_id, seat_id)
	var salary := _salary(advisor_id)
	var net := bonus - salary
	money.add_child(_money_row("Bonus", bonus, Parts.GREEN, "AdvisorBonusValue"))
	money.add_child(_money_row("Salary", salary, Parts.RED, "AdvisorSalaryValue"))
	money.add_child(_money_row("Net", net, Parts.GREEN if net >= 0.0 else Parts.RED, "AdvisorNetBenefitValue"))
	money.custom_minimum_size.x = 170
	money.tooltip_text = "From today's figures. It moves with revenue, costs and loans."
	return money


## Every effect of the seat in words, and the founder's gifts; before a seat is chosen, the seat each effect needs.
func _dossier_effects(advisor_id: String, seat_id: String) -> Control:
	var words := VBoxContainer.new()
	words.name = "EffectWords"
	words.add_theme_constant_override("separation", 3)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if seat_id == "":
		words.add_child(Parts.body("Choose a seat below."))
		return words
	for w in SeatStatus.effects(advisor_id, seat_id):
		var l := Parts.body(w)
		l.custom_minimum_size.x = 60
		words.add_child(l)
	for r: Dictionary in _advisor_bonus_rows(advisor_id, seat_id):
		var name_text := str(r.get("name", ""))
		if name_text.begins_with("Signing gift") or name_text.begins_with("Serves"):
			var l := Parts.body(_plain(name_text) + ": " + _plain(str(r.get("effect", ""))))
			l.custom_minimum_size.x = 60
			words.add_child(l)
	if words.get_child_count() == 0:
		words.add_child(Parts.body("No effect in this seat."))
	return words


## What hiring costs, in words without dashes: "£10.4 a turn: £10.0 base and 1% of revenue (£0.4)".
func _cost_words() -> String:
	var rev := AdvisorState.advisor_revenue_basis()
	var base := AdvisorState.advisor_cost_per_advisor(0.0)
	var share := rev * EconomyConfig.ADVISOR_REVENUE_SHARE
	return "£%.1f/turn: £%.1f base and %.0f%% of revenue (£%.1f)" % [base + share, base, EconomyConfig.ADVISOR_REVENUE_SHARE * 100.0, share]


## Copy on the panel is plain: no dashes, semicolons or middle dots.
static func _plain(text: String) -> String:
	return text.replace(" — ", ". ").replace("—", ", ").replace(" – ", ", ").replace(";", ",").replace(" · ", ", ") \
		.replace("“", "").replace("”", "")


# --- the boardroom's parts --------------------------------------------------------------------------

## The carpet bay, the chairs and the walnut table under the places, all painted in this control's draw so they
## lie under its children. `rows` is the table's column of place rows.
class Boardroom extends MarginContainer:
	var rows: VBoxContainer
	var _table: MarginContainer

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		for side in ["margin_left", "margin_right"]:
			add_theme_constant_override(side, int(BAY_SIDE))
		for side in ["margin_top", "margin_bottom"]:
			add_theme_constant_override(side, int(BAY_EDGE))
		_table = MarginContainer.new()
		_table.name = "Table"
		_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			_table.add_theme_constant_override(side, int(TABLE_PAD))
		add_child(_table)
		rows = VBoxContainer.new()
		rows.name = "Places"
		rows.add_theme_constant_override("separation", int(ROW_GAP))
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_table.add_child(rows)
		rows.sort_children.connect(queue_redraw)
		_table.item_rect_changed.connect(queue_redraw)
		resized.connect(queue_redraw)

	func _draw() -> void:
		Parts.crop_v(self, Parts.tex("people_carpet"), Rect2(Vector2.ZERO, size), CARPET.margin, CARPET.foot)
		var table := _table.get_rect()
		for r in rows.get_child_count():
			var line := rows.get_child(r) as Control
			for p in line.get_children():
				var place := p as Control
				var cx := table.position.x + rows.position.x + line.position.x + place.position.x + place.size.x * 0.5
				var top := r == 0
				var out := str(place.get("state")) in ["filled", "open"]
				var edge := table.position.y if top else table.end.y
				var seat_y := edge + (-1.0 if top else 1.0) * (CHAIR_OUT if out else CHAIR_IN)
				var anchor: Vector2 = CHAIR.up if top else CHAIR.down
				var t := Parts.tex("people_chair_up" if top else "people_chair_down")
				var sz: Vector2 = CHAIR.size / Parts.LAYOUT
				draw_texture_rect(t, Rect2(Vector2(cx, seat_y) - anchor / Parts.LAYOUT, sz), false)
		Parts.crop_v(self, Parts.tex("people_table"), table, TABLE.margin, TABLE.foot)


## A place at the table: the green leather blotter when in use or open, bare table otherwise. `state` is its
## seat's (seat_status.gd).
class Place extends PanelContainer:
	var state := "locked"
	var top_row := true

	func _init() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var pad := StyleBoxEmpty.new()
		pad.set_content_margin_all(PLACE_PAD)
		pad.content_margin_bottom = PLACE_PAD + 2.0
		add_theme_stylebox_override("panel", pad)
		custom_minimum_size.x = 60
		resized.connect(queue_redraw)

	func _draw() -> void:
		if state == "filled" or state == "open":
			Parts.draw_nine(self, Parts.tex("people_blotter"), Rect2(Vector2.ZERO, size), BLOTTER.margin, BLOTTER.corner)


## The role's brass nameplate, engraved navy, one line or two.
class Nameplate extends Control:
	var text := ""

	func _init() -> void:
		custom_minimum_size = Vector2(40, NAMEPLATE_H)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	func _draw() -> void:
		Parts.draw_h3(self, Parts.tex("people_nameplate"), Rect2(Vector2.ZERO, size), NAMEPLATE.margin, NAMEPLATE.cap)
		var font: Font = Plate.FONT_BOLD
		var label := text.to_upper()
		var room := size.x - 20.0
		var fs := Plate._fit(font, label, 15, room)
		var lines: PackedStringArray = [label]
		if fs < 13 and label.contains(" "):
			var words := label.split(" ")
			var half := int(ceil(words.size() / 2.0))
			lines = [" ".join(words.slice(0, half)), " ".join(words.slice(half))]
			fs = mini(Plate._fit(font, lines[0], 13, room), Plate._fit(font, lines[1], 13, room))
		fs = maxi(12, fs)
		var lh := font.get_height(fs) * 0.92
		var y0 := size.y * 0.5 - lh * (lines.size() - 1) * 0.5 + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		for i in lines.size():
			var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var at := Vector2((size.x - w) * 0.5, y0 + i * lh)
			draw_string(font, at + Vector2(0.8, 0.8), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Parts.INK_LIGHT_SHADOW)
			draw_string(font, at, lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Parts.NAVY)


## The portrait under glass in its brass frame (people_frame, the portrait drawn in its hole), or the advisor's
## initials on their colour where there is no portrait.
class Portrait extends Control:
	var portrait_size := PORTRAIT
	var _tex: Texture2D
	var _initials := ""
	var _accent := Color("#53687A")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func set_advisor(adv: Dictionary) -> void:
		var path := str(adv.get("portrait_path", ""))
		_tex = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
		_initials = str(adv.get("initials", "?"))
		var accent: Variant = adv.get("portrait_color", adv.get("accent", "#53687A"))
		_accent = accent if accent is Color else Color(str(accent))
		var rim := FRAME.rim / Parts.LAYOUT
		custom_minimum_size = portrait_size + Vector2(rim, rim) * 2.0
		queue_redraw()

	func _draw() -> void:
		var rim := FRAME.rim / Parts.LAYOUT
		var hole := Rect2(Vector2(rim, rim), portrait_size)
		if _tex != null:
			var ts := _tex.get_size()
			var k := maxf(hole.size.x / ts.x, hole.size.y / ts.y)
			var src_size := hole.size / k
			draw_texture_rect_region(_tex, hole, Rect2((ts - src_size) * 0.5, src_size))
		else:
			draw_rect(hole, _accent.darkened(0.35))
			var font: Font = Parts.Kit.FONT_TITLE
			var fs := int(portrait_size.x * 0.34)
			var w := font.get_string_size(_initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(hole.get_center().x - w * 0.5, hole.get_center().y + fs * 0.35), _initials,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE["TEXT"])
		# The glass: a faint glare across the portrait.
		draw_rect(Rect2(hole.position, Vector2(hole.size.x, hole.size.y * 0.4)), Color(1, 1, 1, 0.05))
		var t := Parts.tex("people_frame")
		var scale := portrait_size.x / (120.0 / Parts.LAYOUT)
		var m := (FRAME.margin + 0.0) / Parts.LAYOUT * scale
		draw_texture_rect(t, Rect2(Vector2(-m, -m), t.get_size() / 2.0 * scale), false)


## Stars earned raised in brass, the rest of five engraved.
class Stars extends Control:
	var count := 0:
		set(v):
			count = v
			queue_redraw()
	var star_px := STAR_PX:
		set(v):
			star_px = v
			custom_minimum_size = Vector2(5.0 * (v + 2.0), v + 2.0)
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		custom_minimum_size = Vector2(5.0 * (STAR_PX + 2.0), STAR_PX + 2.0)

	func _draw() -> void:
		var k := star_px / STAR.star
		var box := STAR.size * k
		for i in 5:
			var at := Vector2(i * (star_px + 2.0) + star_px * 0.5, size.y * 0.5) - Vector2(box, box) * 0.5
			if i < count:
				draw_texture_rect(Parts.tex("people_star_shadow"), Rect2(at, Vector2(box, box)), false)
				draw_texture_rect(Parts.tex("people_star"), Rect2(at, Vector2(box, box)), false)
			else:
				draw_texture_rect(Parts.tex("people_star_empty"), Rect2(at, Vector2(box, box)), false)


## The closed leather folder of a seat nobody holds, a brass padlock through it while the seat is not open.
class Folder extends Control:
	var locked := false:
		set(v):
			locked = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(60, 84)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var t := Parts.tex("people_folder_locked" if locked else "people_folder")
		var part: Vector2 = FOLDER.size / Parts.LAYOUT
		var k := minf(1.0, minf((size.x - 8.0) / part.x, size.y / part.y))
		var drawn := part * k
		var at := Vector2((size.x - drawn.x) * 0.5, (size.y - drawn.y) * 0.5)
		Parts.draw_fixed(self, t, at, FOLDER.margin, k)
