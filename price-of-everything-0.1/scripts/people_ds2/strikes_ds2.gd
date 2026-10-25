extends Control
## The People panel's Strikes tab in DS2 (docs/pacing-labour-mining-licensing-spec.md §6.3): the workforce's
## mood on a case (its band lamp, satisfaction, the next strike check and the union), then the warning board
## while strikers are named, each with what its strike would cost and a key to raise its pay, and a key to raise
## pay for all strikers. Then the buildings on strike, the record of past strikes, and how strikes work.
##
## The figures and the pay rises are LabourState.unrest's (scripts/labour_unrest.gd).

const Parts := preload("res://scripts/people_ds2/parts.gd")
const Kit := preload("res://scripts/ds2/parts.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const StatusLed := preload("res://scripts/status_led.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const LabourUnrest := preload("res://scripts/labour_unrest.gd")

const RAIL_ROOM := 24
const KEY_SCALE := 0.72
const NAME_W := 260.0
## The band lamp's colour: gold at +90, green from +50, cream steady, amber under −5, red under −70.
const BAND_LAMP := {"prize": Color("#f2c84b"), "fast": Color("#7ec98a"), "normal": Color("#e8dcc0"),
	"slow": Color("#e6b34a"), "strike": Color("#e2604a"), "strike_heavy": Color("#e2604a")}
const RECORD_SHOWN := 8

var _scroll: ScrollContainer
var _body: VBoxContainer
var _refresh_queued := false


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
	_body.add_child(_status())
	var u := LabourState.unrest
	if not u.warning.is_empty():
		_body.add_child(_warning_board())
	if not u.active.is_empty():
		_body.add_child(_on_strike())
	if not u.record.is_empty():
		_body.add_child(_record())
	_body.add_child(_how())


# --- status --------------------------------------------------------------------------------------

func _status() -> Control:
	var col := VBoxContainer.new()
	col.name = "StrikeStatus"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("Strikes"))
	var case := Kit.plastic_case("StrikeStatusCase")
	case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	rows.add_child(top)
	var band := LabourState.satisfaction_band()
	var lamp: Control = StatusLed.new()
	lamp.name = "BandLamp"
	lamp.set("lit", true)
	lamp.set("color", BAND_LAMP.get(band, BAND_LAMP.normal))
	var warned := not LabourState.unrest.warning.is_empty()
	lamp.ready.connect(func() -> void: lamp.set("blink", warned))   # its blink timer needs the tree
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(lamp)
	var mood := Parts.title("%s at %s" % [str(LabourState.band_summary().title), LabourState.signed_text(LabourState.satisfaction)])
	mood.name = "Mood"
	top.add_child(mood)
	var turn := int(TurnManager.current_turn)
	var u := LabourState.unrest
	var lines: PackedStringArray = []
	if LabourState.union_tier() != LabourState.UNION_NONE:
		lines.append("A union agreement is in force: the strike will be called off." if not u.warning.is_empty()
			else "A union agreement is in force: no strikes while it stands.")
	elif turn < u.strike_free_until:
		lines.append("Pay rises keep strikes away until turn %d." % u.strike_free_until)
	else:
		lines.append("Next strike check: turn %d." % LabourUnrest.next_check_turn(turn))
	if LabourState.satisfaction < LabourUnrest.HEAVY_STRIKE_BELOW:
		lines.append("Below %s, half your buildings can strike." % _n(LabourUnrest.HEAVY_STRIKE_BELOW))
	elif LabourState.satisfaction < LabourUnrest.STRIKE_BELOW:
		lines.append("Below %s, a quarter of your buildings can strike." % _n(LabourUnrest.STRIKE_BELOW))
	else:
		lines.append("No strikes while satisfaction stays at %s or above." % _n(LabourUnrest.STRIKE_BELOW))
	for line in lines:
		var l := Parts.body(line)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(l)
	col.set_meta("status", lines)
	return col


# --- the warning board ---------------------------------------------------------------------------

func _warning_board() -> Control:
	var u := LabourState.unrest
	var col := VBoxContainer.new()
	col.name = "WarningBoard"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("Strike warning: turn %d" % int(u.warning.get("turn", 0))))
	var case := Kit.plastic_case("WarningCase")
	case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 8)
	var what := Parts.body("Half output for %d turns. Inputs are still used and labour costs half." % LabourUnrest.STRIKE_TURNS)
	what.add_theme_color_override("font_color", DS.PALETTE["WARN"])
	rows.add_child(what)
	var total := 0.0
	for iid in u.warning.get("buildings", []):
		rows.add_child(_building_row(str(iid), "Expected loss", u.expected_loss(str(iid))))
		total += u.pay_raise_cost(str(iid))
	for iid in u.active:
		if not u.is_named(str(iid)):
			total += u.pay_raise_cost(str(iid))
	rows.add_child(_raise_all_row(total))
	return col


## One named or striking building: its name and tile, a figure, and "Raise pay here" with its cost.
func _building_row(iid: String, figure_caption: String, figure: float) -> Control:
	var u := LabourState.unrest
	var b := BuildingState.get_building(iid)
	var row := HBoxContainer.new()
	row.name = "Striker_%s" % iid
	row.add_theme_constant_override("separation", 14)
	var who := VBoxContainer.new()
	who.custom_minimum_size.x = NAME_W
	who.add_child(Parts.title(BuildingNaming.of(b) if not b.is_empty() else iid))
	var tile := Parts.body(Catalog.tile_name(str(b.get("tile_id", ""))) if not b.is_empty() else "")
	who.add_child(tile)
	row.add_child(who)
	var fig := VBoxContainer.new()
	fig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fig.add_child(Parts.body(figure_caption))
	fig.add_child(Parts.money(figure, Parts.RED))
	row.add_child(fig)
	var cost := u.pay_raise_cost(iid)
	var key: Button = CreamKey.make("RaisePay_%s" % iid, "Raise pay here", "£%s over %d turns" % [Parts.money_text(cost), LabourUnrest.PAY_RAISE_TURNS], 0.0, false, false, KEY_SCALE)
	key.custom_minimum_size.x = CreamKey.width_for("Raise pay here", "£%s over %d turns" % [Parts.money_text(cost), LabourUnrest.PAY_RAISE_TURNS], false, false, KEY_SCALE)
	key.tooltip_text = "Labour 20%% higher at this building for %d turns. Its workers go back to work." % LabourUnrest.PAY_RAISE_TURNS
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.pressed.connect(func() -> void:
		if LabourState.unrest.raise_pay(iid):
			MatchState.request_toast("Pay raised at %s." % (BuildingNaming.of(b) if not b.is_empty() else iid), "success"))
	row.add_child(key)
	row.set_meta("cost", cost)
	return row


func _raise_all_row(total: float) -> Control:
	var row := HBoxContainer.new()
	row.name = "RaiseAllRow"
	row.add_theme_constant_override("separation", 14)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(Parts.title("Raise pay for all strikers"))
	var l := Parts.body("Labour 20%% higher at each for %d turns. No strikes for %d turns." % [LabourUnrest.PAY_RAISE_TURNS, LabourUnrest.STRIKE_FREE_TURNS])
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(l)
	row.add_child(words)
	var detail := "£%s over %d turns" % [Parts.money_text(total), LabourUnrest.PAY_RAISE_TURNS]
	var key: Button = CreamKey.make("RaisePayAll", "Raise pay for all", detail, 0.0, false, false, KEY_SCALE)
	key.custom_minimum_size.x = CreamKey.width_for("Raise pay for all", detail, false, false, KEY_SCALE)
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.pressed.connect(func() -> void:
		if LabourState.unrest.raise_pay_all(int(TurnManager.current_turn)):
			MatchState.request_toast("Pay raised for all strikers. No strikes for %d turns." % LabourUnrest.STRIKE_FREE_TURNS, "success"))
	row.add_child(key)
	row.set_meta("total", total)
	return row


# --- on strike -----------------------------------------------------------------------------------

func _on_strike() -> Control:
	var u := LabourState.unrest
	var col := VBoxContainer.new()
	col.name = "OnStrike"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("On strike"))
	var case := Kit.plastic_case("OnStrikeCase")
	case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 8)
	var total := 0.0
	for iid in u.active:
		var left := u.strike_turns_left(str(iid))
		rows.add_child(_building_row(str(iid), "%d turn%s left" % [left, "" if left == 1 else "s"],
			u.output_value_per_turn(str(iid)) * (1.0 - LabourUnrest.STRIKE_OUTPUT_MULT) * float(left)))
		total += u.pay_raise_cost(str(iid))
	if u.warning.is_empty():
		rows.add_child(_raise_all_row(total))
	return col


# --- the record ----------------------------------------------------------------------------------

func _record() -> Control:
	var col := VBoxContainer.new()
	col.name = "StrikeRecord"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("Record"))
	var case := Kit.plastic_case("RecordCase")
	case.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(case)
	var rows: VBoxContainer = case.get_child(0)
	rows.add_theme_constant_override("separation", 6)
	var entries: Array = LabourState.unrest.record.duplicate()
	entries.reverse()
	for i in mini(RECORD_SHOWN, entries.size()):
		var e: Dictionary = entries[i]
		var names := PackedStringArray()
		for b: Dictionary in e.get("buildings", []):
			names.append(str(b.get("name", "")))
		var outcome := str(e.get("outcome", ""))
		var words := "Turn %d. %s. %s." % [int(e.get("turn", 0)), ", ".join(names) if not names.is_empty() else "Nobody",
			outcome.substr(0, 1).to_upper() + outcome.substr(1)]
		if outcome == "struck":
			words += " About £%s lost." % Parts.money_text(float(e.get("lost", 0.0)))
		var l := Parts.body(words)
		l.name = "RecordLine_%d" % i
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(l)
	return col


# --- how strikes work ----------------------------------------------------------------------------

func _how() -> Control:
	var col := VBoxContainer.new()
	col.name = "HowStrikesWork"
	col.add_theme_constant_override("separation", 10)
	col.add_child(Parts.heading("How strikes work"))
	for spec: Array in [
		["Every 10 turns", "Below %s a quarter of your buildings can strike, below %s half. You are warned 2 turns ahead." % [_n(LabourUnrest.STRIKE_BELOW), _n(LabourUnrest.HEAVY_STRIKE_BELOW)]],
		["A strike", "Half output for %d turns. Inputs are still used and labour costs half. Satisfaction rises 5 when it ends." % LabourUnrest.STRIKE_TURNS],
		["Stopping one", "Raise satisfaction above %s before the strike starts, raise pay, or sign a union agreement." % _n(LabourUnrest.STRIKE_BELOW)],
		["Accidents", "Under Minimal safety, mines, furnaces, power plants and chemical works can have accidents: 2 turns down and 2 turns of wages in compensation."],
	]:
		var card: Control = Kit.info(str(spec[0]), "", str(spec[1]))
		col.add_child(card)
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
			_rebuild()},
		{"name": "warning", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_NONE)
			LabourState.unrest.reset()
			LabourState.satisfaction = -78.0
			var named: Array = LabourState.unrest.eligible_buildings().slice(0, 2)
			LabourState.unrest.warning = {"turn": LabourUnrest.next_check_turn(int(TurnManager.current_turn)),
				"buildings": named, "heavy": false, "light": named.size()}
			_rebuild()},
		{"name": "on_strike", "setup": func() -> void:
			LabourState.set_union_tier(LabourState.UNION_NONE)
			LabourState.unrest.reset()
			LabourState.satisfaction = -84.0
			var named: Array = LabourState.unrest.eligible_buildings().slice(0, 2)
			for iid: String in named:
				LabourState.unrest.active[iid] = 2
			LabourState.unrest._add_record(10, named, "called off", 0.0)
			LabourState.unrest._add_record(20, named, "struck", 96.0)
			_rebuild()},
	]
