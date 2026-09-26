extends "res://scripts/upgrade_dialog.gd"
## The upgrade dialog in DS2 (docs/building-ledger-ds2-plan.md), opened from the ledger's Upgrade key while
## UiPrefs.use_ledger_ds2 is on. Everything the v2 dialog shows, laid out in the kit's parts; what the keys
## do is the v2 dialog's own code (_commit, _cancel, the preview), so the two can't disagree.
##
## On Building Detail's backing, top to bottom:
##   the head      the building's emblem, the raised title ("Upgrade Motor Factory A"), the level it goes
##                 from and to on a dot-matrix display, and the Close key
##   Materials     each good the next level takes in its well (the quantity on its pill), under it a lamp
##                 and what is on the tile of what is needed (green when enough, amber short); then, when
##                 some must be bought, their price at market on an LED screen
##   Per turn      what changes a turn, as a table: now, at the next level and the change (outputs and
##                 inputs, power drawn, labour, upkeep and land); then a unit's cost to make, now and then,
##                 on LED screens (green when it falls, red when it rises)
##   blockers      a red lamp and a line for research still needed or a tile without room
##   the foot      how long it takes, and the keys: Use materials on tile, Order from market, Use spare
##                 stockpile from a tile (each greyed when it can't), Cancel
## While an upgrade runs: an amber lamp, how long is left, and Cancel upgrade and Close. At the top level:
## a line saying so and Close.

const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")

const WIDTH := 760.0
const CONTENT_MARGIN := 26
const BACKING_CORNER := 64.0
## The Per turn table's figure columns: now, the next level, the change.
const FIGURE_W := 110.0
const CHANGE_W := 80.0
const MONEY_DIGITS := 6


func _build_shell() -> void:
	theme = DS.theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit_to_viewport()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_to_viewport):
		vp.size_changed.connect(_fit_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Color(0.0, 0.0, 0.0, 0.55)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_card = PanelContainer.new()
	_card.name = "UpgradeSheet"
	_card.custom_minimum_size = Vector2(WIDTH, 0)
	_card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	center.add_child(_card)
	var backing: Control = Nine.make("panel_backing", BACKING_CORNER)
	_card.add_child(backing)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, CONTENT_MARGIN)
	_card.add_child(margin)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	margin.add_child(_content)


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _rebuild() -> void:
	_clear()
	var p := _preview
	var building := BuildingState.get_building(_instance_id)
	var bname := str(p.get("building_name", "Building"))
	if not building.is_empty():
		bname = preload("res://scripts/building_naming.gd").label_for_tile(str(building.get("tile_id", "")), _instance_id,
			str(building.get("building_id", "")), str(building.get("recipe_id", "")))
	if p.is_empty() or not bool(p.get("ok", false)):
		_content.add_child(_head(str(building.get("building_id", "")), "Upgrade", ""))
		_content.add_child(_lamp_line("bad", str(p.get("reason", "It can't be upgraded."))))
		_content.add_child(_keys([["Close", close, false]]))
		return
	var from_level := int(p.get("from_level", 1))
	if bool(p.get("at_max", false)):
		_content.add_child(_head(str(building.get("building_id", "")), bname, "LEVEL %d OF %d" % [from_level, from_level]))
		_content.add_child(_lamp_line("ok", "At the top level."))
		_content.add_child(_keys([["Close", close, false]]))
		return
	var target := int(p.get("target_level", from_level + 1))
	_content.add_child(_head(str(building.get("building_id", "")), "Upgrade %s" % bname, "LEVEL %d → %d" % [from_level, target]))
	if bool(p.get("already_upgrading", false)):
		var left := int(p.get("pending_turns_left", 0))
		var waiting := str(p.get("pending_status", "")) == BuildingWorks.UPGRADE_STATUS_AWAITING
		var line := ("Waiting for materials, then %s." if waiting else "Level %d in %%s." % target) % _turns(left)
		_content.add_child(_lamp_line("warn", line))
		_content.add_child(_keys([["Cancel upgrade", func() -> void: _cancel(), false], ["Close", close, false]]))
		return
	_content.add_child(_materials(p.get("materials", []), float(p.get("market_cost", 0.0))))
	_content.add_child(_per_turn(target, p.get("stats", {}), p.get("unit_cost", {})))
	if bool(p.get("research_locked", false)):
		var gate := str(p.get("research_gate", ""))
		var title := ResearchState.research_title_for_node_id(gate)
		_content.add_child(_lamp_line("bad", "Needs research: %s." % (title if title != "" else gate)))
	if not bool(p.get("fits", true)):
		_content.add_child(_lamp_line("bad", str(p.get("fits_reason", "Not enough room on the tile for the larger building."))))
	_content.add_child(_body("Takes %s. The building keeps producing at level %d until then." % [
		_turns(int(p.get("duration", 3))), from_level]))
	_content.add_child(_keys(_actions(p)))


## The keys the v2 dialog offers, in its order: [words, action, greyed].
func _actions(p: Dictionary) -> Array:
	var blocked := bool(p.get("research_locked", false)) or not bool(p.get("fits", true))
	var on_tile := bool(p.get("all_on_tile", false))
	var free := bool(p.get("all_on_tile_free", on_tile))
	var keys: Array = [["Materials on tile are claimed" if on_tile and not free else "Use materials on tile",
		func() -> void: _commit("tile"), blocked or not free]]
	if not free:
		var sourceable := bool(p.get("market_sourceable", true))
		keys.append(["Order from market" if sourceable else "No market route for some",
			func() -> void: _commit("market"), blocked or not sourceable])
		var src := str(p.get("source_tile", ""))
		if src != "":
			keys.append(["Use stock from %s" % Catalog.tile_label(src), func() -> void: _commit("transfer"), blocked])
	keys.append(["Cancel", close, false])
	return keys


# --- parts -------------------------------------------------------------------------------------

## The emblem, the raised title and the level on a dot display, and the Close key.
func _head(building_id: String, title_text: String, level_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UpgradeHead"
	row.add_theme_constant_override("separation", 14)
	row.add_child(Parts.emblem(building_id, Parts.EMBLEM_PX))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)
	var title: Control = Title.new()
	title.call("set_text", title_text)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(title)
	if level_text != "":
		var level: Control = DotMatrix.new()
		level.name = "LevelDisplay"
		level.set("pitch", 2.0)
		level.set("text", level_text)
		level.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(level)
	var close_key: TextureButton = Key.make("close", Title.line_height())
	close_key.name = "CloseKey"
	close_key.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_key.pressed.connect(close)
	row.add_child(close_key)
	return row


## Each material in its well with what is needed on its pill, under it what the tile holds of it; the
## price of what must be bought.
func _materials(materials: Array, to_buy: float) -> Control:
	var sec := _section("UpgradeMaterials", "Materials", "dark")
	var vb: VBoxContainer = sec.get("content")
	if materials.is_empty():
		vb.add_child(_body("No materials needed."))
		return sec
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 12)
	vb.add_child(flow)
	for m: Dictionary in materials:
		var gid := str(m.get("good_id", ""))
		var need := int(m.get("need", 0))
		var have := int(m.get("have", 0))
		var cell := VBoxContainer.new()
		cell.name = "Material_%s" % gid
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(Parts.good_in_well(gid, need, "%s: %d needed, %d on the tile" % [Catalog.get_display_name(gid), need, have]))
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", Parts.LAMP_GAP)
		var lamp: Control = Lamp.new()
		lamp.set("lamp_scale", Parts.LAMP_SCALE)
		lamp.call("set_tone", "ok" if have >= need else "warn")
		line.add_child(lamp)
		var said := _figure("%d/%d" % [mini(have, need), need])
		line.add_child(said)
		cell.add_child(line)
		flow.add_child(cell)
	if to_buy > 0.0:
		var row := HBoxContainer.new()
		row.name = "MarketPrice"
		row.add_theme_constant_override("separation", 10)
		var words := _body("The rest at market")
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		row.add_child(Parts.money("%.2f" % to_buy, DS.PALETTE["TEXT"], MONEY_DIGITS))
		vb.add_child(row)
	return sec


## What changes a turn at the next level, now against then, and a unit's cost to make.
func _per_turn(target: int, stats: Dictionary, unit_cost: Dictionary) -> Control:
	var sec := _section("UpgradePerTurn", "Per turn", "steel")
	var vb: VBoxContainer = sec.get("content")
	var head := _table_row("", "Now", "Level %d" % target, "Change", true)
	vb.add_child(head)
	var cur: Dictionary = stats.get("cur", {})
	var new_s: Dictionary = stats.get("new", {})
	if not cur.is_empty() and not new_s.is_empty():
		var cur_out: Array = cur.get("outputs", [])
		var new_out: Array = new_s.get("outputs", [])
		for i in mini(cur_out.size(), new_out.size()):
			vb.add_child(_delta("Makes %s" % str(cur_out[i].get("name", "")), float(cur_out[i].get("qty", 0)), float(new_out[i].get("qty", 0)), 0, "", true))
		var cur_in: Array = cur.get("inputs", [])
		var new_in: Array = new_s.get("inputs", [])
		for i in mini(cur_in.size(), new_in.size()):
			vb.add_child(_delta("Uses %s" % str(cur_in[i].get("name", "")), float(cur_in[i].get("qty", 0)), float(new_in[i].get("qty", 0)), 0, "", true))
		if float(cur.get("energy", 0)) > 0.0 or float(new_s.get("energy", 0)) > 0.0:
			vb.add_child(_delta("Power drawn, MW", float(cur.get("energy", 0)), float(new_s.get("energy", 0)), 1, "", false))
		vb.add_child(_delta("Labour", float(cur.get("labour", 0.0)), float(new_s.get("labour", 0.0)), 2, "£", false))
		vb.add_child(_delta("Upkeep", float(cur.get("maintenance", 0.0)), float(new_s.get("maintenance", 0.0)), 2, "£", false))
		vb.add_child(_delta("Land", float(cur.get("size", 1.0)), float(new_s.get("size", 1.0)), 0, "", false))
	if unit_cost.has("cur") and unit_cost.has("new"):
		var cc := float(unit_cost.get("cur", 0.0))
		var cn := float(unit_cost.get("new", 0.0))
		var row := HBoxContainer.new()
		row.name = "UnitCost"
		row.add_theme_constant_override("separation", 10)
		var words := _body("A unit's cost to make")
		words.add_theme_font_override("font", Parts.FONT_TITLE)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		row.add_child(Parts.money("%.2f" % cc, DS.PALETTE["TEXT"], MONEY_DIGITS))
		row.add_child(Parts.caption("→", 18))
		row.add_child(Parts.money("%.2f" % cn, DS.PALETTE["OK"] if cn <= cc else DS.PALETTE["DANGER"], MONEY_DIGITS))
		vb.add_child(row)
	return sec


## A row of the Per turn table: a gain (`more_is_better`) lights its change green when it grows; a cost lights
## it red.
func _delta(label: String, cur: float, new_v: float, decimals: int, prefix: String, more_is_better: bool) -> HBoxContainer:
	var change := ""
	var tone := DS.PALETTE["TEXT"]
	if cur > 0.0 and not is_equal_approx(cur, new_v):
		var pct := roundi((new_v / cur - 1.0) * 100.0)
		change = ("+%d%%" if pct > 0 else "%d%%") % pct
		tone = DS.PALETTE["OK"] if (new_v > cur) == more_is_better else DS.PALETTE["DANGER"]
	elif cur <= 0.0 and new_v > 0.0:
		change = "New"
		tone = DS.PALETTE["OK"] if more_is_better else DS.PALETTE["DANGER"]
	var row := _table_row(label, prefix + _num(cur, decimals), prefix + _num(new_v, decimals), change, false)
	(row.get_node("Change") as Label).add_theme_color_override("font_color", tone)
	(row.get_node("Next") as Label).add_theme_color_override("font_color", tone if change != "" else DS.PALETTE["TEXT"])
	return row


func _table_row(label: String, now: String, next: String, change: String, heading: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cells := [["Label", label, 0.0], ["Now", now, FIGURE_W], ["Next", next, FIGURE_W], ["Change", change, CHANGE_W]]
	for c: Array in cells:
		var l: Label = Parts.caption(str(c[1]), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_RIGHT) if heading else _figure(str(c[1]))
		l.name = str(c[0])
		if float(c[2]) > 0.0:
			l.custom_minimum_size.x = float(c[2])
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			if not heading:
				l.add_theme_font_override("font", Parts.FONT_BODY)
		row.add_child(l)
	return row


## A framed section with its raised heading.
func _section(node_name: String, heading: String, style: String) -> MarginContainer:
	var sec: MarginContainer = Section.new()
	sec.name = node_name
	sec.set("style", style)
	var vb: VBoxContainer = sec.get("content")
	vb.add_theme_constant_override("separation", 10)
	vb.add_child(Parts.heading(heading))
	return sec


## A lamp in `tone` and a line.
func _lamp_line(tone: String, text: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", Parts.LAMP_GAP)
	var lamp: Control = Lamp.new()
	lamp.set("lamp_scale", Parts.LAMP_SCALE)
	lamp.call("set_tone", tone)
	line.add_child(lamp)
	var l := _body(text)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(l)
	return line


## The cabinet's cream keys in a row, each as wide as its words; a greyed one can't be pressed.
func _keys(specs: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UpgradeKeys"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	for spec: Array in specs:
		var words := str(spec[0])
		var key: Button = CreamKey.make("Key_%s" % words.to_pascal_case(), words, "", CreamKey.width_for(words, "", false, false))
		if bool(spec[2]):
			key.call("set_spent", true)
		else:
			key.pressed.connect(spec[1])
		row.add_child(key)
	return row


func _body(text: String) -> Label:
	var l := Parts.body(text)
	l.custom_minimum_size.x = 0
	return l


## A figure: semibold body print, one line.
func _figure(text: String) -> Label:
	var l := Parts.body(text)
	l.add_theme_font_override("font", Parts.FONT_TITLE)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size.x = 0
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return l


func _num(v: float, decimals: int) -> String:
	return str(roundi(v)) if decimals <= 0 else ("%." + str(decimals) + "f") % v


func _turns(n: int) -> String:
	return "%d turn%s" % [n, "" if n == 1 else "s"]
