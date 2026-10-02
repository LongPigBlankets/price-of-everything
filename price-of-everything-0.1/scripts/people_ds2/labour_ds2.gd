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
## The choices go through LabourState as today's tab's do (it is this tab's base); the figures are the engine's
## (Production.labour_overview, labour_charge).

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
## The knobs: their size, the plate's columns, and the icons' scale on their plates.
const KNOB_PX := 104.0
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
	var top := HBoxContainer.new()
	top.name = "ClockAndDoors"
	top.add_theme_constant_override("separation", 16)
	_body.add_child(top)
	top.add_child(_clock())
	top.add_child(_workforce())
	var mid := HBoxContainer.new()
	mid.name = "PoliciesAndNotices"
	mid.add_theme_constant_override("separation", NOTICE_GAP)
	_body.add_child(mid)
	mid.add_child(_policies())
	mid.add_child(_notices())
	var foot := HBoxContainer.new()
	foot.name = "AutomationAndLockers"
	foot.add_theme_constant_override("separation", 12)
	_body.add_child(foot)
	foot.add_child(_automation())
	foot.add_child(_lockers())


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

## Each knob: its name, its options {id, name, words, icon} and the chosen one, and what picking one does.
func _knob_specs() -> Array:
	var v := LabourState.labour_multiplier
	var effort := 1 if absf(v - 1.0) < 0.001 else (0 if v < 1.0 else 2)
	var share := LabourState.idle_labour_pay_share
	var idle := 0 if share < 0.6 else (1 if share < 0.9 else 2)
	var safety_group := [LabourState.WORKFORCE_POLICY_LAX_SAFETY, LabourState.WORKFORCE_POLICY_STANDARD_SAFETY, LabourState.WORKFORCE_POLICY_STRICT_SAFETY]
	var pension_group := [LabourState.WORKFORCE_POLICY_PENSIONS_MINIMUM, LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS]
	var bonus_group := [LabourState.WORKFORCE_POLICY_SMALL_BONUS, LabourState.WORKFORCE_POLICY_ANNUAL_BONUS]
	var profit_group := [LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10]
	return [
		{"id": "effort", "name": "Work effort", "chosen": effort, "options": [
			["Lean", "Salary cost 20% lower. Output pressure falls 2%/turn, down to 30% lower.", func() -> void: LabourState.set_labour_multiplier(0.8)],
			["Standard", "Salary cost unchanged. Output pressure recovers 1%/turn toward none.", func() -> void: LabourState.set_labour_multiplier(1.0)],
			["Overtime", "Salary cost 20% higher. Output gains 1%/turn, up to 10% more.", func() -> void: LabourState.set_labour_multiplier(1.2)]]},
		{"id": "idle", "name": "Pay while idle", "chosen": idle, "options": [
			["50%", "A building that made nothing this turn pays half its wage bill. Cheapest, and hardest on the workforce.", func() -> void: LabourState.set_idle_labour_pay_share(0.5)],
			["75%", "Most of the wage bill is paid through an idle turn.", func() -> void: LabourState.set_idle_labour_pay_share(0.75)],
			["100%", "Workers are paid in full whether the line runs or not.", func() -> void: LabourState.set_idle_labour_pay_share(1.0)]]},
		{"id": "safety", "name": "Safety", "chosen": ["minimal", "standard", "high"].find(_safety_key()), "options": [
			["Minimal", "Output 5% higher. Labour cost rises 0.5%/turn to 15% more, and upkeep 5%/turn to double.", func() -> void: _pick_exclusive(safety_group, LabourState.WORKFORCE_POLICY_LAX_SAFETY)],
			["Standard", "Regulation compliance. No change to output or labour cost.", func() -> void: _pick_exclusive(safety_group, LabourState.WORKFORCE_POLICY_STANDARD_SAFETY)],
			["High", "Output 10% lower. Labour cost falls 0.5%/turn to 15% less.", func() -> void: _pick_exclusive(safety_group, LabourState.WORKFORCE_POLICY_STRICT_SAFETY)]]},
		{"id": "pension", "name": "Pensions", "chosen": ["minimum", "average", "generous"].find(_pensions_key()), "options": [
			["Minimum legal", "Labour cost falls 0.1%/turn to 5% less. Output drifts down 0.05%/turn to 5% less as people leave.", func() -> void: _pick_exclusive(pension_group, LabourState.WORKFORCE_POLICY_PENSIONS_MINIMUM)],
			["Industry average", "The baseline. No change either way.", func() -> void: _pick_exclusive(pension_group, "")],
			["Generous", "Output rises 0.05%/turn to 5% more. Labour cost rises 0.1%/turn, faster as the game ages.", func() -> void: _pick_exclusive(pension_group, LabourState.WORKFORCE_POLICY_GENEROUS_PENSIONS)]]},
		{"id": "bonus", "name": "Annual bonus", "chosen": ["none", "small", "generous"].find(_bonus_key()), "options": [
			["None", "Nothing paid, nothing gained.", func() -> void: _pick_exclusive(bonus_group, "")],
			["Small", "Labour cost 2.5% higher. Output 10% higher every tenth turn, the bonus month.", func() -> void: _pick_exclusive(bonus_group, LabourState.WORKFORCE_POLICY_SMALL_BONUS)],
			["Generous", "Labour cost 5% higher. Output 20% higher every tenth turn, the bonus month.", func() -> void: _pick_exclusive(bonus_group, LabourState.WORKFORCE_POLICY_ANNUAL_BONUS)]]},
		{"id": "profit", "name": "Profit share", "chosen": ["none", "five", "ten"].find(_profit_key()), "options": [
			["None", "Profits stay with the company.", func() -> void: _pick_exclusive(profit_group, "")],
			["5%", "5% of profit after tax and dividends goes to the workers. Output 10% higher.", func() -> void: _pick_exclusive(profit_group, LabourState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE)],
			["10%", "10% of profit after tax and dividends goes to the workers. Output 15% higher.", func() -> void: _pick_exclusive(profit_group, LabourState.WORKFORCE_POLICY_PROFIT_SHARE_10)]]},
	]


func _policies() -> Control:
	var col := VBoxContainer.new()
	col.name = "Policies"
	col.add_theme_constant_override("separation", 8)
	col.custom_minimum_size.x = PLATE_W
	col.add_child(Parts.heading("Policies"))
	var slab: Control = Section.new()
	slab.name = "KnobPlate"
	slab.set("style", "slab")
	slab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(slab)
	var grid := GridContainer.new()
	grid.columns = 2
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
		opts.append({"id": "%s_%d" % [id, i], "name": "%s: %s" % [str(spec.name), str(options[i][0])],
			"icon": Parts.tex("people_icon_%s_%d" % [id, i])})
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

const AUTOMATION_WORDS := "Labour cost falls 0.2%/turn to 15% less. Upkeep rises 2%/turn to 10% more."


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


func _other_policies() -> Array:
	return [
		{"id": LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, "name": "Extended Annual Leave", "lock": "",
			"words": "Output 5% lower every tenth turn. Labour cost falls 0.1%/turn to 5% less."},
		{"id": LabourState.WORKFORCE_POLICY_GENEROUS_PARENTAL_LEAVE, "name": "Generous Parental Leave", "lock": "",
			"words": "Output 5% lower for ten turns in every twenty. Labour cost falls 0.1%/turn to 5% less."},
		{"id": LabourState.WORKFORCE_POLICY_LONG_TENURE, "name": "Long Tenure Awards", "lock": "Needs an HR Director",
			"words": "Labour cost 10% higher every tenth turn, the payout. Otherwise it falls 0.1%/turn to 10% less."},
		{"id": LabourState.WORKFORCE_POLICY_STOCK_OPTIONS, "name": "Stock Options", "lock": "Opens with an HR mission",
			"words": "Dividends grow 0.05%/turn to 10% more. Output rises 0.1%/turn to 5% more."},
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


## The capture tool's views of this tab (tools/people_ds2_shot.gd): Labour at its extremes.
func shot_views() -> Array:
	return [
		{"name": "extremes", "setup": func() -> void:
			LabourState.set_labour_multiplier(0.8)
			LabourState.set_idle_labour_pay_share(0.5)
			_pick_exclusive([LabourState.WORKFORCE_POLICY_LAX_SAFETY, LabourState.WORKFORCE_POLICY_STANDARD_SAFETY, LabourState.WORKFORCE_POLICY_STRICT_SAFETY], LabourState.WORKFORCE_POLICY_STRICT_SAFETY)
			LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_PUSH_AUTOMATION, true)
			LabourState.set_workforce_policy_enabled(LabourState.WORKFORCE_POLICY_EXTENDED_ANNUAL_LEAVE, true)
			_rebuild()},
	]


# --- the parts ---------------------------------------------------------------------------------------

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
