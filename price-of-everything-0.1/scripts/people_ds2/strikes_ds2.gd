extends Control
## The People panel's Strikes tab in DS2 (docs/pacing-labour-mining-licensing-spec.md §6.3), racked in the DS2
## kit's cases and modules as the tile view's Buildings tab is (scripts/ds2/parts.gd):
## - Strike risk: a module with the labour icon, the workforce's pilot lamp, its mood and what it means, and
##   the turns to the next check on a drum (or to the end of a pay rise's protection). Under it the strike
##   scale: satisfaction on Building Detail's mini screen, the two strike zones lit and a needle at today's
##   value, then the zones' key and the key that opens the encyclopedia's Mechanics page on strikes.
## - The board, while strikers are named or on strike: "All strikes (N buildings)" first, as a group's head,
##   with the turns on a drum and the expected loss on an LED screen, then its two actions, each a cost on an
##   LED screen beside its key: Raise pay and Break strike. The buildings hang off its cable, each with its
##   emblem, its name with the good it makes in a well, its tile, its own loss and its own two actions. Every
##   figure stands in one column down the case. An action's key opens a key bed under its module saying what
##   it does, with Confirm and Cancel.
## - The record: a module a past strike, its turn, the buildings, the outcome's lamp and what it lost.
##
## The figures and the pay rises are LabourState.unrest's (scripts/labour_unrest.gd).

const Parts := preload("res://scripts/people_ds2/parts.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const Cable := preload("res://scripts/bdp_v3_cable.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const Tip := preload("res://scripts/ds2/tip.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
const Encyclopedia := preload("res://scripts/encyclopedia_ds2/catalogue.gd")
const LabourUnrest := preload("res://scripts/labour_unrest.gd")

const RAIL_ROOM := 24
const KEY_SCALE := 0.72
## The Mechanics page "How strikes work" opens (search_overlay.gd MECHANIC_ENTRIES).
const MECHANICS_ENTRY := "strikes"
## The board's cable runs under the centre of the head's icon; the buildings start a tap's length right of it.
const FEED_X := Kit.PAD.x + Kit.EMBLEM_PX * 0.5
const FEED_INDENT := FEED_X + Cable.TAP_LENGTH
## The pay rise's key bed: the Advisors tab's seat choice bed (tile_keybed, layout px).
const KEYBED: Texture2D = preload("res://assets/ui/bdp_v3/tile_keybed.png")
const KEYBED_MARGIN := 14.0
const KEYBED_CORNER := 40.0
## The figures' labels, printed once under the head's figures.
const STARTS_IN := "Starts in"
const TURNS_LEFT := "Turns left"
const NEXT_CHECK := "Turns to check"
const TURNS_FREE := "Turns free"
const LOSS := "Expected loss"
const PAY_RISE := "Pay rise"
const RAISE := "Raise pay"
const BREAK := "Break strike"
const RECORD_SHOWN := 8
## A building's good, in a well on its name's line.
const GOOD_PX := 36

var _scroll: ScrollContainer
var _body: VBoxContainer
var _refresh_queued := false
## The action whose bed is open, as "raise:<target>" or "break:<target>" (target "all" or a building's
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
	_body.add_theme_constant_override("separation", 16)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_body)
	LabourState.unrest_changed.connect(_queue_refresh)
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
	var affected := u.affected_buildings()
	var target := _confirming.get_slice(":", 1)
	if not (target == "all" and not affected.is_empty()) and not affected.has(target):
		_confirming = ""
	_body.add_child(_risk())
	if not affected.is_empty():
		_body.add_child(_board(affected))
	if not u.record.is_empty():
		_body.add_child(_record())


## Opens the bed under an action's key ("raise:all", "break:<iid>"), or shuts it when it is already open.
func _toggle_confirm(action: String) -> void:
	_confirming = "" if _confirming == action else action
	_rebuild()


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
		o.merge({"tone": "ok", "words": "Pay rises hold strikes off.", "turns": u.strike_free_until - turn,
			"caption": TURNS_FREE}, true)
	elif s < LabourUnrest.HEAVY_STRIKE_BELOW:
		o.merge({"tone": "bad", "words": "Half your buildings can strike."}, true)
	elif s < LabourUnrest.STRIKE_BELOW:
		o.merge({"tone": "warn", "words": "A quarter of your buildings can strike."}, true)
	else:
		o.merge({"tone": "ok", "words": "No strikes at %s or above." % _n(LabourUnrest.STRIKE_BELOW)}, true)
	return o


func _risk() -> Control:
	var col := VBoxContainer.new()
	col.name = "StrikeStatus"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("Strike risk"))
	var case := Kit.plastic_case("StrikeRiskCase")
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 12)
	var o := outlook(int(TurnManager.current_turn))
	var module := Kit.module("Outlook")
	var row := Kit.row_of(module)
	row.add_child(Kit.raised("econ_icon_labour", Kit.EMBLEM_PX))
	var info := Kit.info(str(o.title), str(o.tone), str(o.words))
	info.name = "Mood"
	row.add_child(info)
	if int(o.turns) >= 0:
		row.add_child(_turns_col(int(o.turns), str(o.caption), _drum_w(int(o.turns), [str(o.caption)])))
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
	col.set_meta("outlook", o)
	return col


# --- the board -----------------------------------------------------------------------------------

## The named and striking buildings under "All strikes (N buildings)".
func _board(iids: Array) -> Control:
	var u := LabourState.unrest
	var turn := int(TurnManager.current_turn)
	var named: Array = u.warning.get("buildings", [])
	var striking := not u.active.is_empty()
	var col := VBoxContainer.new()
	col.name = "OnStrike" if striking else "WarningBoard"
	col.add_theme_constant_override("separation", 10)
	var title := "On strike"
	if not striking:
		title = "Strike warning: turn %d" % int(u.warning.get("turn", turn))
	elif not named.is_empty():
		title = "Strikes"
	col.add_child(Parts.heading(title))
	var case := Kit.plastic_case("StrikeBoardCase")
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	var losses := {}
	var costs := {}
	var breaks := {}
	var total_loss := 0.0
	var total_cost := 0.0
	var total_break := 0.0
	var left := 0
	for iid: String in iids:
		losses[iid] = _loss(iid)
		costs[iid] = u.pay_raise_cost(iid)
		breaks[iid] = u.break_cost(iid)
		total_loss += float(losses[iid])
		total_cost += float(costs[iid])
		total_break += float(breaks[iid])
		left = maxi(left, u.strike_turns_left(iid))
	var turns := left if striking else maxi(0, int(u.warning.get("turn", turn)) - turn)
	var caption := TURNS_LEFT if striking else STARTS_IN
	var grid := _grid(losses.values() + costs.values() + breaks.values() + [total_loss, total_cost, total_break], turns, caption)
	var head := Kit.module("AllStrikes")
	var row := Kit.row_of(head)
	row.add_child(Kit.raised("econ_icon_labour", Kit.EMBLEM_PX))
	var n := iids.size()
	var cut := LabourUnrest.output_cut_pct()
	var words := ("Output %s%%" % _n(-cut)) if striking else "Output %s%% for %d turns" % [_n(-cut), LabourUnrest.STRIKE_TURNS]
	row.add_child(Kit.info("All strikes (%d building%s)" % [n, "" if n == 1 else "s"], "bad" if striking else "warn", words))
	row.add_child(_turns_col(turns, caption, float(grid.fig_w)))
	row.add_child(_money_col(total_loss, Parts.RED, LOSS, grid,
		{"name": LOSS, "detail": "%d%% of every striker's output for the turns its strike runs, at today's prices." % LabourUnrest.output_cut_pct()}))
	row.add_child(_actions("all", total_cost, total_break, grid))
	head.set_meta("total", total_cost)
	head.set_meta("break", total_break)
	head.set_meta("loss", total_loss)
	rows.add_child(head)
	if _confirming.get_slice(":", 1) == "all":
		rows.add_child(_bed(_confirming.get_slice(":", 0), "all", iids))
	var feed := PanelContainer.new()
	feed.name = "Feed"
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = FEED_INDENT
	feed.add_theme_stylebox_override("panel", bare)
	rows.add_child(feed)
	var cable: Control = Cable.new()
	cable.centre_x = FEED_X - FEED_INDENT
	cable.inset = 0.0
	feed.add_child(cable)
	var list := VBoxContainer.new()
	list.name = "Strikers"
	list.add_theme_constant_override("separation", 6)
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.add_child(list)
	var taps: Array[Control] = []
	for iid: String in iids:
		var m := _member(iid, float(losses[iid]), float(costs[iid]), float(breaks[iid]), grid)
		list.add_child(m)
		taps.append(m)
		if _confirming.get_slice(":", 1) == iid:
			list.add_child(_bed(_confirming.get_slice(":", 0), iid, [iid]))
	cable.taps = taps
	return col


## What a building's strike would cost or still costs: a named one's whole strike, a striking one's turns left.
func _loss(iid: String) -> float:
	var u := LabourState.unrest
	if u.is_on_strike(iid):
		return u.output_value_per_turn(iid) * (1.0 - LabourUnrest.STRIKE_OUTPUT_MULT) * float(u.strike_turns_left(iid))
	return u.expected_loss(iid)


## The board's columns: one digit count for every screen, so they are one width and their £ signs line up;
## the loss column at least as wide as its label; the head's turns column as wide as its drum and label; the
## keys one width, so the action screens line up too.
static func _grid(values: Array, turns: int, caption: String) -> Dictionary:
	var digits := 1
	var suffix := 0.0
	for v in values:
		var p := MoneyFigure.screen(float(v))
		digits = maxi(digits, Led.cells_for(str(p.figure)).size())
		if str(p.suffix) != "":
			suffix = Kit.caption_width(str(p.suffix), Kit.POUND_PX) + 4.0
	var money_w := Kit.money_width(digits) + suffix
	return {"digits": digits, "money_w": ceilf(money_w), "loss_w": ceilf(maxf(money_w, Kit.caption_width(LOSS) + 4.0)),
		"fig_w": ceilf(_drum_w(turns, [caption])),
		"key_w": maxf(CreamKey.width_for(RAISE, "", true, false, KEY_SCALE), CreamKey.width_for(BREAK, "", true, false, KEY_SCALE))}


static func _drum_w(turns: int, captions: Array) -> float:
	var w := Drum.width_for(str(maxi(0, turns)).length(), Drum.led_height())
	for c: String in captions:
		w = maxf(w, Kit.caption_width(c) + 4.0)
	return w


## Turns on a drum, its label under it, in a column `width` wide.
static func _turns_col(turns: int, caption: String, width: float) -> VBoxContainer:
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


## A money figure on an LED screen in the board's column, with its label under it on the head (`caption`).
## The loss column (`caption` set, or `wide`) is the loss column's width, the actions' screens the screens'.
static func _money_col(value: float, colour: Color, caption: String, grid: Dictionary, tip: Dictionary, wide := false) -> VBoxContainer:
	var col: VBoxContainer = Tip.TipVBox.new()
	col.name = caption.replace(" ", "") if caption != "" else "Figure"
	col.add_theme_constant_override("separation", 2)
	var width := float(grid.loss_w) if caption != "" or wide else float(grid.money_w)
	col.custom_minimum_size = Vector2(width, 0)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_PASS if not tip.is_empty() else Control.MOUSE_FILTER_IGNORE
	var p := MoneyFigure.screen(value)
	col.add_child(Kit.money(str(p.figure), colour, int(grid.digits), str(p.suffix)))
	if caption != "":
		col.add_child(Kit.caption_under(caption, width))
	col.set_meta("value", value)
	if not tip.is_empty():
		Tip.attach(col, tip)
	return col


## A row's two actions, one over the other: what a pay rise costs over its 10 turns beside Raise pay, and
## what breaking the strike costs this turn beside Break strike. A key opens its bed under the row and stays
## down while the bed is open.
func _actions(target: String, pay: float, brk: float, grid: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = "Actions"
	col.add_theme_constant_override("separation", 6)
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pct := roundi(LabourUnrest.PAY_RAISE * 100.0)
	var where := "at every striker" if target == "all" else "here"
	var shift := LabourUnrest.BREAK_SHIFT_ROUND if target == "all" else LabourUnrest.BREAK_SHIFT_ONE
	for spec: Array in [
		["raise", RAISE, "RaisePay", pay, {"name": PAY_RISE, "detail": "%d%% more labour %s for %d turns." % [pct, where, LabourUnrest.PAY_RAISE_TURNS]}],
		["break", BREAK, "BreakStrike", brk, {"name": "Strike breaking", "detail": "Replacement crews, paid this turn. Satisfaction %s for %d turns." % [_n(shift), LabourState.EVENT_SHIFT_TURNS]}],
	]:
		var line := HBoxContainer.new()
		line.name = "%sLine" % str(spec[2])
		line.add_theme_constant_override("separation", Kit.GAP)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(line)
		line.add_child(_money_col(float(spec[3]), DS.PALETTE["TEXT"], "", grid, spec[4]))
		var action := "%s:%s" % [str(spec[0]), target]
		var key_name := "%sAll" % str(spec[2]) if target == "all" else "%s_%s" % [str(spec[2]), target]
		var key: Button = CreamKey.make(key_name, str(spec[1]), "", float(grid.key_w), true, false, KEY_SCALE)
		key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		key.set("chosen", _confirming == action)
		key.pressed.connect(func() -> void: _toggle_confirm(action))
		line.add_child(key)
	return col


## One named or striking building on the board's cable: its emblem, its name with the good it makes in a small
## well, its tile under its lamp, its loss, and its own two actions.
func _member(iid: String, loss: float, cost: float, brk: float, grid: Dictionary) -> PanelContainer:
	var u := LabourState.unrest
	var b := BuildingState.get_building(iid)
	var module := Kit.module("Striker_%s" % iid)
	var row := Kit.row_of(module)
	row.add_child(Kit.emblem(str(b.get("building_id", "")), Kit.EMBLEM_PX))
	var title := BuildingNaming.of(b) if not b.is_empty() else iid
	var striking := u.is_on_strike(iid)
	var tile_id := str(b.get("tile_id", ""))
	var place := Catalog.tile_name(tile_id) if Catalog.tile_name(tile_id) != "" else Catalog.tile_label(tile_id)
	var info := Kit.info(title, "bad" if striking else "warn", place)
	row.add_child(info)
	# The good it makes, in a small well at the end of its name's line: one column down the board.
	var gid := _good_of(b)
	if gid != "":
		var name_l := info.get_node("Title") as Label
		var line := HBoxContainer.new()
		line.name = "TitleLine"
		line.add_theme_constant_override("separation", 8)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.remove_child(name_l)
		line.add_child(name_l)
		var well := Kit.good_in_well(gid, -1, "", true, GOOD_PX)
		well.name = "Makes"
		well.size_flags_horizontal = Control.SIZE_SHRINK_END
		well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(well)
		info.add_child(line)
		info.move_child(line, 0)
	row.add_child(_money_col(loss, Parts.RED, "", grid,
		{"name": LOSS, "detail": ("%d%% of its output for the %d turns left." % [LabourUnrest.output_cut_pct(), u.strike_turns_left(iid)]) if striking
			else "%d%% of its output for %d turns, at today's prices." % [LabourUnrest.output_cut_pct(), LabourUnrest.STRIKE_TURNS]}, true))
	row.add_child(_actions(iid, cost, brk, grid))
	module.set_meta("cost", cost)
	module.set_meta("break", brk)
	module.set_meta("loss", loss)
	var state := ("On strike, %d turns left" % u.strike_turns_left(iid)) if striking else "Named in the strike warning"
	Tip.attach(module, {"stage": title, "name": "On strike" if striking else "Strike warning", "detail": state + ".",
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


## The bed under an action's key: what it does, then Confirm and Cancel. `action` is "raise" or "break".
func _bed(action: String, target: String, iids: Array) -> Control:
	var stem := "RaisePay" if action == "raise" else "BreakStrike"
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
	confirm.pressed.connect(func() -> void: _confirm(action, target))
	line.add_child(confirm)
	var cancel: Button = CreamKey.make("Cancel%s" % stem, "Cancel", "", 0.0, false, false, KEY_SCALE)
	cancel.custom_minimum_size.x = CreamKey.width_for("Cancel", "", false, false, KEY_SCALE) + 12.0
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(func() -> void: _toggle_confirm("%s:%s" % [action, target]))
	line.add_child(cancel)
	bed.set_meta("words", said)
	return bed


## What an action does, as its bed says it. Breaking also says how close the workforce is to remembering it for
## good, or that this one will.
static func bed_words(action: String, target: String, iids: Array) -> String:
	var u := LabourState.unrest
	var turns := LabourState.EVENT_SHIFT_TURNS
	if action == "raise":
		var pct := roundi(LabourUnrest.PAY_RAISE * 100.0)
		if target == "all":
			return "Labour costs %d%% more at %s for %d turns. Every strike ends, and none can start for %d turns." % [
				pct, "this building" if iids.size() == 1 else "these %d buildings" % iids.size(),
				LabourUnrest.PAY_RAISE_TURNS, LabourUnrest.STRIKE_FREE_TURNS]
		return "Labour costs %d%% more here for %d turns. %s" % [pct, LabourUnrest.PAY_RAISE_TURNS,
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


func _confirm(action: String, target: String) -> void:
	var u := LabourState.unrest
	var turn := int(TurnManager.current_turn)
	_confirming = ""
	var b := BuildingState.get_building(target)
	var who := BuildingNaming.of(b) if not b.is_empty() else target
	if action == "break":
		if target == "all":
			if u.break_all(turn):
				MatchState.request_toast("Strikes broken. Everyone is back at work.", "warning")
		elif u.break_strike(target, turn):
			MatchState.request_toast("Strike broken at %s." % who, "warning")
	elif target == "all":
		if u.raise_pay_all(turn):
			MatchState.request_toast("Pay raised for all strikers. No strikes for %d turns." % LabourUnrest.STRIKE_FREE_TURNS, "success")
	elif u.raise_pay(target):
		MatchState.request_toast("Pay raised at %s." % who, "success")
	_rebuild()


# --- the record ----------------------------------------------------------------------------------

func _record() -> Control:
	var col := VBoxContainer.new()
	col.name = "StrikeRecord"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("Record"))
	var case := Kit.plastic_case("RecordCase")
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 6)
	var entries: Array = LabourState.unrest.record.duplicate()
	entries.reverse()
	entries = entries.slice(0, RECORD_SHOWN)
	var lost: Array = []
	var turn_w := 0.0
	for e: Dictionary in entries:
		lost.append(float(e.get("lost", 0.0)))
		turn_w = maxf(turn_w, Kit.caption_width("Turn %d" % int(e.get("turn", 0))) + 4.0)
	var grid := _grid(lost, 0, "")
	for i in entries.size():
		var e: Dictionary = entries[i]
		var names := PackedStringArray()
		for b: Dictionary in e.get("buildings", []):
			names.append(str(b.get("name", "")))
		var outcome_id := str(e.get("outcome", ""))
		var struck := outcome_id == "struck"
		var m := Kit.module("RecordLine_%d" % i, true)
		var row := Kit.row_of(m)
		row.custom_minimum_size.y = 0
		var when := Kit.caption("Turn %d" % int(e.get("turn", 0)))
		when.custom_minimum_size.x = turn_w
		row.add_child(when)
		var who := ", ".join(names) if not names.is_empty() else "Nobody"
		var outcome := "Called off"
		var tone := "ok"
		if struck:
			outcome = "Struck for %d turns" % LabourUnrest.STRIKE_TURNS
			tone = "bad"
		elif outcome_id == "broken":
			outcome = "Broken"
			tone = "warn"
		row.add_child(Kit.line_info(who, tone, outcome))
		if struck:
			row.add_child(_money_col(float(e.get("lost", 0.0)), Parts.RED, "", grid,
				{"name": "Output lost", "detail": "%d%% of the strikers' output for %d turns, at the prices of the day." % [LabourUnrest.output_cut_pct(), LabourUnrest.STRIKE_TURNS]}))
		else:
			row.add_child(Kit.spacer(float(grid.money_w), 0))
		m.set_meta("words", "Turn %d. %s. %s." % [int(e.get("turn", 0)), who, outcome])
		rows.add_child(m)
	return col


## A threshold as the panels print it, with a true minus sign.
static func _n(v: float) -> String:
	return LabourState.signed_text(v)


func shot_views() -> Array:
	return [
		{"name": "quiet", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_NONE)
			LabourState.unrest.reset()
			LabourState.satisfaction = 12.0
			_confirming = ""
			_rebuild()},
		{"name": "warning", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_NONE)
			LabourState.unrest.reset()
			LabourState.satisfaction = -78.0
			var named: Array = LabourState.unrest.eligible_buildings().slice(0, 2)
			LabourState.unrest.warning = {"turn": LabourUnrest.next_check_turn(int(TurnManager.current_turn)),
				"buildings": named, "heavy": false, "light": named.size()}
			_confirming = ""
			_rebuild()},
		{"name": "warning_confirm", "setup": func() -> void:
			_confirming = "raise:all"
			_rebuild()},
		{"name": "warning_break", "setup": func() -> void:
			_confirming = "break:all"
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
