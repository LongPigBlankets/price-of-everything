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
##   Per turn      a row for each thing the level changes, led by its icon (a good in its well for what it
##                 makes and uses, the raised power, labour and upkeep icons, the land hex): the figure now
##                 and at the next level in large print, the change, and a bar on one linear scale across
##                 every level (1, 2, 3: 100%, 200%, 300% of a building whose figures double and treble), lit
##                 to now, the next level's step in green where it helps and red where it costs, a tick at
##                 each level; then a unit's cost to make, now and then, on LED screens
##   research      when the next level waits for research: the research icon, a red lamp, the research's
##                 name and a View Research key
##   land          the land hex and a lamp: what the larger building needs and what is free
##   the foot      the clock and how long it takes; the materials dial (Use materials on tile, Order from
##                 market, Move materials from other tiles, each lit only where it can be done, market first)
##                 beside the Upgrade and Cancel keys
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
const LandIcon := preload("res://scripts/ds2/land_icon.gd")
const Rotary := preload("res://scripts/rotary_selector.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const RESEARCH_ICON: Texture2D = preload("res://assets/icons/ui_icons/alt/research.png")
## The materials dial's options: [mode, icon, words], in the dial's order (market in the middle, first choice).
const SOURCES := [
	["tile", "res://assets/icons/ui_icons/ds2/source_this_tile.png", "Use materials on tile"],
	["market", "res://assets/icons/ui_icons/route_port.png", "Order from market"],
	["transfer", "res://assets/icons/ui_icons/ds2/source_other_tiles.png", "Move materials from other tiles"],
]
## The raised icons (Building Detail's) that lead the Per turn rows, their size, and the print of the rows'
## figures.
const ROW_ICON_PX := 44.0
const FIGURE_PX := 20
const TRACK_H := 16.0

const WIDTH := 760.0
const CONTENT_MARGIN := 26
const BACKING_CORNER := 64.0
## The Per turn table's figure columns: now, the next level, the change.
const FIGURE_W := 84.0
const CHANGE_W := 66.0
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
	_content.add_child(_per_turn(from_level, target, p.get("unit_cost", {})))
	if str(p.get("research_gate", "")) != "" and bool(p.get("research_locked", false)):
		_content.add_child(_research_line(str(p.get("research_gate", ""))))
	_content.add_child(_land_line(building, p))
	_content.add_child(_time_line(int(p.get("duration", 3)), from_level))
	_content.add_child(_foot(p))


## The materials dial's options with whether each can be done here: the kit all on the tile and unclaimed,
## a port route for what is short, a tile that can send what is short.
func _sources(p: Dictionary) -> Array:
	var on_tile := bool(p.get("all_on_tile", false))
	var free := bool(p.get("all_on_tile_free", on_tile))
	var src := str(p.get("source_tile", ""))
	var ok := {"tile": free, "market": bool(p.get("market_sourceable", true)), "transfer": src != ""}
	var out: Array = []
	for spec: Array in SOURCES:
		var words := str(spec[2])
		if str(spec[0]) == "transfer" and src != "":
			words = "Move materials from %s" % Catalog.tile_label(src)
		out.append({"id": str(spec[0]), "icon": load(str(spec[1])), "name": words, "enabled": bool(ok[str(spec[0])])})
	return out


## The dial, then the Upgrade and Cancel keys. Upgrade starts it the dial's way; it is greyed while research
## or land blocks it, or while no way of bringing the materials can be done.
func _foot(p: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UpgradeKeys"
	row.add_theme_constant_override("separation", 14)
	var options := _sources(p)
	var dial: Control = Rotary.new()
	dial.name = "MaterialsDial"
	dial.set("knob_size", 96.0)
	dial.set("label", "Materials")
	dial.set("label_colour", DS.PALETTE["TEXT"])
	dial.set("options", options)
	var first := -1
	for i in options.size():
		if bool(options[i].enabled) and (first < 0 or str(options[i].id) == "market"):
			first = i
	if first >= 0:
		dial.call("set_value_no_signal", first + 1)
	var chosen := [first]
	dial.connect("value_changed", func(v: int) -> void:
		if bool(options[v - 1].enabled):
			chosen[0] = v - 1
		elif chosen[0] >= 0:
			dial.call("set_value_no_signal", chosen[0] + 1))
	row.add_child(dial)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fill)
	var blocked := bool(p.get("research_locked", false)) or not bool(p.get("fits", true)) or first < 0
	var up: Button = CreamKey.make("Key_Upgrade", "Upgrade", "", CreamKey.width_for("Upgrade", "", false, false))
	up.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if blocked:
		up.call("set_spent", true)
	else:
		up.pressed.connect(func() -> void: _commit(str(options[chosen[0]].id)))
	row.add_child(up)
	var cancel: Button = CreamKey.make("Key_Cancel", "Cancel", "", CreamKey.width_for("Cancel", "", false, false))
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.pressed.connect(close)
	row.add_child(cancel)
	return row


## The research the next level waits for: its icon, a red lamp, its name and a key that opens it.
func _research_line(gate: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "ResearchLine"
	line.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = RESEARCH_ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ROW_ICON_PX, ROW_ICON_PX)
	line.add_child(icon)
	line.add_child(_lamp("bad"))
	var title := ResearchState.research_title_for_node_id(gate)
	var name := _figure(title if title != "" else gate)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(name)
	var view: Button = CreamKey.make("Key_ViewResearch", "View Research", "", CreamKey.width_for("View Research", "", false, false))
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	view.pressed.connect(func() -> void:
		close()
		MatchState.research_search_requested.emit(gate))
	line.add_child(view)
	return line


## The land the larger building needs against what is free on the tile (the ground left, and of it what you
## own), green when it fits.
func _land_line(building: Dictionary, p: Dictionary) -> HBoxContainer:
	var tile := str(building.get("tile_id", ""))
	var need := float(p.get("size_delta", 0.0))
	var free := minf(float(BuildingState.max_tile_land(tile)) - BuildingState.get_tile_space_used(tile),
		float(BuildingState.get_tile_land_owned(tile)) - BuildingState.get_tile_player_space_used(tile))
	free = maxf(0.0, free)
	var fits := bool(p.get("fits", true))
	var line := HBoxContainer.new()
	line.name = "LandLine"
	line.add_theme_constant_override("separation", 10)
	line.add_child(LandIcon.new(ROW_ICON_PX))
	line.add_child(_lamp("ok" if fits else "bad"))
	var words := ("Needs %s land. %s available." % [_land(need), _land(free)]) if fits \
		else "Need %s. Only %s available. Buy more or demolish other buildings to make room." % [_land(need), _land(free)]
	var said := _body(words)
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(said)
	return line


## The clock and how long the upgrade takes.
func _time_line(turns: int, from_level: int) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "TimeLine"
	line.add_theme_constant_override("separation", 10)
	line.add_child(Parts.raised("diag_icon_transit", ROW_ICON_PX))
	var said := _body("%s. Building continues producing at level %d until upgrade complete." % [_turns(turns), from_level])
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(said)
	return line


func _lamp(tone: String) -> Control:
	var lamp: Control = Lamp.new()
	lamp.set("lamp_scale", Parts.LAMP_SCALE)
	lamp.call("set_tone", tone)
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return lamp


func _land(v: float) -> String:
	return str(roundi(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


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


## What changes a turn at the next level: a row a thing, led by its icon, its figures now and then, the
## change and a bar across every level; then a unit's cost to make, now and then.
func _per_turn(from_level: int, target: int, unit_cost: Dictionary) -> Control:
	var sec := _section("UpgradePerTurn", "Per turn", "steel")
	var vb: VBoxContainer = sec.get("content")
	vb.add_child(_table_head(from_level, target))
	var levels: Array = []
	for l in range(1, BuildingLevels.MAX_LEVEL + 1):
		levels.append(Production.stats_at_level(_instance_id, l))
	var at := func(l: int) -> Dictionary: return levels[l - 1] if l - 1 < levels.size() else {}
	var now: Dictionary = at.call(from_level)
	if now.is_empty():
		return sec
	for i in (now.get("outputs", []) as Array).size():
		var gid := str(now.outputs[i].get("good_id", ""))
		var icon: Control = Parts.raised("bar_icon_power", ROW_ICON_PX) if gid == "power" \
			else Parts.good_in_well(gid, -1, "%s made a turn" % Catalog.get_display_name(gid))
		vb.add_child(_track_row("Output_%s" % gid, icon, levels.map(func(st: Dictionary) -> float:
			return float((st.get("outputs", []) as Array)[i].get("qty", 0)) if i < (st.get("outputs", []) as Array).size() else 0.0),
			from_level, target, 0, " MW" if gid == "power" else "", true))
	for i in (now.get("inputs", []) as Array).size():
		var gid := str(now.inputs[i].get("good_id", ""))
		vb.add_child(_track_row("Input_%s" % gid, Parts.good_in_well(gid, -1, "%s used a turn" % Catalog.get_display_name(gid)),
			levels.map(func(st: Dictionary) -> float:
				return float((st.get("inputs", []) as Array)[i].get("qty", 0)) if i < (st.get("inputs", []) as Array).size() else 0.0),
			from_level, target, 0, "", true))
	if levels.any(func(st: Dictionary) -> bool: return float(st.get("energy", 0.0)) > 0.0):
		vb.add_child(_track_row("Power", _tipped(Parts.raised("bar_icon_power", ROW_ICON_PX), "Power drawn, MW"),
			levels.map(func(st: Dictionary) -> float: return float(st.get("energy", 0.0))), from_level, target, 0, " MW", false))
	vb.add_child(_track_row("Labour", _tipped(Parts.raised("econ_icon_labour", ROW_ICON_PX), "Labour a turn"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("labour", 0.0))), from_level, target, 2, "£", false))
	vb.add_child(_track_row("Upkeep", _tipped(Parts.raised("econ_icon_upkeep", ROW_ICON_PX), "Upkeep a turn"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("maintenance", 0.0))), from_level, target, 2, "£", false))
	vb.add_child(_track_row("Land", _tipped(LandIcon.new(ROW_ICON_PX), "Land the building takes"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("size", 0.0))), from_level, target, 0, "", false))
	if unit_cost.has("cur") and unit_cost.has("new"):
		var cc := float(unit_cost.get("cur", 0.0))
		var cn := float(unit_cost.get("new", 0.0))
		var row := HBoxContainer.new()
		row.name = "UnitCost"
		row.add_theme_constant_override("separation", 10)
		var words := _figure("A unit's cost to make")
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		row.add_child(Parts.money("%.2f" % cc, DS.PALETTE["TEXT"], MONEY_DIGITS))
		row.add_child(Parts.caption("→", 18))
		row.add_child(Parts.money("%.2f" % cn, DS.PALETTE["OK"] if cn <= cc else DS.PALETTE["DANGER"], MONEY_DIGITS))
		vb.add_child(row)
	return sec


## The table's captions over its columns.
func _table_head(from_level: int, target: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Parts.spacer(float(Metrics.GOOD_ICON), 0))
	for c: Array in [["Lvl %d" % from_level, FIGURE_W], ["Lvl %d" % target, FIGURE_W]]:
		var l := Parts.caption(str(c[0]), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_RIGHT)
		l.custom_minimum_size.x = float(c[1])
		row.add_child(l)
	var levels := Parts.caption("Levels 1 to %d" % BuildingLevels.MAX_LEVEL, Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
	levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(levels)
	var change := Parts.caption("Change", Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_RIGHT)
	change.custom_minimum_size.x = CHANGE_W
	row.add_child(change)
	return row


## A row: the icon in the icon column, the figure now and at `target` in large print, the level bar and the
## change. A gain (`more_is_better`) lights green as it grows; a cost lights red.
func _track_row(row_name: String, icon: Control, values: Array, from_level: int, target: int, decimals: int, unit: String,
		more_is_better: bool) -> HBoxContainer:
	var cur := float(values[from_level - 1])
	var nxt := float(values[target - 1])
	var tone: Color = DS.PALETTE["TEXT"]
	var change := ""
	if cur > 0.0 and not is_equal_approx(cur, nxt):
		var pct := roundi((nxt / cur - 1.0) * 100.0)
		change = ("+%d%%" if pct > 0 else "%d%%") % pct
		tone = DS.PALETTE["OK"] if (nxt > cur) == more_is_better else DS.PALETTE["DANGER"]
	elif cur <= 0.0 and nxt > 0.0:
		change = "New"
		tone = DS.PALETTE["OK"] if more_is_better else DS.PALETTE["DANGER"]
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 12)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(float(Metrics.GOOD_ICON), float(Metrics.GOOD_ICON) if icon.custom_minimum_size.y >= Metrics.GOOD_ICON else ROW_ICON_PX + 8.0)
	box.add_child(icon)
	row.add_child(box)
	var money := unit == "£"
	for pair: Array in [["Now", cur, DS.PALETTE["TEXT"]], ["Next", nxt, tone]]:
		var text := ("£" if money else "") + _num(float(pair[1]), decimals) + ("" if money else unit)
		var f := _figure(text)
		f.name = str(pair[0])
		f.add_theme_font_size_override("font_size", FIGURE_PX)
		f.add_theme_color_override("font_color", pair[2])
		f.custom_minimum_size.x = FIGURE_W
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		f.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(f)
	var track := LevelTrack.new()
	track.values = values
	track.now_level = from_level
	track.next_level = target
	track.step_colour = tone
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(track)
	var c := _figure(change)
	c.name = "Change"
	c.add_theme_font_size_override("font_size", FIGURE_PX - 2)
	c.add_theme_color_override("font_color", tone)
	c.custom_minimum_size.x = CHANGE_W
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(c)
	return row


func _tipped(c: Control, tip: String) -> Control:
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


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


## A figure at every level on one linear scale, the largest level filling the bar: lit to the level now, the
## next level's step in `step_colour`, the rest dark, a tick where each level stands.
class LevelTrack extends Control:
	var values: Array = []
	var now_level := 1
	var next_level := 2
	var step_colour := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(120, TRACK_H)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var top := 0.0
		for v in values:
			top = maxf(top, float(v))
		var bar := Rect2(Vector2(0, 2), Vector2(size.x, size.y - 4))
		draw_rect(bar, Color(0, 0, 0, 0.45))
		draw_rect(bar, Color(1, 1, 1, 0.18), false, 1.0)
		if top <= 0.0 or values.size() < next_level:
			return
		var x_now := bar.size.x * float(values[now_level - 1]) / top
		var x_next := bar.size.x * float(values[next_level - 1]) / top
		draw_rect(Rect2(bar.position, Vector2(x_now, bar.size.y)), Color("#c9ced6"))
		if x_next > x_now:
			draw_rect(Rect2(bar.position + Vector2(x_now, 0), Vector2(x_next - x_now, bar.size.y)), step_colour)
		elif x_next < x_now:
			draw_rect(Rect2(bar.position + Vector2(x_next, 0), Vector2(x_now - x_next, bar.size.y)), Color(step_colour, 0.55))
		for v in values:
			var x := roundf(bar.size.x * float(v) / top)
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.85), 1.5)
