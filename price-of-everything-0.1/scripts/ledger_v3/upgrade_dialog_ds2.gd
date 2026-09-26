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
## Each is a BuildingWorks.start_upgrade mode: tile_wait waits for what is missing to reach the tile, market buys
## it, stockpiles moves every other tile's spare stock over; the two stockpile modes never buy what is missing.
const SOURCES := [
	["tile_wait", "res://assets/icons/ui_icons/ds2/source_this_tile.png", "This tile's stockpile"],
	["market", "res://assets/icons/ui_icons/route_port.png", "Order from market"],
	["stockpiles", "res://assets/icons/ui_icons/ds2/source_other_tiles.png", "All tile stockpiles"],
]
const NO_MARKET_NOTE := "Missing materials will not be bought from market."
## The raised icons (Building Detail's) that lead the Per turn rows, their size, and the print of the rows'
## figures.
const ROW_ICON_PX := 36.0
## The Per turn table: the icons that aren't goods, drawn as close to this square as their art allows; the
## rows they head; three outputs' goods, two over one.
const METRIC_ICON_PX := 54.0
const METRIC_ROW_H := 60.0
const OUTPUT_SMALL := 60
## The research, land and time lines' height.
const INFO_ROW_H := 40.0
## The estimates' rows, and the room kept at the impact case's side for its scroll rail.
const ESTIMATE_ROW_H := 54.0
const RAIL_ROOM := 20
## The See more key's width.
const FOLD_W := 200.0
const FIGURE_PX := 20
## The icons that aren't goods stand in a cream outline a good's size, so every row is one height.
const OUTLINE_W := 2
const OUTLINE_RADIUS := 12
## The materials grid's columns, and the room it leaves on its right for the dial.
const MATERIAL_COLUMNS := 3
const MATERIAL_CELL_GAP := 6
const NAVY := Color("#0b2340")
## The total's rule and label on the plastic.
const CREAM := Color("#f3e3bd")
## The embossed icons on the dial's black plastic plates.
const OFF_WHITE := Color("#ece6d6")
const DIAL_PX := 165.0
## How much nearer the crane the dial stands than its column would put it.
const DIAL_SHIFT := 30.0
## The dial's name this far under its ring; the price's foot level with the foot of the lowest materials' frames.
const SOURCE_GAP := 10.0

const WIDTH := 780.0
const CONTENT_MARGIN := 18
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
	_content.add_theme_constant_override("separation", 8)
	margin.add_child(_content)


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


## The materials dial's options (_sources) and the one chosen, by index; -1 when none can be done.
var _options: Array = []
var _choice := -1
## The Materials plate's price screen (its hover the breakdown) and its no-buy note, which follow the dial.
var _price: Control = null
var _note: Label = null
## Whether See more is open, kept while the panel is rebuilt.
var _detail_open := false


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
	_content.add_child(_impact(from_level, target))
	if str(p.get("research_gate", "")) != "" and bool(p.get("research_locked", false)):
		_content.add_child(_research_line(str(p.get("research_gate", ""))))
	_content.add_child(_land_line(building, p))
	var time := _time_line(int(p.get("duration", 3)), from_level)
	time.add_child(_foot(p))
	_content.add_child(time)


## The materials dial's options with whether each can be done here: the kit all on the tile and unclaimed,
## a port route for what is short, a tile that can send what is short.
func _sources(p: Dictionary) -> Array:
	var any_here := false
	var short := false
	for m: Dictionary in p.get("materials", []):
		any_here = any_here or int(m.get("have", 0)) > 0
		short = short or int(m.get("short", 0)) > 0
	var plan: Dictionary = p.get("stockpile_plan", {})
	var ok := {"tile_wait": any_here or not short, "market": bool(p.get("market_sourceable", true)),
		"stockpiles": not short or not (plan.get("from_tiles", []) as Array).is_empty()}
	var out: Array = []
	for spec: Array in SOURCES:
		out.append({"id": str(spec[0]), "icon": load(str(spec[1])), "name": str(spec[2]), "enabled": bool(ok[str(spec[0])])})
	return out


## What the chosen source costs: the market's goods and freight, the stockpiles' freight, or nothing (a
## building's upgrade has no fee; its price is its materials). {total, lines: [[words, figure]]}.
func _source_cost(p: Dictionary, mode: String) -> Dictionary:
	var lines: Array = []
	var total := 0.0
	match mode:
		"market":
			for l: Dictionary in p.get("market_lines", []):
				var name := "%d %s" % [int(l.qty), Catalog.get_display_name(str(l.good_id))]
				lines.append([name, float(l.goods)])
				lines.append(["  Transport", float(l.transport)])
				total += float(l.goods) + float(l.transport)
		"stockpiles":
			var plan: Dictionary = p.get("stockpile_plan", {})
			for move: Dictionary in plan.get("from_tiles", []):
				var parts: PackedStringArray = []
				for gid in move.goods:
					parts.append("%d %s" % [int(move.goods[gid]), Catalog.get_display_name(str(gid))])
				lines.append(["From %s: %s" % [Catalog.tile_name(str(move.tile_id)) if Catalog.tile_name(str(move.tile_id)) != "" \
					else Catalog.tile_label(str(move.tile_id)), ", ".join(parts)], float(move.transport)])
				total += float(move.transport)
			for gid in (plan.get("left", {}) as Dictionary):
				lines.append(["%d %s not found, not bought" % [int(plan.left[gid]), Catalog.get_display_name(str(gid))], 0.0])
	if lines.is_empty():
		lines.append(["Nothing to pay: the materials come from this tile", 0.0])
	return {"total": total, "lines": lines}


## The materials dial: where the next level's materials come from, market first, each option lit only where it
## can be done. Sets _options and _choice.
func _dial(p: Dictionary) -> Control:
	_options = _sources(p)
	var dial: Control = Rotary.new()
	dial.name = "MaterialsDial"
	dial.set("knob_size", DIAL_PX)
	dial.set("option_plates", true)
	dial.set("label_gap", SOURCE_GAP)
	dial.set("option_scale", 1.2)
	dial.set("option_ink", OFF_WHITE)
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
			_show_source(p)
		elif _choice >= 0:
			dial.call("set_value_no_signal", _choice + 1))
	return dial


## The price screen, its breakdown and the no-buy note follow the dial.
func _show_source(p: Dictionary) -> void:
	var mode := str(_options[_choice].id) if _choice >= 0 else "market"
	var cost := _source_cost(p, mode)
	if _price != null and is_instance_valid(_price):
		var led: Control = _price.find_child("Led", true, false)
		if led != null:
			var figure := "%.2f" % float(cost.total)
			led.call("set_figure", " ".repeat(maxi(0, MONEY_DIGITS - preload("res://scripts/bdp_v3_led.gd").cells_for(figure).size())) + figure, DS.PALETTE["TEXT"])
		_price.set("breakdown", cost)
		_price.tooltip_text = str(_options[_choice].name) if _choice >= 0 else ""
	if _note != null and is_instance_valid(_note):
		_note.visible = mode == "tile_wait" or mode == "stockpiles"


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
	line.custom_minimum_size.y = INFO_ROW_H
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
	var k := minf(1.0, INFO_ROW_H / CreamKey.height_for(1.0))
	var view: Button = CreamKey.make("Key_ViewResearch", "View Research", "", CreamKey.width_for("View Research", "", false, false, k), false, false, k)
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
	line.custom_minimum_size.y = INFO_ROW_H
	line.add_theme_constant_override("separation", 10)
	line.add_child(LandIcon.new(ROW_ICON_PX))
	line.add_child(_lamp("ok" if fits else "bad"))
	# The land free against the land the larger building needs; the hover says what that means and, short of
	# room, what to do.
	var said := _body("%s/%s available" % [_land(free), _land(need)])
	said.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	said.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(said)
	line.tooltip_text = ("The larger building needs %s more land and %s is free." % [_land(need), _land(free)]) \
		+ ("" if fits else " Demolish other buildings to make room.")
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	return line


## The clock and how long the upgrade takes.
func _time_line(turns: int, from_level: int) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.name = "TimeLine"
	line.custom_minimum_size.y = INFO_ROW_H
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
	# The plate and, over it, the crane standing on its edges: the mast down the right edge, the jib along the
	# right half of the top (a wrapper, so the crane may lie on the plate's edge and not inside its margins).
	var wrap := PanelContainer.new()
	wrap.name = "MaterialsPlate"
	wrap.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	wrap.add_child(sec)
	wrap.add_child(CraneRig.new())
	var vb: VBoxContainer = sec.get("content")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
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
		cell.add_theme_constant_override("separation", MATERIAL_CELL_GAP)
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
	# The section's content starts CASE_INSET in from the plate's edge; the crane's mast and cab take more.
	room.add_theme_constant_override("margin_right", roundi(CraneRig.MAST_W + CraneRig.CAB.x + 10.0 - (Section.RIM + Section.PADDING) - DIAL_SHIFT))
	room.add_theme_constant_override("margin_top", 8)
	room.add_theme_constant_override("margin_left", 0)
	room.add_theme_constant_override("margin_bottom", 0)
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	room.add_child(side)
	var dial := _dial(p)
	dial.set("label_colour", NAVY)
	side.add_child(dial)
	# Between the materials and the dial: what the chosen source costs, its breakdown on hover.
	var money := Parts.money("%.2f" % to_buy, DS.PALETTE["TEXT"], MONEY_DIGITS)
	var price := PriceBox.new()
	price.name = "SourcePrice"
	price.alignment = BoxContainer.ALIGNMENT_CENTER
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.add_theme_constant_override("separation", 4)
	price.mouse_filter = Control.MOUSE_FILTER_STOP
	for part in money.get_children():
		money.remove_child(part)
		price.add_child(part)
	money.free()
	_on_steel(price.get_child(0) as Label)
	var price_room := MarginContainer.new()
	price_room.name = "PriceRoom"
	price_room.size_flags_vertical = Control.SIZE_SHRINK_END
	for edge in ["margin_left", "margin_right", "margin_top"]:
		price_room.add_theme_constant_override(edge, 0)
	# A material's cell is its icon, a gap and its count; the well's frame reaches below the icon. The price
	# stands so its foot meets the frame's.
	price_room.add_theme_constant_override("margin_bottom", roundi(MATERIAL_CELL_GAP + _figure("0/0").get_combined_minimum_size().y - Parts.WELL_REACH))
	price_room.add_child(price)
	row.add_child(price_room)
	_price = price
	row.add_child(room)
	_note = _on_steel(_body(NO_MARKET_NOTE))
	_note.name = "NoMarketNote"
	vb.add_child(_note)
	_show_source(p)
	return wrap


## The breakdown of what the source costs, on the dark metal plate the other hovers use, off-white print: a line a good (or a tile it comes from) with its
## figure, then the total. `cost` is _source_cost's.
static func breakdown_plate(cost: Dictionary) -> Control:
	var host := TipHost.new()
	var plate: MarginContainer = Section.new()
	plate.set("style", "slab")
	host.add_child(plate)
	var vb: VBoxContainer = plate.get("content")
	vb.add_theme_constant_override("separation", 6)
	vb.add_child(Parts.caption("Cost of the materials", 16))
	for line: Array in cost.get("lines", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		var words := Parts.body(str(line[0]))
		words.autowrap_mode = TextServer.AUTOWRAP_OFF
		words.custom_minimum_size.x = 0
		row.add_child(words)
		var fig := Parts.body("£%.2f" % float(line[1]))
		fig.autowrap_mode = TextServer.AUTOWRAP_OFF
		fig.custom_minimum_size.x = 80
		fig.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(fig)
		vb.add_child(row)
	var total := HBoxContainer.new()
	var tw := Parts.caption("Total", 16)
	tw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total.add_child(tw)
	total.add_child(Parts.caption("£%.2f" % float(cost.get("total", 0.0)), 16, HORIZONTAL_ALIGNMENT_RIGHT))
	vb.add_child(total)
	return host


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
## Estimated impact, on a black plastic case: a unit's cost, the costs and the output's value a turn at this
## level and the next on LED screens, always shown; See more opens the Per turn rows under them, and the case,
## which keeps its closed height, scrolls on the rail kept at its side.
func _impact(from_level: int, target: int) -> Control:
	var levels: Array = []
	for l in range(1, BuildingLevels.MAX_LEVEL + 1):
		levels.append(Production.stats_at_level(_instance_id, l))
	var sec: MarginContainer = Section.new()
	sec.name = "UpgradePerTurn"
	sec.set("style", "plastic")
	var vb: VBoxContainer = sec.get("content")
	vb.add_theme_constant_override("separation", 6)
	var est := _estimates(levels)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	for lvl in [from_level, target]:
		var c := Parts.caption("Lvl %d" % lvl, Parts.CAPTION_PX, HORIZONTAL_ALIGNMENT_CENTER)
		c.custom_minimum_size.x = Parts.money_width(MONEY_DIGITS)
		head.add_child(c)
	vb.add_child(head)
	for spec: Array in [["Estimated Cost Increase", "cost", false], ["Estimated Cost per Unit", "unit", false],
			["Estimated Value of Output", "value", true], ["Estimated Net Value Add", "net", true]]:
		var total := str(spec[1]) == "net"
		if total:
			# The net is the total: a cream rule over it, as a ledger rules off its sum.
			vb.add_child(TotalRule.new())
		var row := _estimate_row(str(spec[0]), est[spec[1]], from_level, target, bool(spec[2]))
		if total:
			(row.get_child(0) as Label).add_theme_color_override("font_color", CREAM)
		vb.add_child(row)
	var detail := VBoxContainer.new()
	detail.name = "PerTurnRows"
	detail.add_theme_constant_override("separation", 10)
	detail.visible = _detail_open
	var fold := load("res://scripts/tvp_v3/goods_parts.gd").fold_button("See more", 0.8, "SeeMore", _detail_open,
		func(open: bool) -> void:
			_detail_open = open
			detail.visible = open) as Button
	fold.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fold.custom_minimum_size.x = FOLD_W
	vb.add_child(fold)
	vb.add_child(detail)
	_per_turn_rows(detail, levels, from_level, target)
	# The case in a scroll that keeps the closed case's height, the rail's room kept at its side always.
	var room := MarginContainer.new()
	room.add_theme_constant_override("margin_right", RAIL_ROOM)
	room.add_child(sec)
	var scroll := ScrollContainer.new()
	scroll.name = "ImpactScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preload("res://scripts/bdp_v3_scroll.gd").apply(scroll, true)
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(room)
	var fit := func() -> void:
		var was := detail.visible
		detail.visible = false
		scroll.custom_minimum_size.y = room.get_combined_minimum_size().y
		detail.visible = was
	scroll.ready.connect(fit, CONNECT_DEFERRED)
	return scroll


## The estimates at every level: {cost, unit, value, net: [by level]}, net the value less the costs. Costs a turn are the inputs at market,
## power at the grid's price, labour and upkeep; the value is the outputs at market (power at the grid's price
## for selling); a unit's cost is those costs over the first output, so the three agree.
func _estimates(levels: Array) -> Dictionary:
	var cost: Array = []
	var value: Array = []
	var unit: Array = []
	for st: Dictionary in levels:
		var c := float(st.get("energy", 0.0)) * EconomyConfig.GRID_BUY_PRICE + float(st.get("labour", 0.0)) + float(st.get("maintenance", 0.0))
		for i: Dictionary in st.get("inputs", []):
			c += float(i.get("qty", 0)) * MarketState.get_price(str(i.get("good_id", "")))
		var v := 0.0
		for o: Dictionary in st.get("outputs", []):
			var gid := str(o.get("good_id", ""))
			v += float(o.get("qty", 0)) * (EconomyConfig.GRID_SELL_PRICE if gid == "power" else MarketState.get_price(gid))
		var outs: Array = st.get("outputs", [])
		var first := float(outs[0].get("qty", 0)) if not outs.is_empty() else 0.0
		cost.append(c)
		value.append(v)
		unit.append(c / first if first > 0.0 else 0.0)
	var net: Array = []
	for i in value.size():
		net.append(float(value[i]) - float(cost[i]))
	return {"cost": cost, "value": value, "unit": unit, "net": net}


## An estimate's row, a good's icon tall at the least: its name, and its figure at this level and the next on
## LED screens, the next lit green where it helps and red where it costs.
func _estimate_row(label: String, values: Array, from_level: int, target: int, more_is_better: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = label.to_pascal_case()
	row.custom_minimum_size.y = ESTIMATE_ROW_H
	row.add_theme_constant_override("separation", 12)
	var name := _figure(label)
	name.add_theme_font_size_override("font_size", 16)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name)
	var cur := float(values[from_level - 1])
	var nxt := float(values[target - 1])
	var tone: Color = DS.PALETTE["TEXT"]
	if not is_equal_approx(cur, nxt):
		tone = DS.PALETTE["OK"] if (nxt > cur) == more_is_better else DS.PALETTE["DANGER"]
	for pair: Array in [[cur, DS.PALETTE["TEXT"]], [nxt, tone]]:
		var m := Parts.money("%.2f" % float(pair[0]), pair[1], MONEY_DIGITS)
		m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(m)
	return row


## The Per turn rows, under See more: the table's captions, then a row a thing.
func _per_turn_rows(vb: VBoxContainer, levels: Array, from_level: int, target: int) -> void:
	var now: Dictionary = levels[from_level - 1] if from_level - 1 < levels.size() else {}
	if now.is_empty():
		return
	var outputs: Array = now.get("outputs", [])
	var cluster := _output_cluster(outputs)
	_icon_col = maxf(float(METRIC_ICON_PX), cluster.get_combined_minimum_size().x)
	vb.add_child(_table_head(from_level, target))
	var per_level := func(key: String, i: int) -> Array:
		return levels.map(func(st: Dictionary) -> float:
			var list: Array = st.get(key, [])
			return float(list[i].get("qty", 0)) if i < list.size() else 0.0)
	# [node name, icon, values by level, decimals, unit, more is better, figure lines by level (or [])]
	var specs: Array = []
	if not outputs.is_empty():
		# Every output grows by the level's one factor, so the first output's figures set the bar and the change;
		# each output's own figures print in the columns, a line each.
		var lines_by_level: Array = []
		for l in levels.size():
			var lines: PackedStringArray = []
			for i in outputs.size():
				var q := float((per_level.call("outputs", i) as Array)[l])
				lines.append(_num(q, 0) + (" MW" if str(outputs[i].get("good_id", "")) == "power" else ""))
			lines_by_level.append("\n".join(lines))
		specs.append(["Outputs", cluster, per_level.call("outputs", 0), 0, "", true, lines_by_level])
	var inputs: Array = now.get("inputs", [])
	if not inputs.is_empty():
		var totals: Array = []
		for l in levels.size():
			var sum := 0.0
			for i in inputs.size():
				sum += float((per_level.call("inputs", i) as Array)[l])
			totals.append(sum)
		var tip: PackedStringArray = ["Goods used a turn"]
		for i in inputs.size():
			var vals: Array = per_level.call("inputs", i)
			tip.append("%s: %s → %s" % [Catalog.get_display_name(str(inputs[i].get("good_id", ""))), _num(float(vals[from_level - 1]), 0), _num(float(vals[target - 1]), 0)])
		specs.append(["Inputs", _tipped(Parts.raised("econ_icon_inputs", METRIC_ICON_PX), "\n".join(tip)), totals, 0, "", false, []])
	if levels.any(func(st: Dictionary) -> bool: return float(st.get("energy", 0.0)) > 0.0):
		specs.append(["Power", _tipped(BoltIcon.new(METRIC_ICON_PX), "Power drawn, MW"),
			levels.map(func(st: Dictionary) -> float: return float(st.get("energy", 0.0))), 0, " MW", false, []])
	specs.append(["Labour", _tipped(Parts.raised("econ_icon_labour", METRIC_ICON_PX), "Labour a turn"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("labour", 0.0))), 2, "£", false, []])
	specs.append(["Upkeep", _tipped(Parts.raised("econ_icon_upkeep", METRIC_ICON_PX), "Upkeep a turn"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("maintenance", 0.0))), 2, "£", false, []])
	specs.append(["Land", _tipped(LandIcon.new(METRIC_ICON_PX), "Land the building takes"),
		levels.map(func(st: Dictionary) -> float: return float(st.get("size", 0.0))), 0, "", false, []])
	# One scale for every bar: the most any row reaches at any level, against its figure now.
	var reach := 1.0
	for spec: Array in specs:
		var cur := float(spec[2][from_level - 1])
		if cur > 0.0:
			for v in spec[2]:
				reach = maxf(reach, float(v) / cur)
	for spec: Array in specs:
		vb.add_child(_track_row(str(spec[0]), spec[1], spec[2], from_level, target, int(spec[3]), str(spec[4]), bool(spec[5]), reach, spec[6]))
		# A cut in the plastic between what the building makes and what it takes.
		if str(spec[0]) == "Outputs" and specs.size() > 1:
			vb.add_child(Cut.new())



## `c` with a hover naming it; it passes the mouse on.
func _tipped(c: Control, tip: String) -> Control:
	c.tooltip_text = tip
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	return c


## What the building makes, its goods in their wells: one or two at a good's full size side by side, three at
## OUTPUT_SMALL two over one. Power made is the bolt.
func _output_cluster(outputs: Array) -> Control:
	var px := Metrics.GOOD_ICON if outputs.size() <= 2 else OUTPUT_SMALL
	var grid := GridContainer.new()
	grid.name = "OutputCluster"
	grid.columns = 2 if outputs.size() >= 2 else 1
	grid.add_theme_constant_override("h_separation", 2 * ceili(Parts.WELL_REACH))
	grid.add_theme_constant_override("v_separation", 2 * ceili(Parts.WELL_REACH))
	for o: Dictionary in outputs:
		var gid := str(o.get("good_id", ""))
		var icon: Control = _tipped(BoltIcon.new(px), "Power made, MW") if gid == "power" \
			else Parts.good_in_well(gid, -1, "%s made a turn" % Catalog.get_display_name(gid), true, px)
		var cell := CenterContainer.new()
		cell.custom_minimum_size = Vector2(px, px) + Vector2.ONE * 2.0 * ceilf(Parts.WELL_REACH)
		cell.add_child(icon)
		grid.add_child(cell)
	return grid


## The rows' icon column: as wide as the outputs' cluster, so every row's figures line up under the headings.
var _icon_col := 0.0


## The table's captions over its columns.
func _table_head(from_level: int, target: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Parts.spacer(_icon_col, 0))
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
		more_is_better: bool, reach: float, lines: Array = []) -> HBoxContainer:
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
	row.custom_minimum_size.y = METRIC_ROW_H
	row.add_theme_constant_override("separation", 12)
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(_icon_col, METRIC_ROW_H)
	box.add_child(icon)
	row.add_child(box)
	var money := unit == "£"
	for pair: Array in [["Now", cur, DS.PALETTE["TEXT"], from_level], ["Next", nxt, tone, target]]:
		var text := ("£" if money else "") + _num(float(pair[1]), decimals) + ("" if money else unit)
		if not lines.is_empty():
			text = str(lines[int(pair[3]) - 1])
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


## A tower crane on the materials plate's edges, in steel lattice: the mast down the right edge from a yellow
## machinery box at its foot, the jib along the right half of the top edge (its top chord stopping short so
## its tip slants down to the foot chord), and the operator's yellow cab up at the top, where the jib meets
## the mast. Both girders are braced with a cross in every bay.
class CraneRig extends Control:
	const MAST_W := 30.0
	const JIB_H := 26.0
	const CHORD := 6.0
	const JIB_FROM := 0.44
	const CAB := Vector2(40, 34)
	const BASE := Vector2(64, 30)
	const STEEL := Color("#343940")
	const LIT := Color("#9aa2ab")
	const SHADE := Color("#111417")
	const BRACE := Color("#2b2f35")
	const RIVET := Color("#c9ced6")
	const YELLOW := Color("#f0b429")
	const YELLOW_LIT := Color("#ffd666")
	const YELLOW_DARK := Color("#b9820f")
	const INK := Color("#2a1e04")
	const GLASS := Color("#1b2a36")

	func _init() -> void:
		name = "CraneRig"
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	func _draw() -> void:
		var mx := size.x - MAST_W
		_girder(Rect2(mx, 0.0, MAST_W, size.y - BASE.y), false)
		# The jib: the foot chord runs out to the tip, the top chord stops a bay short, and the end slants down
		# from the top chord's end to the tip.
		var tip := size.x * JIB_FROM
		var shoulder := tip + JIB_H
		_girder(Rect2(shoulder, 0.0, mx - shoulder, JIB_H), true)
		_bar(Vector2(tip, JIB_H - CHORD * 0.5), Vector2(shoulder, JIB_H - CHORD * 0.5), CHORD)
		_bar(Vector2(shoulder, CHORD * 0.5), Vector2(tip, JIB_H - CHORD * 0.5), CHORD)
		_rivet(Vector2(tip + 3.0, JIB_H - CHORD * 0.5))
		# The cab up top against the mast, over the jib's root; the machinery at the mast's foot.
		_box(Rect2(Vector2(mx - CAB.x, 0.0), CAB), true)
		_box(Rect2(size - BASE, BASE), false)

	## A lattice girder in `r`: a chord along each long side and a cross (two diagonals) in every bay.
	func _girder(r: Rect2, across: bool) -> void:
		var depth := r.size.y if across else r.size.x
		var length := r.size.x if across else r.size.y
		var bays := maxi(1, roundi(length / depth))
		var step := length / bays
		var at := func(t: float, side: float) -> Vector2:
			return Vector2(r.position.x + t, r.position.y + side) if across else Vector2(r.position.x + side, r.position.y + t)
		var near := CHORD * 0.5
		var far := depth - CHORD * 0.5
		for i in bays:
			var t0 := i * step
			var t1 := (i + 1) * step
			_line(at.call(t0, near), at.call(t1, far), 2.5)
			_line(at.call(t0, far), at.call(t1, near), 2.5)
		_bar(at.call(0.0, near), at.call(length, near), CHORD)
		_bar(at.call(0.0, far), at.call(length, far), CHORD)
		for i in bays + 1:
			_rivet(at.call(i * step, near))
			_rivet(at.call(i * step, far))

	## A chord: a steel bar `w` thick from `a` to `b`, lit along its upper edge and shaded along its lower.
	func _bar(a: Vector2, b: Vector2, w: float) -> void:
		draw_line(a, b, STEEL, w)
		var n := (b - a).orthogonal().normalized() * (w * 0.5 - 0.5)
		if n.y > 0.0:
			n = -n
		draw_line(a + n, b + n, LIT, 1.0)
		draw_line(a - n, b - n, SHADE, 1.0)

	func _line(a: Vector2, b: Vector2, w: float) -> void:
		draw_line(a, b, BRACE, w, true)
		draw_line(a + Vector2(-0.5, -0.5), b + Vector2(-0.5, -0.5), Color(LIT, 0.3), 1.0, true)

	func _rivet(p: Vector2) -> void:
		draw_circle(p + Vector2(0.5, 0.5), 1.8, SHADE)
		draw_circle(p, 1.6, RIVET)

	## A painted steel box in construction yellow: the cab (with its window) or the machinery at the foot
	## (with its vents and a band of hazard stripes).
	func _box(r: Rect2, cab: bool) -> void:
		draw_rect(r.grow(1.0), INK)
		draw_rect(r, YELLOW)
		draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), YELLOW_LIT)
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - 4.0), Vector2(r.size.x, 4.0)), YELLOW_DARK)
		if cab:
			var win := Rect2(r.position + Vector2(5.0, 7.0), Vector2(r.size.x - 12.0, r.size.y * 0.45))
			draw_rect(win, GLASS)
			draw_line(win.position + Vector2(3.0, win.size.y - 2.0), win.position + Vector2(win.size.x * 0.5, 2.0), Color(1, 1, 1, 0.25), 2.0)
			draw_rect(win, INK, false, 1.0)
		else:
			var band := Rect2(r.position + Vector2(0.0, 3.0), Vector2(r.size.x, 7.0))
			var x := band.position.x - band.size.y
			while x < band.end.x:
				var stripe := PackedVector2Array([Vector2(x, band.end.y), Vector2(x + 5.0, band.end.y),
					Vector2(x + 5.0 + band.size.y, band.position.y), Vector2(x + band.size.y, band.position.y)])
				for i in stripe.size():
					stripe[i].x = clampf(stripe[i].x, band.position.x, band.end.x)
				draw_colored_polygon(stripe, INK)
				x += 10.0
			for i in 3:
				var vy := r.position.y + 14.0 + i * 4.0
				draw_line(Vector2(r.position.x + 8.0, vy), Vector2(r.end.x - 8.0, vy), YELLOW_DARK, 2.0)


## The source's price screen: its hover is the cost's breakdown on a steel plate.
class PriceBox extends HBoxContainer:
	var breakdown: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/ledger_v3/upgrade_dialog_ds2.gd").breakdown_plate(breakdown) if not breakdown.is_empty() else null


## Holds a hover plate in the tooltip's window, the window's own panel cleared so only the plate is drawn.
class TipHost extends MarginContainer:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(side, 8)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PARENTED:
			var win := get_parent() as Window
			if win != null:
				win.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## A cut across the plastic: a dark groove with a lit lip under it.
class Cut extends Control:
	func _init() -> void:
		name = "Cut"
		custom_minimum_size = Vector2(0, 6)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := roundf(size.y * 0.5)
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.75), 2.0)
		draw_line(Vector2(0, y + 1.5), Vector2(size.x, y + 1.5), Color(1, 1, 1, 0.10), 1.0)


## A total's rule: a cream line across the case with a darker hairline under it, over the row it totals.
class TotalRule extends Control:
	func _init() -> void:
		name = "TotalRule"
		custom_minimum_size = Vector2(0, 8)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var y := roundf(size.y * 0.5)
		draw_line(Vector2(0, y - 1.0), Vector2(size.x, y - 1.0), Color("#f3e3bd"), 2.0)
		draw_line(Vector2(0, y + 1.5), Vector2(size.x, y + 1.5), Color(0, 0, 0, 0.6), 1.0)
