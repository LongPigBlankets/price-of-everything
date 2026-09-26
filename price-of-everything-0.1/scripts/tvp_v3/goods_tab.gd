extends RefCounted
## Tile view v3: the Goods tab's body (docs/tile-view-ds2-plan.md §4.3 and §9), built into `pane` on each
## refresh while UiPrefs.use_tvp_v3 is on. With the switch off the v2 panel builds the tab itself.
## `panel` is the tile view (scripts/tile_info_panel_v2.gd): its tile, its signals and its helpers.
##
## In the order a player asks of a site: what it earns, what it makes, and what the ground holds.
##   economics       with two or more of your buildings here, a framed section: each building's emblem, its
##                   kind over what it makes and its letter ("Industrial Goods Factory" over "Motor E"), its
##                   Open key, and its net value added on an LED screen, best first.
##   the result      a plate of dark metal of its own, apart from the buildings above it: the tile's net
##                   value added (the Goods key's figure) on its screen, and under it the key that folds
##                   open Building Detail's value bars, what the goods fetch against what the buildings
##                   spend (closed at first). With one building the plate names it as an Economics row does,
##                   under the title, and carries its Open key, so its figure shows once. Ruled off under
##                   it, what the tile sold last turn, the one figure here that is money banked (while it
##                   sold something or your buildings make goods).
##   the output bay  straight on the body's plate, no frame: each good your buildings make here this turn in a well, its
##                   quantity on the pill in the icon's corner as every good's is, and its value at market on
##                   an LED screen, by value. With nothing made, or none of your buildings here, a line
##                   says why.
##   deposits        straight on the body's plate, no frame: each deposit the survey shows in a well, its
##                   units left on the pill, what works it, its size, and its key; or why there are none to show.
## One grid runs down the tab: an icon column (a good in its well, anything else a raised mark centred in
## the same column), the row's words from one x, then the key column and the money column at the right.
## The money column is as wide as the £ screens (every screen has the same cells) and is there whenever the
## tab shows money. Every key in the tab, Open or Build, is one of the cabinet's cream keys, one width on
## every tile and in the one key column beside the money column. The one wide key with a chevron is the fold
## under the total, a step smaller. Captions for the columns sit on each section's heading line.
## Every figure is the engine's: BuildingEconomics.per_turn (Building Detail's), added up as
## TileViewData.production_summary adds it for the Goods key, TileViewData.sales_summary,
## TileViewData.survey_gated_deposits and the construction projects' own turns.

const Metrics := preload("res://scripts/ds2/metrics.gd")
const Parts := preload("res://scripts/tvp_v3/goods_parts.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const ValueBar := preload("res://scripts/tvp_v3/goods_value_bar.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const BuildingEconomics := preload("res://scripts/building_economics.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

## The room between sections, between a row's columns, and between rows (DS.SP MD, the wells' frames
## clear of each other). Rows of keys stand closer: their bezels keep the room between them.
const SECTION_GAP := 12
const COL_GAP := 12
const ROW_GAP := 12
const KEY_ROW_GAP := 10
## Every row's icon column: a good's well is this size, and any other mark (a building's emblem, the sales
## lorry, the survey pick) is raised at MARK_PX, sized by its drawn art, and centred in it.
const ICON_COL := Metrics.GOOD_ICON
const MARK_PX := 44.0
## The fewest cells on a £ screen (Building Detail's economics screens, five figures with their pence).
const MIN_MONEY_CELLS := 5
## The fold key's size against the cabinet keys': a step smaller, as Building Detail nests its keys, so
## its print stays under the total it explains.
const FOLD_KEY_SCALE := 0.8
## The words on the keys a row can carry: Open a building, or Build one (another, while one is going up, as
## the row's line says).
const OPEN := "Open"
const BUILD := "Build"
const FOLD_TITLE := "Revenue and costs"
## Where the panel keeps whether the value bars are folded open, across refreshes and tiles.
const BARS_OPEN_META := "tvp_prod_bars_open"
## The raised marks: the sales lorry, the survey pick, and the coins of Building Detail's value bars.
const FREIGHT_ICON := "res://assets/ui/bdp_v3/diag_icon_freight.png"
const SURVEY_ICON := "res://assets/ui/bdp_v3/diag_icon_deposit.png"
const VALUE_ICON := "res://assets/ui/bdp_v3/econ_icon_value.png"


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
	var gated := TileViewData.survey_gated_deposits(tile, tile_data)
	var deposits: Array = []
	for d: Dictionary in gated.rows:
		deposits.append(_deposit_view(tile, d))
	var grid := columns(yours, prod, sales, show_sales)
	if yours.size() > 1:
		pane.add_child(_economics(panel, tile, yours, grid))
	if not yours.is_empty() or sold:
		pane.add_child(_result(panel, tile, prod, yours, sales if show_sales else {}, grid))
	pane.add_child(_output_bay(tile, prod, yours, _yours_here(tile), grid))
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


## The tab's figure columns, one width in every section so they run straight down it:
##   cells, money_w    every £ screen's cells (as many as the largest figure needs, at least
##                     MIN_MONEY_CELLS) and the money column's width, the screens' own;
##   shows_money       whether the tab shows any £ screen, so its sections keep the money column;
##   key_w             the key column's width, beside the money column: every key the tab shows (Open in
##                     Economics, on the result plate and on a worked deposit, and a deposit's Build) is
##                     this wide on every tile, the wider print's with its room.
static func columns(yours: Array, prod: Dictionary, sales: Dictionary, show_sales: bool) -> Dictionary:
	var cells := maxi(MIN_MONEY_CELLS, Parts.money_cells(float(prod.net_value)))
	for y: Dictionary in yours:
		cells = maxi(cells, Parts.money_cells(float(y.econ.get("net_value_added", 0.0))))
	for r: Dictionary in prod.rows:
		cells = maxi(cells, Parts.money_cells(float(r.value)))
	if show_sales:
		cells = maxi(cells, Parts.money_cells(float(sales.revenue)))
	var shows_money := not yours.is_empty() or show_sales or not (prod.rows as Array).is_empty()
	return {"cells": cells, "money_w": Parts.money_width(cells), "shows_money": shows_money,
		"key_w": ceilf(maxf(Parts.cabinet_key_width(OPEN), Parts.cabinet_key_width(BUILD)))}


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


## A row's words: its title (semibold, or `title_px` for the total's emphasis) and the `lines` under it, each
## trimmed with an ellipsis rather than widening the body.
static func _words(title: String, lines := PackedStringArray(), title_px := Parts.BODY_PX) -> VBoxContainer:
	var info := VBoxContainer.new()
	info.name = "Words"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 2)
	var t := Parts.body(title, true, title_px)
	t.name = "Title"
	info.add_child(t)
	for line in lines:
		var l := Parts.body(line)
		l.name = "Line"
		info.add_child(l)
	return info


## A £ figure on the tab's screens: every one the money column's width.
static func _money(figure: float, grid: Dictionary) -> Control:
	return Parts.money(figure, Parts.result_colour(figure), int(grid.cells))


## One of your buildings here named in two parts, as every row names it: its kind, and what it makes with
## its letter ("Mine", "Coal A"). The game's name for it (BuildingNaming, "Mine - Coal - A") is split at
## its separators, which the tab never prints; a name without them ("Motor Factory E") is one line.
static func name_parts(tile: String, building: Dictionary) -> PackedStringArray:
	var full := BuildingNaming.label_for_tile(tile, str(building.get("instance_id", "")),
		str(building.get("building_id", "")), str(building.get("recipe_id", "")))
	var parts := full.split(" - ", false)
	if parts.size() <= 1:
		return PackedStringArray([full, ""])
	return PackedStringArray([parts[0], " ".join(parts.slice(1))])


## A building's two part name on one line, for a hover ("Industrial Goods Factory, Motor E").
static func _name_line(parts: PackedStringArray) -> String:
	return parts[0] if parts[1] == "" else "%s, %s" % [parts[0], parts[1]]


## The cabinet key that opens one of your buildings, the key column wide.
static func _open_key(panel: Control, tile: String, building: Dictionary, grid: Dictionary) -> Control:
	var iid := str(building.get("instance_id", ""))
	return Parts.cabinet_key(OPEN, "OpenBuilding_%s" % iid, float(grid.key_w),
		"Open %s" % _name_line(name_parts(tile, building)),
		func() -> void:
			var live := BuildingState.get_building(iid)
			if not live.is_empty():
				panel.building_clicked.emit(live))


# --- Economics ---------------------------------------------------------------------------------------

## Two or more of your buildings: each one's emblem, its name (its kind as the title, what it makes and its
## letter under it), its Open key and its net value added, best first. The total stands apart from them on
## its own plate (`_result`).
static func _economics(panel: Control, tile: String, yours: Array, grid: Dictionary) -> Control:
	var sec := _section("Economics", "Economics", [["", grid.key_w], ["Per turn", grid.money_w]], "steel",
		KEY_ROW_GAP)
	var vb: VBoxContainer = sec.get("content")
	var best := yours.duplicate()
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.econ.net_value_added) > float(b.econ.net_value_added))
	for y: Dictionary in best:
		var building: Dictionary = y.building
		var row := _row("Building_%s" % str(building.get("instance_id", "")),
			Parts.mark(Parts.EMBLEM % str(building.get("building_id", "")), MARK_PX, ICON_COL))
		var parts := name_parts(tile, building)
		row.add_child(_words(parts[0], PackedStringArray([parts[1]]) if parts[1] != "" else PackedStringArray()))
		row.add_child(_open_key(panel, tile, building, grid))
		row.add_child(_money(float(y.econ.net_value_added), grid))
		vb.add_child(row)
	return sec


## The result, on a plate of dark metal of its own: the tile's net value added on its screen, and the key
## that folds open what makes it (Building Detail's Value added in production: each good's revenue against
## the inputs, labour, upkeep and transport, on one scale), closed at first, its state kept on the panel so
## once opened the bars stay open across refreshes and tiles. With one building the plate names it under
## the title as an Economics row names one (its kind over what it makes and its letter) and carries its
## Open key. Ruled off under it, what the tile sold last turn (`sales`, or {} to leave it out).
static func _result(panel: Control, tile: String, prod: Dictionary, yours: Array, sales: Dictionary,
		grid: Dictionary) -> Control:
	var plate := Parts.slab("Result", KEY_ROW_GAP)
	var vb := Parts.slab_content(plate)
	if not yours.is_empty():
		var total := float(prod.net_value)
		var row: HBoxContainer
		if yours.size() == 1:
			var building: Dictionary = yours[0].building
			row = _row("NetValueAdded", Parts.mark(Parts.EMBLEM % str(building.get("building_id", "")), MARK_PX, ICON_COL))
			var parts := name_parts(tile, building)
			var lines := PackedStringArray([parts[0]])
			if parts[1] != "":
				lines.append(parts[1])
			row.add_child(_words("Net value added", lines, Parts.STRONG_PX))
			row.add_child(_open_key(panel, tile, building, grid))
			row.tooltip_text = "What this building adds/turn, before tax."
		else:
			row = _row("NetValueAdded", Parts.mark(VALUE_ICON, MARK_PX, ICON_COL))
			row.add_child(_words("Net value added", PackedStringArray(["Per turn, before tax"]), Parts.STRONG_PX))
			row.tooltip_text = "What your buildings here add/turn, before tax."
		row.add_child(_money(total, grid))
		vb.add_child(row)
		_add_fold(panel, vb, yours, grid)
	if not sales.is_empty():
		var sold_row := _sales_row(sales, grid)
		if not yours.is_empty():
			Parts.groove_over(sold_row, KEY_ROW_GAP)
		vb.add_child(sold_row)
	return plate


## The key under the total that folds its value bars open, from the words' x to the money column, and the
## bars under it while it is open.
static func _add_fold(panel: Control, vb: VBoxContainer, yours: Array, grid: Dictionary) -> void:
	var open := bool(panel.get_meta(BARS_OPEN_META, false))
	var bars := VBoxContainer.new()
	bars.name = "ValueBars"
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _row("Fold", Parts.spacer(ICON_COL))
	var key := Parts.fold_button(FOLD_TITLE, Parts.key_scale() * FOLD_KEY_SCALE, "RevenueAndCostsKey", open,
		func(now: bool) -> void:
			panel.set_meta(BARS_OPEN_META, now)
			_show_bars(bars, yours, now))
	key.tooltip_text = "What the goods fetch against what the buildings spend."
	row.add_child(key)
	row.add_child(Parts.spacer(float(grid.money_w)))
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
	row.add_child(_words("Sold last turn", PackedStringArray([sold_line(int(sales.units))])))
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

## The bay: what your buildings here make this turn, or its door down with a sign saying why nothing is in
## it (`here`: you have a building on the tile or one going up).
static func _output_bay(tile: String, prod: Dictionary, yours: Array, here: bool, grid: Dictionary) -> Control:
	var rows: Array = prod.rows
	var captions := [["Value", grid.money_w]] if not rows.is_empty() else []
	var bay := _section("OutputBay", "Outputs this turn", captions, "bare")
	var vb: VBoxContainer = bay.get("content")
	if rows.is_empty():
		# Nothing made: a line saying why, in the rows' words column.
		var empty := _row("NothingMade", Parts.spacer(ICON_COL))
		var t := Parts.body(nothing_made_note(tile, yours, here), false, Parts.BODY_PX, true)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_child(t)
		vb.add_child(empty)
		return bay
	# Goods made: the door is away and the goods stand in the bay under the heading.
	for r: Dictionary in rows:
		vb.add_child(_bay_row(r, grid))
	return bay


## Why the bay is empty: none of your buildings here, buildings that make no goods this turn (a power
## plant, one stalled or starting), or only buildings still going up.
static func nothing_made_note(tile: String, yours: Array, here := true) -> String:
	if not here:
		return "You have no buildings here."
	if yours.is_empty():
		var going_up := Construction.projects_on_tile(tile).size()
		if going_up == 1:
			return "Nothing made yet. Your building here is still going up."
		if going_up > 1:
			return "Nothing made yet. Your buildings here are still going up."
	return "Your buildings here make no goods this turn."


## One good in the bay: its icon in a well with this turn's quantity on its pill, its name and market
## price, and the quantity's value at market on the screen.
static func _bay_row(r: Dictionary, grid: Dictionary) -> HBoxContainer:
	var gid := str(r.good_id)
	var qty := int(r.qty)
	var value := float(r.value)
	var row := _row("Output_%s" % gid, Parts.good_in_well(gid, ICON_COL, PackedStringArray([
		"Made this turn: %d" % qty, "Worth £%.2f at market" % value]), Parts.pill_text(qty)))
	row.add_child(_words(str(r.display_name), PackedStringArray(["Market price £%.2f" % MarketState.get_price(gid)])))
	row.add_child(_money(value, grid))
	return row


# --- Deposits ----------------------------------------------------------------------------------------

static func _deposits(panel: Control, tile: String, gated: Dictionary, deposits: Array, grid: Dictionary) -> Control:
	var sec := _section("Deposits", "Deposits", [], "bare")
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


## A line saying why there is nothing to show, beside its raised mark in the icon column like every row.
static func _note(note_name: String, icon: String, text: String) -> HBoxContainer:
	var note := _row(note_name, Parts.mark(icon, MARK_PX, ICON_COL))
	var t := Parts.body(text, false, Parts.BODY_PX, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.add_child(t)
	return note


## What the survey says of a deposit's size, in words (the well's hover, and the row's words where the
## size has no count for the pill): water and a deposit the engine tracks no amount for never run out
## (MatchState.has_infinite_deposit), a partial survey leaves the size unknown.
static func deposit_size_text(tile: String, d: Dictionary) -> String:
	var size_qty := int(d.get("size_qty", -1))
	if bool(d.get("is_water", false)):
		return "Never runs out"
	if size_qty >= 0:
		return "%d units left" % size_qty
	if size_qty == -1 and MatchState.has_infinite_deposit(tile, str(d.get("deposit_token", ""))):
		return "Never runs out"
	return "Size unknown"


## A deposit row's size line: ∞ for one that never runs out, its units otherwise, or that the size is unknown.
static func deposit_size_line(size_text: String, size_qty: int) -> String:
	if size_text == "Never runs out":
		return "∞"
	if size_qty >= 0:
		return "%d units" % size_qty
	return size_text


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


## What works a deposit, the line that explains its key: your building or another company's (Open), one
## going up and its turns (Build, another), or nothing yet (Build).
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
## on the pill (its units left, "?" while a partial survey leaves them unknown, "" for a deposit that never
## runs out, which says so in words instead), what works it, and its key.
static func _deposit_view(tile: String, d: Dictionary) -> Dictionary:
	var token := str(d.deposit_token)
	var water := bool(d.get("is_water", false))
	var size_qty := int(d.get("size_qty", -1))
	var size_text := deposit_size_text(tile, d)
	var shown := ""
	if not water and size_qty >= 0:
		shown = Parts.pill_text(size_qty)
	elif size_text == "Size unknown":
		shown = "?"
	var worked := bool(d.get("has_building", false))
	var opts: Array = [] if worked else TileViewData.deposit_build_options(token)
	var project := {} if worked else deposit_project(tile, token, opts)
	return {"d": d, "token": token, "size_qty": size_qty, "size_text": size_text, "size_line": deposit_size_line(size_text, size_qty),
		"pill": shown,
		"state": deposit_state(d, project), "worked": worked, "going_up": not project.is_empty(), "opts": opts}


## One deposit: the good in a well with its units left on the pill, its name, what works it and its size
## (∞ for one that never runs out, its units otherwise), then its key in the key column: Open where a
## building already works it (as the Economics rows open theirs), or Build (another, while one is going
## up). Where the tab shows money the row keeps the money column, empty, so its key stands in line
## with the Open keys above.
static func _deposit_row(panel: Control, tile: String, v: Dictionary, grid: Dictionary) -> HBoxContainer:
	var d: Dictionary = v.d
	var gid := str(d.good_id)
	var token := str(v.token)
	var water := bool(d.get("is_water", false))
	var name := str(d.display_name) if water else "%s deposit" % str(d.display_name)
	var icon: Control = Parts.good_in_well(gid, ICON_COL, PackedStringArray([str(v.size_text)]), str(v.pill)) \
		if Parts.has_icon(gid) else Parts.named_well(str(d.display_name), ICON_COL, str(v.pill))
	var row := _row("Deposit_%s" % token, icon)
	row.add_child(_words(name, PackedStringArray([str(v.state), str(v.size_line)])))
	var key_w := float(grid.key_w)
	if bool(v.worked):
		var iid := str(d.get("instance_id", ""))
		var worker := BuildingState.get_building(iid)
		var tip := "Open the building working this deposit" if worker.is_empty() \
			else "Open %s" % _name_line(name_parts(tile, worker))
		row.add_child(Parts.cabinet_key(OPEN, "GoToBuilding_%s" % token, key_w, tip, func() -> void:
			panel.call("_go_to_building", iid)))
	else:
		var opts: Array = v.opts
		var build_tip := "Find a building that makes %s" % Catalog.get_display_name(gid)
		if opts.size() == 1:
			build_tip = ("Build another %s here" if bool(v.going_up) else "Build a %s here") % str(opts[0].building_name)
		elif opts.size() > 1:
			build_tip = "Choose a building to put here"
		var key := Parts.cabinet_key(BUILD, "DepositKey", key_w, build_tip, Callable())
		key.connect("pressed", func() -> void: panel.call("_on_deposit_build", token, gid, key))
		row.add_child(key)
	if bool(grid.shows_money):
		row.add_child(Parts.spacer(float(grid.money_w)))
	return row
