extends "res://scripts/upgrade_dialog.gd"
## The upgrade dialog in DS2 (docs/building-ledger-ds2-plan.md), opened from the ledger's Upgrade key while
## UiPrefs.use_ledger_ds2 is on. Everything the v2 dialog shows, laid out in the kit's parts; what the keys
## do is the v2 dialog's own code (_commit, _cancel, the preview), so the two can't disagree.
##
## On Building Detail's backing, top to bottom:
##   the head      the building's emblem, the raised title ("Upgrade Motor Factory A"), the level it goes
##                 from and to on a dot-matrix display, and the Close key
##   Materials     each good the next level takes in its well (the quantity on its pill), under it a lamp
##                 and what is on the tile of what is needed (green when enough, amber short), three to a
##                 row; on the right the Source dial (Order from market, first; Use materials on tile; Move
##                 materials from other tiles; each lit only where it can be done) and under it, when some must
##                 be bought, their price at market on an LED screen
##   Per turn      on a black plastic case, a row a thing, every row a good's height, led by its icon (a good
##                 in its well for what it makes and uses; the bolt, labour, upkeep and land hex in a cream
##                 outline): the figure at this level and the next in large print, the change, and a bar on the
##                 tile view's metering screen where this level is the same grey length in every row and the
##                 next level's step runs on from it (green where it helps, red where it costs) on one scale,
##                 so the rows that grow most run furthest; then a unit's cost to make, now and then
##   research      when the next level waits for research: the research icon, a red lamp, the research's
##                 name and a View Research key
##   land          the land hex and a lamp: what the larger building needs and what is free
##   the foot      the clock and how long it takes; the Upgrade and Cancel keys
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
const BoltIcon := preload("res://scripts/ds2/bolt_icon.gd")
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
## The icons that aren't goods stand in a cream outline a good's size, so every row is one height.
const OUTLINE_W := 2
const OUTLINE_RADIUS := 12
## The materials grid's columns, and the room it leaves on its right for the dial.
const MATERIAL_COLUMNS := 3
const NAVY := Color("#0b2340")
const DIAL_PX := 110.0

const WIDTH := 760.0
const CONTENT_MARGIN := 26
const BACKING_CORNER := 64.0
## The Per turn table's figure columns: now, the next level, the change.
const FIGURE_W := 84.0
## The change's dot-matrix screen: its cells ("+100%" and a space) and dot pitch; its column's width.
const CHANGE_CELLS := 5
const CHANGE_PITCH := 2.0
const CHANGE_W := 70.0
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


## The materials dial's options (_sources) and the one chosen, by index; -1 when none can be done.
var _options: Array = []
var _choice := -1


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
	_content.add_child(_materials(p))
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


## The materials dial: where the next level's materials come from, market first, each option lit only where it
## can be done. Sets _options and _choice.
func _dial(p: Dictionary) -> Control:
	_options = _sources(p)
	var dial: Control = Rotary.new()
	dial.name = "MaterialsDial"
	dial.set("knob_size", DIAL_PX)
	dial.set("label", "Source")
	dial.set("label_colour", DS.PALETTE["TEXT"])
	dial.set("options", _options)
	_choice = -1
	for i in _options.size():
		if bool(_options[i].enabled) and (_choice < 0 or str(_options[i].id) == "market"):
			_choice = i
	if _choice >= 0:
		dial.call("set_value_no_signal", _choice + 1)
	dial.connect("value_changed", func(v: int) -> void:
		if bool(_options[v - 1].enabled):
			_choice = v - 1
		elif _choice >= 0:
			dial.call("set_value_no_signal", _choice + 1))
	return dial


## The Upgrade and Cancel keys. Upgrade starts it the dial's way; it is greyed while research or land blocks
## it, or while no way of bringing the materials can be done.
func _foot(p: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "UpgradeKeys"
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 14)
	var blocked := bool(p.get("research_locked", false)) or not bool(p.get("fits", true)) or _choice < 0
	var up: Button = CreamKey.make("Key_Upgrade", "Upgrade", "", CreamKey.width_for("Upgrade", "", false, false))
	if blocked:
		up.call("set_spent", true)
	else:
		up.pressed.connect(func() -> void: _commit(str(_options[_choice].id)))
	row.add_child(up)
	var cancel: Button = CreamKey.make("Key_Cancel", "Cancel", "", CreamKey.width_for("Cancel", "", false, false))
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
func _materials(p: Dictionary) -> Control:
	var materials: Array = p.get("materials", [])
	var to_buy := float(p.get("market_cost", 0.0))
	var sec := _section("UpgradeMaterials", "Materials", "plate")
	# The crane over the source: its mast down the plate's right edge, its jib along the right half of the top.
	var crane := CraneRig.new()
	sec.add_child(crane)
	sec.move_child(crane, 0)
	var vb: VBoxContainer = sec.get("content")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	var grid := GridContainer.new()
	grid.name = "MaterialGrid"
	grid.columns = MATERIAL_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 12)
	row.add_child(grid)
	if materials.is_empty():
		grid.add_child(_body("No materials needed."))
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
		line.add_child(_lamp("ok" if have >= need else "warn"))
		line.add_child(_on_steel(_figure("%d/%d" % [mini(have, need), need])))
		cell.add_child(line)
		grid.add_child(cell)
	# On the right, under the crane's jib and clear of its mast: the dial, and under it what buying the rest
	# costs at market.
	var room := MarginContainer.new()
	room.name = "MaterialsSource"
	room.add_theme_constant_override("margin_right", roundi(CraneRig.MAST_W + 8.0))
	room.add_theme_constant_override("margin_top", roundi(CraneRig.JIB_H))
	room.add_theme_constant_override("margin_left", 0)
	room.add_theme_constant_override("margin_bottom", 0)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	room.add_child(side)
	var dial := _dial(p)
	dial.set("label_colour", NAVY)
	dial.set("option_ink", NAVY)
	side.add_child(dial)
	if to_buy > 0.0:
		var price := Parts.money("%.2f" % to_buy, DS.PALETTE["TEXT"], MONEY_DIGITS)
		price.name = "MarketPrice"
		price.tooltip_text = "Buying what is short at market"
		price.mouse_filter = Control.MOUSE_FILTER_PASS
		_on_steel(price.get_child(0) as Label)
		side.add_child(price)
	row.add_child(room)
	return sec


## Print on the light steel: navy, a faint light shadow under it (DS2's ink for light surfaces).
func _on_steel(l: Label) -> Label:
	l.add_theme_color_override("font_color", NAVY)
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## What changes a turn at the next level, on a black plastic case: a row a thing, led by its icon, its figures
## now and then, the change and a bar; then a unit's cost to make, now and then. Every bar starts from the
## same grey length (this level) on one scale, so the rows that grow most run furthest.
func _per_turn(from_level: int, target: int, unit_cost: Dictionary) -> Control:
	var sec := _section("UpgradePerTurn", "Per turn", "plastic")
	var vb: VBoxContainer = sec.get("content")
	vb.add_child(_table_head(from_level, target))
	var levels: Array = []
	for l in range(1, BuildingLevels.MAX_LEVEL + 1):
		levels.append(Production.stats_at_level(_instance_id, l))
	var now: Dictionary = levels[from_level - 1] if from_level - 1 < levels.size() else {}
	if now.is_empty():
		return sec
	# [node name, icon, values by level, decimals, unit, more is better]
	var specs: Array = []
	for i in (now.get("outputs", []) as Array).size():
		var gid := str(now.outputs[i].get("good_id", ""))
		var icon: Control = _outlined(BoltIcon.new(ROW_ICON_PX), "Power made, MW") if gid == "power" \
			else Parts.good_in_well(gid, -1, "%s made a turn" % Catalog.get_display_name(gid))
		specs.append(["Output_%s" % gid, icon, levels.map(func(st: Dictionary) -> float:
			return float((st.get("outputs", []) as Array)[i].get("qty", 0)) if i < (st.get("outputs", []) as Array).size() else 0.0),
			0, " MW" if gid == "power" else "", true])
	for i in (now.get("inputs", []) as Array).size():
		var gid := str(now.inputs[i].get("good_id", ""))
		specs.append(["Input_%s" % gid, Parts.good_in_well(gid, -1, "%s used a turn" % Catalog.get_display_name(gid)),
			levels.map(func(st: Dictionary) -> float:
				return float((st.get("inputs", []) as Array)[i].get("qty", 0)) if i < (st.get("inputs", []) as Array).size() else 0.0),
			0, "", true])
	if levels.any(func(st: Dictionary) -> bool: return float(st.get("energy", 0.0)) > 0.0):
		specs.append(["Power", _outlined(BoltIcon.new(ROW_ICON_PX), "Power drawn, MW"),
			levels.map(func(st: Dictionary) -> float: return float(st.get("energy", 0.0))), 0, " MW", false])
	specs.append(["Labour", _outlined(Parts.raised("econ_icon_labour", ROW_ICON_PX), "Labour a turn"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("labour", 0.0))), 2, "£", false])
	specs.append(["Upkeep", _outlined(Parts.raised("econ_icon_upkeep", ROW_ICON_PX), "Upkeep a turn"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("maintenance", 0.0))), 2, "£", false])
	specs.append(["Land", _outlined(LandIcon.new(ROW_ICON_PX), "Land the building takes"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("size", 0.0))), 0, "", false])
	# One scale for every bar: the most any row reaches at any level, against its figure now.
	var reach := 1.0
	for spec: Array in specs:
		var cur := float(spec[2][from_level - 1])
		if cur > 0.0:
			for v in spec[2]:
				reach = maxf(reach, float(v) / cur)
	for spec: Array in specs:
		vb.add_child(_track_row(str(spec[0]), spec[1], spec[2], from_level, target, int(spec[3]), str(spec[4]), bool(spec[5]), reach))
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


## An icon that isn't a good, in a cream outline with rounded corners a good's size, so it stands in the icon
## column as a good's well does.
func _outlined(icon: Control, tip: String) -> PanelContainer:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(Metrics.GOOD_ICON, Metrics.GOOD_ICON)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0)
	st.border_color = UIHelpers.PILL_PAPER
	st.set_border_width_all(OUTLINE_W)
	st.set_corner_radius_all(OUTLINE_RADIUS)
	box.add_theme_stylebox_override("panel", st)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(icon)
	box.add_child(center)
	box.tooltip_text = tip
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	return box


## The table's captions over its columns.
func _table_head(from_level: int, target: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Parts.spacer(float(Metrics.GOOD_ICON), 0))
	for c: Array in [["Lvl %d" % from_level, FIGURE_W], ["Lvl %d" % target, FIGURE_W]]:
		var l := Parts.caption(str(c[0]), Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_RIGHT)
		l.custom_minimum_size.x = float(c[1])
		row.add_child(l)
	var levels := Parts.caption("Change", Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
	levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(levels)
	row.add_child(Parts.spacer(CHANGE_W, 0))
	return row


## A row: the icon in the icon column, the figure now and at `target` in large print, the level bar and the
## change. A gain (`more_is_better`) lights green as it grows; a cost lights red.
func _track_row(row_name: String, icon: Control, values: Array, from_level: int, target: int, decimals: int, unit: String,
		more_is_better: bool, reach: float) -> HBoxContainer:
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
	row.custom_minimum_size.y = Metrics.GOOD_ICON
	row.add_theme_constant_override("separation", 12)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(Metrics.GOOD_ICON, Metrics.GOOD_ICON)
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
	track.reach = reach
	track.step_colour = Color("#3fb265") if tone == DS.PALETTE["OK"] else (Color("#b03026") if tone == DS.PALETTE["DANGER"] else Color("#8d949e"))
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(track)
	# The change on a dot-matrix screen, lit in the row's tone; a blank screen where nothing changes.
	var c: Control = DotMatrix.new()
	c.name = "Change"
	c.set("pitch", CHANGE_PITCH)
	c.set("align", HORIZONTAL_ALIGNMENT_RIGHT)
	c.set("colour", tone)
	c.set("text", change.lpad(CHANGE_CELLS))
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.tooltip_text = change
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(c)
	return row


## A framed section with its raised heading.
func _section(node_name: String, heading: String, style: String) -> MarginContainer:
	var sec: MarginContainer = Section.new()
	sec.name = node_name
	sec.set("style", style)
	var vb: VBoxContainer = sec.get("content")
	vb.add_theme_constant_override("separation", 10)
	# On the light steel plate the heading is printed navy; elsewhere it is raised white.
	vb.add_child(_on_steel(Parts.caption(heading, 18)) if style == "plate" else Parts.heading(heading))
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


## A figure's bar on the tile view's metering screens (the Power and Stock tabs' mini screen and glass): this
## level lit grey, always the same length (1 on a scale running to `reach`, shared by every row), the next
## level's step after it in `step_colour` (green where it helps, red where it costs), dark beyond; a notch
## where each level stands.
class LevelTrack extends Control:
	const Nine := preload("res://scripts/bdp_v3_nine.gd")
	const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
	const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
	const CAPTURE_SCALE := 1.875
	const MARGIN := 8.0
	const RIM := 7.0
	const RADIUS := 5.0
	const PANE := Color("#0b0d10")
	const BAR_H := 18.0
	const GREY := Color("#8d949e")
	var values: Array = []
	var now_level := 1
	var next_level := 2
	var reach := 1.0
	var step_colour := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(120, BAR_H + 4.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _slice(r: Rect2, c: Color) -> void:
		if r.size.x <= 0.0:
			return
		draw_rect(r, c)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(r.position + Vector2(0.0, r.size.y * 0.75), Vector2(r.size.x, r.size.y * 0.25)), Color(0, 0, 0, 0.18))

	func _draw() -> void:
		var bar := Rect2(Vector2(0.0, (size.y - BAR_H) * 0.5), Vector2(size.x, BAR_H))
		var corner := (MARGIN + RIM + RADIUS + 2.0) * 2.0 / CAPTURE_SCALE
		Nine.paint(self, SCREEN, bar.grow(MARGIN / CAPTURE_SCALE), corner)
		var pane := bar.grow(-RIM / CAPTURE_SCALE)
		draw_rect(pane, PANE)
		if values.size() >= next_level and float(values[now_level - 1]) > 0.0 and reach > 0.0:
			var cur := float(values[now_level - 1])
			var unit := pane.size.x / reach
			var x_now := unit
			var x_next := unit * float(values[next_level - 1]) / cur
			_slice(Rect2(pane.position, Vector2(minf(x_now, x_next), pane.size.y)), GREY)
			if x_next > x_now:
				_slice(Rect2(pane.position + Vector2(x_now, 0.0), Vector2(x_next - x_now, pane.size.y)), step_colour)
			elif x_next < x_now:
				_slice(Rect2(pane.position + Vector2(x_next, 0.0), Vector2(x_now - x_next, pane.size.y)), Color(step_colour, 0.6))
			for v in values:
				var x := roundf(pane.position.x + unit * float(v) / cur) + 0.5
				if x < pane.end.x - 1.0:
					draw_line(Vector2(x, pane.position.y), Vector2(x, pane.end.y), Color(0, 0, 0, 0.7), 1.0)
		Nine.paint(self, GLASS, bar.grow(MARGIN / CAPTURE_SCALE), corner)


## A crane of steel lattice over the materials plate's right: the mast down its right edge, the jib along the
## right half of its top, joined by a gusset at the corner. Drawn under the plate's contents.
class CraneRig extends Control:
	const MAST_W := 30.0
	const JIB_H := 26.0
	const CHORD := 7.0
	const STEEL := Color("#343940")
	const LIT := Color("#9aa2ab")
	const SHADE := Color("#111417")
	const BRACE := Color("#2b2f35")
	const RIVET := Color("#c9ced6")

	func _init() -> void:
		name = "CraneRig"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var mast := Rect2(size.x - MAST_W, 0.0, MAST_W, size.y)
		var jib := Rect2(size.x * 0.5, 0.0, size.x * 0.5 - MAST_W * 0.5, JIB_H)
		_truss(jib, true)
		_truss(mast, false)
		# The gusset where the jib meets the mast.
		var g := PackedVector2Array([Vector2(mast.position.x, JIB_H), Vector2(mast.position.x - JIB_H, JIB_H),
			Vector2(mast.position.x, JIB_H * 2.0)])
		draw_colored_polygon(g, STEEL)
		draw_polyline(PackedVector2Array([g[1], g[2]]), SHADE, 1.5, true)
		for p: Vector2 in [Vector2(mast.position.x - 5.0, JIB_H + 4.0), Vector2(mast.position.x - 3.0, JIB_H + 10.0)]:
			_rivet(p)

	## A lattice girder in `r`: two chords along its length with braces zigzagging between them.
	func _truss(r: Rect2, across: bool) -> void:
		var a: Rect2
		var b: Rect2
		if across:
			a = Rect2(r.position, Vector2(r.size.x, CHORD))
			b = Rect2(Vector2(r.position.x, r.end.y - CHORD), Vector2(r.size.x, CHORD))
		else:
			a = Rect2(r.position, Vector2(CHORD, r.size.y))
			b = Rect2(Vector2(r.end.x - CHORD, r.position.y), Vector2(CHORD, r.size.y))
		# The braces, a bay as long as the girder is deep.
		var depth := r.size.y if across else r.size.x
		var length := r.size.x if across else r.size.y
		var bays := maxi(1, roundi(length / depth))
		var step := length / bays
		for i in bays:
			var t0 := i * step
			var t1 := (i + 1) * step
			var p0: Vector2
			var p1: Vector2
			if across:
				p0 = Vector2(r.position.x + t0, a.end.y if i % 2 == 0 else b.position.y)
				p1 = Vector2(r.position.x + t1, b.position.y if i % 2 == 0 else a.end.y)
			else:
				p0 = Vector2(a.end.x if i % 2 == 0 else b.position.x, r.position.y + t0)
				p1 = Vector2(b.position.x if i % 2 == 0 else a.end.x, r.position.y + t1)
			draw_line(p0, p1, BRACE, 4.0, true)
			draw_line(p0 + Vector2(-0.5, -0.5), p1 + Vector2(-0.5, -0.5), Color(LIT, 0.35), 1.0, true)
		for chord: Rect2 in [a, b]:
			draw_rect(chord, STEEL)
			draw_rect(Rect2(chord.position, Vector2(chord.size.x, 1.0) if across else Vector2(1.0, chord.size.y)), LIT)
			var far := Rect2(Vector2(chord.position.x, chord.end.y - 1.0), Vector2(chord.size.x, 1.0)) if across \
				else Rect2(Vector2(chord.end.x - 1.0, chord.position.y), Vector2(1.0, chord.size.y))
			draw_rect(far, SHADE)
		for i in bays + 1:
			var t := i * step
			if across:
				_rivet(Vector2(r.position.x + t, a.get_center().y))
				_rivet(Vector2(r.position.x + t, b.get_center().y))
			else:
				_rivet(Vector2(a.get_center().x, r.position.y + t))
				_rivet(Vector2(b.get_center().x, r.position.y + t))

	func _rivet(p: Vector2) -> void:
		draw_circle(p + Vector2(0.5, 0.5), 1.8, SHADE)
		draw_circle(p, 1.6, RIVET)
