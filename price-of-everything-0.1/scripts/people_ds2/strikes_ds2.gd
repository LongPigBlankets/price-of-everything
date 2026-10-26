extends Control
## The People panel's Strikes tab in DS2 (docs/pacing-labour-mining-licensing-spec.md §6.3), built from the DS2
## kit's cases and modules (scripts/ds2/parts.gd). Every part's raised heading stands inside its case.
## - Strike risk: a module with the labour icon, the workforce's pilot lamp, its mood and what it means, and
##   the turns to the next check on a drum (or to the end of a pay rise's protection). Under it the strike
##   scale: satisfaction on Building Detail's mini screen, the two strike zones lit and a needle at today's
##   value, then the zones' key and the key that opens the encyclopedia's Mechanics page on strikes.
## - Two latching keys on a key bed, Upcoming Strikes and Ongoing Strikes, each counting its buildings in
##   brackets: those named for a strike that starts within 5 turns, and those on strike.
## - The chosen one's table, as the Building Ledger is laid out: metal labels over its columns (Location,
##   Output loss, Cost to manage, Action), then "All strikes (N buildings)" with the round's totals and its
##   Settle and Break strike keys, then a row that folds the buildings away ("N buildings", folded at first),
##   and under it a row a building: its emblem and the good it makes side by side, its name, its tile under it, its
##   own figures and keys. Settle and Break strike are two lines, each its cost on a screen in Cost to manage
##   beside its key under Action. A key opens a key bed under its row that says what it does, with Confirm and Cancel.
## - The record: a row a past strike, its turn, the buildings, the outcome's lamp and what it lost.
##
## The figures and the actions are LabourState.unrest's (scripts/labour_unrest.gd).

const Parts := preload("res://scripts/people_ds2/parts.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const Tip := preload("res://scripts/ds2/tip.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
const Encyclopedia := preload("res://scripts/encyclopedia_ds2/catalogue.gd")
const LabourUnrest := preload("res://scripts/labour_unrest.gd")

const RAIL_ROOM := 24
const KEY_SCALE := 0.72
## The Mechanics page "How strikes work" opens (search_overlay.gd MECHANIC_ENTRIES).
const MECHANICS_ENTRY := "strikes"
## The key beds: the Advisors tab's seat choice bed (tile_keybed, layout px).
const KEYBED: Texture2D = preload("res://assets/ui/bdp_v3/tile_keybed.png")
const KEYBED_MARGIN := 14.0
const KEYBED_CORNER := 40.0
const NEXT_CHECK := "Turns to check"
const TURNS_FREE := "Turns free"
## The sub-tabs.
const UPCOMING := "upcoming"
const ONGOING := "ongoing"
## The table: its column labels, the gap between columns, a row's padding, the icons and a building's good.
const LOCATION := "Location"
const LOSS := "Output loss"
const COST := "Cost to manage"
const ACTION := "Action"
const SETTLE := "Settle"
const BREAK := "Break strike"
const COL_GAP := 6
const ROW_PAD_Y := 5.0
## A row's icons: All strikes' labour icon, and a building's emblem and its good's well, all one size.
const ICON_PX := 48
## Buildings under the fold row stand in this far.
const MEMBER_INDENT := 8
const RECORD_SHOWN := 8

var _scroll: ScrollContainer
var _body: VBoxContainer
var _refresh_queued := false
## The sub-tab the player chose, or "" to follow the round (Ongoing while strikes are on). Any change to the
## strikes hands it back to the round.
var _subtab := ""
## Whether the buildings are unfolded under All strikes.
var _members_open := false
## The action whose bed is open, as "settle:<target>" or "break:<target>" (target "all" or a building's
## instance id), or "".
var _confirming := ""


func _ready() -> void:
	name = "StrikesDs2"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll = ScrollContainer.new()
	_scroll.name = "StrikesScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Scroll.apply(_scroll, true)
	add_child(_scroll)
	var col := MarginContainer.new()
	col.name = "StrikesBody"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("margin_right", RAIL_ROOM)
	col.add_theme_constant_override("margin_top", 4)
	col.add_theme_constant_override("margin_bottom", 12)
	_scroll.add_child(col)
	_body = VBoxContainer.new()
	_body.name = "Strikes"
	_body.add_theme_constant_override("separation", 14)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	LabourState.unrest_changed.connect(func() -> void:
		_subtab = ""
		_queue_refresh())
	LabourState.satisfaction_changed.connect(_queue_refresh)
	LabourState.workforce_policies_changed.connect(_queue_refresh)
	TurnManager.turn_resolution_completed.connect(_queue_refresh)
	visibility_changed.connect(_queue_refresh)
	_rebuild()


func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_refresh")


func _apply_refresh() -> void:
	_refresh_queued = false
	if is_visible_in_tree():
		_rebuild()


func _rebuild() -> void:
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var u := LabourState.unrest
	var turn := int(TurnManager.current_turn)
	var up := u.upcoming(turn)
	var on := u.ongoing()
	var shown := shown_subtab(_subtab, up.size(), on.size())
	var listed := up if shown == UPCOMING else on
	var target := _confirming.get_slice(":", 1)
	if not (target == "all" and not listed.is_empty()) and not listed.has(target):
		_confirming = ""
	elif target != "all":
		_members_open = true
	_body.add_child(_risk())
	_body.add_child(_subtabs(up.size(), on.size(), shown))
	_body.add_child(_board(shown, listed))
	if not u.record.is_empty():
		_body.add_child(_record())


## The sub-tab on show: the player's choice, else Ongoing while strikes are on, else Upcoming.
static func shown_subtab(chosen: String, upcoming_n: int, ongoing_n: int) -> String:
	if chosen != "":
		return chosen
	return ONGOING if ongoing_n > 0 else UPCOMING


## Opens the bed under an action's key ("settle:all", "break:<iid>"), or shuts it when it is already open.
func _toggle_confirm(action: String) -> void:
	_confirming = "" if _confirming == action else action
	_rebuild()


## A section's raised heading as the first row inside its case.
static func _cased(case_name: String, heading: String) -> Dictionary:
	var case := Kit.plastic_case(case_name)
	var rows: VBoxContainer = case.get_child(0)
	if heading != "":
		rows.add_child(Parts.heading(heading))
	return {"case": case, "rows": rows}


# --- strike risk ---------------------------------------------------------------------------------

## What the workforce's mood means for strikes: {tone, title, words, turns, caption}. `turns` is -1 when no
## check is coming (a union agreement stands).
static func outlook(turn: int) -> Dictionary:
	var u := LabourState.unrest
	var s := LabourState.satisfaction
	var o := {"title": "%s at %s" % [str(LabourState.band_summary().title), _n(s)],
		"turns": LabourUnrest.next_check_turn(turn) - turn, "caption": NEXT_CHECK}
	if LabourState.union_tier() != LabourState.UNION_NONE:
		o.merge({"tone": "ok", "words": "Union agreement in force. No strikes.", "turns": -1}, true)
	elif turn < u.strike_free_until:
		o.merge({"tone": "ok", "words": "Settled. No strikes for now.", "turns": u.strike_free_until - turn,
			"caption": TURNS_FREE}, true)
	elif s < LabourUnrest.HEAVY_STRIKE_BELOW:
		o.merge({"tone": "bad", "words": "Half your buildings can strike."}, true)
	elif s < LabourUnrest.STRIKE_BELOW:
		o.merge({"tone": "warn", "words": "A quarter of your buildings can strike."}, true)
	else:
		o.merge({"tone": "ok", "words": "No strikes at %s or above." % _n(LabourUnrest.STRIKE_BELOW)}, true)
	return o


func _risk() -> Control:
	var c := _cased("StrikeStatus", "Strike risk")
	var rows: VBoxContainer = c.rows
	rows.add_theme_constant_override("separation", 12)
	var o := outlook(int(TurnManager.current_turn))
	var module := Kit.module("Outlook")
	var row := Kit.row_of(module)
	row.add_child(Kit.raised("econ_icon_labour", Kit.EMBLEM_PX))
	var info := Kit.info(str(o.title), str(o.tone), str(o.words))
	info.name = "Mood"
	row.add_child(info)
	if int(o.turns) >= 0:
		row.add_child(_turns_col(int(o.turns), str(o.caption)))
	Tip.attach(module, {"name": str(o.title), "detail": str(o.words), "tone": str(o.tone)})
	rows.add_child(module)
	var scale := StrikeScale.new(LabourState.satisfaction)
	Tip.attach(scale, {"name": "Strike scale", "detail": "Satisfaction now %s. Below %s a quarter of your buildings can strike, below %s half." % [
		_n(LabourState.satisfaction), _n(LabourUnrest.STRIKE_BELOW), _n(LabourUnrest.HEAVY_STRIKE_BELOW)]})
	rows.add_child(scale)
	var foot := HBoxContainer.new()
	foot.name = "ScaleKey"
	foot.add_theme_constant_override("separation", 8)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(foot)
	foot.add_child(Swatch.new(StrikeScale.HEAVY))
	foot.add_child(Kit.caption("Half can strike"))
	foot.add_child(Kit.spacer(10, 0))
	foot.add_child(Swatch.new(StrikeScale.LIGHT))
	foot.add_child(Kit.caption("A quarter can strike"))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.add_child(gap)
	if not Encyclopedia.mechanics_locked():
		var how: Button = CreamKey.make("HowStrikesWork", "How strikes work", "", 0.0, false, false, KEY_SCALE)
		how.custom_minimum_size.x = CreamKey.width_for("How strikes work", "", false, false, KEY_SCALE)
		how.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		how.tooltip_text = "Opens the encyclopedia's page on strikes and accidents."
		how.pressed.connect(func() -> void: MatchState.encyclopedia_entry_requested.emit(MECHANICS_ENTRY))
		foot.add_child(how)
	c.case.set_meta("outlook", o)
	return c.case


## Turns on a drum, its label under it.
static func _turns_col(turns: int, caption: String) -> VBoxContainer:
	var width := maxf(Drum.width_for(str(maxi(0, turns)).length(), Drum.led_height()), Kit.caption_width(caption) + 4.0)
	var col := VBoxContainer.new()
	col.name = "Turns"
	col.add_theme_constant_override("separation", 2)
	col.custom_minimum_size = Vector2(width, 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drum := Kit.drum(maxi(0, turns), str(maxi(0, turns)).length())
	drum.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(drum)
	col.add_child(Kit.caption_under(caption, width))
	return col


# --- the sub-tabs --------------------------------------------------------------------------------

## The sub-tab names, each with its count in brackets.
static func subtab_text(id: String, n: int) -> String:
	return "%s Strikes (%d)" % ["Upcoming" if id == UPCOMING else "Ongoing", n]


func _subtabs(upcoming_n: int, ongoing_n: int, shown: String) -> Control:
	var bed := PanelContainer.new()
	bed.name = "StrikeSubtabs"
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 10
	pad.content_margin_right = 10
	pad.content_margin_top = 9
	pad.content_margin_bottom = 10
	bed.add_theme_stylebox_override("panel", pad)
	bed.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Section.Nine.paint(bed, KEYBED, Rect2(Vector2.ZERO, bed.size).grow(KEYBED_MARGIN / Parts.LAYOUT), (KEYBED_MARGIN + KEYBED_CORNER) * Parts.TEXELS))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	bed.add_child(line)
	for spec: Array in [[UPCOMING, upcoming_n,
			"Buildings named for a strike that starts within %d turns." % LabourUnrest.UPCOMING_WITHIN],
			[ONGOING, ongoing_n, "Buildings on strike now."]]:
		var id := str(spec[0])
		var text := subtab_text(id, int(spec[1]))
		var k: Control = LatchKey.new()
		k.name = "StrikeTab_%s" % id
		k.set("text", text)
		k.set("latched", id == shown)
		k.custom_minimum_size.x = ceilf(Plate.FONT_SEMI.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, LatchKey.LABEL_PX).x
			+ 2.0 * LatchKey.FACE_INSET / LatchKey.CAPTURE_SCALE + 24.0)
		k.tooltip_text = str(spec[2])
		k.connect("pressed", func() -> void:
			_subtab = id
			_confirming = ""
			_rebuild())
		line.add_child(k)
	return bed


# --- the table -----------------------------------------------------------------------------------

## The chosen sub-tab's table, or a line saying it is empty.
func _board(shown: String, iids: Array) -> Control:
	var u := LabourState.unrest
	var turn := int(TurnManager.current_turn)
	var striking := shown == ONGOING
	var heading := ""
	if not iids.is_empty():
		heading = "On strike" if striking else "Strike warning: turn %d" % int(u.warning.get("turn", turn))
	var c := _cased("OnStrike" if striking else "WarningBoard", heading)
	c.case.set_meta("subtab", shown)
	var rows: VBoxContainer = c.rows
	rows.add_theme_constant_override("separation", 6)
	if iids.is_empty():
		var none := Kit.body("No buildings on strike." if striking
			else "No strikes due in the next %d turns." % LabourUnrest.UPCOMING_WITHIN)
		none.name = "NoStrikes"
		rows.add_child(none)
		return c.case
	var losses := {}
	var settles := {}
	var breaks := {}
	var totals := {"loss": 0.0, "settle": 0.0, "break": 0.0}
	var left := 0
	for iid: String in iids:
		losses[iid] = _loss(iid)
		settles[iid] = u.pay_raise_cost(iid)
		breaks[iid] = u.break_cost(iid)
		totals["loss"] += float(losses[iid])
		totals["settle"] += float(settles[iid])
		totals["break"] += float(breaks[iid])
		left = maxi(left, u.strike_turns_left(iid))
	var grid := _grid(losses.values() + settles.values() + breaks.values() + totals.values())
	rows.add_child(_header_row(grid))
	var n := iids.size()
	var when := ""
	if striking:
		when = "%d turn%s left" % [left, "" if left == 1 else "s"]
	else:
		var due := maxi(0, int(u.warning.get("turn", turn)) - turn)
		when = "Starts this turn" if due == 0 else "Starts in %d turn%s" % [due, "" if due == 1 else "s"]
	var head := _row("AllStrikes", Kit.raised("econ_icon_labour", ICON_PX),
		Kit.info("All strikes (%d building%s)" % [n, "" if n == 1 else "s"], "bad" if striking else "warn", when),
		"all", float(totals.loss), float(totals.settle), float(totals["break"]), grid, iids)
	head.set_meta("total", totals.settle)
	head.set_meta("break", totals["break"])
	head.set_meta("loss", totals.loss)
	rows.add_child(head)
	if _confirming.get_slice(":", 1) == "all":
		rows.add_child(_bed(_confirming.get_slice(":", 0), "all", iids))
	rows.add_child(_fold_row(n))
	var indent := MarginContainer.new()
	indent.name = "StrikersFold"
	indent.add_theme_constant_override("margin_left", MEMBER_INDENT)
	indent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indent.visible = _members_open
	rows.add_child(indent)
	var list := VBoxContainer.new()
	list.name = "Strikers"
	list.add_theme_constant_override("separation", 6)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indent.add_child(list)
	for iid: String in iids:
		list.add_child(_member(iid, float(losses[iid]), float(settles[iid]), float(breaks[iid]), grid))
		if _confirming.get_slice(":", 1) == iid:
			list.add_child(_bed(_confirming.get_slice(":", 0), iid, [iid]))
	return c.case


## What a building's strike would cost or still costs: a named one's whole strike, a striking one's turns left.
func _loss(iid: String) -> float:
	var u := LabourState.unrest
	if u.is_on_strike(iid):
		return u.output_value_per_turn(iid) * (1.0 - LabourUnrest.STRIKE_OUTPUT_MULT) * float(u.strike_turns_left(iid))
	return u.expected_loss(iid)


## The table's columns: one digit count for every screen, so they are one width and their £ signs line up;
## Output loss and Cost to manage a screen wide (or their labels), Action the wider key, both keys that wide.
static func _grid(values: Array) -> Dictionary:
	var digits := 1
	var suffix := 0.0
	for v in values:
		var p := MoneyFigure.screen(float(v))
		digits = maxi(digits, Led.cells_for(str(p.figure)).size())
		if str(p.suffix) != "":
			suffix = Kit.caption_width(str(p.suffix), Kit.POUND_PX) + 4.0
	var money_w := ceilf(Kit.money_width(digits) + suffix)
	var key_w := maxf(CreamKey.width_for(SETTLE, "", false, false, KEY_SCALE), CreamKey.width_for(BREAK, "", false, false, KEY_SCALE))
	return {"digits": digits, "money_w": money_w,
		"loss_w": maxf(money_w, Kit.caption_width(LOSS) + 4.0),
		"cost_w": maxf(money_w, Kit.caption_width(COST) + 4.0),
		"action_w": maxf(key_w, Kit.caption_width(ACTION) + 4.0)}


## The column labels as metal labels, over the rows' columns.
static func _header_row(grid: Dictionary) -> Control:
	var wrap := MarginContainer.new()
	wrap.name = "StrikeHeadings"
	wrap.add_theme_constant_override("margin_left", roundi(Kit.PAD.x))
	wrap.add_theme_constant_override("margin_right", roundi(Kit.PAD.x))
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", COL_GAP)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(line)
	for spec: Array in [[LOCATION, 0.0], [LOSS, float(grid.loss_w)], [COST, float(grid.cost_w)], [ACTION, float(grid.action_w)]]:
		var l := Kit.caption(str(spec[0]), Kit.CAPTION_PX, HORIZONTAL_ALIGNMENT_LEFT if float(spec[1]) == 0.0 else HORIZONTAL_ALIGNMENT_CENTER)
		l.name = "Heading_%s" % str(spec[0]).replace(" ", "")
		if float(spec[1]) == 0.0:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			l.custom_minimum_size.x = float(spec[1])
		line.add_child(l)
	return wrap


## A table row: `icon` and `info` in Location, then the loss, then two lines, Settle's cost beside its key over
## Break strike's cost beside its key.
func _row(row_name: String, icon: Control, info: Control, target: String, loss: float, settle: float, brk: float,
		grid: Dictionary, iids: Array) -> PanelContainer:
	var module := Kit.module(row_name, true)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = Kit.PAD.x
	pad.content_margin_right = Kit.PAD.x
	pad.content_margin_top = ROW_PAD_Y
	pad.content_margin_bottom = ROW_PAD_Y
	module.add_theme_stylebox_override("panel", pad)
	var row := Kit.row_of(module)
	row.custom_minimum_size.y = 0
	row.add_theme_constant_override("separation", COL_GAP)
	var location := HBoxContainer.new()
	location.name = "Location"
	location.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	location.add_theme_constant_override("separation", COL_GAP)
	location.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	location.add_child(icon)
	location.add_child(info)
	row.add_child(location)
	var striking := target != "all" and LabourState.unrest.is_on_strike(target)
	var loss_tip := "%d%% of %s output for %s, at today's prices." % [LabourUnrest.output_cut_pct(),
		"every striker's" if target == "all" else "its",
		("the %d turns left" % LabourState.unrest.strike_turns_left(target)) if striking else "the turns its strike runs"]
	row.add_child(_money_cell(loss, Parts.RED, float(grid.loss_w), grid, {"name": LOSS, "detail": loss_tip}, "Loss"))
	var where := "every striker" if target == "all" else "this building"
	var shift := LabourUnrest.BREAK_SHIFT_ROUND if target == "all" else LabourUnrest.BREAK_SHIFT_ONE
	var manage := VBoxContainer.new()
	manage.name = "Manage"
	manage.add_theme_constant_override("separation", 4)
	manage.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	manage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(manage)
	for spec: Array in [
		["settle", SETTLE, "Settle", settle, "Pay %d%% higher at %s for %d turns." % [roundi(LabourUnrest.PAY_RAISE * 100.0), where, LabourUnrest.PAY_RAISE_TURNS]],
		["break", BREAK, "BreakStrike", brk, "Replacement crews at %s, paid this turn. Satisfaction %s for %d turns." % [where, _n(shift), LabourState.EVENT_SHIFT_TURNS]],
	]:
		var line := HBoxContainer.new()
		line.name = "%sLine" % str(spec[2])
		line.add_theme_constant_override("separation", COL_GAP)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		manage.add_child(line)
		line.add_child(_money_cell(float(spec[3]), DS.PALETTE["TEXT"], float(grid.cost_w), grid,
			{"name": str(spec[1]), "detail": str(spec[4])}, "%sCost" % str(spec[2])))
		var action := "%s:%s" % [str(spec[0]), target]
		var key_name := "%sAll" % str(spec[2]) if target == "all" else "%s_%s" % [str(spec[2]), target]
		var key: Button = CreamKey.make(key_name, str(spec[1]), "", float(grid.action_w), false, false, KEY_SCALE)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.set("chosen", _confirming == action)
		key.pressed.connect(func() -> void: _toggle_confirm(action))
		line.add_child(key)
	module.set_meta("buildings", iids)
	return module


## A money figure on a screen centred in a cell `width` wide; its hover names what it is.
static func _money_cell(value: float, colour: Color, width: float, grid: Dictionary, tip: Dictionary, cell_name: String) -> Control:
	var cell: HBoxContainer = Tip.TipHBox.new()
	cell.name = cell_name
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.custom_minimum_size.x = width
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_theme_constant_override("separation", 4)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var p := MoneyFigure.screen(value)
	cell.add_child(Kit.caption("£", Kit.POUND_PX, HORIZONTAL_ALIGNMENT_RIGHT))
	var led: Control = Led.new()
	led.name = "Led"
	var fig := str(p.figure)
	led.call("set_figure", " ".repeat(maxi(0, int(grid.digits) - Led.cells_for(fig).size())) + fig, colour)
	cell.add_child(led)
	if str(p.suffix) != "":
		cell.add_child(Kit.caption(str(p.suffix), Kit.POUND_PX))
	cell.set_meta("value", value)
	Tip.attach(cell, tip)
	return cell


## The row under All strikes that folds its buildings away: "N buildings" and the fold mark. Folded at first.
func _fold_row(n: int) -> Control:
	var module := Kit.module("StrikersFoldRow", true)
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = Kit.PAD.x
	pad.content_margin_right = Kit.PAD.x
	pad.content_margin_top = ROW_PAD_Y
	pad.content_margin_bottom = ROW_PAD_Y
	module.add_theme_stylebox_override("panel", pad)
	var row := Kit.row_of(module)
	row.custom_minimum_size.y = 0
	var info := Kit.info("%d building%s" % [n, "" if n == 1 else "s"], "", "", true)
	info.name = "FoldTitle"
	row.add_child(info)
	var chevron: Control = info.find_child("Chevron", true, false)
	if chevron != null:
		chevron.set_meta("open", _members_open)
	Tip.attach(module, {"name": "%d building%s" % [n, "" if n == 1 else "s"],
		"detail": "Hide the buildings." if _members_open else "Show each building, its figures and its own keys."})
	Kit.on_click(module, func() -> void:
		_members_open = not _members_open
		_rebuild())
	return module


## One named or striking building: its emblem and the good it makes in a well, one size, at the left; its name
## with its tile under it; its loss, its costs and its keys.
func _member(iid: String, loss: float, settle: float, brk: float, grid: Dictionary) -> PanelContainer:
	var b := BuildingState.get_building(iid)
	var title := BuildingNaming.of(b) if not b.is_empty() else iid
	var tile_id := str(b.get("tile_id", ""))
	var place := Catalog.tile_name(tile_id) if Catalog.tile_name(tile_id) != "" else Catalog.tile_label(tile_id)
	var info := Kit.info(title, "", place)
	var icons := HBoxContainer.new()
	icons.name = "Icons"
	icons.add_theme_constant_override("separation", COL_GAP)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.add_child(Kit.emblem(str(b.get("building_id", "")), ICON_PX))
	var gid := _good_of(b)
	if gid != "":
		var well := Kit.good_in_well(gid, -1, "", true, ICON_PX)
		well.name = "Makes"
		well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icons.add_child(well)
	else:
		icons.add_child(Kit.spacer(ICON_PX, ICON_PX))
	var module := _row("Striker_%s" % iid, icons, info, iid, loss, settle, brk, grid, [iid])
	module.set_meta("cost", settle)
	module.set_meta("break", brk)
	module.set_meta("loss", loss)
	var striking := LabourState.unrest.is_on_strike(iid)
	Tip.attach(module, {"stage": title, "name": "On strike" if striking else "Strike warning",
		"detail": ("On strike, %d turns left." % LabourState.unrest.strike_turns_left(iid)) if striking else "Named in the strike warning.",
		"tone": "bad" if striking else "warn"})
	return module


## The good a building makes first, as its readout names it (power for a power plant), or "".
static func _good_of(b: Dictionary) -> String:
	if b.is_empty():
		return ""
	var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
	for o: Dictionary in BuildingReadout.flow(b, recipe, true).get("outputs", []):
		if str(o.get("good_id", "")) != "":
			return str(o.get("good_id", ""))
	return ""


## The bed under an action's key: what it does, then Confirm and Cancel. `action` is "settle" or "break".
func _bed(action: String, target: String, iids: Array) -> Control:
	var stem := "Settle" if action == "settle" else "BreakStrike"
	var bed := PanelContainer.new()
	bed.name = "%sBed" % stem
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(14)
	bed.add_theme_stylebox_override("panel", pad)
	bed.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	bed.draw.connect(func() -> void:
		Section.Nine.paint(bed, KEYBED, Rect2(Vector2.ZERO, bed.size).grow(KEYBED_MARGIN / Parts.LAYOUT), (KEYBED_MARGIN + KEYBED_CORNER) * Parts.TEXELS))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	bed.add_child(line)
	var said := bed_words(action, target, iids)
	var words := Kit.body(said)
	words.name = "%sWords" % stem
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(words)
	var confirm: Button = CreamKey.make("Confirm%s" % stem, "Confirm", "", 0.0, false, false, KEY_SCALE)
	confirm.custom_minimum_size.x = CreamKey.width_for("Confirm", "", false, false, KEY_SCALE) + 12.0
	confirm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	confirm.pressed.connect(func() -> void: _confirm(action, target, iids))
	line.add_child(confirm)
	var cancel: Button = CreamKey.make("Cancel%s" % stem, "Cancel", "", 0.0, false, false, KEY_SCALE)
	cancel.custom_minimum_size.x = CreamKey.width_for("Cancel", "", false, false, KEY_SCALE) + 12.0
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func() -> void: _toggle_confirm("%s:%s" % [action, target]))
	line.add_child(cancel)
	bed.set_meta("words", said)
	return bed


## What an action does, as its bed says it. Breaking also says how near the workforce is to remembering it for
## good, or that this one will make it.
static func bed_words(action: String, target: String, iids: Array) -> String:
	var u := LabourState.unrest
	var turns := LabourState.EVENT_SHIFT_TURNS
	if action == "settle":
		var pct := roundi(LabourUnrest.PAY_RAISE * 100.0)
		if target == "all":
			return "Pay %d%% higher at %s for %d turns. Every strike ends, and none can start for %d turns." % [
				pct, "this building" if iids.size() == 1 else "these %d buildings" % iids.size(),
				LabourUnrest.PAY_RAISE_TURNS, LabourUnrest.STRIKE_FREE_TURNS]
		return "Pay %d%% higher here for %d turns. %s" % [pct, LabourUnrest.PAY_RAISE_TURNS,
			"Its workers go back to work." if u.is_on_strike(target) else "It leaves the strike."]
	var said := ""
	if target == "all":
		said = "Replacement crews end every strike in this round, paid this turn. Satisfaction %s for %d turns. Strikes can come back at the next check." % [
			_n(LabourUnrest.BREAK_SHIFT_ROUND), turns]
	else:
		said = "Replacement crews %s, paid this turn. Satisfaction %s for %d turns." % [
			"end this strike" if u.is_on_strike(target) else "stand ready, so it will not strike", _n(LabourUnrest.BREAK_SHIFT_ONE), turns]
	if u.routinely_broke:
		return said
	if u.break_makes_routine(target):
		return said + " The workforce will remember this for good: Routinely broke strikes, satisfaction %s until a Comprehensive Union Agreement is signed." % _n(LabourUnrest.ROUTINE_SATISFACTION)
	if target == "all":
		return said + " %d of %d whole rounds broken so far. At %d the workforce remembers it for good." % [
			u.rounds_broken, LabourUnrest.ROUTINE_ROUNDS, LabourUnrest.ROUTINE_ROUNDS]
	return said + " %d of %d single breaks so far. At %d the workforce remembers it for good." % [
		u.buildings_broken, LabourUnrest.ROUTINE_BUILDINGS, LabourUnrest.ROUTINE_BUILDINGS]


func _confirm(action: String, target: String, iids: Array) -> void:
	var u := LabourState.unrest
	var turn := int(TurnManager.current_turn)
	_confirming = ""
	var b := BuildingState.get_building(target)
	var who := BuildingNaming.of(b) if not b.is_empty() else target
	if action == "break":
		if target == "all":
			if u.break_all(turn, iids):
				MatchState.request_toast("Strikes broken. Everyone is back at work.", "warning")
		elif u.break_strike(target, turn):
			MatchState.request_toast("Strike broken at %s." % who, "warning")
	elif target == "all":
		if u.raise_pay_all(turn, iids):
			MatchState.request_toast("Strikes settled. No strikes for %d turns." % LabourUnrest.STRIKE_FREE_TURNS, "success")
	elif u.raise_pay(target):
		MatchState.request_toast("Strike settled at %s." % who, "success")
	_rebuild()


# --- the record ----------------------------------------------------------------------------------

func _record() -> Control:
	var c := _cased("StrikeRecord", "Record")
	var rows: VBoxContainer = c.rows
	rows.add_theme_constant_override("separation", 6)
	var entries: Array = LabourState.unrest.record.duplicate()
	entries.reverse()
	entries = entries.slice(0, RECORD_SHOWN)
	var lost: Array = []
	var turn_w := 0.0
	for e: Dictionary in entries:
		lost.append(float(e.get("lost", 0.0)))
		turn_w = maxf(turn_w, Kit.caption_width("Turn %d" % int(e.get("turn", 0))) + 4.0)
	var grid := _grid(lost)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var names := PackedStringArray()
		for b: Dictionary in e.get("buildings", []):
			names.append(str(b.get("name", "")))
		var outcome_id := str(e.get("outcome", ""))
		var m := Kit.module("RecordLine_%d" % i, true)
		var row := Kit.row_of(m)
		row.custom_minimum_size.y = 0
		var when := Kit.caption("Turn %d" % int(e.get("turn", 0)))
		when.custom_minimum_size.x = turn_w
		row.add_child(when)
		var who := ", ".join(names) if not names.is_empty() else "Nobody"
		var outcome := "Called off"
		var tone := "ok"
		if outcome_id == "struck":
			outcome = "Struck for %d turns" % LabourUnrest.STRIKE_TURNS
			tone = "bad"
		elif outcome_id == "broken":
			outcome = "Broken"
			tone = "warn"
		row.add_child(Kit.line_info(who, tone, outcome))
		if outcome_id == "struck":
			row.add_child(_money_cell(float(e.get("lost", 0.0)), Parts.RED, float(grid.loss_w), grid,
				{"name": "Output lost", "detail": "%d%% of the strikers' output for %d turns, at the prices of the day." % [
					LabourUnrest.output_cut_pct(), LabourUnrest.STRIKE_TURNS]}, "Lost"))
		else:
			row.add_child(Kit.spacer(float(grid.loss_w), 0))
		m.set_meta("words", "Turn %d. %s. %s." % [int(e.get("turn", 0)), who, outcome])
		rows.add_child(m)
	return c.case


## A threshold as the panels print it, with a true minus sign.
static func _n(v: float) -> String:
	return LabourState.signed_text(v)


func shot_views() -> Array:
	return [
		{"name": "quiet", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_NONE)
			LabourState.unrest.reset()
			LabourState.satisfaction = 12.0
			_subtab = ""
			_confirming = ""
			_members_open = false
			_rebuild()},
		{"name": "warning", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_NONE)
			LabourState.unrest.reset()
			LabourState.satisfaction = -78.0
			var named: Array = LabourState.unrest.eligible_buildings().slice(0, 2)
			LabourState.unrest.warning = {"turn": LabourUnrest.next_check_turn(int(TurnManager.current_turn)),
				"buildings": named, "heavy": false, "light": named.size()}
			_subtab = ""
			_confirming = ""
			_members_open = false
			_rebuild()},
		{"name": "warning_open", "setup": func() -> void:
			_members_open = true
			_rebuild()},
		{"name": "warning_settle", "setup": func() -> void:
			_confirming = "settle:all"
			_rebuild()},
		{"name": "warning_break", "setup": func() -> void:
			_confirming = "break:all"
			_rebuild()},
		{"name": "warning_ongoing_tab", "setup": func() -> void:
			_subtab = ONGOING
			_confirming = ""
			_rebuild()},
		{"name": "on_strike", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_NONE)
			LabourState.unrest.reset()
			LabourState.satisfaction = -94.0
			var named: Array = LabourState.unrest.eligible_buildings().slice(0, 2)
			for iid: String in named:
				LabourState.unrest.active[iid] = 2
			LabourState.unrest._add_record(10, named, "called off", 0.0)
			LabourState.unrest._add_record(20, named, "struck", 96.0)
			LabourState.unrest._add_record(30, named.slice(0, 1), "broken", 0.0)
			_subtab = ""
			_members_open = true
			_confirming = ("break:%s" % named[0]) if not named.is_empty() else ""
			_rebuild()},
	]


## Satisfaction from −100 to +100 on Building Detail's mini screen (mini_screen and its glass, as the value
## bars are): below −90 lit red, where half the buildings can strike, −90 to −70 amber, a quarter, the rest
## dark. A needle stands at today's value with its arrow over the bezel, and the thresholds are printed under
## the screen. Its hover is a readout (Tip.attach).
class StrikeScale extends Control:
	const Nine := preload("res://scripts/bdp_v3_nine.gd")
	const Light := preload("res://scripts/bdp_v3_light.gd")
	const Plate := preload("res://scripts/bdp_v3_plate.gd")
	const LedScreen := preload("res://scripts/bdp_v3_led.gd")
	const Unrest := preload("res://scripts/labour_unrest.gd")
	const HEAVY := Color("#E66060")
	const LIGHT := Color("#E6B85C")
	const NEEDLE := Color("#efede6")
	## From layout.json (mini_screen), in layout px: the screen's shadow room, its bezel and its pane's radius.
	const MARGIN := 8.0
	const RIM := 7.0
	const RADIUS := 5.0
	const CAPTURE_SCALE := 1.875
	## In logical px: the pane's height, the arrow over the bezel, and the thresholds' print under it.
	const BAR_H := 14.0
	const ARROW := 9.0
	const MARK_GAP := 5.0
	const MARK_PX := 15
	## The clear room a printed mark keeps either side.
	const MARK_ROOM := 8.0
	const LOW := -100.0
	const HIGH := 100.0

	var value := 0.0
	var tip: Dictionary = {}
	var _lit: Control

	func _init(v: float) -> void:
		value = clampf(v, LOW, HIGH)
		name = "StrikeScale"
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2(240.0, ARROW + 2.0 + _frame_h() + MARK_GAP + Plate.FONT_SEMI.get_height(MARK_PX))
		_lit = Control.new()
		_lit.name = "Zones"
		_lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_lit.material = Light.emissive_material()
		_lit.draw.connect(_draw_zones)
		add_child(_lit)
		var glass := Control.new()
		glass.name = "Glass"
		glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glass.draw.connect(func() -> void: Nine.paint(glass, LedScreen.GLASS, _bar().grow(MARGIN / CAPTURE_SCALE), _corner()))
		add_child(glass)

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/ds2/tip.gd").make(tip) if not tip.is_empty() else null

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()
			_lit.queue_redraw()
			for c in get_children():
				(c as CanvasItem).queue_redraw()

	func _frame_h() -> float:
		return BAR_H + 2.0 * (RIM / CAPTURE_SCALE + 2.0)

	func _corner() -> float:
		return (MARGIN + RIM + RADIUS + 2.0) * 2.0 / CAPTURE_SCALE

	## The bezel, under the arrow's room, inset by its shadow room so the shadow stays inside the control.
	func _bar() -> Rect2:
		var m := MARGIN / CAPTURE_SCALE
		return Rect2(m, ARROW + 2.0, size.x - 2.0 * m, _frame_h())

	func _pane() -> Rect2:
		return _bar().grow(-(RIM / CAPTURE_SCALE + 2.0))

	func x_of(v: float) -> float:
		var pane := _pane()
		return pane.position.x + pane.size.x * (clampf(v, LOW, HIGH) - LOW) / (HIGH - LOW)

	func _draw() -> void:
		var bar := _bar()
		Nine.paint(self, LedScreen.SCREEN, bar.grow(MARGIN / CAPTURE_SCALE), _corner())
		# The needle's arrow over the bezel, pointing down at today's value, with a shadow.
		var x := x_of(value)
		var tri := PackedVector2Array([Vector2(x - ARROW * 0.6, 0.0), Vector2(x + ARROW * 0.6, 0.0), Vector2(x, ARROW)])
		var shadow := PackedVector2Array()
		for p in tri:
			shadow.append(p + Vector2(1.0, 1.0))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.8))
		draw_colored_polygon(tri, NEEDLE)
		# The thresholds, printed under the screen: the ends flush with it, the rest centred on their mark.
		var y := bar.end.y + MARK_GAP + Plate.FONT_SEMI.get_ascent(MARK_PX)
		for m: Dictionary in marks():
			var at := Vector2(float(m.x), y)
			draw_string(Plate.FONT_SEMI, at + Vector2(1.0, 1.0), str(m.text), HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_PX, Color(0, 0, 0, 0.9))
			draw_string(Plate.FONT_SEMI, at, str(m.text), HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_PX, DS.PALETTE["TEXT"])

	## The printed marks [{text, x}]: the thresholds and 0 centred on their place, then each end flush with
	## the screen where it clears them (−100 sits too close to −90 on a narrow scale, and gives way).
	func marks() -> Array:
		var out: Array = []
		var taken: Array[Rect2] = []
		for v: float in [Unrest.HEAVY_STRIKE_BELOW, Unrest.STRIKE_BELOW, 0.0]:
			var text := LabourState.signed_text(v)
			var w := Plate.FONT_SEMI.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_PX).x
			out.append({"text": text, "x": x_of(v) - w * 0.5})
			taken.append(Rect2(x_of(v) - w * 0.5 - MARK_ROOM, 0.0, w + 2.0 * MARK_ROOM, 1.0))
		for v: float in [LOW, HIGH]:
			var text := LabourState.signed_text(v)
			var w := Plate.FONT_SEMI.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, MARK_PX).x
			var x := _pane().position.x if v == LOW else _pane().end.x - w
			var span := Rect2(x, 0.0, w, 1.0)
			if not taken.any(func(r: Rect2) -> bool: return r.intersects(span)):
				out.append({"text": text, "x": x})
		return out

	## The zones lit as the value bars' slices are (their own light, so the lamp over the panel doesn't dim
	## them), the dark zone faintly, a mark at 0, and the needle across the pane.
	func _draw_zones() -> void:
		var pane := _pane()
		var spans := [[LOW, Unrest.HEAVY_STRIKE_BELOW, HEAVY], [Unrest.HEAVY_STRIKE_BELOW, Unrest.STRIKE_BELOW, LIGHT],
			[Unrest.STRIKE_BELOW, HIGH, Color(1, 1, 1, 0.06)]]
		for s: Array in spans:
			var x0 := x_of(float(s[0]))
			var x1 := x_of(float(s[1]))
			var rect := Rect2(x0, pane.position.y, x1 - x0, pane.size.y)
			_lit.draw_rect(rect, s[2])
			if (s[2] as Color).a > 0.5:
				_lit.draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.35)), Color(1, 1, 1, 0.12))
				_lit.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y * 0.75), Vector2(rect.size.x, rect.size.y * 0.25)), Color(0, 0, 0, 0.18))
			if x0 > pane.position.x + 0.5:
				_lit.draw_line(Vector2(x0, rect.position.y), Vector2(x0, rect.end.y), Color(0, 0, 0, 0.55), 1.0)
		var zero := x_of(0.0)
		_lit.draw_line(Vector2(zero, pane.position.y), Vector2(zero, pane.end.y), Color(1, 1, 1, 0.25), 1.0)
		var x := x_of(value)
		_lit.draw_rect(Rect2(x - 1.5, pane.position.y - 1.0, 3.0, pane.size.y + 2.0), Color(0, 0, 0, 0.6))
		_lit.draw_rect(Rect2(x - 1.0, pane.position.y - 1.0, 2.0, pane.size.y + 2.0), NEEDLE)


## A zone's colour in the strike scale's key: a small lit pane in a dark rim.
class Swatch extends Control:
	var colour := Color.WHITE

	func _init(c: Color) -> void:
		colour = c
		name = "Swatch"
		custom_minimum_size = Vector2(22, 12)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r.grow(1.0), Color(0, 0, 0, 0.85))
		draw_rect(r, colour)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.14))
