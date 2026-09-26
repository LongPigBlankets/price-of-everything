extends RefCounted
## Tile view v3: the Goods tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## Framed sections on the body's navy steel, in the order a player asks of a site: what it earns, what it
## makes, and what the ground holds.
##   economics       each of your buildings here on a key that opens it, beside its net value added, best
##                   first; ruled off under them the tile's total (the Goods key's figure) on a key that
##                   folds open Building Detail's value bars, what the goods fetch against what the
##                   buildings spend (closed at first); then what the tile sold last turn, the one figure
##                   here that is money banked (while it sold something or your buildings here make goods).
##   the output bay  a dark plate, its rolling door up in its housing under the heading: each good your
##                   buildings make here this turn in a well, its units on a drum counter and their value
##                   at market on an LED screen, by value. With nothing made the door is down to its foot,
##                   a sign on it saying why. With none of your buildings here the bay gives way to a line.
##   deposits        each deposit the survey shows, what works it, its units left, and its key; or why
##                   there are none to show.
## One grid runs down the tab: an icon column (a good in its well, anything else a raised mark centred in
## the same column), the row's words from one x, then two figure columns at the right. The units column
## holds drum counters, each with the drums its own figure needs, set at the column's right edge. The money
## column is as wide as the £ screens (every screen has the same cells) on every tile, and a deposit's key
## fills it. Every key in the tab stands at the cabinet keys' height. Captions for the columns sit on each
## section's heading line.
## Every figure is the engine's: BuildingEconomics.per_turn (Building Detail's), added up as
## TileViewData.production_summary adds it for the Goods key, TileViewData.sales_summary,
## TileViewData.survey_gated_deposits and the construction projects' own turns.

const Parts := preload("res://scripts/tvp_v3/goods_parts.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Counter := preload("res://scripts/bdp_v3_counter.gd")
const ValueBar := preload("res://scripts/bdp_v3_value_bar.gd")
const CabinetKey := preload("res://scripts/tile_cabinet_key.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const BuildingEconomics := preload("res://scripts/building_economics.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

## The room between sections, between a row's columns, and between rows (DS.SP MD, the wells' frames
## clear of each other). Rows of keys stand closer: their bezels keep the room between them.
const SECTION_GAP := 8
const COL_GAP := 12
const ROW_GAP := 12
const KEY_ROW_GAP := 10
## Every row's icon column: a good's well is this size, and any other mark (a building's emblem, the sales
## lorry, the survey pick) is raised at MARK_PX, sized by its drawn art, and centred in it.
const ICON_COL := 64
const MARK_PX := 44.0
## The fewest drums on a counter (Building Detail's workers counter), and the fewest cells on a £ screen
## (Building Detail's economics screens, five figures with their pence).
const MIN_DRUMS := 3
const MIN_MONEY_CELLS := 5
## How far the bay's door reaches past its row to the frame's rim, at its sides and (shut) its foot.
const DOOR_REACH := Section.PADDING
## The words on the keys a deposit row can carry.
const OPEN := "Open"
const BUILD := "Build"
const BUILD_ANOTHER := "Build another"
## Where the panel keeps whether the value bars are folded open, across refreshes and tiles.
const BARS_OPEN_META := "tvp_prod_bars_open"
## The raised marks: the sales lorry, the survey pick, and the outputs gear from Building Detail's plate.
const FREIGHT_ICON := "res://assets/ui/bdp_v3/diag_icon_freight.png"
const SURVEY_ICON := "res://assets/ui/bdp_v3/diag_icon_deposit.png"
const OUTPUT_ICON := "res://assets/ui/bdp_v3/block_icon_output.png"


static func build(panel: Control, pane: VBoxContainer) -> void:
	pane.add_theme_constant_override("separation", SECTION_GAP)
	var tile := str(panel.get("_current_tile_id"))
	var tile_data: Dictionary = panel.get("_current_tile_data")
	var yours := your_economics(tile)
	var prod := summary(yours)
	var sales := TileViewData.sales_summary(tile)
	# What the tile sold last turn shows while it sold something, or while your buildings here make goods
	# (then nothing sold says the goods went elsewhere). A tile making only power sells none at market.
	var sold := int(sales.units) > 0 or float(sales.revenue) > 0.0
	var show_sales := sold or not (prod.rows as Array).is_empty()
	var here := _yours_here(tile)
	var gated := TileViewData.survey_gated_deposits(tile, tile_data)
	var deposits: Array = []
	for d: Dictionary in gated.rows:
		deposits.append(_deposit_view(tile, d))
	var grid := columns(yours, prod, sales, show_sales, deposits)
	if not yours.is_empty() or sold:
		pane.add_child(_economics(panel, tile, prod, yours, sales if show_sales else {}, grid))
	if here:
		pane.add_child(_output_bay(panel, tile, prod, yours, grid))
	else:
		pane.add_child(_none_here())
	pane.add_child(_deposits(panel, tile, gated, deposits, grid))


## Your buildings on the tile whose economics count towards its net value added, in the tile's order, each
## with its reading (BuildingEconomics.per_turn, Building Detail's), chosen as TileViewData.production_summary
## chooses them: yours, with a recipe, and shown by Building Detail (a battery is not).
static func your_economics(tile: String) -> Array:
	var out: Array = []
	for building: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if not BuildingState.is_player_owned(building):
			continue
		if Catalog.get_recipe(building.get("recipe_id", "")).is_empty():
			continue
		var econ: Dictionary = BuildingEconomics.per_turn(building)
		if bool(econ.get("shown", false)):
			out.append({"building": building, "econ": econ})
	return out


## The tile's net value added and its goods by value, from `yours` exactly as
## TileViewData.production_summary adds them up (so the total is the Goods key's figure): the readings
## summed in the tile's order, each good's units rounded per building, power left out of the goods. It
## reads each building once, where calling that helper as well would read every building twice.
## {net_value, rows: [{good_id, display_name, qty, value}]}.
static func summary(yours: Array) -> Dictionary:
	var net := 0.0
	var by_good := {}
	for y: Dictionary in yours:
		net += float(y.econ.get("net_value_added", 0.0))
		for o: Dictionary in y.econ.get("outputs", []):
			var gid := str(o.get("good_id", ""))
			var qty := int(round(float(o.get("qty", 0))))
			if gid == "" or gid == "power" or qty <= 0:
				continue
			var rec: Dictionary = by_good.get(gid, {"good_id": gid, "display_name": Catalog.get_display_name(gid),
				"qty": 0, "value": 0.0})
			rec.qty = int(rec.qty) + qty
			rec.value = float(rec.value) + float(o.get("value", 0.0))
			by_good[gid] = rec
	var rows: Array = by_good.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.value) > float(b.value))
	return {"net_value": net, "rows": rows}


## The drums a count shows on: as many as its own figure needs, at least MIN_DRUMS.
static func drums(value: float) -> int:
	return Counter.drums_for(value, 0, MIN_DRUMS)


## The tab's figure columns, one width in every section so they run straight down it:
##   cells, money_w    every £ screen's cells (as many as the largest figure needs, at least
##                     MIN_MONEY_CELLS) and the money column's width, the screens' own, on every tile;
##   key_w             a deposit key's width: the money column's where the tab shows £ screens, so the keys
##                     and the screens share both edges, or the widest key's own where it shows none;
##   units_w           the units column: its widest counter (or a deposit's size in words);
##   bay_units, deposit_units   the widest figure in the bay's and in Deposits' units column, for centring
##                     each heading's caption over its own figures at the column's right edge.
static func columns(yours: Array, prod: Dictionary, sales: Dictionary, show_sales: bool, deposits: Array) -> Dictionary:
	var cells := maxi(MIN_MONEY_CELLS, Parts.money_cells(float(prod.net_value)))
	for y: Dictionary in yours:
		cells = maxi(cells, Parts.money_cells(float(y.econ.get("net_value_added", 0.0))))
	for r: Dictionary in prod.rows:
		cells = maxi(cells, Parts.money_cells(float(r.value)))
	if show_sales:
		cells = maxi(cells, Parts.money_cells(float(sales.revenue)))
	var bay_units := 0.0
	for r: Dictionary in prod.rows:
		bay_units = maxf(bay_units, Parts.counter_width(drums(float(r.qty))))
	var deposit_units := 0.0
	var key_natural := 0.0
	for v: Dictionary in deposits:
		key_natural = maxf(key_natural, Parts.link_key_width(v.key_text, Parts.key_scale()) if v.link \
			else Parts.cabinet_key_width(v.key_text))
		deposit_units = maxf(deposit_units, Parts.counter_width(drums(float(v.size_qty))) if v.on_drums \
			else Parts.body_width(v.size_text))
	var money_w := Parts.money_width(cells)
	var shows_money := not yours.is_empty() or show_sales
	return {"cells": cells, "money_w": money_w, "key_w": money_w if shows_money else ceilf(key_natural),
		"units_w": ceilf(maxf(bay_units, deposit_units)), "bay_units": bay_units, "deposit_units": deposit_units}


## True when you have a building, or one going up, on the tile.
static func _yours_here(tile: String) -> bool:
	for building: Dictionary in BuildingState.get_buildings_on_tile(tile):
		if BuildingState.is_player_owned(building):
			return true
	return not Construction.projects_on_tile(tile).is_empty()


## A framed section on the tab's grid: its heading with a caption over each of its figure columns
## (`captions`, [[caption, column width, figure width], ...] left to right, as Parts.heading_row takes).
static func _section(section_name: String, heading: String, captions := [], style := "steel",
		row_gap := ROW_GAP) -> MarginContainer:
	var sec: MarginContainer = Section.new()
	sec.name = section_name
	sec.set("style", style)
	var vb: VBoxContainer = sec.get("content")
	vb.add_theme_constant_override("separation", row_gap)
	vb.add_child(Parts.heading_row(heading, captions, COL_GAP))
	return sec


## A row in the tab's grammar: `icon` in the icon column, then the row's own columns.
static func _row(row_name: String, icon: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", COL_GAP)
	row.add_child(icon)
	return row


## A row's words: its title (semibold) and, when there is one, a line under it.
static func _words(title: String, line := "") -> VBoxContainer:
	var info := VBoxContainer.new()
	info.name = "Words"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 2)
	info.add_child(Parts.body(title, true))
	if line != "":
		info.add_child(Parts.body(line))
	return info


## A count on its own drums, at the units column's right edge.
static func _units(panel: Control, key: String, value: float, grid: Dictionary) -> Control:
	return Parts.at_end(Parts.counter(panel, key, value, drums(value)), float(grid.units_w), "Units")


## A £ figure on the tab's screens: every one the money column's width.
static func _money(figure: float, grid: Dictionary) -> Control:
	return Parts.money(figure, Parts.result_colour(figure), int(grid.cells))


# --- Economics ---------------------------------------------------------------------------------------

## Your buildings' economics, then what the tile sold last turn (`sales`, or {} to leave it out).
static func _economics(panel: Control, tile: String, prod: Dictionary, yours: Array, sales: Dictionary,
		grid: Dictionary) -> Control:
	var sec := _section("Economics", "Economics", [["Per turn", grid.money_w]], "steel", KEY_ROW_GAP)
	var vb: VBoxContainer = sec.get("content")
	if not yours.is_empty():
		var best := yours.duplicate()
		best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.econ.net_value_added) > float(b.econ.net_value_added))
		for y: Dictionary in best:
			vb.add_child(_building_row(panel, tile, y.building, float(y.econ.net_value_added), grid))
		_add_total(panel, vb, float(prod.net_value), yours, grid)
	if not sales.is_empty():
		var row := _sales_row(sales, grid)
		if not yours.is_empty():
			Parts.groove_over(row, KEY_ROW_GAP)
		vb.add_child(row)
	return sec


## One of your buildings: its emblem, its name on a key that opens it, its net value added.
static func _building_row(panel: Control, tile: String, building: Dictionary, nva: float, grid: Dictionary) -> HBoxContainer:
	var iid := str(building.get("instance_id", ""))
	var bid := str(building.get("building_id", ""))
	var row := _row("Building_%s" % iid, Parts.mark(Parts.EMBLEM % bid, MARK_PX, ICON_COL))
	var title := BuildingNaming.label_for_tile(tile, iid, bid, str(building.get("recipe_id", "")))
	var key := Parts.link_button(title, Parts.key_scale(), "OpenBuilding_%s" % iid, func() -> void:
		var live := BuildingState.get_building(iid)
		if not live.is_empty():
			panel.building_clicked.emit(live))
	key.tooltip_text = "Open %s" % title
	row.add_child(key)
	row.add_child(_money(nva, grid))
	return row


## The tile's net value added, ruled off under its buildings as a sum is, on a key that folds open what
## makes it (Building Detail's Value added in production): the value bars, each good's revenue against
## the inputs, labour, upkeep and transport, on one scale. Closed at first. Its state is kept on the
## panel, so once opened the bars stay open across refreshes and tiles.
static func _add_total(panel: Control, vb: VBoxContainer, total: float, yours: Array, grid: Dictionary) -> void:
	var open := bool(panel.get_meta(BARS_OPEN_META, false))
	var bars := VBoxContainer.new()
	bars.name = "ValueBars"
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _row("NetValueAdded", Parts.spacer(ICON_COL))
	var key := Parts.fold_button("Net value added", Parts.key_scale(), "NetValueAddedKey", open, func(now: bool) -> void:
		panel.set_meta(BARS_OPEN_META, now)
		_show_bars(bars, yours, now))
	key.tooltip_text = "What your buildings here add a turn, before tax. Press for what the goods fetch against what the buildings spend."
	row.add_child(key)
	row.add_child(_money(total, grid))
	Parts.groove_over(row, KEY_ROW_GAP)
	vb.add_child(row)
	vb.add_child(bars)
	_show_bars(bars, yours, open)


## The value bars under the total while its key is open, made the first time they are shown.
static func _show_bars(bars: VBoxContainer, yours: Array, open: bool) -> void:
	if open and bars.get_child_count() == 0:
		var bar: Control = ValueBar.new()
		bar.call("set_values", _tile_economics(yours))
		bars.add_child(bar)
	bars.visible = open


## What the tile sold last turn (the only per-tile sales figure the game keeps): how many units, and on
## its screen what they fetched.
static func _sales_row(sales: Dictionary, grid: Dictionary) -> HBoxContainer:
	var row := _row("SoldLastTurn", Parts.mark(FREIGHT_ICON, MARK_PX, ICON_COL))
	row.tooltip_text = "Goods from this tile sold at market last turn, and what they fetched."
	row.add_child(_words("Sold last turn", sold_line(int(sales.units))))
	row.add_child(_money(float(sales.revenue), grid))
	return row


## How many units the tile sold last turn, in words.
static func sold_line(units: int) -> String:
	if units <= 0:
		return "Nothing sold"
	return "1 unit" if units == 1 else "%d units" % units


## Your buildings' economics summed as one reading for the value bars: each good's revenue (power too) and
## the four costs, from the same per_turn readings the rows show.
static func _tile_economics(yours: Array) -> Dictionary:
	var by_good := {}
	var order: Array = []
	var sum := {"input_value": 0.0, "labour": 0.0, "upkeep": 0.0, "transport": 0.0}
	var sold := true
	for y: Dictionary in yours:
		var econ: Dictionary = y.econ
		for o: Dictionary in econ.get("outputs", []):
			var gid := str(o.get("good_id", ""))
			if not by_good.has(gid):
				by_good[gid] = 0.0
				order.append(gid)
			by_good[gid] = float(by_good[gid]) + float(o.get("value", 0.0))
		for k: String in sum:
			sum[k] = float(sum[k]) + float(econ.get(k, 0.0))
		sold = sold and bool(econ.get("sold", true))
	var outputs: Array = []
	for gid: String in order:
		outputs.append({"good_id": gid, "value": by_good[gid]})
	outputs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.value) > float(b.value))
	var out := sum.duplicate()
	out["outputs"] = outputs
	out["sold"] = sold
	return out


# --- The output bay --------------------------------------------------------------------------------

static func _output_bay(panel: Control, tile: String, prod: Dictionary, yours: Array, grid: Dictionary) -> Control:
	var rows: Array = prod.rows
	var captions := [["Units", grid.units_w, grid.bay_units], ["Value", grid.money_w]] if not rows.is_empty() else []
	var bay := _section("OutputBay", "Outputs this turn", captions, "dark")
	var vb: VBoxContainer = bay.get("content")
	if rows.is_empty():
		# Nothing made: the bay's rolling door is down from the heading to the frame's rim, and a sign on
		# it says why.
		vb.add_child(Parts.shut_door(nothing_made_note(tile, yours), DOOR_REACH))
		return bay
	# Goods made: the same door rolled up into its housing over them.
	vb.add_child(Parts.rolled_door(DOOR_REACH))
	for r: Dictionary in rows:
		vb.add_child(_bay_row(panel, r, grid))
	return bay


## Why the bay is empty while you have something on the tile: buildings that make no goods this turn (a
## power plant, one stalled or starting), or only buildings still going up.
static func nothing_made_note(tile: String, yours: Array) -> String:
	if yours.is_empty():
		var going_up := Construction.projects_on_tile(tile).size()
		if going_up == 1:
			return "Nothing made yet. Your building here is still going up."
		if going_up > 1:
			return "Nothing made yet. Your buildings here are still going up."
	return "Your buildings here make no goods this turn."


## One good in the bay: its icon in a well, its name and market price, this turn's units on the drums and
## their value at market on the screen.
static func _bay_row(panel: Control, r: Dictionary, grid: Dictionary) -> HBoxContainer:
	var gid := str(r.good_id)
	var qty := int(r.qty)
	var value := float(r.value)
	var row := _row("Output_%s" % gid, Parts.good_in_well(gid, ICON_COL, PackedStringArray([
		"Made this turn: %d" % qty, "Worth £%.2f at market" % value])))
	row.add_child(_words(str(r.display_name), "Market price £%.2f" % MarketState.get_price(gid)))
	row.add_child(_units(panel, "out:%s" % gid, float(qty), grid))
	row.add_child(_money(value, grid))
	return row


## With none of your buildings on the tile, one line in the bay's place: nothing of yours makes goods here.
static func _none_here() -> Control:
	var line := MarginContainer.new()
	line.name = "NoBuildingsHere"
	var inset := roundi(Section.RIM + Section.PADDING)
	line.add_theme_constant_override("margin_left", inset)
	line.add_theme_constant_override("margin_right", inset)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(_note("NothingMade", OUTPUT_ICON, "You have no buildings making goods here."))
	return line


# --- Deposits ----------------------------------------------------------------------------------------

static func _deposits(panel: Control, tile: String, gated: Dictionary, deposits: Array, grid: Dictionary) -> Control:
	var captions := [["Left", grid.units_w, grid.deposit_units], ["", grid.key_w]] if not deposits.is_empty() else []
	var sec := _section("Deposits", "Deposits", captions)
	var vb: VBoxContainer = sec.get("content")
	if str(gated.status) == "unsurveyed":
		vb.add_child(_note("SurveyNote", SURVEY_ICON, survey_note(tile)))
	elif deposits.is_empty():
		vb.add_child(_note("NoDeposits", SURVEY_ICON, "The survey found no deposits here."))
	for v: Dictionary in deposits:
		vb.add_child(_deposit_row(panel, tile, v, grid))
	return sec


## Why the tile shows no deposits yet, in the Survey key's own terms: a survey under way and its turns,
## or the key to press, or (the key disabled) that the tile is out of survey range.
static func survey_note(tile: String) -> String:
	if MatchState.is_survey_in_progress(tile):
		var turns := MatchState.survey_turns_left(tile)
		return "Survey under way, %d %s left." % [turns, "turn" if turns == 1 else "turns"]
	if MatchState.is_tile_surveyable(tile):
		return "Survey the tile to find its deposits."
	return "This tile is out of survey range. Survey more tiles to extend your range."


## A line saying why there is nothing to show, beside its raised mark in the icon column like every row:
## the outputs gear for goods, the survey pick in Deposits.
static func _note(note_name: String, icon: String, text: String) -> HBoxContainer:
	var note := _row(note_name, Parts.mark(icon, MARK_PX, ICON_COL))
	var t := Parts.body(text, false, Parts.BODY_PX, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_child(t)
	return note


## What the survey says of a deposit's size, in words: water and a deposit the engine tracks no amount for
## never run out (MatchState.has_infinite_deposit), a partial survey leaves the size unknown.
static func deposit_size_text(tile: String, d: Dictionary) -> String:
	var size_qty := int(d.get("size_qty", -1))
	if bool(d.get("is_water", false)):
		return "Never runs out"
	if size_qty >= 0:
		return "%d units left" % size_qty
	if size_qty == -1 and MatchState.has_infinite_deposit(tile, str(d.get("deposit_token", ""))):
		return "Never runs out"
	return "Size unknown"


## The project going up on the tile that would work this deposit, or {}: one of the deposit's build
## options (`opts`, TileViewData.deposit_build_options, read here when not given), matched as the panel's
## `_deposit_under_construction` matches them.
static func deposit_project(tile: String, token: String, opts: Variant = null) -> Dictionary:
	var pairs := {}
	for o: Dictionary in (opts if opts is Array else TileViewData.deposit_build_options(token)):
		pairs["%s|%s" % [str(o.building_id), str(o.recipe_id)]] = true
	if pairs.is_empty():
		return {}
	for project: Dictionary in Construction.projects_on_tile(tile):
		if pairs.has("%s|%s" % [str(project.get("building_id", "")), str(project.get("recipe_id", ""))]):
			return project
	return {}


## What works a deposit, the line that explains its key: yours or another company's building (Open),
## one going up and its turns (Build another), or nothing yet (Build).
static func deposit_state(d: Dictionary, project: Dictionary) -> String:
	if bool(d.get("has_building", false)):
		var worker := BuildingState.get_building(str(d.get("instance_id", "")))
		return "Worked by you" if not worker.is_empty() and BuildingState.is_player_owned(worker) \
			else "Worked by another company"
	if project.is_empty():
		return "Not worked yet"
	if str(project.get("status", "")) == Construction.STATUS_UNDER_CONSTRUCTION:
		var turns := int(project.get("turns_remaining", 0))
		return "One going up, %d %s left" % [turns, "turn" if turns == 1 else "turns"]
	return "One waiting for materials"


## A deposit read once for its row and for the tab's columns: the survey's row `d`, its size in words and
## whether it goes on the drums, what works it, and its key (a link that opens the building working it, or
## the cabinet's Build).
static func _deposit_view(tile: String, d: Dictionary) -> Dictionary:
	var token := str(d.deposit_token)
	var water := bool(d.get("is_water", false))
	var size_qty := int(d.get("size_qty", -1))
	var worked := bool(d.get("has_building", false))
	var opts: Array = [] if worked else TileViewData.deposit_build_options(token)
	var project := {} if worked else deposit_project(tile, token, opts)
	var key_text := OPEN if worked else (BUILD if project.is_empty() else BUILD_ANOTHER)
	return {"d": d, "token": token, "size_qty": size_qty, "size_text": deposit_size_text(tile, d),
		"on_drums": size_qty >= 0 and not water, "state": deposit_state(d, project), "link": worked,
		"key_text": key_text, "opts": opts}


## One deposit: the good in a well, its name and what works it, its units left on the drums (or the size in
## words), and its key, the money column's width: Build (Build another while one is going up) in the
## cabinet's own keys, or where a building already works it, a key that opens that building, as the
## Economics rows open theirs.
static func _deposit_row(panel: Control, tile: String, v: Dictionary, grid: Dictionary) -> HBoxContainer:
	var d: Dictionary = v.d
	var gid := str(d.good_id)
	var token := str(v.token)
	var water := bool(d.get("is_water", false))
	var name := str(d.display_name) if water else "%s deposit" % str(d.display_name)
	var icon: Control = Parts.good_in_well(gid, ICON_COL, PackedStringArray([str(v.size_text)])) \
		if Parts.has_icon(gid) else Parts.named_well(str(d.display_name), ICON_COL)
	var row := _row("Deposit_%s" % token, icon)
	row.add_child(_words(name, str(v.state)))
	if bool(v.on_drums):
		row.add_child(_units(panel, "deposit:%s" % token, float(v.size_qty), grid))
	else:
		var words := Parts.body(str(v.size_text))
		words.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		words.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(Parts.at_end(words, float(grid.units_w), "Units"))
	var key_w := float(grid.key_w)
	if bool(v.link):
		var iid := str(d.get("instance_id", ""))
		var link := Parts.link_button(OPEN, Parts.key_scale(), "GoToBuilding_%s" % token, func() -> void:
			panel.call("_go_to_building", iid))
		link.size_flags_horizontal = Control.SIZE_SHRINK_END
		link.custom_minimum_size.x = key_w
		var worker := BuildingState.get_building(iid)
		link.tooltip_text = "Open the building working this deposit" if worker.is_empty() else "Open %s" % \
			BuildingNaming.label_for_tile(tile, iid, str(worker.get("building_id", "")), str(worker.get("recipe_id", "")))
		row.add_child(link)
		return row
	var key: Control = CabinetKey.new()
	key.name = "DepositKey"
	key.size_flags_horizontal = Control.SIZE_SHRINK_END
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.custom_minimum_size.x = key_w
	key.set("text", str(v.key_text))
	var opts: Array = v.opts
	if opts.size() == 1:
		key.tooltip_text = "Build a %s here" % str(opts[0].building_name)
	elif opts.size() > 1:
		key.tooltip_text = "Choose a building to put here"
	else:
		key.tooltip_text = "Find a building that makes %s" % Catalog.get_display_name(gid)
	key.connect("pressed", func() -> void: panel.call("_on_deposit_build", token, gid, key))
	row.add_child(key)
	return row
