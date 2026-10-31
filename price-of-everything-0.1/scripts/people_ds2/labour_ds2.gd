extends "res://scripts/labour_policy_tab.gd"
## The People panel's Labour tab in DS2 (docs/people-ds2-plan.md §5.2): the works.
##
## The labour cost first, on the time clock: the shift bell with its lamp (lit when labour is at its floor), the
## dial, the time card, the cost this turn and in ten turns on LEDs and the share of base on a drum. Beside it the
## workforce behind Building Detail's factory doors, the headcount of each kind engraved on its kick plate (the
## player's buildings' workforce, Production.labour_headcount). Then the policies: six white knobs on a gunmetal
## plate, each option a pictogram on its arc, and the union notice board, its cards explaining the knob option
## under the pointer and every policy in force. Then automation, a slide switch on a plastic case between hands
## and machines, and the other policies in the workers' lockers, a padlock through the hasp of one not yet open.
##
## Above it all, the workforce's satisfaction (docs/pacing-labour-mining-licensing-spec.md §4.8): a dial with
## its bands, the needle at today's value, a hollow marker at the target and a ghost needle ten turns on; the
## figures on a case beside it, the band's card, and the ledger of what moves it.
##
## The choices go through LabourState as its base tab's do (labour_policy_tab.gd); the figures are the engine's
## (Production.labour_overview, labour_charge, LabourState's satisfaction).

const Parts := preload("res://scripts/people_ds2/parts.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const Door := preload("res://scripts/bdp_v3_labour_door.gd")
const Toggle := preload("res://scripts/bdp_v3_toggle.gd")
const Rotary := preload("res://scripts/rotary_selector.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const PanelGauge := preload("res://scripts/panel_gauge.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const GuardKey := preload("res://scripts/ds2/guard_key.gd")

const RAIL_ROOM := 24
## The time clock (layout.json people_clock, layout px): the render's frame, the housing in it, the bell's lamp,
## and where the figures stand on the housing: the captions' left edge, the screens' left edge and each row.
const CLOCK_FRAME := Vector2(560, 564)
const CLOCK_HOUSING := Rect2(20, 84, 520, 460)
const CLOCK_LAMP := Vector2(120, 272)
const CLOCK_CAPTION_X := 60.0
const CLOCK_SCREEN_X := 300.0
const CLOCK_ROWS := [374.0, 446.0, 512.0]
## How far below the heading the clock's housing stands (its card rises beside the heading).
const CLOCK_DROP := 26.0
## The doors (Building Detail's, 200 x 300 layout px) drawn 1.25 times the study's size.
const DOOR_SIZE := Vector2(133, 200)
const DOOR_GAP := 10
## The satisfaction dial's side, and its bands as shares of the scale from its good end (the dial is mirrored:
## red starts it). Green is −5 and up, amber −70 to −5, red below −70.
const DIAL_PX := 150.0
const DIAL_GREEN_PCT := 52.5
const DIAL_AMBER_PCT := 32.5
const RENEGE_PX := 64.0
## The knobs: their size, the plate's columns, and the icons' scale on their plates.
const KNOB_PX := 96.0
const KNOB_COLUMNS := 4
const KNOB_OPTION_SCALE := 1.05
const PLATE_W := 468.0
const NOTICE_GAP := 12
## The notice board (people_cork) and its cards (people_card), in layout px.
const CORK := {"margin": 14.0, "corner": 44.0, "frame": 16.0}
const CARD := {"margin": 10.0, "corner": 76.0, "rule": 60.0}
const CARD_PAD := Vector2(10, 7)
const PINS := ["people_pin_red", "people_pin_yellow", "people_pin_blue"]
## The automation case and the lockers (people_locker, layout px: the render, the card's face in it, the switch).
const AUTO_W := 160.0
const LOCKER := {"size": Vector2(284, 476), "margin": 18.0, "card": Rect2(45, 133, 194, 126), "switch": Vector2(122, 334)}
const LOCKER_W := 128.0
const LOCKER_GAP := 6
## The slide switches drawn larger than the diagnostics' (their render is at 2 texels a pixel, so a little soft).
const AUTO_SWITCH_SCALE := 1.5
const LOCKER_SWITCH_SCALE := 1.25

var _scroll: ScrollContainer
var _body: VBoxContainer
var _board: VBoxContainer
var _hover_card: Control
var _knobs: Dictionary = {}


func _ready() -> void:
	name = "LabourDs2"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = ScrollContainer.new()
	_scroll.name = "LabourScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Scroll.apply(_scroll, true)
	add_child(_scroll)
	var col := MarginContainer.new()
	col.name = "LabourBody"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("margin_right", RAIL_ROOM)
	col.add_theme_constant_override("margin_top", 4)
	col.add_theme_constant_override("margin_bottom", 12)
	_scroll.add_child(col)
	_body = VBoxContainer.new()
	_body.name = "Works"
	_body.add_theme_constant_override("separation", 16)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	# The base tab's refresh target; kept so its queued rebuilds land here.
	_root = HBoxContainer.new()
	LabourState.workforce_policies_changed.connect(_queue_refresh)
	LabourState.labour_multiplier_changed.connect(func(_v: float) -> void: _queue_refresh())
	LabourState.satisfaction_changed.connect(_queue_refresh)
	AdvisorState.advisors_changed.connect(_queue_refresh)
	TurnManager.turn_resolution_completed.connect(_queue_refresh)
	visibility_changed.connect(_queue_refresh)
	_rebuild()


func _rebuild() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_knobs.clear()
	_hover_card = null
	_body.add_child(_satisfaction())
	var top := HBoxContainer.new()
	top.name = "ClockAndDoors"
	top.add_theme_constant_override("separation", 16)
	_body.add_child(top)
	top.add_child(_clock())
	top.add_child(_workforce())
	_body.add_child(_policies())
	_body.add_child(_notices())
	var foot := HBoxContainer.new()
	foot.name = "AutomationAndLockers"
	foot.add_theme_constant_override("separation", 12)
	_body.add_child(foot)
	foot.add_child(_automation())
	foot.add_child(_lockers())


# --- satisfaction --------------------------------------------------------------------------------

## The dial's needle position for a satisfaction value: −100 at 7 o'clock to +100 at 5 o'clock.
static func dial_value(satisfaction: float) -> float:
	return clampf((satisfaction + 100.0) / 200.0, 0.0, 1.0)


func _satisfaction() -> Control:
	var now := LabourState.satisfaction
	var target := LabourState.target_satisfaction()
	var ten := LabourState.projected_satisfaction(10)
	var col := VBoxContainer.new()
	col.name = "Satisfaction"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("Satisfaction"))
	var row := HBoxContainer.new()
	row.name = "SatisfactionRow"
	row.add_theme_constant_override("separation", 16)
	col.add_child(row)
	var holder := Control.new()
	holder.name = "DialHolder"
	holder.custom_minimum_size = Vector2(DIAL_PX, DIAL_PX)
	holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.tooltip_text = "Needle: now. Hollow marker: where it is heading. Pale needle: in 10 turns."
	row.add_child(holder)
	var gauge: Control = PanelGauge.new()
	gauge.name = "SatisfactionDial"
	gauge.set("gauge_size", DIAL_PX)
	gauge.set("reverse_zones", true)
	gauge.set("green_percent", DIAL_GREEN_PCT)
	gauge.set("amber_percent", DIAL_AMBER_PCT)
	gauge.set("animate_needle", false)
	gauge.set("value", dial_value(now))
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(gauge)
	gauge.size = Vector2(DIAL_PX, DIAL_PX)
	var marks := DialMarks.new()
	marks.name = "DialMarks"
	marks.target_v = dial_value(target)
	marks.ten_v = dial_value(ten)
	holder.add_child(marks)
	marks.size = Vector2(DIAL_PX, DIAL_PX)
	col.set_meta("figures", {"now": now, "target": target, "ten": ten, "band": LabourState.satisfaction_band()})
	# The figures, on a case: light print, as on every dark case.
	var case := Kit.plastic_case("SatisfactionFigures")
	case.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	case.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 8)
	for spec: Array in [["Now", now, "SatisfactionNow"], ["Target", target, "SatisfactionTarget"], ["In 10 turns", ten, "SatisfactionTen"]]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		var cap := Parts.title(str(spec[0]))
		cap.custom_minimum_size.x = 96
		cap.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.add_child(cap)
		var screen := _screen(float(spec[1]))
		screen.name = str(spec[2])
		line.add_child(screen)
		rows.add_child(line)
	var trend := Parts.title(LabourState.satisfaction_trend().capitalize())
	trend.name = "SatisfactionTrend"
	rows.add_child(trend)
	# The band's card, and Renege when it is offered.
	var right := VBoxContainer.new()
	right.name = "SatisfactionNotes"
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var band: Dictionary = LabourState.band_summary()
	var card: Control = Kit.info(str(band.title), str(band.tone), str(band.words))
	card.name = "BandCard"
	right.add_child(card)
	if LabourState.can_renege():
		right.add_child(_renege_key())
	col.add_child(_ledger())
	return col


## A satisfaction figure on an LED screen: green from zero up, amber below, red in strike territory.
func _screen(value: float) -> Control:
	var led: Control = Led.new()
	var colour := Parts.GREEN
	if value < LabourState.BAND_STRIKE_BELOW:
		colour = Parts.RED
	elif value < 0.0:
		colour = Color("#E6B34A")
	led.call("set_figure", "%4d" % roundi(value), colour)
	led.set_meta("value", roundi(value))
	return led


## The sources of labour satisfaction: each standing contribution and each timed shift with its signed value, two to a row.
func _ledger() -> Control:
	var case := Kit.plastic_case("SatisfactionLedger")
	case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 6)
	rows.add_child(Parts.title("Sources of Labour Satisfaction"))
	var lines: Array = []
	for part in LabourState.satisfaction_contributions():
		lines.append([str(part.label), float(part.value)])
	for shift in LabourState.target_shifts:
		var left := int(shift.turns_left)
		var label := str(shift.label) if left < 0 else "%s, %d turn%s" % [str(shift.label), left, "" if left == 1 else "s"]
		lines.append([label, float(shift.value)])
	var grid := GridContainer.new()
	grid.name = "LedgerGrid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 3)
	rows.add_child(grid)
	var n := 0
	for line_spec: Array in lines:
		var line := HBoxContainer.new()
		line.name = "LedgerLine_%d" % n
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var l := Parts.body(str(line_spec[0]))
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		var v := float(line_spec[1])
		var r := Parts.title(LabourState.contribution_text(v))
		r.add_theme_color_override("font_color", DS.PALETTE["OK"] if v > 0.0 else DS.PALETTE["DANGER"])
		r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.custom_minimum_size.x = 40
		line.add_child(r)
		line.set_meta("ledger", "%s|%s" % [str(line_spec[0]), LabourState.signed_text(v)])
		grid.add_child(line)
		n += 1
	if LabourState.union_halving_active:
		var halving := Parts.body("Labour cuts made since turn %d count at half." % LabourState.union_signed_turn)
		halving.name = "HalvingLine"
		halving.add_theme_color_override("font_color", DS.PALETTE["WARN"])
		rows.add_child(halving)
	return case


## Renege on Union Agreements under a guard: lift the cover, then press.
func _renege_key() -> Control:
	var box := HBoxContainer.new()
	box.name = "Renege"
	box.add_theme_constant_override("separation", 10)
	var guard: Control = GuardKey.new(RENEGE_PX)
	guard.name = "RenegeKey"
	guard.set("layer", "guard_dismiss")
	guard.set("glow", "lamp_glow_red")
	guard.tooltip_text = "Labour cuts count in full again. Satisfaction falls 50 at once. Lift the cover, then press."
	guard.connect("pressed", func() -> void:
		LabourState.renege_union_agreements()
		_queue_refresh())
	var room := Control.new()
	room.custom_minimum_size = Vector2(RENEGE_PX, RENEGE_PX + GuardKey.overhang(RENEGE_PX))
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.add_child(guard)
	guard.position = Vector2(0, GuardKey.overhang(RENEGE_PX))
	guard.size = Vector2(RENEGE_PX, RENEGE_PX)
	box.add_child(room)
	var words := VBoxContainer.new()
	words.size_flags_vertical = Control.SIZE_SHRINK_END
	words.add_child(Parts.title("Renege on Union Agreements"))
	var l := Parts.body("Labour cuts count in full again. Satisfaction falls 50 at once.")
	l.add_theme_font_size_override("font_size", 13)
	words.add_child(l)
	box.add_child(words)
	return box


# --- the time clock and the doors ---------------------------------------------------------------

func _clock() -> Control:
	var ov: Dictionary = Production.labour_overview()
	var box := Clock.new()
	box.name = "TimeClock"
	box.add_child(Parts.heading("Labour cost"))
	var k := 1.0 / Parts.LAYOUT
	var origin := Vector2(0, CLOCK_DROP) - CLOCK_HOUSING.position * k
	box.origin = origin
	box.custom_minimum_size = Vector2(CLOCK_HOUSING.size.x * k, CLOCK_DROP + CLOCK_HOUSING.size.y * k)
	var at_floor := bool(ov.get("at_floor", false))
	var lamp: Control = Lamp.new()
	lamp.name = "FloorLamp"
	lamp.set("lamp_scale", 0.62)
	lamp.call("set_tone", "warn" if at_floor else "")
	lamp.set_meta("lit", at_floor)
	box.add_child(lamp)
	lamp.position = origin + CLOCK_LAMP * k - lamp.custom_minimum_size * 0.5
	var floor_l := Parts.caption("At floor", 13, HORIZONTAL_ALIGNMENT_CENTER)
	floor_l.uppercase = false
	floor_l.custom_minimum_size = Vector2(70, 0)
	box.add_child(floor_l)
	floor_l.position = origin + (CLOCK_LAMP + Vector2(0, 26)) * k - Vector2(35, 0)
	floor_l.tooltip_text = "Lit when labour cost is at its floor, %d%% of base. Further cuts do not stack below it." % int(EconomyConfig.LABOUR_FACTOR_MIN * 100.0)
	floor_l.mouse_filter = Control.MOUSE_FILTER_PASS
	var current := float(ov.get("current", 0.0))
	var rows := [
		["Labour cost", Parts.money(current, Parts.RED, "/turn"), "LabourCostNow"],
		["Of base", _share(float(ov.get("factor_pct", 100.0))), "LabourShare"],
		["In 10 turns", Parts.money(float(ov.get("est_10_turns", current)), Parts.RED, "/turn"), "LabourCostTen"],
	]
	for i in rows.size():
		var y := origin.y + float(CLOCK_ROWS[i]) * k
		var cap := Parts.title(str(rows[i][0]))
		cap.autowrap_mode = TextServer.AUTOWRAP_OFF
		cap.custom_minimum_size = Vector2(0, 0)
		box.add_child(cap)
		cap.position = Vector2(origin.x + CLOCK_CAPTION_X * k, y - 10.0)
		var fig: Control = rows[i][1]
		fig.name = str(rows[i][2])
		box.add_child(fig)
		fig.position = Vector2(origin.x + CLOCK_SCREEN_X * k - 14.0, y - fig.get_combined_minimum_size().y * 0.5)
	box.set_meta("figures", {"current": current, "factor_pct": float(ov.get("factor_pct", 100.0)),
		"est_10_turns": float(ov.get("est_10_turns", current)), "at_floor": at_floor})
	return box


## The share of base on a three drum counter, the % printed after it.
func _share(pct: float) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drum: Control = Drum.new(Drum.led_height(), 3, roundi(pct))
	hb.add_child(drum)
	hb.add_child(Parts.caption("%", Kit.POUND_PX))
	return hb


func _workforce() -> Control:
	var col := VBoxContainer.new()
	col.name = "Workforce"
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Parts.heading("Workforce"))
	var doors := HBoxContainer.new()
	doors.add_theme_constant_override("separation", DOOR_GAP)
	col.add_child(doors)
	var hc: Dictionary = Production.labour_headcount()
	for spec: Array in [["Unskilled", "unskilled"], ["Skilled", "skilled"], ["High skilled", "high_skilled"]]:
		var one := VBoxContainer.new()
		one.add_theme_constant_override("separation", 4)
		doors.add_child(one)
		var door: Control = Door.new()
		door.name = "Door_%s" % str(spec[1])
		door.custom_minimum_size = DOOR_SIZE
		door.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		door.set("count", int(hc.get(str(spec[1]), 0)))
		door.tooltip_text = "%s workers in your running buildings." % str(spec[0])
		door.mouse_filter = Control.MOUSE_FILTER_PASS
		one.add_child(door)
		var l := Parts.title(str(spec[0]))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = DOOR_SIZE.x
		one.add_child(l)
	return col


# --- the knobs and the notice board -------------------------------------------------------------

## Hazardous sites, as the safety copy names them.
const HAZARD_WORDS := "mines, furnaces, power plants and chemical works"


## Each knob: its name, its options [name, words, pick, text] and the chosen one. `text` prints on the option's
## plate where the knob has no icon art (the union and the work week).
func _knob_specs() -> Array:
	var v := LabourState.labour_multiplier
	var effort := 1 if absf(v - 1.0) < 0.001 else (0 if v < 1.0 else 2)
	var share := LabourState.idle_labour_pay_share
	var idle := 0 if share < 0.6 else (1 if share < 0.9 else 2)
	var safety_group := [LabourState.WORKFORCE_POLICY_LAX_SAFETY, LabourState.WORKFORCE_POLICY_STANDARD_SAFETY, LabourState.WORKFORCE_POLICY_STRICT_SAFETY]
	var pension_group := [LabourState.WORKFORCE_POLICY_PENSIONS_MINIMUM, LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS]
	var bonus_group := [LabourState.WORKFORCE_POLICY_SMALL_BONUS, LabourState.WORKFORCE_POLICY_ANNUAL_BONUS]
	var profit_group := [LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10]
	var union := LabourState.union_tier() != LabourState.UNION_NONE
	var week_opts: Array = []
	for i in LabourState.WORK_WEEK_HOURS.size():
		var hours: int = LabourState.WORK_WEEK_HOURS[i]
		var level := i + 1
		var cost := "Labour cost %d%% higher." % (level * 10) if union else "Satisfaction target %s lower." % LabourState.points_text(LabourState.WORK_WEEK_SATISFACTION_PER_LEVEL * level)
		week_opts.append(["%d hours" % hours, "Throughput %s%% higher. %s" % [_pct_text(float(LabourState.WORK_WEEK_THROUGHPUT_PCT[hours])), cost],
			func() -> void: LabourState.set_work_week(hours), str(hours)])
	return [
		{"id": "effort", "name": "Work effort", "chosen": effort, "options": [
			["Lean", "Throughput 10%% lower. Salary 20%% lower. Satisfaction target %s lower." % LabourState.points_text(LabourState.EFFORT_SATISFACTION.lean), func() -> void: LabourState.set_labour_multiplier(0.8)],
			["Standard", "No change.", func() -> void: LabourState.set_labour_multiplier(1.0)],
			["Overtime", "Throughput 15%% higher. Salary 25%% higher. Satisfaction target %s lower." % LabourState.points_text(LabourState.EFFORT_SATISFACTION.overtime), func() -> void: LabourState.set_labour_multiplier(1.2)]]},
		{"id": "idle", "name": "Pay while idle", "chosen": idle, "options": [
			["50%", "A building that made nothing this turn pays half its wage bill. Satisfaction target %s lower." % LabourState.points_text(LabourState.IDLE_PAY_SATISFACTION.half), func() -> void: LabourState.set_idle_labour_pay_share(0.5)],
			["75%", "Most of the wage bill is paid through an idle turn. Satisfaction target %s lower." % LabourState.points_text(LabourState.IDLE_PAY_SATISFACTION.most), func() -> void: LabourState.set_idle_labour_pay_share(0.75)],
			["100%", "Workers are paid in full whether the line runs or not. Satisfaction target %s higher." % LabourState.points_text(LabourState.IDLE_PAY_SATISFACTION.full), func() -> void: LabourState.set_idle_labour_pay_share(1.0)]]},
		{"id": "safety", "name": "Safety", "chosen": ["minimal", "standard", "high"].find(_safety_key()), "options": [
			["Minimal", "Throughput 10%% higher at %s. Labour cost 5%% lower. Satisfaction target %s lower." % [HAZARD_WORDS, LabourState.points_text(LabourState.MINIMAL_SAFETY_SATISFACTION)], func() -> void: _pick_exclusive(safety_group, LabourState.WORKFORCE_POLICY_LAX_SAFETY)],
			["Standard", "Regulation compliance. No change.", func() -> void: _pick_exclusive(safety_group, LabourState.WORKFORCE_POLICY_STANDARD_SAFETY)],
			["High", "Labour cost 5%% higher at %s. Satisfaction target %s higher." % [HAZARD_WORDS, LabourState.points_text(LabourState.HIGH_SAFETY_SATISFACTION)], func() -> void: _pick_exclusive(safety_group, LabourState.WORKFORCE_POLICY_STRICT_SAFETY)]]},
		{"id": "pension", "name": "Pensions", "chosen": ["minimum", "average", "generous"].find(_pensions_key()), "options": [
			["Minimum legal", "Labour cost 5%% lower. Satisfaction target %s lower." % LabourState.points_text(LabourState.MINIMUM_PENSIONS_SATISFACTION), func() -> void: _pick_exclusive(pension_group, LabourState.WORKFORCE_POLICY_PENSIONS_MINIMUM)],
			["Industry average", "The baseline. No change either way.", func() -> void: _pick_exclusive(pension_group, "")],
			["Generous", "Labour cost rises 0.1% a turn, faster as the game ages. Satisfaction target 10 higher, 20 after 30 turns.", func() -> void: _pick_exclusive(pension_group, LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS)]]},
		{"id": "bonus", "name": "Annual bonus", "chosen": ["none", "small", "generous"].find(_bonus_key()), "options": [
			["None", "Nothing paid, nothing gained.", func() -> void: _pick_exclusive(bonus_group, "")],
			["Small", "Labour cost 2.5% higher. Satisfaction target 8 higher.", func() -> void: _pick_exclusive(bonus_group, LabourState.WORKFORCE_POLICY_SMALL_BONUS)],
			["Generous", "Labour cost 5% higher. Satisfaction target 15 higher.", func() -> void: _pick_exclusive(bonus_group, LabourState.WORKFORCE_POLICY_ANNUAL_BONUS)]]},
		{"id": "profit", "name": "Profit share", "chosen": ["none", "five", "ten"].find(_profit_key()), "options": [
			["None", "Profits stay with the company.", func() -> void: _pick_exclusive(profit_group, "")],
			_profit_option(LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, profit_group),
			_profit_option(LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10, profit_group)]},
		{"id": "union", "name": "Union", "chosen": LabourState.union_tier(), "options": [
			["None", "No agreement.", func() -> void: _pick_union(LabourState.UNION_NONE), "NONE"],
			["Partial", "Labour cost 10% higher, rising 1% each pay round to 25%. Satisfaction target 15 higher.", func() -> void: _pick_union(LabourState.UNION_PARTIAL), "PART"],
			["Comprehensive", "Labour cost 10% higher, rising each pay round. Satisfaction target 30 higher, and satisfaction rises twice as fast. Labour cuts made after signing count at half, for good.", func() -> void: _pick_union(LabourState.UNION_COMPREHENSIVE), "FULL"]]},
		{"id": "week", "name": "Work week", "chosen": LabourState.WORK_WEEK_HOURS.find(LabourState.work_week_hours), "options": week_opts},
	]


static func _pct_text(pct: float) -> String:
	return str(int(pct)) if is_equal_approx(pct, roundf(pct)) else "%.1f" % pct


## The union knob. Moving up signs at once; stepping down costs money and satisfaction, so it asks first.
func _pick_union(tier: int) -> void:
	var old := LabourState.union_tier()
	if tier >= old:
		LabourState.set_union_tier(tier)
		return
	var steps := old - tier
	var cost := LoanState.average_revenue() * LabourState.UNION_STEP_DOWN_REVENUE_SHARE * float(steps)
	var dialog := ConfirmationDialog.new()
	dialog.name = "UnionStepDown"
	dialog.title = "Step down the union agreement"
	dialog.dialog_text = "Stepping down costs £%.2f now (5%% of average revenue a tier) and lowers satisfaction by 15 a tier, easing over 30 turns. Labour cuts made since signing still count at half." % cost
	dialog.ok_button_text = "Step down"
	dialog.confirmed.connect(func() -> void:
		LabourState.set_union_tier(tier)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void:
		dialog.queue_free()
		_queue_refresh())
	add_child(dialog)
	dialog.popup_centered()


func _policies() -> Control:
	var col := VBoxContainer.new()
	col.name = "Policies"
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Parts.heading("Policies"))
	var slab: Control = Section.new()
	slab.name = "KnobPlate"
	slab.set("style", "slab")
	slab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(slab)
	var grid := GridContainer.new()
	grid.name = "KnobGrid"
	grid.columns = KNOB_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	(slab.get("content") as VBoxContainer).add_child(grid)
	for spec: Dictionary in _knob_specs():
		grid.add_child(_knob(spec))
	return col


func _knob(spec: Dictionary) -> Control:
	var id := str(spec.id)
	var knob: Control = Rotary.new()
	knob.name = "Knob_%s" % id
	knob.knob_size = KNOB_PX
	knob.set("option_plates", true)
	knob.set("option_scale", KNOB_OPTION_SCALE)
	knob.set("option_ink", Color("#feedc3"))
	knob.set("label", str(spec.name))
	knob.set("label_colour", DS.PALETTE["TEXT"])
	knob.set("label_gap", 14.0)
	var opts: Array = []
	var options: Array = spec.options
	for i in options.size():
		var text := str(options[i][3]) if (options[i] as Array).size() > 3 else ""
		opts.append({"id": "%s_%d" % [id, i], "name": "%s: %s" % [str(spec.name), str(options[i][0])],
			"icon": null if text != "" else Parts.tex("people_icon_%s_%d" % [id, i]), "text": text})
	knob.call("set_options", opts)
	knob.call("set_value_no_signal", maxi(0, int(spec.chosen)) + 1)
	knob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buttons: Array = knob.get("option_buttons")
	for i in buttons.size():
		var o: Array = options[i]
		(buttons[i] as Button).mouse_entered.connect(func() -> void: _show_hover(str(spec.name), str(o[0]), str(o[1])))
		(buttons[i] as Button).mouse_exited.connect(func() -> void: _show_hover("", "", ""))
	knob.connect("value_changed", func(v: int) -> void:
		var pick: Callable = options[v - 1][2]
		pick.call()
		_queue_refresh())
	_knobs[id] = knob
	return knob


## The union notice board: the knob option under the pointer pinned on top, then each policy in force.
func _notices() -> Control:
	var col := VBoxContainer.new()
	col.name = "Notices"
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Parts.heading("Notices"))
	var board := Board.new()
	board.name = "NoticeBoard"
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(board)
	_board = board.cards
	_hover_card = _card("", "", "", 0)
	_hover_card.name = "HoverCard"
	_hover_card.visible = false
	_board.add_child(_hover_card)
	var n := 0
	for spec: Dictionary in _knob_specs():
		var o: Array = spec.options[maxi(0, int(spec.chosen))]
		var card := _card(str(spec.name), str(o[0]), str(o[1]), n)
		card.name = "Notice_%s" % str(spec.id)
		_board.add_child(card)
		n += 1
	if LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION):
		_board.add_child(_card("Automation", "Pushed", AUTOMATION_WORDS, n))
		n += 1
	for d: Dictionary in _other_policies():
		if LabourState.is_workforce_policy_enabled(str(d.id)):
			_board.add_child(_card(str(d.name), "In force", str(d.words), n))
			n += 1
	return col


func _show_hover(title: String, option: String, words: String) -> void:
	if _hover_card == null or not is_instance_valid(_hover_card):
		return
	if title == "":
		_hover_card.visible = false
		return
	_fill_card(_hover_card, title, option, words)
	_hover_card.visible = true


## An index card pinned to the board: the policy and its option on the first line over the red rule, what it
## does under it, navy print; white and manila in turn.
func _card(title: String, option: String, words: String, n: int) -> Control:
	var card := NoticeCard.new()
	card.paper = "people_card_white" if n % 2 == 0 else "people_card_manila"
	card.pin = PINS[n % PINS.size()]
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = CARD_PAD.x
	pad.content_margin_right = CARD_PAD.x
	pad.content_margin_top = CARD_PAD.y + 3.0
	pad.content_margin_bottom = CARD_PAD.y + 2.0
	card.add_theme_stylebox_override("panel", pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var line := HBoxContainer.new()
	line.name = "Line"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(line)
	var t := Parts.ink(Parts.title(""))
	t.name = "Title"
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.custom_minimum_size.x = 0
	line.add_child(t)
	var o := Parts.ink(Parts.title(""))
	o.name = "Option"
	o.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	o.autowrap_mode = TextServer.AUTOWRAP_OFF
	o.custom_minimum_size.x = 0
	o.add_theme_font_override("font", Plate.FONT_BOLD)
	o.add_theme_font_size_override("font_size", 15)
	line.add_child(o)
	var w := Parts.ink(Parts.body(""))
	w.name = "Words"
	w.add_theme_font_size_override("font_size", 13)
	w.custom_minimum_size.x = 60
	col.add_child(w)
	_fill_card(card, title, option, words)
	return card


func _fill_card(card: Control, title: String, option: String, words: String) -> void:
	(card.find_child("Title", true, false) as Label).text = title
	(card.find_child("Option", true, false) as Label).text = option
	(card.find_child("Words", true, false) as Label).text = words
	card.set_meta("notice", "%s|%s" % [title, option])


# --- automation and the lockers ------------------------------------------------------------------

const AUTOMATION_WORDS := "On level 2 and 3 buildings: labour cost 15% lower, power and upkeep 10% higher. Satisfaction target 5 lower."


func _automation() -> Control:
	var col := VBoxContainer.new()
	col.name = "Automation"
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size.x = AUTO_W
	col.add_child(Parts.heading("Automation"))
	var case := Kit.plastic_case("AutomationCase")
	case.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	rows.add_theme_constant_override("separation", 14)
	var icons := HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", 18)
	rows.add_child(icons)
	var on := LabourState.is_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION)
	var hands := Kit.raised("people_auto_hands", 44.0)
	hands.modulate = Color.WHITE if not on else Color(0.62, 0.6, 0.56)
	icons.add_child(hands)
	var machines := Kit.raised("people_auto_machines", 44.0)
	machines.modulate = Color.WHITE if on else Color(0.62, 0.6, 0.56)
	icons.add_child(machines)
	var sw: Control = Toggle.new()
	sw.name = "AutomationSwitch"
	sw.call("set_right", on)
	sw.tooltip_text = AUTOMATION_WORDS
	sw.connect("toggled", func(right: bool) -> void:
		LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION, right))
	# Drawn larger than the diagnostics' switch, in a holder its size (a container would ignore the scale).
	var holder := Control.new()
	holder.custom_minimum_size = sw.custom_minimum_size * AUTO_SWITCH_SCALE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(sw)
	sw.size = sw.custom_minimum_size
	sw.scale = Vector2.ONE * AUTO_SWITCH_SCALE
	rows.add_child(holder)
	var l := Parts.title("Push automation")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(l)
	return col


## A profit share option: [face, words, pick]. Its satisfaction follows last turn's profit after tax.
func _profit_option(share_id: String, group: Array) -> Array:
	var rate := roundi(float(LabourState.PROFIT_SHARE_RATE[share_id]) * 100.0)
	var scale := LabourState.PROFIT_SHARE_LOWER_SCALE if share_id == LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE else 1.0
	var sat: Dictionary = LabourState.PROFIT_SHARE_SATISFACTION
	var words := "%d%% of profit after tax and dividends goes to the workers. Satisfaction target %s higher at a loss, %s below £%d profit a turn, %s above." % [
		rate, LabourState.points_text(float(sat.loss) * scale), LabourState.points_text(float(sat.small) * scale),
		int(LabourState.PROFIT_SHARE_SMALL_BELOW), LabourState.points_text(float(sat.large) * scale)]
	return ["%d%%" % rate, words, func() -> void: _pick_exclusive(group, share_id)]


func _other_policies() -> Array:
	var leave_words := "Throughput %d%% lower. Satisfaction target 8 higher." % roundi(absf(LabourState.LEAVE_THROUGHPUT_PCT))
	return [
		{"id": LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, "name": "Extended Annual Leave", "lock": "",
			"words": leave_words},
		{"id": LabourState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE, "name": "Generous Parental Leave", "lock": "",
			"words": leave_words},
		{"id": LabourState.WORKFORCE_POLICY_LONG_TENURE, "name": "Long Tenure Awards", "lock": "Needs an HR Director",
			"words": "Labour cost falls 0.1% a turn to 10% less, with a 10% payout every tenth turn. Satisfaction target 5 higher."},
		{"id": LabourState.WORKFORCE_POLICY_STOCK_OPTIONS, "name": "Stock Options", "lock": "Opens with an HR mission",
			"words": "Dividends grow 0.05% a turn to 10% more. Satisfaction target 10 higher."},
	]


func _lockers() -> Control:
	var col := VBoxContainer.new()
	col.name = "OtherPolicies"
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Parts.heading("Other policies"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LOCKER_GAP)
	col.add_child(row)
	for d: Dictionary in _other_policies():
		row.add_child(_locker(d))
	return col


func _locker(d: Dictionary) -> Control:
	var pid := str(d.id)
	var available: bool = LabourState.is_workforce_policy_available(pid)
	var locker := Locker.new()
	locker.name = "Locker_%s" % pid
	locker.locked = not available
	locker.scale_k = LOCKER_W / (LOCKER.size.x - 2.0 * LOCKER.margin)
	locker.custom_minimum_size = Vector2(LOCKER_W, (LOCKER.size.y - 2.0 * LOCKER.margin) * locker.scale_k)
	locker.tooltip_text = str(d.words)
	var card: Rect2 = LOCKER.card
	var face := Rect2((card.position - Vector2(LOCKER.margin, LOCKER.margin)) * locker.scale_k, card.size * locker.scale_k)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 1)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.position = face.position + Vector2(4, 3)
	words.size = face.size - Vector2(8, 6)
	locker.add_child(words)
	var n := Parts.ink(Parts.title(str(d.name)))
	n.name = "Name"
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_font_size_override("font_size", 12)
	n.add_theme_constant_override("line_spacing", -2)
	n.custom_minimum_size.x = face.size.x - 8.0
	words.add_child(n)
	if not available:
		var why := Parts.ink(Parts.body(str(d.lock)), Parts.INK.warn)
		why.name = "Lock"
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.add_theme_font_size_override("font_size", 12)
		why.add_theme_constant_override("line_spacing", -2)
		why.custom_minimum_size.x = face.size.x - 8.0
		words.add_child(why)
	var sw: Control = Toggle.new()
	sw.name = "Switch"
	sw.call("set_right", LabourState.is_workforce_policy_enabled(pid))
	locker.add_child(sw)
	var at: Vector2 = (LOCKER.switch - Vector2(LOCKER.margin, LOCKER.margin)) * locker.scale_k
	sw.size = sw.custom_minimum_size
	sw.scale = Vector2.ONE * LOCKER_SWITCH_SCALE
	sw.position = at - sw.custom_minimum_size * LOCKER_SWITCH_SCALE * 0.5
	if available:
		sw.connect("toggled", func(right: bool) -> void: LabourState.set_workforce_policy_enabled(pid, right))
	else:
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sw.modulate = Color(0.7, 0.7, 0.7)
		locker.tooltip_text = "%s. %s" % [str(d.lock), str(d.words)]
	return locker


## The capture tool's views of this tab (tools/people_ds2_shot.gd): Labour at its extremes, and the
## satisfaction plate in three bands (content, steady, strike territory).
func shot_views() -> Array:
	return [
		{"name": "satisfaction_content", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_COMPREHENSIVE)
			_pick_exclusive([LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10], LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10)
			LabourState.satisfaction = 62.0
			_rebuild()},
		{"name": "satisfaction_steady", "setup": func() -> void:
			LabourState.satisfaction = 12.0
			_rebuild()},
		{"name": "satisfaction_strikes", "setup": func() -> void:
			LabourState.set_labour_multiplier(1.2)
			_pick_exclusive([LabourState.WORKFORCE_POLICY_LAX_SAFETY, LabourState.WORKFORCE_POLICY_STANDARD_SAFETY, LabourState.WORKFORCE_POLICY_STRICT_SAFETY], LabourState.WORKFORCE_POLICY_LAX_SAFETY)
			LabourState.satisfaction = -76.0
			LabourState.add_target_shift("shot_demolish", "Building demolished", -15.0)
			_rebuild()},
		{"name": "extremes", "setup": func() -> void:
			LabourState.set_labour_multiplier(0.8)
			LabourState.set_idle_labour_pay_share(0.5)
			_pick_exclusive([LabourState.WORKFORCE_POLICY_LAX_SAFETY, LabourState.WORKFORCE_POLICY_STANDARD_SAFETY, LabourState.WORKFORCE_POLICY_STRICT_SAFETY], LabourState.WORKFORCE_POLICY_STRICT_SAFETY)
			LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION, true)
			LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, true)
			_rebuild()},
	]


# --- the parts ---------------------------------------------------------------------------------------

## Over the satisfaction dial: a hollow marker on the scale at the target, and a pale needle where satisfaction
## will be in ten turns. Angles as the gauge's needle (PanelGauge.needle_rotation, clockwise from 12 o'clock).
class DialMarks extends Control:
	var target_v := 0.5
	var ten_v := 0.5

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var side := minf(size.x, size.y)
		var c := size * 0.5
		var r := side * PanelGauge.SCALE_RADIUS / PanelGauge.LAYER_SIZE
		var ten_a := PanelGauge.needle_rotation(ten_v)
		var ten_dir := Vector2(sin(ten_a), -cos(ten_a))
		draw_line(c, c + ten_dir * r * 0.82, Color(1, 1, 1, 0.45), 2.0, true)
		var a := PanelGauge.needle_rotation(target_v)
		var dir := Vector2(sin(a), -cos(a))
		var tip := c + dir * (r + 3.0)
		var side_v := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([tip, tip + dir * 9.0 + side_v * 5.0, tip + dir * 9.0 - side_v * 5.0, tip])
		draw_polyline(tri, Color("#0b2340"), 2.5, true)
		draw_polyline(tri, Color("#f2c84b"), 1.5, true)


## The time clock's render drawn under the figures on it; `origin` is where the render's frame starts.
class Clock extends Control:
	var origin := Vector2.ZERO

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		var t := Parts.tex("people_clock")
		draw_texture_rect(t, Rect2(origin, t.get_size() / 2.0), false)


## Cork in a timber frame, the cards pinned in a column inside it.
class Board extends MarginContainer:
	var cards: VBoxContainer

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var m := int((CORK.frame + 10.0) / Parts.LAYOUT)
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(side, m + 2)
		add_theme_constant_override("margin_top", m + 8)
		cards = VBoxContainer.new()
		cards.name = "Cards"
		cards.add_theme_constant_override("separation", 12)
		cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cards)
		resized.connect(queue_redraw)

	func _draw() -> void:
		Parts.draw_nine(self, Parts.tex("people_cork"), Rect2(Vector2.ZERO, size), CORK.margin, CORK.corner)


## An index card (people_card_white or _manila, a 9-slice; its red rule kept under the first line) with its pin.
class NoticeCard extends PanelContainer:
	var paper := "people_card_white"
	var pin := "people_pin_red"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		resized.connect(queue_redraw)

	func _draw() -> void:
		Parts.draw_nine(self, Parts.tex(paper), Rect2(Vector2.ZERO, size), CARD.margin, CARD.corner)
		var p := Parts.tex(pin)
		var s := p.get_size() / 2.0
		draw_texture_rect(p, Rect2(Vector2(size.x * 0.5 - s.x * 0.5, -s.y * 0.35), s), false)


## A worker's locker, `locked` with a padlock through its hasp; the card and switch are its children.
class Locker extends Control:
	var locked := false
	var scale_k := 1.0 / 1.875

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var t := Parts.tex("people_locker_locked" if locked else "people_locker")
		var m := LOCKER.margin * scale_k
		draw_texture_rect(t, Rect2(Vector2(-m, -m), LOCKER.size * scale_k), false)
